import CryptoKit
import Foundation
import Observation

struct SolariBackendConfiguration: Equatable, Hashable {
    static let backendInfoDictionaryKey = "SmartCartSolariExperimentBackendURL"
    static let demoRetailerInfoDictionaryKey = "SmartCartSolariDemoRetailerBaseURL"
    static let debugFixtureInfoDictionaryKey = "SmartCartSolariDebugFixtureReplay"

    let backendURL: URL
    let demoRetailerBaseURL: URL
    let debugFixtureReplayEnabled: Bool

    init?(bundle: Bundle = .main) {
        guard let backend = bundle.object(forInfoDictionaryKey: Self.backendInfoDictionaryKey) as? String,
              let demo = bundle.object(forInfoDictionaryKey: Self.demoRetailerInfoDictionaryKey) as? String else {
            return nil
        }
        let fixtureValue = bundle.object(forInfoDictionaryKey: Self.debugFixtureInfoDictionaryKey)
        let fixtureEnabled = (fixtureValue as? Bool) == true ||
            (fixtureValue as? String)?.lowercased() == "yes"
        self.init(
            backendRawValue: backend,
            demoRetailerRawValue: demo,
            debugFixtureReplayEnabled: fixtureEnabled
        )
    }

    init?(
        backendRawValue: String,
        demoRetailerRawValue: String,
        debugFixtureReplayEnabled: Bool = false
    ) {
        guard let backend = Self.safeURL(backendRawValue, allowsLocalhost: Self.allowsLocalhostBackend),
              let demo = Self.safeURL(demoRetailerRawValue, allowsLocalhost: false) else { return nil }
        backendURL = backend
        demoRetailerBaseURL = demo
        #if DEBUG
        self.debugFixtureReplayEnabled = debugFixtureReplayEnabled
        #else
        self.debugFixtureReplayEnabled = false
        #endif
    }

    var challengeEndpoint: URL { backendURL.appending(path: "v1/solari/access/challenges") }
    var attestationEndpoint: URL { backendURL.appending(path: "v1/solari/access/attestations") }
    var researchEndpoint: URL { backendURL.appending(path: "v1/solari/research") }

    func sourceURL(for productID: String) -> URL? {
        guard SolariResearchRequestBuilder.supportedProductIDs.contains(productID) else { return nil }
        return demoRetailerBaseURL
            .appending(path: "retailer-v4")
            .appending(path: "product")
            .appending(path: "\(productID).html")
    }

    private static var allowsLocalhostBackend: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func safeURL(_ rawValue: String, allowsLocalhost: Bool) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty else { return nil }
        let isLocalhost = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (allowsLocalhost && scheme == "http" && isLocalhost) else {
            return nil
        }
        components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        return components.url
    }
}

enum SolariResearchRequestBuilder {
    static let supportedProductIDs: Set<String> = [
        "dg4-chicken-value-3lb", "dg4-chicken-organic-1-5lb", "dg4-chicken-free-range-3lb",
        "dg4-penne-value-16oz", "dg4-penne-glutenfree-24oz",
        "dg4-olive-oil-value-17floz", "dg4-olive-oil-organic-17floz", "dg4-olive-oil-smooth-16floz",
        "dg4-heavy-cream-value-16floz", "dg4-heavy-cream-organic-16floz",
        "dg4-parmesan-value-6oz", "dg4-parmesan-frigo-5oz", "dg4-parmesan-kraft-6oz",
        "dg4-garlic-bulb-8ct", "dg4-garlic-peeled-6oz", "dg4-garlic-minced-8oz",
        "dg4-lemon-each-1ct", "dg4-lemon-organic-2lb", "dg4-parsley-bunch-1ct"
    ]

    static let demoCandidateIDsByMatchedProductID: [String: [String]] = [
        "10414680": ["dg4-chicken-value-3lb", "dg4-chicken-organic-1-5lb", "dg4-chicken-free-range-3lb"],
        "145781250": ["dg4-chicken-value-3lb", "dg4-chicken-organic-1-5lb", "dg4-chicken-free-range-3lb"],
        "19400236": ["dg4-chicken-value-3lb", "dg4-chicken-organic-1-5lb", "dg4-chicken-free-range-3lb"],
        "10534084": ["dg4-penne-value-16oz", "dg4-penne-glutenfree-24oz"],
        "623835750": ["dg4-penne-value-16oz", "dg4-penne-glutenfree-24oz"],
        "10315102": ["dg4-olive-oil-value-17floz", "dg4-olive-oil-organic-17floz", "dg4-olive-oil-smooth-16floz"],
        "51630343": ["dg4-olive-oil-value-17floz", "dg4-olive-oil-organic-17floz", "dg4-olive-oil-smooth-16floz"],
        "176946682": ["dg4-olive-oil-value-17floz", "dg4-olive-oil-organic-17floz", "dg4-olive-oil-smooth-16floz"],
        "10450339": ["dg4-heavy-cream-value-16floz", "dg4-heavy-cream-organic-16floz"],
        "53986354": ["dg4-heavy-cream-value-16floz", "dg4-heavy-cream-organic-16floz"],
        "10452414": ["dg4-parmesan-value-6oz", "dg4-parmesan-frigo-5oz", "dg4-parmesan-kraft-6oz"],
        "10307238": ["dg4-parmesan-value-6oz", "dg4-parmesan-frigo-5oz", "dg4-parmesan-kraft-6oz"],
        "47088917": ["dg4-parmesan-value-6oz", "dg4-parmesan-frigo-5oz", "dg4-parmesan-kraft-6oz"],
        "44391100": ["dg4-garlic-bulb-8ct"],
        "44391024": ["dg4-garlic-peeled-6oz", "dg4-garlic-minced-8oz"],
        "131236350": ["dg4-garlic-peeled-6oz", "dg4-garlic-minced-8oz"],
        "41752773": ["dg4-lemon-each-1ct"],
        "51259193": ["dg4-lemon-organic-2lb"],
        "44391167": ["dg4-parsley-bunch-1ct"]
    ]

    private static let packageUnitByProductID: [String: SolariEvidenceUnit] = [
        "dg4-chicken-value-3lb": .gram, "dg4-chicken-organic-1-5lb": .gram, "dg4-chicken-free-range-3lb": .gram,
        "dg4-penne-value-16oz": .gram, "dg4-penne-glutenfree-24oz": .gram,
        "dg4-olive-oil-value-17floz": .milliliter, "dg4-olive-oil-organic-17floz": .milliliter, "dg4-olive-oil-smooth-16floz": .milliliter,
        "dg4-heavy-cream-value-16floz": .milliliter, "dg4-heavy-cream-organic-16floz": .milliliter,
        "dg4-parmesan-value-6oz": .gram, "dg4-parmesan-frigo-5oz": .gram, "dg4-parmesan-kraft-6oz": .gram,
        "dg4-garlic-bulb-8ct": .count, "dg4-garlic-peeled-6oz": .gram, "dg4-garlic-minced-8oz": .gram,
        "dg4-lemon-each-1ct": .count, "dg4-lemon-organic-2lb": .gram, "dg4-parsley-bunch-1ct": .count
    ]

