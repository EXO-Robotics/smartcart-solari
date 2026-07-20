import Foundation

enum MealPrepAggregationService {
    static func aggregate(
        draft: MealPrepDraft,
        pantryInventory: [PantryInventoryItem] = []
    ) throws -> MealPrepAggregationResult {
        try aggregate(
            selections: draft.selections,
            scope: draft.shoppingScope,
            pantryInventory: pantryInventory
        )
    }

    static func aggregate(
        selections: [MealPrepSelection],
        scope: ShoppingScope,
        pantryInventory: [PantryInventoryItem] = []
    ) throws -> MealPrepAggregationResult {
        guard !selections.isEmpty else { throw MealPrepAggregationError.emptySelection }
        guard selections.count <= MealPrepDraft.selectionLimit else {
            throw MealPrepAggregationError.tooManySelections(maximum: MealPrepDraft.selectionLimit)
        }

        var pending: [PendingLine] = []
        for selection in selections {
            guard selection.targetServings > 0,
                  selection.recipeSnapshot.originalServings > 0 else {
                throw MealPrepAggregationError.invalidServings(selectionID: selection.id)
            }

            for ingredient in selection.recipeSnapshot.ingredients
            where ingredient.includeInList && ingredient.pantryState != .exclude {
                let variants = alternativeVariants(for: ingredient)
                for variant in variants {
                    let descriptor = descriptor(for: variant)
                    let source = CombinedIngredientSource(
                        selectionID: selection.id,
                        recipeID: selection.recipeSnapshot.id,
                        recipeTitle: selection.recipeSnapshot.title,
                        ingredient: variant,
                        servingScale: selection.servingScale,
                        scaledQuantity: max(0, variant.quantity * selection.servingScale),
                        variantKey: variants.count > 1 ? normalized(variant.name) : nil
                    )
                    let candidate = PendingLine(
                        descriptor: descriptor,
                        unit: unit(for: variant.unit),
                        category: variant.category,
                        source: source
                    )

                    if let index = pending.firstIndex(where: { canAutomaticallyMerge($0, candidate) }) {
                        let converted = convert(
                            candidate.quantity,
                            from: candidate.unit,
                            to: pending[index].unit
                        )!
                        pending[index].quantity += converted
                        pending[index].sources.append(source)
                        pending[index].state = .automaticallyMerged
                    } else {
                        pending.append(candidate)
                    }
                }
            }
        }

        markUncertainDuplicates(in: &pending)
        var lines = pending.map(makeCombinedLine)
        recomputePantry(pantryInventory, for: &lines)
        return MealPrepAggregationResult(scope: scope, lines: lines)
    }

    static func canonicalUnit(_ raw: String) -> MealPrepUnit {
        unit(for: raw)
    }

    static func convertedQuantity(
        _ quantity: Double,
        from source: MealPrepUnit,
        to destination: MealPrepUnit
    ) -> Double? {
        convert(quantity, from: source, to: destination)
    }

    static func recomputePantry(
        _ inventory: [PantryInventoryItem],
        for lines: inout [CombinedIngredientLine]
    ) {
        for index in lines.indices {
            lines[index].pantryDeductions = []
            switch lines[index].mergeReviewState {
            case .excludedAlternative, .deferredAlternative:
                lines[index].quantityToBuy = 0
            default:
                lines[index].quantityToBuy = lines[index].quantity
            }
        }
        applyPantry(inventory, to: &lines)
    }
}

private extension MealPrepAggregationService {
    struct IngredientDescriptor: Hashable {
        var displayName: String
        var canonicalName: String
        var duplicateBase: String
        var brand: String
        var subtype: String
        var productPreparation: String
        var alternativeGroup: String
        var quantityIsUncertain: Bool
    }

    struct PendingLine {
        var descriptor: IngredientDescriptor
        var unit: MealPrepUnit
        var category: GroceryCategory
        var sources: [CombinedIngredientSource]
        var quantity: Double
        var state: MergeReviewState
        var reasons: Set<MergeReviewReason>
        var uncertainDuplicateGroup: String?

        init(
            descriptor: IngredientDescriptor,
            unit: MealPrepUnit,
            category: GroceryCategory,
            source: CombinedIngredientSource
        ) {
            self.descriptor = descriptor
            self.unit = unit
            self.category = category
            sources = [source]
            quantity = source.scaledQuantity
            uncertainDuplicateGroup = nil

            if !descriptor.alternativeGroup.isEmpty {
                state = .alternativeChoice
                reasons = [.alternative]
            } else if descriptor.quantityIsUncertain {
                state = .reviewRequired
                reasons = [.uncertainQuantity]
            } else {
                state = .notNeeded
                reasons = []
            }
        }
    }

