import Foundation

enum SolariRetailerEvidenceSchema {
    static let requestVersion = "solari-shopping-research-request-v4"
    static let resultVersion = "solari-shopping-research-result-v4"
    static let observationVersion = "retailer-observation-v4"
    static let decisionVersion = "basket-decision-v4"
    static let demoID = "owned-demo-grocer-basket-v4"
    static let retailerID = "smartcart-demo-grocer"
    static let storeReference = "smartcart-demo-grocer-owned-catalog-v4"
    static let maximumRequirements = 12
    static let maximumCandidatesPerRequirement = 3
    static let maximumObservations = 24
    static let maximumResponseBytes = 256 * 1_024
}

struct SolariResearchRequest: Codable, Hashable {
    let schemaVersion: String
    let requestID: UUID
    let demoID: String
    let submittedAt: Date
    let retailerID: String
    let executionMode: SolariExecutionMode
    let storeReference: String
    let optimizationPolicy: SolariOptimizationPolicy
    let requirements: [SolariShoppingRequirement]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestID
        case demoID
        case submittedAt
        case retailerID
        case executionMode
        case storeReference
        case optimizationPolicy
        case requirements
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(requestID.uuidString.lowercased(), forKey: .requestID)
        try container.encode(demoID, forKey: .demoID)
        try container.encode(submittedAt, forKey: .submittedAt)
        try container.encode(retailerID, forKey: .retailerID)
        try container.encode(executionMode, forKey: .executionMode)
        try container.encode(storeReference, forKey: .storeReference)
        try container.encode(optimizationPolicy, forKey: .optimizationPolicy)
        try container.encode(requirements, forKey: .requirements)
    }
}

enum SolariOptimizationObjective: String, Codable, Hashable {
    case minimizeAggregateRelativeSurplus = "minimize-aggregate-relative-surplus"
}

enum SolariOptimizationTieBreak: String, Codable, Hashable {
    case observedSubtotal = "observed-subtotal"
    case retailerProductID = "retailer-product-id"
}

struct SolariOptimizationPolicy: Codable, Hashable {
    let objective: SolariOptimizationObjective
    let maxPremiumOverCheapest: Decimal
    let currency: String
    let tieBreak: [SolariOptimizationTieBreak]

    static let fixedV4 = SolariOptimizationPolicy(
        objective: .minimizeAggregateRelativeSurplus,
        maxPremiumOverCheapest: Decimal(string: "0.75")!,
        currency: "USD",
        tieBreak: [.observedSubtotal, .retailerProductID]
    )
}

struct SolariShoppingRequirement: Codable, Identifiable, Hashable {
    let id: UUID
    let ingredientID: UUID
    let name: String
    let requestedQuantityText: String
    let requiredQuantity: Double
    let unit: SolariRequirementUnit
    let candidateProductIDs: [String]
}

enum SolariRequirementUnit: String, Codable, Hashable {
    case gram = "g"
    case milliliter = "ml"
    case count

    var evidenceUnit: SolariEvidenceUnit {
        switch self {
        case .gram: .gram
        case .milliliter: .milliliter
        case .count: .count
        }
    }
}

enum SolariEvidenceUnit: String, Codable, Hashable {
    case gram
    case milliliter
    case count
}

enum SolariExecutionMode: String, Codable, Hashable {
    case live
    case recordedFixture = "recorded_fixture"
}

enum SolariResultStatus: String, Codable, Hashable {
    case complete
    case partial
    case unavailable
}

enum SolariObservationConfidence: String, Codable, CaseIterable, Hashable {
    case high
    case medium
    case low

    var label: String { rawValue.capitalized }
}

enum SolariFreshnessStatus: String, Codable, Hashable {
    case fresh
    case stale
    case future
    case unknown
}

struct SolariObservationFreshness: Codable, Hashable {
    let status: SolariFreshnessStatus
    let ageSeconds: Int?
    let maxAgeSeconds: Int
}

