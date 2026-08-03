import Foundation
import SwiftUI

enum SmartCartBuildInfo {
    static func version(
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> String {
        let value = (bundleInfo["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "0.0.0" : value
    }

    static func build(
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> String {
        let value = (bundleInfo["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "0" : value
    }

    static func displayVersion(
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> String {
        "Version \(version(bundleInfo: bundleInfo)) (\(build(bundleInfo: bundleInfo)))"
    }

    static func userAgent(
        component: String,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> String {
        "SmartCart-iOS/\(version(bundleInfo: bundleInfo)) \(component)"
    }
}

enum AppTab: String, CaseIterable, Identifiable, Codable, Hashable {
    case home
    case lists
    case pantry
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .lists: "Recipes"
        case .pantry: "Pantry"
        case .account: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .lists: "book.fill"
        case .pantry: "cabinet.fill"
        case .account: "person.crop.circle.fill"
        }
    }

    static func canonicalTab(forRawValue rawValue: String) -> AppTab? {
        rawValue == "store" ? .account : AppTab(rawValue: rawValue)
    }
}

enum SmartRoute: Hashable {
    case weeklyMealsCollection
    case weeklyMealDetail(CuratedRecipeID)
    case mealPrepSelection
    case recipeReady
    case shoppingTrip
    case shoppingReconciliation(UUID)

    /// Translates retired QA/deep-link names at the app boundary without
    /// keeping their duplicate screens in the navigation graph.
    static func canonicalRoute(forLegacyName name: String) -> SmartRoute? {
        switch name {
        case "ingredient", "servings", "pantry", "pantry-match":
            .recipeReady
        case "matching", "shopping":
            .shoppingTrip
        case "preferences", "store", "guided", "walmart-guide", "target-guide":
            .shoppingTrip
        default:
            nil
        }
    }
}

enum ImportMethod: String, CaseIterable, Identifiable, Hashable, Codable {
    case camera
    case photoLibrary
    case recipeLink
    case pinterest
    case recipeText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Take a photo"
        case .photoLibrary: "Upload photo"
        case .recipeLink: "Paste a link"
        case .pinterest: "Pinterest"
        case .recipeText: "Paste recipe"
        }
    }

    var shortTitle: String {
        switch self {
        case .camera: "Camera"
        case .photoLibrary: "Photos"
        case .recipeLink: "Link"
        case .pinterest: "Pinterest"
        case .recipeText: "Text"
        }
    }

    var subtitle: String {
        switch self {
        case .camera: "Scan a cookbook or card"
        case .photoLibrary: "Use a saved screenshot"
        case .recipeLink: "Import recipe page data"
        case .pinterest: "Use a recipe pin link"
        case .recipeText: "Paste an ingredient list"
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .photoLibrary: "photo.on.rectangle.angled"
        case .recipeLink: "link"
        case .pinterest: "p.circle.fill"
        case .recipeText: "doc.text.fill"
        }
    }

    var tint: Color {
        switch self {
        case .camera: SmartCartTheme.walmartBlue
        case .photoLibrary: Color(red: 0.37, green: 0.36, blue: 0.82)
        case .recipeLink: SmartCartTheme.navy
        case .pinterest: Color(red: 0.83, green: 0.08, blue: 0.17)
        case .recipeText: SmartCartTheme.green
        }
    }
}

enum SheetDestination: Identifiable {
    case importer(ImportMethod, String? = nil)

    var id: String {
        switch self {
        case .importer(let method, _): "importer-\(method.rawValue)"
        }
    }
}

enum RecipeLinkInput {
    static func validHTTPSURL(from text: String) -> URL? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else { return nil }
        return url
    }

    static func source(for url: URL) -> RecipeSource {
        guard let host = url.host?.lowercased() else { return .link }
        return host == "pin.it" || host == "pinterest.com" || host.hasSuffix(".pinterest.com")
            ? .pinterest
            : .link
    }
}

enum RecipeSource: String, CaseIterable, Hashable, Codable {
    case photo = "Recipe photo"
    case link = "Recipe link"
    case pinterest = "Pinterest"
    case text = "Pasted text"
    case sample = "SmartCart sample"
}

/// A persisted OCR candidate kept independently from layout reconstruction and parsing.
struct RecipeSourceTextAlternative: Hashable, Codable {
    var text: String
    var confidence: Double
}

/// One raw OCR observation in normalized, orientation-corrected image coordinates.
struct RecipeSourceObservation: Hashable, Codable {
    var observationID: String
    var text: String
    var pageIndex: Int
    var boundingBox: NormalizedSourceRect
    var confidence: Double
    var alternatives: [RecipeSourceTextAlternative]
    /// Stable order supplied by Vision before reconstruction sorts by geometry.
    var originalOrder: Int? = nil
}

/// The immutable source snapshot for a photo recipe. Raw Vision output is retained
/// separately from reconstructed and parser-filtered text so later review never has
/// to infer what the camera originally recognized.
struct RecipeSourceDocument: Hashable, Codable {
    var rawRecognizedText: String
    var reconstructedText: String
    var filteredIngredientLines: [String]
    var ignoredSourceLines: [String]
    var observations: [RecipeSourceObservation]
    /// Per-page, non-destructive OCR focus regions in top-left normalized coordinates.
    var focusRegions: [OCRFocusRegion]? = nil
}

struct Recipe: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var source: RecipeSource
    var sourceDetail: String
    var heroSymbol: String
    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var ingredients: [Ingredient]
    /// Original recognized or pasted text retained for explicit source review.
    /// Optional decoding keeps pre-existing schema-v0 through schema-v6 recipes compatible.
    var rawSourceText: String?
    /// Full photo-OCR provenance. Missing from older schema-v6 payloads by design.
    var sourceDocument: RecipeSourceDocument?

    init(
        id: UUID = UUID(),
        title: String,
        source: RecipeSource,
        sourceDetail: String,
        heroSymbol: String,
        servings: Int,
        prepMinutes: Int,
        cookMinutes: Int,
        ingredients: [Ingredient],
        rawSourceText: String? = nil,
        sourceDocument: RecipeSourceDocument? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.sourceDetail = sourceDetail
        self.heroSymbol = heroSymbol
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.ingredients = ingredients
        self.rawSourceText = rawSourceText
        self.sourceDocument = sourceDocument
    }

    var totalMinutes: Int { prepMinutes + cookMinutes }
}

/// Recipe-level interaction history used only to order the Recent Recipes UI.
/// Shopping-product navigation never writes this record.
struct RecentRecipeRecord: Identifiable, Hashable, Codable {
    var id: UUID { recipeID }
    let recipeID: UUID
    var lastOpenedAt: Date

    init(recipeID: UUID, lastOpenedAt: Date = .now) {
        self.recipeID = recipeID
        self.lastOpenedAt = lastOpenedAt
    }
}

struct Ingredient: Identifiable, Hashable, Codable {
    let id: UUID
    var rawText: String
    var name: String
    var quantity: Double
    /// Qualitative recipe amount supplied by the source when no numeric
    /// quantity exists (for example, "to taste" or "as needed"). A zero
    /// numeric quantity plus this field is intentional and must never be
    /// rewritten to an invented `1`.
    var semanticQuantity: String?
    /// Lower end of an explicit recipe range. `quantity` remains the upper
    /// end so package math stays conservative (for example, 2–3 lemons buys
    /// for 3), while review UI can preserve what the recipe actually said.
    var quantityLowerBound: Double?
    var unit: String
    var preparation: String
    var category: GroceryCategory
    var confidence: IngredientConfidence
    var includeInList: Bool
    var pantryState: PantryState
    var preferenceNote: String
    var sectionName: String?
    var brandNote: String?
    var compoundMeasurements: [IngredientMeasurement]?
    var equivalentMeasurements: [IngredientMeasurement]?
    var alternativeGroup: String?
    var sourceEvidence: IngredientSourceEvidence?
    var quantityReviewRequired: Bool?
    var pantrySuggestion: PantrySuggestion?
    var pantryDecision: PantryDecision?
    /// A pantry product the user prefers for this semantic ingredient. The
    /// recipe name remains unchanged so quantity, aggregation, and identity
    /// safety continue to operate on the ingredient rather than a package.
    var preferredPantryItemID: UUID?
    var preferredProductName: String?

    init(
        id: UUID = UUID(),
        rawText: String = "",
        name: String,
        quantity: Double = 1,
        semanticQuantity: String? = nil,
        quantityLowerBound: Double? = nil,
        unit: String = "",
        preparation: String = "",
        category: GroceryCategory = .pantry,
        confidence: IngredientConfidence = .high,
        includeInList: Bool = true,
        pantryState: PantryState = .needToBuy,
        preferenceNote: String = "",
        sectionName: String? = nil,
        brandNote: String? = nil,
        compoundMeasurements: [IngredientMeasurement]? = nil,
        equivalentMeasurements: [IngredientMeasurement]? = nil,
        alternativeGroup: String? = nil,
        sourceEvidence: IngredientSourceEvidence? = nil,
        quantityReviewRequired: Bool? = nil,
        pantrySuggestion: PantrySuggestion? = nil,
        pantryDecision: PantryDecision? = nil,
        preferredPantryItemID: UUID? = nil,
        preferredProductName: String? = nil
    ) {
        self.id = id
        self.rawText = rawText.isEmpty ? "\(quantity) \(unit) \(name)" : rawText
        self.name = name
        self.quantity = quantity
        self.semanticQuantity = semanticQuantity
        self.quantityLowerBound = quantityLowerBound
        self.unit = unit
        self.preparation = preparation
        self.category = category
        self.confidence = confidence
        self.includeInList = includeInList
        self.pantryState = pantryState
        self.preferenceNote = preferenceNote
        self.sectionName = sectionName
        self.brandNote = brandNote
        self.compoundMeasurements = compoundMeasurements
        self.equivalentMeasurements = equivalentMeasurements
        self.alternativeGroup = alternativeGroup
        self.sourceEvidence = sourceEvidence
        self.quantityReviewRequired = quantityReviewRequired
        self.pantrySuggestion = pantrySuggestion
        self.pantryDecision = pantryDecision
        self.preferredPantryItemID = preferredPantryItemID
        self.preferredProductName = preferredProductName
    }

    var displayQuantity: String {
        if let semanticQuantity = Self.normalizedSemanticQuantity(semanticQuantity) {
            return semanticQuantity
        }
        if quantity == 0, unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        if let quantityLowerBound,
           quantityLowerBound >= 0,
           quantityLowerBound < quantity {
            let lower = Self.quantityText(quantityLowerBound, unit: "")
            let upper = Self.quantityText(quantity, unit: unit)
            return "\(lower)–\(upper)"
        }
        return Self.quantityText(quantity, unit: unit)
    }

    var quantityInputText: String {
        if let semanticQuantity = Self.normalizedSemanticQuantity(semanticQuantity) {
            return semanticQuantity
        }
        guard quantity != 0 else { return "" }
        return Self.quantityText(quantity, unit: "")
    }

    func requestedQuantityText(numericQuantity: Double) -> String {
        quantity == 0 ? displayQuantity : Self.quantityText(numericQuantity, unit: unit)
    }

    func requestedAmount(numericQuantity: Double) -> Double? {
        quantity == 0 ? nil : numericQuantity
    }

    mutating func setQuantityInput(_ input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            quantity = 0
            quantityLowerBound = nil
            semanticQuantity = nil
            return
        }
        if let semantic = Self.normalizedSemanticQuantity(value) {
            quantity = 0
            quantityLowerBound = nil
            semanticQuantity = semantic
            return
        }
        if let numeric = Self.numericQuantityInput(value), numeric >= 0 {
            quantity = numeric
            quantityLowerBound = nil
            semanticQuantity = nil
            return
        }
        quantity = 0
        quantityLowerBound = nil
        semanticQuantity = value.lowercased()
    }

    static func normalizedSemanticQuantity(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return ["as needed", "to taste", "for frying"].contains(normalized)
            ? normalized
            : nil
    }

    private static func numericQuantityInput(_ value: String) -> Double? {
        let fractionMap: [Character: String] = [
            "¼": "1/4", "½": "1/2", "¾": "3/4", "⅓": "1/3", "⅔": "2/3",
            "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"
        ]
        var expanded = ""
        for character in value {
            if let fraction = fractionMap[character] {
                if expanded.last?.isNumber == true { expanded.append(" ") }
                expanded.append(fraction)
            } else {
                expanded.append(character)
            }
        }
        let parts = expanded.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return nil }
        func fraction(_ token: String) -> Double? {
            let values = token.split(separator: "/").compactMap { Double($0) }
            guard values.count == 2, values[1] != 0 else { return nil }
            return values[0] / values[1]
        }
        if parts.count == 2, let whole = Double(parts[0]), let remainder = fraction(parts[1]) {
            return whole + remainder
        }
        return fraction(parts[0]) ?? Double(parts[0])
    }

