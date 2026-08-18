import Foundation

enum TripIntelligenceSchema {
    static let version = "1.0"
}

struct TripIntelligenceEnvelopeDTO<Payload: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: String
    let resolverVersion: String
    let requestId: UUID
    let data: Payload
}

extension TripIntelligenceEnvelopeDTO: Equatable where Payload: Equatable {}

struct TripIntelligenceRequestEnvelopeDTO<Payload: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: String
    let requestId: UUID
    let data: Payload

    init(requestId: UUID = UUID(), data: Payload) {
        schemaVersion = TripIntelligenceSchema.version
        self.requestId = requestId
        self.data = data
    }
}

extension TripIntelligenceRequestEnvelopeDTO: Equatable where Payload: Equatable {}

struct NumericEstimateDTO: Codable, Equatable, Sendable {
    let preferred: Decimal
    let minimum: Decimal
    let maximum: Decimal

    var isOrdered: Bool {
        minimum <= preferred && preferred <= maximum
    }
}

enum ResolutionConfidenceDTO: String, Codable, Equatable, Sendable {
    case verified
    case strong
    case moderate
    case weak
    case unresolved
}

enum ResolutionIssueSeverityDTO: String, Codable, Equatable, Sendable {
    case blocking
    case review
    case informational
}

struct ResolutionIssueDTO: Codable, Equatable, Sendable {
    let code: String
    let severity: ResolutionIssueSeverityDTO
    let message: String
    let field: String?
    let evidenceIds: [String]
}

enum ResolutionEvidenceKindDTO: String, Codable, Equatable, Sendable {
    case userProvided
    case sourceText
    case curatedData
    case densityCatalog
    case usdaFoodData
    case calculation
    case retailerCatalog
}

struct ResolutionEvidenceDTO: Codable, Equatable, Sendable {
    let evidenceId: String
    let kind: ResolutionEvidenceKindDTO
    let sourceName: String
    let sourceVersion: String?
    let sourceRecordId: String?
    let description: String
}

enum CanonicalQuantityDimensionDTO: String, Codable, Equatable, Sendable {
    case mass
    case volume
    case count
    case package
}

enum CanonicalQuantityUnitDTO: String, Codable, Equatable, Sendable {
    case gram = "g"
    case milliliter = "ml"
    case count
    case package
}

enum QuantityCertaintyDTO: String, Codable, Equatable, Sendable {
    case exact
    case estimated
    case unknown
}

struct CanonicalQuantityDTO: Codable, Equatable, Sendable {
    let value: Decimal
    let dimension: CanonicalQuantityDimensionDTO
    let unit: CanonicalQuantityUnitDTO
    let certainty: QuantityCertaintyDTO
}

enum IngredientQuantityInputDTO: Codable, Equatable, Sendable {
    case numeric(value: Decimal, minimumValue: Decimal?, unit: String)
    case semantic(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case minimumValue
        case unit
        case text
    }

    private enum Kind: String, Codable {
        case numeric
        case semantic
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .numeric:
            self = .numeric(
                value: try values.decode(Decimal.self, forKey: .value),
                minimumValue: try values.decodeIfPresent(Decimal.self, forKey: .minimumValue),
                unit: try values.decode(String.self, forKey: .unit)
            )
        case .semantic:
            self = .semantic(try values.decode(String.self, forKey: .text))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .numeric(let value, let minimumValue, let unit):
            try values.encode(Kind.numeric, forKey: .kind)
            try values.encode(value, forKey: .value)
            try values.encodeIfPresent(minimumValue, forKey: .minimumValue)
            try values.encode(unit, forKey: .unit)
        case .semantic(let text):
            try values.encode(Kind.semantic, forKey: .kind)
            try values.encode(text, forKey: .text)
        }
    }
}

struct IngredientInputDTO: Codable, Equatable, Sendable {
    let ingredientId: UUID
    let sourceText: String
    let name: String
    let preparation: String
    let quantity: IngredientQuantityInputDTO?
    let includedInRecipe: Bool
    let includeInTrip: Bool
    let brandPreference: String?
    let evidence: [ResolutionEvidenceDTO]

    private enum CodingKeys: String, CodingKey {
        case ingredientId
        case sourceText
        case name
        case preparation
        case quantity
        case includedInRecipe
        case includeInTrip
        case brandPreference
        case evidence
    }

