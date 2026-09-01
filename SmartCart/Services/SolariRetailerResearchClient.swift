import Foundation

struct SolariBackendConfiguration: Equatable {
    static let infoDictionaryKey = "SmartCartSolariExperimentBackendURL"
    static let walmartFixtureReplayKey = "SmartCartSolariWalmartFixtureReplay"

    let backendURL: URL
    let walmartExecutionMode: SolariExecutionMode?

    init?(bundle: Bundle = .main) {
        guard let value = bundle.object(forInfoDictionaryKey: Self.infoDictionaryKey) as? String else {
            return nil
        }
        let replayValue = bundle.object(forInfoDictionaryKey: Self.walmartFixtureReplayKey)
        let replayEnabled = (replayValue as? Bool) == true ||
            (replayValue as? String)?.lowercased() == "yes"
        self.init(rawValue: value, walmartFixtureReplayEnabled: replayEnabled)
    }

    init?(rawValue: String, walmartFixtureReplayEnabled: Bool = false) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else { return nil }

        #if DEBUG
        let validScheme = scheme == "https" ||
            (scheme == "http" && (host == "localhost" || host == "127.0.0.1"))
        #else
        let validScheme = scheme == "https"
        #endif
        guard validScheme else { return nil }
        backendURL = url
        #if DEBUG
        walmartExecutionMode = walmartFixtureReplayEnabled ? .recordedFixture : nil
        #else
        walmartExecutionMode = nil
        #endif
    }

    var researchEndpoint: URL {
        backendURL.appending(path: "v1/solari/research")
    }
}

enum SolariResearchRequestBuilder {
    private struct CanonicalRequirement {
        let selectedProductID: String
        let candidateProductIDs: [String]
        let requiredQuantity: Double
        let unit: SolariRequirementUnit
    }

    private static let canonicalRequirements = [
        CanonicalRequirement(
            selectedProductID: "10414680",
            candidateProductIDs: ["10414680"],
            requiredQuantity: 1.5,
            unit: .pound
        ),
        CanonicalRequirement(
            selectedProductID: "10534084",
            candidateProductIDs: ["10534084", "623835750"],
            requiredQuantity: 12,
            unit: .ounce
        ),
        CanonicalRequirement(
            selectedProductID: "10452414",
            candidateProductIDs: ["10452414", "10307238", "47088917"],
            requiredQuantity: 3,
            unit: .ounce
        )
    ]

    /// Returns nil when the matched plan is not the exact bounded internship
    /// demo. Every other Walmart plan continues through normal SmartCart.
    static func makeIfEligible(
        items: [ShoppingListItem],
        retailer: ShoppingRetailer,
        executionMode: SolariExecutionMode,
        now: Date = .now
    ) -> SolariResearchRequest? {
        #if DEBUG
        guard retailer == .walmart,
              executionMode == .recordedFixture else { return nil }
        let waitingItems = items.filter { $0.status == .waiting }
        guard waitingItems.count == canonicalRequirements.count else { return nil }

        var requirements: [SolariShoppingRequirement] = []
        for canonical in canonicalRequirements {
            guard let item = waitingItems.first(where: {
                $0.product.retailerProductID == canonical.selectedProductID
            }),
            let amount = item.requestedAmount,
            approximatelyEqual(amount, canonical.requiredQuantity),
            normalizedUnit(item.ingredient.unit) == canonical.unit else { return nil }

            let products = [item.product] + item.alternatives
            let productsByID = Dictionary(
                products.map { ($0.retailerProductID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            guard Set(productsByID.keys).isSuperset(of: canonical.candidateProductIDs) else {
                return nil
            }
            let candidates = canonical.candidateProductIDs.compactMap { productID -> SolariCandidateReference? in
                guard let product = productsByID[productID],
                      product.retailerID == ShoppingRetailer.walmart.rawValue,
                      product.linkKind == .exactProduct,
                      product.exactURL.absoluteString == "https://www.walmart.com/ip/\(productID)" else {
                    return nil
                }
                return SolariCandidateReference(
                    retailerProductID: productID,
                    sourceURL: product.exactURL
                )
            }
            guard candidates.count == canonical.candidateProductIDs.count else { return nil }

            requirements.append(
                SolariShoppingRequirement(
                    id: item.id,
                    ingredientID: item.ingredient.id,
                    name: bounded(item.ingredient.name, maximumLength: 160),
                    requestedQuantityText: bounded(item.requestedQuantity, maximumLength: 160),
                    requiredQuantity: canonical.requiredQuantity,
                    unit: canonical.unit,
                    candidates: candidates
                )
            )
        }
        guard requirements.allSatisfy({ !$0.name.isEmpty && !$0.requestedQuantityText.isEmpty }) else {
            return nil
        }
        return SolariResearchRequest(
            schemaVersion: SolariRetailerEvidenceSchema.requestVersion,
            requestID: UUID(),
            demoID: SolariRetailerEvidenceSchema.demoID,
            submittedAt: now,
            retailerID: retailer.rawValue,
            executionMode: executionMode,
            storeReference: "walmart-online-no-store-selected",
            requirements: requirements
        )
        #else
        return nil
        #endif
    }

    private static func normalizedUnit(_ value: String) -> SolariRequirementUnit? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "oz", "ounce", "ounces": .ounce
        case "lb", "lbs", "pound", "pounds": .pound
        case "count", "item", "items": .count
        default: nil
        }
    }

    private static func bounded(_ value: String, maximumLength: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 0.000_1 * max(1, abs(lhs), abs(rhs))
    }
}

struct SolariEvidenceValidator {
    var now: Date = .now
    var maximumLiveObservationAge: TimeInterval = 24 * 60 * 60
    var timestampTolerance: TimeInterval = 5 * 60

