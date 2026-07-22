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

    func testRemoteConfigurationRequiresHTTPSAndBuildsManifestURL() throws {
        XCTAssertEqual(
            try WeeklyMealsRemoteConfiguration.resolve(
                explicitURL: URL(string: "https://content.smartcart.app")!
            ).get().manifestURL.absoluteString,
            "https://content.smartcart.app/weekly-meals/manifest.json"
        )
        XCTAssertEqual(
            WeeklyMealsRemoteConfiguration.resolve(
                explicitURL: URL(string: "http://content.smartcart.app")!
            ),
            .failure(.insecureConfiguration)
        )
    }

    func testRemoteValidatorAcceptsSelfContainedEightRecipeCollection() throws {
        let remote = try Fixture.remote()
        let resolved = try RemoteWeeklyMealsValidator.validate(
            manifest: remote.manifest,
            document: remote.document,
            currentAppVersion: "0.3.0"
        )

        XCTAssertEqual(resolved.id, "week-01")
        XCTAssertEqual(resolved.meals.count, 8)
    }

    func testRemoteValidatorRejectsNewerMinimumAppVersionAndUnsafeURL() throws {
        let remote = try Fixture.remote(minimumAppVersion: "2.0.0")
        XCTAssertThrowsError(
            try RemoteWeeklyMealsValidator.validate(
                manifest: remote.manifest,
                document: remote.document,
                currentAppVersion: "1.9.9"
            )
        ) { error in
            XCTAssertEqual(error as? WeeklyMealsRemoteError, .unsupportedAppVersion)
        }

        let unsafe = RemoteWeeklyMealsManifest(
            schemaVersion: 1,
            currentCollectionID: remote.manifest.currentCollectionID,
            currentCollectionURL: "https://other.example/collection.json",
            publishedAt: remote.manifest.publishedAt,
            minimumAppVersion: "0.3.0"
        )
        let configuration = try WeeklyMealsRemoteConfiguration.resolve(
            explicitURL: URL(string: "https://content.smartcart.app")!
        ).get()
        XCTAssertThrowsError(
            try RemoteWeeklyMealsValidator.collectionURL(from: unsafe, relativeTo: configuration)
        ) { error in
            XCTAssertEqual(error as? WeeklyMealsRemoteError, .unsafeCollectionURL)
        }
    }

    @MainActor
    func testStoreUsesValidatedCacheImmediatelyThenPromotesFreshRemoteContent() async throws {
        let remote = try Fixture.remote()
        let cached = CachedWeeklyMealsContent(
            manifest: remote.manifest,
            document: remote.document,
            validatedAt: Date(timeIntervalSince1970: 100)
        )
        let cache = MemoryWeeklyMealsCacheStore(
            data: try RemoteWeeklyMealsValidator.encoder().encode(cached)
        )
        let configuration = try WeeklyMealsRemoteConfiguration.resolve(
            explicitURL: URL(string: "https://content.smartcart.app")!
        ).get()
        let collectionURL = try RemoteWeeklyMealsValidator.collectionURL(
            from: remote.manifest,
            relativeTo: configuration
        )
        let client = StaticWeeklyMealsHTTPClient(responses: [
            configuration.manifestURL: .init(
                data: try RemoteWeeklyMealsValidator.encoder().encode(remote.manifest),
                finalURL: configuration.manifestURL
            ),
            collectionURL: .init(
                data: try RemoteWeeklyMealsValidator.encoder().encode(remote.document),
                finalURL: collectionURL
            )
        ])
        let store = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: cache,
            client: client,
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 1_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 1
        )

        XCTAssertEqual(store.source, .cachedRemote)
        XCTAssertEqual(store.collection?.meals.count, 8)

        await store.refreshIfNeeded()

        XCTAssertEqual(store.source, .freshRemote)
        XCTAssertEqual(store.collection?.id, "week-01")
        XCTAssertNotNil(cache.data)
        XCTAssertNil(store.lastRefreshError)
    }

    @MainActor
    func testInvalidRefreshNeverReplacesLastKnownGoodCollection() async throws {
        let remote = try Fixture.remote()
        let cached = CachedWeeklyMealsContent(
            manifest: remote.manifest,
            document: remote.document,
            validatedAt: Date(timeIntervalSince1970: 100)
        )
        let cache = MemoryWeeklyMealsCacheStore(
            data: try RemoteWeeklyMealsValidator.encoder().encode(cached)
        )
        let configuration = try WeeklyMealsRemoteConfiguration.resolve(
            explicitURL: URL(string: "https://content.smartcart.app")!
        ).get()
        let client = StaticWeeklyMealsHTTPClient(responses: [
            configuration.manifestURL: .init(
                data: Data("not json".utf8),
                finalURL: configuration.manifestURL
            )
        ])
        let store = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: cache,
            client: client,
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 1_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 1
        )

        await store.refreshIfNeeded(force: true)

        XCTAssertEqual(store.source, .cachedRemote)
        XCTAssertEqual(store.collection?.id, "week-01")
        XCTAssertNotNil(store.lastRefreshError)
    }
}

private struct StaticWeeklyMealsHTTPClient: WeeklyMealsHTTPClient {
    let responses: [URL: WeeklyMealsHTTPResponse]

    func get(_ url: URL, maximumBytes: Int) async throws -> WeeklyMealsHTTPResponse {
        guard let response = responses[url], response.data.count <= maximumBytes else {
            throw WeeklyMealsRemoteError.invalidResponse
        }
        return response
    }
}

private final class MemoryWeeklyMealsCacheStore: WeeklyMealsCacheStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?

    init(data: Data? = nil) {
        storedData = data
    }

    var data: Data? {
        lock.withLock { storedData }
    }

    func load() throws -> Data? {
        lock.withLock { storedData }
    }

    func save(_ data: Data) throws {
        lock.withLock { storedData = data }
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

    struct RemoteValues {
        let manifest: RemoteWeeklyMealsManifest
        let document: RemoteWeeklyMealCollectionDocument
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

    static func remote(minimumAppVersion: String = "0.3.0") throws -> RemoteValues {
        let values = try make()
        let publishedAt = Date(timeIntervalSince1970: 1_753_200_000)
        return RemoteValues(
            manifest: RemoteWeeklyMealsManifest(
                schemaVersion: 1,
                currentCollectionID: values.collection.id,
                currentCollectionURL: "/weekly-meals/collections/week-001-v1.json",
                publishedAt: publishedAt,
                minimumAppVersion: minimumAppVersion
            ),
            document: RemoteWeeklyMealCollectionDocument(
                schemaVersion: 1,
                id: values.collection.id,
                revision: 1,
                publishedAt: publishedAt,
                collection: values.collection,
                recipes: values.recipes.recipes
            )
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
                isFeaturedEligible: true,
                baseNutritionExcludes: nil
            )
        )
    }
}
