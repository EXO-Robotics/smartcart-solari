import Foundation
import XCTest
@testable import SmartCart

final class SmartCartPersistenceCoordinatorTests: XCTestCase {
    func testCompatibilityWritesRevisionOneThenTwo() throws {
        let store = RecordingRevisionStore()
        let coordinator = SmartCartPersistenceCoordinator(store: store)

        XCTAssertEqual(try coordinator.saveCompatibility(makeState(marker: 1)), 1)
        XCTAssertEqual(try coordinator.saveCompatibility(makeState(marker: 2)), 2)

        XCTAssertEqual(store.savedRevisions, [1, 2])
        XCTAssertEqual(store.savedMarkers, [1, 2])
        XCTAssertEqual(coordinator.latestDurableRevision, 2)
    }

    func testJSONStoreRejectsDelayedRevisionOneAfterRevisionTwo() throws {
        let store = JSONSmartCartStateStore(fileURL: temporaryStateURL())
        var revisionOne = makeState(marker: 1)
        revisionOne.persistenceRevision = 1
        var revisionTwo = makeState(marker: 2)
        revisionTwo.persistenceRevision = 2

        try store.save(revisionOne, expectedRevision: 0)
        try store.save(revisionTwo, expectedRevision: 1)

        XCTAssertThrowsError(try store.save(revisionOne, expectedRevision: 0)) { error in
            XCTAssertEqual(
                error as? SmartCartStateStoreError,
                .staleRevision(attempted: 1, current: 2)
            )
        }
        XCTAssertEqual(try store.load()?.desiredServings, 2)
    }

    func testConcurrentCriticalWritesCommitInDurableOrder() async throws {
        let store = RecordingRevisionStore(writeDelay: 0.02)
        let coordinator = SmartCartPersistenceCoordinator(store: store)

        async let first = coordinator.saveCritical(makeState(marker: 1))
        async let second = coordinator.saveCritical(makeState(marker: 2))
        let revisions = try await [first, second]

        XCTAssertEqual(revisions.sorted(), [1, 2])
        XCTAssertEqual(store.savedRevisions, [1, 2])
        XCTAssertEqual(store.maximumConcurrentWriters, 1)
    }

    func testAutosavesCoalesceToLatestSnapshot() async throws {
        let store = RecordingRevisionStore()
        let coordinator = SmartCartPersistenceCoordinator(
            store: store,
            autosaveDelay: 60
        )

        XCTAssertEqual(try coordinator.requestAutosave(makeState(marker: 1)), 1)
        XCTAssertEqual(try coordinator.requestAutosave(makeState(marker: 2)), 2)
        XCTAssertEqual(coordinator.pendingAutosaveSequence, 2)

        let flushedRevision = try await coordinator.flush()
        XCTAssertEqual(flushedRevision, 1)
        XCTAssertEqual(store.savedMarkers, [2])
        XCTAssertNil(coordinator.pendingAutosaveSequence)
    }

    func testCriticalSaveCancelsOlderPendingAutosave() async throws {
        let store = RecordingRevisionStore()
        let coordinator = SmartCartPersistenceCoordinator(
            store: store,
            autosaveDelay: 60
        )

        _ = try coordinator.requestAutosave(makeState(marker: 1))
        let criticalRevision = try await coordinator.saveCritical(makeState(marker: 2))
        let trailingFlush = try await coordinator.flush()
        XCTAssertEqual(criticalRevision, 1)
        XCTAssertNil(trailingFlush)

        XCTAssertEqual(store.savedMarkers, [2])
        XCTAssertEqual(store.savedRevisions, [1])
    }

    @MainActor
    func testCompatibilityStoreWorkRunsOffMainThread() throws {
        let store = RecordingRevisionStore()
        let coordinator = SmartCartPersistenceCoordinator(store: store)

        _ = try coordinator.saveCompatibility(makeState(marker: 3))

        XCTAssertEqual(store.saveRanOnMainThread, [false])
    }

    @MainActor
    func testAppModelSeedsFirstSuccessorFromLoadedRevision() async throws {
        var loaded = makeState(marker: 3)
        loaded.persistenceRevision = 7
        let store = InMemorySmartCartStateStore(state: loaded)
        let model = AppModel(stateStore: store)

        model.zipCode = "12345"
        await model.flushPendingPersistence()

        let durable = try XCTUnwrap(store.state)
        XCTAssertEqual(durable.persistenceRevision, 8)
        XCTAssertEqual(durable.zipCode, "12345")
    }