    private static let semanticAliasesByProductID: [String: [String]] = [
        "dg4-chicken-value-3lb": ["chicken"],
        "dg4-penne-value-16oz": ["pasta", "penne", "rigatoni", "spaghetti", "fettuccine", "noodle"],
        "dg4-olive-oil-value-17floz": ["olive oil"],
        "dg4-heavy-cream-value-16floz": ["heavy cream", "whipping cream", "cream"],
        "dg4-parmesan-value-6oz": ["parmesan"],
        "dg4-garlic-bulb-8ct": ["garlic"], "dg4-garlic-peeled-6oz": ["garlic"],
        "dg4-lemon-each-1ct": ["lemon"], "dg4-lemon-organic-2lb": ["lemon"],
        "dg4-parsley-bunch-1ct": ["parsley"]
    ]

    static func evaluate(
        items: [ShoppingListItem],
        configuration: SolariBackendConfiguration?,
        servingCount: Int,
        now: Date = .now,
        requestID: UUID = UUID()
    ) -> SolariResearchEligibility {
        guard let configuration else { return .ineligible([.configurationUnavailable]) }
        let waitingItems = items.filter { $0.status == .waiting }
        guard !waitingItems.isEmpty else { return .ineligible([.noWaitingItems]) }
        guard Set(waitingItems.map(\.id)).count == waitingItems.count,
              Set(waitingItems.map(\.ingredient.id)).count == waitingItems.count else {
            return .ineligible([.duplicateRequirement])
        }
        let deterministicWaitingItems = waitingItems.sorted { $0.id.uuidString < $1.id.uuidString }

        var requirements: [SolariShoppingRequirement] = []
        var skippedLines: [SolariSkippedResearchLine] = []
        var sourceURLs: [String: URL] = [:]
        var allCandidateIDs: [String] = []
        let originalSelections = deterministicWaitingItems.map(Self.originalSelection)

        for item in deterministicWaitingItems {
            let name = bounded(item.ingredient.name, maximumLength: 160)
            let requestedQuantity = bounded(item.requestedQuantity, maximumLength: 160)
            guard !name.isEmpty,
                  !requestedQuantity.isEmpty,
                  !isSemanticQuantity(requestedQuantity),
                  let amount = item.requestedAmount, amount.isFinite, amount > 0 else {
                skippedLines.append(skipped(item, name: name, reason: .invalidQuantity(name)))
                continue
            }
            guard case .exact(let canonical) = QuantityEngine.canonicalize(
                value: Decimal(amount),
                unit: item.ingredient.unit
            ), canonical.certainty == .exact,
              let unit = requirementUnit(for: canonical.dimension) else {
                skippedLines.append(skipped(
                    item,
                    name: name,
                    reason: .unsupportedUnit(name: name, unit: item.ingredient.unit)
                ))
                continue
            }
            let canonicalValue = NSDecimalNumber(decimal: canonical.value).doubleValue
            guard canonicalValue.isFinite, canonicalValue > 0, canonicalValue <= 10_000_000 else {
                skippedLines.append(skipped(item, name: name, reason: .invalidQuantity(name)))
                continue
            }
            guard item.product.linkKind == .exactProduct,
                  !supportedProductIDs.contains(item.product.retailerProductID) else {
                skippedLines.append(skipped(item, name: name, reason: .missingExactCandidate(name)))
                continue
            }
            guard let mappedCandidates = demoCandidateIDsByMatchedProductID[item.product.retailerProductID] else {
                skippedLines.append(skipped(item, name: name, reason: .unsupportedProduct(name)))
                continue
            }
            let foldedName = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard let aliases = semanticAliasesByProductID[mappedCandidates[0]],
                  aliases.contains(where: { foldedName.localizedStandardContains($0) }) else {
                skippedLines.append(skipped(item, name: name, reason: .unsupportedProduct(name)))
                continue
            }
            let candidateIDs = mappedCandidates.filter { packageUnitByProductID[$0] == unit.evidenceUnit }
            guard !candidateIDs.isEmpty else {
                skippedLines.append(skipped(item, name: name, reason: .incompatiblePackageDimension(name)))
                continue
            }
            guard candidateIDs.allSatisfy({ !allCandidateIDs.contains($0) }) else {
                skippedLines.append(skipped(item, name: name, reason: .overlappingCatalogCoverage(name)))
                continue
            }
            guard requirements.count < SolariRetailerEvidenceSchema.maximumRequirements else {
                skippedLines.append(skipped(
                    item,
                    name: name,
                    reason: .requirementLimitReached(SolariRetailerEvidenceSchema.maximumRequirements)
                ))
                continue
            }
            guard allCandidateIDs.count + candidateIDs.count <= SolariRetailerEvidenceSchema.maximumObservations else {
                skippedLines.append(skipped(
                    item,
                    name: name,
                    reason: .observationLimitReached(SolariRetailerEvidenceSchema.maximumObservations)
                ))
                continue
            }
            allCandidateIDs.append(contentsOf: candidateIDs)
            var lineSourceURLs: [String: URL] = [:]
            for productID in candidateIDs {
                guard let sourceURL = configuration.sourceURL(for: productID) else {
                    return .ineligible([.configurationUnavailable])
                }
                lineSourceURLs[productID] = sourceURL
            }
            sourceURLs.merge(lineSourceURLs, uniquingKeysWith: { existing, _ in existing })
            requirements.append(
                SolariShoppingRequirement(
                    id: item.id,
                    ingredientID: item.ingredient.id,
                    name: name,
                    requestedQuantityText: requestedQuantity,
                    requiredQuantity: canonicalValue,
                    unit: unit,
                    candidateProductIDs: candidateIDs
                )
            )
        }

        guard !requirements.isEmpty else {
            return .ineligible(skippedLines.map(\.reason))
        }
        guard Set(allCandidateIDs).count == allCandidateIDs.count else {
            return .ineligible([.duplicateCandidate])
        }
        #if DEBUG
        let executionMode: SolariExecutionMode = configuration.debugFixtureReplayEnabled ? .recordedFixture : .live
        #else
        let executionMode: SolariExecutionMode = .live
        #endif
        let request = SolariResearchRequest(
            schemaVersion: SolariRetailerEvidenceSchema.requestVersion,
            requestID: requestID,
            demoID: SolariRetailerEvidenceSchema.demoID,
            submittedAt: now,
            retailerID: SolariRetailerEvidenceSchema.retailerID,
            executionMode: executionMode,
            storeReference: SolariRetailerEvidenceSchema.storeReference,
            optimizationPolicy: .fixedV4,
            requirements: requirements
        )
        let admittedServingCount = max(0, servingCount)
        let fingerprint = planFingerprint(
            request: request,
            originalSelections: originalSelections,
            skippedLines: skippedLines,
            servingCount: admittedServingCount
        )
        return .eligible(
            SolariResearchPlan(
                configuration: configuration,
                request: request,
                fingerprint: fingerprint,
                sourceURLsByProductID: sourceURLs,
                originalSmartCartSelections: originalSelections,
                skippedLines: skippedLines,
                totalWaitingCount: waitingItems.count,
                servingCount: admittedServingCount
            )
        )
    }