    static func quantityText(_ quantity: Double, unit: String) -> String {
        let value: String
        if quantity.rounded() == quantity {
            value = String(Int(quantity))
        } else if quantity < 1 {
            value = String(format: "%.2g", quantity)
        } else {
            value = String(format: "%.1f", quantity)
        }
        return unit.isEmpty ? value : "\(value) \(unit)"
    }
}

enum IngredientIssueSeverity: Int, Hashable {
    case ready
    case review
    case blocking
}

struct IngredientIssue: Identifiable, Hashable {
    let code: String
    let severity: IngredientIssueSeverity
    let message: String

    var id: String { code }
}

struct IngredientIssueAssessment: Hashable {
    var issues: [IngredientIssue]

    var blockingIssues: [IngredientIssue] { issues.filter { $0.severity == .blocking } }
    var reviewSuggestions: [IngredientIssue] { issues.filter { $0.severity == .review } }
    var hasBlockingIssues: Bool { !blockingIssues.isEmpty }
    var severity: IngredientIssueSeverity {
        if hasBlockingIssues { return .blocking }
        if !reviewSuggestions.isEmpty { return .review }
        return .ready
    }
}

/// The single interpretation of ingredient readiness used by Recipe Review,
/// retailer matching, navigation guards, and restored shopping sessions.
enum IngredientIssueEvaluator {
    static let blockingEvidenceReasons: Set<String> = [
        "contradictory_parsed_fields",
        "invalid_fraction_glyph",
        "malformed_measurement_structure",
        "measurement_token_in_name",
        "missing_expected_unit",
        "missing_ingredient_name",
        "unresolved_parse_conflict"
    ]

