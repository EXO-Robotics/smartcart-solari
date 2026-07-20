import Foundation

enum PantryMatchingService {
    static func convertedQuantity(_ quantity: Double, from source: String, to destination: String) -> Double? {
        convert(quantity, from: source, to: destination)
    }

    static func bestSuggestion(
        for ingredient: Ingredient,
        requiredQuantity: Double? = nil,
        inventory: [PantryInventoryItem]
    ) -> PantrySuggestion? {
        let ingredientTokens = tokens(for: ingredient.name)
        guard !ingredientTokens.isEmpty else { return nil }

        let candidates = inventory.compactMap { item -> PantrySuggestion? in
            guard item.requiresUserNaming != true else { return nil }
            let itemTokens = tokens(for: item.name + " " + item.brand)
            let score = matchScore(ingredientTokens, itemTokens)
            guard score >= 0.62 else { return nil }

            let requested = max(0, requiredQuantity ?? ingredient.quantity)
            let stockQuantity = max(0, item.remainingAmount)
            let stockUnit = item.remainingUnit
            let converted = convert(stockQuantity, from: stockUnit, to: ingredient.unit)
            let coverage: PantryCoverage
            let available: Double

            if item.hasUnknownPackageMass == true {
                // Package count is useful display information, but it is not
                // an exact mass. Keep it review-only even if a future caller
                // happens to request a superficially compatible unit.
                available = stockQuantity
                coverage = .possible
            } else if let converted {
                available = converted
                coverage = converted + 0.0001 >= requested ? .full : .partial
            } else {
                available = stockQuantity
                coverage = .possible
            }

            return PantrySuggestion(
                pantryItemID: item.id,
                pantryItemName: item.name,
                coverage: coverage,
                availableQuantity: available,
                availableUnit: converted == nil ? stockUnit : ingredient.unit,
                requiredQuantity: requested,
                requiredUnit: ingredient.unit,
                matchScore: score
            )
        }

        return candidates.max {
            if $0.matchScore == $1.matchScore {
                return coverageRank($0.coverage) < coverageRank($1.coverage)
            }
            return $0.matchScore < $1.matchScore
        }
    }

    static func quantityToBuy(
        for ingredient: Ingredient,
        requiredQuantity: Double
    ) -> Double {
        guard ingredient.includeInList,
              ingredient.pantryState != .exclude,
              ingredient.pantryState != .haveEnough else { return 0 }
        guard ingredient.pantryDecision == .useAvailable,
              let suggestion = ingredient.pantrySuggestion else { return requiredQuantity }

        switch suggestion.coverage {
        case .full:
            return 0
        case .possible:
            // Cross-domain or otherwise unmeasured pantry stock cannot safely
            // reduce an exact shopping quantity.
            return requiredQuantity
        case .partial:
            return max(0, requiredQuantity - suggestion.availableQuantity)
        }
    }

    private static func tokens(for value: String) -> Set<String> {
        let stopWords: Set<String> = [
            "and", "the", "a", "an", "of", "fresh", "organic", "great", "value",
            "brand", "bag", "bottle", "box", "can", "jar", "package", "pkg"
        ]
        let normalized = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(singularized)
            .filter { !stopWords.contains($0) }
        return Set(normalized)
    }

    private static func singularized(_ token: String) -> String {
        if token.hasSuffix("ies"), token.count > 4 { return String(token.dropLast(3)) + "y" }
        if token.hasSuffix("es"), token.count > 4 { return String(token.dropLast(2)) }
        if token.hasSuffix("s"), !token.hasSuffix("ss"), token.count > 3 { return String(token.dropLast()) }
        return token
    }

    private static func matchScore(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let intersection = lhs.intersection(rhs)
        guard !intersection.isEmpty else { return 0 }
        if lhs == rhs || lhs.isSubset(of: rhs) || rhs.isSubset(of: lhs) { return 1 }
        return Double(intersection.count) / Double(lhs.union(rhs).count)
    }

    private static func coverageRank(_ value: PantryCoverage) -> Int {
        switch value {
        case .full: 3
        case .partial: 2
        case .possible: 1
        }
    }

    private static func convert(_ quantity: Double, from source: String, to destination: String) -> Double? {
        let sourceKey = canonicalUnit(source)
        let destinationKey = canonicalUnit(destination)
        if sourceKey == destinationKey { return quantity }
        guard let sourceMeasure = unitDefinition(sourceKey),
              let destinationMeasure = unitDefinition(destinationKey),
              sourceMeasure.dimension == destinationMeasure.dimension else { return nil }
        return quantity * sourceMeasure.baseMultiplier / destinationMeasure.baseMultiplier
    }

    private static func canonicalUnit(_ raw: String) -> String {
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases: [String: String] = [
            "tablespoon": "tbsp", "tablespoons": "tbsp", "tbs": "tbsp",
            "teaspoon": "tsp", "teaspoons": "tsp",
            "cups": "cup", "c": "cup", "fluid ounce": "fl oz", "fluid ounces": "fl oz",
            "ounces": "oz", "ounce": "oz", "pounds": "lb", "pound": "lb", "lbs": "lb",
            "grams": "g", "gram": "g", "kilograms": "kg", "kilogram": "kg",
            "milliliters": "ml", "milliliter": "ml", "liters": "l", "liter": "l",
            "items": "item", "count": "item", "each": "item"
        ]
        return aliases[key] ?? key
    }

    private static func unitDefinition(_ unit: String) -> (dimension: String, baseMultiplier: Double)? {
        switch unit {
        case "tsp": ("volume", 4.92892)
        case "tbsp": ("volume", 14.7868)
        case "fl oz": ("volume", 29.5735)
        case "cup": ("volume", 236.588)
        case "ml": ("volume", 1)
        case "l": ("volume", 1000)
        case "g": ("mass", 1)
        case "kg": ("mass", 1000)
        case "oz": ("mass", 28.3495)
        case "lb": ("mass", 453.592)
        case "item", "", "clove", "cloves", "egg", "eggs": ("count", 1)
        default: nil
        }
    }
}