    static func canAutomaticallyMerge(_ lhs: PendingLine, _ rhs: PendingLine) -> Bool {
        let left = lhs.descriptor
        let right = rhs.descriptor
        guard left.alternativeGroup.isEmpty,
              right.alternativeGroup.isEmpty,
              !left.quantityIsUncertain,
              !right.quantityIsUncertain,
              left.canonicalName == right.canonicalName,
              left.brand == right.brand,
              left.subtype == right.subtype,
              left.productPreparation == right.productPreparation else { return false }
        return convert(rhs.quantity, from: rhs.unit, to: lhs.unit) != nil
    }

    static func makeCombinedLine(_ pending: PendingLine) -> CombinedIngredientLine {
        let sourceIDs = pending.sources.map(\.id).sorted().joined(separator: "|")
        return CombinedIngredientLine(
            id: "meal-prep-line:\(sourceIDs)",
            shoppingItemID: UUID(),
            name: pending.descriptor.displayName,
            canonicalName: pending.descriptor.canonicalName,
            quantity: pending.quantity,
            unit: pending.unit,
            category: pending.category,
            sources: pending.sources,
            mergeReviewState: pending.state,
            mergeReviewReasons: pending.reasons,
            uncertainDuplicateGroup: pending.uncertainDuplicateGroup,
            pantryDeductions: [],
            quantityToBuy: pending.quantity
        )
    }

    static func markUncertainDuplicates(in lines: inout [PendingLine]) {
        var groups: [String: [Int]] = [:]
        for index in lines.indices {
            let descriptor = lines[index].descriptor
            let key = descriptor.alternativeGroup.isEmpty
                ? "ingredient:\(descriptor.duplicateBase)"
                : "alternative:\(normalized(descriptor.alternativeGroup))"
            groups[key, default: []].append(index)
        }

        for (key, indices) in groups
        where indices.count > 1 || key.hasPrefix("alternative:") {
            for index in indices {
                let descriptor = lines[index].descriptor
                lines[index].uncertainDuplicateGroup = key
                if !descriptor.alternativeGroup.isEmpty {
                    lines[index].state = .alternativeChoice
                    lines[index].reasons.insert(.alternative)
                    continue
                }
                lines[index].state = .reviewRequired
                let peers = indices.filter { $0 != index }.map { lines[$0] }
                if peers.contains(where: { $0.descriptor.subtype != descriptor.subtype }) {
                    lines[index].reasons.insert(.subtype)
                }
                if peers.contains(where: { $0.descriptor.brand != descriptor.brand }) {
                    lines[index].reasons.insert(.brand)
                }
                if peers.contains(where: { $0.descriptor.productPreparation != descriptor.productPreparation }) {
                    lines[index].reasons.insert(.productChangingPreparation)
                }
                if peers.contains(where: { convert($0.quantity, from: $0.unit, to: lines[index].unit) == nil }) {
                    lines[index].reasons.insert(.incompatibleUnit)
                }
            }
        }
    }

    static func applyPantry(_ inventory: [PantryInventoryItem], to lines: inout [CombinedIngredientLine]) {
        var remaining = Dictionary(uniqueKeysWithValues: inventory.map { ($0.id, max(0, $0.remainingAmount)) })

        for lineIndex in lines.indices {
            guard lines[lineIndex].mergeReviewState != .alternativeChoice,
                  lines[lineIndex].mergeReviewState != .excludedAlternative,
                  lines[lineIndex].mergeReviewState != .deferredAlternative,
                  !lines[lineIndex].mergeReviewReasons.contains(.uncertainQuantity) else { continue }
            var needed = lines[lineIndex].quantity
            var candidateRemaining = remaining

            for item in inventory where needed > 0.000_001 {
                guard let available = candidateRemaining[item.id], available > 0,
                      pantryItem(item, isSafeFor: lines[lineIndex]),
                      let convertedAvailable = convert(
                        available,
                        from: unit(for: item.remainingUnit),
                        to: lines[lineIndex].unit
                      ) else { continue }

                let probe = Ingredient(
                    name: lines[lineIndex].name,
                    quantity: needed,
                    unit: lines[lineIndex].unit.symbol,
                    category: lines[lineIndex].category
                )
                var itemProbe = item
                itemProbe.remainingAmount = available
                guard let suggestion = PantryMatchingService.bestSuggestion(
                    for: probe,
                    requiredQuantity: needed,
                    inventory: [itemProbe]
                ), suggestion.coverage != .possible else { continue }

                let applied = min(needed, convertedAvailable)
                guard applied > 0 else { continue }
                let consumedInPantryUnit = convert(
                    applied,
                    from: lines[lineIndex].unit,
                    to: unit(for: item.remainingUnit)
                )!
                candidateRemaining[item.id] = max(0, available - consumedInPantryUnit)
                needed -= applied
                lines[lineIndex].pantryDeductions.append(
                    PantryIngredientDeduction(
                        pantryItemID: item.id,
                        pantryItemName: item.name,
                        quantity: applied,
                        unit: lines[lineIndex].unit.symbol
                    )
                )
            }
            if lines[lineIndex].isBuyingFullQuantity {
                lines[lineIndex].quantityToBuy = lines[lineIndex].quantity
            } else {
                remaining = candidateRemaining
                lines[lineIndex].quantityToBuy = max(0, needed)
            }
        }
    }

