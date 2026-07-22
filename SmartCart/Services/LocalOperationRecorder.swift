import Dispatch
import Foundation

enum LocalOperationTerminalEvent: String, Codable, CaseIterable, Hashable, Sendable {
    case handledAutomatically = "operation_handled_automatically"
    case requiredDecision = "operation_required_decision"
    case recovered = "operation_recovered"
    case abandoned = "operation_abandoned"
    case failedUnrecoverably = "operation_failed_unrecoverably"
}

enum LocalOperationType: String, Codable, CaseIterable, Hashable, Sendable {
    case recipeImport = "recipe_import"
    case recipeMutation = "recipe_mutation"
    case recipeLibraryMutation = "recipe_library_mutation"
    case opticalCharacterRecognition = "optical_character_recognition"
    case productMatching = "product_matching"
    case statePersistence = "state_persistence"
    case shoppingTrip = "shopping_trip"
    case retailerPageLoad = "retailer_page_load"
    case barcodeLookup = "barcode_lookup"
    case pantryMutation = "pantry_mutation"
    case shoppingReconciliation = "shopping_reconciliation"
    case mealPrepAggregation = "meal_prep_aggregation"
    case weeklyMeals = "weekly_meals"
}

enum WeeklyMealOperationEvent: String, Codable, CaseIterable, Hashable, Sendable {
    case weeklyMealsViewed
    case weeklyMealCardFocused
    case weeklyMealOpened
    case weeklyMealSaved
    case weeklyMealServingsChanged
    case weeklyMealShopStarted
    case weeklyMealAddedToMealPrep
    case weeklyMealRetailerHandoffStarted
    case weeklyMealShoppingCompleted
}

struct WeeklyMealOperationMetadata: Codable, Equatable, Sendable {
    let collectionID: String
    let recipeID: String?
    let contentVersion: Int?
    let mealSlot: String?
    let placement: String
    let servingCountBucket: String?
    let costDisplayAvailability: String?
    let completionState: String?
    let elapsedTimeBucket: String?
}

enum LocalOperationImportMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case camera
    case photoLibrary = "photo_library"
    case recipeLink = "recipe_link"
    case pastedText = "pasted_text"
    case sharedImages = "shared_images"
    case sharedLink = "shared_link"
    case sharedText = "shared_text"
    case sample
}

enum LocalOperationRetailer: String, Codable, CaseIterable, Hashable, Sendable {
    case walmart
    case target
    case kroger
    case instacart
}

enum LocalOperationFailureCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case invalidInput = "invalid_input"
    case noResult = "no_result"
    case ambiguousResult = "ambiguous_result"
    case offline
    case timedOut = "timed_out"
    case rateLimited = "rate_limited"
    case serviceUnavailable = "service_unavailable"
    case configurationUnavailable = "configuration_unavailable"
    case persistenceUnavailable = "persistence_unavailable"
    case persistenceWriteFailed = "persistence_write_failed"
    case unsupportedStateSchema = "unsupported_state_schema"
    case corruptState = "corrupt_state"
    case cancelledByUser = "cancelled_by_user"
    case discardedByUser = "discarded_by_user"
    case processInterrupted = "process_interrupted"
    case superseded
    case invariantViolation = "invariant_violation"
    case unclassified
}

enum LocalOperationDurationBucket: String, Codable, CaseIterable, Hashable, Sendable {
    case under300Milliseconds = "under_300_ms"
    case underOneSecond = "under_1_s"
    case underFiveSeconds = "under_5_s"
    case underThirtySeconds = "under_30_s"
    case thirtySecondsOrMore = "30_s_or_more"
    case unknown

    static func bucket(for interval: TimeInterval) -> Self {
        guard interval.isFinite, interval >= 0 else { return .unknown }
        switch interval {
        case ..<0.3: return .under300Milliseconds
        case ..<1: return .underOneSecond
        case ..<5: return .underFiveSeconds
        case ..<30: return .underThirtySeconds
        default: return .thirtySecondsOrMore
        }
    }
}

enum LocalOperationRecorderStorageHealth: Equatable, Sendable {
    case available
    case unavailable
}

struct LocalOperationToken: Hashable, Sendable {
    fileprivate let nonce: UUID
}

struct LocalOperationRecord: Codable, Equatable, Sendable {
    let operationType: LocalOperationType
    let importMethod: LocalOperationImportMethod?
    let retailer: LocalOperationRetailer?
    fileprivate(set) var retryCount: Int
    fileprivate(set) var eventName: LocalOperationTerminalEvent?
    fileprivate(set) var failureCategory: LocalOperationFailureCategory?
    fileprivate(set) var durationBucket: LocalOperationDurationBucket?
    let weeklyMealEvent: WeeklyMealOperationEvent?
    let weeklyMealMetadata: WeeklyMealOperationMetadata?
    fileprivate var runtimeToken: LocalOperationToken?
    fileprivate var runtimeStartedAt: Date?

