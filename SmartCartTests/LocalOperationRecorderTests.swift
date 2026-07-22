import Foundation
import XCTest
@testable import SmartCart

final class LocalOperationRecorderTests: XCTestCase {
    func testEveryTerminalCategoryRecordsWithTypedMetadata() throws {
        let recorder = LocalOperationRecorder(fileURL: temporaryFileURL())

        for event in LocalOperationTerminalEvent.allCases {
            let token = try XCTUnwrap(
                recorder.start(
                    .recipeImport,
                    importMethod: .pastedText,
                    retailer: .walmart
                )
            )
            XCTAssertTrue(recorder.finish(token, event: event, failureCategory: .invalidInput))
        }

        XCTAssertEqual(recorder.records().compactMap(\.eventName), LocalOperationTerminalEvent.allCases)
        XCTAssertTrue(recorder.records().allSatisfy { $0.operationType == .recipeImport })
        XCTAssertTrue(recorder.records().allSatisfy { $0.importMethod == .pastedText })
        XCTAssertTrue(recorder.records().allSatisfy { $0.retailer == .walmart })
    }

    func testRetryThenAutomaticFinishNormalizesToRecoveredAndBucketsDuration() throws {
        let clock = OperationRecorderTestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let recorder = LocalOperationRecorder(fileURL: temporaryFileURL(), now: clock.now)
        let token = try XCTUnwrap(recorder.start(.retailerPageLoad, retailer: .target))

        clock.advance(by: 0.5)
        XCTAssertTrue(recorder.recordRetry(token, failureCategory: .offline))
        clock.advance(by: 1.5)
        XCTAssertTrue(recorder.finish(token, event: .handledAutomatically))

        let record = try XCTUnwrap(recorder.record(for: token))
        XCTAssertEqual(record.eventName, .recovered)
        XCTAssertEqual(record.retryCount, 1)
        XCTAssertEqual(record.failureCategory, .offline)
        XCTAssertEqual(record.durationBucket, .underFiveSeconds)
    }

    func testDurationBucketingHasStableLowCardinalityBoundaries() {
        XCTAssertEqual(LocalOperationDurationBucket.bucket(for: 0.299), .under300Milliseconds)
        XCTAssertEqual(LocalOperationDurationBucket.bucket(for: 0.3), .underOneSecond)
        XCTAssertEqual(LocalOperationDurationBucket.bucket(for: 1), .underFiveSeconds)
        XCTAssertEqual(LocalOperationDurationBucket.bucket(for: 5), .underThirtySeconds)
        XCTAssertEqual(LocalOperationDurationBucket.bucket(for: 30), .thirtySecondsOrMore)
        XCTAssertEqual(LocalOperationDurationBucket.bucket(for: .infinity), .unknown)
        XCTAssertEqual(LocalOperationDurationBucket.bucket(for: -1), .unknown)
    }

    func testInterruptedInflightRecordBecomesAbandonedOnRelaunchWithoutTimestamp() throws {
        let fileURL = temporaryFileURL()
        let recorder = LocalOperationRecorder(fileURL: fileURL)
        XCTAssertNotNil(recorder.start(.productMatching, retailer: .kroger))

        let restored = LocalOperationRecorder(fileURL: fileURL)
        let record = try XCTUnwrap(restored.records().first)
        XCTAssertEqual(record.eventName, .abandoned)
        XCTAssertEqual(record.failureCategory, .processInterrupted)
        XCTAssertEqual(record.durationBucket, .unknown)
        XCTAssertEqual(restored.recoverStaleInFlightOperations(), 0)
    }

    func testRetentionCapEvictsOldestTerminalAndNeverInflight() throws {
        let recorder = LocalOperationRecorder(fileURL: temporaryFileURL(), capacity: 2)
        let first = try XCTUnwrap(recorder.start(.recipeImport))
        let second = try XCTUnwrap(recorder.start(.productMatching))
        XCTAssertNil(recorder.start(.shoppingTrip))

        XCTAssertTrue(recorder.finish(first, event: .handledAutomatically))
        let third = try XCTUnwrap(recorder.start(.shoppingTrip))

        XCTAssertNil(recorder.record(for: first))
        XCTAssertNotNil(recorder.record(for: second))
        XCTAssertNotNil(recorder.record(for: third))
        XCTAssertEqual(recorder.records().count, 2)
    }

