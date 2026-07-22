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

    private let factory = WeeklyMealSnapshotFactory()

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