    var isInFlight: Bool { eventName == nil }

    private enum CodingKeys: String, CodingKey {
        case operationType
        case importMethod
        case retailer
        case retryCount
        case eventName
        case failureCategory
        case durationBucket
        case weeklyMealEvent
        case weeklyMealMetadata
    }

    init(
        operationType: LocalOperationType,
        importMethod: LocalOperationImportMethod?,
        retailer: LocalOperationRetailer?,
        retryCount: Int,
        eventName: LocalOperationTerminalEvent?,
        failureCategory: LocalOperationFailureCategory?,
        durationBucket: LocalOperationDurationBucket?,
        runtimeToken: LocalOperationToken?,
        runtimeStartedAt: Date?,
        weeklyMealEvent: WeeklyMealOperationEvent? = nil,
        weeklyMealMetadata: WeeklyMealOperationMetadata? = nil
    ) {
        self.operationType = operationType
        self.importMethod = importMethod
        self.retailer = retailer
        self.retryCount = retryCount
        self.eventName = eventName
        self.failureCategory = failureCategory
        self.durationBucket = durationBucket
        self.runtimeToken = runtimeToken
        self.runtimeStartedAt = runtimeStartedAt
        self.weeklyMealEvent = weeklyMealEvent
        self.weeklyMealMetadata = weeklyMealMetadata
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        operationType = try values.decode(LocalOperationType.self, forKey: .operationType)
        importMethod = try values.decodeIfPresent(LocalOperationImportMethod.self, forKey: .importMethod)
        retailer = try values.decodeIfPresent(LocalOperationRetailer.self, forKey: .retailer)
        retryCount = try values.decode(Int.self, forKey: .retryCount)
        eventName = try values.decodeIfPresent(LocalOperationTerminalEvent.self, forKey: .eventName)
        failureCategory = try values.decodeIfPresent(
            LocalOperationFailureCategory.self,
            forKey: .failureCategory
        )
        durationBucket = try values.decodeIfPresent(
            LocalOperationDurationBucket.self,
            forKey: .durationBucket
        )
        weeklyMealEvent = try values.decodeIfPresent(
            WeeklyMealOperationEvent.self,
            forKey: .weeklyMealEvent
        )
        weeklyMealMetadata = try values.decodeIfPresent(
            WeeklyMealOperationMetadata.self,
            forKey: .weeklyMealMetadata
        )
        runtimeToken = nil
        runtimeStartedAt = nil
    }
}

protocol LocalOperationDataStoring: AnyObject {
    func loadData() throws -> Data?
    func saveData(_ data: Data) throws
}

protocol LocalOperationObserving: Sendable {
    @discardableResult
    func start(
        _ operationType: LocalOperationType,
        importMethod: LocalOperationImportMethod?,
        retailer: LocalOperationRetailer?
    ) -> LocalOperationToken

    func recordRetry(
        _ token: LocalOperationToken,
        failureCategory: LocalOperationFailureCategory?
    )

    func finish(
        _ token: LocalOperationToken,
        event: LocalOperationTerminalEvent,
        failureCategory: LocalOperationFailureCategory?
    )

    func setRecordingEnabled(_ enabled: Bool)
    func clear()
    func recoverStaleInFlightOperations()
    func recordWeeklyMealEvent(
        _ event: WeeklyMealOperationEvent,
        metadata: WeeklyMealOperationMetadata
    )
}

final class AsyncLocalOperationObserver: LocalOperationObserving, @unchecked Sendable {
    static let shared = AsyncLocalOperationObserver()

    private let recorder: LocalOperationRecorder
    private let queue: DispatchQueue

