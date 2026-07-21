import Foundation

/// The physical domain represented by a quantity.
///
/// Ingredient identity and ingredient-specific yield or density rules intentionally do not
/// belong here. For example, `cup` is volume and `gram` is mass regardless of whether the
/// ingredient happens to be flour.
enum QuantityDimension: String, Codable, CaseIterable, Hashable, Sendable {
    case mass
    case volume
    case count
    case package
    case nonQuantitative
    case unknown
}

/// Confidence in the source facts, independent of whether the unit arithmetic is exact.
enum QuantityCertainty: String, Codable, CaseIterable, Hashable, Sendable {
    case exact
    case estimated
    case unknown

    fileprivate static func combined(
        _ lhs: QuantityCertainty,
        _ rhs: QuantityCertainty
    ) -> QuantityCertainty {
        if lhs == .unknown || rhs == .unknown { return .unknown }
        if lhs == .estimated || rhs == .estimated { return .estimated }
        return .exact
    }
}

/// SmartCart's canonical storage unit for each numeric dimension.
enum CanonicalQuantityUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case gram = "g"
    case milliliter = "ml"
    case count
    case package
}

/// A numeric quantity expressed in the one canonical unit for its dimension.
///
/// Mass is stored in grams, volume in milliliters, count in individual counts, and package
/// in package counts. Non-quantitative and unknown inputs do not produce this type; they are
/// retained as explicit conversion outcomes instead.
struct CanonicalQuantity: Hashable, Codable, Sendable {
    let value: Decimal
    let dimension: QuantityDimension
    let certainty: QuantityCertainty

    var canonicalUnit: CanonicalQuantityUnit? {
        switch dimension {
        case .mass: .gram
        case .volume: .milliliter
        case .count: .count
        case .package: .package
        case .nonQuantitative, .unknown: nil
        }
    }

    init?(
        value: Decimal,
        dimension: QuantityDimension,
        certainty: QuantityCertainty
    ) {
        guard Self.isValid(value: value, dimension: dimension) else { return nil }
        self.value = value
        self.dimension = dimension
        self.certainty = certainty
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case dimension
        case certainty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(Decimal.self, forKey: .value)
        let dimension = try container.decode(QuantityDimension.self, forKey: .dimension)
        let certainty = try container.decode(QuantityCertainty.self, forKey: .certainty)

        guard Self.isValid(value: value, dimension: dimension) else {
            throw DecodingError.dataCorruptedError(
                forKey: .dimension,
                in: container,
                debugDescription: "Canonical quantities require a nonnegative numeric value and a numeric dimension."
            )
        }

        self.value = value
        self.dimension = dimension
        self.certainty = certainty
    }

    private static func isValid(value: Decimal, dimension: QuantityDimension) -> Bool {
        guard !value.isNaN, value >= 0 else { return false }
        switch dimension {
        case .mass, .volume, .count, .package:
            return true
        case .nonQuantitative, .unknown:
            return false
        }
    }
}

/// Contents of one package, used only when a conversion crosses the package boundary.
///
/// Examples include `8 oz per package` or `12 count per carton`. The unit is deliberately a
/// raw unit string so catalog and parser inputs can pass through the same alias resolution as
/// recipe quantities. Package-within-package metadata is rejected by `QuantityEngine`.
struct QuantityPackageMetadata: Hashable, Codable, Sendable {
    let contentsPerPackage: Decimal
    let contentsUnit: String?
    let certainty: QuantityCertainty

    init(
        contentsPerPackage: Decimal,
        contentsUnit: String?,
        certainty: QuantityCertainty = .exact
    ) {
        self.contentsPerPackage = contentsPerPackage
        self.contentsUnit = contentsUnit
        self.certainty = certainty
    }
}

enum QuantityUnitRole: String, Hashable, Sendable {
    case source
    case destination
    case packageContents
}

/// Why a successful conversion contains estimated rather than fully exact source facts.
///
/// No ingredient-density case exists here by design. A future density/yield service may
/// calculate an estimate outside this engine, but the core engine never invents one.
enum QuantityEstimationBasis: String, Hashable, Sendable {
    case sourceQuantity
    case packageMetadata
    case sourceAndPackageMetadata
    /// The arithmetic is exact, but the source observation is not trustworthy
    /// enough to authorize exact package or pantry math.
    case uncertainSource
    /// The arithmetic is exact, but the package contents are not trustworthy
    /// enough to authorize exact package or pantry math.
    case uncertainPackageMetadata
    case uncertainSourceAndPackageMetadata
}

