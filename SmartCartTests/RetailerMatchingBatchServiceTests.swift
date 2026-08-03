import Foundation
import XCTest
@testable import SmartCart

final class RetailerMatchingBatchServiceTests: XCTestCase {
    func testMaximumFourFetchesRunAndReverseCompletionStillReturnsInputOrder() async throws {
        let recorder = CatalogFetchRecorder()
        let delays: [String: UInt64] = [
            "item 0": 120_000_000,
            "item 1": 90_000_000,
            "item 2": 60_000_000,
            "item 3": 30_000_000,
            "item 4": 120_000_000,
            "item 5": 90_000_000,
            "item 6": 60_000_000,
            "item 7": 30_000_000
        ]
        let adapter = RecordingGuideAdapter(
            recorder: recorder,
            delaysByQuery: delays,
            products: { request in
                [Self.product(id: "sku-\(request.ingredient.name)", request: request)]
            }
        )
        let engine = RetailerGuideEngine(adapters: [.walmart: adapter])
        let service = RetailerMatchingBatchService(
            configuration: .init(maximumConcurrentFetches: 4)
        )
        let generation = RetailerMatchingGeneration(id: uuid(1))
        let demands = (0..<8).map { index in
            Self.demand(name: "Item \(index)", quantity: 1)
        }

        let result = try await service.match(
            demands,
            using: engine,
            generation: generation
        )
        let items = try result.acceptedItems(for: generation)

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.maximumActiveCount, 4)
        XCTAssertNotEqual(snapshot.completionQueries, demands.map {
            RetailerCandidateFetchKey.normalizeQuery($0.request.ingredient.name)
        })
        XCTAssertEqual(items.map(\.inputIndex), Array(0..<8))
        XCTAssertEqual(
            items.map(\.request.ingredient.name),
            demands.map(\.request.ingredient.name)
        )
        XCTAssertTrue(items.allSatisfy {
            if case .exactProduct = $0.resolution.resolution { return true }
            return false
        })
    }

    func testDuplicateEquivalentQueryFetchesOnceAndReturnsSeparateDemandResults() async throws {
        let recorder = CatalogFetchRecorder()
        let adapter = RecordingGuideAdapter(
            recorder: recorder,
            products: { request in
                [
                    Self.product(
                        id: "small",
                        request: request,
                        title: "Pasta small package",
                        packageQuantity: 8,
                        observedPrice: 2
                    ),
                    Self.product(
                        id: "large",
                        request: request,
                        title: "Pasta large package",
                        packageQuantity: 16,
                        observedPrice: 4
                    )
                ]
            }
        )
        let engine = RetailerGuideEngine(adapters: [.walmart: adapter])
        let service = RetailerMatchingBatchService()
        let preferences = ShoppingPreferences(
            organicPolicy: .noPreference,
            budgetPriority: .lowestTotal
        )
        let demands = [
            Self.demand(name: "Pasta", quantity: 4, preferences: preferences),
            Self.demand(name: "  PASTA!! ", quantity: 12, preferences: preferences)
        ]
        let generation = RetailerMatchingGeneration(id: uuid(2))

        let result = try await service.match(demands, using: engine, generation: generation)
        let items = try result.acceptedItems(for: generation)

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.startedCount, 1)
        XCTAssertEqual(result.uniqueFetchGroupCount, 1)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Self.productID(in: items[0].resolution.resolution), "small")
        XCTAssertEqual(Self.productID(in: items[1].resolution.resolution), "large")
        XCTAssertEqual(items.map(\.resolution.id), demands.map(\.request.ingredient.id))
    }

    func testTransientProviderFailureProducesOneTerminalResultPerDemand() async throws {
        let recorder = CatalogFetchRecorder()
        let adapter = RecordingGuideAdapter(
            recorder: recorder,
            failingQueries: ["rice"],
            products: { _ in [] }
        )
        let engine = RetailerGuideEngine(adapters: [.walmart: adapter])
        let service = RetailerMatchingBatchService()
        let demands = [
            Self.demand(name: "Rice", quantity: 1),
            Self.demand(name: "RICE", quantity: 2)
        ]
        let generation = RetailerMatchingGeneration(id: uuid(3))

        let result = try await service.match(demands, using: engine, generation: generation)
        let items = try result.acceptedItems(for: generation)

        let startedCount = await recorder.startedCount()
        XCTAssertEqual(startedCount, 1)
        XCTAssertEqual(items.count, demands.count)
        XCTAssertEqual(
            items.map(\.resolution.resolution),
            Array(repeating: .unresolved(.transientProviderFailure), count: demands.count)
        )
    }

    func testCancellationDuringActiveRequestsCancelsAdapterAndReturnsNoResult() async {
        let recorder = CatalogFetchRecorder()
        let adapter = RecordingGuideAdapter(
            recorder: recorder,
            defaultDelayNanoseconds: 2_000_000_000,
            products: { request in [Self.product(id: "slow", request: request)] }
        )
        let engine = RetailerGuideEngine(adapters: [.walmart: adapter])
        let service = RetailerMatchingBatchService()
        let demands = (0..<6).map { Self.demand(name: "Slow \($0)", quantity: 1) }

        let task = Task {
            try await service.match(demands, using: engine)
        }
        await recorder.waitUntilStarted(atLeast: 4)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A canceled batch must not return a partial result")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Cancellation must remain CancellationError, got \(error)")
        }

        let snapshot = await recorder.snapshot()
        XCTAssertGreaterThan(snapshot.canceledCount, 0)
        XCTAssertEqual(snapshot.successfulCount, 0)
    }

    func testCancellationBeforeWorkStartsPerformsNoCatalogRequest() async {
        let recorder = CatalogFetchRecorder()
        let adapter = RecordingGuideAdapter(
            recorder: recorder,
            products: { request in [Self.product(id: "unused", request: request)] }
        )
        let engine = RetailerGuideEngine(adapters: [.walmart: adapter])
        let service = RetailerMatchingBatchService()
        let demand = Self.demand(name: "Milk", quantity: 1)

        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await service.match([demand], using: engine)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A request canceled before matching must throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Cancellation must remain CancellationError, got \(error)")
        }

        let startedCount = await recorder.startedCount()
        XCTAssertEqual(startedCount, 0)
    }

    func testEmptyInputReturnsAcceptedEmptyResultWithoutFetches() async throws {
        let recorder = CatalogFetchRecorder()
        let adapter = RecordingGuideAdapter(recorder: recorder, products: { _ in [] })
        let engine = RetailerGuideEngine(adapters: [.walmart: adapter])
        let service = RetailerMatchingBatchService()
        let generation = RetailerMatchingGeneration(id: uuid(6))

        let result = try await service.match([], using: engine, generation: generation)
        let items = try result.acceptedItems(for: generation)

        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(result.itemCount, 0)
        XCTAssertEqual(result.uniqueFetchGroupCount, 0)
        let startedCount = await recorder.startedCount()
        XCTAssertEqual(startedCount, 0)
    }

    func testUnavailableAdapterProducesTypedTerminalResolution() async throws {
        let engine = RetailerGuideEngine(adapters: [:])
        let service = RetailerMatchingBatchService()
        let demand = Self.demand(name: "Milk", quantity: 1)
        let generation = RetailerMatchingGeneration(id: uuid(7))

        let result = try await service.match([demand], using: engine, generation: generation)
        let items = try result.acceptedItems(for: generation)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(
            items[0].resolution.resolution,
            .unresolved(.adapterUnavailable(retailerID: ShoppingRetailer.walmart.rawValue))
        )
    }

    func testInvalidIngredientQueryNeverStartsRetailerFetch() async throws {
        let recorder = CatalogFetchRecorder()
        let adapter = RecordingGuideAdapter(
            recorder: recorder,
            products: { request in
                [Self.product(id: "must-not-fetch", request: request)]
            }
        )
        let engine = RetailerGuideEngine(adapters: [.walmart: adapter])
        let service = RetailerMatchingBatchService()
        let generation = RetailerMatchingGeneration(id: uuid(12))

        let result = try await service.match(
            [Self.demand(name: "For The Thai Infused Rum", quantity: 1)],
            using: engine,
            generation: generation
        )
        let items = try result.acceptedItems(for: generation)
        let snapshot = await recorder.snapshot()

        XCTAssertEqual(snapshot.startedCount, 0)
        XCTAssertEqual(result.uniqueFetchGroupCount, 0)
        XCTAssertEqual(items.first?.resolution.resolution, .unresolved(.fallbackUnavailable))
    }

    func testMalformedCandidateBecomesInvalidCandidateTerminalResolution() async throws {
        let recorder = CatalogFetchRecorder()
        let adapter = RecordingGuideAdapter(
            recorder: recorder,
            fallback: { _, _, _ in nil },
            products: { request in
                [Self.product(id: "", request: request, title: "Malformed product")]
            }
        )
        let engine = RetailerGuideEngine(adapters: [.walmart: adapter])
        let service = RetailerMatchingBatchService()
        let generation = RetailerMatchingGeneration(id: uuid(8))

        let result = try await service.match(
            [Self.demand(name: "Milk", quantity: 1)],
            using: engine,
            generation: generation
        )
        let items = try result.acceptedItems(for: generation)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].resolution.resolution, .unresolved(.invalidCandidateData))
    }

    func testMixedExactFallbackUnresolvedAndExcludedResultsRemainInInputOrder() async throws {
        let recorder = CatalogFetchRecorder()
        let adapter = RecordingGuideAdapter(
            recorder: recorder,
            fallback: { ingredient, storeID, _ in
                guard RetailerCandidateFetchKey.normalizeQuery(ingredient.name) == "fallback" else {
                    return nil
                }
                return Self.searchFallback(for: ingredient, storeID: storeID)
            },
            products: { request in
                guard RetailerCandidateFetchKey.normalizeQuery(request.ingredient.name) == "exact" else {
                    return []
                }
                return [Self.product(id: "exact-sku", request: request)]
            }
        )
        let engine = RetailerGuideEngine(adapters: [.walmart: adapter])
        let service = RetailerMatchingBatchService()
        let demands = [
            Self.demand(name: "Exact", quantity: 1),
            Self.demand(name: "Fallback", quantity: 1),
            Self.demand(name: "Unresolved", quantity: 1),
            Self.demand(name: "Excluded", quantity: 1, isExplicitlyExcluded: true)
        ]
        let generation = RetailerMatchingGeneration(id: uuid(9))

        let result = try await service.match(demands, using: engine, generation: generation)
        let items = try result.acceptedItems(for: generation)

        XCTAssertEqual(items.map(\.inputIndex), Array(0..<demands.count))
        XCTAssertEqual(items.map(\.resolution.id), demands.map(\.request.ingredient.id))
        XCTAssertEqual(Self.productID(in: items[0].resolution.resolution), "exact-sku")
        if case .searchFallback = items[1].resolution.resolution {
            // Expected.
        } else {
            XCTFail("Second demand must retain its labeled search fallback")
        }
        XCTAssertEqual(items[2].resolution.resolution, .unresolved(.fallbackUnavailable))
        XCTAssertEqual(items[3].resolution.resolution, .userExcluded)
        XCTAssertEqual(result.uniqueFetchGroupCount, 3)
    }

    func testStaleGenerationIsRejectedAtPublicationBoundary() async throws {
        let recorder = CatalogFetchRecorder()
        let adapter = RecordingGuideAdapter(
            recorder: recorder,
            products: { request in [Self.product(id: "milk", request: request)] }
        )
        let engine = RetailerGuideEngine(adapters: [.walmart: adapter])
        let service = RetailerMatchingBatchService()
        let completed = RetailerMatchingGeneration(id: uuid(10))
        let current = RetailerMatchingGeneration(id: uuid(11))

        let result = try await service.match(
            [Self.demand(name: "Milk", quantity: 1)],
            using: engine,
            generation: completed
        )

        XCTAssertThrowsError(try result.acceptedItems(for: current)) { error in
            XCTAssertEqual(
                error as? RetailerMatchingPublicationError,
                .staleGeneration(completed: completed, current: current)
            )
        }
        XCTAssertEqual(try result.acceptedItems(for: completed).count, 1)
    }

    private static func demand(
        name: String,
        quantity: Double,
        unit: String = "oz",
        storeID: String = "walmart-5206",
        fulfillment: FulfillmentMethod = .pickup,
        preferences: ShoppingPreferences = ShoppingPreferences(),
        isExplicitlyExcluded: Bool = false
    ) -> RetailerMatchingDemand {
        let ingredient = Ingredient(name: name, quantity: quantity, unit: unit)
        return RetailerMatchingDemand(
            request: RetailerProductSearchRequest(
                ingredient: ingredient,
                retailerID: ShoppingRetailer.walmart.rawValue,
                requestedQuantity: quantity,
                requestedUnit: unit,
                storeID: storeID,
                fulfillmentMethod: fulfillment
            ),
            preferences: preferences,
            isExplicitlyExcluded: isExplicitlyExcluded
        )
    }

    fileprivate static func product(
        id: String,
        request: RetailerProductSearchRequest,
        title: String? = nil,
        packageQuantity: Double = 16,
        observedPrice: Decimal = 3
    ) -> RetailerProductRecord {
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "invalid"
        let url = URL(string: "https://www.walmart.com/ip/\(encodedID)")
            ?? URL(fileURLWithPath: "/invalid-test-url")
        return RetailerProductRecord(
            retailerID: request.retailerID,
            storeID: request.storeID,
            retailerProductID: id,
            title: title ?? "\(request.ingredient.name) product",
            brand: "Fixture Brand",
            exactURL: url,
            packageDescription: "\(packageQuantity) oz",
            packageQuantity: packageQuantity,
            packageUnit: "oz",
            observedPrice: observedPrice,
            unitPriceValue: observedPrice / Decimal(packageQuantity),
            unitPriceText: "$\(observedPrice)",
            priceType: .exact,
            availability: .inStock,
            fulfillmentMethods: [.pickup, .delivery],
            organicStatus: .notOrganic,
            dataSource: .retailerAPI,
            observedAt: Date(timeIntervalSince1970: 1_000),
            linkKind: .exactProduct,
            symbol: "cart",
            matchKeywords: [request.ingredient.name.lowercased()]
        )
    }

    fileprivate static func searchFallback(
        for ingredient: Ingredient,
        storeID: String
    ) -> RetailerProductRecord {
        let request = RetailerProductSearchRequest(
            ingredient: ingredient,
            retailerID: ShoppingRetailer.walmart.rawValue,
            requestedQuantity: ingredient.quantity,
            requestedUnit: ingredient.unit,
            storeID: storeID,
            fulfillmentMethod: .pickup
        )
        var fallback = product(id: "search:\(ingredient.name)", request: request)
        fallback.dataSource = .searchFallback
        fallback.linkKind = .searchResults
        fallback.observedPrice = nil
        fallback.unitPriceValue = nil
        fallback.unitPriceText = "Price unavailable"
        fallback.priceType = .unavailable
        fallback.fulfillmentMethods = []
        return fallback
    }

    private static func productID(in resolution: ShoppingResolution) -> String? {
        resolution.product?.retailerProductID
    }

    private func uuid(_ suffix: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, suffix))
    }
}

