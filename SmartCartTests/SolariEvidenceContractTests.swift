import Foundation
import XCTest
@testable import SmartCart

final class SolariEvidenceContractTests: XCTestCase {
    private let validationDate = Date(timeIntervalSince1970: 1_799_000_000)

    private var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "contracts/fixtures/v1/solari")
    }

    func testCanonicalRecordedFixtureAcceptsHistoricalTimestampAndWarnsNotLive() throws {
        let request = try decodeRequest()
        let result = try decodeResult()

        let validated = try SolariEvidenceValidator(now: validationDate).validate(result, for: request)

        XCTAssertEqual(validated.result.basket.observedSubtotal, decimal("12.79"))
        XCTAssertEqual(validated.result.observations.first?.observedAt, isoDate("2026-07-16T12:00:00Z"))
        XCTAssertTrue(validated.warnings.contains(where: { $0.contains("historical") && $0.contains("not live") }))
    }

    func testUnknownResultVersionFailsClosed() throws {
        let request = try decodeRequest()
        let result = try mutatedResult { $0["schemaVersion"] = "solari-shopping-research-result-v2" }

        XCTAssertThrowsError(try validator().validate(result, for: request)) { error in
            XCTAssertEqual(error as? SolariEvidenceContractError, .unknownSchemaVersion)
        }
    }

    func testUnsubmittedSourceURLFailsClosed() throws {
        let request = try decodeRequest()
        let result = try mutatedResult { object in
            var observations = object["observations"] as! [[String: Any]]
            observations[0]["sourceURL"] = "https://www.walmart.com/ip/not-submitted/999"
            object["observations"] = observations
        }

        XCTAssertThrowsError(try validator().validate(result, for: request)) { error in
            XCTAssertEqual(error as? SolariEvidenceContractError, .invalidObservationReference)
        }
    }

    func testLiveModeRejectsHistoricalStaleObservation() throws {
        let request = try mutatedRequest { object in
            object["executionMode"] = "live"
            object["submittedAt"] = "2026-12-31T23:58:00Z"
        }
        let result = try mutatedResult { object in
            object["executionMode"] = "live"
            object["completedAt"] = "2026-12-31T23:59:00Z"
            var observations = object["observations"] as! [[String: Any]]
            for index in observations.indices {
                observations[index]["collectionMethod"] = "solari-browser-controlled-demo"
            }
            object["observations"] = observations
        }
        let now = isoDate("2027-01-01T00:00:00Z")

        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(result, for: request)) { error in
            XCTAssertEqual(error as? SolariEvidenceContractError, .staleObservation)
        }
    }

    func testCompleteClaimWithMissingPriceLineFailsClosed() throws {
        let request = try decodeRequest()
        let result = try mutatedResult { object in
            var observations = object["observations"] as! [[String: Any]]
            observations[0]["visiblePrice"] = NSNull()
            observations[0]["currency"] = NSNull()
            object["observations"] = observations

            var decisions = object["decisions"] as! [[String: Any]]
            decisions[0]["lineTotal"] = NSNull()
            decisions[0]["currency"] = NSNull()
            object["decisions"] = decisions

            var basket = object["basket"] as! [String: Any]
            basket["observedSubtotal"] = 3.32
            basket["pricedLineCount"] = 2
            basket["missingPriceLineCount"] = 1
            object["basket"] = basket
        }

        XCTAssertThrowsError(try validator().validate(result, for: request)) { error in
            XCTAssertEqual(error as? SolariEvidenceContractError, .incompleteBasketClaim)
        }
    }

    func testInconsistentLinePriceFailsClosed() throws {
        let request = try decodeRequest()
        let result = try mutatedResult { object in
            var decisions = object["decisions"] as! [[String: Any]]
            decisions[0]["lineTotal"] = 10.00
            object["decisions"] = decisions
        }

        XCTAssertThrowsError(try validator().validate(result, for: request)) { error in
            XCTAssertEqual(error as? SolariEvidenceContractError, .invalidPriceMath)
        }
    }

    func testExactDemoPlanBuildsBoundedCredentialFreeRequest() throws {
        let request = try XCTUnwrap(
            SolariResearchRequestBuilder.makeIfEligible(
                items: demoItems(),
                retailer: .walmart,
                executionMode: .recordedFixture,
                now: validationDate
            )
        )
        let encoded = try SolariRetailerResearchClient.encoder.encode(request)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8)).lowercased()

        XCTAssertEqual(request.requirements.count, 3)
        XCTAssertEqual(Set(request.requirements.flatMap(\.candidates).map(\.retailerProductID)), Set([
            "10414680", "10534084", "623835750", "10452414", "10307238", "47088917"
        ]))
        XCTAssertFalse(text.contains("cookie"))
        XCTAssertFalse(text.contains("credential"))
        XCTAssertFalse(text.contains("account"))
        XCTAssertFalse(text.contains("session"))
        XCTAssertFalse(text.contains("pantry"))
    }

    func testNonDemoWalmartPlanUsesNormalSmartCartPath() {
        var items = demoItems()
        items.removeLast()

        XCTAssertNil(
            SolariResearchRequestBuilder.makeIfEligible(
                items: items,
                retailer: .walmart,
                executionMode: .recordedFixture,
                now: validationDate
            )
        )
    }

    func testBackendConfigurationRejectsCredentialsAndInsecureRemoteHTTP() {
        XCTAssertNil(SolariBackendConfiguration(rawValue: "https://user:secret@example.com"))
        XCTAssertNil(SolariBackendConfiguration(rawValue: "http://example.com"))
        XCTAssertNil(SolariBackendConfiguration(rawValue: ""))
    }

    private func validator() -> SolariEvidenceValidator {
        SolariEvidenceValidator(now: validationDate)
    }

    private func decodeRequest() throws -> SolariResearchRequest {
        try SolariRetailerResearchClient.decoder.decode(
            SolariResearchRequest.self,
            from: Data(contentsOf: fixtureRoot.appending(path: "chicken-parmesan-walmart-request.json"))
        )
    }

    private func decodeResult() throws -> SolariResearchResult {
        try SolariRetailerResearchClient.decoder.decode(
            SolariResearchResult.self,
            from: Data(contentsOf: fixtureRoot.appending(path: "chicken-parmesan-walmart-result.json"))
        )
    }

    private func mutatedRequest(
        _ mutation: (inout [String: Any]) -> Void
    ) throws -> SolariResearchRequest {
        var object = try jsonObject("chicken-parmesan-walmart-request.json")
        mutation(&object)
        return try SolariRetailerResearchClient.decoder.decode(
            SolariResearchRequest.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func mutatedResult(
        _ mutation: (inout [String: Any]) -> Void
    ) throws -> SolariResearchResult {
        var object = try jsonObject("chicken-parmesan-walmart-result.json")
        mutation(&object)
        return try SolariRetailerResearchClient.decoder.decode(
            SolariResearchResult.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func jsonObject(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: fixtureRoot.appending(path: name))
            ) as? [String: Any]
        )
    }

    private func demoItems() -> [ShoppingListItem] {
        let storeID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
        return [
            item(
                name: "Boneless skinless chicken breast",
                amount: 1.5,
                unit: "lb",
                selected: product(id: "10414680", packageQuantity: 3, packageUnit: "lb"),
                alternatives: [],
                storeID: storeID
            ),
            item(
                name: "Penne pasta",
                amount: 12,
                unit: "oz",
                selected: product(id: "10534084", packageQuantity: 16, packageUnit: "oz"),
                alternatives: [product(id: "623835750", packageQuantity: 24, packageUnit: "oz")],
                storeID: storeID
            ),
            item(
                name: "Finely shredded Parmesan",
                amount: 3,
                unit: "oz",
                selected: product(id: "10452414", packageQuantity: 6, packageUnit: "oz"),
                alternatives: [
                    product(id: "10307238", packageQuantity: 5, packageUnit: "oz"),
                    product(id: "47088917", packageQuantity: 6, packageUnit: "oz")
                ],
                storeID: storeID
            )
        ]
    }

    private func item(
        name: String,
        amount: Double,
        unit: String,
        selected: RetailerProductRecord,
        alternatives: [RetailerProductRecord],
        storeID: UUID
    ) -> ShoppingListItem {
        ShoppingListItem(
            ingredient: Ingredient(name: name, quantity: amount, unit: unit),
            requestedQuantity: "\(amount.formatted()) \(unit)",
            requestedAmount: amount,
            purchaseQuantity: 1,
            product: selected,
            alternatives: alternatives,
            storeID: storeID,
            matchScore: 1
        )
    }

    private func product(
        id: String,
        packageQuantity: Double,
        packageUnit: String
    ) -> RetailerProductRecord {
        RetailerProductRecord(
            retailerID: ShoppingRetailer.walmart.rawValue,
            storeID: nil,
            retailerProductID: id,
            title: "Fixture \(id)",
            brand: "Fixture",
            exactURL: URL(string: "https://www.walmart.com/ip/\(id)")!,
            packageDescription: "\(packageQuantity) \(packageUnit)",
            packageQuantity: packageQuantity,
            packageUnit: packageUnit,
            observedPrice: 1,
            unitPriceText: "$1",
            priceType: .exact,
            availability: .unknown,
            fulfillmentMethods: [],
            organicStatus: .unknown,
            dataSource: .demoSeed,
            observedAt: validationDate,
            symbol: "basket",
            confidence: .high,
            matchKeywords: []
        )
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