    @MainActor
    func testRecipeImportCommitsBeforePublishingRecipeReadyRoute() throws {
        let store = RecordingRevisionStore()
        let model = AppModel(stateStore: store)
        let recipe = makeImportRecipe(title: "Durable import")

        XCTAssertTrue(model.beginRecipe(recipe))

        XCTAssertEqual(store.state?.activeRecipe.id, recipe.id)
        XCTAssertTrue(store.state?.recipes.contains(where: { $0.id == recipe.id }) == true)
        XCTAssertEqual(model.homePath, [.recipeReady])
        XCTAssertNil(model.persistenceIssue)
    }

    @MainActor
    func testFailedRecipeImportPreservesWorkBlocksRouteAndRetriesLatestGraph() async throws {
        let store = RecordingRevisionStore(failuresRemaining: 1)
        let model = AppModel(stateStore: store)
        let recipe = makeImportRecipe(title: "Retryable import")

        XCTAssertFalse(model.beginRecipe(recipe))
        XCTAssertEqual(model.activeRecipe.id, recipe.id)
        XCTAssertTrue(model.recipes.contains(where: { $0.id == recipe.id }))
        XCTAssertTrue(model.homePath.isEmpty)
        XCTAssertEqual(model.persistenceIssue, "Couldn’t save this change.")
        XCTAssertNil(store.state)

        let retried = await model.retryPersistence()
        XCTAssertTrue(retried)
        XCTAssertEqual(store.state?.activeRecipe.id, recipe.id)
        XCTAssertEqual(store.savedRevisions, [1])
        XCTAssertNil(model.persistenceIssue)
    }

    @MainActor
    func testTimerAutosaveFailureRemainsEligibleForLifecycleRetry() async throws {
        let store = RecordingRevisionStore(failuresRemaining: 1)
        let model = AppModel(stateStore: store)

        model.zipCode = "90210"
        await model.flushPendingPersistence()
        XCTAssertEqual(model.persistenceIssue, "Couldn’t save this change.")
        XCTAssertNil(store.state)

        let retried = await model.retryPersistence()
        XCTAssertTrue(retried)
        XCTAssertEqual(store.state?.zipCode, "90210")
        XCTAssertEqual(store.savedRevisions, [1])
    }

    func testExplicitFailureRetainsLatestSnapshotForRetry() async throws {
        let store = RecordingRevisionStore(failuresRemaining: 1)
        let coordinator = SmartCartPersistenceCoordinator(store: store)

        do {
            _ = try await coordinator.saveCritical(makeState(marker: 4))
            XCTFail("The first write should fail")
        } catch {
            XCTAssertEqual(error as? PersistenceCoordinatorTestError, .intentional)
        }

        let retriedRevision = try await coordinator.retryLatest()
        XCTAssertEqual(retriedRevision, 1)
        XCTAssertEqual(store.savedMarkers, [4])
        XCTAssertEqual(store.savedRevisions, [1])
    }

    func testRetryAfterKnownCommitIsIdempotent() async throws {
        let store = RecordingRevisionStore()
        let coordinator = SmartCartPersistenceCoordinator(store: store)

        let committedRevision = try await coordinator.saveCritical(makeState(marker: 5))
        let retriedRevision = try await coordinator.retryLatest()
        XCTAssertEqual(committedRevision, 1)
        XCTAssertEqual(retriedRevision, 1)

        XCTAssertEqual(store.savedMarkers, [5])
        XCTAssertEqual(store.savedRevisions, [1])
    }