    static func matchesCurrentPlan(
        _ plan: SolariResearchPlan,
        items: [ShoppingListItem],
        servingCount: Int
    ) -> Bool {
        switch evaluate(
            items: items,
            configuration: plan.configuration,
            servingCount: servingCount,
            now: plan.request.submittedAt,
            requestID: plan.request.requestID
        ) {
        case .eligible(let current): current.fingerprint == plan.fingerprint
        case .ineligible: false
        }
    }

    static func refreshedPlan(
        from plan: SolariResearchPlan,
        now: Date = .now,
        requestID: UUID = UUID()
    ) -> SolariResearchPlan {
        let previous = plan.request
        let refreshedRequest = SolariResearchRequest(
            schemaVersion: previous.schemaVersion,
            requestID: requestID,
            demoID: previous.demoID,
            submittedAt: now,
            retailerID: previous.retailerID,
            executionMode: previous.executionMode,
            storeReference: previous.storeReference,
            optimizationPolicy: previous.optimizationPolicy,
            requirements: previous.requirements
        )
        return SolariResearchPlan(
            configuration: plan.configuration,
            request: refreshedRequest,
            fingerprint: plan.fingerprint,
            sourceURLsByProductID: plan.sourceURLsByProductID,
            originalSmartCartSelections: plan.originalSmartCartSelections,
            skippedLines: plan.skippedLines,
            totalWaitingCount: plan.totalWaitingCount,
            servingCount: plan.servingCount
        )
    }

    private static func planFingerprint(
        request: SolariResearchRequest,
        originalSelections: [SolariOriginalSmartCartSelection],
        skippedLines: [SolariSkippedResearchLine],
        servingCount: Int
    ) -> String {
        struct FingerprintInput: Encodable {
            let version: String
            let demoID: String
            let retailerID: String
            let storeReference: String
            let executionMode: SolariExecutionMode
            let optimizationPolicy: SolariOptimizationPolicy
            let servingCount: Int
            let requirements: [SolariShoppingRequirement]
            let originalSelections: [SolariOriginalSmartCartSelection]
            let skippedLines: [SolariSkippedResearchLine]
        }
        let input = FingerprintInput(
            version: "smartcart-solari-plan-fingerprint-v4",
            demoID: request.demoID,
            retailerID: request.retailerID,
            storeReference: request.storeReference,
            executionMode: request.executionMode,
            optimizationPolicy: request.optimizationPolicy,
            servingCount: servingCount,
            requirements: request.requirements,
            originalSelections: originalSelections.sorted {
                $0.requirementID.uuidString < $1.requirementID.uuidString
            },
            skippedLines: skippedLines
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(input)
        return "solari-plan-v4:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func requirementUnit(for dimension: QuantityDimension) -> SolariRequirementUnit? {
        switch dimension {
        case .mass: .gram
        case .volume: .milliliter
        case .count: .count
        case .package, .nonQuantitative, .unknown: nil
        }
    }

    private static func isSemanticQuantity(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["for frying", "to taste", "as needed"].contains { normalized.contains($0) }
    }

    private static func originalSelection(_ item: ShoppingListItem) -> SolariOriginalSmartCartSelection {
        SolariOriginalSmartCartSelection(
            requirementID: item.id,
            ingredientID: item.ingredient.id,
            ingredientName: item.ingredient.name,
            ingredientUnit: item.ingredient.unit,
            requestedQuantity: item.requestedQuantity,
            requestedAmount: item.requestedAmount,
            retailerID: item.product.retailerID,
            retailerProductID: item.product.retailerProductID
        )
    }

    private static func skipped(
        _ item: ShoppingListItem,
        name: String,
        reason: SolariResearchIneligibilityReason
    ) -> SolariSkippedResearchLine {
        SolariSkippedResearchLine(id: item.id, ingredientID: item.ingredient.id, name: name, reason: reason)
    }

    private static func bounded(_ value: String, maximumLength: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }
}

enum SolariOriginalSmartCartContinuation {
    static func permitsFinalization(
        plan: SolariResearchPlan,
        research: SolariValidatedResearch,
        items: [ShoppingListItem],
        servingCount: Int
    ) -> Bool {
        let result = research.result
        let handoff = SolariEvidenceHandoff(result: result)
        guard research.planFingerprint == plan.fingerprint,
              result.demoID == SolariRetailerEvidenceSchema.demoID,
              result.retailerID == SolariRetailerEvidenceSchema.retailerID,
              !handoff.transfersToConfiguredRetailer,
              Set(handoff.selectedSourceURLs).isSubset(of: Set(plan.sourceURLsByProductID.values)),
              SolariResearchRequestBuilder.matchesCurrentPlan(
                  plan,
                  items: items,
                  servingCount: servingCount
              ) else { return false }

        let currentSelections = items
            .filter { $0.status == .waiting }
            .map {
                SolariOriginalSmartCartSelection(
                    requirementID: $0.id,
                    ingredientID: $0.ingredient.id,
                    ingredientName: $0.ingredient.name,
                    ingredientUnit: $0.ingredient.unit,
                    requestedQuantity: $0.requestedQuantity,
                    requestedAmount: $0.requestedAmount,
                    retailerID: $0.product.retailerID,
                    retailerProductID: $0.product.retailerProductID
                )
            }
            .sorted { $0.requirementID.uuidString < $1.requirementID.uuidString }
        let admittedSelections = plan.originalSmartCartSelections.sorted {
            $0.requirementID.uuidString < $1.requirementID.uuidString
        }
        return currentSelections == admittedSelections && currentSelections.count == plan.totalWaitingCount &&
            currentSelections.allSatisfy { !SolariResearchRequestBuilder.supportedProductIDs.contains($0.retailerProductID) }
    }
}

struct SolariEvidenceValidator {
    var now: Date = .now
    var maximumLiveObservationAge: TimeInterval = 24 * 60 * 60
    var timestampTolerance: TimeInterval = 5 * 60
    var freshnessAgeTolerance: TimeInterval = 5

