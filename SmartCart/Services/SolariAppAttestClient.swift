import CryptoKit
import DeviceCheck
import Foundation

enum SolariAppAttestError: LocalizedError, Equatable {
    case unsupported
    case invalidKeyIdentifier
    case invalidChallenge
    case invalidResponse
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "This device cannot provide Apple App Attest, so Solari research stays unavailable. Normal SmartCart shopping is unchanged."
        case .invalidKeyIdentifier:
            "Apple App Attest returned an invalid device key identifier."
        case .invalidChallenge:
            "The Solari backend returned an invalid or expired App Attest challenge."
        case .invalidResponse:
            "The Solari backend returned an unreadable App Attest response."
        case .server(let statusCode):
            "App-verified SmartCart access is unavailable (HTTP \(statusCode))."
        }
    }
}

protocol SolariAppAttestServicing: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

struct SystemSolariAppAttestService: SolariAppAttestServicing, @unchecked Sendable {
    private let service = DCAppAttestService.shared

    var isSupported: Bool { service.isSupported }

    func generateKey() async throws -> String {
        try await service.generateKey()
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await service.attestKey(keyID, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await service.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}

actor SolariAppAttestClient: SolariResearchAuthorizing {
    static let shared = SolariAppAttestClient()

    private static let keyIdentifierDefaultsKey = "smartcart.solari.app-attest.key-id.v1"
    private static let acceptedDefaultsKey = "smartcart.solari.app-attest.accepted.v1"
    private let service: any SolariAppAttestServicing
    private let session: URLSession
    private let defaults: UserDefaults

    init(
        service: any SolariAppAttestServicing = SystemSolariAppAttestService(),
        session: URLSession? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.session = session ?? Self.ephemeralSession()
        self.defaults = defaults
    }

    func authorization(
        forExactResearchBody body: Data,
        configuration: SolariBackendConfiguration
    ) async throws -> SolariAppAttestAuthorization {
        guard service.isSupported else { throw SolariAppAttestError.unsupported }
        let keyID = try await admittedKeyID(configuration: configuration)
        let challenge: AdmittedChallenge
        do {
            challenge = try await fetchChallenge(operation: .research, keyID: keyID, configuration: configuration)
        } catch SolariAppAttestError.server(let statusCode) where statusCode == 401 || statusCode == 403 {
            // The verifier may have deliberately evicted its admitted-key state.
            // Never bypass it: clear only the public key identifier so the next
            // explicit user retry performs a fresh Apple attestation.
            clearPersistedKey()
            throw SolariAppAttestError.server(statusCode: statusCode)
        }
        let hash = Self.assertionClientDataHash(
            challengeBase64URL: challenge.base64URL,
            exactResearchBody: body,
            researchPath: configuration.researchEndpoint.path
        )
        let assertion = try await service.generateAssertion(keyID, clientDataHash: hash)
        guard !assertion.isEmpty else { throw SolariAppAttestError.invalidResponse }
        return SolariAppAttestAuthorization(keyID: keyID, challengeID: challenge.id, assertion: assertion)
    }

    func authorizationWasRejected(statusCode: Int) async {
        guard statusCode == 401 || statusCode == 403 else { return }
        clearPersistedKey()
    }

    static func attestationClientDataHash(challenge: Data) -> Data {
        Data(SHA256.hash(data: challenge))
    }

    static func assertionClientDataHash(
        challengeBase64URL: String,
        exactResearchBody: Data,
        researchPath: String = "/v1/solari/research"
    ) -> Data {
        let bodyDigest = Data(SHA256.hash(data: exactResearchBody))
        let bodyDigestBase64URL = base64URLEncode(bodyDigest)
        let binding = "smartcart-app-attest-v1\n\(challengeBase64URL)\nPOST\n\(researchPath)\n\(bodyDigestBase64URL)\n"
        return Data(SHA256.hash(data: Data(binding.utf8)))
    }

    private func admittedKeyID(configuration: SolariBackendConfiguration) async throws -> String {
        if let persisted = defaults.string(forKey: Self.keyIdentifierDefaultsKey),
           Self.isValidKeyID(persisted),
           defaults.bool(forKey: Self.acceptedDefaultsKey) {
            return persisted
        }
        clearPersistedKey()
        let keyID = try await service.generateKey()
        guard Self.isValidKeyID(keyID) else { throw SolariAppAttestError.invalidKeyIdentifier }
        defaults.set(keyID, forKey: Self.keyIdentifierDefaultsKey)
        let challenge = try await fetchChallenge(operation: .attest, keyID: keyID, configuration: configuration)
        let attestation = try await service.attestKey(
            keyID,
            clientDataHash: Self.attestationClientDataHash(challenge: challenge.bytes)
        )
        guard !attestation.isEmpty else { throw SolariAppAttestError.invalidResponse }
        let result = try await submitAttestation(
            keyID: keyID,
            challengeID: challenge.id,
            attestation: attestation,
            configuration: configuration
        )
        guard result.keyID == keyID, result.status == .accepted else {
            clearPersistedKey()
            throw SolariAppAttestError.invalidResponse
        }
        defaults.set(true, forKey: Self.acceptedDefaultsKey)
        return keyID
    }

    private func clearPersistedKey() {
        defaults.removeObject(forKey: Self.keyIdentifierDefaultsKey)
        defaults.removeObject(forKey: Self.acceptedDefaultsKey)
    }

    private func fetchChallenge(
        operation: ChallengeOperation,
        keyID: String,
        configuration: SolariBackendConfiguration
    ) async throws -> AdmittedChallenge {
        let contract = ChallengeRequest(
            schemaVersion: "solari-app-attest-challenge-request-v1",
            operation: operation,
            keyID: keyID
        )
        let data = try await post(contract, to: configuration.challengeEndpoint, expectedStatus: 201)
        let result: ChallengeResult
        do { result = try Self.decoder.decode(ChallengeResult.self, from: data) }
        catch { throw SolariAppAttestError.invalidResponse }
        guard result.schemaVersion == "solari-app-attest-challenge-result-v1",
              result.expiresAt > Date(),
              result.expiresAt <= Date().addingTimeInterval(10 * 60),
              let bytes = Self.base64URLDecode(result.challenge),
              bytes.count == 32 else { throw SolariAppAttestError.invalidChallenge }
        return AdmittedChallenge(id: result.challengeID, base64URL: result.challenge, bytes: bytes)
    }

    private func submitAttestation(
        keyID: String,
        challengeID: UUID,
        attestation: Data,
        configuration: SolariBackendConfiguration
    ) async throws -> AttestationResult {
        let contract = AttestationRequest(
            schemaVersion: "solari-app-attestation-request-v1",
            challengeID: challengeID,
            keyID: keyID,
            attestationObject: attestation.base64EncodedString()
        )
        let data = try await post(contract, to: configuration.attestationEndpoint, expectedStatus: 201)
        let result: AttestationResult
        do { result = try Self.decoder.decode(AttestationResult.self, from: data) }
        catch { throw SolariAppAttestError.invalidResponse }
        guard result.schemaVersion == "solari-app-attestation-result-v1" else {
            throw SolariAppAttestError.invalidResponse
        }
        return result
    }

    private func post<Body: Encodable>(_ body: Body, to endpoint: URL, expectedStatus: Int) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try Self.encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SolariAppAttestError.invalidResponse }
        guard response.statusCode == expectedStatus else { throw SolariAppAttestError.server(statusCode: response.statusCode) }
        guard data.count <= 32 * 1_024 else { throw SolariAppAttestError.invalidResponse }
        return data
    }