private actor CatalogFetchRecorder {
    struct Snapshot {
        let startedCount: Int
        let successfulCount: Int
        let canceledCount: Int
        let maximumActiveCount: Int
        let completionQueries: [String]
    }

    private var activeCount = 0
    private var maximumActiveCount = 0
    private var startedQueries: [String] = []
    private var completionQueries: [String] = []
    private var successfulCount = 0
    private var canceledCount = 0

    func started(query: String) {
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        startedQueries.append(query)
    }

    func finished(query: String, canceled: Bool) {
        activeCount -= 1
        if canceled {
            canceledCount += 1
        } else {
            successfulCount += 1
            completionQueries.append(query)
        }
    }

    func startedCount() -> Int { startedQueries.count }

    func waitUntilStarted(atLeast count: Int) async {
        while startedQueries.count < count {
            await Task.yield()
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            startedCount: startedQueries.count,
            successfulCount: successfulCount,
            canceledCount: canceledCount,
            maximumActiveCount: maximumActiveCount,
            completionQueries: completionQueries
        )
    }
}

private struct RecordingGuideAdapter: RetailerGuideAdapter {
    typealias Products = @Sendable (RetailerProductSearchRequest) -> [RetailerProductRecord]
    typealias Fallback = @Sendable (
        Ingredient,
        String,
        ShoppingPreferences
    ) -> RetailerProductRecord?

