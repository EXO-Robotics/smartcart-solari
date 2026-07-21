import XCTest
@testable import SmartCart

final class QuantityEngineTests: XCTestCase {
    func testPoundCanonicalizesExactlyToGrams() throws {
        let quantity = try exactQuantity(
            QuantityEngine.canonicalize(value: 1, unit: "lb")
        )

        XCTAssertEqual(quantity.value, decimal("453.59237"))
        XCTAssertEqual(quantity.dimension, .mass)
        XCTAssertEqual(quantity.canonicalUnit, .gram)
        XCTAssertEqual(quantity.certainty, .exact)
    }

    func testTwoCupsCanonicalizeExactlyToMilliliters() throws {
        let quantity = try exactQuantity(
            QuantityEngine.canonicalize(value: 2, unit: "cups")
        )

        XCTAssertEqual(quantity.value, decimal("473.176473"))
        XCTAssertEqual(quantity.dimension, .volume)
        XCTAssertEqual(quantity.canonicalUnit, .milliliter)
    }

    func testMassAliasesShareOneCanonicalValue() throws {
        let pounds = try exactQuantity(
            QuantityEngine.canonicalize(value: 1, unit: "LBS.")
        )
        let ounces = try exactQuantity(
            QuantityEngine.canonicalize(value: 16, unit: "ounces")
        )
        let grams = try exactQuantity(
            QuantityEngine.canonicalize(value: decimal("453.59237"), unit: "grams")
        )
        let kilograms = try exactQuantity(
            QuantityEngine.canonicalize(value: decimal("0.45359237"), unit: "kilograms")
        )

        XCTAssertEqual(pounds.value, ounces.value)
        XCTAssertEqual(pounds.value, grams.value)
        XCTAssertEqual(pounds.value, kilograms.value)
    }

    func testVolumeAliasesShareOneCanonicalValue() throws {
        let fluidOunce = try exactQuantity(
            QuantityEngine.canonicalize(value: 1, unit: "fl. oz.")
        )
        let teaspoons = try exactQuantity(
            QuantityEngine.canonicalize(value: 6, unit: "teaspoons")
        )
        let tablespoons = try exactQuantity(
            QuantityEngine.canonicalize(value: 2, unit: "tablespoons")
        )
        let milliliters = try exactQuantity(
            QuantityEngine.canonicalize(value: decimal("29.5735295625"), unit: "ml")
        )
        let liters = try exactQuantity(
            QuantityEngine.canonicalize(value: decimal("0.0295735295625"), unit: "litres")
        )

        XCTAssertEqual(fluidOunce.value, teaspoons.value)
        XCTAssertEqual(fluidOunce.value, tablespoons.value)
        XCTAssertEqual(fluidOunce.value, milliliters.value)
        XCTAssertEqual(fluidOunce.value, liters.value)
    }

    func testCountAliasesRemainCount() throws {
        let quantity = try exactQuantity(
            QuantityEngine.convert(value: 3, from: "items", to: "count")
        )

        XCTAssertEqual(quantity.value, 3)
        XCTAssertEqual(quantity.dimension, .count)
        XCTAssertEqual(quantity.canonicalUnit, .count)
    }

    func testIngredientNamesRemainOutsideGenericQuantityEngine() {
        for alias in ["clove", "cloves", "egg", "eggs", "lemon", "lemons"] {
            XCTAssertEqual(QuantityEngine.dimension(for: alias), .unknown, alias)
            XCTAssertNil(QuantityEngine.normalizedUnit(for: alias), alias)
        }

        XCTAssertEqual(QuantityEngine.dimension(for: "each"), .count)
        XCTAssertEqual(QuantityEngine.normalizedUnit(for: "each"), "count")
    }

    func testDestinationValueConvertsGramsToPounds() throws {
        let quantity = try exactUnitValue(
            QuantityEngine.convertedValue(
                value: decimal("453.59237"),
                from: "g",
                to: "lb"
            )
        )

        XCTAssertEqual(quantity.value, 1)
        XCTAssertEqual(quantity.unit, "lb")
        XCTAssertEqual(quantity.dimension, .mass)
        XCTAssertEqual(quantity.canonicalQuantity.value, decimal("453.59237"))
    }

    func testDestinationValueConvertsCupToFortyEightTeaspoons() throws {
        let quantity = try exactUnitValue(
            QuantityEngine.convertedValue(value: 1, from: "cup", to: "tsp")
        )

        XCTAssertEqual(quantity.value, 48)
        XCTAssertEqual(quantity.unit, "tsp")
        XCTAssertEqual(quantity.dimension, .volume)
        XCTAssertEqual(quantity.canonicalQuantity.value, decimal("236.5882365"))
    }

