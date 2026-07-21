import Foundation

/// One demand submitted to the bounded retailer-matching pipeline.
///
/// Equivalent raw queries may share one fetch, but every demand retains its
/// complete request and preferences for independent ranking and resolution.
struct RetailerMatchingDemand: Hashable {
    let request: RetailerProductSearchRequest
    let preferences: ShoppingPreferences
    let isExplicitlyExcluded: Bool

    init(
        request: RetailerProductSearchRequest,
        preferences: ShoppingPreferences,
        isExplicitlyExcluded: Bool = false
    ) {
        self.request = request
        self.preferences = preferences
        self.isExplicitlyExcluded = isExplicitlyExcluded
    }
}

/// A request-generation token. Later runtime integration must retain its
/// current token and pass it through `acceptedItems(for:)` before publication.
struct RetailerMatchingGeneration: Codable, Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

enum RetailerMatchingPublicationError: Error, Hashable {
    case staleGeneration(
        completed: RetailerMatchingGeneration,
        current: RetailerMatchingGeneration
    )
}

struct RetailerMatchingBatchItem: Hashable {
    let inputIndex: Int
    let request: RetailerProductSearchRequest
    let resolution: IngredientResolution
}

struct RetailerMatchingBatchResult: Hashable {
    let generation: RetailerMatchingGeneration
    let uniqueFetchGroupCount: Int
    private let orderedItems: [RetailerMatchingBatchItem]

    init(
        generation: RetailerMatchingGeneration,
        items: [RetailerMatchingBatchItem],
        uniqueFetchGroupCount: Int
    ) {
        self.generation = generation
        self.uniqueFetchGroupCount = uniqueFetchGroupCount
        orderedItems = items
    }

    var itemCount: Int { orderedItems.count }

    /// The only item-publication seam. A completed older generation cannot
    /// expose its results as current work.
    func acceptedItems(
        for currentGeneration: RetailerMatchingGeneration
    ) throws -> [RetailerMatchingBatchItem] {
        guard generation == currentGeneration else {
            throw RetailerMatchingPublicationError.staleGeneration(
                completed: generation,
                current: currentGeneration
            )
        }
        return orderedItems
    }
}

/// The identity of same-batch raw catalog work. Quantity and unit are omitted
/// because they affect per-demand ranking rather than candidate retrieval.
struct RetailerCandidateFetchKey: Hashable {
    let retailerID: String
    let storeID: String
    let canonicalQuery: String
    let fulfillmentMethod: FulfillmentMethod
    let preferences: ShoppingPreferences

    init(
        request: RetailerProductSearchRequest,
        preferences: ShoppingPreferences
    ) {
        retailerID = request.retailerID
        storeID = request.storeID
        canonicalQuery = Self.normalizeQuery(request.ingredient.name)
        fulfillmentMethod = request.fulfillmentMethod
        self.preferences = preferences
    }

