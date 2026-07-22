import XCTest
@testable import SmartCart

final class WeeklyMealCostEstimatorTests: XCTestCase {
    func testProportionalPackageUseAndPerServingDivision() {
        let estimate = WeeklyMealCostEstimator.estimate(recipe: recipe(), pricing: completePricing())
        XCTAssertEqual(estimate.status, .calculated)
        XCTAssertEqual(estimate.totalRecipeCost, Decimal(string: "2.50"))
        XCTAssertEqual(estimate.costPerServing, Decimal(string: "0.625"))
        XCTAssertEqual(WeeklyMealCostFormatter.string(for: estimate, locale: Locale(identifier: "en_US")), "Est. $0.63 per serving")
    }

    func testExcludedOptionalAndQualitativeIngredientsDoNotCreatePartialTotal() {
        let estimate = WeeklyMealCostEstimator.estimate(recipe: recipe(), pricing: completePricing())
        XCTAssertEqual(estimate.status, .calculated)
        XCTAssertEqual(Set(estimate.excludedIngredientIDs), ["salt", "syrup"])
    }

    func testSelectingOptionalIngredientRequiresItsReviewedPrice() {
        let estimate = WeeklyMealCostEstimator.estimate(
            recipe: recipe(),
            pricing: completePricing(),
            includedOptionalIngredientIDs: ["syrup"]
        )
        XCTAssertEqual(estimate.status, .requiresVerification)
        XCTAssertNil(estimate.totalRecipeCost)
        XCTAssertNil(WeeklyMealCostFormatter.string(for: estimate))
    }

    func testMissingOrPartialPricingNeverDisplaysZero() {
        let empty = WeeklyMealPricingResource(
            schemaVersion: 1,
            pricingVersion: 1,
            currencyCode: "USD",
            pricingRegion: "US",
            snapshotDate: nil,
            staleAfterDays: nil,
            prices: []
        )
        let estimate = WeeklyMealCostEstimator.estimate(recipe: recipe(), pricing: empty)
        XCTAssertEqual(estimate.status, .requiresVerification)
        XCTAssertNil(estimate.totalRecipeCost)
        XCTAssertNil(estimate.costPerServing)
        XCTAssertNil(WeeklyMealCostFormatter.string(for: estimate))
    }

    func testContentVersionMismatchRejectsEstimate() {
        var resource = completePricing()
        resource = .init(
            schemaVersion: resource.schemaVersion,
            pricingVersion: resource.pricingVersion,
            currencyCode: resource.currencyCode,
            pricingRegion: resource.pricingRegion,
            snapshotDate: resource.snapshotDate,
            staleAfterDays: resource.staleAfterDays,
            prices: resource.prices.map {
                .init(
                    id: $0.id,
                    recipeID: $0.recipeID,
                    recipeContentVersion: 2,
                    ingredientID: $0.ingredientID,
                    pricingKey: $0.pricingKey,
                    packagePrice: $0.packagePrice,
                    packageQuantity: $0.packageQuantity,
                    packageUnit: $0.packageUnit,
                    reviewed: $0.reviewed
                )
            }
        )
        XCTAssertEqual(
            WeeklyMealCostEstimator.estimate(recipe: recipe(), pricing: resource).status,
            .requiresVerification
        )
    }

    private func recipe() -> CuratedRecipeRecord {
        let id = CuratedRecipeID(rawValue: "weekly.cost-fixture")
        return CuratedRecipeRecord(
            id: id,
            contentVersion: 1,
            title: "Cost Fixture",
            shortDescription: "Synthetic test only",
            defaultServings: 4,
            servingDescription: "1 bowl",
            ingredients: [
                ingredient(id: "rice", quantity: 2, unit: "cup"),
                ingredient(id: "salt", quantity: nil, unit: "", qualitative: true),
                ingredient(id: "syrup", quantity: 1, unit: "tbsp", optional: .excludedByDefault)
            ],
            instructions: [.init(id: 1, text: "Cook.")],
            substitutions: [],
            metadata: .init(
                prepMinutes: 5,
                cookMinutes: 5,
                passiveMinutes: 0,
                nutrition: nil,
                costEstimate: nil,
                mealTypes: [.lunch],
                verifiedDietaryClaims: [],
                merchandisingTags: [],
                imageAssetName: "fixture",
                accessibilityDescription: "Fixture",
                isMealPrepFriendly: false,
                isFeaturedEligible: true,
                baseNutritionExcludes: nil
            )
        )
    }

    private func ingredient(
        id: String,
        quantity: Decimal?,
        unit: String,
        qualitative: Bool = false,
        optional: CuratedOptionalIngredientPolicy? = nil
    ) -> CuratedIngredient {
        .init(
            id: id,
            rawText: "fixture",
            name: id,
            quantity: quantity,
            unit: unit,
            preparation: "",
            category: "pantry",
            pricingKey: id,
            optionalPolicy: optional,
            isQualitative: qualitative
        )
    }

    private func completePricing() -> WeeklyMealPricingResource {
        .init(
            schemaVersion: 1,
            pricingVersion: 1,
            currencyCode: "USD",
            pricingRegion: "US",
            snapshotDate: nil,
            staleAfterDays: nil,
            prices: [
                .init(
                    id: "rice-price",
                    recipeID: "weekly.cost-fixture",
                    recipeContentVersion: 1,
                    ingredientID: "rice",
                    pricingKey: "rice",
                    packagePrice: 5,
                    packageQuantity: 4,
                    packageUnit: "cup",
                    reviewed: true
                )
            ]
        )
    }
}
