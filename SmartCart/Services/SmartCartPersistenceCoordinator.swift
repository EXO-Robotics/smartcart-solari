import Foundation

/// Serializes every post-load SmartCart save and stamps exact durable
/// successors. The synchronous compatibility entry point preserves current
/// AppModel rollback and navigation timing while encoding and disk I/O execute
/// on the dedicated store queue.
final class SmartCartPersistenceCoordinator: @unchecked Sendable {
    private struct Request {
        let sequence: UInt64
        let snapshot: SmartCartPersistedState
    }

    private struct PendingAutosave {
        let request: Request
        let workItem: DispatchWorkItem
    }

    private let store: any SmartCartStateStoring
    private let defaultAutosaveDelay: TimeInterval
    private let coordinationQueue: DispatchQueue
    private let storeQueue: DispatchQueue
    private let coordinationKey = DispatchSpecificKey<UInt8>()
    private let storeKey = DispatchSpecificKey<UInt8>()

    // Coordination-queue state.
    private var requestSequence: UInt64
    private var pendingAutosave: PendingAutosave?
    private var isShutdown = false

    // Store-queue state.
    private var durableRevision: UInt64
    private var highestEnqueuedSequence: UInt64
    private var lastWriteError: Error?
    private var latestFailedRequest: Request?
    private var latestCommittedSequence: UInt64?
    private var staleConflictRevision: UInt64?

    init(
        store: any SmartCartStateStoring,
        autosaveDelay: TimeInterval = 0.35,
        initialRevision: UInt64 = 0
    ) {
        self.store = store
        defaultAutosaveDelay = max(0, autosaveDelay)
        requestSequence = initialRevision
        durableRevision = initialRevision
        highestEnqueuedSequence = initialRevision

        let identifier = UUID().uuidString
        coordinationQueue = DispatchQueue(
            label: "com.smartcart.persistence.coordination.\(identifier)",
            qos: .userInitiated
        )
        storeQueue = DispatchQueue(
            label: "com.smartcart.persistence.store.\(identifier)",
            qos: .userInitiated
        )
        coordinationQueue.setSpecific(key: coordinationKey, value: 1)
        storeQueue.setSpecific(key: storeKey, value: 1)
    }

    var latestDurableRevision: UInt64 {
        withStore { durableRevision }
    }

    var pendingAutosaveSequence: UInt64? {
        withCoordination { pendingAutosave?.request.sequence }
    }

    /// Current AppModel compatibility boundary. It remains caller-synchronous,
    /// but the actual store operation is always submitted asynchronously to
    /// the dedicated store queue before this method waits for completion.
    @discardableResult
    func saveCompatibility(
        _ snapshot: SmartCartPersistedState
    ) throws -> UInt64 {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<UInt64, Error>?
        try withCoordination {
            try ensureActive()
            cancelPendingAutosave()
            let request = try makeRequest(snapshot)
            enqueue(request) { completion in
                result = completion
                semaphore.signal()
            }
        }
        semaphore.wait()
        guard let result else {
            throw SmartCartPersistenceCoordinatorError.missingCompletion
        }
        return try result.get()
    }