    func testManyTerminalRecordsRemainBounded() throws {
        let recorder = LocalOperationRecorder(fileURL: temporaryFileURL(), capacity: 3)
        for _ in 0..<20 {
            let token = try XCTUnwrap(recorder.start(.statePersistence))
            XCTAssertTrue(recorder.finish(token, event: .handledAutomatically))
        }
        XCTAssertEqual(recorder.records().count, 3)
    }

    func testRecorderWriteFailureNeverEscapesAndTypedMemoryStateContinues() throws {
        let recorder = LocalOperationRecorder(store: FailingOperationDataStore(failLoad: false))
        let token = try XCTUnwrap(recorder.start(.statePersistence))
        XCTAssertTrue(recorder.recordRetry(token, failureCategory: .persistenceWriteFailed))
        XCTAssertTrue(recorder.finish(token, event: .recovered))

        XCTAssertEqual(recorder.storageHealth, .unavailable)
        XCTAssertEqual(recorder.record(for: token)?.eventName, .recovered)
        XCTAssertFalse(recorder.clear())
    }

    func testMalformedFileFailsClosedAndCanBeExplicitlyReenabled() throws {
        let fileURL = temporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        let recorder = LocalOperationRecorder(fileURL: fileURL)
        XCTAssertFalse(recorder.isRecordingEnabled)
        XCTAssertNil(recorder.start(.recipeImport))

        recorder.setRecordingEnabled(true)
        XCTAssertNotNil(recorder.start(.recipeImport))
        XCTAssertEqual(recorder.storageHealth, .available)
    }

    func testOptOutPersistsAndClearDeletesRecords() throws {
        let fileURL = temporaryFileURL()
        let recorder = LocalOperationRecorder(fileURL: fileURL)
        let token = try XCTUnwrap(recorder.start(.barcodeLookup))
        XCTAssertTrue(recorder.finish(token, event: .requiredDecision, failureCategory: .noResult))
        recorder.setRecordingEnabled(false)
        XCTAssertTrue(recorder.clear())

        let restored = LocalOperationRecorder(fileURL: fileURL)
        XCTAssertFalse(restored.isRecordingEnabled)
        XCTAssertTrue(restored.records().isEmpty)
        XCTAssertNil(restored.start(.pantryMutation))
    }