    init(
        ingredientId: UUID,
        sourceText: String,
        name: String,
        preparation: String,
        quantity: IngredientQuantityInputDTO?,
        includedInRecipe: Bool,
        includeInTrip: Bool,
        brandPreference: String?,
        evidence: [ResolutionEvidenceDTO]
    ) {
        self.ingredientId = ingredientId
        self.sourceText = sourceText
        self.name = name
        self.preparation = preparation
        self.quantity = quantity
        self.includedInRecipe = includedInRecipe
        self.includeInTrip = includeInTrip
        self.brandPreference = brandPreference
        self.evidence = evidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ingredientId = try values.decode(UUID.self, forKey: .ingredientId)
        sourceText = try values.decode(String.self, forKey: .sourceText)
        name = try values.decode(String.self, forKey: .name)
        preparation = try values.decode(String.self, forKey: .preparation)
        quantity = try values.decodeIfPresent(IngredientQuantityInputDTO.self, forKey: .quantity)
        includedInRecipe = try values.decode(Bool.self, forKey: .includedInRecipe)
        includeInTrip = try values.decode(Bool.self, forKey: .includeInTrip)
        brandPreference = try values.decodeIfPresent(String.self, forKey: .brandPreference)
        evidence = try values.decode([ResolutionEvidenceDTO].self, forKey: .evidence)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(ingredientId, forKey: .ingredientId)
        try values.encode(sourceText, forKey: .sourceText)
        try values.encode(name, forKey: .name)
        try values.encode(preparation, forKey: .preparation)
        if let quantity {
            try values.encode(quantity, forKey: .quantity)
        } else {
            try values.encodeNil(forKey: .quantity)
        }
        try values.encode(includedInRecipe, forKey: .includedInRecipe)
        try values.encode(includeInTrip, forKey: .includeInTrip)
        try values.encodeIfPresent(brandPreference, forKey: .brandPreference)
        try values.encode(evidence, forKey: .evidence)
    }
}

struct IngredientIdentityModifiersDTO: Codable, Equatable, Sendable {
    let form: String?
    let variety: String?
    let criticalAttributes: [String]
    let unclassified: [String]
}

struct IngredientIdentityResolutionDTO: Codable, Equatable, Sendable {
    let ingredientId: UUID
    let identityKey: String?
    let canonicalName: String?
    let modifiers: IngredientIdentityModifiersDTO
    let confidence: ResolutionConfidenceDTO
    let safeForRetailerQuery: Bool
    let retailerQuery: String?
    let evidence: [ResolutionEvidenceDTO]
    let issues: [ResolutionIssueDTO]
}

struct IngredientMassEstimateDTO: Codable, Equatable, Sendable {
    let ingredientId: UUID
    let sourceQuantity: CanonicalQuantityDTO?
    let massGrams: NumericEstimateDTO?
    let confidence: ResolutionConfidenceDTO
    let evidence: [ResolutionEvidenceDTO]
    let issues: [ResolutionIssueDTO]
}

struct NutritionValuesDTO: Codable, Equatable, Sendable {
    let energyKilocalories: NumericEstimateDTO
    let proteinGrams: NumericEstimateDTO
}

struct IngredientNutritionResolutionDTO: Codable, Equatable, Sendable {
    let ingredientId: UUID
    let identityKey: String?
    let massGrams: NumericEstimateDTO?
    let nutrition: NutritionValuesDTO?
    let confidence: ResolutionConfidenceDTO
    let evidence: [ResolutionEvidenceDTO]
    let issues: [ResolutionIssueDTO]
}

struct RecipeNutritionRequestDataDTO: Codable, Equatable, Sendable {
    let recipeId: UUID
    let title: String
    let servings: Decimal
    let ingredients: [IngredientInputDTO]
}

struct RecipeNutritionEstimateDTO: Codable, Equatable, Sendable {
    let recipeId: UUID
    let servings: Decimal
    let ingredientResolutions: [IngredientNutritionResolutionDTO]
    let totals: NutritionValuesDTO?
    let perServing: NutritionValuesDTO?
    let confidence: ResolutionConfidenceDTO
    let evidence: [ResolutionEvidenceDTO]
    let issues: [ResolutionIssueDTO]
}

struct MealPrepNutritionEstimateDTO: Codable, Equatable, Sendable {
    let mealPlanId: UUID
    let recipeEstimates: [RecipeNutritionEstimateDTO]
    let totals: NutritionValuesDTO?
    let totalServings: Decimal
    let weightedAveragePerServing: NutritionValuesDTO?
    let confidence: ResolutionConfidenceDTO
    let evidence: [ResolutionEvidenceDTO]
    let issues: [ResolutionIssueDTO]
}
