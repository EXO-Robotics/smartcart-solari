import Foundation

struct WeeklyMealDisplayModel: Identifiable, Hashable, Sendable {
    let id: CuratedRecipeID
    let contentVersion: Int
    let collectionID: String
    let entryID: String
    let imageAssetName: String
    let accessibilityDescription: String
    let slot: WeeklyMealSlot
    let isFeatured: Bool
    let title: String
    let shortDescription: String
    let defaultServings: Int
    let servingDescription: String
    let caloriesPerServing: Int?
    let proteinGramsPerServing: Decimal?
    let totalMinutes: Int
    let costPerServingText: String?
    let costStatus: CostEstimateStatus?
    let verifiedDietaryClaims: [VerifiedDietaryClaim]
    let merchandisingTags: [MerchandisingTag]

    var primaryTag: MerchandisingTag? { merchandisingTags.first }
    var secondaryTag: MerchandisingTag? { merchandisingTags.dropFirst().first }
}

enum WeeklyMealDisplayModelFactory {
    static func makeModels(
        from collection: ResolvedWeeklyMealCollection,
        locale: Locale = .current
    ) -> [WeeklyMealDisplayModel] {
        collection.meals.map { meal in
            let recipe = meal.recipe
            let cost = recipe.metadata.costEstimate
            return WeeklyMealDisplayModel(
                id: recipe.id,
                contentVersion: recipe.contentVersion,
                collectionID: collection.collection.id,
                entryID: meal.entry.id,
                imageAssetName: recipe.metadata.imageAssetName,
                accessibilityDescription: recipe.metadata.accessibilityDescription,
                slot: meal.entry.slot,
                isFeatured: meal.entry.isFeatured,
                title: recipe.title,
                shortDescription: recipe.shortDescription,
                defaultServings: recipe.defaultServings,
                servingDescription: recipe.servingDescription,
                caloriesPerServing: recipe.metadata.nutrition?.caloriesPerServing,
                proteinGramsPerServing: recipe.metadata.nutrition?.proteinGramsPerServing,
                totalMinutes: recipe.metadata.prepMinutes + recipe.metadata.cookMinutes,
                costPerServingText: displayableCost(cost, locale: locale),
                costStatus: cost?.status,
                verifiedDietaryClaims: recipe.metadata.verifiedDietaryClaims,
                merchandisingTags: recipe.metadata.merchandisingTags
            )
        }
    }

    private static func displayableCost(
        _ estimate: RecipeCostEstimate?,
        locale: Locale
    ) -> String? {
        guard let estimate else { return nil }
        return WeeklyMealCostFormatter.string(for: estimate, locale: locale)
    }
}

extension WeeklyMealSlot {
    var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snacks"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: "sun.max.fill"
        case .lunch: "takeoutbag.and.cup.and.straw.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        }
    }
}

extension MerchandisingTag {
    var displayName: String {
        switch self {
        case .highProtein: "High Protein"
        case .mealPrepFriendly: "Meal Prep Friendly"
        case .makeAhead: "Make Ahead"
        case .freezerFriendly: "Freezer Friendly"
        case .thirtyMinutes: "30 Minutes"
        case .fiveMinutes: "5 Minutes"
        case .familyFriendly: "Family Friendly"
        case .onePan: "One Pan"
        case .easyCleanup: "Easy Cleanup"
        case .reheatsWell: "Reheats Well"
        case .crowdFavorite: "Crowd Favorite"
        case .easyPrep: "Easy Prep"
        }
    }

    var symbolName: String {
        switch self {
        case .highProtein: "dumbbell.fill"
        case .mealPrepFriendly: "shippingbox.fill"
        case .makeAhead: "clock.badge.checkmark.fill"
        case .freezerFriendly: "snowflake"
        case .thirtyMinutes, .fiveMinutes: "timer"
        case .familyFriendly: "person.3.fill"
        case .onePan: "frying.pan.fill"
        case .easyCleanup: "sparkles"
        case .reheatsWell: "arrow.clockwise"
        case .crowdFavorite: "heart.fill"
        case .easyPrep: "checkmark.circle.fill"
        }
    }
}