    func testSerializedSchemaIsDeterministicAllowlistedAndContentFree() throws {
        let sensitiveValues = [
            "PRIVATE_RECIPE_TEXT_7849",
            "https://private.example/recipe",
            "person@example.com",
            "078742002163",
            "PRIVATE_PRODUCT_NAME_1177"
        ]
        let fileURL = temporaryFileURL(pathComponents: sensitiveValues)
        let recorder = LocalOperationRecorder(fileURL: fileURL)
        let token = try XCTUnwrap(
            recorder.start(.recipeImport, importMethod: .recipeLink, retailer: .target)
        )
        XCTAssertTrue(recorder.recordRetry(token, failureCategory: .serviceUnavailable))
        XCTAssertTrue(recorder.finish(token, event: .requiredDecision, failureCategory: .ambiguousResult))

        let data = try Data(contentsOf: fileURL)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        for value in sensitiveValues {
            XCTAssertFalse(encoded.contains(value))
        }
        XCTAssertFalse(encoded.contains(fileURL.path))
        XCTAssertFalse(encoded.contains("startedAt"))
        XCTAssertFalse(encoded.contains("finishedAt"))
        XCTAssertFalse(encoded.contains("shoppingOutcome"))
        XCTAssertFalse(encoded.contains("properties"))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["schemaVersion", "recordingEnabled", "records"]))
        let records = try XCTUnwrap(object["records"] as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(
            Set(record.keys),
            Set([
                "operationType", "importMethod", "retailer", "retryCount",
                "eventName", "failureCategory", "durationBucket"
            ])
        )
    }

    func testSharedImportMethodsRecordOnlyCategoricalMetadata() throws {
        let fileURL = temporaryFileURL()
        let recorder = LocalOperationRecorder(fileURL: fileURL)

        for method in [
            LocalOperationImportMethod.sharedImages,
            .sharedLink,
            .sharedText
        ] {
            let token = try XCTUnwrap(
                recorder.start(.recipeImport, importMethod: method, retailer: nil)
            )
            XCTAssertTrue(recorder.finish(token, event: .handledAutomatically))
        }

        XCTAssertEqual(
            recorder.records().compactMap(\.importMethod),
            [.sharedImages, .sharedLink, .sharedText]
        )
        let encoded = try XCTUnwrap(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        XCTAssertFalse(encoded.contains("https://private.example/recipe"))
        XCTAssertFalse(encoded.contains("PRIVATE_SHARED_TEXT"))
        XCTAssertFalse(encoded.contains("private-photo.heic"))
        XCTAssertFalse(encoded.contains("inboxItemID"))
    }

    func testConcurrentRecordingIsSerializedAndKeepsOneTerminalResultPerToken() throws {
        let recorder = LocalOperationRecorder(fileURL: temporaryFileURL(), capacity: 100)
        let queue = DispatchQueue(label: "LocalOperationRecorderTests.concurrent", attributes: .concurrent)
        let group = DispatchGroup()

        for _ in 0..<50 {
            group.enter()
            queue.async {
                if let token = recorder.start(.pantryMutation) {
                    _ = recorder.finish(token, event: .handledAutomatically)
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(recorder.records().count, 50)
        XCTAssertTrue(recorder.records().allSatisfy { $0.eventName == .handledAutomatically })
    }

    @MainActor
    func testAsyncObserverWritesOffMainThreadInSubmissionOrder() throws {
        XCTAssertTrue(Thread.isMainThread)
        let store = ThreadRecordingOperationDataStore()
        let recorder = LocalOperationRecorder(store: store)
        let observer = AsyncLocalOperationObserver(recorder: recorder)

        let token = observer.start(.productMatching, retailer: .walmart)
        observer.finish(token, event: .handledAutomatically, failureCategory: nil)
        observer.waitUntilIdle()

        XCTAssertEqual(store.saveWasMainThread, [false, false])
        XCTAssertEqual(recorder.records().first?.eventName, .handledAutomatically)
    }

    @MainActor
    func testRecorderWriteFailureCannotChangeProductFlowOrDurableState() throws {
        let stateStore = InMemorySmartCartStateStore()
        let recorder = LocalOperationRecorder(store: FailingOperationDataStore(failLoad: false))
        let observer = AsyncLocalOperationObserver(recorder: recorder)
        let model = AppModel(
            stateStore: stateStore,
            commerceDefaults: isolatedDefaults(),
            operationObserver: observer
        )
        let recipe = testRecipe(title: "Recorder failure stays isolated")

        XCTAssertTrue(model.beginRecipe(recipe))
        observer.waitUntilIdle()

        XCTAssertEqual(model.activeRecipe.id, recipe.id)
        XCTAssertEqual(stateStore.state?.activeRecipe.id, recipe.id)
        XCTAssertEqual(model.homePath, [.recipeReady])
        XCTAssertEqual(recorder.storageHealth, .unavailable)
    }

    @MainActor
    func testAppModelRecordsTypedImportAndUndoRecoveryWithoutContent() async throws {
        let fileURL = temporaryFileURL()
        let recorder = LocalOperationRecorder(fileURL: fileURL)
        let observer = AsyncLocalOperationObserver(recorder: recorder)
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedDefaults(),
            operationObserver: observer
        )
        let sensitiveTitle = "PRIVATE_RECIPE_TITLE_91827"
        let recipe = testRecipe(title: sensitiveTitle)

        XCTAssertTrue(model.beginRecipe(recipe))
        XCTAssertTrue(model.removeRecipeFromLibrary(recipe.id))
        let didUndo = await model.undoPendingDomainAction()
        XCTAssertTrue(didUndo)
        observer.waitUntilIdle()

        XCTAssertTrue(recorder.records().contains {
            $0.operationType == .recipeImport && $0.eventName == .handledAutomatically
        })
        XCTAssertTrue(recorder.records().contains {
            $0.operationType == .statePersistence && $0.eventName == .recovered
        })
        let encoded = try XCTUnwrap(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        XCTAssertFalse(encoded.contains(sensitiveTitle))
    }

    func testWeeklyMealEventsPersistOnlyAllowlistedMetadata() throws {
        let fileURL = temporaryFileURL()
        let recorder = LocalOperationRecorder(fileURL: fileURL)
        let metadata = WeeklyMealOperationMetadata(
            collectionID: "weekly.week-01",
            recipeID: "weekly.chicken-taco-rice-bowls",
            contentVersion: 1,
            mealSlot: "lunch",
            placement: "home_carousel",
            servingCountBucket: "three_to_four",
            costDisplayAvailability: "unavailable",
            completionState: nil,
            elapsedTimeBucket: "under_one_second"
        )

        XCTAssertTrue(recorder.recordWeeklyMealEvent(.weeklyMealCardFocused, metadata: metadata))
        let record = try XCTUnwrap(recorder.records().first)
        XCTAssertEqual(record.operationType, .weeklyMeals)
        XCTAssertEqual(record.weeklyMealEvent, .weeklyMealCardFocused)
        XCTAssertEqual(record.weeklyMealMetadata, metadata)

        let encoded = try XCTUnwrap(String(data: Data(contentsOf: fileURL), encoding: .utf8))
        XCTAssertFalse(encoded.contains("ingredient"))
        XCTAssertFalse(encoded.contains("instruction"))
        XCTAssertFalse(encoded.contains("product"))
        XCTAssertFalse(encoded.contains("https://"))
        XCTAssertFalse(encoded.contains("@"))
    }

    @MainActor
    private func isolatedDefaults() -> UserDefaults {
        let suite = "LocalOperationRecorderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func testRecipe(title: String) -> Recipe {
        Recipe(
            title: title,
            source: .text,
            sourceDetail: "Recorder integration test",
            heroSymbol: "fork.knife",
            servings: 2,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: [Ingredient(name: "Rice", quantity: 1, unit: "cup")]
        )
    }

    private func temporaryFileURL(pathComponents: [String] = []) -> URL {
        var directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalOperationRecorderTests-\(UUID().uuidString)", isDirectory: true)
        for component in pathComponents {
            directory.appendPathComponent(component, isDirectory: true)
        }
        addTeardownBlock {
            var root = directory
            for _ in pathComponents { root.deleteLastPathComponent() }
            try? FileManager.default.removeItem(at: root)
        }
        return directory.appendingPathComponent("observations.json")
    }
}

private final class OperationRecorderTestClock {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(interval)
        lock.unlock()
    }
}

private enum OperationDataStoreTestError: Error { case intentional }

private final class FailingOperationDataStore: LocalOperationDataStoring {
    let failLoad: Bool
    init(failLoad: Bool) { self.failLoad = failLoad }
    func loadData() throws -> Data? {
        if failLoad { throw OperationDataStoreTestError.intentional }
        return nil
    }
    func saveData(_ data: Data) throws { throw OperationDataStoreTestError.intentional }
}

private final class ThreadRecordingOperationDataStore: LocalOperationDataStoring {
    private let lock = NSLock()
    private var data: Data?
    private var recordedThreads: [Bool] = []

    var saveWasMainThread: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return recordedThreads
    }

    func loadData() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func saveData(_ data: Data) throws {
        lock.lock()
        self.data = data
        recordedThreads.append(Thread.isMainThread)
        lock.unlock()
    }
}
