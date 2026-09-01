import Foundation

enum SolariRetailerEvidenceSchema {
    static let requestVersion = "solari-shopping-research-request-v2"
    static let resultVersion = "solari-shopping-research-result-v2"
    static let observationVersion = "retailer-observation-v2"
    static let decisionVersion = "basket-decision-v2"
    static let demoID = "owned-demo-grocer-basket-v2"
    static let retailerID = "smartcart-demo-grocer"
    static let storeReference = "smartcart-demo-grocer-owned-catalog-v1"
    static let maximumRequirements = 3
    static let maximumCandidatesPerRequirement = 3
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
    let requirements: [SolariShoppingRequirement]
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
    case ounce = "oz"
    case pound = "lb"
    case count

    var evidenceUnit: SolariEvidenceUnit {
        switch self {
        case .ounce: .ounce
        case .pound: .pound
        case .count: .count
        }
    }
}

enum SolariEvidenceUnit: String, Codable, Hashable {
    case ounce
    case pound
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
    let collectionMethod: SolariCollectionMethod
    let freshness: SolariObservationFreshness

    var id: String { observationID }
}

struct SolariBasketDecision: Codable, Identifiable, Hashable {
    let schemaVersion: String
    let requirementID: UUID
    let observationID: String
    let packageCount: Int
    let requiredQuantity: Double
    let coveredQuantity: Double
    let quantityUnit: SolariEvidenceUnit
    let surplusQuantity: Double
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

enum SolariOptimizerMethod: String, Codable, Hashable {
    case sandbox = "solari-sandbox"
    case deterministicFixture = "smartcart-deterministic-fixture-replay"
}

struct SolariOptimizerProvenance: Codable, Hashable {
    let method: SolariOptimizerMethod
    let algorithmVersion: String
    let independentlyVerified: Bool
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
}

struct SolariResearchPlan: Hashable {
    let configuration: SolariBackendConfiguration
    let request: SolariResearchRequest
    let fingerprint: String
    let sourceURLsByProductID: [String: URL]
    let servingCount: Int
}

struct SolariReviewContext: Identifiable, Hashable {
    var id: String { plan.fingerprint }
    let plan: SolariResearchPlan
}

enum SolariResearchIneligibilityReason: LocalizedError, Equatable, Hashable {
    case configurationUnavailable
    case noWaitingItems
    case tooManyWaitingItems(Int)
    case unsupportedProduct(String)
    case missingExactCandidate(String)
    case invalidQuantity(String)
    case unsupportedUnit(String)
    case duplicateRequirement
    case duplicateCandidate

    var errorDescription: String? {
        switch self {
        case .configurationUnavailable:
            "Solari beta research is not configured in this build. Normal SmartCart shopping is still available."
        case .noWaitingItems:
            "There are no waiting shopping items to research."
        case .tooManyWaitingItems(let count):
            "This beta researches one to three waiting items at a time; the current plan has \(count)."
        case .unsupportedProduct(let name):
            "\(name) has no candidate in the owned Demo Grocer catalog."
        case .missingExactCandidate(let name):
            "\(name) does not have an exact reviewed product candidate."
        case .invalidQuantity(let name):
            "\(name) needs a positive, reviewed quantity before research."
        case .unsupportedUnit(let unit):
            "The Demo Grocer beta cannot normalize the unit “\(unit)”."
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
        case .incompleteBasketClaim: "Solari labeled an incomplete or unpriced basket as complete."
        case .invalidProvenance: "Solari returned evidence without the required Browser, Sandbox, App Attest, and user-control boundaries."
        }
    }
}
