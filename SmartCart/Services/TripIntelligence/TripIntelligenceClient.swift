import Foundation

enum TripIntelligenceClientError: Error, Equatable {
    case invalidBaseURL
    case invalidHTTPResponse
    case rejected(statusCode: Int)
    case unsupportedSchemaVersion(String)
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