    func validate(_ result: SolariResearchResult, for plan: SolariResearchPlan) throws -> SolariValidatedResearch {
        let request = plan.request
        guard result.schemaVersion == SolariRetailerEvidenceSchema.resultVersion,
              result.observations.allSatisfy({ $0.schemaVersion == SolariRetailerEvidenceSchema.observationVersion }),
              result.decisions.allSatisfy({ $0.schemaVersion == SolariRetailerEvidenceSchema.decisionVersion }) else {
            throw SolariEvidenceContractError.unknownSchemaVersion
        }
        guard request.schemaVersion == SolariRetailerEvidenceSchema.requestVersion,
              result.requestID == request.requestID,
              result.demoID == request.demoID,
              result.retailerID == request.retailerID,
              result.executionMode == .live,
              request.executionMode == .live else { throw SolariEvidenceContractError.requestMismatch }
        guard result.status != .unavailable else { throw SolariEvidenceContractError.unavailableResult }
        guard result.completedAt <= now.addingTimeInterval(timestampTolerance),
              result.completedAt >= request.submittedAt.addingTimeInterval(-timestampTolerance) else {
            throw SolariEvidenceContractError.invalidCompletionTimestamp
        }
        let submittedCandidateIDs = request.requirements.flatMap(\.candidateProductIDs)
        let submittedObservationCount = submittedCandidateIDs.count
        guard Set(request.requirements.map(\.id)).count == request.requirements.count,
              Set(request.requirements.map(\.ingredientID)).count == request.requirements.count,
              request.requirements.allSatisfy({
                  !$0.name.isEmpty && $0.name.count <= 160 &&
                      !$0.requestedQuantityText.isEmpty && $0.requestedQuantityText.count <= 160 &&
                      $0.requiredQuantity.isFinite && $0.requiredQuantity > 0 && $0.requiredQuantity <= 10_000_000 &&
                      (1...SolariRetailerEvidenceSchema.maximumCandidatesPerRequirement).contains($0.candidateProductIDs.count) &&
                      Set($0.candidateProductIDs).count == $0.candidateProductIDs.count
              }),
              Set(submittedCandidateIDs).count == submittedCandidateIDs.count,
              Set(plan.sourceURLsByProductID.keys) == Set(submittedCandidateIDs) else {
            throw SolariEvidenceContractError.invalidObservationReference
        }
        guard (1...SolariRetailerEvidenceSchema.maximumRequirements).contains(request.requirements.count),
              submittedObservationCount <= SolariRetailerEvidenceSchema.maximumObservations,
              result.observations.count == submittedObservationCount,
              result.decisions.count == request.requirements.count,
              result.observations.count <= SolariRetailerEvidenceSchema.maximumObservations else {
            throw SolariEvidenceContractError.tooManyResults
        }
        guard result.optimizer.method == .sandbox,
              result.optimizer.algorithmVersion == "relative-surplus-premium-dp-v1",
              result.optimizer.objective == .minimizeAggregateRelativeSurplus,
              result.optimizer.authority == .sandbox,
              result.optimizer.verification == .smartCartPolicyInvariants,
              result.optimizer.policyInvariantsVerified,
              result.provenance.browser == .browser,
              result.provenance.sandbox == .sandbox,
              !result.provenance.fixtureReplay,
              result.provenance.resourceCleanup.browser == .enforcedBeforeResponse,
              result.provenance.resourceCleanup.sandbox == .enforcedBeforeResponse,
              result.provenance.accessBoundary == .appleAppAttest,
              result.trust.priceClaim == .observedNotGuaranteed,
              !result.trust.accountAccessed,
              !result.trust.cartModified,
              !result.trust.checkoutAutomated,
              result.trust.userControlsHandoff,
              !result.trust.limitations.isEmpty,
              request.optimizationPolicy == .fixedV4 else { throw SolariEvidenceContractError.invalidProvenance }

        let requirementsByID = Dictionary(uniqueKeysWithValues: request.requirements.map { ($0.id, $0) })
        var observationsByID: [String: SolariRetailerObservation] = [:]
        for observation in result.observations {
            guard observationsByID[observation.observationID] == nil else {
                throw SolariEvidenceContractError.duplicateObservation
            }
            guard let requirement = requirementsByID[observation.requirementID],
                  requirement.candidateProductIDs.contains(observation.retailerProductID),
                  plan.sourceURLsByProductID[observation.retailerProductID] == observation.sourceURL else {
                throw SolariEvidenceContractError.invalidObservationReference
            }
            guard isLowercaseEvidenceID(observation.observationID),
                  observation.title.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 500 }) ?? true,
                  observation.packageDescription.map({ !$0.isEmpty && $0.count <= 160 }) ?? true,
                  observation.packageQuantity.map({ $0.isFinite && $0 > 0 }) ?? true,
                  observation.ambiguityReasons.count <= 8,
                  observation.ambiguityReasons.allSatisfy({ !$0.isEmpty && $0.count <= 300 }),
                  observation.proteinGramsPerPackage == nil,
                  observation.collectionMethod == .controlledDemo,
                  observation.location == .controlledDemo,
                  observation.catalogEra == "current-v4",
                  observation.syntheticPrice else {
                throw SolariEvidenceContractError.invalidObservation
            }
            if let price = observation.visiblePrice {
                guard price >= 0, observation.currency == "USD" else { throw SolariEvidenceContractError.invalidObservation }
            } else if observation.currency != nil {
                throw SolariEvidenceContractError.invalidObservation
            }
            let actualAgeSeconds = now.timeIntervalSince(observation.observedAt)
            let ageAtCompletionSeconds = result.completedAt.timeIntervalSince(observation.observedAt)
            guard observation.observedAt <= now.addingTimeInterval(timestampTolerance),
                  observation.observedAt <= result.completedAt.addingTimeInterval(timestampTolerance),
                  observation.freshness.status == .fresh,
                  observation.freshness.maxAgeSeconds >= 60,
                  let claimedAgeSeconds = observation.freshness.ageSeconds,
                  claimedAgeSeconds >= 0,
                  actualAgeSeconds >= -timestampTolerance,
                  ageAtCompletionSeconds >= -freshnessAgeTolerance,
                  actualAgeSeconds <= maximumLiveObservationAge + freshnessAgeTolerance,
                  actualAgeSeconds <= Double(observation.freshness.maxAgeSeconds) + freshnessAgeTolerance,
                  abs(max(0, ageAtCompletionSeconds) - Double(claimedAgeSeconds)) <= freshnessAgeTolerance,
                  Double(claimedAgeSeconds) <= min(
                      Double(observation.freshness.maxAgeSeconds),
                      maximumLiveObservationAge
                  ) + freshnessAgeTolerance else {
                throw SolariEvidenceContractError.staleObservation
            }
            observationsByID[observation.observationID] = observation
        }
        for requirement in request.requirements {
            let observedCandidateIDs = Set(result.observations.lazy
                .filter { $0.requirementID == requirement.id }
                .map(\.retailerProductID))
            guard observedCandidateIDs == Set(requirement.candidateProductIDs) else {
                throw SolariEvidenceContractError.invalidObservationReference
            }
        }