    static func assess(_ ingredient: Ingredient) -> IngredientIssueAssessment {
        guard ingredient.includeInList else { return IngredientIssueAssessment(issues: []) }
        var issues: [IngredientIssue] = []
        var seen = Set<String>()
        func append(_ code: String, _ severity: IngredientIssueSeverity, _ message: String) {
            guard seen.insert(code).inserted else { return }
            issues.append(IngredientIssue(code: code, severity: severity, message: message))
        }

        let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            append("missing_ingredient_name", .blocking, "Enter an ingredient name.")
        }
        if name.range(
            of: #"^(?:[%?](?=\s|$)|\d|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|(?:cups?|tbsp|tablespoons?|tsp|teaspoons?|oz|ounces?|lbs?|pounds?|grams?|kg|ml|liters?)\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            append(
                "measurement_token_in_name",
                .blocking,
                "Move the measurement out of the ingredient name."
            )
        }
        if isPreparationOnly(name) || isHeadingLike(name) {
            append("invalid_ingredient_identity", .blocking, "Enter a purchasable ingredient name.")
        }
        if ingredient.alternativeGroup != nil,
           name.range(
               of: #"\s+or\s+"#,
               options: [.regularExpression, .caseInsensitive]
           ) != nil {
            append("unresolved_alternative", .blocking, "Choose one ingredient option.")
        }
        if !ingredient.quantity.isFinite || ingredient.quantity < 0 {
            append("invalid_numeric_quantity", .blocking, "Enter a valid quantity.")
        }
        if ingredient.quantity > 0, ingredient.semanticQuantity != nil {
            append(
                "contradictory_parsed_fields",
                .blocking,
                "Use either a numeric or a qualitative quantity, not both."
            )
        }
        if let semantic = ingredient.semanticQuantity,
           Ingredient.normalizedSemanticQuantity(semantic) == nil {
            append(
                "unsupported_semantic_quantity",
                .blocking,
                "Use a number, leave quantity blank, or use as needed, to taste, or for frying."
            )
        }

        let evidenceReasons = ingredient.sourceEvidence?.reviewReasons ?? []
        for reason in evidenceReasons where blockingEvidenceReasons.contains(reason) {
            append(reason, .blocking, blockingMessage(for: reason))
        }
        if ingredient.quantityReviewRequired == true {
            append("quantity_confirmation_required", .blocking, "Confirm the quantity before shopping.")
        }

        if !issues.contains(where: { $0.severity == .blocking }) {
            if evidenceReasons.contains("ocr_alternative_selected") {
                append("ocr_alternative_selected", .review, "OCR used a supported alternative; compare it with the source.")
            }
            if evidenceReasons.contains("instruction_suffix_removed") {
                append("instruction_suffix_removed", .review, "Cooking text was removed from this row.")
            }
            if let confidence = ingredient.sourceEvidence?.ocrConfidence, confidence < 0.72 {
                append("low_ocr_confidence", .review, "OCR confidence is low; compare this row with the source.")
            } else if ingredient.confidence == .review,
                      evidenceReasons.isEmpty,
                      ingredient.sourceEvidence?.parserConfidence ?? 1 < 0.8 {
                append("low_parser_confidence", .review, "The ingredient parse may need a quick check.")
            } else if ingredient.confidence == .unknown {
                append("unknown_ingredient", .review, "SmartCart could not confidently identify this ingredient.")
            }
        }

        return IngredientIssueAssessment(issues: issues)
    }

    static func hasBlockingIssues(in ingredients: [Ingredient]) -> Bool {
        ingredients.contains { assess($0).hasBlockingIssues }
    }

    static func resolveCorrectedStructure(
        previous: Ingredient,
        updated: Ingredient
    ) -> Ingredient {
        let fieldsChanged = previous.name != updated.name
            || previous.quantity != updated.quantity
            || previous.semanticQuantity != updated.semanticQuantity
            || previous.unit != updated.unit
            || previous.preparation != updated.preparation
        guard fieldsChanged else { return updated }

        var result = updated
        if structurallyValidFields(result) {
            result.quantityReviewRequired = false
            if var evidence = result.sourceEvidence {
                evidence.reviewReasons = evidence.reviewReasons?.filter {
                    !blockingEvidenceReasons.contains($0)
                }
                result.sourceEvidence = evidence
            }
            if assess(result).severity == .ready {
                result.confidence = .high
            }
        }
        return result
    }

    static func confirmCurrentStructure(_ ingredient: Ingredient) -> Ingredient {
        var result = ingredient
        guard structurallyValidFields(result) else { return result }
        result.quantityReviewRequired = false
        if var evidence = result.sourceEvidence {
            evidence.reviewReasons = evidence.reviewReasons?.filter {
                !blockingEvidenceReasons.contains($0)
            }
            result.sourceEvidence = evidence
        }
        return result
    }

    private static func structurallyValidFields(_ ingredient: Ingredient) -> Bool {
        var probe = ingredient
        probe.quantityReviewRequired = false
        if var evidence = probe.sourceEvidence {
            evidence.reviewReasons = evidence.reviewReasons?.filter {
                !blockingEvidenceReasons.contains($0)
            }
            probe.sourceEvidence = evidence
        }
        return !assess(probe).hasBlockingIssues
    }

    private static func isPreparationOnly(_ value: String) -> Bool {
        value.range(
            of: #"^(?:(?:or )?(?:(?:finely|freshly|coarsely|roughly)\s+)?(?:chopped|flaked|grated|shredded|diced|minced|sliced)|divided|optional|preferably|to taste|as needed|for frying|for (?:serving|garnish|topping))$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isHeadingLike(_ value: String) -> Bool {
        value.range(
            of: #"^for\s+(?:the\s+)?"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil || value.range(
            of: #"^(?:ingredients?|directions?|instructions?|method|shopping list|new ingredient)\s*:?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func blockingMessage(for reason: String) -> String {
        switch reason {
        case "invalid_fraction_glyph": "The source fraction could not be read safely."
        case "measurement_token_in_name": "Move the measurement out of the ingredient name."
        case "missing_expected_unit": "Confirm the missing measurement unit."
        case "missing_ingredient_name": "Enter an ingredient name."
        case "unresolved_parse_conflict": "Choose the correct interpretation from the source."
        default: "Correct the quantity, unit, and ingredient fields before shopping."
        }
    }
}

struct IngredientMeasurement: Hashable, Codable {
    var quantity: Double
    var unit: String
    var rawText: String

    init(quantity: Double, unit: String, rawText: String = "") {
        self.quantity = quantity
        self.unit = unit
        self.rawText = rawText.isEmpty ? Ingredient.quantityText(quantity, unit: unit) : rawText
    }
}

/// Human-friendly recipe quantity text. This formatter is presentation-only:
/// canonical quantities, matching inputs, and persisted request strings retain
/// their original numeric value and unit.
enum KitchenQuantityFormatter {
    private struct Fraction {
        let value: Double
        let text: String
    }

    private static let commonFractions = [
        Fraction(value: 1.0 / 8.0, text: "1/8"),
        Fraction(value: 1.0 / 4.0, text: "1/4"),
        Fraction(value: 1.0 / 3.0, text: "1/3"),
        Fraction(value: 3.0 / 8.0, text: "3/8"),
        Fraction(value: 1.0 / 2.0, text: "1/2"),
        Fraction(value: 5.0 / 8.0, text: "5/8"),
        Fraction(value: 2.0 / 3.0, text: "2/3"),
        Fraction(value: 3.0 / 4.0, text: "3/4"),
        Fraction(value: 7.0 / 8.0, text: "7/8")
    ]

    static func text(quantity: Double, unit: String) -> String {
        guard quantity.isFinite, quantity >= 0 else {
            return "Unknown quantity"
        }

        let preferred = preferredMeasurement(quantity: quantity, unit: unit)
        let value = fractionText(preferred.quantity)
        let displayUnit = displayUnit(preferred.unit, quantity: preferred.quantity)
        return displayUnit.isEmpty ? value : "\(value) \(displayUnit)"
    }

    private static func preferredMeasurement(
        quantity: Double,
        unit: String
    ) -> (quantity: Double, unit: String) {
        let normalizedUnit = QuantityEngine.normalizedUnit(for: unit)
        let shouldPromoteToCups =
            (normalizedUnit == "tbsp" && quantity >= 16) ||
            (normalizedUnit == "tsp" && quantity >= 48)

        if shouldPromoteToCups,
           let converted = QuantityEngine.convertedValue(
               doubleValue: quantity,
               from: normalizedUnit,
               to: "cup"
           ).quantity {
            return (
                NSDecimalNumber(decimal: converted.value).doubleValue,
                converted.unit
            )
        }

        return (quantity, normalizedUnit ?? unit.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func fractionText(_ quantity: Double) -> String {
        let whole = Int(quantity.rounded(.down))
        let remainder = quantity - Double(whole)
        if remainder < 0.001 {
            return String(whole)
        }

        if let fraction = commonFractions.min(by: {
            abs($0.value - remainder) < abs($1.value - remainder)
        }), abs(fraction.value - remainder) <= 0.04 {
            return whole == 0 ? fraction.text : "\(whole) \(fraction.text)"
        }

        return Ingredient.quantityText(quantity, unit: "")
    }

    private static func displayUnit(_ unit: String, quantity: Double) -> String {
        guard unit == "cup" else { return unit }
        return abs(quantity - 1) < 0.001 ? "cup" : "cups"
    }
}

struct NormalizedSourceRect: Hashable, Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum IngredientExtractionStrategy: String, Hashable, Codable {
    case pastedText
    case visionOCR
    case structuredData
    case visiblePageText
    case sample
    case manual
}

/// Optional durable locator for an OCR source crop. Slice 2 keeps existing
/// inline JPEG data unchanged; external blob storage is intentionally deferred.
struct IngredientSourceCropReference: Hashable, Codable {
    var sha256: String
    var byteCount: Int

    var isStructurallyValid: Bool {
        byteCount >= 0 && sha256.count == 64 && sha256.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}

struct IngredientSourceEvidence: Hashable, Codable {
    var rawText: String
    var pageIndex: Int?
    var boundingBox: NormalizedSourceRect?
    var extractionStrategy: IngredientExtractionStrategy
    var ocrConfidence: Double?
    var layoutConfidence: Double?
    var parserConfidence: Double
    var normalizationConfidence: Double
    var alternateQuantityCandidates: [Double]
    var alternateSourceTexts: [String]? = nil
    var sourceCropReference: IngredientSourceCropReference? = nil
    var sourceCropJPEGData: Data? = nil
    var ocrColumnIndex: Int? = nil
    var sourceObservationIDs: [String]? = nil
    var continuationAttached: Bool? = nil
    var reconstructionConfidence: Double? = nil
    var originalLine: String? = nil
    var removedSuffix: String? = nil
    var reviewReasons: [String]? = nil
}

extension IngredientSourceEvidence {
    private enum CodingKeys: String, CodingKey {
        case rawText
        case pageIndex
        case boundingBox
        case extractionStrategy
        case ocrConfidence
        case layoutConfidence
        case parserConfidence
        case normalizationConfidence
        case alternateQuantityCandidates
        case alternateSourceTexts
        case sourceCropReference
        case sourceCropJPEGData
        case ocrColumnIndex
        case sourceObservationIDs
        case continuationAttached
        case reconstructionConfidence
        case originalLine
        case removedSuffix
        case reviewReasons
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rawText = try values.decode(String.self, forKey: .rawText)
        pageIndex = try values.decodeIfPresent(Int.self, forKey: .pageIndex)
        boundingBox = try values.decodeIfPresent(NormalizedSourceRect.self, forKey: .boundingBox)
        extractionStrategy = try values.decode(IngredientExtractionStrategy.self, forKey: .extractionStrategy)
        ocrConfidence = try values.decodeIfPresent(Double.self, forKey: .ocrConfidence)
        layoutConfidence = try values.decodeIfPresent(Double.self, forKey: .layoutConfidence)
        parserConfidence = try values.decode(Double.self, forKey: .parserConfidence)
        normalizationConfidence = try values.decode(Double.self, forKey: .normalizationConfidence)
        alternateQuantityCandidates = try values.decode([Double].self, forKey: .alternateQuantityCandidates)
        alternateSourceTexts = try values.decodeIfPresent([String].self, forKey: .alternateSourceTexts)
        sourceCropReference = try? values.decodeIfPresent(
            IngredientSourceCropReference.self,
            forKey: .sourceCropReference
        )
        if sourceCropReference?.isStructurallyValid == false {
            sourceCropReference = nil
        }
        sourceCropJPEGData = try values.decodeIfPresent(Data.self, forKey: .sourceCropJPEGData)
        ocrColumnIndex = try values.decodeIfPresent(Int.self, forKey: .ocrColumnIndex)
        sourceObservationIDs = try values.decodeIfPresent([String].self, forKey: .sourceObservationIDs)
        continuationAttached = try values.decodeIfPresent(Bool.self, forKey: .continuationAttached)
        reconstructionConfidence = try values.decodeIfPresent(Double.self, forKey: .reconstructionConfidence)
        originalLine = try values.decodeIfPresent(String.self, forKey: .originalLine)
        removedSuffix = try values.decodeIfPresent(String.self, forKey: .removedSuffix)
        reviewReasons = try values.decodeIfPresent([String].self, forKey: .reviewReasons)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(rawText, forKey: .rawText)
        try values.encodeIfPresent(pageIndex, forKey: .pageIndex)
        try values.encodeIfPresent(boundingBox, forKey: .boundingBox)
        try values.encode(extractionStrategy, forKey: .extractionStrategy)
        try values.encodeIfPresent(ocrConfidence, forKey: .ocrConfidence)
        try values.encodeIfPresent(layoutConfidence, forKey: .layoutConfidence)
        try values.encode(parserConfidence, forKey: .parserConfidence)
        try values.encode(normalizationConfidence, forKey: .normalizationConfidence)
        try values.encode(alternateQuantityCandidates, forKey: .alternateQuantityCandidates)
        try values.encodeIfPresent(alternateSourceTexts, forKey: .alternateSourceTexts)
        try values.encodeIfPresent(sourceCropReference, forKey: .sourceCropReference)
        try values.encodeIfPresent(sourceCropJPEGData, forKey: .sourceCropJPEGData)
        try values.encodeIfPresent(ocrColumnIndex, forKey: .ocrColumnIndex)
        try values.encodeIfPresent(sourceObservationIDs, forKey: .sourceObservationIDs)
        try values.encodeIfPresent(continuationAttached, forKey: .continuationAttached)
        try values.encodeIfPresent(reconstructionConfidence, forKey: .reconstructionConfidence)
        try values.encodeIfPresent(originalLine, forKey: .originalLine)
        try values.encodeIfPresent(removedSuffix, forKey: .removedSuffix)
        try values.encodeIfPresent(reviewReasons, forKey: .reviewReasons)
    }
}

enum PantryCoverage: String, Hashable, Codable {
    case full
    case partial
    case possible
}

struct PantrySuggestion: Hashable, Codable {
    var pantryItemID: UUID
    var pantryItemName: String
    var coverage: PantryCoverage
    var availableQuantity: Double
    var availableUnit: String
    var requiredQuantity: Double
    var requiredUnit: String
    var matchScore: Double
}

enum PantryDecision: String, CaseIterable, Identifiable, Hashable, Codable {
    case review
    case useAvailable
    case buyFull

    var id: String { rawValue }
}

struct RecipeImportReport: Hashable {
    var sourcePageCount: Int
    var recognizedLineCount: Int
    var ingredientLineCount: Int
    var highConfidenceCount: Int
    var reviewCount: Int
    var unknownCount: Int
    var retryCount: Int
    var duration: TimeInterval
    var layoutConfidence: Double = 1
    var layoutAmbiguityCount: Int = 0
    var ignoredInstructionLineCount: Int = 0
    var sourceEvidenceCount: Int = 0
    var quantityAlternativeReviewCount: Int = 0
    var omittedCandidateLineCount: Int = 0
    var requiredConfirmationCount: Int = 0

    var confidenceScore: Double {
        guard ingredientLineCount > 0 else { return 0 }
        let weighted = Double(highConfidenceCount) + Double(reviewCount) * 0.55
        return min(1, max(0, weighted / Double(ingredientLineCount)))
    }

    var confidenceLabel: String {
        if omittedCandidateLineCount > 0 || requiredConfirmationCount > 0 {
            return "Needs review"
        }
        return switch confidenceScore {
        case 0.82...: "High confidence"
        case 0.55...: "Review suggested"
        default: "Needs review"
        }
    }
}

enum IngredientConfidence: String, CaseIterable, Identifiable, Hashable, Codable {
    case high = "High confidence"
    case review = "Review suggested"
    case unknown = "Could not identify"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: "High confidence"
        case .review: "Review"
        case .unknown: "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .high: "checkmark.circle.fill"
        case .review: "exclamationmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .high: SmartCartTheme.green
        case .review: SmartCartTheme.amber
        case .unknown: SmartCartTheme.coral
        }
    }
}

enum PantryState: String, CaseIterable, Identifiable, Hashable, Codable {
    case haveEnough = "Have enough"
    case runningLow = "Running low"
    case needToBuy = "Need to buy"
    case alwaysAsk = "Always ask"
    case exclude = "Exclude"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .haveEnough: "Have enough"
        case .runningLow: "Running low"
        case .needToBuy: "Need to buy"
        case .alwaysAsk: "Ask me"
        case .exclude: "Exclude"
        }
    }

    var symbol: String {
        switch self {
        case .haveEnough: "checkmark.seal.fill"
        case .runningLow: "clock.badge.exclamationmark.fill"
        case .needToBuy: "cart.badge.plus"
        case .alwaysAsk: "questionmark.bubble.fill"
        case .exclude: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .haveEnough: SmartCartTheme.green
        case .runningLow: SmartCartTheme.amber
        case .needToBuy: SmartCartTheme.walmartBlue
        case .alwaysAsk: SmartCartTheme.purple
        case .exclude: SmartCartTheme.secondaryInk
        }
    }
}

