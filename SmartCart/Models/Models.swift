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
    case ingredientReview
    case servingAdjustment
    case pantryCheck
    case preferences
    case storeSelection
    case matching
    case shoppingList
    case guidedShopping
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
    case importer(ImportMethod)

    var id: String {
        switch self {
        case .importer(let method): "importer-\(method.rawValue)"
        }
    }
}

enum RecipeSource: String, CaseIterable, Hashable, Codable {
    case photo = "Recipe photo"
    case link = "Recipe link"
    case pinterest = "Pinterest"
    case text = "Pasted text"
    case sample = "SmartCart sample"
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

    init(
        id: UUID = UUID(),
        title: String,
        source: RecipeSource,
        sourceDetail: String,
        heroSymbol: String,
        servings: Int,
        prepMinutes: Int,
        cookMinutes: Int,
        ingredients: [Ingredient]
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
    }

    var totalMinutes: Int { prepMinutes + cookMinutes }
}

struct Ingredient: Identifiable, Hashable, Codable {
    let id: UUID
    var rawText: String
    var name: String
    var quantity: Double
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
        Self.quantityText(quantity, unit: unit)
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
    var sourceCropJPEGData: Data? = nil
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

    var confidenceScore: Double {
        guard ingredientLineCount > 0 else { return 0 }
        let weighted = Double(highConfidenceCount) + Double(reviewCount) * 0.55
        return min(1, max(0, weighted / Double(ingredientLineCount)))
    }

    var confidenceLabel: String {
        switch confidenceScore {
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

struct PantryInventoryItem: Identifiable, Hashable, Codable {
    let id: UUID
    var upc: String?
    var name: String
    var brand: String
    var quantity: Double
    var unit: String
    var preferredRetailerProductID: String?
    var source: PantryItemSource
    var updatedAt: Date
    var packageSize: Double?
    var packageUnit: String?
    var requiresUserNaming: Bool?
    var rawBarcode: String?
    var barcodeSymbology: String?
    var gtin14: String?
    /// Every normalized barcode observed for this pantry item. Optional keeps
    /// older persisted states migration-safe; `gtin14` remains the primary
    /// legacy identity while this array records additional package barcodes.
    var barcodeGTINs: [String]?

    init(
        id: UUID = UUID(),
        upc: String? = nil,
        name: String,
        brand: String = "",
        quantity: Double = 1,
        unit: String = "item",
        preferredRetailerProductID: String? = nil,
        source: PantryItemSource = .manual,
        updatedAt: Date = .now,
        packageSize: Double? = nil,
        packageUnit: String? = nil,
        requiresUserNaming: Bool? = nil,
        rawBarcode: String? = nil,
        barcodeSymbology: String? = nil,
        gtin14: String? = nil,
        barcodeGTINs: [String]? = nil
    ) {
        self.id = id
        self.upc = upc
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.unit = unit
        self.preferredRetailerProductID = preferredRetailerProductID
        self.source = source
        self.updatedAt = updatedAt
        self.packageSize = packageSize
        self.packageUnit = packageUnit
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
    }

    func matches(barcode: NormalizedBarcode) -> Bool {
        gtin14 == barcode.canonicalGTIN14 ||
            upc == barcode.digits ||
            (barcodeGTINs?.contains(barcode.canonicalGTIN14) ?? false)
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
    case barcodeScanned = "barcode_scanned"
    case pantryItemAdded = "pantry_item_added"
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
    case added
    case skipped
}

struct ShoppingListItem: Identifiable, Hashable, Codable {
    let id: UUID
    var ingredient: Ingredient
    var requestedQuantity: String
    var purchaseQuantity: Int
    var product: RetailerProductRecord
    var alternatives: [RetailerProductRecord]
    var storeID: UUID
    var status: GuidedItemStatus
    var matchScore: Double
    var selectionReasons: [String]

    init(
        id: UUID = UUID(),
        ingredient: Ingredient,
        requestedQuantity: String,
        purchaseQuantity: Int = 1,
        product: RetailerProductRecord,
        alternatives: [RetailerProductRecord],
        storeID: UUID,
        status: GuidedItemStatus = .waiting,
        matchScore: Double = 0,
        selectionReasons: [String] = []
    ) {
        self.id = id
        self.ingredient = ingredient
        self.requestedQuantity = requestedQuantity
        self.purchaseQuantity = purchaseQuantity
        self.product = product
        self.alternatives = alternatives
        self.storeID = storeID
        self.status = status
        self.matchScore = matchScore
        self.selectionReasons = selectionReasons
    }

    var lineTotal: Double {
        product.price * Double(purchaseQuantity)
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