    let recorder: CatalogFetchRecorder
    var delaysByQuery: [String: UInt64]
    var defaultDelayNanoseconds: UInt64
    var failingQueries: Set<String>
    let fallback: Fallback
    let products: Products

    init(
        recorder: CatalogFetchRecorder,
        delaysByQuery: [String: UInt64] = [:],
        defaultDelayNanoseconds: UInt64 = 0,
        failingQueries: Set<String> = [],
        fallback: @escaping Fallback = { ingredient, storeID, _ in
            RetailerMatchingBatchServiceTests.searchFallback(
                for: ingredient,
                storeID: storeID
            )
        },
        products: @escaping Products
    ) {
        self.recorder = recorder
        self.delaysByQuery = delaysByQuery
        self.defaultDelayNanoseconds = defaultDelayNanoseconds
        self.failingQueries = failingQueries
        self.fallback = fallback
        self.products = products
    }

    var retailer: ShoppingRetailer { .walmart }
    var retailerID: String { ShoppingRetailer.walmart.rawValue }
    var capabilities: RetailerCapabilities {
        [.catalogSearch, .exactProductLinks, .guidedProductHandoff]
    }

    func searchProducts(
        for request: RetailerProductSearchRequest
    ) async throws -> [RetailerProductRecord] {
        let query = RetailerCandidateFetchKey.normalizeQuery(request.ingredient.name)
        await recorder.started(query: query)
        do {
            let delay = delaysByQuery[query] ?? defaultDelayNanoseconds
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }
            if failingQueries.contains(query) {
                throw RecordingAdapterError.scriptedFailure
            }
            try Task.checkCancellation()
            let result = products(request).map { product in
                var product = product
                product.storeID = request.storeID
                return product
            }
            await recorder.finished(query: query, canceled: false)
            return result
        } catch {
            await recorder.finished(
                query: query,
                canceled: error is CancellationError || Task.isCancelled
            )
            throw error
        }
    }

    func resolveProduct(
        retailerProductID: String,
        storeID: String?
    ) async throws -> RetailerProductRecord {
        throw RetailerServiceError.productNotFound(retailerProductID)
    }

    func refresh(product: RetailerProductRecord) async throws -> RetailerProductRecord {
        product
    }

    func createHandoff(manifest: ShoppingManifest) async throws -> RetailerHandoff {
        throw RetailerServiceError.unsupportedCapability("Fixture handoff")
    }

    func searchFallback(
        for ingredient: Ingredient,
        storeID: String,
        preferences: ShoppingPreferences
    ) -> RetailerProductRecord {
        fallback(ingredient, storeID, preferences)
            ?? Self.unavailableFallback(for: ingredient, storeID: storeID)
    }

    func batchSearchFallback(
        for ingredient: Ingredient,
        storeID: String,
        preferences: ShoppingPreferences
    ) -> RetailerProductRecord? {
        fallback(ingredient, storeID, preferences)
    }

    private static func unavailableFallback(
        for ingredient: Ingredient,
        storeID: String
    ) -> RetailerProductRecord {
        let request = RetailerProductSearchRequest(
            ingredient: ingredient,
            retailerID: ShoppingRetailer.walmart.rawValue,
            requestedQuantity: ingredient.quantity,
            requestedUnit: ingredient.unit,
            storeID: storeID,
            fulfillmentMethod: .pickup
        )
        var product = RetailerMatchingBatchServiceTests.product(
            id: "unavailable-fallback",
            request: request
        )
        product.availability = .outOfStock
        product.dataSource = .searchFallback
        product.linkKind = .searchResults
        return product
    }
}

private enum RecordingAdapterError: Error {
    case scriptedFailure
}
