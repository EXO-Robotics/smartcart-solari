import XCTest
@testable import SmartCart

final class WeeklyMealRepositoryTests: XCTestCase {
    func testLocalCalendarDateRoundTripsWithoutTimeZoneDrift() throws {
        let date = try LocalCalendarDate(iso8601: "2026-07-21")
        let data = try JSONEncoder().encode(date)
        XCTAssertEqual(try JSONDecoder().decode(LocalCalendarDate.self, from: data), date)
        XCTAssertThrowsError(try LocalCalendarDate(iso8601: "2026-02-30"))
    }

    func testCollectionCurrentnessUsesExclusiveLocalDateBoundary() throws {
        let collection = try Fixture.make().collection
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let activeDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 26, hour: 12))
        )
        let expiredDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))
        )

        XCTAssertTrue(collection.contains(activeDate, calendar: calendar))
        XCTAssertFalse(collection.contains(expiredDate, calendar: calendar))
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

    func testMinimumAppVersionUsesNumericComponentOrdering() throws {
        let supportedCases = [
            (current: "1.10.0", minimum: "1.9.0"),
            (current: "1.2.10", minimum: "1.2.9"),
            (current: "2.0", minimum: "1.99.99")
        ]
        for versionCase in supportedCases {
            let remote = try Fixture.remote(minimumAppVersion: versionCase.minimum)
            XCTAssertNoThrow(
                try RemoteWeeklyMealsValidator.validate(
                    manifest: remote.manifest,
                    document: remote.document,
                    currentAppVersion: versionCase.current
                ),
                "Expected \(versionCase.current) to satisfy \(versionCase.minimum)"
            )
        }

        let release = try Fixture.remote(minimumAppVersion: "1.0.0")
        XCTAssertThrowsError(
            try RemoteWeeklyMealsValidator.validate(
                manifest: release.manifest,
                document: release.document,
                currentAppVersion: "1.0.0-beta"
            )
        ) { error in
            XCTAssertEqual(error as? WeeklyMealsRemoteError, .unsupportedAppVersion)
        }
    }

    func testRemoteCollectionRejectsUnapprovedImageAsset() throws {
        let remote = try Fixture.remote(imageAssetName: "AppIcon")

        XCTAssertThrowsError(
            try RemoteWeeklyMealsValidator.validate(
                manifest: remote.manifest,
                document: remote.document,
                currentAppVersion: "0.3.0"
            )
        ) { error in
            guard case let WeeklyMealsRemoteError.invalidCollection(issues) = error else {
                return XCTFail("Expected invalid collection, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.code == .invalidRecipe })
        }
    }

    @MainActor
    func testMissingConfigurationAndCorruptedCacheUseBundledFallback() async {
        let store = WeeklyMealsStore(
            configuration: nil,
            cacheStore: MemoryWeeklyMealsCacheStore(data: Data("corrupt".utf8)),
            currentAppVersion: "0.3.0"
        )

        await store.refreshIfNeeded(force: true)

        XCTAssertEqual(store.source, .bundledFallback)
        XCTAssertEqual(store.collection?.meals.count, 8)
        XCTAssertFalse(store.isCurrentCollection)
        XCTAssertNil(store.lastRefreshError)
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

    @MainActor
    func testOversizedManifestAndCollectionPreserveLastKnownGoodContent() async throws {
        let remote = try Fixture.remote()
        let cached = Fixture.cached(remote)
        let configuration = try Fixture.configuration()
        let collectionURL = try RemoteWeeklyMealsValidator.collectionURL(
            from: remote.manifest,
            relativeTo: configuration
        )

        var oversizedManifestResponses = try Fixture.responses(for: remote, configuration: configuration)
        oversizedManifestResponses[configuration.manifestURL] = .init(
            data: Data(repeating: 0x20, count: RemoteWeeklyMealsValidator.maximumManifestBytes + 1),
            finalURL: configuration.manifestURL
        )
        let manifestStore = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: MemoryWeeklyMealsCacheStore(data: try Fixture.encoded(cached)),
            client: StaticWeeklyMealsHTTPClient(responses: oversizedManifestResponses),
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 2_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 1
        )

        await manifestStore.refreshIfNeeded(force: true)

        XCTAssertEqual(manifestStore.source, .cachedRemote)
        XCTAssertEqual(manifestStore.lastRefreshError, .payloadTooLarge)

        var oversizedCollectionResponses = try Fixture.responses(for: remote, configuration: configuration)
        oversizedCollectionResponses[collectionURL] = .init(
            data: Data(repeating: 0x20, count: RemoteWeeklyMealsValidator.maximumCollectionBytes + 1),
            finalURL: collectionURL
        )
        let collectionStore = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: MemoryWeeklyMealsCacheStore(data: try Fixture.encoded(cached)),
            client: StaticWeeklyMealsHTTPClient(responses: oversizedCollectionResponses),
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 2_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 1
        )

        await collectionStore.refreshIfNeeded(force: true)

        XCTAssertEqual(collectionStore.source, .cachedRemote)
        XCTAssertEqual(collectionStore.lastRefreshError, .payloadTooLarge)
    }

    @MainActor
    func testCrossOriginRedirectPreservesLastKnownGoodContent() async throws {
        let remote = try Fixture.remote()
        let configuration = try Fixture.configuration()
        let collectionURL = try RemoteWeeklyMealsValidator.collectionURL(
            from: remote.manifest,
            relativeTo: configuration
        )
        var responses = try Fixture.responses(for: remote, configuration: configuration)
        responses[configuration.manifestURL] = .init(
            data: try Fixture.encoded(remote.manifest),
            finalURL: URL(string: "https://other.example/weekly-meals/manifest.json")!
        )
        let store = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: MemoryWeeklyMealsCacheStore(data: try Fixture.encoded(Fixture.cached(remote))),
            client: StaticWeeklyMealsHTTPClient(responses: responses),
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 2_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 1
        )

        await store.refreshIfNeeded(force: true)

        XCTAssertEqual(store.source, .cachedRemote)
        XCTAssertEqual(store.lastRefreshError, .crossOriginRedirect)

        var collectionRedirectResponses = try Fixture.responses(for: remote, configuration: configuration)
        collectionRedirectResponses[collectionURL] = .init(
            data: try Fixture.encoded(remote.document),
            finalURL: URL(string: "https://other.example/weekly-meals/collections/week-001-v1.json")!
        )
        let collectionRedirectStore = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: MemoryWeeklyMealsCacheStore(data: try Fixture.encoded(Fixture.cached(remote))),
            client: StaticWeeklyMealsHTTPClient(responses: collectionRedirectResponses),
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 2_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 1
        )

        await collectionRedirectStore.refreshIfNeeded(force: true)

        XCTAssertEqual(collectionRedirectStore.source, .cachedRemote)
        XCTAssertEqual(collectionRedirectStore.lastRefreshError, .crossOriginRedirect)
    }

    @MainActor
    func testOlderPublicationAndLowerRevisionAreRejected() async throws {
        let base = try Fixture.remote(revision: 2)
        let configuration = try Fixture.configuration()

        let older = try Fixture.remote(
            revision: 3,
            publishedAt: base.manifest.publishedAt.addingTimeInterval(-1)
        )
        let olderStore = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: MemoryWeeklyMealsCacheStore(data: try Fixture.encoded(Fixture.cached(base))),
            client: StaticWeeklyMealsHTTPClient(
                responses: try Fixture.responses(for: older, configuration: configuration)
            ),
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 2_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 1
        )

        await olderStore.refreshIfNeeded(force: true)

        XCTAssertEqual(olderStore.source, .cachedRemote)
        XCTAssertEqual(olderStore.lastRefreshError, .staleManifest)

        let lowerRevision = try Fixture.remote(revision: 1)
        let lowerRevisionStore = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: MemoryWeeklyMealsCacheStore(data: try Fixture.encoded(Fixture.cached(base))),
            client: StaticWeeklyMealsHTTPClient(
                responses: try Fixture.responses(for: lowerRevision, configuration: configuration)
            ),
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 2_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 1
        )

        await lowerRevisionStore.refreshIfNeeded(force: true)

        XCTAssertEqual(lowerRevisionStore.source, .cachedRemote)
        XCTAssertEqual(lowerRevisionStore.lastRefreshError, .staleManifest)
    }

    @MainActor
    func testSameRevisionMutationIsRejectedAndHigherRevisionIsAccepted() async throws {
        let base = try Fixture.remote()
        let configuration = try Fixture.configuration()
        let changedAtSameRevision = try Fixture.remote(revision: 1, collectionTitle: "Changed without revision")
        let staleStore = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: MemoryWeeklyMealsCacheStore(data: try Fixture.encoded(Fixture.cached(base))),
            client: StaticWeeklyMealsHTTPClient(
                responses: try Fixture.responses(for: changedAtSameRevision, configuration: configuration)
            ),
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 2_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 1
        )

        await staleStore.refreshIfNeeded(force: true)

        XCTAssertEqual(staleStore.source, .cachedRemote)
        XCTAssertEqual(staleStore.lastRefreshError, .staleManifest)

        let higherRevision = try Fixture.remote(revision: 2, collectionTitle: "Approved revision")
        let promotedStore = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: MemoryWeeklyMealsCacheStore(data: try Fixture.encoded(Fixture.cached(base))),
            client: StaticWeeklyMealsHTTPClient(
                responses: try Fixture.responses(for: higherRevision, configuration: configuration)
            ),
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 2_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 1
        )

        await promotedStore.refreshIfNeeded(force: true)

        XCTAssertEqual(promotedStore.source, .freshRemote)
        XCTAssertEqual(promotedStore.collection?.collection.title, "Approved revision")
        XCTAssertNil(promotedStore.lastRefreshError)
    }

    @MainActor
    func testSimultaneousRefreshesCoalesceAndForcedRefreshBypassesInterval() async throws {
        let remote = try Fixture.remote()
        let configuration = try Fixture.configuration()
        let counter = WeeklyMealsRequestCounter()
        let client = StaticWeeklyMealsHTTPClient(
            responses: try Fixture.responses(for: remote, configuration: configuration),
            delayNanoseconds: 50_000_000,
            counter: counter
        )
        let store = WeeklyMealsStore(
            configuration: configuration,
            cacheStore: MemoryWeeklyMealsCacheStore(),
            client: client,
            clock: FixedWeeklyMealsClock(now: Date(timeIntervalSince1970: 2_000)),
            currentAppVersion: "0.3.0",
            refreshInterval: 3_600
        )

        async let first: Void = store.refreshIfNeeded(force: true)
        async let second: Void = store.refreshIfNeeded(force: true)
        _ = await (first, second)

        let coalescedRequestCount = await counter.value
        XCTAssertEqual(coalescedRequestCount, 2)
        XCTAssertEqual(store.source, .freshRemote)

        await store.refreshIfNeeded()
        let intervalRequestCount = await counter.value
        XCTAssertEqual(intervalRequestCount, 2)

        await store.refreshIfNeeded(force: true)
        let forcedRequestCount = await counter.value
        XCTAssertEqual(forcedRequestCount, 4)
    }
}