    func testDoubleBridgeRejectsInvalidValuesAndUsesTheSameConversionTable() throws {
        let quantity = try exactUnitValue(
            QuantityEngine.convertedValue(doubleValue: 500, from: "g", to: "lb")
        )

        XCTAssertEqual(
            NSDecimalNumber(decimal: quantity.value).doubleValue,
            1.1023113109243879,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(
            QuantityEngine.convertedValue(doubleValue: .infinity, from: "g", to: "lb"),
            .unsupportedConversion(.invalidValue)
        )
    }

    func testDestinationValueNormalizesAliasAndPreservesEstimate() {
        let result = QuantityEngine.convertedValue(
            value: 16,
            from: "ounces",
            to: "pounds",
            certainty: .estimated
        )
        guard case .estimated(let quantity, basis: .sourceQuantity) = result else {
            return XCTFail("Expected source estimate, got \(result)")
        }

        XCTAssertEqual(quantity.value, 1)
        XCTAssertEqual(quantity.unit, "lb")
        XCTAssertEqual(quantity.certainty, .estimated)
    }

    func testDestinationValuePreservesTypedFailureReason() {
        XCTAssertEqual(
            QuantityEngine.convertedValue(value: 1, from: "cup", to: "g"),
            .incompatibleDimensions(source: .volume, destination: .mass)
        )
        XCTAssertEqual(
            QuantityEngine.convertedValue(value: 1, from: "g", to: nil),
            .missingUnit(.destination)
        )
    }

    func testDestinationValueUsesPackageMetadataWithoutAssumingPackageSize() throws {
        XCTAssertEqual(
            QuantityEngine.convertedValue(value: 1, from: "package", to: "oz"),
            .unsupportedConversion(.packageMetadataRequired)
        )

        let quantity = try exactUnitValue(
            QuantityEngine.convertedValue(
                value: 1,
                from: "package",
                to: "oz",
                packageMetadata: QuantityPackageMetadata(
                    contentsPerPackage: 8,
                    contentsUnit: "oz"
                )
            )
        )
        XCTAssertEqual(quantity.value, 8)
        XCTAssertEqual(quantity.unit, "oz")
    }

    func testCupToGramIsIncompatibleWithoutIngredientDensity() {
        XCTAssertEqual(
            QuantityEngine.convert(value: 2, from: "cups", to: "g"),
            .incompatibleDimensions(source: .volume, destination: .mass)
        )
    }

    func testCountToCupIsIncompatibleWithoutIngredientYieldRule() {
        XCTAssertEqual(
            QuantityEngine.convert(value: 1, from: "count", to: "cup"),
            .incompatibleDimensions(source: .count, destination: .volume)
        )
    }

    func testPackageToMassRequiresMetadata() {
        XCTAssertEqual(
            QuantityEngine.convert(value: 1, from: "package", to: "oz"),
            .unsupportedConversion(.packageMetadataRequired)
        )
    }

    func testPackageMetadataAllowsExactPhysicalConversion() throws {
        let metadata = QuantityPackageMetadata(
            contentsPerPackage: 8,
            contentsUnit: "oz"
        )
        let quantity = try exactQuantity(
            QuantityEngine.convert(
                value: 2,
                from: "packages",
                to: "lb",
                packageMetadata: metadata
            )
        )

        XCTAssertEqual(quantity.value, decimal("453.59237"))
        XCTAssertEqual(quantity.dimension, .mass)
        XCTAssertEqual(quantity.canonicalUnit, .gram)
    }

    func testPhysicalQuantityCanResolveToPackageCountWithMetadata() throws {
        let metadata = QuantityPackageMetadata(
            contentsPerPackage: 8,
            contentsUnit: "oz"
        )
        let quantity = try exactQuantity(
            QuantityEngine.convert(
                value: 1,
                from: "lb",
                to: "package",
                packageMetadata: metadata
            )
        )

        XCTAssertEqual(quantity.value, 2)
        XCTAssertEqual(quantity.dimension, .package)
        XCTAssertEqual(quantity.canonicalUnit, .package)
    }

    func testEstimatedPackageMetadataRemainsExplicit() throws {
        let metadata = QuantityPackageMetadata(
            contentsPerPackage: 8,
            contentsUnit: "oz",
            certainty: .estimated
        )
        let result = QuantityEngine.convert(
            value: 1,
            from: "package",
            to: "g",
            packageMetadata: metadata
        )
        guard case .estimated(let quantity, basis: .packageMetadata) = result else {
            return XCTFail("Expected an estimate tied to package metadata, got \(result)")
        }

        XCTAssertEqual(quantity.value, decimal("226.796185"))
        XCTAssertEqual(quantity.certainty, .estimated)
    }

    func testMissingUnitIsNotSilentlyTreatedAsCount() {
        XCTAssertEqual(
            QuantityEngine.canonicalize(value: 2, unit: nil),
            .missingUnit(.source)
        )
        XCTAssertEqual(
            QuantityEngine.canonicalize(value: 2, unit: "   "),
            .missingUnit(.source)
        )
        XCTAssertEqual(QuantityEngine.dimension(for: nil), .unknown)
    }

    func testUnknownUnitReturnsItsTypedReason() {
        XCTAssertEqual(
            QuantityEngine.canonicalize(value: 1, unit: "pinch"),
            .unsupportedConversion(.unknownUnit(unit: "pinch", role: .source))
        )
        XCTAssertEqual(QuantityEngine.dimension(for: "pinch"), .unknown)
    }

    func testNonQuantitativeAmountDoesNotBecomeANumericQuantity() {
        XCTAssertEqual(
            QuantityEngine.canonicalize(value: 1, unit: "to taste"),
            .unsupportedConversion(.nonQuantitative(unit: "to taste", role: .source))
        )
        XCTAssertEqual(QuantityEngine.dimension(for: "as needed"), .nonQuantitative)
    }

    func testPackageMetadataCannotRecursivelyDescribePackages() {
        let metadata = QuantityPackageMetadata(
            contentsPerPackage: 2,
            contentsUnit: "packages"
        )

        XCTAssertEqual(
            QuantityEngine.convert(
                value: 1,
                from: "package",
                to: "count",
                packageMetadata: metadata
            ),
            .unsupportedConversion(.invalidPackageMetadata)
        )
    }

    func testUnknownSourceNeverUsesExactTerminalResult() {
        let result = QuantityEngine.canonicalize(
            value: 1,
            unit: "kg",
            certainty: .unknown
        )
        guard case .estimated(let quantity, basis: .uncertainSource) = result else {
            return XCTFail("Expected uncertain source review, got \(result)")
        }

        XCTAssertEqual(quantity.value, 1_000)
        XCTAssertEqual(quantity.certainty, .unknown)
    }

    func testEstimatedSourceUsesEstimatedTerminalResult() {
        let result = QuantityEngine.canonicalize(
            value: 1,
            unit: "kg",
            certainty: .estimated
        )
        guard case .estimated(let quantity, basis: .sourceQuantity) = result else {
            return XCTFail("Expected source estimate, got \(result)")
        }

        XCTAssertEqual(quantity.value, 1_000)
        XCTAssertEqual(quantity.certainty, .estimated)
    }

    func testCanonicalQuantityRejectsNonNumericDimensionDuringDecode() throws {
        let invalidJSON = Data(
            #"{"value":1,"dimension":"nonQuantitative","certainty":"unknown"}"#.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(CanonicalQuantity.self, from: invalidJSON))
    }

    func testCanonicalQuantityRejectsInvalidDirectValuesWithoutTrapping() {
        XCTAssertNil(
            CanonicalQuantity(value: -1, dimension: .mass, certainty: .exact)
        )
        XCTAssertNil(
            CanonicalQuantity(value: 1, dimension: .unknown, certainty: .unknown)
        )
        XCTAssertNil(
            CanonicalQuantity(value: 1, dimension: .nonQuantitative, certainty: .unknown)
        )
    }
}

private extension QuantityEngineTests {
    enum TestFailure: Error {
        case expectedExact(QuantityConversionResult)
        case expectedExactValue(QuantityValueConversionResult)
    }

    func exactQuantity(_ result: QuantityConversionResult) throws -> CanonicalQuantity {
        guard case .exact(let quantity) = result else {
            throw TestFailure.expectedExact(result)
        }
        return quantity
    }

    func exactUnitValue(_ result: QuantityValueConversionResult) throws -> QuantityUnitValue {
        guard case .exact(let quantity) = result else {
            throw TestFailure.expectedExactValue(result)
        }
        return quantity
    }

    func decimal(_ value: String) -> Decimal {
        guard let decimal = Decimal(
            string: value,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            XCTFail("Invalid Decimal test fixture: \(value)")
            return .nan
        }
        return decimal
    }
}
