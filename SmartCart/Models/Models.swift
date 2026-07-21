import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Codable, Hashable {
    case home
    case lists
    case pantry
    case store
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .lists: "Recipes"
        case .pantry: "Pantry"
        case .store: "Store"
        case .account: "Account"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .lists: "book.fill"
        case .pantry: "cabinet.fill"
        case .store: "storefront.fill"
        case .account: "person.crop.circle.fill"
        }
    }
}

enum SmartRoute: Hashable {
    case mealPrepSelection
    case mealPrepReview
    case mealPrepDashboard
    case recipeReady
    case shoppingTrip
    case ingredientReview
    case servingAdjustment
    case pantryCheck
    case preferences
    case storeSelection
    case matching
    case shoppingList
    case guidedShopping
    case shoppingReconciliation(UUID)
}

enum ImportMethod: String, CaseIterable, Identifiable, Hashable, Codable {
    case camera
    case photoLibrary
    case recipeLink
    case pinterest
    case recipeText
    case sample

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Take a photo"
        case .photoLibrary: "Upload photo"
        case .recipeLink: "Paste a link"
        case .pinterest: "Pinterest"
        case .recipeText: "Paste recipe"
        case .sample: "Try a sample"
        }
    }

    var shortTitle: String {
        switch self {
        case .camera: "Camera"
        case .photoLibrary: "Photos"
        case .recipeLink: "Link"
        case .pinterest: "Pinterest"
        case .recipeText: "Text"
        case .sample: "Sample"
        }
    }

    var subtitle: String {
        switch self {
        case .camera: "Scan a cookbook or card"
        case .photoLibrary: "Use a saved screenshot"
        case .recipeLink: "Import recipe page data"
        case .pinterest: "Use a recipe pin link"
        case .recipeText: "Paste an ingredient list"
        case .sample: "Explore the complete flow"
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .photoLibrary: "photo.on.rectangle.angled"
        case .recipeLink: "link"
        case .pinterest: "p.circle.fill"
        case .recipeText: "doc.text.fill"
        case .sample: "takeoutbag.and.cup.and.straw.fill"
        }
    }

    var tint: Color {
        switch self {
        case .camera: SmartCartTheme.walmartBlue
        case .photoLibrary: Color(red: 0.37, green: 0.36, blue: 0.82)
        case .recipeLink: SmartCartTheme.navy
        case .pinterest: Color(red: 0.83, green: 0.08, blue: 0.17)
        case .recipeText: SmartCartTheme.green
        case .sample: SmartCartTheme.amber
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

    init(
        id: UUID = UUID(),
        rawText: String = "",
        name: String,
        quantity: Double = 1,
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
        pantryDecision: PantryDecision? = nil
    ) {
        self.id = id
        self.rawText = rawText.isEmpty ? "\(quantity) \(unit) \(name)" : rawText
        self.name = name
        self.quantity = quantity
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
    }

    var displayQuantity: String {
        if let quantityLowerBound,
           quantityLowerBound >= 0,
           quantityLowerBound < quantity {
            let lower = Self.quantityText(quantityLowerBound, unit: "")
            let upper = Self.quantityText(quantity, unit: unit)
            return "\(lower)–\(upper)"
        }
        return Self.quantityText(quantity, unit: unit)
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
