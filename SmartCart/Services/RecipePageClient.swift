import Foundation
import Network

enum RecipePageBackendBuildMode: Hashable, Sendable {
    case debug
    case release

    static var current: Self {
        #if DEBUG
        .debug
        #else
        .release
        #endif
    }
}

enum RecipePageBackendConfigurationSource: Hashable, Sendable {
    case injected
    case debugEnvironment
    case bundle
}

enum RecipePageBackendConfigurationError: Error, Hashable, Sendable {
    case missing
    case invalidURL
    case insecureReleaseURL
    case disallowedReleaseHost
}

struct RecipePageBackendConfiguration: Hashable, Sendable {
    static let bundleKey = "SmartCartRecipeBackendURL"

    let baseURL: URL
    let source: RecipePageBackendConfigurationSource

    static func resolve(
        explicitURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        buildMode: RecipePageBackendBuildMode = .current
    ) -> Result<Self, RecipePageBackendConfigurationError> {
        if let explicitURL {
            return validated(explicitURL, source: .injected, buildMode: buildMode)
        }
        if buildMode == .debug,
           let value = environment["SMARTCART_RECIPE_BACKEND_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            guard let url = URL(string: value) else { return .failure(.invalidURL) }
            return validated(url, source: .debugEnvironment, buildMode: buildMode)
        }
        if let rawValue = bundleInfo[bundleKey] as? String {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, !value.contains("$("), let url = URL(string: value) {
                return validated(url, source: .bundle, buildMode: buildMode)
            }
            if !value.isEmpty, !value.contains("$(") { return .failure(.invalidURL) }
        }
        return .failure(.missing)
    }

    private static func validated(
        _ url: URL,
        source: RecipePageBackendConfigurationSource,
        buildMode: RecipePageBackendBuildMode
    ) -> Result<Self, RecipePageBackendConfigurationError> {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              scheme == "http" || scheme == "https" else {
            return .failure(.invalidURL)
        }
        if buildMode == .release {
            guard scheme == "https" else { return .failure(.insecureReleaseURL) }
            guard !isDisallowedReleaseHost(host) else {
                return .failure(.disallowedReleaseHost)
            }
        }
        return .success(Self(baseURL: url, source: source))
    }

    private static func isDisallowedReleaseHost(_ rawHost: String) -> Bool {
        var host = rawHost
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return true }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }
        if ["example", "example.com", "example.net", "example.org", "test", "invalid"]
            .contains(host) ||
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
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
                return isDisallowedIPv4(Array(bytes.suffix(4)))
            }
            if bytes[0] & 0xfe == 0xfc ||
                (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) ||
                (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0xc0) ||
                bytes[0] == 0xff || Array(bytes.prefix(4)) == [0x20, 0x01, 0x0d, 0xb8] {
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
                  isASCIIAlphaNumeric(first),
                  isASCIIAlphaNumeric(last) else { return false }
            return bytes.allSatisfy { isASCIIAlphaNumeric($0) || $0 == 45 }
        }
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }

    private static func isDisallowedIPv4(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else { return true }
        let first = octets[0]
        let second = octets[1]
        let third = octets[2]
        switch (first, second) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168),
             (172, 16...31), (100, 64...127), (198, 18...19):
            return true
        default:
            break
        }
        return first >= 224 ||
            (first == 192 && second == 0 && (third == 0 || third == 2)) ||
            (first == 198 && second == 51 && third == 100) ||
            (first == 203 && second == 0 && third == 113)
    }
}

enum RecipeLinkCapability: Hashable, Sendable {
    case available
    case unavailable(RecipePageBackendConfigurationError)

    static var current: Self { resolve() }

    static func resolve(
        explicitURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        buildMode: RecipePageBackendBuildMode = .current
    ) -> Self {
        switch RecipePageBackendConfiguration.resolve(
            explicitURL: explicitURL,
            environment: environment,
            bundleInfo: bundleInfo,
            buildMode: buildMode
        ) {
        case .success: .available
        case .failure(let error): .unavailable(error)
        }
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var fallbackMessage: String {
        "Recipe links aren’t available in this build. Import photos or paste the ingredient list instead."
    }
}

enum RecipeLinkImporter {
    static func importRecipe(
        from url: URL,
        source: RecipeSource,
        client: RecipePageBackendClient = RecipePageBackendClient()
    ) async throws -> Recipe {
        guard url.scheme?.lowercased() == "https" else {
            throw RecipePageClientError.invalidURL
        }

        let response = try await client.extract(url: url)
        let sectionedText = response.recipe.ingredientSections.flatMap { section -> [String] in
            guard let name = section.name, !name.isEmpty else { return section.ingredients }
            return ["\(name):"] + section.ingredients
        }
        let text = sectionedText.isEmpty
            ? response.recipe.ingredients.joined(separator: "\n")
            : sectionedText.joined(separator: "\n")

        var recipe = RecipeParser.parse(
            title: response.recipe.name,
            text: text,
            source: source,
            sourceDetail: "\(url.host ?? "Recipe page") → \(response.page.finalURL.host ?? "extracted page")"
        )
        for index in recipe.ingredients.indices {
            recipe.ingredients[index].sourceEvidence?.extractionStrategy = response.recipe.extractionMethod == "json-ld"
                ? .structuredData
                : .visiblePageText
        }
        return recipe
    }
}

struct RecipePageBackendClient {
    private let session: URLSession
    private let configuration: Result<RecipePageBackendConfiguration, RecipePageBackendConfigurationError>

