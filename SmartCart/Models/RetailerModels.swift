import Foundation

enum PriceType: String, Codable, CaseIterable, Hashable {
    case exact
    case estimated
    case variableWeight
    case unavailable

    var label: String {
        switch self {
        case .exact: "Observed price"
        case .estimated: "Estimated price"
        case .variableWeight: "Variable-weight estimate"
        case .unavailable: "Price unavailable"
        }
    }
}

enum ProductAvailability: String, Codable, CaseIterable, Hashable {
    case inStock
    case limited
    case outOfStock
    case unknown

    var label: String {
        switch self {
        case .inStock: "Available"
        case .limited: "Limited"
        case .outOfStock: "Out of stock"
        case .unknown: "Availability unverified"
        }
    }

    var rankingValue: Int {
        switch self {
        case .inStock: 3
        case .limited: 2
        case .unknown: 1
        case .outOfStock: 0
        }
    }
}

enum FulfillmentMethod: String, Codable, CaseIterable, Hashable {
    case pickup
    case delivery
    case shipping
}

enum OrganicStatus: String, Codable, CaseIterable, Hashable {
    case certified
    case claimed
    case notOrganic
    case unknown

    var isOrganic: Bool {
        self == .certified || self == .claimed
    }

    var label: String {
        switch self {
        case .certified: "Certified organic"
        case .claimed: "Organic"
        case .notOrganic: "Conventional"
        case .unknown: "Organic status unknown"
        }
    }
}

enum DietaryAttribute: String, Codable, CaseIterable, Identifiable, Hashable {
    case vegetarian
    case vegan
    case glutenFree
    case dairyFree
    case nutFree
    case kosher
    case halal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .glutenFree: "Gluten-free"
        case .dairyFree: "Dairy-free"
        case .nutFree: "Nut-free"
        case .kosher: "Kosher"
        case .halal: "Halal"
        }
    }
}

enum ProductDataSource: String, Codable, CaseIterable, Hashable {
    case demoSeed
    case manualVerification
    case retailerAPI
    case partnerFeed
    case searchFallback

    var label: String {
        switch self {
        case .demoSeed: "Seeded demo record"
        case .manualVerification: "Manually verified"
        case .retailerAPI: "Retailer catalog"
        case .partnerFeed: "Partner catalog"
        case .searchFallback: "Retailer search fallback"
        }
    }
}

enum RetailerLinkKind: String, Codable, CaseIterable, Hashable {
    case exactProduct
    case searchResults

    var label: String {
        switch self {
        case .exactProduct: "Exact product"
        case .searchResults: "Retailer search"
        }
    }
}

enum OrganicPolicy: String, Codable, CaseIterable, Identifiable, Hashable {
    case noPreference
    case whenAvailable
    case only

    var id: String { rawValue }

    var label: String {
        switch self {
        case .noPreference: "No preference"
        case .whenAvailable: "Organic when available"
        case .only: "Organic only"
        }
    }

    var explanation: String {
        switch self {
        case .noPreference: "Organic status does not change ranking."
        case .whenAvailable: "Organic products rank first, with a conventional fallback."
        case .only: "Conventional products are removed from matching."
        }
    }
}

enum BudgetPriority: String, Codable, CaseIterable, Identifiable, Hashable {
    case lowestTotal
    case balanced
    case qualityFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lowestTotal: "Lowest total"
        case .balanced: "Balanced"
        case .qualityFirst: "Quality first"
        }
    }
}

enum StoreBrandPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case prefer
    case neutral
    case avoid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .prefer: "Prefer store brand"
        case .neutral: "No brand preference"
        case .avoid: "Avoid store brand"
        }
    }
}

struct ShoppingPreferences: Codable, Hashable {
    var organicPolicy: OrganicPolicy = .whenAvailable
    var budgetPriority: BudgetPriority = .balanced
    var dietaryRestrictions: Set<DietaryAttribute> = []
    var storeBrandPreference: StoreBrandPreference = .neutral
    var preferredBrands: [String] = []

    var summary: String {
        var parts = [organicPolicy.label, budgetPriority.label]
        if !dietaryRestrictions.isEmpty {
            parts.append(
                dietaryRestrictions
                    .map(\.label)
                    .sorted()
                    .joined(separator: ", ")
            )
        }
        if storeBrandPreference != .neutral {
            parts.append(storeBrandPreference.label)
        }
        return parts.joined(separator: " · ")
    }
}