    static func pantryItem(_ item: PantryInventoryItem, isSafeFor line: CombinedIngredientLine) -> Bool {
        guard item.requiresUserNaming != true else { return false }
        let pantryDescriptor = descriptor(name: item.name, preparation: "", brand: item.brand)

        let sourceDescriptors = line.sources.map {
            descriptor(
                name: $0.ingredient.name,
                preparation: $0.ingredient.preparation,
                brand: $0.ingredient.brandNote ?? ""
            )
        }
        guard sourceDescriptors.allSatisfy({ source in
            (source.subtype.isEmpty || source.subtype == pantryDescriptor.subtype)
                && (source.productPreparation.isEmpty || source.productPreparation == pantryDescriptor.productPreparation)
                && (source.brand.isEmpty || source.brand == pantryDescriptor.brand)
        }) else { return false }

        return convert(
            item.remainingAmount,
            from: unit(for: item.remainingUnit),
            to: line.unit
        ) != nil
    }

    static func descriptor(for ingredient: FrozenMealPrepIngredient) -> IngredientDescriptor {
        var result = descriptor(
            name: ingredient.name,
            preparation: ingredient.preparation,
            brand: ingredient.brandNote ?? ""
        )
        result.alternativeGroup = normalized(ingredient.alternativeGroup ?? "")
        result.quantityIsUncertain = ingredient.quantityReviewRequired || ingredient.confidence == .unknown
        return result
    }

