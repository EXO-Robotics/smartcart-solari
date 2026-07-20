import Foundation

/// The scanner payload exactly as it was received. Normalization never replaces these values.
struct BarcodeScan: Hashable, Sendable {
    let rawBarcode: String
    let rawSymbology: String?

    init(rawBarcode: String, rawSymbology: String? = nil) {
        self.rawBarcode = rawBarcode
        self.rawSymbology = rawSymbology
    }
}

enum BarcodeFormat: String, Codable, Hashable, Sendable {
    case ean8
    case upcA
    case ean13
    case gtin14
}

enum BarcodeValidationError: Error, Hashable, Sendable {
    case empty
    case containsNonASCIIDigits
    case unsupportedLength(Int)
    case invalidCheckDigit(expected: Character, actual: Character)
}

extension BarcodeValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty:
            "The barcode is empty."
        case .containsNonASCIIDigits:
            "The barcode must contain only ASCII digits."
        case .unsupportedLength(let length):
            "The barcode has \(length) digits; expected EAN-8 (8), UPC-A (12), EAN-13 (13), or GTIN-14 (14)."
        case .invalidCheckDigit(let expected, let actual):
            "The barcode check digit is \(actual); expected \(expected)."
        }
    }
}

/// A validated barcode. All representations remain strings so leading zeroes cannot be lost.
struct NormalizedBarcode: Hashable, Codable, Sendable {
    let digits: String
    let format: BarcodeFormat
    let canonicalGTIN14: String

    var upcA: String? {
        guard canonicalGTIN14.hasPrefix("00") else { return nil }
        return String(canonicalGTIN14.suffix(12))
    }

    var ean13: String? {
        guard canonicalGTIN14.hasPrefix("0") else { return nil }
        return String(canonicalGTIN14.suffix(13))
    }
}

enum BarcodeNormalizer {
    static func normalize(_ scan: BarcodeScan) -> Result<NormalizedBarcode, BarcodeValidationError> {
        normalize(scan.rawBarcode)
    }

    static func normalize(_ rawBarcode: String) -> Result<NormalizedBarcode, BarcodeValidationError> {
        let digits = rawBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty else { return .failure(.empty) }
        guard digits.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else {
            return .failure(.containsNonASCIIDigits)
        }

        let format: BarcodeFormat
        let canonicalGTIN14: String
        switch digits.count {
        case 8:
            format = .ean8
            canonicalGTIN14 = "000000" + digits
        case 12:
            format = .upcA
            canonicalGTIN14 = "00" + digits
        case 13:
            format = .ean13
            canonicalGTIN14 = "0" + digits
        case 14:
            format = .gtin14
            canonicalGTIN14 = digits
        default:
            return .failure(.unsupportedLength(digits.count))
        }

        let expected = checkDigit(forBody: digits.dropLast())
        guard let actual = digits.last, actual == expected else {
            return .failure(.invalidCheckDigit(expected: expected, actual: digits.last!))
        }

        return .success(
            NormalizedBarcode(
                digits: digits,
                format: format,
                canonicalGTIN14: canonicalGTIN14
            )
        )
    }

    /// GS1 modulo-10 check digit calculation for EAN-8, UPC-A, EAN-13, and GTIN-14 bodies.
    static func checkDigit(forBody body: Substring) -> Character {
        var sum = 0
        for (offset, character) in body.reversed().enumerated() {
            let digit = Int(character.asciiValue! - Character("0").asciiValue!)
            sum += digit * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return Character(String((10 - (sum % 10)) % 10))
    }
}

/// Product identity only. Price and availability intentionally belong to other, verified systems.
struct BarcodeProduct: Hashable, Codable, Sendable {
    let identifier: String
    let name: String
    let brand: String?
    let externalReference: String?

    init(
        identifier: String,
        name: String,
        brand: String? = nil,
        externalReference: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.brand = brand
        self.externalReference = externalReference
    }
}

struct UserEditedBarcodeEntry: Hashable, Codable, Sendable {
    let canonicalGTIN14: String
    let product: BarcodeProduct
    let editedAt: Date

