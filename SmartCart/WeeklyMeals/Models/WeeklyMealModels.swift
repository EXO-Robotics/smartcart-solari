import Foundation

struct LocalCalendarDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) throws {
        guard Self.isValid(year: year, month: month, day: day) else {
            throw LocalCalendarDateError.invalidDate(year: year, month: month, day: day)
        }
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    init(iso8601 value: String) throws {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              Self.isValid(year: year, month: month, day: day) else {
            throw LocalCalendarDateError.invalidString(value)
        }
        self.year = year
        self.month = month
        self.day = day
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(iso8601: container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return false
        }
        let result = calendar.dateComponents([.year, .month, .day], from: date)
        return result.year == year && result.month == month && result.day == day
    }
}

enum LocalCalendarDateError: Error, Equatable, Sendable {
    case invalidDate(year: Int, month: Int, day: Int)
    case invalidString(String)
}

struct CuratedRecipeID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }
}

struct CuratedRecipeReference: Codable, Hashable, Sendable {
    let recipeID: CuratedRecipeID
    let contentVersion: Int
}

enum WeeklyMealSlot: String, Codable, CaseIterable, Hashable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
}

enum NutritionEstimateStatus: String, Codable, Hashable, Sendable {
    case requiresVerification
    case editorialEstimate
    case calculated
    case verified
}

struct NutritionEstimate: Codable, Hashable, Sendable {
    let caloriesPerServing: Int
    let calorieRangeMinimum: Int?
    let calorieRangeMaximum: Int?
    let proteinGramsPerServing: Decimal
    let servingDefinition: String
    let verificationStatus: NutritionEstimateStatus
    let nutritionVersion: Int
}

enum CostEstimateStatus: String, Codable, Hashable, Sendable {
    case editorialEstimate
    case calculated
    case verified
    case requiresVerification
}

enum CostEstimateBasis: String, Codable, Hashable, Sendable {
    case bundledEditorialPriceCatalog
    case proportionalIngredientValue
    case retailerCatalogSnapshot
}

struct RecipeCostEstimate: Codable, Hashable, Sendable {
    let recipeID: CuratedRecipeID
    let recipeContentVersion: Int
    let servingDefinition: String
    let totalRecipeCost: Decimal?
    let costPerServing: Decimal?
    let costRangeMinimumPerServing: Decimal?
    let costRangeMaximumPerServing: Decimal?
    let currencyCode: String
    let basis: CostEstimateBasis
    let status: CostEstimateStatus
    let pricingRegion: String?
    let priceSnapshotDate: LocalCalendarDate?
    let pricingVersion: Int
    let includedIngredientIDs: [String]
    let excludedIngredientIDs: [String]
    let notes: String?

    var isPubliclyDisplayable: Bool {
        status != .requiresVerification && costPerServing != nil
    }
}

enum DietaryClaim: String, Codable, CaseIterable, Hashable, Sendable {
    case madeWithoutNuts
    case dairyFree
    case glutenFree
    case vegetarian
    case vegan
    case ketoFriendly
    case lowCarb
}

enum DietaryClaimApplicability: String, Codable, Hashable, Sendable {
    case asWritten
    case withDocumentedSubstitution
}

struct VerifiedDietaryClaim: Codable, Hashable, Sendable {
    let claim: DietaryClaim
    let applicability: DietaryClaimApplicability
    let verificationVersion: Int
}

enum MerchandisingTag: String, Codable, CaseIterable, Hashable, Sendable {
    case highProtein
    case mealPrepFriendly
    case makeAhead
    case freezerFriendly
    case thirtyMinutes
    case fiveMinutes
    case familyFriendly
    case onePan
    case easyCleanup
    case reheatsWell
    case crowdFavorite
    case easyPrep
}

enum CuratedOptionalIngredientPolicy: String, Codable, Hashable, Sendable {
    case includedByDefault
    case excludedByDefault
}

struct CuratedIngredient: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let rawText: String
    let name: String
    let quantity: Decimal?
    let unit: String
    let preparation: String
    let category: String
    let pricingKey: String?
    let optionalPolicy: CuratedOptionalIngredientPolicy?
    let isQualitative: Bool
}

struct CuratedInstruction: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let text: String
}

struct CuratedSubstitution: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let ingredientID: String
    let replacementName: String
    let note: String
}

struct CuratedRecipeMetadata: Codable, Hashable, Sendable {
    let prepMinutes: Int
    let cookMinutes: Int
    let passiveMinutes: Int
    let nutrition: NutritionEstimate?
    let costEstimate: RecipeCostEstimate?
    let mealTypes: [WeeklyMealSlot]
    let verifiedDietaryClaims: [VerifiedDietaryClaim]
    let merchandisingTags: [MerchandisingTag]
    let imageAssetName: String
    let accessibilityDescription: String
    let isMealPrepFriendly: Bool
    let isFeaturedEligible: Bool
    let baseNutritionExcludes: [String]?
}

struct CuratedRecipeRecord: Codable, Identifiable, Hashable, Sendable {
    let id: CuratedRecipeID
    let contentVersion: Int
    let title: String
    let shortDescription: String
    let defaultServings: Int
    let servingDescription: String
    let ingredients: [CuratedIngredient]
    let instructions: [CuratedInstruction]
    let substitutions: [CuratedSubstitution]
    let metadata: CuratedRecipeMetadata
}

struct WeeklyMealEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let recipeReference: CuratedRecipeReference
    let slot: WeeklyMealSlot
    let displayOrder: Int
    let isFeatured: Bool
    let promotionalTag: MerchandisingTag?
}

struct WeeklyMealCollection: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let contentSchemaVersion: Int
    let title: String
    let weekStartDate: LocalCalendarDate
    let weekEndDateExclusive: LocalCalendarDate
    let entries: [WeeklyMealEntry]
    let promotionalMessage: String?

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let localDate = LocalCalendarDate(date, calendar: calendar)
        return weekStartDate <= localDate && localDate < weekEndDateExclusive
    }
}

struct WeeklyMealRecipesResource: Codable, Hashable, Sendable {
    let contentSchemaVersion: Int
    let recipes: [CuratedRecipeRecord]
}

struct WeeklyMealsManifest: Codable, Hashable, Sendable {
    static let supportedSchemaVersion = 1

    let contentSchemaVersion: Int
    let recipesResource: String
    let collectionResources: [String]
    let fallbackCollectionID: String
    let pricingResource: String
}

struct ResolvedWeeklyMeal: Identifiable, Hashable, Sendable {
    var id: String { entry.id }
    let entry: WeeklyMealEntry
    let recipe: CuratedRecipeRecord
}

struct ResolvedWeeklyMealCollection: Identifiable, Hashable, Sendable {
    var id: String { collection.id }
    let collection: WeeklyMealCollection
    let meals: [ResolvedWeeklyMeal]
}