    init(
        recorder: LocalOperationRecorder = LocalOperationRecorder(),
        queueLabel: String = "com.blakestudio.smartcart.local-operation-observer"
    ) {
        self.recorder = recorder
        queue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    @discardableResult
    func start(
        _ operationType: LocalOperationType,
        importMethod: LocalOperationImportMethod? = nil,
        retailer: LocalOperationRetailer? = nil
    ) -> LocalOperationToken {
        let token = LocalOperationToken(nonce: UUID())
        queue.async { [recorder] in
            _ = recorder.start(
                token: token,
                operationType,
                importMethod: importMethod,
                retailer: retailer
            )
        }
        return token
    }

    func recordRetry(
        _ token: LocalOperationToken,
        failureCategory: LocalOperationFailureCategory? = nil
    ) {
        queue.async { [recorder] in
            _ = recorder.recordRetry(token, failureCategory: failureCategory)
        }
    }

    func finish(
        _ token: LocalOperationToken,
        event: LocalOperationTerminalEvent,
        failureCategory: LocalOperationFailureCategory? = nil
    ) {
        queue.async { [recorder] in
            _ = recorder.finish(token, event: event, failureCategory: failureCategory)
        }
    }

    func setRecordingEnabled(_ enabled: Bool) {
        queue.async { [recorder] in recorder.setRecordingEnabled(enabled) }
    }

    func clear() {
        queue.async { [recorder] in _ = recorder.clear() }
    }

    func recoverStaleInFlightOperations() {
        queue.async { [recorder] in _ = recorder.recoverStaleInFlightOperations() }
    }

    func recordWeeklyMealEvent(
        _ event: WeeklyMealOperationEvent,
        metadata: WeeklyMealOperationMetadata
    ) {
        queue.async { [recorder] in
            _ = recorder.recordWeeklyMealEvent(event, metadata: metadata)
        }
    }

    func waitUntilIdle() {
        queue.sync {}
    }
}

final class AtomicLocalOperationDataStore: LocalOperationDataStoring {
    let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadData() throws -> Data? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    func saveData(_ data: Data) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

final class LocalOperationRecorder: @unchecked Sendable {
    private struct Snapshot: Codable, Equatable {
        static let currentSchemaVersion = 1

        var schemaVersion = currentSchemaVersion
        var recordingEnabled = true
        var records: [LocalOperationRecord] = []
    }

    private let store: any LocalOperationDataStoring
    private let capacity: Int
    private let now: () -> Date
    private let lock = NSLock()

    private var snapshot: Snapshot
    private var storageHealthStorage: LocalOperationRecorderStorageHealth

    convenience init(
        fileURL: URL = LocalOperationRecorder.defaultFileURL(),
        capacity: Int = 500,
        recordingEnabled: Bool? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            store: AtomicLocalOperationDataStore(fileURL: fileURL),
            capacity: capacity,
            recordingEnabled: recordingEnabled,
            now: now
        )
    }

    init(
        store: any LocalOperationDataStoring,
        capacity: Int = 500,
        recordingEnabled: Bool? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.capacity = max(1, capacity)
        self.now = now

        let loaded: Snapshot
        let loadSucceeded: Bool
        do {
            if let data = try store.loadData() {
                let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
                loaded = decoded.schemaVersion == Snapshot.currentSchemaVersion
                    ? decoded
                    : Snapshot(recordingEnabled: false)
            } else {
                loaded = Snapshot()
            }
            loadSucceeded = true
        } catch {
            loaded = Snapshot(recordingEnabled: false)
            loadSucceeded = false
        }

        var normalized = Self.normalized(loaded, capacity: self.capacity)
        if let recordingEnabled { normalized.recordingEnabled = recordingEnabled }
        snapshot = normalized
        storageHealthStorage = loadSucceeded ? .available : .unavailable

        let recovered = recoverStaleLocked()
        if !loadSucceeded || recordingEnabled != nil || normalized != loaded || recovered > 0 {
            persistLocked()
        }
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return baseURL
            .appendingPathComponent("SmartCart", isDirectory: true)
            .appendingPathComponent("operation-observations.json")
    }

    var isRecordingEnabled: Bool { locked { snapshot.recordingEnabled } }
    var storageHealth: LocalOperationRecorderStorageHealth { locked { storageHealthStorage } }
    func records() -> [LocalOperationRecord] { locked { snapshot.records } }

    func record(for token: LocalOperationToken) -> LocalOperationRecord? {
        locked { snapshot.records.first { $0.runtimeToken == token } }
    }

    @discardableResult
    func start(
        _ operationType: LocalOperationType,
        importMethod: LocalOperationImportMethod? = nil,
        retailer: LocalOperationRetailer? = nil
    ) -> LocalOperationToken? {
        let token = LocalOperationToken(nonce: UUID())
        return start(
            token: token,
            operationType,
            importMethod: importMethod,
            retailer: retailer
        ) ? token : nil
    }

    @discardableResult
    fileprivate func start(
        token: LocalOperationToken,
        _ operationType: LocalOperationType,
        importMethod: LocalOperationImportMethod? = nil,
        retailer: LocalOperationRetailer? = nil
    ) -> Bool {
        locked {
            guard snapshot.recordingEnabled,
                  makeRoomForNewRecordLocked(),
                  !snapshot.records.contains(where: { $0.runtimeToken == token })
            else { return false }

            snapshot.records.append(
                LocalOperationRecord(
                    operationType: operationType,
                    importMethod: importMethod,
                    retailer: retailer,
                    retryCount: 0,
                    eventName: nil,
                    failureCategory: nil,
                    durationBucket: nil,
                    runtimeToken: token,
                    runtimeStartedAt: now()
                )
            )
            persistLocked()
            return true
        }
    }