enum QuantityUnsupportedConversionReason: Hashable, Sendable {
    case unknownUnit(unit: String, role: QuantityUnitRole)
    case nonQuantitative(unit: String, role: QuantityUnitRole)
    case packageMetadataRequired
    case invalidPackageMetadata
    case invalidValue
}

/// A typed terminal result. Callers never need to infer why a conversion returned no value.
///
/// `.exact` means both the unit arithmetic and every source fact are exact.
/// Estimated or unknown source facts always use `.estimated`, which prevents a
/// caller from accidentally accepting an uncertain value as authoritative.
enum QuantityConversionResult: Hashable, Sendable {
    case exact(CanonicalQuantity)
    case estimated(CanonicalQuantity, basis: QuantityEstimationBasis)
    case incompatibleDimensions(source: QuantityDimension, destination: QuantityDimension)
    case missingUnit(QuantityUnitRole)
    case unsupportedConversion(QuantityUnsupportedConversionReason)

    var quantity: CanonicalQuantity? {
        switch self {
        case .exact(let quantity), .estimated(let quantity, _):
            quantity
        case .incompatibleDimensions, .missingUnit, .unsupportedConversion:
            nil
        }
    }
}

/// A converted value expressed in the caller's requested, normalized destination unit.
///
/// `canonicalQuantity` keeps a lossless common representation for comparison and arithmetic;
/// `value` and `unit` are suitable for existing package, pantry, and display calculations.
struct QuantityUnitValue: Hashable, Sendable {
    let value: Decimal
    let unit: String
    let dimension: QuantityDimension
    let certainty: QuantityCertainty
    let canonicalQuantity: CanonicalQuantity

    fileprivate init(
        value: Decimal,
        unit: String,
        canonicalQuantity: CanonicalQuantity
    ) {
        self.value = value
        self.unit = unit
        dimension = canonicalQuantity.dimension
        certainty = canonicalQuantity.certainty
        self.canonicalQuantity = canonicalQuantity
    }
}

/// Typed terminal result for callers that need a value in a specific destination unit.
enum QuantityValueConversionResult: Hashable, Sendable {
    case exact(QuantityUnitValue)
    case estimated(QuantityUnitValue, basis: QuantityEstimationBasis)
    case incompatibleDimensions(source: QuantityDimension, destination: QuantityDimension)
    case missingUnit(QuantityUnitRole)
    case unsupportedConversion(QuantityUnsupportedConversionReason)

    var quantity: QuantityUnitValue? {
        switch self {
        case .exact(let quantity), .estimated(let quantity, _):
            quantity
        case .incompatibleDimensions, .missingUnit, .unsupportedConversion:
            nil
        }
    }
}

/// Conservative, ingredient-agnostic quantity normalization.
///
/// The engine recognizes only exact physical conversions and explicitly supplied package
/// contents. US customary cooking volumes use their exact definitions in milliliters.
enum QuantityEngine {
    /// Converts a raw amount to SmartCart's canonical unit for the source dimension.
    static func canonicalize(
        value: Decimal,
        unit: String?,
        certainty: QuantityCertainty = .exact
    ) -> QuantityConversionResult {
        guard isValid(value) else {
            return .unsupportedConversion(.invalidValue)
        }

        switch resolve(unit, role: .source) {
        case .failure(let result):
            return result
        case .unit(let definition):
            guard definition.dimension != .nonQuantitative else {
                return .unsupportedConversion(
                    .nonQuantitative(unit: definition.symbol, role: .source)
                )
            }

            let canonicalValue = value * definition.multiplierToCanonical
            guard isValid(canonicalValue) else {
                return .unsupportedConversion(.invalidValue)
            }
            guard let quantity = CanonicalQuantity(
                value: canonicalValue,
                dimension: definition.dimension,
                certainty: certainty
            ) else {
                return .unsupportedConversion(.invalidValue)
            }
            return successfulResult(quantity, sourceCertainty: certainty)
        }
    }

