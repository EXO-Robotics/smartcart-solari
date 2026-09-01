import Foundation

enum SolariRetailerEvidenceSchema {
    static let requestVersion = "solari-shopping-research-request-v1"
    static let resultVersion = "solari-shopping-research-result-v1"
    static let observationVersion = "retailer-observation-v1"
    static let decisionVersion = "basket-decision-v1"
    static let demoID = "chicken-parmesan-pasta-v1"
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
    let candidates: [SolariCandidateReference]
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

struct SolariCandidateReference: Codable, Hashable {
    let retailerProductID: String
    let sourceURL: URL
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
    case seededFixtureReplay = "smartcart-seeded-fixture-replay"
    case controlledDemo = "solari-browser-controlled-demo"
    case authorizedRetailer = "solari-browser-authorized-retailer"
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

struct SolariValidatedResearch: Hashable {
    let result: SolariResearchResult
    let warnings: [String]
}

struct SolariReviewContext: Identifiable {
    let id: UUID
    let backendURL: URL
    let request: SolariResearchRequest

    init(backendURL: URL, request: SolariResearchRequest) {
        id = request.requestID
        self.backendURL = backendURL
        self.request = request
    }
}

enum SolariEvidenceContractError: LocalizedError, Equatable {
    case unknownSchemaVersion
    case requestMismatch
    case recordedFixtureNotAllowed
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

    var errorDescription: String? {
        switch self {
        case .unknownSchemaVersion: "Solari returned an unsupported evidence version."
        case .requestMismatch: "Solari returned evidence for a different shopping request."
        case .recordedFixtureNotAllowed: "Recorded Solari evidence is unavailable in this build."
        case .invalidCompletionTimestamp: "Solari returned an invalid completion timestamp."
        case .unavailableResult: "Solari could not produce an evidence-backed basket."
        case .tooManyResults: "Solari returned more evidence than this experiment accepts."
        case .duplicateObservation: "Solari returned duplicate retailer observations."
        case .invalidObservationReference: "Solari returned evidence that does not match a submitted product candidate."
        case .staleObservation: "Solari returned live retailer evidence that is stale or has an invalid timestamp."
        case .invalidObservation: "Solari returned an incomplete retailer observation."
        case .duplicateDecision: "Solari returned more than one basket decision for a requirement."
        case .invalidDecisionReference: "A basket decision does not reference matching retailer evidence."
        case .invalidPackageMath: "Solari returned inconsistent package quantity math."
        case .invalidPriceMath: "Solari returned inconsistent visible-price math."
        case .invalidProteinMath: "Solari returned unsupported protein-per-dollar data."
        case .invalidBasketSummary: "Solari returned an inconsistent basket summary."
        case .incompleteBasketClaim: "Solari labeled an incomplete or unpriced basket as complete."
        }
    }
}