    func testJSONStoreExactByteRetryIsIdempotent() throws {
        let fileURL = temporaryStateURL()
        var writes = 0
        let store = JSONSmartCartStateStore(
            fileURL: fileURL,
            atomicWriter: { data, destination in
                writes += 1
                try data.write(to: destination, options: [.atomic])
            }
        )
        var state = makeState(marker: 6)
        state.persistenceRevision = 1

        try store.save(state, expectedRevision: 0)
        try store.save(state, expectedRevision: 0)

        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try store.load(), state)
    }

    func testStaleConflictBlocksBlindRetryOfRejectedWholeGraph() async throws {
        let store = RecordingRevisionStore()
        let winner = SmartCartPersistenceCoordinator(store: store)
        let stale = SmartCartPersistenceCoordinator(store: store)
        _ = try await winner.saveCritical(makeState(marker: 20))

        do {
            _ = try await stale.saveCritical(makeState(marker: 21))
            XCTFail("The stale coordinator should lose the CAS")
        } catch {
            XCTAssertEqual(
                error as? SmartCartStateStoreError,
                .staleRevision(attempted: 1, current: 1)
            )
        }

        do {
            _ = try await stale.retryLatest()
            XCTFail("Blind retry must remain blocked until reload")
        } catch {
            XCTAssertEqual(
                error as? SmartCartPersistenceCoordinatorError,
                .staleConflictRequiresReload(currentRevision: 1)
            )
        }
        XCTAssertEqual(store.state?.desiredServings, 20)
        XCTAssertEqual(store.savedRevisions, [1])
    }

    func testShutdownCancelsPendingAutosaveAndRejectsNewWork() async throws {
        let store = RecordingRevisionStore()
        let coordinator = SmartCartPersistenceCoordinator(
            store: store,
            autosaveDelay: 60
        )
        _ = try coordinator.requestAutosave(makeState(marker: 7))

        try await coordinator.shutdown()

        XCTAssertTrue(store.savedRevisions.isEmpty)
        XCTAssertThrowsError(try coordinator.saveCompatibility(makeState(marker: 8))) { error in
            XCTAssertEqual(error as? SmartCartPersistenceCoordinatorError, .shutdown)
        }
    }

    func testAcceptedCancelledTaskCannotCommitAfterNewerSnapshot() async throws {
        let store = RecordingRevisionStore(writeDelay: 0.03)
        let coordinator = SmartCartPersistenceCoordinator(store: store)
        let older = Task {
            try await coordinator.saveCritical(makeState(marker: 8))
        }
        XCTAssertEqual(store.saveStarted.wait(timeout: .now() + 2), .success)
        older.cancel()

        _ = try await coordinator.saveCritical(makeState(marker: 9))
        _ = try? await older.value
        try await coordinator.shutdown()

        XCTAssertEqual(store.savedMarkers, [8, 9])
        XCTAssertEqual(store.savedRevisions, [1, 2])
        XCTAssertEqual(store.state?.desiredServings, 9)
    }

    func testRevisionExhaustionReturnsTypedFailureWithoutTrap() {
        let coordinator = SmartCartPersistenceCoordinator(
            store: RecordingRevisionStore(initialRevision: UInt64.max),
            initialRevision: UInt64.max
        )

        XCTAssertThrowsError(try coordinator.saveCompatibility(makeState(marker: 10))) { error in
            XCTAssertEqual(error as? SmartCartPersistenceCoordinatorError, .revisionExhausted)
        }
    }

    func testAtomicWriteFailurePreservesPreviousDurableJSON() throws {
        let fileURL = temporaryStateURL()
        let initialStore = JSONSmartCartStateStore(fileURL: fileURL)
        var revisionOne = makeState(marker: 11)
        revisionOne.persistenceRevision = 1
        try initialStore.save(revisionOne, expectedRevision: 0)
        let originalBytes = try Data(contentsOf: fileURL)

        let failingStore = JSONSmartCartStateStore(
            fileURL: fileURL,
            atomicWriter: { _, _ in throw PersistenceCoordinatorTestError.intentional }
        )
        var revisionTwo = makeState(marker: 12)
        revisionTwo.persistenceRevision = 2

        XCTAssertThrowsError(try failingStore.save(revisionTwo, expectedRevision: 1))
        XCTAssertEqual(try Data(contentsOf: fileURL), originalBytes)
        XCTAssertEqual(try initialStore.load(), revisionOne)
    }

    func testFutureSchemaIsRejectedByCASWithoutChangingBytes() throws {
        let fileURL = temporaryStateURL()
        let future = Data(#"{"schemaVersion":999,"persistenceRevision":50,"future":"keep"}"#.utf8)
        try future.write(to: fileURL, options: [.atomic])
        let store = JSONSmartCartStateStore(fileURL: fileURL)
        var state = makeState(marker: 13)
        state.persistenceRevision = 1

        XCTAssertThrowsError(try store.save(state, expectedRevision: 0)) { error in
            XCTAssertEqual(error as? SmartCartStateStoreError, .unsupportedSchema(999))
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), future)
    }

    private func makeState(marker: Int) -> SmartCartPersistedState {
        let recipe = Recipe(
            title: "Persistence \(marker)",
            source: .text,
            sourceDetail: "Coordinator test",
            heroSymbol: "fork.knife",
            servings: marker,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: []
        )
        return SmartCartPersistedState(
            recipes: [recipe],
            activeRecipe: recipe,
            desiredServings: marker,
            preferences: ShoppingPreferences(),
            featureFlags: AppFeatureFlags(),
            storeStrategy: .oneStore,
            fulfillmentMode: .pickup,
            selectedStoreIDs: [],
            zipCode: "00000",
            pickupDay: "Today",
            pickupTime: "Now",
            shoppingItems: [],
            guidedIndex: 0,
            savedLists: [],
            preferredDeliveryPartnerName: nil,
            pantryInventory: [],
            preferredProductIDsByIngredient: [:],
            analyticsEvents: []
        )
    }

    private func makeImportRecipe(title: String) -> Recipe {
        Recipe(
            title: title,
            source: .text,
            sourceDetail: "Persistence test",
            heroSymbol: "fork.knife",
            servings: 2,
            prepMinutes: 5,
            cookMinutes: 10,
            ingredients: [
                Ingredient(
                    name: "Flour",
                    quantity: 1,
                    unit: "cup",
                    category: .pantry
                )
            ]
        )
    }

    private func temporaryStateURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartCart-Slice2-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("state.json")
    }
}