enum SolariCollectionMethod: String, Codable, Hashable {
    case controlledDemo = "solari-browser-controlled-demo"
}

struct SolariResearchResult: Codable, Hashable {
    let schemaVersion: String
    let requestID: UUID
    let demoID: String
    let retailerID: String
    let completedAt: Date
    let executionMode: SolariExecutionMode
    let status: SolariResultStatus
    let observations: [SolariRetailerObservation]
    let decisions: [SolariBasketDecision]
    let basket: SolariBasketSummary
    let comparison: SolariBasketComparison
    let optimizer: SolariOptimizerProvenance
    let provenance: SolariExecutionProvenance
    let trust: SolariTrustBoundary
}

struct SolariRetailerObservation: Codable, Identifiable, Hashable {
    let schemaVersion: String
    let observationID: String
    let requirementID: UUID
    let retailerProductID: String
    let sourceURL: URL
    let title: String?
    let packageDescription: String?
    let packageQuantity: Double?
    let packageUnit: SolariEvidenceUnit?
    let visiblePrice: Decimal?
    let currency: String?
    let observedAt: Date
    let confidence: SolariObservationConfidence
    let ambiguityReasons: [String]
    let proteinGramsPerPackage: Double?
    let collectionMethod: SolariCollectionMethod
    let location: SolariObservationLocation
    let catalogEra: String
    let syntheticPrice: Bool
    let freshness: SolariObservationFreshness

    var id: String { observationID }
}

struct SolariObservationLocation: Codable, Hashable {
    let kind: String
    let label: String

    static let controlledDemo = SolariObservationLocation(
        kind: "controlled-demo",
        label: "SmartCart Demo Grocer synthetic catalog"
    )
}

struct SolariBasketDecision: Codable, Identifiable, Hashable {
    let schemaVersion: String
    let requirementID: UUID
    let observationID: String
    let retailerProductID: String
    let packageCount: Int
    let requiredQuantity: Double
    let coveredQuantity: Double
    let quantityUnit: SolariEvidenceUnit
    let surplusQuantity: Double
    let relativeSurplus: Double
    let lineTotal: Decimal?
    let currency: String?
    let proteinGramsPerDollar: Double?
    let substitutionNote: String?
    let rationale: [String]
    let confidence: SolariObservationConfidence
    let ambiguityReasons: [String]

    var id: UUID { requirementID }
}

enum SolariBasketCompleteness: String, Codable, Hashable {
    case complete
    case partial
}

struct SolariBasketSummary: Codable, Hashable {
    let completeness: SolariBasketCompleteness
    let observedSubtotal: Decimal?
    let currency: String?
    let pricedLineCount: Int
    let missingPriceLineCount: Int
    let unmatchedRequirementCount: Int
}

struct SolariBasketComparison: Codable, Hashable {
    let cheapestAdequateSubtotal: Decimal
    let selectedSubtotal: Decimal
    let premiumOverCheapest: Decimal
    let cheapestAggregateRelativeSurplus: Double
    let selectedAggregateRelativeSurplus: Double
    let relativeSurplusAvoided: Double
    let maxPremiumOverCheapest: Decimal
    let currency: String
}

enum SolariOptimizerMethod: String, Codable, Hashable {
    case sandbox = "solari-sandbox"
    case deterministicFixture = "smartcart-deterministic-fixture-replay"
}

struct SolariOptimizerProvenance: Codable, Hashable {
    let method: SolariOptimizerMethod
    let algorithmVersion: String
    let objective: SolariOptimizationObjective
    let authority: SolariOptimizerAuthority
    let verification: SolariOptimizerVerification
    let policyInvariantsVerified: Bool
}

enum SolariOptimizerAuthority: String, Codable, Hashable {
    case sandbox = "solari-sandbox"
    case notRunFixture = "not-run-fixture-replay"
}