    @discardableResult
    func recordRetry(
        _ token: LocalOperationToken,
        failureCategory: LocalOperationFailureCategory? = nil
    ) -> Bool {
        locked {
            guard snapshot.recordingEnabled,
                  let index = snapshot.records.firstIndex(where: {
                      $0.runtimeToken == token && $0.isInFlight
                  }) else { return false }
            if snapshot.records[index].retryCount < Int.max {
                snapshot.records[index].retryCount += 1
            }
            if let failureCategory { snapshot.records[index].failureCategory = failureCategory }
            persistLocked()
            return true
        }
    }

    @discardableResult
    func finish(
        _ token: LocalOperationToken,
        event: LocalOperationTerminalEvent,
        failureCategory: LocalOperationFailureCategory? = nil
    ) -> Bool {
        locked {
            guard snapshot.recordingEnabled,
                  let index = snapshot.records.firstIndex(where: {
                      $0.runtimeToken == token && $0.isInFlight
                  }) else { return false }

            let normalizedEvent: LocalOperationTerminalEvent =
                event == .handledAutomatically && snapshot.records[index].retryCount > 0
                    ? .recovered
                    : event
            let elapsed = snapshot.records[index].runtimeStartedAt.map {
                now().timeIntervalSince($0)
            }
            snapshot.records[index].eventName = normalizedEvent
            if let failureCategory { snapshot.records[index].failureCategory = failureCategory }
            snapshot.records[index].durationBucket = elapsed.map(LocalOperationDurationBucket.bucket)
                ?? .unknown
            trimTerminalRecordsToCapacityLocked()
            persistLocked()
            return true
        }
    }

    @discardableResult
    func recordWeeklyMealEvent(
        _ event: WeeklyMealOperationEvent,
        metadata: WeeklyMealOperationMetadata
    ) -> Bool {
        locked {
            guard snapshot.recordingEnabled, makeRoomForNewRecordLocked() else { return false }
            snapshot.records.append(
                LocalOperationRecord(
                    operationType: .weeklyMeals,
                    importMethod: nil,
                    retailer: nil,
                    retryCount: 0,
                    eventName: .handledAutomatically,
                    failureCategory: nil,
                    durationBucket: .unknown,
                    runtimeToken: nil,
                    runtimeStartedAt: nil,
                    weeklyMealEvent: event,
                    weeklyMealMetadata: metadata
                )
            )
            trimTerminalRecordsToCapacityLocked()
            persistLocked()
            return true
        }
    }

    @discardableResult
    func recoverStaleInFlightOperations() -> Int {
        locked {
            let recovered = recoverStaleLocked()
            if recovered > 0 { persistLocked() }
            return recovered
        }
    }

    func setRecordingEnabled(_ enabled: Bool) {
        locked {
            let changed = snapshot.recordingEnabled != enabled
            snapshot.recordingEnabled = enabled
            if changed || storageHealthStorage == .unavailable { persistLocked() }
        }
    }

    @discardableResult
    func clear() -> Bool {
        locked {
            snapshot.records.removeAll(keepingCapacity: false)
            persistLocked()
            return storageHealthStorage == .available
        }
    }

    private func recoverStaleLocked() -> Int {
        guard snapshot.recordingEnabled else { return 0 }
        var recovered = 0
        for index in snapshot.records.indices
        where snapshot.records[index].isInFlight && snapshot.records[index].runtimeToken == nil {
            snapshot.records[index].eventName = .abandoned
            snapshot.records[index].failureCategory = .processInterrupted
            snapshot.records[index].durationBucket = .unknown
            recovered += 1
        }
        trimTerminalRecordsToCapacityLocked()
        return recovered
    }

    private func makeRoomForNewRecordLocked() -> Bool {
        while snapshot.records.count >= capacity {
            guard let terminalIndex = snapshot.records.firstIndex(where: { !$0.isInFlight }) else {
                return false
            }
            snapshot.records.remove(at: terminalIndex)
        }
        return true
    }

    private func trimTerminalRecordsToCapacityLocked() {
        while snapshot.records.count > capacity,
              let terminalIndex = snapshot.records.firstIndex(where: { !$0.isInFlight }) {
            snapshot.records.remove(at: terminalIndex)
        }
    }

    private func persistLocked() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try store.saveData(encoder.encode(snapshot))
            storageHealthStorage = .available
        } catch {
            storageHealthStorage = .unavailable
        }
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    private static func normalized(_ source: Snapshot, capacity: Int) -> Snapshot {
        var result = source
        while result.records.count > capacity,
              let terminalIndex = result.records.firstIndex(where: { !$0.isInFlight }) {
            result.records.remove(at: terminalIndex)
        }
        return result
    }
}