    /// Validates a conversion between two units and returns the value in the destination
    /// dimension's canonical unit. For same-dimension conversions, this is the canonicalized
    /// source value. Package-to-physical and physical-to-package conversions require contents
    /// metadata; the engine never assumes that one package is sufficient.
    static func convert(
        value: Decimal,
        from sourceUnit: String?,
        to destinationUnit: String?,
        certainty: QuantityCertainty = .exact,
        packageMetadata: QuantityPackageMetadata? = nil
    ) -> QuantityConversionResult {
        guard isValid(value) else {
            return .unsupportedConversion(.invalidValue)
        }

        let source: UnitDefinition
        switch resolve(sourceUnit, role: .source) {
        case .unit(let definition):
            source = definition
        case .failure(let result):
            return result
        }

        let destination: UnitDefinition
        switch resolve(destinationUnit, role: .destination) {
        case .unit(let definition):
            destination = definition
        case .failure(let result):
            return result
        }

        if source.dimension == .nonQuantitative {
            return .unsupportedConversion(
                .nonQuantitative(unit: source.symbol, role: .source)
            )
        }
        if destination.dimension == .nonQuantitative {
            return .unsupportedConversion(
                .nonQuantitative(unit: destination.symbol, role: .destination)
            )
        }

        if source.dimension == destination.dimension {
            let canonicalValue = value * source.multiplierToCanonical
            guard isValid(canonicalValue) else {
                return .unsupportedConversion(.invalidValue)
            }
            guard let quantity = CanonicalQuantity(
                value: canonicalValue,
                dimension: source.dimension,
                certainty: certainty
            ) else {
                return .unsupportedConversion(.invalidValue)
            }
            return successfulResult(quantity, sourceCertainty: certainty)
        }

        guard source.dimension == .package || destination.dimension == .package else {
            return .incompatibleDimensions(
                source: source.dimension,
                destination: destination.dimension
            )
        }

        guard let packageMetadata else {
            return .unsupportedConversion(.packageMetadataRequired)
        }
        guard isValidPackageContents(packageMetadata.contentsPerPackage) else {
            return .unsupportedConversion(.invalidPackageMetadata)
        }

        let packageContents: UnitDefinition
        switch resolve(packageMetadata.contentsUnit, role: .packageContents) {
        case .unit(let definition):
            packageContents = definition
        case .failure(let result):
            return result
        }
        guard packageContents.dimension != .package else {
            return .unsupportedConversion(.invalidPackageMetadata)
        }
        guard packageContents.dimension != .nonQuantitative else {
            return .unsupportedConversion(
                .nonQuantitative(unit: packageContents.symbol, role: .packageContents)
            )
        }

        let canonicalContents = packageMetadata.contentsPerPackage
            * packageContents.multiplierToCanonical
        guard isValidPackageContents(canonicalContents) else {
            return .unsupportedConversion(.invalidPackageMetadata)
        }

        let outputCertainty = QuantityCertainty.combined(
            certainty,
            packageMetadata.certainty
        )

        if source.dimension == .package {
            guard packageContents.dimension == destination.dimension else {
                return .incompatibleDimensions(
                    source: packageContents.dimension,
                    destination: destination.dimension
                )
            }
            let canonicalValue = value * canonicalContents
            guard isValid(canonicalValue) else {
                return .unsupportedConversion(.invalidValue)
            }
            guard let quantity = CanonicalQuantity(
                value: canonicalValue,
                dimension: destination.dimension,
                certainty: outputCertainty
            ) else {
                return .unsupportedConversion(.invalidValue)
            }
            return successfulResult(
                quantity,
                sourceCertainty: certainty,
                packageCertainty: packageMetadata.certainty
            )
        }

        guard source.dimension == packageContents.dimension else {
            return .incompatibleDimensions(
                source: source.dimension,
                destination: packageContents.dimension
            )
        }
        let canonicalSource = value * source.multiplierToCanonical
        let packageCount = canonicalSource / canonicalContents
        guard isValid(packageCount) else {
            return .unsupportedConversion(.invalidValue)
        }
        guard let quantity = CanonicalQuantity(
            value: packageCount,
            dimension: .package,
            certainty: outputCertainty
        ) else {
            return .unsupportedConversion(.invalidValue)
        }
        return successfulResult(
            quantity,
            sourceCertainty: certainty,
            packageCertainty: packageMetadata.certainty
        )
    }