struct AppFeatureFlags: Codable, Hashable {
    var advancedToolsEnabled = false
    var internalTesterModeEnabled = false
    var localAnalyticsEnabled = true

    private enum CodingKeys: String, CodingKey {
        case advancedToolsEnabled
        case internalTesterModeEnabled
        case localAnalyticsEnabled
    }

    init(
        advancedToolsEnabled: Bool = false,
        internalTesterModeEnabled: Bool = false,
        localAnalyticsEnabled: Bool = true
    ) {
        self.advancedToolsEnabled = advancedToolsEnabled
        self.internalTesterModeEnabled = internalTesterModeEnabled
        self.localAnalyticsEnabled = localAnalyticsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        advancedToolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .advancedToolsEnabled) ?? false
        internalTesterModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .internalTesterModeEnabled) ?? false
        localAnalyticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .localAnalyticsEnabled) ?? true
    }
}

struct RetailerCapabilities: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let catalogSearch = RetailerCapabilities(rawValue: 1 << 0)
    static let exactProductLinks = RetailerCapabilities(rawValue: 1 << 1)
    static let priceRefresh = RetailerCapabilities(rawValue: 1 << 2)
    static let pickup = RetailerCapabilities(rawValue: 1 << 3)
    static let delivery = RetailerCapabilities(rawValue: 1 << 4)
    static let guidedProductHandoff = RetailerCapabilities(rawValue: 1 << 5)
    static let manifestTransfer = RetailerCapabilities(rawValue: 1 << 6)
    static let wishlist = RetailerCapabilities(rawValue: 1 << 7)
    static let cartCreation = RetailerCapabilities(rawValue: 1 << 8)
}

struct RetailerProductRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var retailerID: String
    var storeID: String?
    var retailerProductID: String
    var gtin: String?
    var title: String
    var brand: String
    var exactURL: URL
    var imageURL: URL?
    var packageDescription: String
    var packageQuantity: Double?
    var packageUnit: String?
    var observedPrice: Decimal?
    var unitPriceValue: Decimal?
    var unitPriceText: String
    var priceType: PriceType
    var availability: ProductAvailability
    var fulfillmentMethods: Set<FulfillmentMethod>
    var organicStatus: OrganicStatus
    var dietaryAttributes: Set<DietaryAttribute>
    var dataSource: ProductDataSource
    var observedAt: Date
    var linkKind: RetailerLinkKind
    var symbol: String
    var confidence: IngredientConfidence
    var variableWeight: Bool
    var matchKeywords: Set<String>
    var isStoreBrand: Bool

    init(
        id: UUID = UUID(),
        retailerID: String,
        storeID: String?,
        retailerProductID: String,
        gtin: String? = nil,
        title: String,
        brand: String,
        exactURL: URL,
        imageURL: URL? = nil,
        packageDescription: String,
        packageQuantity: Double? = nil,
        packageUnit: String? = nil,
        observedPrice: Decimal? = nil,
        unitPriceValue: Decimal? = nil,
        unitPriceText: String,
        priceType: PriceType,
        availability: ProductAvailability,
        fulfillmentMethods: Set<FulfillmentMethod>,
        organicStatus: OrganicStatus,
        dietaryAttributes: Set<DietaryAttribute> = [],
        dataSource: ProductDataSource,
        observedAt: Date,
        linkKind: RetailerLinkKind = .exactProduct,
        symbol: String,
        confidence: IngredientConfidence = .high,
        variableWeight: Bool = false,
        matchKeywords: Set<String> = [],
        isStoreBrand: Bool = false
    ) {
        self.id = id
        self.retailerID = retailerID
        self.storeID = storeID
        self.retailerProductID = retailerProductID
        self.gtin = gtin
        self.title = title
        self.brand = brand
        self.exactURL = exactURL
        self.imageURL = imageURL
        self.packageDescription = packageDescription
        self.packageQuantity = packageQuantity
        self.packageUnit = packageUnit
        self.observedPrice = observedPrice
        self.unitPriceValue = unitPriceValue
        self.unitPriceText = unitPriceText
        self.priceType = priceType
        self.availability = availability
        self.fulfillmentMethods = fulfillmentMethods
        self.organicStatus = organicStatus
        self.dietaryAttributes = dietaryAttributes
        self.dataSource = dataSource
        self.observedAt = observedAt
        self.linkKind = linkKind
        self.symbol = symbol
        self.confidence = confidence
        self.variableWeight = variableWeight
        self.matchKeywords = matchKeywords
        self.isStoreBrand = isStoreBrand
    }

    var name: String { title }
    var package: String { packageDescription }
    var unitPrice: String { unitPriceText }
    var isExactProductLink: Bool { linkKind == .exactProduct }
    var hasObservedPrice: Bool { observedPrice != nil }
    var priceDisclosure: String {
        switch dataSource {
        case .demoSeed:
            "Demo price · observed \(observedAt.formatted(date: .abbreviated, time: .omitted)) · not live"
        case .manualVerification:
            "Last-known price · observed \(observedAt.formatted(date: .abbreviated, time: .omitted)) · not live"
        case .retailerAPI, .partnerFeed:
            "Observed \(observedAt.formatted(date: .abbreviated, time: .omitted)) · retailer confirms final price"
        case .searchFallback:
            "Price unavailable · retailer confirms"
        }
    }

    var price: Double {
        observedPrice.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
    }

    func isPriceStale(
        relativeTo date: Date = .now,
        maximumAge: TimeInterval = 24 * 60 * 60
    ) -> Bool {
        date.timeIntervalSince(observedAt) > maximumAge
    }
}

