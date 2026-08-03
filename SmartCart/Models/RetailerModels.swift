import Foundation
import MapKit

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
        case .demoSeed: "Representative catalog record"
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

struct CommerceCapabilities: Codable, Hashable {
    let preparesShoppingList: Bool
    let liveProductReview: Bool
    let livePricing: Bool
    let liveAvailability: Bool
    let pickup: Bool
    let delivery: Bool
    let checkout: Bool
    let embeddedCheckout: Bool

    static let instacart = CommerceCapabilities(
        preparesShoppingList: true,
        liveProductReview: true,
        livePricing: true,
        liveAvailability: true,
        pickup: true,
        delivery: true,
        checkout: true,
        embeddedCheckout: false
    )

    static let walmartGuided = CommerceCapabilities(
        preparesShoppingList: true,
        liveProductReview: false,
        livePricing: false,
        liveAvailability: false,
        pickup: false,
        delivery: false,
        checkout: false,
        embeddedCheckout: false
    )

    static let linkOnly = CommerceCapabilities(
        preparesShoppingList: false,
        liveProductReview: false,
        livePricing: false,
        liveAvailability: false,
        pickup: false,
        delivery: false,
        checkout: false,
        embeddedCheckout: false
    )
}

enum RetailerGuideAvailability: String, Codable, Hashable {
    case available
    case comingSoon
}

enum ShoppingRetailer: String, CaseIterable, Identifiable, Codable, Hashable {
    case walmart
    case target
    case kroger

    var id: String { rawValue }

    var accountURL: URL {
        switch self {
        case .walmart:
            URL(string: "https://www.walmart.com/account/login")!
        case .target:
            URL(string: "https://www.target.com/account")!
        case .kroger:
            URL(string: "https://www.kroger.com/account/login")!
        }
    }

    var cartURL: URL {
        switch self {
        case .walmart:
            URL(string: "https://www.walmart.com/cart")!
        case .target:
            URL(string: "https://www.target.com/cart")!
        case .kroger:
            URL(string: "https://www.kroger.com/cart")!
        }
    }

    var configuration: RetailerGuideConfiguration {
        switch self {
        case .walmart:
            RetailerGuideConfiguration(
                retailer: self,
                displayName: "Walmart",
                guideLabel: "Shopping Trip",
                cardHighlights: [
                    "Walmart Shopping Trip",
                    "Walmart confirms pickup or delivery",
                    "Broad nationwide coverage"
                ],
                availability: .available,
                listURL: URL(string: "https://www.walmart.com/lists")!,
                homeURL: URL(string: "https://www.walmart.com/")!,
                savedListName: "Walmart Wishlist",
                instructions: [
                    "Review the product, live price, and availability.",
                    "Walmart owns every list, cart, and quantity action.",
                    "When ready, use Next Item in SmartCart. It records only that you advanced."
                ]
            )
        case .target:
            RetailerGuideConfiguration(
                retailer: self,
                displayName: "Target",
                guideLabel: "Shopping Trip",
                cardHighlights: [
                    "Target Shopping Trip",
                    "Target confirms Drive Up eligibility",
                    "Strong grocery and household coverage"
                ],
                availability: .available,
                listURL: URL(string: "https://www.target.com/lists")!,
                homeURL: URL(string: "https://www.target.com/")!,
                savedListName: "Target Shopping List",
                instructions: [
                    "Review the product, live price, and store availability.",
                    "Target owns every list, cart, and quantity action.",
                    "When ready, use Next Item in SmartCart. It records only that you advanced."
                ]
            )
        case .kroger:
            RetailerGuideConfiguration(
                retailer: self,
                displayName: "Kroger",
                guideLabel: "Shopping Trip",
                cardHighlights: [
                    "Kroger Shopping Trip",
                    "Kroger-family rollout planned",
                    "Local grocery focus"
                ],
                availability: .comingSoon,
                listURL: URL(string: "https://www.kroger.com/shopping/list")!,
                homeURL: URL(string: "https://www.kroger.com/")!,
                savedListName: "Kroger Shopping List",
                instructions: []
            )
        }
    }
}

