import Foundation
import XCTest
@testable import SmartCart

final class RecipeLinkCapabilityTests: XCTestCase {
    #if DEBUG
    func testCurrentBuildModeReflectsDebugTestConfiguration() {
        XCTAssertEqual(RecipePageBackendBuildMode.current, .debug)
    }
    #endif

    func testDebugAllowsExplicitLocalDevelopmentEndpoint() throws {
        let configuration = try RecipePageBackendConfiguration.resolve(
            environment: ["SMARTCART_RECIPE_BACKEND_URL": "http://localhost:8787"],
            bundleInfo: [RecipePageBackendConfiguration.bundleKey: "https://recipes.smartcart.app"],
            buildMode: .debug
        ).get()

        XCTAssertEqual(configuration.source, .debugEnvironment)
        XCTAssertEqual(configuration.baseURL.host, "localhost")
        XCTAssertEqual(configuration.baseURL.port, 8787)
    }

    func testReleaseUsesSignedBundleAndIgnoresEnvironment() throws {
        let configuration = try RecipePageBackendConfiguration.resolve(
            environment: ["SMARTCART_RECIPE_BACKEND_URL": "http://localhost:8787"],
            bundleInfo: [RecipePageBackendConfiguration.bundleKey: "https://recipes.smartcart.app/service"],
            buildMode: .release
        ).get()

        XCTAssertEqual(configuration.source, .bundle)
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://recipes.smartcart.app/service")
    }

    func testReleaseMissingConfigurationIsUnavailable() {
        assertFailure(
            RecipePageBackendConfiguration.resolve(
                environment: ["SMARTCART_RECIPE_BACKEND_URL": "https://environment.smartcart.app"],
                bundleInfo: [:],
                buildMode: .release
            ),
            equals: .missing
        )
    }

    func testReleaseAcceptsPublicHTTPS() throws {
        for value in ["https://recipes.smartcart.app", "https://api.smartcart.app:443/v1", "https://8.8.8.8"] {
            let configuration = try RecipePageBackendConfiguration.resolve(
                environment: [:],
                bundleInfo: [RecipePageBackendConfiguration.bundleKey: value],
                buildMode: .release
            ).get()
            XCTAssertEqual(configuration.baseURL.absoluteString, value)
        }
    }

    func testReleaseRejectsHTTP() {
        assertFailure(
            RecipePageBackendConfiguration.resolve(
                environment: [:],
                bundleInfo: [RecipePageBackendConfiguration.bundleKey: "http://recipes.smartcart.app"],
                buildMode: .release
            ),
            equals: .insecureReleaseURL
        )
    }

    func testReleaseRejectsLoopbackPrivateAndReservedHosts() {
        let rejected = [
            "https://localhost:8787", "https://extractor.local", "https://127.0.0.1",
            "https://10.1.2.3", "https://100.64.0.1", "https://169.254.1.1",
            "https://172.16.0.1", "https://172.31.255.255", "https://192.168.1.1",
            "https://198.18.0.1", "https://192.0.2.1", "https://198.51.100.1",
            "https://203.0.113.1", "https://224.0.0.1", "https://[::1]",
            "https://[fd00::1]", "https://[fe80::1]", "https://[fec0::1]",
            "https://[ff02::1]", "https://[2001:db8::1]", "https://[::ffff:127.0.0.1]",
            "https://example.com", "https://recipes.example.net", "https://recipes.test"
        ]

        for value in rejected {
            assertFailure(
                RecipePageBackendConfiguration.resolve(
                    environment: [:],
                    bundleInfo: [RecipePageBackendConfiguration.bundleKey: value],
                    buildMode: .release
                ),
                equals: .disallowedReleaseHost,
                message: value
            )
        }
    }

    func testMalformedEndpointsAreRejected() {
        for value in [
            "not a url", "ftp://recipes.smartcart.app", "https:///missing-host",
            "https://user:password@recipes.smartcart.app",
            "https://recipes.smartcart.app?token=secret",
            "https://recipes.smartcart.app#fragment"
        ] {
            assertFailure(
                RecipePageBackendConfiguration.resolve(
                    environment: [:],
                    bundleInfo: [RecipePageBackendConfiguration.bundleKey: value],
                    buildMode: .release
                ),
                equals: .invalidURL,
                message: value
            )
        }
    }

    func testUnavailableCapabilityOffersOnlySupportedAlternatives() {
        let capability = RecipeLinkCapability.resolve(
            environment: [:],
            bundleInfo: [:],
            buildMode: .release
        )

        XCTAssertEqual(capability, .unavailable(.missing))
        XCTAssertFalse(capability.isAvailable)
        XCTAssertTrue(capability.fallbackMessage.contains("Import photos"))
        XCTAssertTrue(capability.fallbackMessage.contains("paste the ingredient list"))
        XCTAssertFalse(capability.fallbackMessage.localizedCaseInsensitiveContains("localhost"))
        XCTAssertFalse(capability.fallbackMessage.localizedCaseInsensitiveContains("backend"))
    }

    func testUnavailableConfigurationPerformsNoNetworkRequest() async throws {
        RequestCountingURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCountingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = RecipePageBackendClient(
            session: session,
            environment: [:],
            bundleInfo: [:],
            buildMode: .release
        )

        do {
            _ = try await RecipeLinkImporter.importRecipe(
                from: try XCTUnwrap(URL(string: "https://recipes.example.org/dinner")),
                source: .link,
                client: client
            )
            XCTFail("Unavailable configuration must fail before networking")
        } catch {
            XCTAssertEqual(error.localizedDescription, RecipeLinkCapability.unavailable(.missing).fallbackMessage)
        }
        XCTAssertEqual(RequestCountingURLProtocol.requestCount, 0)
    }

    private func assertFailure(
        _ result: Result<RecipePageBackendConfiguration, RecipePageBackendConfigurationError>,
        equals expected: RecipePageBackendConfigurationError,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let error) = result else {
            return XCTFail("Expected configuration failure. \(message)", file: file, line: line)
        }
        XCTAssertEqual(error, expected, message, file: file, line: line)
    }
}

private final class RequestCountingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storedRequestCount = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCount
    }

    static func reset() {
        lock.lock()
        storedRequestCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.storedRequestCount += 1
        Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }

    override func stopLoading() {}
}
