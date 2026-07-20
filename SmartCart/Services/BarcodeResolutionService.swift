import Foundation
import Network
import OSLog

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
    let packageDisplayText: String?
    let imageURL: URL?
    let externalReference: String?
    let catalogSource: String?
    let isVerified: Bool?

    init(
        identifier: String,
        name: String,
        brand: String? = nil,
        packageDisplayText: String? = nil,
        imageURL: URL? = nil,
        externalReference: String? = nil,
        catalogSource: String? = nil,
        isVerified: Bool? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.brand = brand
        self.packageDisplayText = packageDisplayText
        self.imageURL = imageURL
        self.externalReference = externalReference
        self.catalogSource = catalogSource
        self.isVerified = isVerified
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
            var identities = Set((item.barcodeGTINs ?? []) + [item.gtin14].compactMap { $0 })
            if let legacyUPC = item.upc,
               case .success(let normalized) = BarcodeNormalizer.normalize(legacyUPC) {
                identities.insert(normalized.canonicalGTIN14)
            }
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
                    name: "Kettle Cooked Original Potato Chips with Sea Salt",
                    brand: "Great Value"
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
    case configuration(BarcodeBackendConfigurationError)
    case failure(BarcodeLookupFailure)
}

enum BarcodeBackendBuildMode: Hashable, Sendable {
    case debug
    case release

    static var current: BarcodeBackendBuildMode {
        #if DEBUG
        .debug
        #else
        .release
        #endif
    }
}

enum BarcodeBackendConfigurationSource: String, Hashable, Sendable {
    case injected
    case debugEnvironment
    case bundle
}

enum BarcodeBackendConfigurationError: Error, Hashable, Sendable {
    case missing
    case invalidURL
    case insecureReleaseURL
    case disallowedReleaseHost
}

extension BarcodeBackendConfigurationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missing:
            "The barcode product service is not configured."
        case .invalidURL:
            "The barcode product service URL is invalid."
        case .insecureReleaseURL:
            "Release builds require an HTTPS barcode product service."
        case .disallowedReleaseHost:
            "Release builds require a public, non-loopback barcode product service."
        }
    }
}

struct BarcodeBackendConfiguration: Hashable, Sendable {
    static let bundleKey = "SmartCartBarcodeBackendURL"

    let baseURL: URL
    let source: BarcodeBackendConfigurationSource

    static func resolve(
        explicitURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        buildMode: BarcodeBackendBuildMode = .current
    ) -> Result<BarcodeBackendConfiguration, BarcodeBackendConfigurationError> {
        if let explicitURL {
            return validated(explicitURL, source: .injected, buildMode: buildMode)
        }

        if buildMode == .debug {
            let environmentValue = [
                "SMARTCART_BARCODE_BACKEND_URL",
                "SMARTCART_RECIPE_BACKEND_URL",
                "SMARTCART_COMMERCE_BACKEND_URL"
            ]
                .compactMap { environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if let environmentValue {
                guard let url = URL(string: environmentValue) else { return .failure(.invalidURL) }
                return validated(url, source: .debugEnvironment, buildMode: buildMode)
            }
        }

        if let bundleValue = bundleInfo[bundleKey] as? String {
            let value = bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, !value.contains("$("), let url = URL(string: value) {
                return validated(url, source: .bundle, buildMode: buildMode)
            }
            if !value.isEmpty, !value.contains("$(") {
                return .failure(.invalidURL)
            }
        }

        return .failure(.missing)
    }

    private static func validated(
        _ url: URL,
        source: BarcodeBackendConfigurationSource,
        buildMode: BarcodeBackendBuildMode
    ) -> Result<BarcodeBackendConfiguration, BarcodeBackendConfigurationError> {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              scheme == "http" || scheme == "https"
        else {
            return .failure(.invalidURL)
        }

        if buildMode == .release {
            guard scheme == "https" else { return .failure(.insecureReleaseURL) }
            guard !isDisallowedReleaseHost(host) else {
                return .failure(.disallowedReleaseHost)
            }
        }

        return .success(BarcodeBackendConfiguration(baseURL: url, source: source))
    }

    private static func isDisallowedReleaseHost(_ rawHost: String) -> Bool {
        var host = rawHost
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return true }

        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }
        let reservedNames = [
            "example", "example.com", "example.net", "example.org",
            "test", "invalid"
        ]
        if reservedNames.contains(host) ||
            [".example", ".example.com", ".example.net", ".example.org", ".test", ".invalid"]
                .contains(where: host.hasSuffix) {
            return true
        }
        if host == "0.0.0.0" || host == "::" || host == "::1" || host == "[::1]" || host == "*" {
            return true
        }
        let unwrappedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let address = IPv4Address(unwrappedHost) {
            return isDisallowedIPv4(Array(address.rawValue))
        }
        if let address = IPv6Address(unwrappedHost) {
            let bytes = Array(address.rawValue)
            guard bytes.count == 16 else { return true }
            if bytes.allSatisfy({ $0 == 0 }) ||
                (bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1) {
                return true
            }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }),
               bytes[10] == 0xff,
               bytes[11] == 0xff {
                return isDisallowedIPv4(Array(bytes.suffix(4)))
            }
            if bytes[0] & 0xfe == 0xfc ||
                (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) ||
                (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0xc0) ||
                bytes[0] == 0xff ||
                Array(bytes.prefix(4)) == [0x20, 0x01, 0x0d, 0xb8] {
                return true
            }
            return false
        }

        return !isValidPublicDNSHost(host)
    }

    private static func isValidPublicDNSHost(_ host: String) -> Bool {
        guard host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        return labels.allSatisfy { label in
            let bytes = Array(label.utf8)
            guard (1...63).contains(bytes.count),
                  let first = bytes.first,
                  let last = bytes.last,
                  first.isASCIIAlphaNumeric,
                  last.isASCIIAlphaNumeric else {
                return false
            }
            return bytes.allSatisfy { $0.isASCIIAlphaNumeric || $0 == 45 }
        }
    }

    private static func isDisallowedIPv4(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else { return true }
        let first = octets[0]
        let second = octets[1]
        let third = octets[2]
        switch (first, second) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168):
            return true
        case (172, 16...31):
            return true
        case (100, 64...127), (198, 18...19):
            return true
        default:
            break
        }
        if first >= 224 ||
            (first == 192 && second == 0 && (third == 0 || third == 2)) ||
            (first == 198 && second == 51 && third == 100) ||
            (first == 203 && second == 0 && third == 113) {
            return true
        }
        return false
    }
}