enum GroceryCategory: String, CaseIterable, Hashable, Codable {
    case produce = "Produce"
    case dairy = "Dairy"
    case meat = "Meat & Seafood"
    case bakery = "Bakery"
    case pantry = "Pantry"
    case frozen = "Frozen"

    var symbol: String {
        switch self {
        case .produce: "leaf.fill"
        case .dairy: "waterbottle.fill"
        case .meat: "fork.knife"
        case .bakery: "birthday.cake.fill"
        case .pantry: "cabinet.fill"
        case .frozen: "snowflake"
        }
    }
}

enum StoreStrategy: String, CaseIterable, Identifiable, Hashable, Codable {
    case oneStore = "One store"
    case multipleStops = "Multiple stops"

    var id: String { rawValue }
}

enum FulfillmentMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case pickup = "Pickup"
    case delivery = "Delivery"

    var id: String { rawValue }
}

struct RetailerStore: Identifiable, Hashable, Codable {
    let id: UUID
    var retailerID: String
    var retailerStoreID: String
    var name: String
    var format: String
    var address: String
    var distance: Double
    var pickupWindow: String
    var supportsPickup: Bool
    var supportsDelivery: Bool

    init(
        id: UUID = UUID(),
        retailerID: String = "walmart",
        retailerStoreID: String,
        name: String,
        format: String,
        address: String,
        distance: Double,
        pickupWindow: String,
        supportsPickup: Bool = true,
        supportsDelivery: Bool = true
    ) {
        self.id = id
        self.retailerID = retailerID
        self.retailerStoreID = retailerStoreID
        self.name = name
        self.format = format
        self.address = address
        self.distance = distance
        self.pickupWindow = pickupWindow
        self.supportsPickup = supportsPickup
        self.supportsDelivery = supportsDelivery
    }
}