private struct StaticWeeklyMealsHTTPClient: WeeklyMealsHTTPClient {
    let responses: [URL: WeeklyMealsHTTPResponse]
    var delayNanoseconds: UInt64 = 0
    var counter: WeeklyMealsRequestCounter?

    func get(_ url: URL, maximumBytes: Int) async throws -> WeeklyMealsHTTPResponse {
        await counter?.record()
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard let response = responses[url] else { throw WeeklyMealsRemoteError.invalidResponse }
        guard response.data.count <= maximumBytes else { throw WeeklyMealsRemoteError.payloadTooLarge }
        return response
    }
}

private actor WeeklyMealsRequestCounter {
    private var count = 0

    func record() {
        count += 1
    }

    var value: Int { count }
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

    static func remote(
        minimumAppVersion: String = "0.3.0",
        revision: Int = 1,
        publishedAt: Date = Date(timeIntervalSince1970: 1_753_200_000),
        collectionTitle: String? = nil,
        imageAssetName: String? = nil
    ) throws -> RemoteValues {
        let values = try make()
        let collection = WeeklyMealCollection(
            id: values.collection.id,
            contentSchemaVersion: values.collection.contentSchemaVersion,
            title: collectionTitle ?? values.collection.title,
            weekStartDate: values.collection.weekStartDate,
            weekEndDateExclusive: values.collection.weekEndDateExclusive,
            entries: values.collection.entries,
            promotionalMessage: values.collection.promotionalMessage
        )
        var recipes = values.recipes.recipes
        if let imageAssetName {
            recipes[0] = replacingImageAssetName(in: recipes[0], with: imageAssetName)
        }
        return RemoteValues(
            manifest: RemoteWeeklyMealsManifest(
                schemaVersion: 1,
                currentCollectionID: collection.id,
                currentCollectionURL: "/weekly-meals/collections/week-001-v1.json",
                publishedAt: publishedAt,
                minimumAppVersion: minimumAppVersion
            ),
            document: RemoteWeeklyMealCollectionDocument(
                schemaVersion: 1,
                id: collection.id,
                revision: revision,
                publishedAt: publishedAt,
                collection: collection,
                recipes: recipes
            )
        )
    }

    static func cached(_ remote: RemoteValues) -> CachedWeeklyMealsContent {
        CachedWeeklyMealsContent(
            manifest: remote.manifest,
            document: remote.document,
            validatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    static func configuration() throws -> WeeklyMealsRemoteConfiguration {
        try WeeklyMealsRemoteConfiguration.resolve(
            explicitURL: URL(string: "https://content.smartcart.app")!
        ).get()
    }

    static func responses(
        for remote: RemoteValues,
        configuration: WeeklyMealsRemoteConfiguration
    ) throws -> [URL: WeeklyMealsHTTPResponse] {
        let collectionURL = try RemoteWeeklyMealsValidator.collectionURL(
            from: remote.manifest,
            relativeTo: configuration
        )
        return [
            configuration.manifestURL: .init(
                data: try encoded(remote.manifest),
                finalURL: configuration.manifestURL
            ),
            collectionURL: .init(
                data: try encoded(remote.document),
                finalURL: collectionURL
            )
        ]
    }

    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        try RemoteWeeklyMealsValidator.encoder().encode(value)
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
                imageAssetName: "weekly-placeholder-protein-overnight-oats",
                accessibilityDescription: "A plated meal",
                isMealPrepFriendly: true,
                isFeaturedEligible: true,
                baseNutritionExcludes: nil
            )
        )
    }

    private static func replacingImageAssetName(
        in recipe: CuratedRecipeRecord,
        with imageAssetName: String
    ) -> CuratedRecipeRecord {
        let metadata = CuratedRecipeMetadata(
            prepMinutes: recipe.metadata.prepMinutes,
            cookMinutes: recipe.metadata.cookMinutes,
            passiveMinutes: recipe.metadata.passiveMinutes,
            nutrition: recipe.metadata.nutrition,
            costEstimate: recipe.metadata.costEstimate,
            mealTypes: recipe.metadata.mealTypes,
            verifiedDietaryClaims: recipe.metadata.verifiedDietaryClaims,
            merchandisingTags: recipe.metadata.merchandisingTags,
            imageAssetName: imageAssetName,
            accessibilityDescription: recipe.metadata.accessibilityDescription,
            isMealPrepFriendly: recipe.metadata.isMealPrepFriendly,
            isFeaturedEligible: recipe.metadata.isFeaturedEligible,
            baseNutritionExcludes: recipe.metadata.baseNutritionExcludes
        )
        return CuratedRecipeRecord(
            id: recipe.id,
            contentVersion: recipe.contentVersion,
            title: recipe.title,
            shortDescription: recipe.shortDescription,
            defaultServings: recipe.defaultServings,
            servingDescription: recipe.servingDescription,
            ingredients: recipe.ingredients,
            instructions: recipe.instructions,
            substitutions: recipe.substitutions,
            metadata: metadata
        )
    }
}