    func validate(
        _ result: SolariResearchResult,
        for request: SolariResearchRequest
    ) throws -> SolariValidatedResearch {
        guard result.schemaVersion == SolariRetailerEvidenceSchema.resultVersion else {
            throw SolariEvidenceContractError.unknownSchemaVersion
        }
        guard request.schemaVersion == SolariRetailerEvidenceSchema.requestVersion,
              result.requestID == request.requestID,
              request.demoID == SolariRetailerEvidenceSchema.demoID,
              result.demoID == request.demoID,
              result.retailerID == request.retailerID,
              result.executionMode == request.executionMode else {
            throw SolariEvidenceContractError.requestMismatch
        }
        #if !DEBUG
        guard result.executionMode == .live else {
            throw SolariEvidenceContractError.recordedFixtureNotAllowed
        }
        #endif
        guard result.status != .unavailable else {
            throw SolariEvidenceContractError.unavailableResult
        }
        guard result.completedAt <= now.addingTimeInterval(timestampTolerance) else {
            throw SolariEvidenceContractError.invalidCompletionTimestamp
        }
        if result.executionMode == .live,
           result.completedAt < request.submittedAt.addingTimeInterval(-timestampTolerance) {
            throw SolariEvidenceContractError.invalidCompletionTimestamp
        }
        guard result.observations.count <= 6,
              result.decisions.count <= request.requirements.count else {
            throw SolariEvidenceContractError.tooManyResults
        }

        let requirementsByID = Dictionary(uniqueKeysWithValues: request.requirements.map { ($0.id, $0) })
        var observationsByID: [String: SolariRetailerObservation] = [:]
        for observation in result.observations {
            guard observation.schemaVersion == SolariRetailerEvidenceSchema.observationVersion else {
                throw SolariEvidenceContractError.unknownSchemaVersion
            }
            guard observationsByID[observation.observationID] == nil else {
                throw SolariEvidenceContractError.duplicateObservation
            }
            guard let requirement = requirementsByID[observation.requirementID],
                  requirement.candidates.contains(where: {
                      $0.retailerProductID == observation.retailerProductID &&
                          $0.sourceURL.absoluteString == observation.sourceURL.absoluteString
                  }) else {
                throw SolariEvidenceContractError.invalidObservationReference
            }
            guard !observation.observationID.isEmpty,
                  observation.observationID.count <= 100,
                  observation.title.map({
                      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 500
                  }) ?? true,
                  observation.packageDescription.map({ !$0.isEmpty && $0.count <= 160 }) ?? true,
                  observation.packageQuantity.map({ $0.isFinite && $0 > 0 }) ?? true,
                  observation.ambiguityReasons.count <= 8,
                  observation.ambiguityReasons.allSatisfy({ !$0.isEmpty && $0.count <= 300 }) else {
                throw SolariEvidenceContractError.invalidObservation
            }
            if let price = observation.visiblePrice {
                guard price >= 0, observation.currency == "USD" else {
                    throw SolariEvidenceContractError.invalidObservation
                }
            } else if observation.currency != nil {
                throw SolariEvidenceContractError.invalidObservation
            }
            try validateFreshness(observation, mode: result.executionMode, completedAt: result.completedAt)
            observationsByID[observation.observationID] = observation
        }

        var decidedRequirementIDs: Set<UUID> = []
        var computedSubtotal: Decimal = 0
        var computedPricedLineCount = 0
        var computedMissingPriceLineCount = 0
        for decision in result.decisions {
            guard decision.schemaVersion == SolariRetailerEvidenceSchema.decisionVersion else {
                throw SolariEvidenceContractError.unknownSchemaVersion
            }
            guard decidedRequirementIDs.insert(decision.requirementID).inserted else {
                throw SolariEvidenceContractError.duplicateDecision
            }
            guard let requirement = requirementsByID[decision.requirementID],
                  let observation = observationsByID[decision.observationID],
                  let packageQuantity = observation.packageQuantity,
                  let packageUnit = observation.packageUnit,
                  observation.requirementID == decision.requirementID,
                  packageUnit == decision.quantityUnit,
                  decision.confidence == observation.confidence,
                  decision.ambiguityReasons == observation.ambiguityReasons else {
                throw SolariEvidenceContractError.invalidDecisionReference
            }
            guard (1...50).contains(decision.packageCount),
                  approximatelyEqual(decision.requiredQuantity, requirement.requiredQuantity),
                  compatible(requirement.unit.evidenceUnit, decision.quantityUnit),
                  (1...8).contains(decision.rationale.count),
                  decision.rationale.allSatisfy({ !$0.isEmpty && $0.count <= 240 }),
                  decision.substitutionNote.map({ $0.count <= 300 }) ?? true else {
                throw SolariEvidenceContractError.invalidPackageMath
            }
            guard let requiredBase = baseQuantity(requirement.requiredQuantity, unit: requirement.unit.evidenceUnit),
                  let packageBase = baseQuantity(packageQuantity, unit: packageUnit),
                  let decisionScale = unitScale(decision.quantityUnit) else {
                throw SolariEvidenceContractError.invalidPackageMath
            }
            let expectedCoverage = packageQuantity * Double(decision.packageCount)
            let expectedSurplus = (packageBase * Double(decision.packageCount) - requiredBase) / decisionScale
            guard approximatelyEqual(decision.coveredQuantity, expectedCoverage),
                  expectedSurplus >= -0.000_1,
                  approximatelyEqual(decision.surplusQuantity, max(0, expectedSurplus)) else {
                throw SolariEvidenceContractError.invalidPackageMath
            }
            guard decision.proteinGramsPerDollar == nil else {
                throw SolariEvidenceContractError.invalidProteinMath
            }

            if let price = observation.visiblePrice {
                let expectedLineTotal = price * Decimal(decision.packageCount)
                guard let lineTotal = decision.lineTotal,
                      decision.currency == "USD",
                      decimalEqual(lineTotal, expectedLineTotal) else {
                    throw SolariEvidenceContractError.invalidPriceMath
                }
                computedSubtotal += lineTotal
                computedPricedLineCount += 1
            } else {
                guard decision.lineTotal == nil, decision.currency == nil else {
                    throw SolariEvidenceContractError.invalidPriceMath
                }
                computedMissingPriceLineCount += 1
            }
        }

        let computedUnmatchedCount = request.requirements.count - decidedRequirementIDs.count
        guard result.basket.pricedLineCount == computedPricedLineCount,
              result.basket.missingPriceLineCount == computedMissingPriceLineCount,
              result.basket.unmatchedRequirementCount == computedUnmatchedCount else {
            throw SolariEvidenceContractError.invalidBasketSummary
        }
        if computedPricedLineCount > 0 {
            guard let subtotal = result.basket.observedSubtotal,
                  result.basket.currency == "USD",
                  decimalEqual(subtotal, computedSubtotal) else {
                throw SolariEvidenceContractError.invalidBasketSummary
            }
        } else if result.basket.observedSubtotal != nil || result.basket.currency != nil {
            throw SolariEvidenceContractError.invalidBasketSummary
        }

        let actuallyComplete = computedUnmatchedCount == 0 &&
            computedMissingPriceLineCount == 0 &&
            computedPricedLineCount == request.requirements.count
        if result.basket.completeness == .complete && !actuallyComplete {
            throw SolariEvidenceContractError.incompleteBasketClaim
        }
        if result.basket.completeness == .partial && actuallyComplete {
            throw SolariEvidenceContractError.invalidBasketSummary
        }
        guard (result.status == .complete) == (result.basket.completeness == .complete) else {
            throw SolariEvidenceContractError.invalidBasketSummary
        }

        var warnings: [String] = []
        if result.executionMode == .recordedFixture {
            warnings.append("Recorded Walmart prices are historical and stale—not live, local, or guaranteed.")
        }
        if computedUnmatchedCount > 0 {
            warnings.append("\(computedUnmatchedCount) requirement\(computedUnmatchedCount == 1 ? "" : "s") could not be matched to admitted evidence.")
        }
        if computedMissingPriceLineCount > 0 {
            warnings.append("\(computedMissingPriceLineCount) selected product\(computedMissingPriceLineCount == 1 ? " has" : "s have") no visible price, so the subtotal is partial.")
        }
        if result.observations.contains(where: { !$0.ambiguityReasons.isEmpty || $0.confidence != .high }) {
            warnings.append("Some observations are ambiguous or lower confidence. Review them before continuing.")
        }
        return SolariValidatedResearch(result: result, warnings: warnings)
    }

