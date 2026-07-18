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
            capabilities: [.catalogSearch, .exactProductLinks, .guidedProductHandoff],
            integrationNote: "Seeded catalog and exact public product links with a user-driven Safari handoff. No account link, live inventory, cart creation, fulfillment scheduling, payment, or checkout integration."
        ),
        RetailConnectorProfile(
            id: "instacart",
            displayName: "Instacart",
            homepage: URL(string: "https://www.instacart.com")!,
            state: .credentialsRequired,
            capabilities: [.catalogSearch, .pickup, .delivery, .manifestTransfer],
            integrationNote: "Shopping-list adapter, cache, and in-app handoff are ready; approved server-side credentials are required before live calls."
        ),
        RetailConnectorProfile(
            id: "kroger",
            displayName: "Kroger",
            homepage: URL(string: "https://www.kroger.com")!,
            state: .researchOnly,
            capabilities: [],
            integrationNote: "A guided Kroger Shopping List adapter is planned, but no product guide or live connection is enabled."
        ),
        RetailConnectorProfile(
            id: "target",
            displayName: "Target",
            homepage: URL(string: "https://www.target.com")!,
            state: .demoReady,
            capabilities: [.catalogSearch, .exactProductLinks, .guidedProductHandoff],
            integrationNote: "A bounded seeded catalog, exact public product links, search fallbacks, and a user-driven Safari guide are available. No account, list, cart, fulfillment, payment, or checkout integration is represented."
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

protocol InstacartHandoffServicing: Sendable {
    func createHandoff(
        draft: InstacartManifestDraft,
        postalCode: String,
        preferredRetailer: InstacartRetailerPreference,
        fulfillment: CommerceFulfillmentPreference
    ) async throws -> InstacartHandoffResponse
}

actor InstacartHandoffClient: InstacartHandoffServicing {
    private let session: URLSession
    private let baseURL: URL
    private var cachedResponses: [Data: InstacartHandoffResponse] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        let environment = ProcessInfo.processInfo.environment
        if let configured = environment["SMARTCART_COMMERCE_BACKEND_URL"] ?? environment["SMARTCART_RECIPE_BACKEND_URL"],
           let url = URL(string: configured) {
            baseURL = url
        } else {
            baseURL = URL(string: "http://localhost:8787")!
        }
    }

    func createHandoff(
        draft: InstacartManifestDraft,
        postalCode: String,
        preferredRetailer: InstacartRetailerPreference,
        fulfillment: CommerceFulfillmentPreference
    ) async throws -> InstacartHandoffResponse {
        let cacheKey = try JSONEncoder.smartCart.encode(
            CacheIdentity(
                draft: draft,
                postalCode: postalCode,
                preferredRetailerKey: preferredRetailer.rawValue,
                fulfillmentPreference: fulfillment.rawValue
            )
        )
        if let cached = cachedResponses[cacheKey] {
            return cached
        }

        do {
            let account: CommerceAccountEnvelope = try await post(
                path: "/v1/demo/accounts",
                body: CommerceAccountRequest(
                    displayName: "SmartCart Commerce Handoff",
                    email: "commerce-\(UUID().uuidString.lowercased())@smartcart.local"
                ),
                bearerToken: nil
            )
            let sessionEnvelope: CommerceSessionEnvelope = try await post(
                path: "/v1/demo/sessions",
                body: CommerceSessionRequest(accountId: account.account.id),
                bearerToken: nil
            )
            let uploaded: CommerceManifestEnvelope = try await post(
                path: "/v1/manifests",
                body: CommerceManifestUpload(
                    manifest: BackendManifest(
                        draft: draft,
                        preferredRetailer: preferredRetailer,
                        fulfillment: fulfillment
                    )
                ),
                bearerToken: sessionEnvelope.session.token
            )
            let response: InstacartHandoffResponse = try await post(
                path: "/api/handoffs/instacart",
                body: CommerceHandoffRequest(
                    shoppingManifestId: uploaded.manifest.id,
                    postalCode: postalCode,
                    preferredRetailerKey: preferredRetailer.rawValue,
                    fulfillmentPreference: fulfillment.rawValue
                ),
                bearerToken: sessionEnvelope.session.token
            )
            cachedResponses[cacheKey] = response
            return response
        } catch let error as InstacartHandoffError {
            throw error
        } catch let error as URLError {
            if error.code == .timedOut { throw InstacartHandoffError.timeout }
            throw InstacartHandoffError.backendUnavailable
        } catch {
            throw InstacartHandoffError.unreadableResponse
        }
    }

    private func post<Response: Decodable, Body: Encodable>(
        path: String,
        body: Body,
        bearerToken: String?
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw InstacartHandoffError.backendUnavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SmartCart-iOS/0.4 instacart-handoff", forHTTPHeaderField: "User-Agent")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder.smartCart.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InstacartHandoffError.unreadableResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let envelope = try? JSONDecoder.smartCart.decode(CommerceErrorEnvelope.self, from: data)
            throw InstacartHandoffError.server(
                envelope?.error.message ?? "The commerce service returned HTTP \(http.statusCode)."
            )
        }
        do {
            return try JSONDecoder.smartCart.decode(Response.self, from: data)
        } catch {
            throw InstacartHandoffError.unreadableResponse
        }
    }
}