    static func normalizeQuery(_ query: String) -> String {
        query
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

actor RetailerMatchingBatchService {
    struct Configuration: Hashable {
        let maximumConcurrentFetches: Int

        init(maximumConcurrentFetches: Int = 4) {
            self.maximumConcurrentFetches = Swift.max(1, maximumConcurrentFetches)
        }

        static let `default` = Configuration()
    }

    private struct FetchGroup {
        let key: RetailerCandidateFetchKey
        let representativeRequest: RetailerProductSearchRequest
        var inputIndexes: [Int]
    }

    private struct FetchJob {
        let groupIndex: Int
        let request: RetailerProductSearchRequest
    }

    private struct FetchCompletion {
        let groupIndex: Int
        let fetch: RetailerCandidateFetch
    }

    private let configuration: Configuration

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// Resolves a complete batch with a bounded sliding window of child tasks.
    /// Cancellation throws and never returns a partial publishable result.
    func match(
        _ demands: [RetailerMatchingDemand],
        using engine: RetailerGuideEngine,
        generation: RetailerMatchingGeneration = RetailerMatchingGeneration()
    ) async throws -> RetailerMatchingBatchResult {
        try Task.checkCancellation()
        guard !demands.isEmpty else {
            return RetailerMatchingBatchResult(
                generation: generation,
                items: [],
                uniqueFetchGroupCount: 0
            )
        }

        let grouping = makeFetchGroups(for: demands)
        let groups = grouping.groups
        let groupIndexByInput = grouping.groupIndexByInput
        var fetchesByGroupIndex: [Int: RetailerCandidateFetch] = [:]

        if !groups.isEmpty {
            let jobs = groups.enumerated().map { groupIndex, group in
                FetchJob(
                    groupIndex: groupIndex,
                    request: group.representativeRequest
                )
            }

            try await withThrowingTaskGroup(of: FetchCompletion.self) { taskGroup in
                let initialJobCount = Swift.min(
                    configuration.maximumConcurrentFetches,
                    jobs.count
                )
                var nextJobIndex = initialJobCount

                for job in jobs.prefix(initialJobCount) {
                    taskGroup.addTask {
                        try await Self.execute(job: job, using: engine)
                    }
                }

                while let completion = try await taskGroup.next() {
                    try Task.checkCancellation()
                    fetchesByGroupIndex[completion.groupIndex] = completion.fetch

                    if nextJobIndex < jobs.count {
                        let nextJob = jobs[nextJobIndex]
                        nextJobIndex += 1
                        taskGroup.addTask {
                            try await Self.execute(job: nextJob, using: engine)
                        }
                    }
                }
            }
        }

        try Task.checkCancellation()

        let items = demands.enumerated().map { inputIndex, demand in
            let outcome: IngredientMatchingOutcome
            if demand.isExplicitlyExcluded {
                outcome = .explicitlyExcluded
            } else if let groupIndex = groupIndexByInput[inputIndex],
                      let fetch = fetchesByGroupIndex[groupIndex] {
                outcome = engine.rankCandidates(
                    fetch,
                    for: demand.request,
                    preferences: demand.preferences
                )
            } else {
                // The grouping map is total for every nonexcluded input. Keep
                // an impossible internal mismatch terminal and visible rather
                // than aliasing it to another demand's fetch.
                outcome = .failed(.invalidCandidateData)
            }

            return RetailerMatchingBatchItem(
                inputIndex: inputIndex,
                request: demand.request,
                resolution: ShoppingResolutionService.resolve(
                    IngredientMatchingInput(
                        ingredient: demand.request.ingredient,
                        outcome: outcome
                    )
                )
            )
        }

        try Task.checkCancellation()
        return RetailerMatchingBatchResult(
            generation: generation,
            items: items,
            uniqueFetchGroupCount: groups.count
        )
    }

    private nonisolated static func execute(
        job: FetchJob,
        using engine: RetailerGuideEngine
    ) async throws -> FetchCompletion {
        do {
            try Task.checkCancellation()
            let fetch = try await engine.fetchCandidates(for: job.request)
            try Task.checkCancellation()
            return FetchCompletion(groupIndex: job.groupIndex, fetch: fetch)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return FetchCompletion(
                groupIndex: job.groupIndex,
                fetch: .failed(.transientProviderFailure)
            )
        }
    }

    private func makeFetchGroups(
        for demands: [RetailerMatchingDemand]
    ) -> (groups: [FetchGroup], groupIndexByInput: [Int?]) {
        var groups: [FetchGroup] = []
        var groupIndexByKey: [RetailerCandidateFetchKey: Int] = [:]
        var groupIndexByInput = Array<Int?>(repeating: nil, count: demands.count)

        for (inputIndex, demand) in demands.enumerated() {
            guard !demand.isExplicitlyExcluded else { continue }

            let key = RetailerCandidateFetchKey(
                request: demand.request,
                preferences: demand.preferences
            )
            if let groupIndex = groupIndexByKey[key] {
                groups[groupIndex].inputIndexes.append(inputIndex)
                groupIndexByInput[inputIndex] = groupIndex
            } else {
                let groupIndex = groups.count
                groupIndexByKey[key] = groupIndex
                groupIndexByInput[inputIndex] = groupIndex
                groups.append(
                    FetchGroup(
                        key: key,
                        representativeRequest: demand.request,
                        inputIndexes: [inputIndex]
                    )
                )
            }
        }

        return (groups, groupIndexByInput)
    }
}