struct RetailerProductSearchRequest: Hashable {
    var ingredient: Ingredient
    var requestedQuantity: Double
    var requestedUnit: String
    var storeID: String
    var fulfillmentMethod: FulfillmentMethod
}

struct RankedRetailerProduct: Hashable {
    var product: RetailerProductRecord
    var score: Double
    var reasons: [String]
}

enum RetailerHandoffMode: String, Codable, Hashable {
    case guidedProducts
    case manifestTransfer
    case retailerSearch
    case retailerHome
}

struct RetailerHandoff: Codable, Identifiable, Hashable {
    let id: UUID
    var retailerID: String
    var mode: RetailerHandoffMode
    var url: URL
    var title: String
    var disclosure: String

    init(
        id: UUID = UUID(),
        retailerID: String,
        mode: RetailerHandoffMode,
        url: URL,
        title: String,
        disclosure: String
    ) {
        self.id = id
        self.retailerID = retailerID
        self.mode = mode
        self.url = url
        self.title = title
        self.disclosure = disclosure
    }
}

enum ManifestHandoffProgress: String, Codable, Hashable {
    case notStarted
    case inProgress
    case completed
}

struct ManifestLineItem: Codable, Identifiable, Hashable {
    let id: UUID
    var ingredientID: UUID
    var ingredientName: String
    var requestedQuantity: String
    var purchaseQuantity: Int
    var product: RetailerProductRecord
    var status: GuidedItemStatus

    init(
        id: UUID = UUID(),
        ingredientID: UUID,
        ingredientName: String,
        requestedQuantity: String,
        purchaseQuantity: Int,
        product: RetailerProductRecord,
        status: GuidedItemStatus
    ) {
        self.id = id
        self.ingredientID = ingredientID
        self.ingredientName = ingredientName
        self.requestedQuantity = requestedQuantity
        self.purchaseQuantity = purchaseQuantity
        self.product = product
        self.status = status
    }
}

struct ShoppingManifest: Codable, Identifiable, Hashable {
    let id: UUID
    var recipeID: UUID
    var recipeTitle: String
    var retailerID: String
    var storeID: String
    var storeName: String
    var desiredServings: Int
    var fulfillmentMode: FulfillmentMode
    var items: [ManifestLineItem]
    var createdAt: Date
    var updatedAt: Date
    var handoffProgress: ManifestHandoffProgress

    init(
        id: UUID = UUID(),
        recipeID: UUID,
        recipeTitle: String,
        retailerID: String,
        storeID: String,
        storeName: String,
        desiredServings: Int,
        fulfillmentMode: FulfillmentMode,
        items: [ManifestLineItem],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        handoffProgress: ManifestHandoffProgress = .notStarted
    ) {
        self.id = id
        self.recipeID = recipeID
        self.recipeTitle = recipeTitle
        self.retailerID = retailerID
        self.storeID = storeID
        self.storeName = storeName
        self.desiredServings = desiredServings
        self.fulfillmentMode = fulfillmentMode
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.handoffProgress = handoffProgress
    }

    var total: Double {
        items.reduce(0) {
            $0 + ($1.product.price * Double($1.purchaseQuantity))
        }
    }
}
