import Foundation

enum TripIntelligenceModelAdapterError: Error, Equatable {
    case invalidNumericQuantity(ingredientID: UUID)
    case unsupportedSemanticQuantity(ingredientID: UUID, value: String)
}

extension IngredientInputDTO {
    init(
        ingredient: Ingredient,
        includedInRecipe: Bool,
        includeInTrip: Bool
    ) throws {
        let semantic = ingredient.semanticQuantity?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let quantity: IngredientQuantityInputDTO?

        if let semantic, !semantic.isEmpty {
            guard ["as needed", "to taste", "for frying"].contains(semantic) else {
                throw TripIntelligenceModelAdapterError.unsupportedSemanticQuantity(
                    ingredientID: ingredient.id,
                    value: semantic
                )
            }
            quantity = .semantic(semantic)
        } else if ingredient.quantity > 0, ingredient.quantity.isFinite {
            quantity = .numeric(
                value: Decimal(ingredient.quantity),
                minimumValue: ingredient.quantityLowerBound.map { Decimal($0) },
                unit: ingredient.unit
            )
        } else if ingredient.quantity == 0,
                  ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            quantity = nil
        } else {
            throw TripIntelligenceModelAdapterError.invalidNumericQuantity(
                ingredientID: ingredient.id
            )
        }

        let sourceName = ingredient.sourceEvidence
            .map { "SmartCart \($0.extractionStrategy.rawValue)" }
            ?? "SmartCart reviewed ingredient"
        let sourceDescription = ingredient.sourceEvidence == nil
            ? "Reviewed ingredient text supplied by the user."
            : "Reviewed ingredient text retained without transporting source image bytes."

        self.init(
            ingredientId: ingredient.id,
            sourceText: ingredient.rawText,
            name: ingredient.name,
            preparation: ingredient.preparation,
            quantity: quantity,
            includedInRecipe: includedInRecipe,
            includeInTrip: includeInTrip,
            brandPreference: ingredient.preferredProductName ?? ingredient.brandNote,
            evidence: [
                ResolutionEvidenceDTO(
                    evidenceId: "ingredient-\(ingredient.id.uuidString.lowercased())",
                    kind: .sourceText,
                    sourceName: sourceName,
                    sourceVersion: nil,
                    sourceRecordId: ingredient.sourceEvidence?
                        .sourceCropReference?
                        .sha256,
                    description: sourceDescription
                )
            ]
        )
    }
}

extension RecipeNutritionRequestDataDTO {
    init(
        recipe: Recipe,
        includedIngredientIDs: Set<UUID>,
        shoppingIngredientIDs: Set<UUID>
    ) throws {
        recipeId = recipe.id
        title = recipe.title
        servings = Decimal(recipe.servings)
        ingredients = try recipe.ingredients.map { ingredient in
            try IngredientInputDTO(
                ingredient: ingredient,
                includedInRecipe: includedIngredientIDs.contains(ingredient.id),
                includeInTrip: shoppingIngredientIDs.contains(ingredient.id)
            )
        }
    }
}