        var decidedRequirementIDs: Set<UUID> = []
        var computedSubtotal: Decimal = 0
        var selectedAggregateRelativeSurplus = 0.0
        var priced = 0
        var unpriced = 0
        for decision in result.decisions {
            guard decidedRequirementIDs.insert(decision.requirementID).inserted else {
                throw SolariEvidenceContractError.duplicateDecision
            }
            guard let requirement = requirementsByID[decision.requirementID],
                  let observation = observationsByID[decision.observationID],
                  let packageQuantity = observation.packageQuantity,
                  let packageUnit = observation.packageUnit,
                  observation.requirementID == decision.requirementID,
                  observation.retailerProductID == decision.retailerProductID,
                  packageUnit == decision.quantityUnit,
                  decision.confidence == observation.confidence,
                  decision.ambiguityReasons == observation.ambiguityReasons else {
                throw SolariEvidenceContractError.invalidDecisionReference
            }
            guard (1...10_000).contains(decision.packageCount),
                  approximatelyEqual(decision.requiredQuantity, requirement.requiredQuantity),
                  requirement.unit.evidenceUnit == decision.quantityUnit,
                  (1...8).contains(decision.rationale.count),
                  decision.rationale.allSatisfy({ !$0.isEmpty && $0.count <= 240 }),
                  decision.substitutionNote.map({
                      !$0.isEmpty && $0.count <= 300 && observation.ambiguityReasons.contains($0)
                  }) ?? true else {
                throw SolariEvidenceContractError.invalidPackageMath
            }
            guard packageUnit == requirement.unit.evidenceUnit else {
                throw SolariEvidenceContractError.invalidPackageMath
            }
            let expectedCoverage = packageQuantity * Double(decision.packageCount)
            let expectedSurplus = expectedCoverage - requirement.requiredQuantity
            let expectedRelativeSurplus = expectedSurplus / requirement.requiredQuantity
            guard approximatelyEqual(decision.coveredQuantity, expectedCoverage),
                  expectedSurplus >= -0.000_1,
                  approximatelyEqual(decision.surplusQuantity, max(0, expectedSurplus)),
                  approximatelyEqual(decision.relativeSurplus, max(0, expectedRelativeSurplus)) else {
                throw SolariEvidenceContractError.invalidPackageMath
            }
            selectedAggregateRelativeSurplus += max(0, expectedRelativeSurplus)
            guard decision.proteinGramsPerDollar == nil else { throw SolariEvidenceContractError.invalidProteinMath }
            if let price = observation.visiblePrice {
                guard let lineTotal = decision.lineTotal,
                      decision.currency == "USD",
                      decimalEqual(lineTotal, price * Decimal(decision.packageCount)) else {
                    throw SolariEvidenceContractError.invalidPriceMath
                }
                computedSubtotal += lineTotal
                priced += 1
            } else {
                guard decision.lineTotal == nil, decision.currency == nil else { throw SolariEvidenceContractError.invalidPriceMath }
                unpriced += 1
            }
        }

        let unmatched = request.requirements.count - decidedRequirementIDs.count
        guard result.basket.pricedLineCount == priced,
              result.basket.missingPriceLineCount == unpriced,
              result.basket.unmatchedRequirementCount == unmatched else {
            throw SolariEvidenceContractError.invalidBasketSummary
        }
        if priced > 0 {
            guard let subtotal = result.basket.observedSubtotal,
                  result.basket.currency == "USD",
                  decimalEqual(subtotal, computedSubtotal) else { throw SolariEvidenceContractError.invalidBasketSummary }
        } else if result.basket.observedSubtotal != nil || result.basket.currency != nil {
            throw SolariEvidenceContractError.invalidBasketSummary
        }
        let complete = unmatched == 0 && unpriced == 0 && priced == request.requirements.count
        guard (result.status == .complete) == (result.basket.completeness == .complete) else {
            throw SolariEvidenceContractError.invalidBasketSummary
        }
        if result.basket.completeness == .complete && !complete { throw SolariEvidenceContractError.incompleteBasketClaim }
        if result.basket.completeness == .partial && complete { throw SolariEvidenceContractError.invalidBasketSummary }
        guard complete,
              result.status == .complete,
              result.basket.completeness == .complete,
              let selectedSubtotal = result.basket.observedSubtotal else {
            throw SolariEvidenceContractError.incompleteBasketClaim
        }

        let cheapest = try cheapestAdequateReference(
            requirements: request.requirements,
            observations: Array(observationsByID.values)
        )
        let premium = selectedSubtotal - cheapest.subtotal
        let avoidedSurplus = cheapest.aggregateRelativeSurplus - selectedAggregateRelativeSurplus
        guard premium >= 0,
              premium <= request.optimizationPolicy.maxPremiumOverCheapest,
              avoidedSurplus >= -0.000_1,
              decimalEqual(result.comparison.cheapestAdequateSubtotal, cheapest.subtotal),
              decimalEqual(result.comparison.selectedSubtotal, selectedSubtotal),
              decimalEqual(result.comparison.premiumOverCheapest, premium),
              decimalEqual(result.comparison.maxPremiumOverCheapest, request.optimizationPolicy.maxPremiumOverCheapest),
              approximatelyEqual(result.comparison.cheapestAggregateRelativeSurplus, cheapest.aggregateRelativeSurplus),
              approximatelyEqual(result.comparison.selectedAggregateRelativeSurplus, selectedAggregateRelativeSurplus),
              approximatelyEqual(result.comparison.relativeSurplusAvoided, max(0, avoidedSurplus)),
              result.comparison.currency == request.optimizationPolicy.currency else {
            throw SolariEvidenceContractError.invalidComparison
        }