private struct CacheIdentity: Encodable {
    var draft: InstacartManifestDraft
    var postalCode: String
    var preferredRetailerKey: String
    var fulfillmentPreference: String
}

private struct CommerceAccountRequest: Encodable {
    var displayName: String
    var email: String
}

private struct CommerceSessionRequest: Encodable {
    var accountId: String
}

private struct CommerceAccountEnvelope: Decodable {
    struct Account: Decodable { var id: String }
    var account: Account
}

private struct CommerceSessionEnvelope: Decodable {
    struct Session: Decodable { var token: String }
    var session: Session
}

private struct CommerceManifestEnvelope: Decodable {
    struct Manifest: Decodable { var id: String }
    var manifest: Manifest
}

private struct CommerceManifestUpload: Encodable {
    var manifest: BackendManifest
}

private struct BackendManifest: Encodable {
    struct Item: Encodable {
        struct Product: Encodable {
            var itemID: String
            var title: String
        }

        struct Commerce: Encodable {
            var name: String
            var displayText: String
            var quantity: Double
            var unit: String
            var healthFilters: [String]
            var exactUPC: String?
            var exactIdentityReliable: Bool
            var pantryExcluded: Bool
            var optionalSelected: Bool
            var quantityConfirmed: Bool
            var unresolvedAlternative: Bool
        }

        var id: String
        var ingredientID: String
        var ingredientName: String
        var requestedQuantity: String
        var purchaseQuantity: Int
        var product: Product
        var status: String
        var commerce: Commerce
    }

    var recipeID: String
    var recipeTitle: String
    var retailerID: String
    var storeID: String
    var storeName: String
    var desiredServings: Int
    var fulfillmentMode: String
    var handoffProgress: String
    var items: [Item]

    init(
        draft: InstacartManifestDraft,
        preferredRetailer: InstacartRetailerPreference,
        fulfillment: CommerceFulfillmentPreference
    ) {
        recipeID = draft.recipeID.uuidString
        recipeTitle = draft.title
        retailerID = "instacart"
        storeID = preferredRetailer.rawValue
        storeName = preferredRetailer.label
        desiredServings = draft.desiredServings
        fulfillmentMode = fulfillment == .delivery ? "Delivery" : "Pickup"
        handoffProgress = "notStarted"
        items = draft.items.map { item in
            Item(
                id: item.ingredientID.uuidString,
                ingredientID: item.ingredientID.uuidString,
                ingredientName: item.name,
                requestedQuantity: item.displayText,
                purchaseQuantity: 1,
                product: Item.Product(itemID: "ingredient-\(item.ingredientID.uuidString)", title: item.name),
                status: "waiting",
                commerce: Item.Commerce(
                    name: item.name,
                    displayText: item.displayText,
                    quantity: item.quantity,
                    unit: item.unit,
                    healthFilters: item.healthFilters,
                    exactUPC: item.exactUPC,
                    exactIdentityReliable: item.exactUPC != nil,
                    pantryExcluded: false,
                    optionalSelected: true,
                    quantityConfirmed: item.quantityConfirmed,
                    unresolvedAlternative: item.unresolvedAlternative
                )
            )
        }
    }
}

private struct CommerceHandoffRequest: Encodable {
    var shoppingManifestId: String
    var postalCode: String
    var preferredRetailerKey: String
    var fulfillmentPreference: String
}

private struct CommerceErrorEnvelope: Decodable {
    struct ServerError: Decodable { var message: String }
    var error: ServerError
}

private extension JSONEncoder {
    static var smartCart: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var smartCart: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