enum PantryItemSource: String, Codable, Hashable {
    case barcode
    case recipe
    case manual

    var label: String {
        switch self {
        case .barcode: "Barcode scan"
        case .recipe: "Recipe decision"
        case .manual: "Manual entry"
        }
    }
}

/// One independently evidenced exact-identity value. Legacy display mirrors
/// such as `upc`, `gtin14`, and `preferredRetailerProductID` are intentionally
/// not promoted into trusted identity during decoding.
struct PantryIdentityClaim: Hashable, Codable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case gtin14
        case scopedRetailerProductID
    }

    enum Evidence: String, Codable, Hashable, Sendable {
        case barcodeScan
        case exactPurchase
    }

    let kind: Kind
    let normalizedValue: String
    let evidence: Evidence
    let normalizationVersion: Int

    static func observedBarcode(_ barcode: NormalizedBarcode) -> PantryIdentityClaim {
        PantryIdentityClaim(
            kind: .gtin14,
            normalizedValue: barcode.canonicalGTIN14,
            evidence: .barcodeScan,
            normalizationVersion: ExactProductIdentity.currentNormalizationVersion
        )
    }

    static func exactPurchaseGTIN(_ canonicalGTIN14: String) -> PantryIdentityClaim {
        PantryIdentityClaim(
            kind: .gtin14,
            normalizedValue: canonicalGTIN14,
            evidence: .exactPurchase,
            normalizationVersion: ExactProductIdentity.currentNormalizationVersion
        )
    }

    static func exactPurchaseRetailerProductID(
        _ scopedRetailerProductID: String
    ) -> PantryIdentityClaim {
        PantryIdentityClaim(
            kind: .scopedRetailerProductID,
            normalizedValue: scopedRetailerProductID,
            evidence: .exactPurchase,
            normalizationVersion: ExactProductIdentity.currentNormalizationVersion
        )
    }
}

struct PantryInventoryItem: Identifiable, Hashable, Codable {
    let id: UUID
    var upc: String?
    var name: String
    var brand: String
    /// Legacy package-count mirrors retained for schema-v1...v4 state and old
    /// call sites. New pantry math uses `packageCount` and remaining quantity.
    var quantity: Double
    var unit: String
    var preferredRetailerProductID: String?
    /// The generic ingredient name used by recipes, such as `coffee`. This is
    /// distinct from the branded package name and from inventory quantity.
    var preferredIngredientName: String?
    /// Nil lets older saved products use conservative inference. False is an
    /// explicit opt-out; true is an explicit user preference.
    var isRecipeFavorite: Bool?
    /// Persisted value-level proof used for exact matching. The neighboring
    /// UPC, GTIN, and retailer fields remain compatibility/display mirrors.
    private(set) var identityClaims: [PantryIdentityClaim]
    var source: PantryItemSource
    var updatedAt: Date
    var packageCount: Double
    var packageSize: Double?
    var packageUnit: String?
    var remainingAmount: Double
    var remainingUnit: String
    var requiresUserNaming: Bool?
    var rawBarcode: String?
    var barcodeSymbology: String?
    var gtin14: String?
    /// Every normalized barcode observed for this pantry item. Optional keeps
    /// older persisted states migration-safe; `gtin14` remains the primary
    /// legacy identity while this array records additional package barcodes.
    var barcodeGTINs: [String]?
    /// True when packages are known to exist but their physical mass was not
    /// confirmed. Such inventory must never satisfy exact mass deductions.
    var hasUnknownPackageMass: Bool?