    private func validateFreshness(
        _ observation: SolariRetailerObservation,
        mode: SolariExecutionMode,
        completedAt: Date
    ) throws {
        guard observation.observedAt <= now.addingTimeInterval(timestampTolerance),
              observation.observedAt <= completedAt.addingTimeInterval(timestampTolerance),
              observation.freshness.maxAgeSeconds >= 60,
              observation.freshness.ageSeconds.map({ $0 >= 0 }) ?? true else {
            throw SolariEvidenceContractError.staleObservation
        }
        switch mode {
        case .recordedFixture:
            guard observation.collectionMethod == .seededFixtureReplay,
                  observation.freshness.status == .stale else {
                throw SolariEvidenceContractError.staleObservation
            }
        case .live:
            guard observation.collectionMethod != .seededFixtureReplay,
                  observation.freshness.status == .fresh,
                  observation.observedAt >= now.addingTimeInterval(-maximumLiveObservationAge),
                  observation.freshness.ageSeconds.map({
                      $0 <= min(observation.freshness.maxAgeSeconds, Int(maximumLiveObservationAge))
                  }) ?? false else {
                throw SolariEvidenceContractError.staleObservation
            }
        }
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        guard lhs.isFinite, rhs.isFinite else { return false }
        return abs(lhs - rhs) <= 0.000_1 * max(1, abs(lhs), abs(rhs))
    }

