import Foundation

enum TripIntelligenceClientError: Error, Equatable {
    case invalidBaseURL
    case invalidHTTPResponse
    case rejected(statusCode: Int)
    case unsupportedSchemaVersion(String)
}

enum SmartCartHandoffClientError: LocalizedError, Equatable {
    case invalidToken
    case invalidBaseURL
    case invalidHTTPResponse
    case unexpectedResponseURL
    case unexpectedRequestID
    case invalidContentType
    case responseTooLarge
    case rejected(statusCode: Int)
    case unsupportedSchemaVersion(String)

    var errorDescription: String? {
        switch self {
        case .rejected(let statusCode) where statusCode == 410:
            "This SmartCart plan has expired. Ask ChatGPT to create a new link."
        default:
            "SmartCart could not open this plan. Check your connection and try the link again."
        }
    }
}

private final class SmartCartHandoffRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct SmartCartHandoffClient: Sendable {
    static let maximumResponseBytes = 512 * 1_024

    let baseURL: URL
    let session: URLSession
    private let ownsSession: Bool

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
            ownsSession = false
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(
                configuration: configuration,
                delegate: SmartCartHandoffRedirectDelegate(),
                delegateQueue: nil
            )
            ownsSession = true
        }
    }

    func claim(
        token: String,
        requestID: UUID
    ) async throws -> SmartCartHandoffPayloadDTO {
        defer {
            if ownsSession {
                session.invalidateAndCancel()
            }
        }
        guard SmartCartHandoffURLParser.isValidToken(token) else {
            throw SmartCartHandoffClientError.invalidToken
        }
        guard let endpoint = claimEndpoint else {
            throw SmartCartHandoffClientError.invalidBaseURL
        }

        let envelope = TripIntelligenceRequestEnvelopeDTO(
            requestId: requestID,
            data: SmartCartHandoffClaimRequestDataDTO(claimToken: token)
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Request-ID")
        request.httpBody = try JSONEncoder().encode(envelope)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SmartCartHandoffClientError.invalidHTTPResponse
        }
        guard response.url == endpoint else {
            throw SmartCartHandoffClientError.unexpectedResponseURL
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SmartCartHandoffClientError.rejected(statusCode: response.statusCode)
        }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard contentType == "application/json" else {
            throw SmartCartHandoffClientError.invalidContentType
        }
        let declaredLength = response.value(forHTTPHeaderField: "Content-Length")
            .flatMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if response.expectedContentLength > Int64(Self.maximumResponseBytes) ||
            (declaredLength.map { $0 > Int64(Self.maximumResponseBytes) } == true) {
            throw SmartCartHandoffClientError.responseTooLarge
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw SmartCartHandoffClientError.responseTooLarge
        }

        let result = try JSONDecoder().decode(SmartCartHandoffPayloadDTO.self, from: data)
        guard result.schemaVersion == TripIntelligenceSchema.version else {
            throw SmartCartHandoffClientError.unsupportedSchemaVersion(result.schemaVersion)
        }
        guard result.requestId == requestID else {
            throw SmartCartHandoffClientError.unexpectedRequestID
        }
        return result
    }

    private var claimEndpoint: URL? {
        guard baseURL.scheme?.lowercased() == "https",
              let host = baseURL.host,
              !host.isEmpty,
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.port == nil,
              baseURL.query == nil,
              baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/" else { return nil }
        return baseURL
            .appending(path: "v1")
            .appending(path: "handoffs")
            .appending(path: "claim")
    }
}

struct TripIntelligenceClient: Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func estimateRecipeNutrition(
        _ request: TripIntelligenceRequestEnvelopeDTO<RecipeNutritionRequestDataDTO>
    ) async throws -> TripIntelligenceEnvelopeDTO<RecipeNutritionEstimateDTO> {
        guard let endpoint = URL(
            string: "v1/intelligence/nutrition/recipes/estimate",
            relativeTo: baseURL
        )?.absoluteURL else {
            throw TripIntelligenceClientError.invalidBaseURL
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(request.requestId.uuidString, forHTTPHeaderField: "X-Request-ID")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let response = response as? HTTPURLResponse else {
            throw TripIntelligenceClientError.invalidHTTPResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw TripIntelligenceClientError.rejected(statusCode: response.statusCode)
        }

        let result = try JSONDecoder().decode(
            TripIntelligenceEnvelopeDTO<RecipeNutritionEstimateDTO>.self,
            from: data
        )
        guard result.schemaVersion == TripIntelligenceSchema.version else {
            throw TripIntelligenceClientError.unsupportedSchemaVersion(result.schemaVersion)
        }
        return result
    }
}