    init(
        id: UUID = UUID(),
        upc: String? = nil,
        name: String,
        brand: String = "",
        quantity: Double = 1,
        unit: String = "item",
        preferredRetailerProductID: String? = nil,
        preferredIngredientName: String? = nil,
        isRecipeFavorite: Bool? = nil,
        identityClaims: [PantryIdentityClaim] = [],
        source: PantryItemSource = .manual,
        updatedAt: Date = .now,
        packageCount: Double? = nil,
        packageSize: Double? = nil,
        packageUnit: String? = nil,
        remainingAmount: Double? = nil,
        remainingUnit: String? = nil,
        requiresUserNaming: Bool? = nil,
        rawBarcode: String? = nil,
        barcodeSymbology: String? = nil,
        gtin14: String? = nil,
        barcodeGTINs: [String]? = nil,
        hasUnknownPackageMass: Bool? = nil
    ) {
        self.id = id
        self.upc = upc
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.unit = unit
        self.preferredRetailerProductID = preferredRetailerProductID
        self.preferredIngredientName = preferredIngredientName
        self.isRecipeFavorite = isRecipeFavorite
        self.identityClaims = Self.canonicalizedIdentityClaims(identityClaims)
        self.source = source
        self.updatedAt = updatedAt
        let resolvedPackageCount = max(0, packageCount ?? quantity)
        self.packageCount = resolvedPackageCount
        self.packageSize = packageSize
        self.packageUnit = packageUnit
        self.remainingAmount = max(
            0,
            remainingAmount ?? packageSize.map { resolvedPackageCount * $0 } ?? resolvedPackageCount
        )
        self.remainingUnit = remainingUnit ?? packageUnit ?? unit
        self.requiresUserNaming = requiresUserNaming
        self.rawBarcode = rawBarcode
        self.barcodeSymbology = barcodeSymbology
        self.gtin14 = gtin14
        if let barcodeGTINs {
            self.barcodeGTINs = Array(Set(barcodeGTINs)).sorted()
        } else if let gtin14 {
            self.barcodeGTINs = [gtin14]
        } else {
            self.barcodeGTINs = nil
        }
        self.hasUnknownPackageMass = hasUnknownPackageMass
    }

    private enum CodingKeys: String, CodingKey {
        case id, upc, name, brand, quantity, unit, preferredRetailerProductID
        case preferredIngredientName, isRecipeFavorite
        case identityClaims
        case source, updatedAt, packageCount, packageSize, packageUnit
        case remainingAmount, remainingUnit, requiresUserNaming, rawBarcode
        case barcodeSymbology, gtin14, barcodeGTINs, hasUnknownPackageMass
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        upc = try values.decodeIfPresent(String.self, forKey: .upc)
        name = try values.decode(String.self, forKey: .name)
        brand = try values.decode(String.self, forKey: .brand)
        quantity = try values.decode(Double.self, forKey: .quantity)
        unit = try values.decode(String.self, forKey: .unit)
        preferredRetailerProductID = try values.decodeIfPresent(String.self, forKey: .preferredRetailerProductID)
        preferredIngredientName = try values.decodeIfPresent(String.self, forKey: .preferredIngredientName)
        isRecipeFavorite = try values.decodeIfPresent(Bool.self, forKey: .isRecipeFavorite)
        identityClaims = Self.canonicalizedIdentityClaims(
            try values.decodeIfPresent([PantryIdentityClaim].self, forKey: .identityClaims) ?? []
        )
        source = try values.decode(PantryItemSource.self, forKey: .source)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        packageSize = try values.decodeIfPresent(Double.self, forKey: .packageSize)
        packageUnit = try values.decodeIfPresent(String.self, forKey: .packageUnit)

        let decodedPackageCount = try values.decodeIfPresent(Double.self, forKey: .packageCount)
        let resolvedPackageCount = max(0, decodedPackageCount ?? quantity)
        packageCount = resolvedPackageCount
        let decodedRemainingAmount = try values.decodeIfPresent(Double.self, forKey: .remainingAmount)
        let resolvedRemainingAmount = if let decodedRemainingAmount {
            decodedRemainingAmount
        } else if let packageSize {
            resolvedPackageCount * packageSize
        } else {
            resolvedPackageCount
        }
        remainingAmount = max(
            0,
            resolvedRemainingAmount
        )
        remainingUnit = try values.decodeIfPresent(String.self, forKey: .remainingUnit)
            ?? packageUnit
            ?? unit

        requiresUserNaming = try values.decodeIfPresent(Bool.self, forKey: .requiresUserNaming)
        rawBarcode = try values.decodeIfPresent(String.self, forKey: .rawBarcode)
        barcodeSymbology = try values.decodeIfPresent(String.self, forKey: .barcodeSymbology)
        gtin14 = try values.decodeIfPresent(String.self, forKey: .gtin14)
        barcodeGTINs = try values.decodeIfPresent([String].self, forKey: .barcodeGTINs)
        hasUnknownPackageMass = try values.decodeIfPresent(Bool.self, forKey: .hasUnknownPackageMass)
    }

    mutating func setPackageCount(_ value: Double) {
        addPackages(max(0, value) - packageCount)
    }

    mutating func addPackages(
        _ amount: Double,
        packageSize incomingPackageSize: Double? = nil,
        packageUnit incomingPackageUnit: String? = nil
    ) {
        let previousCount = packageCount
        let updatedCount = max(0, previousCount + amount)
        let appliedDelta = updatedCount - previousCount
        packageCount = updatedCount
        quantity = updatedCount

        if packageSize == nil, let incomingPackageSize {
            packageSize = incomingPackageSize
        }
        if packageUnit == nil, let incomingPackageUnit, !incomingPackageUnit.isEmpty {
            packageUnit = incomingPackageUnit
        }

        if let resolvedSize = packageSize,
           let resolvedUnit = packageUnit,
           !resolvedUnit.isEmpty {
            let unitChanged = remainingUnit.compare(
                resolvedUnit,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != .orderedSame
            if unitChanged {
                // Legacy package counts had no content unit. Once exact package
                // metadata arrives, derive a coherent remaining amount.
                remainingAmount = updatedCount * resolvedSize
                remainingUnit = resolvedUnit
            } else {
                remainingAmount = max(0, remainingAmount + (appliedDelta * resolvedSize))
            }
        } else {
            remainingAmount = max(0, remainingAmount + appliedDelta)
            remainingUnit = unit
        }
    }

    func matches(barcode: NormalizedBarcode) -> Bool {
        claimedGTIN14s.contains(barcode.canonicalGTIN14)
    }

    mutating func register(
        barcode: NormalizedBarcode,
        rawValue: String,
        symbology: String?
    ) {
        if upc == nil { upc = barcode.digits }
        if gtin14 == nil { gtin14 = barcode.canonicalGTIN14 }
        if rawBarcode == nil { rawBarcode = rawValue }
        if barcodeSymbology == nil { barcodeSymbology = symbology }

        var identities = barcodeGTINs ?? []
        if let primary = gtin14, !identities.contains(primary) {
            identities.append(primary)
        }
        if !identities.contains(barcode.canonicalGTIN14) {
            identities.append(barcode.canonicalGTIN14)
        }
        barcodeGTINs = identities.sorted()
        addIdentityClaims([.observedBarcode(barcode)])
    }

    var claimedGTIN14s: Set<String> {
        Set(identityClaims.compactMap { claim in
            guard let claim = Self.validatedIdentityClaim(claim),
                  claim.kind == .gtin14 else { return nil }
            return claim.normalizedValue
        })
    }

    var claimedScopedRetailerProductIDs: Set<String> {
        Set(identityClaims.compactMap { claim in
            guard let claim = Self.validatedIdentityClaim(claim),
                  claim.kind == .scopedRetailerProductID else { return nil }
            return claim.normalizedValue
        })
    }

    mutating func addIdentityClaims(_ claims: [PantryIdentityClaim]) {
        identityClaims = Self.canonicalizedIdentityClaims(identityClaims + claims)
    }

    private static func canonicalizedIdentityClaims(
        _ claims: [PantryIdentityClaim]
    ) -> [PantryIdentityClaim] {
        Array(Set(claims.compactMap(validatedIdentityClaim))).sorted { first, second in
            if first.kind.rawValue != second.kind.rawValue {
                return first.kind.rawValue < second.kind.rawValue
            }
            if first.normalizedValue != second.normalizedValue {
                return first.normalizedValue < second.normalizedValue
            }
            if first.evidence.rawValue != second.evidence.rawValue {
                return first.evidence.rawValue < second.evidence.rawValue
            }
            return first.normalizationVersion < second.normalizationVersion
        }
    }

    private static func validatedIdentityClaim(
        _ claim: PantryIdentityClaim
    ) -> PantryIdentityClaim? {
        guard claim.normalizationVersion == ExactProductIdentity.currentNormalizationVersion else {
            return nil
        }

        switch claim.kind {
        case .gtin14:
            guard case .success(let barcode) = BarcodeNormalizer.normalize(claim.normalizedValue),
                  barcode.canonicalGTIN14 == claim.normalizedValue else { return nil }
        case .scopedRetailerProductID:
            let value = claim.normalizedValue
            guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
                  let separator = value.firstIndex(of: ":") else { return nil }
            let retailerID = String(value[..<separator])
            let productID = String(value[value.index(after: separator)...])
            let normalizedRetailerID = retailerID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
                .lowercased()
            let normalizedProductID = productID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            guard !normalizedRetailerID.isEmpty,
                  !normalizedProductID.isEmpty,
                  retailerID == normalizedRetailerID,
                  productID == normalizedProductID else { return nil }
        }
        return claim
    }
}

enum AnalyticsEventName: String, CaseIterable, Codable, Hashable {
    case importStarted = "import_started"
    case extractionCompleted = "extraction_completed"
    case ingredientsCorrected = "ingredients_corrected"
    case matchingCompleted = "matching_completed"
    case productReplaced = "product_replaced"
    case retailerLinkOpened = "retailer_link_opened"
    case handoffFeedbackRecorded = "handoff_feedback_recorded"
    case guidedItemCompleted = "guided_item_completed"
    case guidedShoppingCompleted = "guided_shopping_completed"
    case retailerSetupStarted = "retailer_setup_started"
    case retailerSetupCompleted = "retailer_setup_completed"
    case shoppingSessionStarted = "shopping_session_started"
    case shoppingSessionResumed = "shopping_session_resumed"
    case shoppingSessionPaused = "shopping_session_paused"
    case barcodeScanned = "barcode_scanned"
    case pantryItemAdded = "pantry_item_added"
    case walmartSetupStarted = "walmart_setup_started"
    case walmartWishlistURLSaved = "walmart_wishlist_url_saved"
    case walmartProductOpened = "walmart_product_opened"
    case walmartProductSelfReportedSaved = "walmart_product_self_reported_saved"
    case walmartGuidedFlowCompleted = "walmart_guided_flow_completed"
    case walmartWishlistOpened = "walmart_wishlist_opened"
    case shoppingReconciliationStarted = "shopping_reconciliation_started"
    case shoppingOutcomeRecorded = "shopping_outcome_recorded"
    case pantryReconciliationCommitted = "pantry_reconciliation_committed"
    case substitutionRecorded = "substitution_recorded"
}

struct AnalyticsEvent: Identifiable, Hashable, Codable {
    let id: UUID
    var name: AnalyticsEventName
    var timestamp: Date
    var properties: [String: String]