        var warnings = result.trust.limitations
        if unmatched > 0 { warnings.append("\(unmatched) shopping requirement could not be matched to admitted evidence.") }
        if unpriced > 0 { warnings.append("\(unpriced) selected product has no visible price, so the subtotal is partial.") }
        if result.observations.contains(where: { !$0.ambiguityReasons.isEmpty || $0.confidence != .high }) {
            warnings.append("Some observations are ambiguous or lower confidence. Review them before continuing.")
        }
        return SolariValidatedResearch(
            result: result,
            warnings: Array(Set(warnings)).sorted(),
            planFingerprint: plan.fingerprint
        )
    }

    private func cheapestAdequateReference(
        requirements: [SolariShoppingRequirement],
        observations: [SolariRetailerObservation]
    ) throws -> (subtotal: Decimal, aggregateRelativeSurplus: Double) {
        var subtotal: Decimal = 0
        var aggregateRelativeSurplus = 0.0
        for requirement in requirements {
            let requiredQuantity = requirement.requiredQuantity
            guard requiredQuantity.isFinite, requiredQuantity > 0 else { throw SolariEvidenceContractError.invalidComparison }
            let candidates = observations.filter { $0.requirementID == requirement.id }
            let adequate = candidates.compactMap { observation -> (id: String, total: Decimal, surplus: Double)? in
                guard let packageQuantity = observation.packageQuantity,
                      let packageUnit = observation.packageUnit,
                      packageUnit == requirement.unit.evidenceUnit,
                      packageQuantity > 0,
                      let price = observation.visiblePrice,
                      observation.currency == "USD" else { return nil }
                let packageCount = max(1, Int(ceil(requiredQuantity / packageQuantity)))
                return (
                    observation.retailerProductID,
                    price * Decimal(packageCount),
                    max(0, packageQuantity * Double(packageCount) - requiredQuantity) / requiredQuantity
                )
            }
            guard adequate.count == requirement.candidateProductIDs.count,
                  let cheapest = adequate.min(by: {
                      if $0.total != $1.total { return $0.total < $1.total }
                      return $0.id < $1.id
                  }) else {
                throw SolariEvidenceContractError.invalidComparison
            }
            subtotal += cheapest.total
            aggregateRelativeSurplus += cheapest.surplus
        }
        return (subtotal, aggregateRelativeSurplus)
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs.isFinite && rhs.isFinite && abs(lhs - rhs) <= 0.000_1 * max(1, abs(lhs), abs(rhs))
    }

    private func isLowercaseEvidenceID(_ value: String) -> Bool {
        value.range(
            of: "^[a-z0-9][a-z0-9-]{0,119}$",
            options: .regularExpression
        ) != nil
    }

    private func decimalEqual(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        var lhs = lhs
        var rhs = rhs
        var roundedLHS = Decimal()
        var roundedRHS = Decimal()
        NSDecimalRound(&roundedLHS, &lhs, 2, .plain)
        NSDecimalRound(&roundedRHS, &rhs, 2, .plain)
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
        case .invalidRequest: "SmartCart could not safely prepare the bounded Solari request."
        case .invalidResponse: "Solari returned an unreadable evidence response."
        case .responseTooLarge: "Solari returned more retailer evidence than SmartCart accepts."
        case .server(let statusCode): "Solari research is unavailable (HTTP \(statusCode))."
        }
    }
}

struct SolariAppAttestAuthorization: Equatable {
    let keyID: String
    let challengeID: UUID
    let assertion: Data
}

struct SolariAppAttestResearchEnvelope: Codable, Equatable {
    static let schemaVersion = "solari-app-attest-research-envelope-v1"

    let schemaVersion: String
    let challengeID: UUID
    let keyID: String
    let assertionObject: String
    let payloadBase64: String

    init(payload: Data, authorization: SolariAppAttestAuthorization) {
        schemaVersion = Self.schemaVersion
        challengeID = authorization.challengeID
        keyID = authorization.keyID
        assertionObject = authorization.assertion.base64EncodedString()
        payloadBase64 = payload.base64EncodedString()
    }
}

protocol SolariResearchAuthorizing {
    func authorization(forExactResearchBody body: Data, configuration: SolariBackendConfiguration) async throws -> SolariAppAttestAuthorization
    func authorizationWasRejected(statusCode: Int) async
}

extension SolariResearchAuthorizing {
    func authorizationWasRejected(statusCode: Int) async {}
}

struct SolariRetailerResearchClient {
    static let requestTimeoutInterval: TimeInterval = 75
    static let resourceTimeoutInterval: TimeInterval = 90

    private let session: URLSession
    private let authorizer: any SolariResearchAuthorizing

    init(session: URLSession? = nil, authorizer: (any SolariResearchAuthorizing)? = nil) {
        self.session = session ?? Self.ephemeralSession()
        self.authorizer = authorizer ?? SolariAppAttestClient.shared
    }

    func research(plan: SolariResearchPlan, now: Date = .now) async throws -> SolariValidatedResearch {
        guard plan.request.schemaVersion == SolariRetailerEvidenceSchema.requestVersion else {
            throw SolariRetailerResearchClientError.invalidRequest
        }
        let body = try Self.encoder.encode(plan.request)
        let authorization = try await authorizer.authorization(
            forExactResearchBody: body,
            configuration: plan.configuration
        )
        let request = try Self.researchRequest(
            exactBody: body,
            authorization: authorization,
            endpoint: plan.configuration.researchEndpoint
        )

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SolariRetailerResearchClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                await authorizer.authorizationWasRejected(statusCode: response.statusCode)
            }
            throw SolariRetailerResearchClientError.server(statusCode: response.statusCode)
        }
        guard data.count <= SolariRetailerEvidenceSchema.maximumResponseBytes else {
            throw SolariRetailerResearchClientError.responseTooLarge
        }
        let result: SolariResearchResult
        do { result = try Self.decoder.decode(SolariResearchResult.self, from: data) }
        catch { throw SolariRetailerResearchClientError.invalidResponse }
        return try SolariEvidenceValidator(now: now).validate(result, for: plan)
    }

    static func researchRequest(
        exactBody: Data,
        authorization: SolariAppAttestAuthorization,
        endpoint: URL
    ) throws -> URLRequest {
        guard SolariAppAttestClient.isValidKeyID(authorization.keyID),
              !authorization.assertion.isEmpty else {
            throw SolariRetailerResearchClientError.invalidRequest
        }
        let envelope = SolariAppAttestResearchEnvelope(payload: exactBody, authorization: authorization)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = requestTimeoutInterval
        request.httpBody = try encoder.encode(envelope)
        return request
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
            let whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
            if let date = whole.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO-8601 timestamp.")
        }
        return decoder
    }()

    private static func ephemeralSession() -> URLSession {
        URLSession(configuration: ephemeralSessionConfiguration())
    }

    static func ephemeralSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = requestTimeoutInterval
        configuration.timeoutIntervalForResource = resourceTimeoutInterval
        configuration.waitsForConnectivity = false
        return configuration
    }
}

struct SolariValidatedResearchCache {
    struct Entry {
        let research: SolariValidatedResearch
        let expiresAt: Date
    }

    private(set) var entries: [String: Entry] = [:]
    var timeToLive: TimeInterval = 2 * 60
    var maximumEntries = 8

    mutating func value(for fingerprint: String, now: Date = .now, bypass: Bool = false) -> SolariValidatedResearch? {
        entries = entries.filter { $0.value.expiresAt > now }
        guard !bypass else {
            entries.removeValue(forKey: fingerprint)
            return nil
        }
        return entries[fingerprint]?.research
    }

    mutating func insert(_ research: SolariValidatedResearch, for fingerprint: String, now: Date = .now) {
        entries = entries.filter { $0.value.expiresAt > now }
        if entries.count >= maximumEntries, let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[fingerprint] = Entry(research: research, expiresAt: now.addingTimeInterval(timeToLive))
    }
}