enum RetailerStoreLocatorError: LocalizedError, Equatable {
    case invalidPostalCode
    case postalCodeNotFound
    case noStoresFound(retailer: String, postalCode: String)

    var errorDescription: String? {
        switch self {
        case .invalidPostalCode:
            "Enter a five-digit US ZIP code."
        case .postalCodeNotFound:
            "SmartCart could not locate that ZIP code."
        case .noStoresFound(let retailer, let postalCode):
            "No nearby \(retailer) locations were found for \(postalCode)."
        }
    }
}

protocol RetailerStoreLocating {
    func stores(
        for retailer: ShoppingRetailer,
        postalCode: String,
        limit: Int
    ) async throws -> [RetailerStore]
}

/// Uses Apple's local-search index for nearby storefront discovery. This is
/// location lookup only; it does not claim retailer inventory, fulfillment,
/// pricing, account, or API access.
struct MapKitRetailerStoreLocator: RetailerStoreLocating {
    func stores(
        for retailer: ShoppingRetailer,
        postalCode: String,
        limit: Int = 5
    ) async throws -> [RetailerStore] {
        let postalCode = postalCode.filter(\.isNumber)
        guard postalCode.count == 5 else { throw RetailerStoreLocatorError.invalidPostalCode }

        let postalRequest = MKLocalSearch.Request()
        postalRequest.naturalLanguageQuery = postalCode
        let postalResponse = try await MKLocalSearch(request: postalRequest).start()
        guard let postalCoordinate = postalResponse.mapItems.first?.placemark.coordinate else {
            throw RetailerStoreLocatorError.postalCodeNotFound
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = retailer.configuration.displayName
        request.region = MKCoordinateRegion(
            center: postalCoordinate,
            latitudinalMeters: 80_000,
            longitudinalMeters: 80_000
        )
        request.resultTypes = .pointOfInterest
        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: postalCoordinate.latitude, longitude: postalCoordinate.longitude)
        let retailerToken = retailer.configuration.displayName.lowercased()

        let results = response.mapItems.compactMap { item -> RetailerStore? in
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard name.lowercased().contains(retailerToken) else { return nil }
            let coordinate = item.placemark.coordinate
            let distance = origin.distance(
                from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            ) / 1_609.344
            guard distance.isFinite, distance <= 50 else { return nil }

            let address = formattedAddress(for: item.placemark)
            let normalizedAddress = RetailerStoreResultNormalizer.normalizedAddressKey(address)
            let locationKey = normalizedAddress.isEmpty || normalizedAddress == "address available in maps"
                ? String(format: "%.4f|%.4f", coordinate.latitude, coordinate.longitude)
                : normalizedAddress
            let identity = "\(retailer.rawValue)|\(locationKey)"
            let stableID = stableUUID(for: identity)
            return RetailerStore(
                id: stableID,
                retailerID: retailer.rawValue,
                retailerStoreID: "mapkit-\(stableID.uuidString.lowercased())",
                name: name,
                format: "Nearby store",
                address: address,
                distance: distance,
                pickupWindow: "Confirmed by \(retailer.configuration.displayName)"
            )
        }
        .sorted { first, second in
            if first.distance != second.distance { return first.distance < second.distance }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }

        let unique = RetailerStoreResultNormalizer.deduplicated(
            results,
            retailer: retailer,
            limit: limit
        )
        guard !unique.isEmpty else {
            throw RetailerStoreLocatorError.noStoresFound(
                retailer: retailer.configuration.displayName,
                postalCode: postalCode
            )
        }
        return unique
    }

