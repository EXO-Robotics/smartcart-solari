import Foundation

enum RecipeLinkImporter {
    static func importRecipe(from url: URL, source: RecipeSource) async throws -> Recipe {
        guard url.scheme?.lowercased() == "https" else {
            throw RecipePageClientError.invalidURL
        }

        let client = RecipePageBackendClient()
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

private struct RecipePageBackendClient {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared) {
        self.session = session
        if let configured = ProcessInfo.processInfo.environment["SMARTCART_RECIPE_BACKEND_URL"],
           let url = URL(string: configured) {
            baseURL = url
        } else {
            baseURL = URL(string: "http://localhost:8787")!
        }
    }

    func extract(url: URL) async throws -> RecipePageResponse {
        do {
            let account: AccountEnvelope = try await post(
                path: "/v1/demo/accounts",
                body: [
                    "displayName": "SmartCart Local Recipe Import",
                    "email": "recipe-\(UUID().uuidString.lowercased())@smartcart.local"
                ],
                bearerToken: nil
            )
            let sessionEnvelope: SessionEnvelope = try await post(
                path: "/v1/demo/sessions",
                body: ["accountId": account.account.id],
                bearerToken: nil
            )
            return try await post(
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
        path: String,
        body: [String: String],
        bearerToken: String?
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw RecipePageClientError.backendUnavailable
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

private struct RecipePageResponse: Decodable {
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
    case backendUnavailable
    case timeout
    case unreadableResponse
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Recipe links must begin with https://."
        case .backendUnavailable:
            "The local SmartCart recipe extractor is not running. Start backend/ and try again, or paste the ingredients."
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