    private func compatible(_ lhs: SolariEvidenceUnit, _ rhs: SolariEvidenceUnit) -> Bool {
        (lhs == .count) == (rhs == .count)
    }

    private func unitScale(_ unit: SolariEvidenceUnit) -> Double? {
        switch unit {
        case .ounce: 1
        case .pound: 16
        case .count: 1
        }
    }

    private func baseQuantity(_ value: Double, unit: SolariEvidenceUnit) -> Double? {
        guard value.isFinite, let scale = unitScale(unit) else { return nil }
        return value * scale
    }

    private func decimalEqual(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        var lhsValue = lhs
        var rhsValue = rhs
        var roundedLHS = Decimal()
        var roundedRHS = Decimal()
        NSDecimalRound(&roundedLHS, &lhsValue, 2, .plain)
        NSDecimalRound(&roundedRHS, &rhsValue, 2, .plain)
        return roundedLHS == roundedRHS
    }
}

enum SolariRetailerResearchClientError: LocalizedError, Equatable {
    case invalidRequest
    case invalidResponse
    case responseTooLarge
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "SmartCart could not safely prepare the Solari request."
        case .invalidResponse: "Solari returned an unreadable evidence response."
        case .responseTooLarge: "Solari returned more retailer evidence than SmartCart accepts."
        case .server(let statusCode): "Solari research is unavailable (HTTP \(statusCode))."
        }
    }
}

struct SolariRetailerResearchClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 45
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func research(
        request contract: SolariResearchRequest,
        configuration: SolariBackendConfiguration,
        now: Date = .now
    ) async throws -> SolariValidatedResearch {
        guard contract.schemaVersion == SolariRetailerEvidenceSchema.requestVersion else {
            throw SolariRetailerResearchClientError.invalidRequest
        }
        var request = URLRequest(url: configuration.researchEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try Self.encoder.encode(contract)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SolariRetailerResearchClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SolariRetailerResearchClientError.server(statusCode: httpResponse.statusCode)
        }
        guard data.count <= SolariRetailerEvidenceSchema.maximumResponseBytes else {
            throw SolariRetailerResearchClientError.responseTooLarge
        }

        let result: SolariResearchResult
        do {
            result = try Self.decoder.decode(SolariResearchResult.self, from: data)
        } catch {
            throw SolariRetailerResearchClientError.invalidResponse
        }
        return try SolariEvidenceValidator(now: now).validate(result, for: contract)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let wholeSeconds = ISO8601DateFormatter()
            wholeSeconds.formatOptions = [.withInternetDateTime]
            if let date = wholeSeconds.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 timestamp."
            )
        }
        return decoder
    }()
}