    private func formattedAddress(for placemark: MKPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let locality = [placemark.locality, placemark.administrativeArea, placemark.postalCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let address = [street, locality].filter { !$0.isEmpty }.joined(separator: ", ")
        return address.isEmpty ? "Address available in Maps" : address
    }

    private func stableUUID(for value: String) -> UUID {
        func fnv1a(_ input: String, seed: UInt64) -> UInt64 {
            input.utf8.reduce(seed) { hash, byte in
                (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
        }
        let high = fnv1a(value, seed: 14_695_981_039_346_656_037)
        let low = fnv1a("smartcart-store|\(value)", seed: 1_099_511_628_211)
        let hex = String(format: "%016llx%016llx", high, low)
        let uuidText = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: uuidText) ?? UUID()
    }
}

enum RetailerStoreResultNormalizer {
    static func deduplicated(
        _ stores: [RetailerStore],
        retailer: ShoppingRetailer,
        limit: Int
    ) -> [RetailerStore] {
        let grouped = Dictionary(grouping: stores) { store in
            let addressKey = normalizedAddressKey(store.address)
            if addressKey.isEmpty || addressKey == "address available in maps" {
                return "store-id|\(store.retailerStoreID.lowercased())"
            }
            return addressKey
        }

        let representatives = grouped.values.compactMap { group -> RetailerStore? in
            guard var preferred = group.min(by: { first, second in
                isPreferred(first, over: second, for: retailer)
            }) else { return nil }
            preferred.name = canonicalStoreName(for: retailer, names: group.map(\.name))
            return preferred
        }
        .sorted { first, second in
            if first.distance != second.distance { return first.distance < second.distance }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }

        return Array(representatives.prefix(max(1, limit)))
    }

    static func normalizedAddressKey(_ address: String) -> String {
        let folded = address
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let words = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let abbreviations = [
            "street": "st", "avenue": "ave", "boulevard": "blvd", "road": "rd",
            "drive": "dr", "lane": "ln", "highway": "hwy", "route": "rte",
            "north": "n", "south": "s", "east": "e", "west": "w"
        ]
        return words.map { abbreviations[$0] ?? $0 }.joined(separator: " ")
    }

    private static func isPreferred(
        _ first: RetailerStore,
        over second: RetailerStore,
        for retailer: ShoppingRetailer
    ) -> Bool {
        let firstRank = storefrontRank(first.name, retailer: retailer)
        let secondRank = storefrontRank(second.name, retailer: retailer)
        if firstRank != secondRank { return firstRank < secondRank }
        if first.distance != second.distance { return first.distance < second.distance }
        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
    }

    private static func storefrontRank(_ name: String, retailer: ShoppingRetailer) -> Int {
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let retailerName = retailer.configuration.displayName.lowercased()
        if normalizedName == retailerName { return 0 }

        switch retailer {
        case .walmart:
            if normalizedName.contains("supercenter") { return 1 }
            if normalizedName.contains("neighborhood market") { return 2 }
        case .target:
            if normalizedName == "target store" { return 1 }
        case .kroger:
            if normalizedName.hasPrefix("kroger marketplace") { return 1 }
        }

        let departmentTerms = [
            "auto care", "bakery", "photo", "pharmacy", "vision", "garden center",
            "fuel station", "money center", "optical", "cafe", "grocery pickup"
        ]
        if departmentTerms.contains(where: { normalizedName.contains($0) }) { return 50 }
        return normalizedName.hasPrefix(retailerName) ? 10 : 25
    }

    private static func canonicalStoreName(
        for retailer: ShoppingRetailer,
        names: [String]
    ) -> String {
        let normalizedNames = names.map { $0.lowercased() }
        switch retailer {
        case .walmart:
            if normalizedNames.contains(where: { $0.contains("supercenter") }) {
                return "Walmart Supercenter"
            }
            if normalizedNames.contains(where: { $0.contains("neighborhood market") }) {
                return "Walmart Neighborhood Market"
            }
            return "Walmart"
        case .target:
            return "Target"
        case .kroger:
            return "Kroger"
        }
    }
}

struct RetailerGuideConfiguration: Identifiable, Hashable {
    var retailer: ShoppingRetailer
    var displayName: String
    var guideLabel: String
    var cardHighlights: [String]
    var availability: RetailerGuideAvailability
    var listURL: URL
    var homeURL: URL
    var savedListName: String
    var instructions: [String]

    var id: ShoppingRetailer { retailer }
    var isAvailable: Bool { availability == .available }
    var accountURL: URL { retailer.accountURL }
    var cartURL: URL { retailer.cartURL }
    var cartName: String { "\(displayName) cart" }
}

enum ShoppingRoutePreference: String, CaseIterable, Identifiable, Codable, Hashable {
    case instacart
    case walmartDirect
    case otherRetailerLinks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instacart: "Shop through Instacart"
        case .walmartDirect: "Walmart Shopping Trip"
        case .otherRetailerLinks: "Other retailer links"
        }
    }

