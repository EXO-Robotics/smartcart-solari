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

enum SmartCartHandoffSourceTypeDTO: String, Codable, Equatable, Sendable {
    case text
    case imageTranscription = "image_transcription"
}

struct SmartCartRecipeAnalysisDataDTO: Codable, Equatable, Sendable {
    let recipeId: UUID
    let title: String
    let servings: Decimal
    let ingredients: [IngredientInputDTO]
    let evidence: [ResolutionEvidenceDTO]
    let issues: [ResolutionIssueDTO]
}

typealias SmartCartRecipeAnalysisDTO = TripIntelligenceEnvelopeDTO<SmartCartRecipeAnalysisDataDTO>

struct SmartCartHandoffRecipeDTO: Codable, Equatable, Sendable {
    let sourceType: SmartCartHandoffSourceTypeDTO
    let recipeText: String
    let analysis: SmartCartRecipeAnalysisDTO
    let quantityReviewIngredientIds: [UUID]
}

struct SmartCartHandoffPayloadDataDTO: Codable, Equatable, Sendable {
    let claimId: UUID
    let audience: String
    let payloadDigest: String
    let issuedAt: String
    let expiresAt: String
    let recipes: [SmartCartHandoffRecipeDTO]
}

typealias SmartCartHandoffPayloadDTO = TripIntelligenceEnvelopeDTO<SmartCartHandoffPayloadDataDTO>

struct SmartCartHandoffClaimRequestDataDTO: Codable, Equatable, Sendable {
    let claimToken: String
}

enum SmartCartHandoffURLParseResult: Equatable, Sendable {
    case notSmartCartHandoff
    case valid(token: String)
    case invalid
}

enum SmartCartHandoffURLParser {
    static let minimumTokenLength = 40
    static let maximumTokenLength = 24_000
    static let universalLinkHost = "smartcart-barcode-api-omega.vercel.app"

    static func parse(_ url: URL) -> SmartCartHandoffURLParseResult {
        switch url.scheme?.lowercased() {
        case "smartcart":
            return parseCustomScheme(url)
        case "https" where url.host?.lowercased() == universalLinkHost:
            return parseUniversalLink(url)
        default:
            return .notSmartCartHandoff
        }
    }

    private static func parseCustomScheme(_ url: URL) -> SmartCartHandoffURLParseResult {
        guard url.host?.lowercased() == "claim",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.path.isEmpty,
              let token = url.fragment,
              isValidToken(token)
        else {
            return .invalid
        }
        return .valid(token: token)
    }

    private static func parseUniversalLink(_ url: URL) -> SmartCartHandoffURLParseResult {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard url.host?.lowercased() == universalLinkHost,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              components?.percentEncodedPath == "/t",
              let token = url.fragment,
              isValidToken(token)
        else {
            return .invalid
        }
        return .valid(token: token)
    }

    static func isValidToken(_ token: String) -> Bool {
        guard (minimumTokenLength...maximumTokenLength).contains(token.utf8.count),
              token.hasPrefix("v1.") else { return false }
        return token.dropFirst(3).utf8.allSatisfy {
            (48...57).contains($0) ||
                (65...90).contains($0) ||
                (97...122).contains($0) ||
                $0 == 45 ||
                $0 == 95
        }
    }
}

enum SmartCartHandoffValidationError: LocalizedError, Equatable {
    case unsupportedSchema
    case invalidAudience
    case invalidDigest
    case invalidDates
    case expired
    case invalidRecipeCount
    case duplicateRecipeID
    case invalidServings(recipeID: UUID)
    case emptyRecipe(recipeID: UUID)
    case invalidIngredient(recipeID: UUID, ingredientID: UUID)
    case duplicateIngredientID(recipeID: UUID)
    case blockingAnalysis(recipeID: UUID)
    case invalidQuantityReviewSet(recipeID: UUID)

    var errorDescription: String? {
        switch self {
        case .expired:
            "This SmartCart plan has expired. Ask ChatGPT to create a new link."
        default:
            "This SmartCart plan could not be verified. Ask ChatGPT to create a new link."
        }
    }
}

struct SmartCartHandoffImport: Equatable {
    let claimID: UUID
    let recipes: [Recipe]
}

enum SmartCartHandoffSnapshotFactory {
    private static let resolverVersion = "smartcart-handoff-v1"
    private static let audience = "smartcart-ios"
    private static let maximumLifetime: TimeInterval = 10 * 60
    private static let maximumClockSkew: TimeInterval = 60

