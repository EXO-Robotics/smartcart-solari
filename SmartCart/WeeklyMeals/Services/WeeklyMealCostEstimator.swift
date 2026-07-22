import Foundation

struct WeeklyMealPriceRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let recipeID: CuratedRecipeID
    let recipeContentVersion: Int
    let ingredientID: String
    let pricingKey: String
    let packagePrice: Decimal
    let packageQuantity: Decimal
    let packageUnit: String
    let reviewed: Bool
}

struct WeeklyMealPricingResource: Codable, Hashable, Sendable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let pricingVersion: Int
    let currencyCode: String
    let pricingRegion: String?
    let snapshotDate: LocalCalendarDate?
    let staleAfterDays: Int?
    let prices: [WeeklyMealPriceRecord]
}

enum WeeklyMealPricingResourceDecoder {
    static func decode(_ data: Data) throws -> WeeklyMealPricingResource {
        try JSONDecoder().decode(WeeklyMealPricingResource.self, from: data)
    }
}

enum WeeklyMealCostEstimator {
    static func estimate(
        recipe: CuratedRecipeRecord,
        pricing: WeeklyMealPricingResource,
        includedOptionalIngredientIDs: Set<String> = [],
        asOf date: LocalCalendarDate? = nil,
        calendar: Calendar? = nil
    ) -> RecipeCostEstimate {
        var includedIDs: [String] = []
        var excludedIDs: [String] = []
        var missingIDs: [String] = []
        var total: Decimal = 0

        guard pricing.schemaVersion == WeeklyMealPricingResource.supportedSchemaVersion,
              pricing.pricingVersion > 0,
              validCurrencyCode(pricing.currencyCode),
              !isStale(pricing: pricing, asOf: date, calendar: calendar) else {
            return unavailableEstimate(
                recipe: recipe,
                pricing: pricing,
                includedIDs: [],
                excludedIDs: recipe.ingredients.map(\.id),
                note: "Pricing resource is invalid, unsupported, or stale."
            )
        }

        let records = Dictionary(grouping: pricing.prices) { record in
            "\(record.recipeID.rawValue)|\(record.recipeContentVersion)|\(record.ingredientID)"
        }

        for ingredient in recipe.ingredients {
            if ingredient.isQualitative {
                excludedIDs.append(ingredient.id)
                continue
            }
            if ingredient.optionalPolicy == .excludedByDefault &&
                !includedOptionalIngredientIDs.contains(ingredient.id) {
                excludedIDs.append(ingredient.id)
                continue
            }
            guard let quantity = ingredient.quantity, quantity > 0 else {
                missingIDs.append(ingredient.id)
                continue
            }
            let lookupKey = "\(recipe.id.rawValue)|\(recipe.contentVersion)|\(ingredient.id)"
            guard let matches = records[lookupKey], matches.count == 1, let record = matches.first,
                  record.reviewed, record.packagePrice >= 0, record.packageQuantity > 0,
                  !record.pricingKey.isEmpty else {
                missingIDs.append(ingredient.id)
                continue
            }
            guard let usedPackageFraction = packageFraction(
                quantity: quantity,
                unit: ingredient.unit,
                packageQuantity: record.packageQuantity,
                packageUnit: record.packageUnit
            ) else {
                missingIDs.append(ingredient.id)
                continue
            }
            includedIDs.append(ingredient.id)
            total += usedPackageFraction * record.packagePrice
        }

        guard missingIDs.isEmpty, recipe.defaultServings > 0 else {
            return unavailableEstimate(
                recipe: recipe,
                pricing: pricing,
                includedIDs: includedIDs,
                excludedIDs: (excludedIDs + missingIDs).sorted(),
                note: "Missing reviewed price inputs for: \(missingIDs.sorted().joined(separator: ", "))."
            )
        }

        return RecipeCostEstimate(
            recipeID: recipe.id,
            recipeContentVersion: recipe.contentVersion,
            servingDefinition: recipe.servingDescription,
            totalRecipeCost: total,
            costPerServing: total / Decimal(recipe.defaultServings),
            costRangeMinimumPerServing: nil,
            costRangeMaximumPerServing: nil,
            currencyCode: pricing.currencyCode,
            basis: .proportionalIngredientValue,
            status: .calculated,
            pricingRegion: pricing.pricingRegion,
            priceSnapshotDate: pricing.snapshotDate,
            pricingVersion: pricing.pricingVersion,
            includedIngredientIDs: includedIDs.sorted(),
            excludedIngredientIDs: excludedIDs.sorted(),
            notes: excludedIDs.isEmpty ? nil : "Qualitative or excluded-by-default optional ingredients are omitted."
        )
    }

    private static func unavailableEstimate(
        recipe: CuratedRecipeRecord,
        pricing: WeeklyMealPricingResource,
        includedIDs: [String],
        excludedIDs: [String],
        note: String
    ) -> RecipeCostEstimate {
        RecipeCostEstimate(
            recipeID: recipe.id,
            recipeContentVersion: recipe.contentVersion,
            servingDefinition: recipe.servingDescription,
            totalRecipeCost: nil,
            costPerServing: nil,
            costRangeMinimumPerServing: nil,
            costRangeMaximumPerServing: nil,
            currencyCode: pricing.currencyCode,
            basis: .proportionalIngredientValue,
            status: .requiresVerification,
            pricingRegion: pricing.pricingRegion,
            priceSnapshotDate: pricing.snapshotDate,
            pricingVersion: pricing.pricingVersion,
            includedIngredientIDs: includedIDs.sorted(),
            excludedIngredientIDs: excludedIDs.sorted(),
            notes: note
        )
    }

    private static func packageFraction(
        quantity: Decimal,
        unit: String,
        packageQuantity: Decimal,
        packageUnit: String
    ) -> Decimal? {
        switch QuantityEngine.convertedValue(value: quantity, from: unit, to: packageUnit) {
        case .exact(let converted), .estimated(let converted, _):
            return converted.value / packageQuantity
        case .incompatibleDimensions, .missingUnit, .unsupportedConversion:
            return nil
        }
    }

    private static func validCurrencyCode(_ code: String) -> Bool {
        code.count == 3 && code == code.uppercased() && code.allSatisfy { $0.isASCII && $0.isLetter }
    }

    private static func isStale(
        pricing: WeeklyMealPricingResource,
        asOf date: LocalCalendarDate?,
        calendar: Calendar?
    ) -> Bool {
        guard let snapshot = pricing.snapshotDate,
              let staleAfterDays = pricing.staleAfterDays,
              let date,
              let calendar,
              let snapshotDate = snapshot.date(in: calendar),
              let comparisonDate = date.date(in: calendar),
              let staleDate = calendar.date(byAdding: .day, value: staleAfterDays, to: snapshotDate) else {
            return false
        }
        return comparisonDate >= staleDate
    }
}

enum WeeklyMealCostFormatter {
    static func string(for estimate: RecipeCostEstimate, locale: Locale = .current) -> String? {
        guard estimate.isPubliclyDisplayable, let amount = estimate.costPerServing else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = estimate.currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        guard let formatted = formatter.string(from: amount as NSDecimalNumber) else { return nil }
        return "Est. \(formatted) per serving"
    }
}