    init(
        session: URLSession = .shared,
        baseURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        buildMode: RecipePageBackendBuildMode = .current
    ) {
        self.session = session
        configuration = RecipePageBackendConfiguration.resolve(
            explicitURL: baseURL,
            environment: environment,
            bundleInfo: bundleInfo,
            buildMode: buildMode
        )
    }

    func extract(url: URL) async throws -> RecipePageResponse {
        let baseURL: URL
        switch configuration {
        case .success(let configuration):
            baseURL = configuration.baseURL
        case .failure(let error):
            throw RecipePageClientError.configuration(error)
        }
        do {
            let account: AccountEnvelope = try await post(
                baseURL: baseURL,
                path: "/v1/demo/accounts",
                body: [
                    "displayName": "SmartCart Local Recipe Import",
                    "email": "recipe-\(UUID().uuidString.lowercased())@smartcart.local"
                ],
                bearerToken: nil
            )
            let sessionEnvelope: SessionEnvelope = try await post(
                baseURL: baseURL,
                path: "/v1/demo/sessions",
                body: ["accountId": account.account.id],
                bearerToken: nil
            )
            return try await post(
                baseURL: baseURL,
                path: "/v1/recipe-pages/extract",
                body: ["url": url.absoluteString],
                bearerToken: sessionEnvelope.session.token
            )
        } catch let error as RecipePageClientError {
            throw error
        } catch let error as URLError {
            if error.code == .timedOut { throw RecipePageClientError.timeout }
            throw RecipePageClientError.backendUnavailable
        } catch {
            throw RecipePageClientError.unreadableResponse
        }
    }

    private func post<Response: Decodable>(
        baseURL: URL,
        path: String,
        body: [String: String],
        bearerToken: String?
    ) async throws -> Response {
        let url = path.split(separator: "/").reduce(baseURL) {
            $0.appendingPathComponent(String($1))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 14
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SmartCart-iOS/0.4 recipe-import", forHTTPHeaderField: "User-Agent")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RecipePageClientError.unreadableResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw RecipePageClientError.server(
                code: envelope?.error.code ?? "http_\(http.statusCode)",
                message: envelope?.error.message ?? "The recipe service returned HTTP \(http.statusCode)."
            )
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw RecipePageClientError.unreadableResponse
        }
    }
}

private struct AccountEnvelope: Decodable {
    struct Account: Decodable { var id: String }
    var account: Account
}

private struct SessionEnvelope: Decodable {
    struct Session: Decodable { var token: String }
    var session: Session
}

struct RecipePageResponse: Decodable {
    struct Page: Decodable {
        var originalURL: URL
        var finalURL: URL

        enum CodingKeys: String, CodingKey {
            case originalURL = "originalUrl"
            case finalURL = "finalUrl"
        }
    }

    struct ExtractedRecipe: Decodable {
        struct Section: Decodable {
            var name: String?
            var ingredients: [String]
        }

        var name: String
        var ingredients: [String]
        var ingredientSections: [Section]
        var extractionMethod: String
    }

    var page: Page
    var recipe: ExtractedRecipe
}

private struct ErrorEnvelope: Decodable {
    struct ServerError: Decodable {
        var code: String
        var message: String
    }
    var error: ServerError
}

private enum RecipePageClientError: LocalizedError {
    case invalidURL
    case configuration(RecipePageBackendConfigurationError)
    case backendUnavailable
    case timeout
    case unreadableResponse
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Recipe links must begin with https://."
        case .configuration:
            RecipeLinkCapability.unavailable(.missing).fallbackMessage
        case .backendUnavailable:
            "The recipe page service could not be reached. Try again, import photos, or paste the ingredient list."
        case .timeout:
            "The recipe page took too long to answer. Try again or paste the ingredients."
        case .unreadableResponse:
            "The SmartCart recipe extractor returned an unreadable response."
        case .server(let code, let message):
            switch code {
            case "upstream_access_denied": "That recipe site denied access. Paste the ingredients or import a screenshot instead."
            case "recipe_not_found": "No ingredient list was found on that page. Paste the ingredients or import a screenshot instead."
            case "unsupported_mime": "That link did not return an HTML recipe page."
            case "page_too_large": "That page is too large for safe recipe import."
            default: message
            }
        }
    }
}