    static func isValidKeyID(_ value: String) -> Bool {
        guard value.count <= 256,
              let decoded = Data(base64Encoded: value),
              (32...128).contains(decoded.count) else { return false }
        // The wire contract uses standard padded Base64, not Base64URL.
        return decoded.base64EncodedString() == value
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        guard value.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }) else { return nil }
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func base64URLEncode(_ value: Data) -> String {
        value.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = SolariRetailerResearchClient.decoder.dateDecodingStrategy
        return decoder
    }()

    private static func ephemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

private extension SolariAppAttestClient {
    enum ChallengeOperation: String, Codable { case attest; case research }

    struct ChallengeRequest: Codable {
        let schemaVersion: String
        let operation: ChallengeOperation
        let keyID: String
    }

    struct ChallengeResult: Codable {
        let schemaVersion: String
        let challengeID: UUID
        let challenge: String
        let expiresAt: Date
    }

    struct AdmittedChallenge {
        let id: UUID
        let base64URL: String
        let bytes: Data
    }

    struct AttestationRequest: Codable {
        let schemaVersion: String
        let challengeID: UUID
        let keyID: String
        let attestationObject: String
    }

    enum AttestationStatus: String, Codable { case accepted }

    struct AttestationResult: Codable {
        let schemaVersion: String
        let keyID: String
        let status: AttestationStatus
    }
}