    var subtitle: String {
        switch self {
        case .instacart: "SmartCart prepares the list; Instacart confirms products and checkout."
        case .walmartDirect: "Open exact products one at a time, then finish the trip in Walmart."
        case .otherRetailerLinks: "Open clearly labeled retailer destinations without a list transfer."
        }
    }

    var symbol: String {
        switch self {
        case .instacart: "carrot.fill"
        case .walmartDirect: "storefront.fill"
        case .otherRetailerLinks: "arrow.up.right.square.fill"
        }
    }
}

enum InstacartRetailerPreference: String, CaseIterable, Identifiable, Codable, Hashable {
    case bestAvailable = "best_available"
    case walmart
    case aldi
    case martinsGiant = "martins_giant"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bestAvailable: "Best available nearby"
        case .walmart: "Walmart, where available"
        case .aldi: "ALDI"
        case .martinsGiant: "MARTIN’S / GIANT"
        }
    }
}

enum CommerceFulfillmentPreference: String, CaseIterable, Identifiable, Codable, Hashable {
    case pickup
    case delivery
    case decideInInstacart = "decide_in_instacart"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pickup: "Pickup"
        case .delivery: "Delivery"
        case .decideInInstacart: "Decide in Instacart"
        }
    }
}

enum CommerceHandoffFeedback: String, CaseIterable, Identifiable, Codable, Hashable {
    case orderPlaced
    case savedForLater
    case productsUnavailable
    case changedProducts
    case didNotFinish

    var id: String { rawValue }

    var label: String {
        switch self {
        case .orderPlaced: "Order placed"
        case .savedForLater: "Saved for later"
        case .productsUnavailable: "Some products unavailable"
        case .changedProducts: "I changed products"
        case .didNotFinish: "I did not finish"
        }
    }
}

struct WalmartWishlistReference: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var sharedURL: URL
    var createdAt: Date
    var lastOpenedAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        sharedURL: URL,
        createdAt: Date = .now,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.sharedURL = sharedURL
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
    }
}

enum WalmartWishlistURLValidationError: LocalizedError, Equatable {
    case empty
    case invalidURL
    case insecureURL
    case unsupportedHost
    case notSharedWishlist

    var errorDescription: String? {
        switch self {
        case .empty:
            "Paste the shared Walmart Wishlist URL."
        case .invalidURL:
            "That does not look like a complete web address."
        case .insecureURL:
            "Use the secure https:// Walmart Wishlist link."
        case .unsupportedHost:
            "Only links from walmart.com can be saved."
        case .notSharedWishlist:
            "Paste the link from Wishlist > Share > Copy URL."
        }
    }
}

enum WalmartWishlistURLValidator {
    static func validate(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WalmartWishlistURLValidationError.empty
        }
        guard var components = URLComponents(string: trimmed), components.url != nil else {
            throw WalmartWishlistURLValidationError.invalidURL
        }
        guard components.scheme?.lowercased() == "https" else {
            throw WalmartWishlistURLValidationError.insecureURL
        }
        guard let host = components.host?.lowercased(), host == "walmart.com" || host == "www.walmart.com" else {
            throw WalmartWishlistURLValidationError.unsupportedHost
        }

        let path = components.path.split(separator: "/").map(String.init)
        guard
            path.count >= 4,
            path[0].lowercased() == "lists",
            path[1].lowercased() == "shared",
            path[2].uppercased() == "WL",
            !path[3].isEmpty
        else {
            throw WalmartWishlistURLValidationError.notSharedWishlist
        }