@MainActor
@Observable
final class SolariResearchStore {
    @ObservationIgnored private var cache = SolariValidatedResearchCache()
    @ObservationIgnored private let client: SolariRetailerResearchClient

    init(client: SolariRetailerResearchClient = SolariRetailerResearchClient()) {
        self.client = client
    }

    func research(plan: SolariResearchPlan, refresh: Bool = false, now: Date = .now) async throws -> SolariValidatedResearch {
        if let cached = cache.value(for: plan.fingerprint, now: now, bypass: refresh) { return cached }
        let research: SolariValidatedResearch
        #if DEBUG
        if plan.request.executionMode == .recordedFixture {
            research = try SolariDebugRecordedFixture.make(for: plan)
        } else {
            research = try await client.research(plan: plan, now: now)
        }
        #else
        research = try await client.research(plan: plan, now: now)
        #endif
        cache.insert(research, for: plan.fingerprint, now: now)
        return research
    }
}

#if DEBUG
enum SolariDebugRecordedFixture {
    private struct Product {
        let id: String
        let title: String
        let packageDescription: String
        let packageQuantity: Double
        let packageUnit: SolariEvidenceUnit
        let price: Decimal
    }

    private static let products: [String: Product] = [
        "dg4-chicken-value-3lb": Product(id: "dg4-chicken-value-3lb", title: "Demo Chicken Breasts — Value", packageDescription: "3 lb synthetic package", packageQuantity: 1_360.777_11, packageUnit: .gram, price: 9.47),
        "dg4-chicken-organic-1-5lb": Product(id: "dg4-chicken-organic-1-5lb", title: "Demo Chicken Breasts — Organic", packageDescription: "1.5 lb synthetic package", packageQuantity: 680.388_555, packageUnit: .gram, price: 8.76),
        "dg4-chicken-free-range-3lb": Product(id: "dg4-chicken-free-range-3lb", title: "Demo Chicken Breasts — Free Range", packageDescription: "3 lb synthetic package", packageQuantity: 1_360.777_11, packageUnit: .gram, price: 13.92),
        "dg4-penne-value-16oz": Product(id: "dg4-penne-value-16oz", title: "Demo Penne Pasta — Value", packageDescription: "16 oz synthetic box", packageQuantity: 453.592_37, packageUnit: .gram, price: 1.24),
        "dg4-penne-glutenfree-24oz": Product(id: "dg4-penne-glutenfree-24oz", title: "Demo Penne Pasta — Gluten Free", packageDescription: "24 oz synthetic box", packageQuantity: 680.388_555, packageUnit: .gram, price: 11.98),
        "dg4-olive-oil-value-17floz": Product(id: "dg4-olive-oil-value-17floz", title: "Demo Extra Virgin Olive Oil — Value", packageDescription: "17 fl oz synthetic bottle", packageQuantity: 502.750_002_562_5, packageUnit: .milliliter, price: 6.12),
        "dg4-olive-oil-organic-17floz": Product(id: "dg4-olive-oil-organic-17floz", title: "Demo Extra Virgin Olive Oil — Organic", packageDescription: "17 fl oz synthetic bottle", packageQuantity: 502.750_002_562_5, packageUnit: .milliliter, price: 7.36),
        "dg4-olive-oil-smooth-16floz": Product(id: "dg4-olive-oil-smooth-16floz", title: "Demo Extra Virgin Olive Oil — Smooth", packageDescription: "16 fl oz synthetic bottle", packageQuantity: 473.176_473, packageUnit: .milliliter, price: 6.75),
        "dg4-heavy-cream-value-16floz": Product(id: "dg4-heavy-cream-value-16floz", title: "Demo Heavy Whipping Cream — Value", packageDescription: "16 fl oz synthetic carton", packageQuantity: 473.176_473, packageUnit: .milliliter, price: 2.96),
        "dg4-heavy-cream-organic-16floz": Product(id: "dg4-heavy-cream-organic-16floz", title: "Demo Heavy Whipping Cream — Organic", packageDescription: "16 fl oz synthetic carton", packageQuantity: 473.176_473, packageUnit: .milliliter, price: 5.87),
        "dg4-parmesan-value-6oz": Product(id: "dg4-parmesan-value-6oz", title: "Demo Finely Shredded Parmesan — Value", packageDescription: "6 oz synthetic package", packageQuantity: 170.097_138_75, packageUnit: .gram, price: 2.08),
        "dg4-parmesan-frigo-5oz": Product(id: "dg4-parmesan-frigo-5oz", title: "Demo Shredded Parmesan — Cup", packageDescription: "5 oz synthetic package", packageQuantity: 141.747_615_625, packageUnit: .gram, price: 3.28),
        "dg4-parmesan-kraft-6oz": Product(id: "dg4-parmesan-kraft-6oz", title: "Demo Finely Shredded Parmesan — Premium", packageDescription: "6 oz synthetic package", packageQuantity: 170.097_138_75, packageUnit: .gram, price: 4.98),
        "dg4-garlic-bulb-8ct": Product(id: "dg4-garlic-bulb-8ct", title: "Demo Fresh Whole Garlic Bulb", packageDescription: "8 count synthetic package", packageQuantity: 8, packageUnit: .count, price: 0.78),
        "dg4-garlic-peeled-6oz": Product(id: "dg4-garlic-peeled-6oz", title: "Demo Fresh Peeled Garlic", packageDescription: "6 oz synthetic package", packageQuantity: 170.097_138_75, packageUnit: .gram, price: 3.07),
        "dg4-garlic-minced-8oz": Product(id: "dg4-garlic-minced-8oz", title: "Demo Minced Garlic in Olive Oil", packageDescription: "8 oz synthetic package", packageQuantity: 226.796_185, packageUnit: .gram, price: 3.12),
        "dg4-lemon-each-1ct": Product(id: "dg4-lemon-each-1ct", title: "Demo Fresh Lemon", packageDescription: "1 count synthetic package", packageQuantity: 1, packageUnit: .count, price: 0.64),
        "dg4-lemon-organic-2lb": Product(id: "dg4-lemon-organic-2lb", title: "Demo Organic Lemons", packageDescription: "2 lb synthetic package", packageQuantity: 907.184_74, packageUnit: .gram, price: 3.92),
        "dg4-parsley-bunch-1ct": Product(id: "dg4-parsley-bunch-1ct", title: "Demo Fresh Cut Parsley", packageDescription: "1 count synthetic bunch", packageQuantity: 1, packageUnit: .count, price: 0.98)
    ]