    static func alternativeVariants(
        for ingredient: FrozenMealPrepIngredient
    ) -> [FrozenMealPrepIngredient] {
        guard ingredient.alternativeGroup?.isEmpty == false else { return [ingredient] }
        let separated = ingredient.name.replacingOccurrences(
            of: #"(?i)\s+or\s+"#,
            with: "\u{001F}",
            options: .regularExpression
        )
        let names = separated
            .components(separatedBy: "\u{001F}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard names.count > 1 else { return [ingredient] }
        return names.map { name in
            var variant = ingredient
            variant.name = name
            return variant
        }
    }

    static func descriptor(name: String, preparation: String, brand: String) -> IngredientDescriptor {
        let normalizedName = canonicalIngredientName(name)
        let allTokens = Set((normalizedName + " " + normalized(preparation)).split(separator: " ").map(String.init))
        let subtypeTokens: Set<String> = [
            "red", "yellow", "white", "sweet", "green", "pearl", "vidalia",
            "salted", "unsalted", "european", "vegan", "whole", "skim",
            "lowfat", "boneless", "skinless", "bone-in", "skin-on"
        ]
        let preparationTokens: Set<String> = [
            "cooked", "uncooked", "raw", "dried", "sun-dried", "fresh", "frozen", "canned",
            "clarified", "smoked", "pickled", "roasted"
        ]
        let subtype = allTokens.intersection(subtypeTokens).sorted().joined(separator: " ")
        let productPreparation = allTokens.intersection(preparationTokens).sorted().joined(separator: " ")
        let removable = subtypeTokens.union(preparationTokens)
        let duplicateBase = normalizedName.split(separator: " ")
            .map(String.init)
            .filter { !removable.contains($0) }
            .joined(separator: " ")

        return IngredientDescriptor(
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            canonicalName: normalizedName,
            duplicateBase: duplicateBase,
            brand: normalized(brand),
            subtype: subtype,
            productPreparation: productPreparation,
            alternativeGroup: "",
            quantityIsUncertain: false
        )
    }

    static func canonicalIngredientName(_ raw: String) -> String {
        let aliases: [String: String] = [
            "scallion": "green onion",
            "green onion": "green onion",
            "confectioner sugar": "powdered sugar",
            "confectioners sugar": "powdered sugar",
            "icing sugar": "powdered sugar",
            "garbanzo bean": "chickpea"
        ]
        let value = normalized(raw).split(separator: " ").map { singularized(String($0)) }.joined(separator: " ")
        return aliases[value] ?? value
    }

    static func normalized(_ raw: String) -> String {
        raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "-", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func singularized(_ token: String) -> String {
        let exceptions: [String: String] = [
            "cloves": "clove", "leaves": "leaf", "tomatoes": "tomato",
            "potatoes": "potato", "scallions": "scallion"
        ]
        if let exception = exceptions[token] { return exception }
        if token.hasSuffix("ies"), token.count > 4 { return String(token.dropLast(3)) + "y" }
        if token.hasSuffix("s"), !token.hasSuffix("ss"), token.count > 3 { return String(token.dropLast()) }
        return token
    }

    static func unit(for raw: String) -> MealPrepUnit {
        let key = normalized(raw)
        let aliases: [String: MealPrepUnit] = [
            "": MealPrepUnit(symbol: "count", family: .count),
            "count": MealPrepUnit(symbol: "count", family: .count),
            "counts": MealPrepUnit(symbol: "count", family: .count),
            "item": MealPrepUnit(symbol: "count", family: .count),
            "items": MealPrepUnit(symbol: "count", family: .count),
            "each": MealPrepUnit(symbol: "count", family: .count),
            "ea": MealPrepUnit(symbol: "count", family: .count),
            "piece": MealPrepUnit(symbol: "count", family: .count),
            "pieces": MealPrepUnit(symbol: "count", family: .count),
            "tsp": MealPrepUnit(symbol: "tsp", family: .usVolume),
            "teaspoon": MealPrepUnit(symbol: "tsp", family: .usVolume),
            "teaspoons": MealPrepUnit(symbol: "tsp", family: .usVolume),
            "tbsp": MealPrepUnit(symbol: "tbsp", family: .usVolume, baseMultiplier: 3),
            "tablespoon": MealPrepUnit(symbol: "tbsp", family: .usVolume, baseMultiplier: 3),
            "tablespoons": MealPrepUnit(symbol: "tbsp", family: .usVolume, baseMultiplier: 3),
            "tbs": MealPrepUnit(symbol: "tbsp", family: .usVolume, baseMultiplier: 3),
            "cup": MealPrepUnit(symbol: "cup", family: .usVolume, baseMultiplier: 48),
            "cups": MealPrepUnit(symbol: "cup", family: .usVolume, baseMultiplier: 48),
            "c": MealPrepUnit(symbol: "cup", family: .usVolume, baseMultiplier: 48),
            "fl oz": MealPrepUnit(symbol: "fl oz", family: .usVolume, baseMultiplier: 6),
            "fluid ounce": MealPrepUnit(symbol: "fl oz", family: .usVolume, baseMultiplier: 6),
            "fluid ounces": MealPrepUnit(symbol: "fl oz", family: .usVolume, baseMultiplier: 6),
            "oz": MealPrepUnit(symbol: "oz", family: .imperialMass),
            "ounce": MealPrepUnit(symbol: "oz", family: .imperialMass),
            "ounces": MealPrepUnit(symbol: "oz", family: .imperialMass),
            "lb": MealPrepUnit(symbol: "lb", family: .imperialMass, baseMultiplier: 16),
            "lbs": MealPrepUnit(symbol: "lb", family: .imperialMass, baseMultiplier: 16),
            "pound": MealPrepUnit(symbol: "lb", family: .imperialMass, baseMultiplier: 16),
            "pounds": MealPrepUnit(symbol: "lb", family: .imperialMass, baseMultiplier: 16),
            "g": MealPrepUnit(symbol: "g", family: .metricMass),
            "gram": MealPrepUnit(symbol: "g", family: .metricMass),
            "grams": MealPrepUnit(symbol: "g", family: .metricMass),
            "kg": MealPrepUnit(symbol: "kg", family: .metricMass, baseMultiplier: 1_000),
            "kilogram": MealPrepUnit(symbol: "kg", family: .metricMass, baseMultiplier: 1_000),
            "kilograms": MealPrepUnit(symbol: "kg", family: .metricMass, baseMultiplier: 1_000),
            "ml": MealPrepUnit(symbol: "ml", family: .metricVolume),
            "milliliter": MealPrepUnit(symbol: "ml", family: .metricVolume),
            "milliliters": MealPrepUnit(symbol: "ml", family: .metricVolume),
            "l": MealPrepUnit(symbol: "l", family: .metricVolume, baseMultiplier: 1_000),
            "liter": MealPrepUnit(symbol: "l", family: .metricVolume, baseMultiplier: 1_000),
            "liters": MealPrepUnit(symbol: "l", family: .metricVolume, baseMultiplier: 1_000)
        ]
        return aliases[key] ?? MealPrepUnit(symbol: key, family: .exactOnly)
    }

    static func convert(_ quantity: Double, from source: MealPrepUnit, to destination: MealPrepUnit) -> Double? {
        guard source.family == destination.family else { return nil }
        if source.family == .exactOnly, source.symbol != destination.symbol { return nil }
        return quantity * source.baseMultiplier / destination.baseMultiplier
    }
}