        components.fragment = nil
        guard let normalizedURL = components.url else {
            throw WalmartWishlistURLValidationError.invalidURL
        }
        return normalizedURL
    }
}

struct InstacartManifestLineItem: Codable, Hashable {
    var ingredientID: UUID
    var name: String
    var displayText: String
    var quantity: Double
    var unit: String
    var healthFilters: [String]
    var exactUPC: String?
    var quantityConfirmed: Bool
    var unresolvedAlternative: Bool
}

struct InstacartManifestDraft: Codable, Hashable {
    var localManifestID: UUID
    var recipeID: UUID
    var title: String
    var desiredServings: Int
    var items: [InstacartManifestLineItem]
    var pantryItemsRemoved: Int
}

struct InstacartHandoffResponse: Codable, Identifiable, Hashable {
    var provider: String
    var url: URL
    var manifestFingerprint: String
    var createdAt: Date
    var presentationMode: String

    var id: String { manifestFingerprint }
}

enum InstacartHandoffError: LocalizedError {
    case blocked([String])
    case backendUnavailable
    case timeout
    case unreadableResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let issues): issues.joined(separator: " ")
        case .backendUnavailable: "The SmartCart commerce service is unavailable. Start the backend or configure its reachable URL."
        case .timeout: "Instacart list preparation took too long. Try again."
        case .unreadableResponse: "The SmartCart commerce service returned an unreadable response."
        case .server(let message): message
        }
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
            "Representative price · observed \(observedAt.formatted(date: .abbreviated, time: .omitted)) · not live"
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
    var retailerID: String = ShoppingRetailer.walmart.rawValue
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
    case paused
    case completed
}

struct ManifestLineItem: Codable, Identifiable, Hashable {
    let id: UUID
    var ingredientID: UUID
    var ingredientName: String
    var requestedQuantity: String
    var requestedAmount: Double?
    var purchaseQuantity: Int
    var product: RetailerProductRecord
    var status: GuidedItemStatus
    var sourceContributions: [CombinedIngredientSource]?
    var purchaseGroup: ProductPurchaseGroup?

    init(
        id: UUID = UUID(),
        ingredientID: UUID,
        ingredientName: String,
        requestedQuantity: String,
        requestedAmount: Double? = nil,
        purchaseQuantity: Int,
        product: RetailerProductRecord,
        status: GuidedItemStatus,
        sourceContributions: [CombinedIngredientSource] = [],
        purchaseGroup: ProductPurchaseGroup? = nil
    ) {
        self.id = id
        self.ingredientID = ingredientID
        self.ingredientName = ingredientName
        self.requestedQuantity = requestedQuantity
        self.requestedAmount = requestedAmount
        self.purchaseQuantity = purchaseQuantity
        self.product = product
        self.status = status
        self.sourceContributions = sourceContributions
        self.purchaseGroup = purchaseGroup
    }
}

struct ShoppingManifest: Codable, Identifiable, Hashable {
    let id: UUID
    /// Created once for a logical shopping trip, then carried unchanged into
    /// its session, frozen completion snapshot, and pantry reconciliation.
    var logicalTripID: UUID?
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
    var shoppingScope: ShoppingScope?
    var mealPrepSnapshot: MealPrepPlanSnapshot?

    init(
        id: UUID = UUID(),
        logicalTripID: UUID? = nil,
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
        handoffProgress: ManifestHandoffProgress = .notStarted,
        shoppingScope: ShoppingScope? = nil,
        mealPrepSnapshot: MealPrepPlanSnapshot? = nil
    ) {
        self.id = id
        self.logicalTripID = logicalTripID
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
        self.shoppingScope = shoppingScope
        self.mealPrepSnapshot = mealPrepSnapshot
    }

    var total: Double {
        items.reduce(0) {
            $0 + ($1.product.price * Double($1.purchaseQuantity))
        }
    }
}