private extension UInt8 {
    var isASCIIAlphaNumeric: Bool {
        (48...57).contains(self) || (65...90).contains(self) || (97...122).contains(self)
    }
}

enum BarcodeLookupFailure: Error, Hashable, Sendable {
    case configurationMissing
    case offline
    case timedOut
    case rateLimited
    case serverError
    case malformedResponse
}

extension BarcodeLookupFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            "The barcode product service is not configured for this build."
        case .offline:
            "The barcode product service could not be reached."
        case .timedOut:
            "The barcode product lookup timed out."
        case .rateLimited:
            "The barcode product service is temporarily rate limited."
        case .serverError:
            "The barcode product service returned an error."
        case .malformedResponse:
            "The barcode product service returned an unreadable response."
        }
    }
}

/// Resolves product identity through the SmartCart backend. The provider does
/// not return or imply price, availability, pantry quantity, or purchase state.
struct SmartCartBackendBarcodeAdapter: BarcodeProductAdapter, @unchecked Sendable {
    let identifier = "smartcart-barcode-api"

    private static let logger = Logger(
        subsystem: "com.blakestudio.smartcart",
        category: "BarcodeLookup"
    )

    private let session: URLSession
    private let configuration: Result<BarcodeBackendConfiguration, BarcodeBackendConfigurationError>

    init(
        session: URLSession = .shared,
        baseURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        buildMode: BarcodeBackendBuildMode = .current
    ) {
        self.session = session
        configuration = BarcodeBackendConfiguration.resolve(
            explicitURL: baseURL,
            environment: environment,
            bundleInfo: bundleInfo,
            buildMode: buildMode
        )
    }

