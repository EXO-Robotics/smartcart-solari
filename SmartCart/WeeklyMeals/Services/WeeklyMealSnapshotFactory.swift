import CryptoKit
import Foundation

enum WeeklyMealSnapshotFactoryError: Error, Equatable {
    case invalidServings
}

struct WeeklyMealSnapshotFactory {
    func makeSnapshot(
        collectionID: String,
        recipe: CuratedRecipeRecord,
        targetServings: Int,
        includedOptionalIngredientIDs: Set<String> = []
    ) throws -> Recipe {
        guard targetServings > 0 else { throw WeeklyMealSnapshotFactoryError.invalidServings }
        let scale = Decimal(targetServings) / Decimal(recipe.defaultServings)
        let ingredients = recipe.ingredients.map { ingredient in
            makeIngredient(
                ingredient,
                recipe: recipe,
                scale: scale,
                includedOptionalIngredientIDs: includedOptionalIngredientIDs
            )
        }

        return Recipe(
            id: stableUUID("recipe|\(recipe.id.rawValue)|v\(recipe.contentVersion)"),
            title: recipe.title,
            source: .sample,
            sourceDetail: "Weekly Meals · \(collectionID) · \(recipe.id.rawValue) · version \(recipe.contentVersion)",
            heroSymbol: recipe.metadata.mealTypes.first?.symbolName ?? "fork.knife",
            servings: targetServings,
            prepMinutes: recipe.metadata.prepMinutes,
            cookMinutes: recipe.metadata.cookMinutes,
            ingredients: ingredients,
            rawSourceText: frozenSourceText(collectionID: collectionID, recipe: recipe),
            sourceDocument: nil
        )
    }

    private func makeIngredient(
        _ ingredient: CuratedIngredient,
        recipe: CuratedRecipeRecord,
        scale: Decimal,
        includedOptionalIngredientIDs: Set<String>
    ) -> Ingredient {
        let isExcludedOptional = ingredient.optionalPolicy == .excludedByDefault &&
            !includedOptionalIngredientIDs.contains(ingredient.id)
        let scaledQuantity = ingredient.quantity.map { NSDecimalNumber(decimal: $0 * scale).doubleValue } ?? 1
        return Ingredient(
            id: stableUUID("ingredient|\(recipe.id.rawValue)|v\(recipe.contentVersion)|\(ingredient.id)"),
            rawText: ingredient.rawText,
            name: ingredient.name,
            quantity: scaledQuantity,
            unit: ingredient.unit,
            preparation: ingredient.preparation,
            category: groceryCategory(ingredient.category),
            confidence: .high,
            includeInList: !isExcludedOptional,
            pantryState: isExcludedOptional ? .exclude : (ingredient.isQualitative ? .alwaysAsk : .needToBuy),
            preferenceNote: isExcludedOptional ? "Optional ingredient excluded by default" : "",
            sourceEvidence: IngredientSourceEvidence(
                rawText: ingredient.rawText,
                pageIndex: nil,
                boundingBox: nil,
                extractionStrategy: .sample,
                ocrConfidence: nil,
                layoutConfidence: nil,
                parserConfidence: 1,
                normalizationConfidence: 1,
                alternateQuantityCandidates: [],
                originalLine: ingredient.rawText
            ),
            quantityReviewRequired: false
        )
    }

    private func frozenSourceText(
        collectionID: String,
        recipe: CuratedRecipeRecord
    ) -> String {
        let ingredients = recipe.ingredients.map { "• \($0.rawText)" }.joined(separator: "\n")
        let instructions = recipe.instructions.map { "\($0.id). \($0.text)" }.joined(separator: "\n")
        let nutrition = recipe.metadata.nutrition.map {
            "Calories per serving: \($0.caloriesPerServing); protein grams per serving: \($0.proteinGramsPerServing); status: \($0.verificationStatus.rawValue); version: \($0.nutritionVersion)"
        } ?? "Not supplied"
        let cost = recipe.metadata.costEstimate.map {
            "Status: \($0.status.rawValue); basis: \($0.basis.rawValue); currency: \($0.currencyCode); pricing version: \($0.pricingVersion)"
        } ?? "Not supplied"
        let tags = recipe.metadata.merchandisingTags.map(\.rawValue).joined(separator: ", ")
        let claims = recipe.metadata.verifiedDietaryClaims.map {
            "\($0.claim.rawValue):\($0.applicability.rawValue):v\($0.verificationVersion)"
        }.joined(separator: ", ")
        let exclusions = recipe.metadata.baseNutritionExcludes?.joined(separator: ", ") ?? "None"
        return """
        Weekly Meals frozen snapshot
        Collection: \(collectionID)
        Recipe ID: \(recipe.id.rawValue)
        Content version: \(recipe.contentVersion)
        Serves: \(recipe.defaultServings) (\(recipe.servingDescription))
        Prep minutes: \(recipe.metadata.prepMinutes)
        Cook minutes: \(recipe.metadata.cookMinutes)
        Passive minutes: \(recipe.metadata.passiveMinutes)
        Nutrition: \(nutrition)
        Recipe cost: \(cost)
        Merchandising tags: \(tags)
        Verified dietary claims: \(claims.isEmpty ? "None" : claims)
        Base nutrition excludes: \(exclusions)

        Ingredients
        \(ingredients)

        Instructions
        \(instructions)
        """
    }

    private func groceryCategory(_ value: String) -> GroceryCategory {
        switch value.lowercased() {
        case "produce": .produce
        case "dairy": .dairy
        case "meat", "meat & seafood": .meat
        case "bakery": .bakery
        case "frozen": .frozen
        default: .pantry
        }
    }

    private func stableUUID(_ value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
