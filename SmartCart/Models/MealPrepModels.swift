import Foundation

struct ShoppingScope: Hashable, Codable {
    enum Kind: String, Hashable, Codable {
        case singleRecipe
        case mealPrepBeta
    }

    var kind: Kind
    var identifier: UUID

    static func singleRecipe(_ recipeID: UUID) -> ShoppingScope {
        ShoppingScope(kind: .singleRecipe, identifier: recipeID)
    }

    static func mealPrep(_ draftID: UUID) -> ShoppingScope {
        ShoppingScope(kind: .mealPrepBeta, identifier: draftID)
    }

    /// Stable input for callers that hash or persist shopping-session identity.
    var fingerprintInput: String {
        "shopping-scope:v1:\(kind.rawValue):\(identifier.uuidString.lowercased())"
    }
}

struct FrozenMealPrepIngredient: Identifiable, Hashable, Codable {
    let id: UUID
    var rawText: String
    var name: String
    var quantity: Double
    var unit: String
    var preparation: String
    var category: GroceryCategory
    var confidence: IngredientConfidence
    var includeInList: Bool
    var pantryState: PantryState
    var preferenceNote: String
    var brandNote: String?
    var alternativeGroup: String?
    var quantityReviewRequired: Bool
    var preferredPantryItemID: UUID?
    var preferredProductName: String?

    init(ingredient: Ingredient) {
        id = ingredient.id
        rawText = ingredient.rawText
        name = ingredient.name
        quantity = ingredient.quantity
        unit = ingredient.unit
        preparation = ingredient.preparation
        category = ingredient.category
        confidence = ingredient.confidence
        includeInList = ingredient.includeInList
        pantryState = ingredient.pantryState
        preferenceNote = ingredient.preferenceNote
        brandNote = ingredient.brandNote
        alternativeGroup = ingredient.alternativeGroup
        quantityReviewRequired = ingredient.quantityReviewRequired == true
        preferredPantryItemID = ingredient.preferredPantryItemID
        preferredProductName = ingredient.preferredProductName
    }
}

struct FrozenMealPrepRecipe: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var originalServings: Int
    var ingredients: [FrozenMealPrepIngredient]

    init(recipe: Recipe) {
        id = recipe.id
        title = recipe.title
        originalServings = recipe.servings
        ingredients = recipe.ingredients.map(FrozenMealPrepIngredient.init)
    }
}

struct MealPrepSelection: Identifiable, Hashable, Codable {
    let id: UUID
    var recipeSnapshot: FrozenMealPrepRecipe
    var targetServings: Double

    init(
        id: UUID = UUID(),
        recipe: Recipe,
        targetServings: Double
    ) {
        self.id = id
        recipeSnapshot = FrozenMealPrepRecipe(recipe: recipe)
        self.targetServings = targetServings
    }

    init(id: UUID = UUID(), recipeSnapshot: FrozenMealPrepRecipe, targetServings: Double) {
        self.id = id
        self.recipeSnapshot = recipeSnapshot
        self.targetServings = targetServings
    }

    var servingScale: Double {
        guard recipeSnapshot.originalServings > 0 else { return 0 }
        return targetServings / Double(recipeSnapshot.originalServings)
    }
}

struct MealPrepDraft: Identifiable, Hashable, Codable {
    static let selectionLimit = 5

    let id: UUID
    var title: String
    var selections: [MealPrepSelection]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Weekly Meal Prep",
        selections: [MealPrepSelection] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.selections = selections
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var shoppingScope: ShoppingScope { .mealPrep(id) }

    mutating func addSelection(_ selection: MealPrepSelection) throws {
        guard selections.count < Self.selectionLimit else {
            throw MealPrepAggregationError.tooManySelections(maximum: Self.selectionLimit)
        }
        selections.append(selection)
        updatedAt = .now
    }
}

enum MealPrepUnitFamily: String, Hashable, Codable {
    case count
    case usVolume
    case imperialMass
    case metricMass
    case metricVolume
    case exactOnly
}

struct MealPrepUnit: Hashable, Codable {
    var symbol: String
    var family: MealPrepUnitFamily
    var baseMultiplier: Double

