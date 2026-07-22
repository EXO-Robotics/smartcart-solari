import Foundation
import XCTest
@testable import SmartCart

final class WeeklyMealContentResourceTests: XCTestCase {
    func testWeekOneResourcesDecodeAndPassManifestValidation() throws {
        let loader = SourceResourceLoader()
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(
            WeeklyMealsManifest.self,
            from: loader.data(resource: "manifest-v1.json")
        )
        let recipes = try decoder.decode(
            WeeklyMealRecipesResource.self,
            from: loader.data(resource: manifest.recipesResource)
        )
        let collections = try manifest.collectionResources.map {
            try decoder.decode(WeeklyMealCollection.self, from: loader.data(resource: $0))
        }

        XCTAssertTrue(
            WeeklyMealManifestValidator.issues(
                manifest: manifest,
                recipes: recipes,
                collections: collections
            ).isEmpty
        )
        XCTAssertEqual(recipes.recipes.count, 8)
        XCTAssertEqual(Set(recipes.recipes.map(\.id.rawValue)), Self.expectedRecipeIDs)
        XCTAssertEqual(collections.first?.entries.count, 8)
        XCTAssertEqual(collections.first?.entries.first?.recipeReference.recipeID.rawValue, "weekly.chicken-taco-rice-bowls")
        XCTAssertEqual(collections.first?.entries.filter(\.isFeatured).count, 1)
    }

    func testWeekOneNutritionIsEditorialAndProductionCostIsNotDisplayable() throws {
        let recipes = try JSONDecoder().decode(
            WeeklyMealRecipesResource.self,
            from: SourceResourceLoader().data(resource: "recipes-v1.json")
        ).recipes

        XCTAssertTrue(recipes.allSatisfy { $0.contentVersion == 1 })
        XCTAssertTrue(recipes.allSatisfy { $0.metadata.nutrition?.verificationStatus == .editorialEstimate })
        XCTAssertTrue(recipes.allSatisfy { $0.metadata.costEstimate?.status == .requiresVerification })
        XCTAssertTrue(recipes.allSatisfy { $0.metadata.costEstimate?.totalRecipeCost == nil })
        XCTAssertTrue(recipes.allSatisfy { $0.metadata.costEstimate?.costPerServing == nil })
        XCTAssertTrue(recipes.allSatisfy { $0.metadata.costEstimate?.isPubliclyDisplayable == false })
        XCTAssertTrue(recipes.allSatisfy { $0.metadata.imageAssetName.hasPrefix("weekly-placeholder-") })
    }

    func testProductionPricingResourceContainsNoSyntheticOrPartialPrices() throws {
        let pricing = try WeeklyMealPricingResourceDecoder.decode(
            SourceResourceLoader().data(resource: "pricing-v1.json")
        )

        XCTAssertEqual(pricing.schemaVersion, 1)
        XCTAssertEqual(pricing.pricingVersion, 1)
        XCTAssertEqual(pricing.currencyCode, "USD")
        XCTAssertTrue(pricing.prices.isEmpty)
    }

    func testOptionalIngredientsAreExcludedByDefault() throws {
        let recipes = try JSONDecoder().decode(
            WeeklyMealRecipesResource.self,
            from: SourceResourceLoader().data(resource: "recipes-v1.json")
        ).recipes
        let optionalIDs = Set(
            recipes.flatMap(\.ingredients)
                .filter { $0.optionalPolicy == .excludedByDefault }
                .map(\.id)
        )

        XCTAssertEqual(optionalIDs, ["maple-syrup", "sesame-seeds", "green-onions"])
    }

    func testBuffaloDipBaseNutritionExclusionsArePreserved() throws {
        let recipes = try JSONDecoder().decode(
            WeeklyMealRecipesResource.self,
            from: SourceResourceLoader().data(resource: "recipes-v1.json")
        ).recipes
        let buffaloDip = try XCTUnwrap(
            recipes.first { $0.id.rawValue == "weekly.creamy-buffalo-chicken-dip" }
        )

        XCTAssertEqual(
            buffaloDip.metadata.baseNutritionExcludes,
            ["chips", "crackers", "bread", "wraps", "vegetables used for dipping"]
        )
    }

    private static let expectedRecipeIDs: Set<String> = [
        "weekly.protein-overnight-oats",
        "weekly.make-ahead-breakfast-burritos",
        "weekly.chicken-taco-rice-bowls",
        "weekly.korean-ground-beef-bowls",
        "weekly.honey-garlic-chicken-rice",
        "weekly.one-pot-cheeseburger-pasta",
        "weekly.protein-berry-smoothie",
        "weekly.creamy-buffalo-chicken-dip"
    ]
}

private struct SourceResourceLoader: WeeklyMealsResourceLoading {
    func data(resource: String) throws -> Data {
        try Data(contentsOf: resourceDirectory.appendingPathComponent(resource))
    }

    private var resourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SmartCart/WeeklyMeals/Resources", isDirectory: true)
    }
}
