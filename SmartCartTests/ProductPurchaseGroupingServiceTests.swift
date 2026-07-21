import Foundation
import XCTest
@testable import SmartCart

final class ProductPurchaseGroupingServiceTests: XCTestCase {
    func testSameRetailerProductIDProducesOneGroupWithTwoContributions() {
        let product = makeProduct(productID: "same-sku")
        let groups = ProductPurchaseGroupingService.group([
            candidate(line: 1, ingredient: 11, product: product),
            candidate(line: 2, ingredient: 12, product: product)
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.memberLineIDs, [uuid(1), uuid(2)])
        XCTAssertEqual(groups.first?.contributions.count, 2)
    }

    func testDifferentRetailerProductIDsAndRetailersDoNotGroup() {
        let first = makeProduct(productID: "sku-a", retailerID: "walmart")
        let second = makeProduct(productID: "sku-b", retailerID: "walmart")
        let third = makeProduct(productID: "sku-a", retailerID: "target")

        let groups = ProductPurchaseGroupingService.group([
            candidate(line: 1, ingredient: 11, product: first),
            candidate(line: 2, ingredient: 12, product: second),
            candidate(line: 3, ingredient: 13, product: third)
        ])

        XCTAssertEqual(groups.count, 3)
    }

    func testCanonicalGTINProducesOneGroup() throws {
        let upc = makeProduct(productID: "", gtin: "036000291452", pathID: "1")
        let gtin14 = makeProduct(productID: "", gtin: "00036000291452", pathID: "2")

        let groups = ProductPurchaseGroupingService.group([
            candidate(line: 1, ingredient: 11, product: upc),
            candidate(line: 2, ingredient: 12, product: gtin14)
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(try XCTUnwrap(groups.first?.exactProductIdentity).kind, .gtin)
    }

    func testSharedCanonicalGTINGroupsEvenWhenRetailerProductIDsDiffer() {
        let first = makeProduct(
            productID: "sku-a",
            gtin: "036000291452",
            pathID: "1"
        )
        let second = makeProduct(
            productID: "sku-b",
            gtin: "00036000291452",
            pathID: "2"
        )

        let groups = ProductPurchaseGroupingService.group([
            candidate(line: 1, ingredient: 11, product: first),
            candidate(line: 2, ingredient: 12, product: second)
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.contributions.count, 2)
        XCTAssertTrue(groups.first?.exactProductIdentityEvidence?.contains {
            $0.kind == .gtin && $0.normalizedValue == "00036000291452"
        } == true)
    }

    func testThreeRecipesPreserveOrderedProvenance() {
        let product = makeProduct(productID: "shared-sku")
        let groups = ProductPurchaseGroupingService.group([
            candidate(line: 1, ingredient: 11, recipe: 21, product: product, display: "1 cup"),
            candidate(line: 2, ingredient: 12, recipe: 22, product: product, display: "2 tbsp"),
            candidate(line: 3, ingredient: 13, recipe: 23, product: product, display: "3 tsp")
        ])

        XCTAssertEqual(groups.first?.contributions.map(\.sourceRecipeID), [uuid(21), uuid(22), uuid(23)])
        XCTAssertEqual(groups.first?.contributions.map(\.sourceIngredientID), [uuid(11), uuid(12), uuid(13)])
        XCTAssertEqual(groups.first?.contributions.map(\.originalDisplayQuantity), ["1 cup", "2 tbsp", "3 tsp"])
        XCTAssertTrue(groups.first?.contributions.allSatisfy { $0.selectedProductIdentity != nil } == true)
    }

    func testGroupOrderingIsFirstSeenAndDeterministic() {
        let productA = makeProduct(productID: "a")
        let productB = makeProduct(productID: "b")
        let input = [
            candidate(line: 1, ingredient: 11, product: productB),
            candidate(line: 2, ingredient: 12, product: productA),
            candidate(line: 3, ingredient: 13, product: productB)
        ]

        let first = ProductPurchaseGroupingService.group(input)
        let second = ProductPurchaseGroupingService.group(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.id), [uuid(1), uuid(2)])
        XCTAssertEqual(first.first?.memberLineIDs, [uuid(1), uuid(3)])
    }

    func testCompatibleMassQuantitiesSumAndPreservePantryDeductions() throws {
        let product = makeProduct(productID: "mass", packageQuantity: 100, packageUnit: "g")
        let fifty = try quantity(50, .mass)
        let hundred = try quantity(100, .mass)
        let pantry = try quantity(10, .mass)

        let groups = ProductPurchaseGroupingService.group([
            candidate(line: 1, ingredient: 11, product: product, canonical: fifty, pantry: pantry),
            candidate(line: 2, ingredient: 12, product: product, canonical: hundred)
        ])

        XCTAssertEqual(groups.first?.packagePlan?.requiredQuantity?.value, 150)
        XCTAssertEqual(groups.first?.packagePlan?.requiredQuantity?.dimension, .mass)
        XCTAssertEqual(groups.first?.contributions.first?.pantryDeduction, pantry)
        XCTAssertEqual(groups.first?.packagePlan?.packageCount, 2)
        XCTAssertEqual(groups.first?.packagePlan?.acquiredQuantity?.value, 200)
        XCTAssertEqual(groups.first?.packagePlan?.overage?.value, 50)
    }

    func testSameEightOunceProductRecalculatesPackagePlanWhenRequirementChanges() throws {
        let product = makeProduct(productID: "eight-ounce", packageQuantity: 8, packageUnit: "oz")
        let onePackage = ProductPurchaseGroupingService.group([
            candidate(
                line: 1,
                ingredient: 11,
                product: product,
                canonical: try XCTUnwrap(
                    QuantityEngine.canonicalize(value: 8, unit: "oz").quantity
                )
            )
        ])
        let twoPackages = ProductPurchaseGroupingService.group([
            candidate(
                line: 1,
                ingredient: 11,
                product: product,
                canonical: try XCTUnwrap(
                    QuantityEngine.canonicalize(value: 16, unit: "oz").quantity
                )
            )
        ])

        XCTAssertEqual(onePackage.first?.packagePlan?.packageCount, 1)
        XCTAssertEqual(twoPackages.first?.packagePlan?.packageCount, 2)
        XCTAssertEqual(twoPackages.first?.packagePlan?.acquiredQuantity?.dimension, .mass)
        XCTAssertEqual(twoPackages.first?.packagePlan?.overage?.value, 0)
        XCTAssertEqual(onePackage.first?.exactProductIdentity, twoPackages.first?.exactProductIdentity)
        XCTAssertEqual(onePackage.first?.contributions.map(\.sourceIngredientID), [uuid(11)])
        XCTAssertEqual(twoPackages.first?.contributions.map(\.sourceIngredientID), [uuid(11)])
    }

    func testCompatibleVolumeQuantitiesSum() throws {
        let product = makeProduct(productID: "volume", packageQuantity: 500, packageUnit: "ml")
        let groups = ProductPurchaseGroupingService.group([
            candidate(line: 1, ingredient: 11, product: product, canonical: try quantity(250, .volume)),
            candidate(line: 2, ingredient: 12, product: product, canonical: try quantity(500, .volume))
        ])

        XCTAssertEqual(groups.first?.packagePlan?.requiredQuantity?.value, 750)
        XCTAssertEqual(groups.first?.packagePlan?.requiredQuantity?.dimension, .volume)
        XCTAssertEqual(groups.first?.packagePlan?.packageCount, 2)
        XCTAssertEqual(groups.first?.packagePlan?.overage?.value, 250)
    }

    func testMassAndVolumeRemainInProvenanceWithoutBeingSummed() throws {
        let product = makeProduct(productID: "mixed")
        let mass = try quantity(100, .mass)
        let volume = try quantity(100, .volume)
        let groups = ProductPurchaseGroupingService.group([
            candidate(line: 1, ingredient: 11, product: product, canonical: mass),
            candidate(line: 2, ingredient: 12, product: product, canonical: volume)
        ])

        XCTAssertNil(groups.first?.packagePlan?.requiredQuantity)
        XCTAssertEqual(groups.first?.contributions.map(\.canonicalRequiredQuantity), [mass, volume])
    }

    func testUnknownQuantityRemainsPreservedWithoutCoercion() {
        let groups = ProductPurchaseGroupingService.group([
            candidate(
                line: 1,
                ingredient: 11,
                product: makeProduct(productID: "unknown"),
                display: "to taste",
                canonical: nil
            )
        ])

        XCTAssertEqual(groups.first?.contributions.first?.originalDisplayQuantity, "to taste")
        XCTAssertNil(groups.first?.contributions.first?.canonicalRequiredQuantity)
        XCTAssertNil(groups.first?.packagePlan?.requiredQuantity)
    }

    func testMissingPackageMetadataNeverDefaultsToOne() throws {
        let groups = ProductPurchaseGroupingService.group([
            candidate(
                line: 1,
                ingredient: 11,
                product: makeProduct(productID: "missing"),
                canonical: try quantity(100, .mass)
            )
        ])

        XCTAssertNil(groups.first?.packagePlan?.packageSize)
        XCTAssertNil(groups.first?.packagePlan?.packageCount)
        XCTAssertNil(groups.first?.packagePlan?.acquiredQuantity)
    }

    func testVariableWeightProductRequiresExplicitPackageQuantity() throws {
        var product = makeProduct(
            productID: "variable",
            packageQuantity: 1,
            packageUnit: "lb"
        )
        product.variableWeight = true

        let groups = ProductPurchaseGroupingService.group([
            candidate(
                line: 1,
                ingredient: 11,
                product: product,
                canonical: try quantity(453.59237, .mass)
            )
        ])

        XCTAssertNil(groups.first?.packagePlan?.packageCount)
        XCTAssertEqual(groups.first?.packagePlan?.certainty, .unknown)
    }

    func testSameExactURLGroupsEvenWhenProductIDsAreUnavailable() {
        let first = makeProduct(productID: "", pathID: "777")
        let second = makeProduct(productID: "", pathID: "777")

        let groups = ProductPurchaseGroupingService.group([
            candidate(line: 1, ingredient: 11, product: first),
            candidate(line: 2, ingredient: 12, product: second)
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.contributions.count, 2)
        XCTAssertTrue(groups.first?.exactProductIdentityEvidence?.contains {
            $0.kind == .exactURL
        } == true)
    }

    func testPackageOnlyQuantityRemainsPreservedWithoutPackageCount() throws {
        let package = try quantity(2, .package)
        let groups = ProductPurchaseGroupingService.group([
            candidate(line: 1, ingredient: 11, product: makeProduct(productID: "package"), canonical: package)
        ])

        XCTAssertEqual(groups.first?.contributions.first?.canonicalRequiredQuantity, package)
        XCTAssertNil(groups.first?.packagePlan?.requiredQuantity)
        XCTAssertNil(groups.first?.packagePlan?.packageCount)
        XCTAssertNil(groups.first?.packagePlan?.acquiredQuantity)
        XCTAssertNil(groups.first?.packagePlan?.overage)
    }

    func testExactAndFallbackRowsRemainSeparate() {
        let exact = makeProduct(productID: "rice")
        let fallback = makeProduct(
            productID: "rice",
            pathID: "search",
            dataSource: .searchFallback,
            linkKind: .searchResults,
            url: "https://www.walmart.com/search?q=rice"
        )
        let ingredientA = makeIngredient(11)
        let ingredientB = makeIngredient(12)
        let groups = ProductPurchaseGroupingService.group([
            ProductPurchaseCandidate(
                lineID: uuid(1),
                ingredientResolution: IngredientResolution(ingredient: ingredientA, resolution: .exactProduct(exact)),
                originalDisplayQuantity: "1"
            ),
            ProductPurchaseCandidate(
                lineID: uuid(2),
                ingredientResolution: IngredientResolution(ingredient: ingredientB, resolution: .searchFallback(fallback)),
                originalDisplayQuantity: "1"
            )
        ])

        XCTAssertEqual(groups.count, 2)
        XCTAssertNotNil(groups.first?.exactProductIdentity)
        XCTAssertNil(groups.last?.exactProductIdentity)
        XCTAssertEqual(groups.map(\.memberLineIDs), [[uuid(1)], [uuid(2)]])
    }

    func testUnresolvedAndExcludedRowsDoNotEnterGroups() {
        let unresolvedIngredient = makeIngredient(11)
        let excludedIngredient = makeIngredient(12)
        let groups = ProductPurchaseGroupingService.group([
            ProductPurchaseCandidate(
                lineID: uuid(1),
                ingredientResolution: IngredientResolution(
                    ingredient: unresolvedIngredient,
                    resolution: .unresolved(.noCandidates)
                ),
                originalDisplayQuantity: "1"
            ),
            ProductPurchaseCandidate(
                lineID: uuid(2),
                ingredientResolution: IngredientResolution(
                    ingredient: excludedIngredient,
                    resolution: .userExcluded
                ),
                originalDisplayQuantity: "1"
            )
        ])

        XCTAssertTrue(groups.isEmpty)
    }

    func testEmptyInputProducesNoGroups() {
        XCTAssertTrue(ProductPurchaseGroupingService.group([]).isEmpty)
    }

    func testLegacyShoppingListItemWithoutPurchaseGroupDecodesAsAbsent() throws {
        let product = makeProduct(productID: "legacy")
        let item = ShoppingListItem(
            id: uuid(1),
            ingredient: makeIngredient(11),
            requestedQuantity: "1 package",
            product: product,
            alternatives: [],
            storeID: uuid(99)
        )
        let encoded = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "purchaseGroup")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ShoppingListItem.self, from: legacyData)

        XCTAssertNil(decoded.purchaseGroup)
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.purchaseQuantity, 1)
    }

    private func candidate(
        line: UInt8,
        ingredient: UInt8,
        recipe: UInt8? = nil,
        product: RetailerProductRecord,
        display: String = "1",
        canonical: CanonicalQuantity? = nil,
        pantry: CanonicalQuantity? = nil
    ) -> ProductPurchaseCandidate {
        let ingredient = makeIngredient(ingredient)
        return ProductPurchaseCandidate(
            lineID: uuid(line),
            sourceRecipeID: recipe.map(uuid),
            ingredientResolution: IngredientResolution(
                ingredient: ingredient,
                resolution: .exactProduct(product)
            ),
            originalDisplayQuantity: display,
            canonicalRequiredQuantity: canonical,
            pantryDeduction: pantry
        )
    }

    private func makeIngredient(_ id: UInt8) -> Ingredient {
        Ingredient(id: uuid(id), name: "Ingredient \(id)")
    }

    private func makeProduct(
        productID: String,
        gtin: String? = nil,
        pathID: String = "",
        retailerID: String = "walmart",
        dataSource: ProductDataSource = .retailerAPI,
        linkKind: RetailerLinkKind = .exactProduct,
        url: String? = nil,
        packageQuantity: Double? = nil,
        packageUnit: String? = nil
    ) -> RetailerProductRecord {
        let resolvedPathID = pathID.isEmpty ? productID : pathID
        let urlString = url ?? (resolvedPathID.isEmpty
            ? "https://www.\(retailerID).com/search?q=unknown"
            : "https://www.\(retailerID).com/ip/product/\(resolvedPathID)")
        return RetailerProductRecord(
            retailerID: retailerID,
            storeID: "store-1",
            retailerProductID: productID,
            gtin: gtin,
            title: "Test Product",
            brand: "Test Brand",
            exactURL: URL(string: urlString) ?? URL(fileURLWithPath: "/invalid-test-url"),
            packageDescription: "1 package",
            packageQuantity: packageQuantity,
            packageUnit: packageUnit,
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

    private func quantity(
        _ value: Decimal,
        _ dimension: QuantityDimension,
        certainty: QuantityCertainty = .exact
    ) throws -> CanonicalQuantity {
        try XCTUnwrap(CanonicalQuantity(value: value, dimension: dimension, certainty: certainty))
    }

    private func uuid(_ suffix: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, suffix))
    }
}