    static func make(for plan: SolariResearchPlan) throws -> SolariValidatedResearch {
        guard plan.request.executionMode == .recordedFixture else {
            throw SolariRetailerResearchClientError.invalidRequest
        }
        let observedAt = ISO8601DateFormatter().date(from: "2026-07-16T12:00:00Z")!
        var observations: [SolariRetailerObservation] = []
        var decisions: [SolariBasketDecision] = []
        var subtotal: Decimal = 0
        var cheapestSubtotal: Decimal = 0
        var selectedAggregateRelativeSurplus = 0.0
        var cheapestAggregateRelativeSurplus = 0.0

        for requirement in plan.request.requirements {
            let candidates = requirement.candidateProductIDs.compactMap { products[$0] }
            guard candidates.count == requirement.candidateProductIDs.count else {
                throw SolariRetailerResearchClientError.invalidRequest
            }
            let candidateObservations = try candidates.map { product -> SolariRetailerObservation in
                guard let sourceURL = plan.sourceURLsByProductID[product.id] else {
                    throw SolariRetailerResearchClientError.invalidRequest
                }
                return SolariRetailerObservation(
                    schemaVersion: SolariRetailerEvidenceSchema.observationVersion,
                    observationID: "debug-recorded-\(requirement.id.uuidString.lowercased())-\(product.id)",
                    requirementID: requirement.id,
                    retailerProductID: product.id,
                    sourceURL: sourceURL,
                    title: product.title,
                    packageDescription: product.packageDescription,
                    packageQuantity: product.packageQuantity,
                    packageUnit: product.packageUnit,
                    visiblePrice: product.price,
                    currency: "USD",
                    observedAt: observedAt,
                    confidence: .high,
                    ambiguityReasons: [],
                    proteinGramsPerPackage: nil,
                    collectionMethod: .controlledDemo,
                    location: .controlledDemo,
                    catalogEra: "current-v4",
                    syntheticPrice: true,
                    freshness: SolariObservationFreshness(status: .stale, ageSeconds: nil, maxAgeSeconds: 86_400)
                )
            }
            observations.append(contentsOf: candidateObservations)

            guard let cheapest = candidates.min(by: {
                cheapestKey(product: $0, requirement: requirement) < cheapestKey(product: $1, requirement: requirement)
            }),
            let observation = candidateObservations.first(where: { $0.retailerProductID == cheapest.id }) else {
                throw SolariRetailerResearchClientError.invalidRequest
            }
            let selected = cheapest
            let packageCount = max(1, Int(ceil(requirement.requiredQuantity / selected.packageQuantity)))
            let covered = selected.packageQuantity * Double(packageCount)
            let surplus = covered - requirement.requiredQuantity
            let relativeSurplus = surplus / requirement.requiredQuantity
            let lineTotal = selected.price * Decimal(packageCount)
            subtotal += lineTotal
            selectedAggregateRelativeSurplus += relativeSurplus

            let cheapestCount = max(1, Int(ceil(requirement.requiredQuantity / cheapest.packageQuantity)))
            cheapestSubtotal += cheapest.price * Decimal(cheapestCount)
            cheapestAggregateRelativeSurplus += max(
                0,
                (cheapest.packageQuantity * Double(cheapestCount) - requirement.requiredQuantity) / requirement.requiredQuantity
            )
            decisions.append(
                SolariBasketDecision(
                    schemaVersion: SolariRetailerEvidenceSchema.decisionVersion,
                    requirementID: requirement.id,
                    observationID: observation.observationID,
                    retailerProductID: selected.id,
                    packageCount: packageCount,
                    requiredQuantity: requirement.requiredQuantity,
                    coveredQuantity: covered,
                    quantityUnit: selected.packageUnit,
                    surplusQuantity: max(0, surplus),
                    relativeSurplus: max(0, relativeSurplus),
                    lineTotal: lineTotal,
                    currency: "USD",
                    proteinGramsPerDollar: nil,
                    substitutionNote: nil,
                    rationale: ["Recorded V4 comparison selected this admitted package within the shared premium cap."],
                    confidence: .high,
                    ambiguityReasons: []
                )
            )
        }

        let result = SolariResearchResult(
            schemaVersion: SolariRetailerEvidenceSchema.resultVersion,
            requestID: plan.request.requestID,
            demoID: plan.request.demoID,
            retailerID: plan.request.retailerID,
            completedAt: observedAt,
            executionMode: .recordedFixture,
            status: .complete,
            observations: observations,
            decisions: decisions,
            basket: SolariBasketSummary(
                completeness: .complete,
                observedSubtotal: subtotal,
                currency: "USD",
                pricedLineCount: decisions.count,
                missingPriceLineCount: 0,
                unmatchedRequirementCount: 0
            ),
            comparison: SolariBasketComparison(
                cheapestAdequateSubtotal: cheapestSubtotal,
                selectedSubtotal: subtotal,
                premiumOverCheapest: subtotal - cheapestSubtotal,
                cheapestAggregateRelativeSurplus: cheapestAggregateRelativeSurplus,
                selectedAggregateRelativeSurplus: selectedAggregateRelativeSurplus,
                relativeSurplusAvoided: max(0, cheapestAggregateRelativeSurplus - selectedAggregateRelativeSurplus),
                maxPremiumOverCheapest: plan.request.optimizationPolicy.maxPremiumOverCheapest,
                currency: "USD"
            ),
            optimizer: SolariOptimizerProvenance(
                method: .deterministicFixture,
                algorithmVersion: "recorded-relative-surplus-comparison-v4",
                objective: .minimizeAggregateRelativeSurplus,
                authority: .notRunFixture,
                verification: .notRunFixture,
                policyInvariantsVerified: false
            ),
            provenance: SolariExecutionProvenance(
                browser: .notRunFixture,
                sandbox: .notRunFixture,
                fixtureReplay: true,
                resourceCleanup: .init(browser: .notRunFixture, sandbox: .notRunFixture),
                accessBoundary: .notUsedRecordedFixture
            ),
            trust: SolariTrustBoundary(
                priceClaim: .recordedFixtureNotLive,
                accountAccessed: false,
                cartModified: false,
                checkoutAutomated: false,
                userControlsHandoff: true,
                limitations: [
                    "DEBUG recorded replay only: Solari Browser, Solari Sandbox, and Apple App Attest did not run.",
                    "Prices are historical synthetic seed data from 2026-07-16, not live or guaranteed."
                ]
            )
        )
        return SolariValidatedResearch(
            result: result,
            warnings: result.trust.limitations,
            planFingerprint: plan.fingerprint
        )
    }

    private static func cheapestKey(product: Product, requirement: SolariShoppingRequirement) -> String {
        let count = max(1, Int(ceil(requirement.requiredQuantity / product.packageQuantity)))
        let cents = NSDecimalNumber(decimal: product.price * Decimal(count)).multiplying(byPowerOf10: 2).intValue
        return String(format: "%010d-%@", cents, product.id)
    }

}
#endif
