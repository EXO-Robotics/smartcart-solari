import Foundation
import XCTest
@testable import SmartCart

final class ShoppingResolutionServiceTests: XCTestCase {
    func testZeroCandidatesBecomesUnresolvedWithoutDroppingOrReorderingIngredients() {
        let first = makeIngredient(id: uuid(1), name: "Fresh basil")
        let second = makeIngredient(id: uuid(2), name: "Olive oil")
        let exact = ranked(makeProduct(id: uuid(20), retailerProductID: "olive-oil"))

        let resolutions = ShoppingResolutionService.resolve([
            IngredientMatchingInput(ingredient: first, outcome: .ranked([])),
            IngredientMatchingInput(ingredient: second, outcome: .ranked([exact]))
        ])

        XCTAssertEqual(resolutions.map(\.id), [first.id, second.id])
        XCTAssertEqual(resolutions.count, 2)
        XCTAssertEqual(resolutions[0].resolution, .unresolved(.noCandidates))
        XCTAssertEqual(resolutions[1].resolution, .exactProduct(exact.product))
    }

    func testTypedProviderFailureIsPreserved() {
        let ingredient = makeIngredient(id: uuid(3), name: "Gluten-free pasta")

        let resolution = ShoppingResolutionService.resolve(
            IngredientMatchingInput(
                ingredient: ingredient,
                outcome: .failed(.transientProviderFailure)
            )
        )

        XCTAssertEqual(resolution.id, ingredient.id)
        XCTAssertEqual(resolution.resolution, .unresolved(.transientProviderFailure))
    }

    func testSearchFallbackIsLabeledAndNeverBecomesExactProduct() {
        let ingredient = makeIngredient(id: uuid(4), name: "Saffron")
        let fallback = makeProduct(
            id: uuid(40),
            retailerProductID: "search:saffron",
            dataSource: .searchFallback,
            linkKind: .searchResults,
            url: "https://www.walmart.com/search?q=saffron"
        )

        let resolution = ShoppingResolutionService.resolve(
            IngredientMatchingInput(
                ingredient: ingredient,
                outcome: .ranked([ranked(fallback)])
            )
        )

        XCTAssertEqual(resolution.resolution, .searchFallback(fallback))
        if case .exactProduct = resolution.resolution {
            XCTFail("A search fallback must not become an exact product")
        }
    }

    func testExactProductRetainsRankedSelectionProvenance() {
        let ingredient = makeIngredient(id: uuid(5), name: "Cream cheese")
        let exact = makeProduct(id: uuid(50), retailerProductID: "cream-cheese-8oz")
        let alternative = makeProduct(id: uuid(51), retailerProductID: "cream-cheese-12oz")

        let resolution = ShoppingResolutionService.resolve(
            IngredientMatchingInput(
                ingredient: ingredient,
                outcome: .ranked([
                    ranked(exact, score: 0.94, reasons: ["Exact ingredient match"]),
                    ranked(alternative, score: 0.81)
                ])
            )
        )

        XCTAssertEqual(resolution.resolution, .exactProduct(exact))
        XCTAssertEqual(resolution.matchScore, 0.94)
        XCTAssertEqual(resolution.selectionReasons, ["Exact ingredient match"])
        XCTAssertEqual(resolution.alternatives, [alternative])
    }

    func testInvalidTopRankNeverStrandsValidLowerRankedProduct() {
        let ingredient = makeIngredient(id: uuid(52), name: "Cream cheese")
        let invalid = makeProduct(
            id: uuid(53),
            retailerProductID: "",
            url: "http://invalid.example/product"
        )
        let valid = makeProduct(id: uuid(54), retailerProductID: "valid-cream-cheese")

        let resolution = ShoppingResolutionService.resolve(
            IngredientMatchingInput(
                ingredient: ingredient,
                outcome: .ranked([
                    ranked(invalid, score: 0.99),
                    ranked(valid, score: 0.91, reasons: ["Verified candidate"])
                ])
            )
        )

        XCTAssertEqual(resolution.resolution, .exactProduct(valid))
        XCTAssertEqual(resolution.matchScore, 0.91)
        XCTAssertEqual(resolution.selectionReasons, ["Verified candidate"])
    }