enum SolariOptimizerVerification: String, Codable, Hashable {
    case smartCartPolicyInvariants = "smartcart-policy-invariants-no-local-global-argmin"
    case notRunFixture = "not-run-fixture-replay"
}

enum SolariBrowserProvenance: String, Codable, Hashable {
    case browser = "solari-browser"
    case notRunFixture = "not-run-fixture-replay"
}

enum SolariSandboxProvenance: String, Codable, Hashable {
    case sandbox = "solari-sandbox"
    case notRunFixture = "not-run-fixture-replay"
}

enum SolariResourceCleanupStatus: String, Codable, Hashable {
    case enforcedBeforeResponse = "enforced-before-response"
    case notRunFixture = "not-run-fixture-replay"
}

enum SolariAccessBoundary: String, Codable, Hashable {
    case appleAppAttest = "apple-app-attest"
    case operatorQualification = "operator-qualification"
    case notUsedRecordedFixture = "not-used-recorded-fixture"
}

struct SolariExecutionProvenance: Codable, Hashable {
    struct ResourceCleanup: Codable, Hashable {
        let browser: SolariResourceCleanupStatus
        let sandbox: SolariResourceCleanupStatus
    }

    let browser: SolariBrowserProvenance
    let sandbox: SolariSandboxProvenance
    let fixtureReplay: Bool
    let resourceCleanup: ResourceCleanup
    let accessBoundary: SolariAccessBoundary
}

enum SolariPriceClaim: String, Codable, Hashable {
    case observedNotGuaranteed = "observed-visible-price-not-guaranteed"
    case recordedFixtureNotLive = "recorded-fixture-not-live"
}

struct SolariTrustBoundary: Codable, Hashable {
    let priceClaim: SolariPriceClaim
    let accountAccessed: Bool
    let cartModified: Bool
    let checkoutAutomated: Bool
    let userControlsHandoff: Bool
    let limitations: [String]
}

struct SolariValidatedResearch: Hashable {
    let result: SolariResearchResult
    let warnings: [String]
    let planFingerprint: String
}

struct SolariResearchPlan: Hashable {
    let configuration: SolariBackendConfiguration
    let request: SolariResearchRequest
    let fingerprint: String
    let sourceURLsByProductID: [String: URL]
    let originalSmartCartSelections: [SolariOriginalSmartCartSelection]
    let skippedLines: [SolariSkippedResearchLine]
    let totalWaitingCount: Int
    let servingCount: Int
}

struct SolariOriginalSmartCartSelection: Codable, Hashable {
    let requirementID: UUID
    let ingredientID: UUID
    let ingredientName: String
    let ingredientUnit: String
    let requestedQuantity: String
    let requestedAmount: Double?
    let retailerID: String
    let retailerProductID: String
}

struct SolariSkippedResearchLine: Codable, Identifiable, Hashable {
    let id: UUID
    let ingredientID: UUID
    let name: String
    let reason: SolariResearchIneligibilityReason
}

struct SolariReviewContext: Identifiable, Hashable {
    var id: String { plan.fingerprint }
    let plan: SolariResearchPlan
}

struct SolariEvidenceHandoff: Equatable, Hashable {
    let retailerID: String
    let selectedSourceURLs: [URL]
    let transfersToConfiguredRetailer: Bool

    init(result: SolariResearchResult) {
        var observationsByID: [String: SolariRetailerObservation] = [:]
        result.observations.forEach { observationsByID[$0.observationID] = $0 }
        retailerID = result.retailerID
        selectedSourceURLs = result.decisions.compactMap { observationsByID[$0.observationID]?.sourceURL }
        transfersToConfiguredRetailer = false
    }
}

enum SolariResearchIneligibilityReason: Codable, LocalizedError, Equatable, Hashable {
    case configurationUnavailable
    case noWaitingItems
    case unsupportedProduct(String)
    case missingExactCandidate(String)
    case invalidQuantity(String)
    case unsupportedUnit(name: String, unit: String)
    case incompatiblePackageDimension(String)
    case overlappingCatalogCoverage(String)
    case requirementLimitReached(Int)
    case observationLimitReached(Int)
    case duplicateRequirement
    case duplicateCandidate

