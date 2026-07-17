import Foundation

enum RetailConnectorState: String, Codable, Hashable {
    case demoReady = "Demo ready"
    case credentialsRequired = "Credentials required"
    case researchOnly = "Research only"
}

struct RetailConnectorProfile: Identifiable, Hashable {
    var id: String
    var displayName: String
    var homepage: URL
    var state: RetailConnectorState
    var capabilities: RetailerCapabilities
    var integrationNote: String

    var supportsCart: Bool { capabilities.contains(.cartCreation) }
    var supportsWishlist: Bool { capabilities.contains(.wishlist) }
    var supportsDelivery: Bool { capabilities.contains(.delivery) }
    var supportsLookup: Bool { capabilities.contains(.catalogSearch) }
}

enum RetailConnectorRegistry {
    static let profiles: [RetailConnectorProfile] = [
        RetailConnectorProfile(
            id: "walmart",
            displayName: "Walmart",
            homepage: URL(string: "https://www.walmart.com")!,
            state: .demoReady,
            capabilities: [.catalogSearch, .exactProductLinks, .pickup, .delivery, .guidedProductHandoff],
            integrationNote: "Seeded catalog and exact public product links. No live price, inventory, cart, or pickup reservation."
        ),
        RetailConnectorProfile(
            id: "instacart",
            displayName: "Instacart",
            homepage: URL(string: "https://www.instacart.com")!,
            state: .credentialsRequired,
            capabilities: [.catalogSearch, .delivery, .manifestTransfer],
            integrationNote: "Adapter contract is ready; partner approval and credentials are required before live calls."
        ),
        RetailConnectorProfile(
            id: "kroger",
            displayName: "Kroger",
            homepage: URL(string: "https://www.kroger.com")!,
            state: .credentialsRequired,
            capabilities: [.catalogSearch, .exactProductLinks, .pickup, .delivery],
            integrationNote: "OAuth and API-key slots are defined; no live Kroger connection is enabled."
        ),
        RetailConnectorProfile(
            id: "target",
            displayName: "Target",
            homepage: URL(string: "https://www.target.com")!,
            state: .researchOnly,
            capabilities: [.pickup, .delivery, .guidedProductHandoff],
            integrationNote: "Public handoff research only; no catalog or cart API is represented as available."
        ),
        RetailConnectorProfile(
            id: "amazon-fresh",
            displayName: "Amazon Fresh",
            homepage: URL(string: "https://www.amazon.com/fresh")!,
            state: .researchOnly,
            capabilities: [.delivery, .guidedProductHandoff],
            integrationNote: "Homepage handoff only until an approved partner interface exists."
        ),
        RetailConnectorProfile(
            id: "generic-affiliate",
            displayName: "Generic affiliate",
            homepage: URL(string: "https://example.invalid")!,
            state: .credentialsRequired,
            capabilities: [.guidedProductHandoff],
            integrationNote: "URL-template abstraction for a future approved affiliate program; intentionally inactive."
        )
    ]

    static func profile(id: String) -> RetailConnectorProfile? {
        profiles.first { $0.id == id }
    }
}

extension RetailerCatalogService {
    var supportsCart: Bool { capabilities.contains(.cartCreation) }
    var supportsWishlist: Bool { capabilities.contains(.wishlist) }
    var supportsDelivery: Bool { capabilities.contains(.delivery) }

    func lookupProduct(
        retailerProductID: String,
        storeID: String? = nil
    ) async throws -> RetailerProductRecord {
        try await resolveProduct(retailerProductID: retailerProductID, storeID: storeID)
    }
}

struct CredentialFreeRetailConnector: RetailerCatalogService {
    let profile: RetailConnectorProfile

    var retailerID: String { profile.id }
    var capabilities: RetailerCapabilities { profile.capabilities }

    func searchProducts(
        for request: RetailerProductSearchRequest
    ) async throws -> [RetailerProductRecord] {
        throw RetailerServiceError.unsupportedCapability(
            "Live \(profile.displayName) catalog search without approved credentials"
        )
    }

    func resolveProduct(
        retailerProductID: String,
        storeID: String?
    ) async throws -> RetailerProductRecord {
        throw RetailerServiceError.unsupportedCapability(
            "Live \(profile.displayName) product lookup without approved credentials"
        )
    }

    func refresh(product: RetailerProductRecord) async throws -> RetailerProductRecord {
        throw RetailerServiceError.unsupportedCapability(
            "Live \(profile.displayName) price and availability refresh"
        )
    }

    func createHandoff(manifest: ShoppingManifest) async throws -> RetailerHandoff {
        guard profile.homepage.scheme == "https", profile.homepage.host != "example.invalid" else {
            throw RetailerServiceError.unsupportedCapability(
                "Affiliate handoff before an approved destination is configured"
            )
        }
        return RetailerHandoff(
            retailerID: profile.id,
            mode: .retailerHome,
            url: profile.homepage,
            title: "Visit \(profile.displayName)",
            disclosure: "This opens the retailer homepage. SmartCart did not transfer products, create a cart, reserve fulfillment, or submit payment."
        )
    }
}

struct OfflineBarcodeRecord: Hashable {
    var upc: String
    var name: String
    var brand: String
    var retailerProductID: String?
}

enum OfflineBarcodeCatalog {
    private static let records: [OfflineBarcodeRecord] = [
        OfflineBarcodeRecord(upc: "078742002166", name: "Penne Pasta", brand: "Great Value", retailerProductID: "10534084"),
        OfflineBarcodeRecord(upc: "078742131910", name: "Extra Virgin Olive Oil", brand: "Great Value", retailerProductID: "10315102"),
        OfflineBarcodeRecord(upc: "041000303314", name: "Shredded Parmesan Cheese", brand: "Kraft", retailerProductID: "47088917")
    ]

    static func lookup(upc: String) -> OfflineBarcodeRecord? {
        let normalized = upc.filter(\.isNumber)
        return records.first { $0.upc == normalized }
    }
}
