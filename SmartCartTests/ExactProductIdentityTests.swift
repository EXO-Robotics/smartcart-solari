import Foundation
import XCTest
@testable import SmartCart

final class ExactProductIdentityTests: XCTestCase {
    func testRetailerProductIDHasPrecedenceOverGTINAndURL() throws {
        let product = makeProduct(
            retailerProductID: "  A-12345678  ",
            gtin: "036000291452",
            retailerID: " TARGET ",
            url: "https://www.target.com/p/different/-/A-99999999"
        )

        let identity = try XCTUnwrap(product.exactProductIdentity)

        XCTAssertEqual(identity.retailerID, "target")
        XCTAssertEqual(identity.kind, .retailerProductID)
        XCTAssertEqual(identity.normalizedValue, "12345678")
        XCTAssertEqual(identity.normalizationVersion, ExactProductIdentity.currentNormalizationVersion)
    }

    func testCanonicalGTINUsesOnlySupportedChecksumValidLengths() throws {
        let upc = makeProduct(
            retailerProductID: "",
            gtin: "0360-0029 1452",
            url: "https://www.walmart.com/ip/upc/1"
        )
        let gtin14 = makeProduct(
            retailerProductID: "",
            gtin: "00036000291452",
            url: "https://www.walmart.com/ip/gtin/2"
        )

        let first = try XCTUnwrap(upc.exactProductIdentity)
        let second = try XCTUnwrap(gtin14.exactProductIdentity)

        XCTAssertEqual(first.kind, .gtin)
        XCTAssertEqual(first.normalizedValue, "00036000291452")
        XCTAssertEqual(first, second)
    }

    func testMalformedAndNonnumericGTINsAreRejected() {
        for gtin in ["036000291453", "12345", "03600029X452", "000000000000000"] {
            let product = makeProduct(
                retailerProductID: "",
                gtin: gtin,
                url: "https://www.walmart.com/search?q=milk"
            )
            XCTAssertNil(product.exactProductIdentity, gtin)
        }
    }

    func testExactURLNormalizesHostPathAndTrailingSlash() throws {
        let verbose = makeProduct(
            retailerProductID: "",
            gtin: nil,
            url: "https://WALMART.com/ip/whole-milk/123456789/"
        )
        let canonical = makeProduct(
            retailerProductID: "",
            gtin: nil,
            url: "https://www.walmart.com/ip/123456789"
        )

        let first = try XCTUnwrap(verbose.exactProductIdentity)
        let second = try XCTUnwrap(canonical.exactProductIdentity)

        XCTAssertEqual(first.kind, .exactURL)
        XCTAssertEqual(first.normalizedValue, "https://www.walmart.com/ip/123456789")
        XCTAssertEqual(first, second)
    }

    func testTrackingAndStoreContextDoNotChangeExactURLIdentity() throws {
        let tracked = makeProduct(
            retailerProductID: "",
            gtin: nil,
            retailerID: "kroger",
            url: "https://www.kroger.com/p/whole-milk/0001111040101/?utm_source=mail&storeId=123&gclid=abc"
        )
        let clean = makeProduct(
            retailerProductID: "",
            gtin: nil,
            retailerID: "kroger",
            url: "https://kroger.com/p/whole-milk/0001111040101"
        )

        XCTAssertEqual(try XCTUnwrap(tracked.exactProductIdentity), try XCTUnwrap(clean.exactProductIdentity))
    }

    func testUnknownProductDefiningQueryIsPreservedConservatively() throws {
        let first = makeProduct(
            retailerProductID: "",
            gtin: nil,
            url: "https://www.walmart.com/ip/product/123456789?variant=original"
        )
        let second = makeProduct(
            retailerProductID: "",
            gtin: nil,
            url: "https://www.walmart.com/ip/product/123456789?variant=family-size"
        )

        XCTAssertNotEqual(try XCTUnwrap(first.exactProductIdentity), try XCTUnwrap(second.exactProductIdentity))
    }

    func testSearchAndKnownRetailerHostMismatchAreRejected() {
        let search = makeProduct(
            retailerProductID: "",
            gtin: nil,
            url: "https://www.walmart.com/search?q=rice",
            linkKind: .exactProduct
        )
        let mismatch = makeProduct(
            retailerProductID: "",
            gtin: nil,
            url: "https://www.target.com/p/rice/-/A-12345678"
        )

        XCTAssertNil(search.exactProductIdentity)
        XCTAssertNil(mismatch.exactProductIdentity)
    }

    func testSearchFallbackMetadataCanNeverProduceIdentity() {
        let fallback = makeProduct(
            retailerProductID: "123456789",
            gtin: "036000291452",
            url: "https://www.walmart.com/ip/123456789",
            dataSource: .searchFallback,
            linkKind: .searchResults
        )

        XCTAssertNil(fallback.exactProductIdentity)
    }

    func testDifferentExactProductPathsRemainDifferent() throws {
        let first = makeProduct(
            retailerProductID: "",
            gtin: nil,
            retailerID: "kroger",
            url: "https://www.kroger.com/p/whole-milk/0001111040101"
        )
        let second = makeProduct(
            retailerProductID: "",
            gtin: nil,
            retailerID: "kroger",
            url: "https://www.kroger.com/p/whole-milk/0001111040102"
        )

        XCTAssertNotEqual(try XCTUnwrap(first.exactProductIdentity), try XCTUnwrap(second.exactProductIdentity))
    }

    func testNormalizationVersionRoundTripsAndParticipatesInEquality() throws {
        let current = try XCTUnwrap(ExactProductIdentity(
            retailerID: "walmart",
            kind: .retailerProductID,
            normalizedValue: "123"
        ))
        let old = try XCTUnwrap(ExactProductIdentity(
            retailerID: "walmart",
            kind: .retailerProductID,
            normalizedValue: "123",
            normalizationVersion: 2
        ))

        let decoded = try JSONDecoder().decode(
            ExactProductIdentity.self,
            from: JSONEncoder().encode(old)
        )

        XCTAssertEqual(decoded.normalizationVersion, 2)
        XCTAssertEqual(decoded, old)
        XCTAssertNotEqual(decoded, current)
    }

    private func makeProduct(
        retailerProductID: String,
        gtin: String? = nil,
        retailerID: String = "walmart",
        url: String,
        dataSource: ProductDataSource = .retailerAPI,
        linkKind: RetailerLinkKind = .exactProduct
    ) -> RetailerProductRecord {
        RetailerProductRecord(
            retailerID: retailerID,
            storeID: "store-1",
            retailerProductID: retailerProductID,
            gtin: gtin,
            title: "Test Product",
            brand: "Test Brand",
            exactURL: URL(string: url) ?? URL(fileURLWithPath: "/invalid-test-url"),
            packageDescription: "1 package",
            unitPriceText: "Price unavailable",
            priceType: .unavailable,
            availability: .inStock,
            fulfillmentMethods: [.pickup],
            organicStatus: .unknown,
            dataSource: dataSource,
            observedAt: Date(timeIntervalSince1970: 0),
            linkKind: linkKind,
            symbol: "cart"
        )
    }
}
