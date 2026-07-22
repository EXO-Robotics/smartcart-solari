import Foundation
import XCTest
@testable import SmartCart

final class WeeklyMealIntegrationTests: XCTestCase {
    func testSnapshotPreservesContentVersionAndProvenance() throws {
        let recipe = try weeklyRecipe("weekly.chicken-taco-rice-bowls")
        let snapshot = try factory.makeSnapshot(
            collectionID: "weekly.week-01",
            recipe: recipe,
            targetServings: 4
        )

        XCTAssertEqual(snapshot.source, .sample)
        XCTAssertEqual(snapshot.sourceDetail, "Weekly Meals · weekly.week-01 · weekly.chicken-taco-rice-bowls · version 1")
        XCTAssertTrue(snapshot.rawSourceText?.contains("Content version: 1") == true)
        XCTAssertTrue(snapshot.rawSourceText?.contains("Nutrition: Calories per serving: 500") == true)
        XCTAssertTrue(snapshot.rawSourceText?.contains("Recipe cost: Status: requiresVerification") == true)
        XCTAssertTrue(snapshot.rawSourceText?.contains("Instructions") == true)
        XCTAssertEqual(snapshot.ingredients.count, 12)
    }

    func testSnapshotIdentityIsIdempotentForSameVersion() throws {
        let recipe = try weeklyRecipe("weekly.protein-overnight-oats")
        let first = try factory.makeSnapshot(collectionID: "weekly.week-01", recipe: recipe, targetServings: 1)
        let second = try factory.makeSnapshot(collectionID: "weekly.week-01", recipe: recipe, targetServings: 2)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.ingredients.map(\.id), second.ingredients.map(\.id))
    }

    func testAContentVersionChangeCreatesNewFrozenIdentity() throws {
        let recipe = try weeklyRecipe("weekly.protein-overnight-oats")
        let nextVersion = CuratedRecipeRecord(
            id: recipe.id,
            contentVersion: 2,
            title: recipe.title,
            shortDescription: recipe.shortDescription,
            defaultServings: recipe.defaultServings,
            servingDescription: recipe.servingDescription,
            ingredients: recipe.ingredients,
            instructions: recipe.instructions,
            substitutions: recipe.substitutions,
            metadata: recipe.metadata
        )

        let first = try factory.makeSnapshot(collectionID: "weekly.week-01", recipe: recipe, targetServings: 1)
        let second = try factory.makeSnapshot(collectionID: "weekly.week-02", recipe: nextVersion, targetServings: 1)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testSelectedServingsScaleFrozenIngredientQuantities() throws {
        let recipe = try weeklyRecipe("weekly.chicken-taco-rice-bowls")
        let snapshot = try factory.makeSnapshot(collectionID: "weekly.week-01", recipe: recipe, targetServings: 8)
        let chicken = try XCTUnwrap(snapshot.ingredients.first { $0.name == "Boneless skinless chicken breast" })

        XCTAssertEqual(snapshot.servings, 8)
        XCTAssertEqual(chicken.quantity, 2.5, accuracy: 0.001)
    }

    func testOptionalIngredientIsExcludedUnlessExplicitlySelected() throws {
        let recipe = try weeklyRecipe("weekly.protein-overnight-oats")
        let baseline = try factory.makeSnapshot(collectionID: "weekly.week-01", recipe: recipe, targetServings: 1)
        let selected = try factory.makeSnapshot(
            collectionID: "weekly.week-01",
            recipe: recipe,
            targetServings: 1,
            includedOptionalIngredientIDs: ["maple-syrup"]
        )

        XCTAssertEqual(baseline.ingredients.first { $0.name == "Maple syrup" }?.includeInList, false)
        XCTAssertEqual(selected.ingredients.first { $0.name == "Maple syrup" }?.includeInList, true)
    }

    func testQualitativeIngredientRemainsExplicitWithoutFabricatedQuantityText() throws {
        let recipe = try weeklyRecipe("weekly.chicken-taco-rice-bowls")
        let snapshot = try factory.makeSnapshot(collectionID: "weekly.week-01", recipe: recipe, targetServings: 4)
        let salt = try XCTUnwrap(snapshot.ingredients.first { $0.name == "Salt" })

        XCTAssertEqual(salt.rawText, "Salt to taste")
        XCTAssertEqual(salt.pantryState, .alwaysAsk)
        XCTAssertFalse(salt.quantityReviewRequired == true)
    }

    @MainActor
    func testBeginWeeklyMealFreezesDefaultServingSnapshotAndOpensRecipeReady() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedDefaults()
        )
        let recipe = try weeklyRecipe("weekly.chicken-taco-rice-bowls")

        XCTAssertTrue(
            model.beginWeeklyMeal(
                collectionID: "weekly.week-01",
                recipe: recipe,
                targetServings: recipe.defaultServings
            )
        )

        XCTAssertEqual(model.homePath, [.recipeReady])
        XCTAssertEqual(model.activeRecipe.servings, recipe.defaultServings)
        XCTAssertEqual(
            model.activeRecipe.sourceDetail,
            "Weekly Meals · weekly.week-01 · weekly.chicken-taco-rice-bowls · version 1"
        )
        XCTAssertEqual(model.shoppingScope, .singleRecipe(model.activeRecipe.id))
    }

    @MainActor
    func testWeeklyMealSaveIsIdempotentAndSupportsDurableUndo() async throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, commerceDefaults: isolatedDefaults())
        let snapshot = try snapshot("weekly.protein-overnight-oats", servings: 1)

        XCTAssertTrue(model.saveWeeklyMealSnapshot(snapshot))
        XCTAssertTrue(model.saveWeeklyMealSnapshot(snapshot))
        XCTAssertTrue(model.isRecipeSaved(snapshot.id))
        XCTAssertEqual(model.recipes.filter { $0.id == snapshot.id }.count, 1)
        XCTAssertEqual(model.domainUndoAction?.message, "Recipe saved")

        let didUndo = await model.undoPendingDomainAction()
        XCTAssertTrue(didUndo)
        XCTAssertFalse(model.isRecipeSaved(snapshot.id))
        XCTAssertFalse(model.recipes.contains { $0.id == snapshot.id })
    }

    @MainActor
    func testEnsureMealPrepSelectionNeverTogglesOffAndUpdatesServings() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedDefaults()
        )
        let snapshot = try snapshot("weekly.chicken-taco-rice-bowls", servings: 4)

        XCTAssertTrue(model.ensureRecipeIsIncludedInMealPrep(snapshot, targetServings: 4))
        XCTAssertTrue(model.ensureRecipeIsIncludedInMealPrep(snapshot, targetServings: 6))
        XCTAssertTrue(model.ensureRecipeIsIncludedInMealPrep(snapshot, targetServings: 6))

        let matches = model.mealPrepDraft?.selections.filter { $0.recipeSnapshot.id == snapshot.id }
        XCTAssertEqual(matches?.count, 1)
        XCTAssertEqual(matches?.first?.targetServings, 6)
        XCTAssertTrue(model.isRecipeSelectedForMealPrep(snapshot.id))
    }

    @MainActor
    func testMealPrepInclusionDoesNotImplicitlySaveRecipeMembership() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedDefaults()
        )
        let snapshot = try snapshot("weekly.korean-ground-beef-bowls", servings: 4)

        XCTAssertTrue(model.ensureRecipeIsIncludedInMealPrep(snapshot, targetServings: 4))
        XCTAssertFalse(model.isRecipeSaved(snapshot.id))
        XCTAssertTrue(model.mealPrepCandidateRecipes.contains { $0.id == snapshot.id })
    }

    @MainActor
    func testAddingToReviewedDraftReaggregatesExistingMealPrepPlan() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedDefaults()
        )
        let first = try snapshot("weekly.protein-overnight-oats", servings: 1)
        let second = try snapshot("weekly.protein-berry-smoothie", servings: 1)

        XCTAssertTrue(model.ensureRecipeIsIncludedInMealPrep(first, targetServings: 1))
        XCTAssertTrue(model.buildMealPrepPlan())
        XCTAssertTrue(model.ensureRecipeIsIncludedInMealPrep(second, targetServings: 1))

        XCTAssertEqual(model.currentMealPrepPlan?.selections.count, 2)
        XCTAssertEqual(model.currentMealPrepPlan?.id, model.mealPrepDraft?.id)
    }

    @MainActor
    func testStartedMealPrepSnapshotRemainsFrozenWhenWeeklyMealIsAdded() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedDefaults()
        )
        let first = try snapshot("weekly.protein-overnight-oats", servings: 1)
        let second = try snapshot("weekly.protein-berry-smoothie", servings: 1)
        XCTAssertTrue(model.ensureRecipeIsIncludedInMealPrep(first, targetServings: 1))
        XCTAssertTrue(model.buildMealPrepPlan())
        let frozenDraft = try XCTUnwrap(model.mealPrepDraft)
        let frozenPlan = try XCTUnwrap(model.mealPrepPlan)
        let historicalSession = ShoppingSession(
            logicalTripID: UUID(),
            recipeID: frozenPlan.id,
            recipeTitle: frozenPlan.title,
            storeID: model.primaryStore.retailerStoreID,
            retailerID: model.selectedRetailer.rawValue,
            fulfillmentMode: model.fulfillmentMode,
            shoppingScope: frozenPlan.shoppingScope,
            mealPrepSnapshot: frozenPlan,
            items: []
        )
        model.shoppingSessions = [historicalSession]

        XCTAssertTrue(model.ensureRecipeIsIncludedInMealPrep(second, targetServings: 1))

        XCTAssertNotEqual(model.mealPrepDraft?.id, frozenDraft.id)
        XCTAssertEqual(model.mealPrepDraft?.selections.map(\.recipeSnapshot.id), [second.id])
        XCTAssertNil(model.mealPrepPlan)
        XCTAssertEqual(model.shoppingSession(id: historicalSession.id), historicalSession)
        XCTAssertEqual(model.shoppingSession(id: historicalSession.id)?.mealPrepSnapshot, frozenPlan)
    }

    private let factory = WeeklyMealSnapshotFactory()

    private func snapshot(_ id: String, servings: Int) throws -> Recipe {
        try factory.makeSnapshot(
            collectionID: "weekly.week-01",
            recipe: weeklyRecipe(id),
            targetServings: servings
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WeeklyMealIntegrationTests.\(UUID().uuidString)")!
    }

    private func weeklyRecipe(_ id: String) throws -> CuratedRecipeRecord {
        let resourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SmartCart/WeeklyMeals/Resources", isDirectory: true)
        let resource = try JSONDecoder().decode(
            WeeklyMealRecipesResource.self,
            from: Data(contentsOf: resourceDirectory.appendingPathComponent("recipes-v1.json"))
        )
        return try XCTUnwrap(resource.recipes.first { $0.id.rawValue == id })
    }
}