    func resolve(_ barcode: NormalizedBarcode) async throws -> BarcodeProduct? {
        let resolvedConfiguration: BarcodeBackendConfiguration
        switch configuration {
        case .success(let value):
            resolvedConfiguration = value
        case .failure(let error):
            Self.logger.error("Barcode lookup unavailable: configuration error \(String(describing: error), privacy: .public)")
            throw SmartCartBarcodeAdapterError.configuration(error)
        }

        let url = resolvedConfiguration.baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("barcodes")
            .appendingPathComponent(barcode.canonicalGTIN14)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SmartCart-iOS/0.4 barcode-identity", forHTTPHeaderField: "User-Agent")

        let startedAt = Date()
        Self.logger.info(
            "Barcode lookup request host=\(resolvedConfiguration.baseURL.host ?? "unknown", privacy: .public) route=/v1/barcodes/:gtin configuration=\(resolvedConfiguration.source.rawValue, privacy: .public)"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            let failure: BarcodeLookupFailure
            switch error.code {
            case .timedOut:
                failure = .timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff,
                 .callIsActive, .dataNotAllowed:
                failure = .offline
            case .cannotParseResponse, .badServerResponse, .cannotDecodeRawData,
                 .cannotDecodeContentData:
                failure = .malformedResponse
            default:
                failure = .serverError
            }
            Self.logger.error(
                "Barcode lookup transport failure outcome=\(String(describing: failure), privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000), privacy: .public)"
            )
            throw SmartCartBarcodeAdapterError.failure(failure)
        } catch {
            Self.logger.error("Barcode lookup transport failure outcome=serverError")
            throw SmartCartBarcodeAdapterError.failure(.serverError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SmartCartBarcodeAdapterError.failure(.malformedResponse)
        }
        Self.logger.info(
            "Barcode lookup response status=\(http.statusCode, privacy: .public) durationMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000), privacy: .public)"
        )
        switch http.statusCode {
        case 200..<300:
            break
        case 404:
            if let notFound = try? JSONDecoder().decode(BarcodeAPIResponse.self, from: data),
               notFound.status == "not_found",
               notFound.barcode == barcode.canonicalGTIN14 {
                return nil
            }
            throw SmartCartBarcodeAdapterError.failure(.serverError)
        case 408, 504:
            throw SmartCartBarcodeAdapterError.failure(.timedOut)
        case 429:
            throw SmartCartBarcodeAdapterError.failure(.rateLimited)
        case 500..<600:
            throw SmartCartBarcodeAdapterError.failure(.serverError)
        default:
            throw SmartCartBarcodeAdapterError.failure(.serverError)
        }

        let envelope: BarcodeAPIResponse
        do {
            envelope = try JSONDecoder().decode(BarcodeAPIResponse.self, from: data)
        } catch {
            throw SmartCartBarcodeAdapterError.failure(.malformedResponse)
        }
        guard envelope.barcode == barcode.canonicalGTIN14 else {
            throw SmartCartBarcodeAdapterError.failure(.malformedResponse)
        }
        if envelope.status == "not_found" { return nil }
        guard envelope.status == "resolved", let product = envelope.product else {
            throw SmartCartBarcodeAdapterError.failure(.malformedResponse)
        }
        let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw SmartCartBarcodeAdapterError.failure(.malformedResponse)
        }

        return BarcodeProduct(
            identifier: "backend:\(barcode.canonicalGTIN14)",
            name: name,
            brand: product.brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            packageDisplayText: product.quantity?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            imageURL: safeImageURL(product.imageURL),
            externalReference: nil,
            catalogSource: envelope.source?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            isVerified: envelope.verified
        )
    }

    private func safeImageURL(_ rawValue: String?) -> URL? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: rawValue),
              url.scheme == "https",
              url.user == nil,
              url.password == nil,
              url.host != nil
        else { return nil }
        return url
    }

    private struct BarcodeAPIResponse: Decodable {
        let status: String
        let barcode: String
        let product: Product?
        let source: String?
        let verified: Bool?

        struct Product: Decodable {
            let name: String
            let brand: String?
            let quantity: String?
            let imageURL: String?
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
    let failure: BarcodeLookupFailure
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

enum BarcodeLookupOutcome: Hashable, Sendable {
    case resolved(ResolvedBarcodeProduct)
    case notFound(UnresolvedBarcode)
    case unavailable(UnresolvedBarcode, BarcodeLookupFailure)
    case invalid(UnresolvedBarcode)
}

typealias BarcodeResolutionResult = BarcodeLookupOutcome

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
            return .invalid(
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
                let failure: BarcodeLookupFailure
                if let adapterError = error as? SmartCartBarcodeAdapterError {
                    switch adapterError {
                    case .configuration:
                        failure = .configurationMissing
                    case .failure(let typedFailure):
                        failure = typedFailure
                    }
                } else if let typedFailure = error as? BarcodeLookupFailure {
                    failure = typedFailure
                } else {
                    failure = .serverError
                }
                adapterFailures.append(
                    BarcodeAdapterFailure(
                        adapterIdentifier: adapter.identifier,
                        failure: failure
                    )
                )
            }
        }

        let unresolved = UnresolvedBarcode(
            scan: scan,
            normalizedBarcode: normalized,
            reason: .noMatch,
            attemptedAdapterIdentifiers: attemptedAdapterIdentifiers,
            adapterFailures: adapterFailures
        )
        if let failure = adapterFailures.first?.failure {
            return .unavailable(unresolved, failure)
        }
        return .notFound(unresolved)
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
