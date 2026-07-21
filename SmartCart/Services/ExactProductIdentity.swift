import Foundation

/// A retailer-scoped identity for a product SmartCart can prove is exact.
///
/// The normalization version is stored with the value so future rules cannot
/// silently reinterpret purchase groups that have already been persisted.
struct ExactProductIdentity: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case retailerProductID
        case gtin
        case exactURL
    }

    static let currentNormalizationVersion = 3

    let retailerID: String
    let kind: Kind
    let normalizedValue: String
    let normalizationVersion: Int

    init?(product: RetailerProductRecord) {
        guard product.linkKind == .exactProduct,
              product.dataSource != .searchFallback,
              let retailerID = Self.normalizedRetailerID(product.retailerID)
        else {
            return nil
        }

        if let productID = Self.normalizedRetailerProductID(
            product.retailerProductID,
            retailerID: retailerID
        ) {
            self.init(
                retailerID: retailerID,
                kind: .retailerProductID,
                normalizedValue: productID
            )
            return
        }

        if let gtin = Self.normalizedGTIN(product.gtin) {
            self.init(
                retailerID: retailerID,
                kind: .gtin,
                normalizedValue: gtin
            )
            return
        }

        guard let exactURL = Self.normalizedExactURL(
            product.exactURL,
            retailerID: retailerID
        ) else {
            return nil
        }
        self.init(
            retailerID: retailerID,
            kind: .exactURL,
            normalizedValue: exactURL
        )
    }

    init?(
        retailerID: String,
        kind: Kind,
        normalizedValue: String,
        normalizationVersion: Int = Self.currentNormalizationVersion
    ) {
        guard let retailerID = Self.normalizedRetailerID(retailerID),
              !normalizedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              normalizationVersion > 0
        else {
            return nil
        }

        self.retailerID = retailerID
        self.kind = kind
        self.normalizedValue = normalizedValue
        self.normalizationVersion = normalizationVersion
    }

    private enum CodingKeys: String, CodingKey {
        case retailerID
        case kind
        case normalizedValue
        case normalizationVersion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let retailerID = try values.decode(String.self, forKey: .retailerID)
        let kind = try values.decode(Kind.self, forKey: .kind)
        let normalizedValue = try values.decode(String.self, forKey: .normalizedValue)
        let normalizationVersion = try values.decode(Int.self, forKey: .normalizationVersion)

        guard let decoded = Self(
            retailerID: retailerID,
            kind: kind,
            normalizedValue: normalizedValue,
            normalizationVersion: normalizationVersion
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .normalizedValue,
                in: values,
                debugDescription: "Exact product identities require a retailer, a value, and a positive normalization version."
            )
        }
        self = decoded
    }

    private static func normalizedRetailerID(_ rawValue: String) -> String? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedRetailerProductID(
        _ rawValue: String,
        retailerID: String
    ) -> String? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty else { return nil }

        if retailerID == ShoppingRetailer.target.rawValue,
           normalized.count > 2,
           String(normalized.prefix(2)).caseInsensitiveCompare("A-") == .orderedSame {
            let suffix = String(normalized.dropFirst(2))
            if suffix.unicodeScalars.allSatisfy(isASCIIDigit) {
                return suffix
            }
        }
        return normalized
    }

    /// Converts checksum-valid GTIN-8, UPC-A, EAN-13, and GTIN-14 to GTIN-14.
    private static func normalizedGTIN(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let compact = String(
            rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .filter { !$0.isWhitespace && $0 != "-" }
        )
        guard [8, 12, 13, 14].contains(compact.count),
              compact.unicodeScalars.allSatisfy(isASCIIDigit)
        else {
            return nil
        }

        let digits = compact.unicodeScalars.map { Int($0.value - 48) }
        guard let suppliedCheckDigit = digits.last else { return nil }
        let weightedSum = digits.dropLast().reversed().enumerated().reduce(into: 0) {
            sum, entry in
            sum += entry.element * (entry.offset.isMultiple(of: 2) ? 3 : 1)
        }
        let expectedCheckDigit = (10 - weightedSum % 10) % 10
        guard suppliedCheckDigit == expectedCheckDigit else { return nil }
        return String(repeating: "0", count: 14 - compact.count) + compact
    }

    private static func normalizedExactURL(
        _ url: URL,
        retailerID: String
    ) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let rawHost = components.host?.lowercased(),
              let canonicalHost = canonicalHost(rawHost, retailerID: retailerID)
        else {
            return nil
        }

        var path = components.percentEncodedPath
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        guard !path.isEmpty, path != "/", !isSearchPath(path, retailerID: retailerID) else {
            return nil
        }

        if retailerID == ShoppingRetailer.walmart.rawValue,
           let productID = walmartProductID(in: path) {
            path = "/ip/\(productID)"
        } else if retailerID == ShoppingRetailer.target.rawValue,
                  let productID = targetProductID(in: path) {
            path = "/p/-/A-\(productID)"
        }

        components.scheme = "https"
        components.host = canonicalHost
        components.fragment = nil
        components.percentEncodedPath = path
        if components.port == 443 {
            components.port = nil
        }

        let filteredQueryItems = (components.queryItems ?? []).filter {
            !isKnownNonidentityQueryName($0.name)
        }
        let names = filteredQueryItems.map { $0.name.lowercased() }
        components.queryItems = Set(names).count == names.count
            ? filteredQueryItems.sorted(by: stableQueryOrder)
            : filteredQueryItems
        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }

        return components.string
    }

    private static func canonicalHost(_ host: String, retailerID: String) -> String? {
        let allowedHosts: Set<String>
        let outputHost: String
        switch retailerID {
        case ShoppingRetailer.walmart.rawValue:
            allowedHosts = ["walmart.com", "www.walmart.com"]
            outputHost = "www.walmart.com"
        case ShoppingRetailer.target.rawValue:
            allowedHosts = ["target.com", "www.target.com"]
            outputHost = "www.target.com"
        case ShoppingRetailer.kroger.rawValue:
            allowedHosts = ["kroger.com", "www.kroger.com"]
            outputHost = "www.kroger.com"
        default:
            return nil
        }
        return allowedHosts.contains(host) ? outputHost : nil
    }

    private static func isSearchPath(_ path: String, retailerID: String) -> Bool {
        let parts = path.split(separator: "/").map { $0.lowercased() }
        guard let first = parts.first else { return true }
        if first == "search" || first == "search-results" { return true }
        if retailerID == ShoppingRetailer.target.rawValue, first == "s" { return true }
        return false
    }

    private static func walmartProductID(in path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.first?.lowercased() == "ip",
              let candidate = parts.last,
              candidate.unicodeScalars.allSatisfy(isASCIIDigit)
        else {
            return nil
        }
        return String(candidate)
    }

    private static func targetProductID(in path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.first?.lowercased() == "p",
              let candidate = parts.last,
              candidate.count > 2,
              String(candidate.prefix(2)).caseInsensitiveCompare("A-") == .orderedSame
        else {
            return nil
        }
        let suffix = candidate.dropFirst(2)
        return suffix.unicodeScalars.allSatisfy(isASCIIDigit) ? String(suffix) : nil
    }

    private static func isKnownNonidentityQueryName(_ rawName: String) -> Bool {
        let name = rawName.lowercased()
        return name.hasPrefix("utm_") || knownNonidentityQueryNames.contains(name)
    }

    private static let knownNonidentityQueryNames: Set<String> = [
        "affiliate", "athbdg", "athcpid", "athguid", "athieid", "athpgid",
        "athstid", "clkid", "dclid", "fbclid", "fulfillment", "gbraid", "gclid",
        "location", "mc_cid", "mc_eid", "msclkid", "store", "storeid", "wbraid"
    ]

    private static func stableQueryOrder(_ lhs: URLQueryItem, _ rhs: URLQueryItem) -> Bool {
        let lhsName = lhs.name.lowercased()
        let rhsName = rhs.name.lowercased()
        if lhsName != rhsName { return lhsName < rhsName }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        switch (lhs.value, rhs.value) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (lhsValue?, rhsValue?): return lhsValue < rhsValue
        }
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }
}

extension RetailerProductRecord {
    var exactProductIdentity: ExactProductIdentity? {
        ExactProductIdentity(product: self)
    }
}