    init(symbol: String, family: MealPrepUnitFamily, baseMultiplier: Double = 1) {
        self.symbol = symbol
        self.family = family
        self.baseMultiplier = baseMultiplier
    }
}

enum MergeReviewState: String, Hashable, Codable {
    case notNeeded
    case automaticallyMerged
    case reviewRequired
    case alternativeChoice
    case confirmedSeparate
    case confirmedQuantity
    case selectedAlternative
    case excludedAlternative
    case deferredAlternative
}

enum MergeReviewReason: String, Hashable, Codable {
    case subtype
    case brand
    case alternative
    case productChangingPreparation
    case incompatibleUnit
    case uncertainQuantity
}

struct CombinedIngredientSource: Identifiable, Hashable, Codable {
    var id: String {
        let base = "\(selectionID.uuidString.lowercased()):\(ingredient.id.uuidString.lowercased())"
        guard let variantKey, !variantKey.isEmpty else { return base }
        return "\(base):\(variantKey)"
    }

    var selectionID: UUID
    var recipeID: UUID
    var recipeTitle: String
    var ingredient: FrozenMealPrepIngredient
    var servingScale: Double
    var scaledQuantity: Double
    var variantKey: String? = nil
}

struct PantryIngredientDeduction: Identifiable, Hashable, Codable {
    var id: UUID { pantryItemID }
    var pantryItemID: UUID
    var pantryItemName: String
    var quantity: Double
    var unit: String
}

struct CombinedIngredientLine: Identifiable, Hashable, Codable {
    var id: String
    var shoppingItemID: UUID?
    var name: String
    var canonicalName: String
    var quantity: Double
    var unit: MealPrepUnit
    var category: GroceryCategory
    var sources: [CombinedIngredientSource]
    var mergeReviewState: MergeReviewState
    var mergeReviewReasons: Set<MergeReviewReason>
    var uncertainDuplicateGroup: String?
    var pantryDeductions: [PantryIngredientDeduction]
    var quantityToBuy: Double
    var buyFullOverride: Bool? = nil

    var pantryQuantityApplied: Double { max(0, quantity - quantityToBuy) }
    var pantrySuggestedQuantityToBuy: Double {
        max(0, quantity - pantryDeductions.reduce(0) { $0 + $1.quantity })
    }
    var isBuyingFullQuantity: Bool {
        // A missing choice is the conservative state: pantry stock is only
        // applied after the user explicitly chooses Use Pantry.
        buyFullOverride != false
    }
    var hasPantryChoice: Bool {
        !pantryDeductions.isEmpty
    }
    var participatesInCurrentTrip: Bool {
        mergeReviewState != .excludedAlternative && mergeReviewState != .deferredAlternative
    }
    var needsReview: Bool {
        mergeReviewState == .reviewRequired || mergeReviewState == .alternativeChoice
    }
}

struct MealPrepAggregationResult: Hashable, Codable {
    var scope: ShoppingScope
    var lines: [CombinedIngredientLine]
}

struct MealPrepPlanSnapshot: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var selections: [MealPrepSelection]
    var lines: [CombinedIngredientLine]
    var createdAt: Date
    var updatedAt: Date

    init(draft: MealPrepDraft, lines: [CombinedIngredientLine]) {
        id = draft.id
        title = draft.title
        selections = draft.selections
        self.lines = lines
        createdAt = draft.createdAt
        updatedAt = draft.updatedAt
    }

    var shoppingScope: ShoppingScope { .mealPrep(id) }
    var recipeCount: Int { selections.count }
    var ingredientCount: Int { lines.count }
    var pantryCoveredCount: Int {
        lines.filter { $0.participatesInCurrentTrip && $0.pantryQuantityApplied > 0 }.count
    }
    var purchaseCount: Int { lines.filter { $0.quantityToBuy > 0 }.count }
    var unresolvedReviewCount: Int { lines.filter(\.needsReview).count }
}

struct PantryAcquisition: Hashable, Codable {
    var shoppingItemID: UUID
    var pantryItemID: UUID
    var amount: Double
    var sourceContributions: [CombinedIngredientSource]
}

enum MealPrepAggregationError: Error, Equatable {
    case emptySelection
    case tooManySelections(maximum: Int)
    case invalidServings(selectionID: UUID)
}