    /// Converts a raw amount and expresses it in the requested destination unit.
    ///
    /// Unlike `convert`, which always returns canonical grams, milliliters, counts, or package
    /// counts, this API performs the final exact division needed by callers replacing local
    /// conversion tables. It retains the canonical quantity alongside the requested-unit value.
    static func convertedValue(
        value: Decimal,
        from sourceUnit: String?,
        to destinationUnit: String?,
        certainty: QuantityCertainty = .exact,
        packageMetadata: QuantityPackageMetadata? = nil
    ) -> QuantityValueConversionResult {
        let canonicalResult = convert(
            value: value,
            from: sourceUnit,
            to: destinationUnit,
            certainty: certainty,
            packageMetadata: packageMetadata
        )

        guard canonicalResult.quantity != nil else {
            return valueResult(from: canonicalResult)
        }

        let destination: UnitDefinition
        switch resolve(destinationUnit, role: .destination) {
        case .unit(let definition):
            destination = definition
        case .failure(let result):
            return valueResult(from: result)
        }

        switch canonicalResult {
        case .exact(let quantity):
            return expressedValue(quantity, in: destination, estimationBasis: nil)
        case .estimated(let quantity, let basis):
            return expressedValue(quantity, in: destination, estimationBasis: basis)
        case .incompatibleDimensions, .missingUnit, .unsupportedConversion:
            return valueResult(from: canonicalResult)
        }
    }

    /// Bridges legacy `Double`-backed model values into the Decimal engine without asking
    /// each caller to maintain another conversion implementation.
    static func convertedValue(
        doubleValue: Double,
        from sourceUnit: String?,
        to destinationUnit: String?,
        certainty: QuantityCertainty = .exact,
        packageMetadata: QuantityPackageMetadata? = nil
    ) -> QuantityValueConversionResult {
        guard doubleValue.isFinite,
              doubleValue >= 0,
              let value = Decimal(
                string: String(doubleValue),
                locale: Locale(identifier: "en_US_POSIX")
              ) else {
            return .unsupportedConversion(.invalidValue)
        }

        return convertedValue(
            value: value,
            from: sourceUnit,
            to: destinationUnit,
            certainty: certainty,
            packageMetadata: packageMetadata
        )
    }

    /// Returns the engine's canonical spelling for a recognized unit alias.
    /// Missing, blank, and unknown units remain unresolved.
    static func normalizedUnit(for unit: String?) -> String? {
        switch resolve(unit, role: .source) {
        case .unit(let definition): definition.symbol
        case .failure: nil
        }
    }

    /// Returns the recognized physical domain without treating a missing unit as a count.
    static func dimension(for unit: String?) -> QuantityDimension {
        switch resolve(unit, role: .source) {
        case .unit(let definition): definition.dimension
        case .failure: .unknown
        }
    }
}

private extension QuantityEngine {
    struct UnitDefinition {
        let symbol: String
        let dimension: QuantityDimension
        let multiplierToCanonical: Decimal
    }

    enum UnitResolution {
        case unit(UnitDefinition)
        case failure(QuantityConversionResult)
    }

    static let unitAliases: [String: UnitDefinition] = {
        var units: [String: UnitDefinition] = [:]

        func register(
            symbol: String,
            dimension: QuantityDimension,
            multiplier: Decimal,
            aliases: [String]
        ) {
            let definition = UnitDefinition(
                symbol: symbol,
                dimension: dimension,
                multiplierToCanonical: multiplier
            )
            for alias in aliases {
                units[alias] = definition
            }
        }

        register(
            symbol: "g",
            dimension: .mass,
            multiplier: 1,
            aliases: ["g", "gram", "grams"]
        )
        register(
            symbol: "kg",
            dimension: .mass,
            multiplier: 1_000,
            aliases: ["kg", "kilogram", "kilograms"]
        )
        register(
            symbol: "oz",
            dimension: .mass,
            multiplier: decimal("28.349523125"),
            aliases: ["oz", "ounce", "ounces"]
        )
        register(
            symbol: "lb",
            dimension: .mass,
            multiplier: decimal("453.59237"),
            aliases: ["lb", "lbs", "pound", "pounds"]
        )

        register(
            symbol: "ml",
            dimension: .volume,
            multiplier: 1,
            aliases: ["ml", "milliliter", "milliliters", "millilitre", "millilitres"]
        )
        register(
            symbol: "l",
            dimension: .volume,
            multiplier: 1_000,
            aliases: ["l", "liter", "liters", "litre", "litres"]
        )
        register(
            symbol: "tsp",
            dimension: .volume,
            multiplier: decimal("4.92892159375"),
            aliases: ["tsp", "teaspoon", "teaspoons"]
        )
        register(
            symbol: "tbsp",
            dimension: .volume,
            multiplier: decimal("14.78676478125"),
            aliases: ["tbsp", "tbs", "tablespoon", "tablespoons"]
        )
        register(
            symbol: "fl oz",
            dimension: .volume,
            multiplier: decimal("29.5735295625"),
            aliases: ["fl oz", "floz", "fluid ounce", "fluid ounces"]
        )
        register(
            symbol: "cup",
            dimension: .volume,
            multiplier: decimal("236.5882365"),
            aliases: ["c", "cup", "cups"]
        )

        register(
            symbol: "count",
            dimension: .count,
            multiplier: 1,
            aliases: [
                "count", "counts", "ea", "each", "item", "items", "piece", "pieces",
                "unit", "units"
            ]
        )
        register(
            symbol: "package",
            dimension: .package,
            multiplier: 1,
            aliases: ["package", "packages", "pkg", "pkgs", "pack", "packs"]
        )
        register(
            symbol: "to taste",
            dimension: .nonQuantitative,
            multiplier: 1,
            aliases: ["to taste", "as needed", "as desired", "qs"]
        )

        return units
    }()