    var errorDescription: String? {
        switch self {
        case .configurationUnavailable:
            "Solari beta research is not configured in this build. Normal SmartCart shopping is still available."
        case .noWaitingItems:
            "There are no waiting shopping items to research."
        case .unsupportedProduct(let name):
            "\(name) is not in the current Demo Grocer catalog and will continue through normal SmartCart."
        case .missingExactCandidate(let name):
            "\(name) does not have an exact reviewed product candidate."
        case .invalidQuantity(let name):
            "\(name) needs a positive, reviewed quantity before research."
        case .unsupportedUnit(let name, let unit):
            "\(name) uses “\(unit)”, which cannot be converted exactly to grams, milliliters, or count. Review its numeric quantity to research it."
        case .incompatiblePackageDimension(let name):
            "\(name) has no reviewed package in the same quantity dimension. SmartCart will not invent a density or package conversion."
        case .overlappingCatalogCoverage(let name):
            "\(name) shares the same Demo Grocer candidates as another researched line. Review or combine the duplicate need; this line will continue through normal SmartCart."
        case .requirementLimitReached(let limit):
            "This request is limited to \(limit) researched items. This line will continue through normal SmartCart."
        case .observationLimitReached(let limit):
            "This request is limited to \(limit) retailer observations. This line will continue through normal SmartCart."
        case .duplicateRequirement:
            "The current plan contains duplicate requirement identities and cannot be researched safely."
        case .duplicateCandidate:
            "The current plan assigns the same Demo Grocer candidate to more than one requirement."
        }
    }
}

enum SolariResearchEligibility: Equatable {
    case eligible(SolariResearchPlan)
    case ineligible([SolariResearchIneligibilityReason])
}

enum SolariEvidenceContractError: LocalizedError, Equatable {
    case unknownSchemaVersion
    case requestMismatch
    case invalidCompletionTimestamp
    case unavailableResult
    case tooManyResults
    case duplicateObservation
    case invalidObservationReference
    case staleObservation
    case invalidObservation
    case duplicateDecision
    case invalidDecisionReference
    case invalidPackageMath
    case invalidPriceMath
    case invalidProteinMath
    case invalidBasketSummary
    case invalidComparison
    case incompleteBasketClaim
    case invalidProvenance

    var errorDescription: String? {
        switch self {
        case .unknownSchemaVersion: "Solari returned an unsupported evidence version."
        case .requestMismatch: "Solari returned evidence for a different shopping request."
        case .invalidCompletionTimestamp: "Solari returned an invalid completion timestamp."
        case .unavailableResult: "Solari could not produce an evidence-backed basket."
        case .tooManyResults: "Solari returned more evidence than this beta accepts."
        case .duplicateObservation: "Solari returned duplicate retailer observations."
        case .invalidObservationReference: "Solari returned evidence outside the submitted product allowlist."
        case .staleObservation: "Solari returned stale or future retailer evidence."
        case .invalidObservation: "Solari returned an incomplete retailer observation."
        case .duplicateDecision: "Solari returned more than one basket decision for a requirement."
        case .invalidDecisionReference: "A basket decision does not reference matching retailer evidence."
        case .invalidPackageMath: "Solari returned inconsistent package quantity math."
        case .invalidPriceMath: "Solari returned inconsistent visible-price math."
        case .invalidProteinMath: "Solari returned unsupported protein-per-dollar data."
        case .invalidBasketSummary: "Solari returned an inconsistent basket summary."
        case .invalidComparison: "Solari returned inconsistent cheapest-basket or package-surplus comparison math."
        case .incompleteBasketClaim: "Solari labeled an incomplete or unpriced basket as complete."
        case .invalidProvenance: "Solari returned evidence without the required Browser, Sandbox, App Attest, and user-control boundaries."
        }
    }
}