    static func makeImport(
        from payload: SmartCartHandoffPayloadDTO,
        now: Date = .now
    ) throws -> SmartCartHandoffImport {
        guard payload.schemaVersion == TripIntelligenceSchema.version,
              payload.resolverVersion == resolverVersion else {
            throw SmartCartHandoffValidationError.unsupportedSchema
        }
        guard payload.data.audience == audience else {
            throw SmartCartHandoffValidationError.invalidAudience
        }
        guard payload.data.payloadDigest.count == 64,
              payload.data.payloadDigest.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }) else {
            throw SmartCartHandoffValidationError.invalidDigest
        }
        guard let issuedAt = parseInternetDate(payload.data.issuedAt),
              let expiresAt = parseInternetDate(payload.data.expiresAt),
              issuedAt <= expiresAt,
              expiresAt.timeIntervalSince(issuedAt) <= maximumLifetime,
              issuedAt.timeIntervalSince(now) <= maximumClockSkew else {
            throw SmartCartHandoffValidationError.invalidDates
        }
        guard expiresAt > now else { throw SmartCartHandoffValidationError.expired }

        let recipeDTOs = payload.data.recipes
        guard (1...MealPrepDraft.selectionLimit).contains(recipeDTOs.count) else {
            throw SmartCartHandoffValidationError.invalidRecipeCount
        }
        guard Set(recipeDTOs.map { $0.analysis.data.recipeId }).count == recipeDTOs.count else {
            throw SmartCartHandoffValidationError.duplicateRecipeID
        }

        let isSingleRecipe = recipeDTOs.count == 1
        let recipes = try recipeDTOs.map { recipeDTO in
            try makeRecipe(recipeDTO, isSingleRecipe: isSingleRecipe)
        }
        return SmartCartHandoffImport(claimID: payload.data.claimId, recipes: recipes)
    }

    private static func makeRecipe(
        _ source: SmartCartHandoffRecipeDTO,
        isSingleRecipe: Bool
    ) throws -> Recipe {
        let analysis = source.analysis
        let recipeID = analysis.data.recipeId
        guard analysis.schemaVersion == TripIntelligenceSchema.version else {
            throw SmartCartHandoffValidationError.unsupportedSchema
        }
        guard !analysis.data.issues.contains(where: { $0.severity == .blocking }) else {
            throw SmartCartHandoffValidationError.blockingAnalysis(recipeID: recipeID)
        }
        guard let servings = exactPositiveInteger(analysis.data.servings),
              isSingleRecipe ? (1...24).contains(servings) : (1...48).contains(servings) else {
            throw SmartCartHandoffValidationError.invalidServings(recipeID: recipeID)
        }

        let title = analysis.data.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipeText = source.recipeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title.count <= 300,
              !recipeText.isEmpty,
              recipeText.count <= 50_000,
              !analysis.data.ingredients.isEmpty,
              analysis.data.ingredients.count <= 200 else {
            throw SmartCartHandoffValidationError.emptyRecipe(recipeID: recipeID)
        }
        let ingredientIDs = analysis.data.ingredients.map(\.ingredientId)
        guard Set(ingredientIDs).count == ingredientIDs.count else {
            throw SmartCartHandoffValidationError.duplicateIngredientID(recipeID: recipeID)
        }

        let numericIDs = Set(analysis.data.ingredients.compactMap { ingredient -> UUID? in
            guard case .numeric = ingredient.quantity else { return nil }
            return ingredient.ingredientId
        })
        let reviewIDs = Set(source.quantityReviewIngredientIds)
        guard reviewIDs.count == source.quantityReviewIngredientIds.count,
              source.quantityReviewIngredientIds.count <= 200 else {
            throw SmartCartHandoffValidationError.invalidQuantityReviewSet(recipeID: recipeID)
        }
        switch source.sourceType {
        case .text:
            guard reviewIDs.isEmpty else {
                throw SmartCartHandoffValidationError.invalidQuantityReviewSet(recipeID: recipeID)
            }
        case .imageTranscription:
            guard reviewIDs == numericIDs else {
                throw SmartCartHandoffValidationError.invalidQuantityReviewSet(recipeID: recipeID)
            }
        }

        let ingredients = try analysis.data.ingredients.map { ingredient in
            try makeIngredient(
                ingredient,
                sourceType: source.sourceType,
                requiresQuantityReview: reviewIDs.contains(ingredient.ingredientId),
                recipeID: recipeID
            )
        }
        return Recipe(
            id: recipeID,
            title: title,
            source: .text,
            sourceDetail: source.sourceType == .imageTranscription
                ? "ChatGPT image transcription"
                : "ChatGPT plugin",
            heroSymbol: "fork.knife",
            servings: servings,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: ingredients,
            rawSourceText: source.recipeText
        )
    }

    private static func makeIngredient(
        _ source: IngredientInputDTO,
        sourceType: SmartCartHandoffSourceTypeDTO,
        requiresQuantityReview: Bool,
        recipeID: UUID
    ) throws -> Ingredient {
        let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawText = source.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let preparation = source.preparation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.count <= 300,
              !rawText.isEmpty,
              rawText.count <= 2_000,
              preparation.count <= 300,
              source.brandPreference.map({ $0.count <= 300 }) ?? true,
              !source.evidence.isEmpty,
              source.includedInRecipe || !source.includeInTrip else {
            throw SmartCartHandoffValidationError.invalidIngredient(
                recipeID: recipeID,
                ingredientID: source.ingredientId
            )
        }

        let quantity: Double
        let lowerBound: Double?
        let semanticQuantity: String?
        let unit: String
        switch source.quantity {
        case .numeric(let value, let minimumValue, let rawUnit):
            guard let numeric = finitePositiveDouble(value),
                  minimumValue.map({ finitePositiveDouble($0) != nil }) ?? true else {
                throw SmartCartHandoffValidationError.invalidIngredient(
                    recipeID: recipeID,
                    ingredientID: source.ingredientId
                )
            }
            let minimum = minimumValue.flatMap(finitePositiveDouble)
            let normalizedUnit = rawUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            guard minimum.map({ $0 <= numeric }) ?? true else {
                throw SmartCartHandoffValidationError.invalidIngredient(
                    recipeID: recipeID,
                    ingredientID: source.ingredientId
                )
            }
            quantity = numeric
            lowerBound = minimum
            semanticQuantity = nil
            guard normalizedUnit.count <= 100 else {
                throw SmartCartHandoffValidationError.invalidIngredient(
                    recipeID: recipeID,
                    ingredientID: source.ingredientId
                )
            }
            unit = normalizedUnit
        case .semantic(let rawSemantic):
            let normalized = rawSemantic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["as needed", "to taste", "for frying"].contains(normalized) else {
                throw SmartCartHandoffValidationError.invalidIngredient(
                    recipeID: recipeID,
                    ingredientID: source.ingredientId
                )
            }
            quantity = 0
            lowerBound = nil
            semanticQuantity = normalized
            unit = ""
        case nil:
            quantity = 0
            lowerBound = nil
            semanticQuantity = nil
            unit = ""
        }

        let evidence = IngredientSourceEvidence(
            rawText: source.sourceText,
            pageIndex: nil,
            boundingBox: nil,
            extractionStrategy: sourceType == .imageTranscription ? .visionOCR : .pastedText,
            ocrConfidence: nil,
            layoutConfidence: nil,
            parserConfidence: 1,
            normalizationConfidence: 1,
            alternateQuantityCandidates: [],
            sourceObservationIDs: source.evidence.map(\.evidenceId),
            originalLine: source.sourceText,
            reviewReasons: sourceType == .imageTranscription
                ? ["remote_image_transcription"]
                : nil
        )
        return Ingredient(
            id: source.ingredientId,
            rawText: source.sourceText,
            name: name,
            quantity: quantity,
            semanticQuantity: semanticQuantity,
            quantityLowerBound: lowerBound,
            unit: unit,
            preparation: preparation,
            category: category(for: name),
            confidence: requiresQuantityReview ? .review : .high,
            includeInList: source.includedInRecipe && source.includeInTrip,
            pantryState: source.includedInRecipe && source.includeInTrip ? .needToBuy : .exclude,
            brandNote: source.brandPreference,
            sourceEvidence: evidence,
            quantityReviewRequired: requiresQuantityReview
        )
    }

    private static func exactPositiveInteger(_ value: Decimal) -> Int? {
        let number = NSDecimalNumber(decimal: value)
        let double = number.doubleValue
        guard double.isFinite,
              double > 0,
              double.rounded() == double,
              double <= Double(Int.max) else { return nil }
        return Int(double)
    }

    private static func finitePositiveDouble(_ value: Decimal) -> Double? {
        let double = NSDecimalNumber(decimal: value).doubleValue
        return double.isFinite && double > 0 ? double : nil
    }

    private static func parseInternetDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let ordinary = ISO8601DateFormatter()
        ordinary.formatOptions = [.withInternetDateTime]
        return ordinary.date(from: value)
    }

    private static func category(for name: String) -> GroceryCategory {
        let value = name.lowercased()
        if ["milk", "cream", "cheese", "butter", "yogurt", "egg", "parmesan"].contains(where: value.contains) {
            return .dairy
        }
        if ["chicken", "beef", "pork", "salmon", "shrimp", "turkey", "sausage"].contains(where: value.contains) {
            return .meat
        }
        if ["bread", "tortilla", "bun", "bagel", "pita"].contains(where: value.contains) {
            return .bakery
        }
        if ["frozen", "ice cream"].contains(where: value.contains) { return .frozen }
        if [
            "onion", "garlic", "tomato", "spinach", "lime", "lemon", "pepper", "avocado",
            "cabbage", "carrot", "potato", "parsley", "cilantro", "broccoli", "bean"
        ].contains(where: value.contains) {
            return .produce
        }
        return .pantry
    }
}