    static func resolve(_ rawUnit: String?, role: QuantityUnitRole) -> UnitResolution {
        guard let rawUnit else {
            return .failure(.missingUnit(role))
        }
        let key = normalizedUnitKey(rawUnit)
        guard !key.isEmpty else {
            return .failure(.missingUnit(role))
        }
        guard let definition = unitAliases[key] else {
            return .failure(
                .unsupportedConversion(.unknownUnit(unit: key, role: role))
            )
        }
        return .unit(definition)
    }

    static func normalizedUnitKey(_ rawUnit: String) -> String {
        rawUnit
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    static func successfulResult(
        _ quantity: CanonicalQuantity,
        sourceCertainty: QuantityCertainty,
        packageCertainty: QuantityCertainty? = nil
    ) -> QuantityConversionResult {
        let basis: QuantityEstimationBasis?
        switch (sourceCertainty, packageCertainty ?? .exact) {
        case (.exact, .exact):
            basis = nil
        case (.estimated, .exact):
            basis = .sourceQuantity
        case (.exact, .estimated):
            basis = .packageMetadata
        case (.estimated, .estimated):
            basis = .sourceAndPackageMetadata
        case (.unknown, .exact):
            basis = .uncertainSource
        case (.exact, .unknown):
            basis = .uncertainPackageMetadata
        case (.unknown, .unknown), (.unknown, .estimated), (.estimated, .unknown):
            basis = .uncertainSourceAndPackageMetadata
        }

        if let basis {
            return .estimated(quantity, basis: basis)
        }
        return .exact(quantity)
    }

    static func expressedValue(
        _ quantity: CanonicalQuantity,
        in destination: UnitDefinition,
        estimationBasis: QuantityEstimationBasis?
    ) -> QuantityValueConversionResult {
        guard quantity.dimension == destination.dimension else {
            return .incompatibleDimensions(
                source: quantity.dimension,
                destination: destination.dimension
            )
        }

        let value = quantity.value / destination.multiplierToCanonical
        guard isValid(value) else {
            return .unsupportedConversion(.invalidValue)
        }
        let expressed = QuantityUnitValue(
            value: value,
            unit: destination.symbol,
            canonicalQuantity: quantity
        )
        if let estimationBasis {
            return .estimated(expressed, basis: estimationBasis)
        }
        return .exact(expressed)
    }

    static func valueResult(
        from result: QuantityConversionResult
    ) -> QuantityValueConversionResult {
        switch result {
        case .exact(let quantity):
            guard let canonicalUnit = quantity.canonicalUnit else {
                return .unsupportedConversion(.invalidValue)
            }
            return .exact(
                QuantityUnitValue(
                    value: quantity.value,
                    unit: canonicalUnit.rawValue,
                    canonicalQuantity: quantity
                )
            )
        case .estimated(let quantity, let basis):
            guard let canonicalUnit = quantity.canonicalUnit else {
                return .unsupportedConversion(.invalidValue)
            }
            return .estimated(
                QuantityUnitValue(
                    value: quantity.value,
                    unit: canonicalUnit.rawValue,
                    canonicalQuantity: quantity
                ),
                basis: basis
            )
        case .incompatibleDimensions(let source, let destination):
            return .incompatibleDimensions(source: source, destination: destination)
        case .missingUnit(let role):
            return .missingUnit(role)
        case .unsupportedConversion(let reason):
            return .unsupportedConversion(reason)
        }
    }

    static func isValid(_ value: Decimal) -> Bool {
        !value.isNaN && value >= 0
    }

    static func isValidPackageContents(_ value: Decimal) -> Bool {
        isValid(value) && value > 0
    }

    static func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }
}