    /// Nonblocking critical boundary available to later slices. Once accepted,
    /// cancellation of the awaiting task does not reorder or abandon the write.
    @discardableResult
    func saveCritical(
        _ snapshot: SmartCartPersistedState
    ) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try withCoordination {
                    try ensureActive()
                    cancelPendingAutosave()
                    let request = try makeRequest(snapshot)
                    enqueue(request) { continuation.resume(with: $0) }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Coalesces ordinary delayed saves. The request sequence is process-local;
    /// the persisted revision advances only when the surviving snapshot commits.
    @discardableResult
    func requestAutosave(
        _ snapshot: SmartCartPersistedState,
        delay: TimeInterval? = nil
    ) throws -> UInt64 {
        try withCoordination {
            try ensureActive()
            cancelPendingAutosave()
            let request = try makeRequest(snapshot)
            let workItem = DispatchWorkItem { [weak self] in
                self?.beginAutosave(sequence: request.sequence)
            }
            pendingAutosave = PendingAutosave(
                request: request,
                workItem: workItem
            )
            coordinationQueue.asyncAfter(
                deadline: .now() + max(0, delay ?? defaultAutosaveDelay),
                execute: workItem
            )
            return request.sequence
        }
    }

    /// Immediately submits the latest pending autosave, or waits for all work
    /// already ahead of the barrier and reports its terminal failure.
    @discardableResult
    func flush() async throws -> UInt64? {
        try await withCheckedThrowingContinuation { continuation in
            withCoordination {
                if let pendingAutosave {
                    pendingAutosave.workItem.cancel()
                    self.pendingAutosave = nil
                    enqueue(pendingAutosave.request) {
                        continuation.resume(with: $0.map(Optional.some))
                    }
                } else {
                    storeQueue.async { [self] in
                        if let lastWriteError {
                            continuation.resume(throwing: lastWriteError)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }

    /// Retries only the newest eligible failed snapshot. A retry after a known
    /// success is idempotent and simply returns the durable revision.
    @discardableResult
    func retryLatest() async throws -> UInt64? {
        try await withCheckedThrowingContinuation { continuation in
            storeQueue.async { [self] in
                if let staleConflictRevision {
                    continuation.resume(
                        throwing: SmartCartPersistenceCoordinatorError
                            .staleConflictRequiresReload(
                                currentRevision: staleConflictRevision
                            )
                    )
                    return
                }
                guard let request = latestFailedRequest else {
                    continuation.resume(returning: latestCommittedSequence == nil ? nil : durableRevision)
                    return
                }
                let result = perform(request)
                continuation.resume(with: result.map(Optional.some))
            }
        }
    }

    /// Cancels delayed work, rejects new requests, and waits for every already
    /// accepted store operation to reach a terminal result.
    func shutdown() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            withCoordination {
                isShutdown = true
                cancelPendingAutosave()
                storeQueue.async { [self] in
                    if let lastWriteError {
                        continuation.resume(throwing: lastWriteError)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }

    private func beginAutosave(sequence: UInt64) {
        guard let pendingAutosave,
              pendingAutosave.request.sequence == sequence,
              !isShutdown else {
            return
        }
        self.pendingAutosave = nil
        enqueue(pendingAutosave.request, completion: nil)
    }

    private func enqueue(
        _ request: Request,
        completion: ((Result<UInt64, Error>) -> Void)?
    ) {
        storeQueue.async { [self] in
            let result: Result<UInt64, Error>
            if request.sequence < highestEnqueuedSequence {
                result = .failure(
                    SmartCartPersistenceCoordinatorError.supersededRequest(
                        attempted: request.sequence,
                        latest: highestEnqueuedSequence
                    )
                )
            } else {
                highestEnqueuedSequence = request.sequence
                result = perform(request)
            }
            completion?(result)
        }
    }

    private func perform(
        _ request: Request
    ) -> Result<UInt64, Error> {
        if let staleConflictRevision {
            let error = SmartCartPersistenceCoordinatorError
                .staleConflictRequiresReload(
                    currentRevision: staleConflictRevision
                )
            lastWriteError = error
            latestFailedRequest = nil
            return .failure(error)
        }
        guard durableRevision < UInt64.max else {
            let error = SmartCartPersistenceCoordinatorError.revisionExhausted
            lastWriteError = error
            latestFailedRequest = request
            return .failure(error)
        }

        let committedRevision = durableRevision + 1
        var durableSnapshot = request.snapshot
        durableSnapshot.schemaVersion = SmartCartPersistedState.currentSchemaVersion
        durableSnapshot.persistenceRevision = committedRevision

        do {
            try store.save(
                durableSnapshot,
                expectedRevision: durableRevision
            )
            durableRevision = committedRevision
            latestCommittedSequence = request.sequence
            latestFailedRequest = nil
            staleConflictRevision = nil
            lastWriteError = nil
            return .success(committedRevision)
        } catch {
            if let storeError = error as? SmartCartStateStoreError,
               case .staleRevision(_, let currentRevision) = storeError {
                staleConflictRevision = currentRevision
                latestFailedRequest = nil
            }
            if let storeError = error as? SmartCartStateStoreError,
               case .staleRevision = storeError,
               let winner = try? store.load(),
               winner.schemaVersion == SmartCartPersistedState.currentSchemaVersion {
                durableRevision = max(durableRevision, winner.persistenceRevision)
            }
            lastWriteError = error
            if staleConflictRevision == nil,
               request.sequence >= highestEnqueuedSequence {
                latestFailedRequest = request
            }
            return .failure(error)
        }
    }

    private func makeRequest(
        _ snapshot: SmartCartPersistedState
    ) throws -> Request {
        guard requestSequence < UInt64.max else {
            throw SmartCartPersistenceCoordinatorError.revisionExhausted
        }
        requestSequence += 1
        return Request(sequence: requestSequence, snapshot: snapshot)
    }

    private func ensureActive() throws {
        guard !isShutdown else {
            throw SmartCartPersistenceCoordinatorError.shutdown
        }
    }

    private func cancelPendingAutosave() {
        pendingAutosave?.workItem.cancel()
        pendingAutosave = nil
    }

    private func withCoordination<T>(
        _ operation: () throws -> T
    ) rethrows -> T {
        if DispatchQueue.getSpecific(key: coordinationKey) != nil {
            return try operation()
        }
        return try coordinationQueue.sync(execute: operation)
    }

    private func withStore<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: storeKey) != nil {
            return operation()
        }
        return storeQueue.sync(execute: operation)
    }
}

enum SmartCartPersistenceCoordinatorError: LocalizedError, Equatable {
    case revisionExhausted
    case shutdown
    case supersededRequest(attempted: UInt64, latest: UInt64)
    case staleConflictRequiresReload(currentRevision: UInt64)
    case missingCompletion

    var errorDescription: String? {
        switch self {
        case .revisionExhausted:
            "SmartCart persistence revision is exhausted; no data was overwritten."
        case .shutdown:
            "SmartCart persistence is shutting down and cannot accept another save."
        case .supersededRequest(let attempted, let latest):
            "SmartCart rejected request \(attempted) because newer request \(latest) already exists."
        case .staleConflictRequiresReload(let currentRevision):
            "SmartCart found newer durable revision \(currentRevision). Reload before retrying this whole-state snapshot."
        case .missingCompletion:
            "SmartCart persistence ended without a save result."
        }
    }
}
