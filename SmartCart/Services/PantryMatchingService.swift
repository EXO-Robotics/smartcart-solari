import Foundation

enum RecipeQuantityUnitNormalizer {
    static func quantityEngineUnit(
        for raw: String,
        blankMeansCount: Bool = true
    ) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return blankMeansCount ? "count" : normalized
        }
        switch normalized.lowercased() {
        case "clove", "cloves", "egg", "eggs":
            return "count"
        default:
            return normalized
        }
    }
}

enum PantryMatchingService {
    /// A small, conservative inference list lets previously scanned pantry
    /// products participate immediately. Users can override the inferred value
    /// with `preferredIngredientName` in Pantry.
    private static let inferredIngredientNames = ["coffee", "espresso", "tea"]
    private static let inferenceBlockingWords = [
        "candy", "creamer", "flavor", "flavored", "syrup"
    ]

    static func recipeIngredientName(for item: PantryInventoryItem) -> String? {
        guard item.isRecipeFavorite != false else { return nil }
        if let explicit = item.preferredIngredientName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }

        let searchable = normalizedWords("\(item.brand) \(item.name)")
        guard !searchable.isEmpty,
              !inferenceBlockingWords.contains(where: { searchable.contains(" \($0) ") }) else {
            return nil
        }
        return inferredIngredientNames.first { candidate in
            let phrase = normalizedWords(candidate)
            return searchable.range(of: phrase) != nil
        }
    }

    static func preferredProductDisplayName(for item: PantryInventoryItem) -> String {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let brand = item.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brand.isEmpty else { return name }
        guard name.range(of: brand, options: [.caseInsensitive, .diacriticInsensitive]) == nil else {
            return name
        }
        return "\(brand) \(name)"
    }

    static func preferredProduct(
        for ingredient: Ingredient,
        inventory: [PantryInventoryItem]
    ) -> PantryInventoryItem? {
        guard ingredient.brandNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            // An explicitly branded recipe remains authoritative.
            return nil
        }

        let candidates = inventory.filter { item in
            guard item.requiresUserNaming != true,
                  let preferredIngredientName = recipeIngredientName(for: item) else { return false }
            return IngredientIdentityService.relationship(
                between: ingredient.name,
                and: preferredIngredientName,
                lhsPreparation: ingredient.preparation
            ) == .exact
        }

        return candidates.sorted { first, second in
            let firstIsExplicit = first.isRecipeFavorite == true
            let secondIsExplicit = second.isRecipeFavorite == true
            if firstIsExplicit != secondIsExplicit { return firstIsExplicit }
            if first.updatedAt != second.updatedAt { return first.updatedAt > second.updatedAt }
            return first.id.uuidString < second.id.uuidString
        }.first
    }

    static func convertedQuantity(
        _ quantity: Double,
        from source: String,
        to destination: String,
        sourceBlankMeansIngredientCount: Bool = false,
        destinationBlankMeansIngredientCount: Bool = false
    ) -> Double? {
        guard case .exact(let converted) = QuantityEngine.convertedValue(
            doubleValue: quantity,
            from: RecipeQuantityUnitNormalizer.quantityEngineUnit(
                for: source,
                blankMeansCount: sourceBlankMeansIngredientCount
            ),
            to: RecipeQuantityUnitNormalizer.quantityEngineUnit(
                for: destination,
                blankMeansCount: destinationBlankMeansIngredientCount
            )
        ) else { return nil }
        let value = NSDecimalNumber(decimal: converted.value).doubleValue
        return value.isFinite ? value : nil
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
            let explicitIngredientName = item.preferredIngredientName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let pantryIngredientName: String
            if let explicitIngredientName, !explicitIngredientName.isEmpty {
                pantryIngredientName = explicitIngredientName
            } else {
                pantryIngredientName = item.name
            }
            let relationship = IngredientIdentityService.relationship(
                between: ingredient.name,
                and: pantryIngredientName,
                lhsPreparation: ingredient.preparation
            )
            guard relationship != .incompatible else { return nil }

            let itemTokens = tokens(for: pantryIngredientName)
            let tokenScore = matchScore(ingredientTokens, itemTokens)
            let score = relationship == .exact ? 1 : tokenScore
            guard score >= 0.62 else { return nil }

            let requested = max(0, requiredQuantity ?? ingredient.quantity)
            let stockQuantity = max(0, item.remainingAmount)
            let stockUnit = item.remainingUnit
            let converted = convertedQuantity(
                stockQuantity,
                from: stockUnit,
                to: ingredient.unit,
                destinationBlankMeansIngredientCount: true
            )
            let coverage: PantryCoverage
            let available: Double

            if relationship != .exact {
                available = converted ?? stockQuantity
                coverage = .possible
            } else if item.hasUnknownPackageMass == true {
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

    private static func normalizedWords(_ value: String) -> String {
        let words = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return " \(words.joined(separator: " ")) "
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
        if lhs == rhs { return 1 }
        return Double(intersection.count) / Double(lhs.union(rhs).count)
    }

    private static func coverageRank(_ value: PantryCoverage) -> Int {
        switch value {
        case .full: 3
        case .partial: 2
        case .possible: 1
        }
    }

}