    init(
        id: UUID = UUID(),
        name: AnalyticsEventName,
        timestamp: Date = .now,
        properties: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.properties = properties
    }
}

enum GuidedItemStatus: String, Hashable, Codable {
    case waiting
    /// The user explicitly advanced after viewing the retailer page. This is
    /// not evidence that the product was saved, added, ordered, or purchased.
    case visited
    /// Retained so schema-v3 state remains decodable. New Walmart flows use
    /// the explicit self-reported outcomes below.
    case added
    case savedToWishlist = "saved_to_wishlist"
    case addedToCart = "added_to_cart"
    case unavailable
    case skipped

    var isCompleted: Bool { self != .waiting }
}

enum RetailerGuideContinuation: Equatable {
    case nextItem(UUID)
    case cart(ShoppingRetailer)
}

struct ShoppingListItem: Identifiable, Hashable, Codable {
    let id: UUID
    var ingredient: Ingredient
    var requestedQuantity: String
    var requestedAmount: Double?
    var purchaseQuantity: Int
    var product: RetailerProductRecord
    var alternatives: [RetailerProductRecord]
    var storeID: UUID
    var status: GuidedItemStatus
    var matchScore: Double
    var selectionReasons: [String]
    /// Stable identity for every non-quantity input that can affect matching.
    /// Optional so schema-v6 and older persisted items remain decodable.
    var matchingContextFingerprint: String?
    /// `matchingContextFingerprint` plus the requested quantity.
    var matchingInputFingerprint: String?
    /// The exact matching input the user explicitly reviewed, when needed.
    var reviewedMatchingFingerprint: String?
    /// Optional frozen purchase-group metadata. Missing legacy fields decode
    /// as nil, so historical Shopping Trips are not regrouped by this slice.
    var purchaseGroup: ProductPurchaseGroup?

    init(
        id: UUID = UUID(),
        ingredient: Ingredient,
        requestedQuantity: String,
        requestedAmount: Double? = nil,
        purchaseQuantity: Int = 1,
        product: RetailerProductRecord,
        alternatives: [RetailerProductRecord],
        storeID: UUID,
        status: GuidedItemStatus = .waiting,
        matchScore: Double = 0,
        selectionReasons: [String] = [],
        matchingContextFingerprint: String? = nil,
        matchingInputFingerprint: String? = nil,
        reviewedMatchingFingerprint: String? = nil,
        purchaseGroup: ProductPurchaseGroup? = nil
    ) {
        self.id = id
        self.ingredient = ingredient
        self.requestedQuantity = requestedQuantity
        self.requestedAmount = requestedAmount
        self.purchaseQuantity = purchaseQuantity
        self.product = product
        self.alternatives = alternatives
        self.storeID = storeID
        self.status = status
        self.matchScore = matchScore
        self.selectionReasons = selectionReasons
        self.matchingContextFingerprint = matchingContextFingerprint
        self.matchingInputFingerprint = matchingInputFingerprint
        self.reviewedMatchingFingerprint = reviewedMatchingFingerprint
        self.purchaseGroup = purchaseGroup
    }

    var lineTotal: Double {
        product.price * Double(purchaseQuantity)
    }
}

extension ShoppingListItem {
    private enum CodingKeys: String, CodingKey {
        case id
        case ingredient
        case requestedQuantity
        case requestedAmount
        case purchaseQuantity
        case product
        case alternatives
        case storeID
        case status
        case matchScore
        case selectionReasons
        case matchingContextFingerprint
        case matchingInputFingerprint
        case reviewedMatchingFingerprint
        case purchaseGroup
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        ingredient = try values.decode(Ingredient.self, forKey: .ingredient)
        requestedQuantity = try values.decode(String.self, forKey: .requestedQuantity)
        requestedAmount = try values.decodeIfPresent(Double.self, forKey: .requestedAmount)
        purchaseQuantity = try values.decode(Int.self, forKey: .purchaseQuantity)
        product = try values.decode(RetailerProductRecord.self, forKey: .product)
        alternatives = try values.decode([RetailerProductRecord].self, forKey: .alternatives)
        storeID = try values.decode(UUID.self, forKey: .storeID)
        status = try values.decode(GuidedItemStatus.self, forKey: .status)
        matchScore = try values.decode(Double.self, forKey: .matchScore)
        selectionReasons = try values.decode([String].self, forKey: .selectionReasons)
        matchingContextFingerprint = try values.decodeIfPresent(
            String.self,
            forKey: .matchingContextFingerprint
        )
        matchingInputFingerprint = try values.decodeIfPresent(
            String.self,
            forKey: .matchingInputFingerprint
        )
        reviewedMatchingFingerprint = try values.decodeIfPresent(
            String.self,
            forKey: .reviewedMatchingFingerprint
        )
        purchaseGroup = try? values.decodeIfPresent(
            ProductPurchaseGroup.self,
            forKey: .purchaseGroup
        )
    }
}

enum ShoppingTripOutcome: String, CaseIterable, Identifiable, Codable, Hashable {
    case boughtEverything = "bought_everything"
    case boughtMost = "bought_most"
    case boughtFew = "bought_few"
    case didNotShop = "did_not_shop"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .boughtEverything: "Bought all available items"
        case .boughtMost: "Bought most items"
        case .boughtFew: "Bought only a few items"
        case .didNotShop: "Didn’t shop"
        }
    }

    var guidance: String {
        switch self {
        case .boughtEverything: "Available items start selected; you can add anything bought elsewhere or substituted."
        case .boughtMost: "Tap only the items you did not buy."
        case .boughtFew: "Tap the few items you did buy."
        case .didNotShop: "Nothing in your pantry will change."
        }
    }

    var symbol: String {
        switch self {
        case .boughtEverything: "checkmark.circle.fill"
        case .boughtMost: "checklist.checked"
        case .boughtFew: "hand.tap.fill"
        case .didNotShop: "xmark.circle"
        }
    }
}