private enum PersistenceCoordinatorTestError: Error, Equatable {
    case intentional
}

private final class RecordingRevisionStore: SmartCartStateStoring {
    private let lock = NSLock()
    private let writeDelay: TimeInterval
    private var failuresRemaining: Int
    private var activeWriters = 0
    let saveStarted = DispatchSemaphore(value: 0)

    private(set) var state: SmartCartPersistedState?
    private(set) var savedRevisions: [UInt64] = []
    private(set) var savedMarkers: [Int] = []
    private(set) var saveRanOnMainThread: [Bool] = []
    private(set) var maximumConcurrentWriters = 0

    init(
        initialRevision: UInt64 = 0,
        writeDelay: TimeInterval = 0,
        failuresRemaining: Int = 0
    ) {
        self.writeDelay = writeDelay
        self.failuresRemaining = failuresRemaining
        if initialRevision > 0 {
            var initial = makeInitialState()
            initial.persistenceRevision = initialRevision
            state = initial
        }
    }

    func load() throws -> SmartCartPersistedState? {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func save(_ state: SmartCartPersistedState) throws {
        try save(state, expectedRevision: self.state?.persistenceRevision ?? 0)
    }

    func save(
        _ newState: SmartCartPersistedState,
        expectedRevision: UInt64
    ) throws {
        lock.lock()
        activeWriters += 1
        maximumConcurrentWriters = max(maximumConcurrentWriters, activeWriters)
        saveRanOnMainThread.append(Thread.isMainThread)
        lock.unlock()
        saveStarted.signal()

        if writeDelay > 0 {
            Thread.sleep(forTimeInterval: writeDelay)
        }

        lock.lock()
        defer {
            activeWriters -= 1
            lock.unlock()
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw PersistenceCoordinatorTestError.intentional
        }
        let currentRevision = state?.persistenceRevision ?? 0
        if newState.persistenceRevision == currentRevision, state == newState {
            return
        }
        guard expectedRevision == currentRevision,
              currentRevision < UInt64.max,
              newState.persistenceRevision == currentRevision + 1
        else {
            throw SmartCartStateStoreError.staleRevision(
                attempted: newState.persistenceRevision,
                current: currentRevision
            )
        }
        state = newState
        savedRevisions.append(newState.persistenceRevision)
        savedMarkers.append(newState.desiredServings)
    }

    private func makeInitialState() -> SmartCartPersistedState {
        let recipe = Recipe(
            title: "Initial",
            source: .text,
            sourceDetail: "Coordinator test",
            heroSymbol: "fork.knife",
            servings: 1,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: []
        )
        return SmartCartPersistedState(
            recipes: [recipe],
            activeRecipe: recipe,
            desiredServings: 1,
            preferences: ShoppingPreferences(),
            featureFlags: AppFeatureFlags(),
            storeStrategy: .oneStore,
            fulfillmentMode: .pickup,
            selectedStoreIDs: [],
            zipCode: "00000",
            pickupDay: "Today",
            pickupTime: "Now",
            shoppingItems: [],
            guidedIndex: 0,
            savedLists: [],
            preferredDeliveryPartnerName: nil,
            pantryInventory: [],
            preferredProductIDsByIngredient: [:],
            analyticsEvents: []
        )
    }
}