    func testExplicitExclusionIsCompleteAndDoesNotRequireAProduct() {
        let ingredient = makeIngredient(id: uuid(6), name: "Optional parsley")
        let resolution = ShoppingResolutionService.resolve(
            IngredientMatchingInput(
                ingredient: ingredient,
                outcome: .explicitlyExcluded
            )
        )

        let validation = ShoppingResolutionService.validate(
            includedIngredients: [ingredient],
            resolutions: [resolution]
        )

        XCTAssertEqual(resolution.resolution, .userExcluded)
        XCTAssertTrue(validation.hasExactlyOneResolutionPerIngredient)
        XCTAssertTrue(validation.canStartShoppingTrip)
    }

    func testValidationDetectsDuplicateAndMissingResolutions() {
        let first = makeIngredient(id: uuid(7), name: "Milk")
        let second = makeIngredient(id: uuid(8), name: "Eggs")
        let firstResolution = IngredientResolution(
            ingredient: first,
            resolution: .userExcluded
        )

        let validation = ShoppingResolutionService.validate(
            includedIngredients: [first, second],
            resolutions: [firstResolution, firstResolution]
        )

        XCTAssertEqual(
            validation.issues,
            [
                .duplicate(ingredientID: first.id, count: 2),
                .missing(ingredientID: second.id)
            ]
        )
        XCTAssertFalse(validation.hasExactlyOneResolutionPerIngredient)
        XCTAssertFalse(validation.canStartShoppingTrip)
    }

    func testUnresolvedBlocksTripUntilIngredientIsExplicitlyExcluded() {
        let ingredient = makeIngredient(id: uuid(9), name: "Fresh truffles")
        let unresolved = IngredientResolution(
            ingredient: ingredient,
            resolution: .unresolved(.fallbackUnavailable)
        )

        let blocked = ShoppingResolutionService.validate(
            includedIngredients: [ingredient],
            resolutions: [unresolved]
        )

        XCTAssertTrue(blocked.hasExactlyOneResolutionPerIngredient)
        XCTAssertEqual(blocked.unresolvedIngredientIDs, [ingredient.id])
        XCTAssertFalse(blocked.canStartShoppingTrip)

        let excluded = IngredientResolution(
            ingredient: ingredient,
            resolution: .userExcluded
        )
        let unblocked = ShoppingResolutionService.validate(
            includedIngredients: [ingredient],
            resolutions: [excluded]
        )

        XCTAssertTrue(unblocked.unresolvedIngredientIDs.isEmpty)
        XCTAssertTrue(unblocked.canStartShoppingTrip)
    }

    func testValidationRejectsResolutionForUnexpectedIngredient() {
        let expected = makeIngredient(id: uuid(10), name: "Rice")
        let unexpected = makeIngredient(id: uuid(11), name: "Coffee")

        let validation = ShoppingResolutionService.validate(
            includedIngredients: [expected],
            resolutions: [
                IngredientResolution(ingredient: expected, resolution: .userExcluded),
                IngredientResolution(ingredient: unexpected, resolution: .userExcluded)
            ]
        )

        XCTAssertEqual(validation.issues, [.unexpected(ingredientID: unexpected.id)])
        XCTAssertFalse(validation.canStartShoppingTrip)
    }

    private func makeIngredient(id: UUID, name: String) -> Ingredient {
        Ingredient(id: id, name: name)
    }

    private func ranked(
        _ product: RetailerProductRecord,
        score: Double = 0.9,
        reasons: [String] = []
    ) -> RankedRetailerProduct {
        RankedRetailerProduct(product: product, score: score, reasons: reasons)
    }

    private func makeProduct(
        id: UUID,
        retailerProductID: String,
        dataSource: ProductDataSource = .demoSeed,
        linkKind: RetailerLinkKind = .exactProduct,
        url: String = "https://www.walmart.com/ip/test-product/123456789"
    ) -> RetailerProductRecord {
        RetailerProductRecord(
            id: id,
            retailerID: "walmart",
            storeID: "store-1",
            retailerProductID: retailerProductID,
            title: "Test Product",
            brand: "Test Brand",
            exactURL: URL(string: url) ?? URL(fileURLWithPath: "/invalid-test-url"),
            packageDescription: "8 oz",
            packageQuantity: 8,
            packageUnit: "oz",
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

    private func uuid(_ suffix: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, suffix))
    }
}