    init(canonicalGTIN14: String, product: BarcodeProduct, editedAt: Date = .now) {
        self.canonicalGTIN14 = canonicalGTIN14
        self.product = product
        self.editedAt = editedAt
    }
}

protocol BarcodeUserEditedCache: Sendable {
    func product(forCanonicalGTIN14 canonicalGTIN14: String) async -> BarcodeProduct?
}

protocol WritableBarcodeUserEditedCache: BarcodeUserEditedCache {
    func save(_ entry: UserEditedBarcodeEntry) async
    func removeProduct(forCanonicalGTIN14 canonicalGTIN14: String) async
}

actor InMemoryBarcodeUserEditedCache: WritableBarcodeUserEditedCache {
    private var entries: [String: UserEditedBarcodeEntry]

    init(entries: [UserEditedBarcodeEntry] = []) {
        self.entries = Dictionary(entries.map { ($0.canonicalGTIN14, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    func product(forCanonicalGTIN14 canonicalGTIN14: String) -> BarcodeProduct? {
        entries[canonicalGTIN14]?.product
    }

    func save(_ entry: UserEditedBarcodeEntry) {
        entries[entry.canonicalGTIN14] = entry
    }

    func removeProduct(forCanonicalGTIN14 canonicalGTIN14: String) {
        entries.removeValue(forKey: canonicalGTIN14)
    }
}

/// A read-only snapshot of durable pantry mappings. Manual names are already
/// persisted in SmartCart state, so relaunches do not depend on a second cache.
struct PantryBarcodeUserEditedCache: BarcodeUserEditedCache, Sendable {
    private let productsByGTIN14: [String: BarcodeProduct]

    init(items: [PantryInventoryItem]) {
        var products: [String: BarcodeProduct] = [:]
        for item in items where item.requiresUserNaming != true {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.caseInsensitiveCompare("Unknown Product") != .orderedSame else {
                continue
            }
            let identities = Set((item.barcodeGTINs ?? []) + [item.gtin14].compactMap { $0 })
            for identity in identities where products[identity] == nil {
                products[identity] = BarcodeProduct(
                    identifier: "pantry:\(item.id.uuidString)",
                    name: name,
                    brand: item.brand.isEmpty ? nil : item.brand,
                    externalReference: item.preferredRetailerProductID
                )
            }
        }
        productsByGTIN14 = products
    }

    func product(forCanonicalGTIN14 canonicalGTIN14: String) async -> BarcodeProduct? {
        productsByGTIN14[canonicalGTIN14]
    }
}

struct BundledBarcodeFixture: Hashable, Sendable {
    let barcode: String
    let product: BarcodeProduct

    init(barcode: String, product: BarcodeProduct) {
        self.barcode = barcode
        self.product = product
    }
}

struct BundledBarcodeFixtureCatalog: Sendable {
    private let productsByGTIN14: [String: BarcodeProduct]

    init(fixtures: [BundledBarcodeFixture]) {
        var productsByGTIN14: [String: BarcodeProduct] = [:]
        for fixture in fixtures {
            guard case .success(let barcode) = BarcodeNormalizer.normalize(fixture.barcode) else {
                continue
            }
            // The first fixture wins, making duplicate input deterministic.
            if productsByGTIN14[barcode.canonicalGTIN14] == nil {
                productsByGTIN14[barcode.canonicalGTIN14] = fixture.product
            }
        }
        self.productsByGTIN14 = productsByGTIN14
    }

    func product(for barcode: NormalizedBarcode) -> BarcodeProduct? {
        productsByGTIN14[barcode.canonicalGTIN14]
    }

    static let smartCart = BundledBarcodeFixtureCatalog(
        fixtures: [
            BundledBarcodeFixture(
                barcode: "078742002163",
                product: BarcodeProduct(
                    identifier: "fixture:078742002163",
                    name: "Penne Pasta",
                    brand: "Great Value",
                    externalReference: "10534084"
                )
            ),
            BundledBarcodeFixture(
                barcode: "078742131917",
                product: BarcodeProduct(
                    identifier: "fixture:078742131917",
                    name: "Extra Virgin Olive Oil",
                    brand: "Great Value",
                    externalReference: "10315102"
                )
            ),
            BundledBarcodeFixture(
                barcode: "041000303319",
                product: BarcodeProduct(
                    identifier: "fixture:041000303319",
                    name: "Shredded Parmesan Cheese",
                    brand: "Kraft",
                    externalReference: "47088917"
                )
            )
        ]
    )
}

/// Optional integrations implement this boundary. The service itself performs no network calls.
protocol BarcodeProductAdapter: Sendable {
    var identifier: String { get }
    func resolve(_ barcode: NormalizedBarcode) async throws -> BarcodeProduct?
}

enum SmartCartBarcodeAdapterError: Error, Hashable, Sendable {
    case invalidEndpoint
    case invalidResponse
    case server(statusCode: Int)
}

/// Resolves product identity through the SmartCart backend. The provider does
/// not return or imply price, availability, pantry quantity, or purchase state.
struct SmartCartBackendBarcodeAdapter: BarcodeProductAdapter, @unchecked Sendable {
    let identifier = "smartcart-barcode-api"

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL? = nil) {
        self.session = session
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let environment = ProcessInfo.processInfo.environment
            let configured = environment["SMARTCART_BARCODE_BACKEND_URL"]
                ?? environment["SMARTCART_RECIPE_BACKEND_URL"]
                ?? environment["SMARTCART_COMMERCE_BACKEND_URL"]
            self.baseURL = configured.flatMap(URL.init(string:))
                ?? URL(string: "http://localhost:8787")!
        }
    }

    func resolve(_ barcode: NormalizedBarcode) async throws -> BarcodeProduct? {
        let url = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("barcodes")
            .appendingPathComponent(barcode.canonicalGTIN14)
        guard url.scheme == "http" || url.scheme == "https" else {
            throw SmartCartBarcodeAdapterError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SmartCart-iOS/0.4 barcode-identity", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SmartCartBarcodeAdapterError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw SmartCartBarcodeAdapterError.server(statusCode: http.statusCode)
        }

        let envelope: BarcodeAPIResponse
        do {
            envelope = try JSONDecoder().decode(BarcodeAPIResponse.self, from: data)
        } catch {
            throw SmartCartBarcodeAdapterError.invalidResponse
        }
        guard envelope.status == "resolved", let product = envelope.product else { return nil }
        let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        return BarcodeProduct(
            identifier: "backend:\(barcode.canonicalGTIN14)",
            name: name,
            brand: product.brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            externalReference: nil
        )
    }

    private struct BarcodeAPIResponse: Decodable {
        let status: String
        let product: Product?

        struct Product: Decodable {
            let name: String
            let brand: String?
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum BarcodeResolutionSource: Hashable, Sendable {
    case localUserEditedCache
    case bundledFixture
    case adapter(identifier: String)
}

struct ResolvedBarcodeProduct: Hashable, Sendable {
    let scan: BarcodeScan
    let barcode: NormalizedBarcode
    let product: BarcodeProduct
    let source: BarcodeResolutionSource
}

struct BarcodeAdapterFailure: Hashable, Sendable {
    let adapterIdentifier: String
    let message: String
}

enum UnresolvedBarcodeReason: Hashable, Sendable {
    case invalid(BarcodeValidationError)
    case noMatch
}

struct UnresolvedBarcode: Hashable, Sendable {
    let scan: BarcodeScan
    let normalizedBarcode: NormalizedBarcode?
    let reason: UnresolvedBarcodeReason
    let attemptedAdapterIdentifiers: [String]
    let adapterFailures: [BarcodeAdapterFailure]
}

enum BarcodeResolutionResult: Hashable, Sendable {
    case resolved(ResolvedBarcodeProduct)
    case unresolved(UnresolvedBarcode)
}

protocol BarcodeProductResolver: Sendable {
    func resolve(_ scan: BarcodeScan) async -> BarcodeResolutionResult
}

struct BarcodeResolutionService: BarcodeProductResolver, Sendable {
    private let userEditedCache: any BarcodeUserEditedCache
    private let fixtures: BundledBarcodeFixtureCatalog
    private let adapters: [any BarcodeProductAdapter]

    init(
        userEditedCache: any BarcodeUserEditedCache = InMemoryBarcodeUserEditedCache(),
        fixtures: BundledBarcodeFixtureCatalog = .smartCart,
        adapters: [any BarcodeProductAdapter] = []
    ) {
        self.userEditedCache = userEditedCache
        self.fixtures = fixtures
        self.adapters = adapters
    }

    func resolve(_ scan: BarcodeScan) async -> BarcodeResolutionResult {
        let normalized: NormalizedBarcode
        switch BarcodeNormalizer.normalize(scan) {
        case .success(let barcode):
            normalized = barcode
        case .failure(let error):
            return .unresolved(
                UnresolvedBarcode(
                    scan: scan,
                    normalizedBarcode: nil,
                    reason: .invalid(error),
                    attemptedAdapterIdentifiers: [],
                    adapterFailures: []
                )
            )
        }

        if let product = await userEditedCache.product(
            forCanonicalGTIN14: normalized.canonicalGTIN14
        ) {
            return resolved(product, scan: scan, barcode: normalized, source: .localUserEditedCache)
        }

        if let product = fixtures.product(for: normalized) {
            return resolved(product, scan: scan, barcode: normalized, source: .bundledFixture)
        }

        var attemptedAdapterIdentifiers: [String] = []
        var adapterFailures: [BarcodeAdapterFailure] = []
        for adapter in adapters {
            attemptedAdapterIdentifiers.append(adapter.identifier)
            do {
                if let product = try await adapter.resolve(normalized) {
                    return resolved(
                        product,
                        scan: scan,
                        barcode: normalized,
                        source: .adapter(identifier: adapter.identifier)
                    )
                }
            } catch {
                adapterFailures.append(
                    BarcodeAdapterFailure(
                        adapterIdentifier: adapter.identifier,
                        message: String(describing: error)
                    )
                )
            }
        }

        return .unresolved(
            UnresolvedBarcode(
                scan: scan,
                normalizedBarcode: normalized,
                reason: .noMatch,
                attemptedAdapterIdentifiers: attemptedAdapterIdentifiers,
                adapterFailures: adapterFailures
            )
        )
    }

    private func resolved(
        _ product: BarcodeProduct,
        scan: BarcodeScan,
        barcode: NormalizedBarcode,
        source: BarcodeResolutionSource
    ) -> BarcodeResolutionResult {
        .resolved(
            ResolvedBarcodeProduct(
                scan: scan,
                barcode: barcode,
                product: product,
                source: source
            )
        )
    }
}

struct BarcodeDuplicateCandidate: Hashable, Sendable {
    let existingItemIdentifier: String
    let existingProduct: BarcodeProduct
    let scannedProduct: BarcodeProduct
    let barcode: NormalizedBarcode
}

enum BarcodeDuplicateResolutionAction: String, CaseIterable, Codable, Hashable, Sendable {
    case increment
    case replace
    case cancel
}

typealias BarcodeDuplicateAction = BarcodeDuplicateResolutionAction

struct BarcodeDuplicateResolution: Hashable, Sendable {
    let candidate: BarcodeDuplicateCandidate
    let action: BarcodeDuplicateResolutionAction
}

struct PantryBarcodeSubmission: Hashable, Sendable {
    let scan: BarcodeScan
    let barcode: NormalizedBarcode
    let name: String
    let brand: String
    let externalProductID: String?
    let requiresUserNaming: Bool
}