struct ShoppingSubstitutionFeedback: Identifiable, Codable, Hashable {
    let id: UUID
    var originalItemID: UUID
    var replacementName: String
    var replacementBrand: String
    var replacementRetailerProductID: String?
    var replacementGTIN14: String?
    var packageQuantity: Double?
    var packageUnit: String?
    var replacementAmount: Double?
    var preferNextTime: Bool
    var recordedAt: Date

    init(
        id: UUID = UUID(),
        originalItemID: UUID,
        replacementName: String,
        replacementBrand: String = "",
        replacementRetailerProductID: String? = nil,
        replacementGTIN14: String? = nil,
        packageQuantity: Double? = nil,
        packageUnit: String? = nil,
        replacementAmount: Double? = nil,
        preferNextTime: Bool = false,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.originalItemID = originalItemID
        self.replacementName = replacementName
        self.replacementBrand = replacementBrand
        self.replacementRetailerProductID = replacementRetailerProductID
        self.replacementGTIN14 = replacementGTIN14
        self.packageQuantity = packageQuantity
        self.packageUnit = packageUnit
        self.replacementAmount = replacementAmount
        self.preferNextTime = preferNextTime
        self.recordedAt = recordedAt
    }
}

struct ShoppingReconciliationRecord: Codable, Hashable {
    var outcome: ShoppingTripOutcome
    var purchasedItemIDs: Set<UUID>
    var substitutions: [ShoppingSubstitutionFeedback]
    var pantryItemIDs: Set<UUID>
    var committedAt: Date
    var acquisitions: [PantryAcquisition]? = nil
    /// Durable idempotency key for the logical trip that produced this
    /// transaction. Optional only so pre-v6 records remain decodable.
    var logicalTripID: UUID? = nil
}

struct ShoppingReconciliationDraft: Codable, Hashable {
    var outcome: ShoppingTripOutcome?
    var purchasedItemIDs: Set<UUID>
    var substitutions: [ShoppingSubstitutionFeedback]
    var updatedAt: Date
}

/// The only two pieces of durable trip work Home is allowed to expose.
/// Display details are projected separately so the view never interprets a
/// complete shopping session or persists presentation state.
enum HomeTripAction: Identifiable, Equatable {
    case resume(sessionID: UUID)
    case updatePantry(sessionID: UUID)

    var sessionID: UUID {
        switch self {
        case .resume(let sessionID), .updatePantry(let sessionID):
            sessionID
        }
    }

    var id: UUID { sessionID }
}

struct HomeTripActionPresentation: Identifiable, Equatable {
    let action: HomeTripAction
    let title: String
    let detail: String

    var id: UUID { action.id }
}

struct ShoppingSession: Identifiable, Codable, Hashable {
    let id: UUID
    /// Retained for decoding repair-candidate state written before the
    /// logical-trip identity was carried by manifests and reconciliation.
    var tripID: UUID?
    var logicalTripID: UUID?
    var recipeID: UUID
    var recipeTitle: String
    var manifestID: UUID?
    var storeID: String
    var retailerID: String?
    var desiredServings: Int?
    var fulfillmentMode: FulfillmentMode?
    var shoppingScope: ShoppingScope?
    var mealPrepSnapshot: MealPrepPlanSnapshot?
    var startedAt: Date
    var items: [ShoppingListItem]
    var stateFingerprint: String?
    var reconciliationDraft: ShoppingReconciliationDraft?
    var reconciliation: ShoppingReconciliationRecord?
    /// Suppresses only the Home pantry-update reminder. The completed trip
    /// and its later reconciliation route remain intact.
    var pantryUpdateReminderArchivedAt: Date?

    init(
        id: UUID = UUID(),
        tripID: UUID? = nil,
        logicalTripID: UUID? = nil,
        recipeID: UUID,
        recipeTitle: String,
        manifestID: UUID? = nil,
        storeID: String,
        retailerID: String? = nil,
        desiredServings: Int? = nil,
        fulfillmentMode: FulfillmentMode? = nil,
        shoppingScope: ShoppingScope? = nil,
        mealPrepSnapshot: MealPrepPlanSnapshot? = nil,
        startedAt: Date = .now,
        items: [ShoppingListItem],
        stateFingerprint: String? = nil,
        reconciliationDraft: ShoppingReconciliationDraft? = nil,
        reconciliation: ShoppingReconciliationRecord? = nil,
        pantryUpdateReminderArchivedAt: Date? = nil
    ) {
        self.id = id
        self.tripID = tripID ?? logicalTripID
        self.logicalTripID = logicalTripID ?? tripID
        self.recipeID = recipeID
        self.recipeTitle = recipeTitle
        self.manifestID = manifestID
        self.storeID = storeID
        self.retailerID = retailerID
        self.desiredServings = desiredServings
        self.fulfillmentMode = fulfillmentMode
        self.shoppingScope = shoppingScope
        self.mealPrepSnapshot = mealPrepSnapshot
        self.startedAt = startedAt
        self.items = items
        self.stateFingerprint = stateFingerprint
        self.reconciliationDraft = reconciliationDraft
        self.reconciliation = reconciliation
        self.pantryUpdateReminderArchivedAt = pantryUpdateReminderArchivedAt
    }

    var isCommitted: Bool { reconciliation != nil }
    var reconciliationIdentity: UUID? { logicalTripID ?? tripID }
    var isGuideComplete: Bool {
        !items.isEmpty && items.allSatisfy { $0.status.isCompleted }
    }
    var isReusable: Bool { !isCommitted && !isGuideComplete }
    var hasPendingPantryUpdateReminder: Bool {
        isGuideComplete && !isCommitted && pantryUpdateReminderArchivedAt == nil
    }
}

struct SavedShoppingList: Identifiable, Hashable, Codable {
    let id: UUID
    var manifest: ShoppingManifest

    init(
        id: UUID = UUID(),
        manifest: ShoppingManifest
    ) {
        self.id = id
        self.manifest = manifest
    }

    var recipeTitle: String { manifest.recipeTitle }
    var storeName: String { manifest.storeName }
    var itemCount: Int { manifest.items.count }
    var total: Double { manifest.total }
    var savedAt: Date { manifest.updatedAt }
}

struct DeliveryPartner: Identifiable, Hashable {
    let id: UUID
    var name: String
    var symbol: String
    var color: Color
    var url: URL
    var capabilities: RetailerCapabilities

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        color: Color,
        url: URL,
        capabilities: RetailerCapabilities = []
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.url = url
        self.capabilities = capabilities
    }
}
