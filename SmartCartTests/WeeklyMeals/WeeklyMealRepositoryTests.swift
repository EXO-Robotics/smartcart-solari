import XCTest
@testable import SmartCart

final class WeeklyMealRepositoryTests: XCTestCase {
    func testLocalCalendarDateRoundTripsWithoutTimeZoneDrift() throws {
        let date = try LocalCalendarDate(iso8601: "2026-07-21")
        let data = try JSONEncoder().encode(date)
        XCTAssertEqual(try JSONDecoder().decode(LocalCalendarDate.self, from: data), date)
        XCTAssertThrowsError(try LocalCalendarDate(iso8601: "2026-02-30"))
    }

    func testValidatorAcceptsExactlyEightBalancedMeals() throws {
        let fixture = try Fixture.make()
        XCTAssertTrue(
            WeeklyMealManifestValidator.issues(
                manifest: fixture.manifest,
                recipes: fixture.recipes,
                collections: [fixture.collection]
            ).isEmpty
        )
    }

    func testValidatorRejectsUnbalancedAndDuplicateCollection() throws {
        let fixture = try Fixture.make()
        let duplicated = WeeklyMealCollection(
            id: fixture.collection.id,
            contentSchemaVersion: 1,
            title: fixture.collection.title,
            weekStartDate: fixture.collection.weekStartDate,
            weekEndDateExclusive: fixture.collection.weekEndDateExclusive,
            entries: Array(repeating: fixture.collection.entries[0], count: 8),
            promotionalMessage: nil
        )
        let issues = WeeklyMealManifestValidator.issues(
            manifest: fixture.manifest,
            recipes: fixture.recipes,
            collections: [duplicated]
        )
        XCTAssertTrue(issues.contains { $0.code == .invalidSlotCount })
        XCTAssertTrue(issues.contains { $0.code == .duplicateID })
        XCTAssertTrue(issues.contains { $0.code == .duplicateRecipe })
    }

    func testRepositoryResolvesActiveThenFallbackCollection() throws {
        let fixture = try Fixture.make()
        let loader = DictionaryLoader(values: [
            "manifest-v1.json": try JSONEncoder().encode(fixture.manifest),
            "recipes-v1.json": try JSONEncoder().encode(fixture.recipes),
            "week-01.json": try JSONEncoder().encode(fixture.collection),
            "pricing-v1.json": try JSONEncoder().encode(fixture.pricing)
        ])
        let repository = try BundledWeeklyMealRepository(loader: loader)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let activeDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 22))!
        let futureDate = calendar.date(from: DateComponents(year: 2027, month: 7, day: 22))!
        XCTAssertEqual(try repository.activeCollection(on: activeDate, calendar: calendar).meals.count, 8)
        XCTAssertEqual(try repository.activeCollection(on: futureDate, calendar: calendar).id, "week-01")
    }
}

private struct DictionaryLoader: WeeklyMealsResourceLoading {
    let values: [String: Data]

    func data(resource: String) throws -> Data {
        guard let data = values[resource] else { throw WeeklyMealRepositoryError.missingResource(resource) }
        return data
    }
}

private enum Fixture {
    struct Values {
        let manifest: WeeklyMealsManifest
        let recipes: WeeklyMealRecipesResource
        let collection: WeeklyMealCollection
        let pricing: WeeklyMealPricingResource
    }

    static func make() throws -> Values {
        let slots: [WeeklyMealSlot] = [.breakfast, .breakfast, .lunch, .lunch, .dinner, .dinner, .snack, .snack]
        let recipes = slots.enumerated().map { index, slot in recipe(index: index, slot: slot) }
        let entries = zip(recipes, slots).enumerated().map { index, pair in
            WeeklyMealEntry(
                id: "entry-\(index)",
                recipeReference: .init(recipeID: pair.0.id, contentVersion: 1),
                slot: pair.1,
                displayOrder: index,
                isFeatured: index == 2,
                promotionalTag: .highProtein
            )
        }
        let collection = WeeklyMealCollection(
            id: "week-01",
            contentSchemaVersion: 1,
            title: "This Week's Meals",
            weekStartDate: try .init(iso8601: "2026-07-20"),
            weekEndDateExclusive: try .init(iso8601: "2026-07-27"),
            entries: entries,
            promotionalMessage: nil
        )
        let manifest = WeeklyMealsManifest(
            contentSchemaVersion: 1,
            recipesResource: "recipes-v1.json",
            collectionResources: ["week-01.json"],
            fallbackCollectionID: "week-01",
            pricingResource: "pricing-v1.json"
        )
        let pricing = WeeklyMealPricingResource(
            schemaVersion: 1,
            pricingVersion: 1,
            currencyCode: "USD",
            pricingRegion: "US",
            snapshotDate: nil,
            staleAfterDays: nil,
            prices: []
        )
        return Values(
            manifest: manifest,
            recipes: .init(contentSchemaVersion: 1, recipes: recipes),
            collection: collection,
            pricing: pricing
        )
    }

    static func recipe(index: Int, slot: WeeklyMealSlot) -> CuratedRecipeRecord {
        let id = CuratedRecipeID(rawValue: "weekly.fixture-\(index)")
        return CuratedRecipeRecord(
            id: id,
            contentVersion: 1,
            title: "Fixture \(index)",
            shortDescription: "Fixture description",
            defaultServings: 4,
            servingDescription: "1 serving",
            ingredients: [
                .init(
                    id: "ingredient",
                    rawText: "1 cup ingredient",
                    name: "Ingredient",
                    quantity: 1,
                    unit: "cup",
                    preparation: "",
                    category: "pantry",
                    pricingKey: "ingredient",
                    optionalPolicy: nil,
                    isQualitative: false
                )
            ],
            instructions: [.init(id: 1, text: "Cook it.")],
            substitutions: [],
            metadata: .init(
                prepMinutes: 5,
                cookMinutes: 10,
                passiveMinutes: 0,
                nutrition: .init(
                    caloriesPerServing: 300,
                    calorieRangeMinimum: 250,
                    calorieRangeMaximum: 350,
                    proteinGramsPerServing: 20,
                    servingDefinition: "1 serving",
                    verificationStatus: .editorialEstimate,
                    nutritionVersion: 1
                ),
                costEstimate: .init(
                    recipeID: id,
                    recipeContentVersion: 1,
                    servingDefinition: "1 serving",
                    totalRecipeCost: nil,
                    costPerServing: nil,
                    costRangeMinimumPerServing: nil,
                    costRangeMaximumPerServing: nil,
                    currencyCode: "USD",
                    basis: .proportionalIngredientValue,
                    status: .requiresVerification,
                    pricingRegion: nil,
                    priceSnapshotDate: nil,
                    pricingVersion: 1,
                    includedIngredientIDs: [],
                    excludedIngredientIDs: ["ingredient"],
                    notes: "Pending"
                ),
                mealTypes: [slot],
                verifiedDietaryClaims: [],
                merchandisingTags: [.highProtein],
                imageAssetName: "weekly-placeholder",
                accessibilityDescription: "A plated meal",
                isMealPrepFriendly: true,
                isFeaturedEligible: true
            )
        )
    }
}
