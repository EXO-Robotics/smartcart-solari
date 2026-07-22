import Foundation

protocol WeeklyMealsClock: Sendable {
    var now: Date { get }
}

struct SystemWeeklyMealsClock: WeeklyMealsClock {
    var now: Date { Date() }
}

struct FixedWeeklyMealsClock: WeeklyMealsClock {
    let now: Date
}

protocol WeeklyMealsResourceLoading: Sendable {
    func data(resource: String) throws -> Data
}

struct BundleWeeklyMealsResourceLoader: WeeklyMealsResourceLoading {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func data(resource: String) throws -> Data {
        let path = resource as NSString
        let name = path.deletingPathExtension
        let extensionName = path.pathExtension.isEmpty ? "json" : path.pathExtension
        guard let url = bundle.url(forResource: name, withExtension: extensionName) else {
            throw WeeklyMealRepositoryError.missingResource(resource)
        }
        return try Data(contentsOf: url)
    }
}

protocol WeeklyMealCollectionRepository: Sendable {
    func activeCollection(on date: Date, calendar: Calendar) throws -> ResolvedWeeklyMealCollection
    func recipe(for reference: CuratedRecipeReference) throws -> CuratedRecipeRecord
    func pricingResource() throws -> WeeklyMealPricingResource
}

enum WeeklyMealRepositoryError: Error, Equatable, Sendable {
    case missingResource(String)
    case invalidManifest([WeeklyMealManifestIssue])
    case noValidCollection
    case missingRecipe(CuratedRecipeID)
    case recipeVersionMismatch(CuratedRecipeID, expected: Int, actual: Int)
}

struct WeeklyMealManifestIssue: Equatable, Hashable, Sendable {
    enum Code: String, Sendable {
        case unsupportedSchema
        case invalidDateRange
        case invalidEntryCount
        case invalidSlotCount
        case invalidFeaturedCount
        case duplicateID
        case duplicateRecipe
        case missingRecipe
        case versionMismatch
        case invalidRecipe
        case invalidNutrition
        case invalidCost
        case invalidClaim
    }

    let code: Code
    let path: String
    let message: String
}

enum WeeklyMealManifestValidator {
    static func issues(
        manifest: WeeklyMealsManifest,
        recipes: WeeklyMealRecipesResource,
        collections: [WeeklyMealCollection]
    ) -> [WeeklyMealManifestIssue] {
        var issues: [WeeklyMealManifestIssue] = []
        if manifest.contentSchemaVersion != WeeklyMealsManifest.supportedSchemaVersion ||
            recipes.contentSchemaVersion != WeeklyMealsManifest.supportedSchemaVersion {
            issues.append(.init(code: .unsupportedSchema, path: "manifest", message: "Unsupported content schema."))
        }

        let groupedRecipes = Dictionary(grouping: recipes.recipes, by: \.id)
        for (id, records) in groupedRecipes where records.count > 1 {
            issues.append(.init(code: .duplicateID, path: "recipes.\(id.rawValue)", message: "Recipe IDs must be unique."))
        }
        let recipesByID = groupedRecipes.compactMapValues(\.first)
        for recipe in recipes.recipes {
            validate(recipe: recipe, path: "recipes.\(recipe.id.rawValue)", issues: &issues)
        }

        let groupedCollections = Dictionary(grouping: collections, by: \.id)
        for (id, values) in groupedCollections where values.count > 1 {
            issues.append(.init(code: .duplicateID, path: "collections.\(id)", message: "Collection IDs must be unique."))
        }

        for collection in collections {
            let path = "collections.\(collection.id)"
            if collection.contentSchemaVersion != WeeklyMealsManifest.supportedSchemaVersion {
                issues.append(.init(code: .unsupportedSchema, path: path, message: "Unsupported collection schema."))
            }
            if collection.weekStartDate >= collection.weekEndDateExclusive {
                issues.append(.init(code: .invalidDateRange, path: path, message: "Start must precede exclusive end."))
            }
            if collection.entries.count != 8 {
                issues.append(.init(code: .invalidEntryCount, path: path, message: "A collection requires exactly eight entries."))
            }
            for slot in WeeklyMealSlot.allCases where collection.entries.filter({ $0.slot == slot }).count != 2 {
                issues.append(.init(code: .invalidSlotCount, path: "\(path).\(slot.rawValue)", message: "Each meal slot requires exactly two entries."))
            }
            if collection.entries.filter(\.isFeatured).count != 1 {
                issues.append(.init(code: .invalidFeaturedCount, path: path, message: "A collection requires exactly one featured entry."))
            }
            if Set(collection.entries.map(\.id)).count != collection.entries.count {
                issues.append(.init(code: .duplicateID, path: path, message: "Entry IDs must be unique."))
            }
            if Set(collection.entries.map(\.recipeReference)).count != collection.entries.count {
                issues.append(.init(code: .duplicateRecipe, path: path, message: "Recipe references must be unique."))
            }
            if Set(collection.entries.map(\.displayOrder)) != Set(0..<collection.entries.count) {
                issues.append(.init(code: .invalidEntryCount, path: path, message: "Display order must be deterministic and contiguous from zero."))
            }
            for entry in collection.entries {
                guard let recipe = recipesByID[entry.recipeReference.recipeID] else {
                    issues.append(.init(code: .missingRecipe, path: "\(path).\(entry.id)", message: "Recipe reference cannot be resolved."))
                    continue
                }
                if recipe.contentVersion != entry.recipeReference.contentVersion {
                    issues.append(.init(code: .versionMismatch, path: "\(path).\(entry.id)", message: "Recipe content version does not match."))
                }
                if entry.isFeatured && !recipe.metadata.isFeaturedEligible {
                    issues.append(.init(code: .invalidRecipe, path: "\(path).\(entry.id)", message: "Featured recipe is not eligible."))
                }
            }
        }
        if !collections.contains(where: { $0.id == manifest.fallbackCollectionID }) {
            issues.append(.init(code: .missingRecipe, path: "fallbackCollectionID", message: "Fallback collection cannot be resolved."))
        }
        return issues
    }

    private static func validate(
        recipe: CuratedRecipeRecord,
        path: String,
        issues: inout [WeeklyMealManifestIssue]
    ) {
        if recipe.id.rawValue.isEmpty || recipe.contentVersion <= 0 || recipe.title.isEmpty ||
            recipe.defaultServings <= 0 || recipe.servingDescription.isEmpty || recipe.ingredients.isEmpty ||
            recipe.instructions.isEmpty || recipe.metadata.prepMinutes < 0 || recipe.metadata.cookMinutes < 0 ||
            recipe.metadata.passiveMinutes < 0 {
            issues.append(.init(code: .invalidRecipe, path: path, message: "Recipe structure is incomplete."))
        }
        if Set(recipe.ingredients.map(\.id)).count != recipe.ingredients.count ||
            Set(recipe.instructions.map(\.id)).count != recipe.instructions.count {
            issues.append(.init(code: .duplicateID, path: path, message: "Ingredient and instruction IDs must be unique."))
        }
        if recipe.instructions.map(\.id).sorted() != Array(1...recipe.instructions.count) {
            issues.append(.init(code: .invalidRecipe, path: "\(path).instructions", message: "Instruction steps must be contiguous from one."))
        }
        for ingredient in recipe.ingredients {
            let validQuantity = ingredient.isQualitative
                ? ingredient.quantity == nil
                : ingredient.quantity.map { $0 > 0 } == true
            if ingredient.id.isEmpty || ingredient.rawText.isEmpty || ingredient.name.isEmpty || !validQuantity {
                issues.append(.init(code: .invalidRecipe, path: "\(path).ingredients.\(ingredient.id)", message: "Ingredient structure is invalid."))
            }
        }
        if let nutrition = recipe.metadata.nutrition {
            if nutrition.verificationStatus == .requiresVerification || nutrition.caloriesPerServing <= 0 ||
                nutrition.proteinGramsPerServing < 0 || nutrition.servingDefinition != recipe.servingDescription ||
                nutrition.nutritionVersion <= 0 {
                issues.append(.init(code: .invalidNutrition, path: "\(path).nutrition", message: "Public nutrition is not valid."))
            }
        }
        if let cost = recipe.metadata.costEstimate {
            if cost.recipeID != recipe.id || cost.recipeContentVersion != recipe.contentVersion ||
                cost.servingDefinition != recipe.servingDescription || cost.currencyCode.count != 3 ||
                (cost.status == .requiresVerification && (cost.totalRecipeCost != nil || cost.costPerServing != nil)) {
                issues.append(.init(code: .invalidCost, path: "\(path).costEstimate", message: "Cost estimate is inconsistent with its recipe."))
            }
        }
        for claim in recipe.metadata.verifiedDietaryClaims where claim.verificationVersion <= 0 {
            issues.append(.init(code: .invalidClaim, path: "\(path).claims", message: "Dietary claim lacks verification."))
        }
    }
}

final class BundledWeeklyMealRepository: WeeklyMealCollectionRepository, @unchecked Sendable {
    private let manifest: WeeklyMealsManifest
    private let recipes: WeeklyMealRecipesResource
    private let collections: [WeeklyMealCollection]
    private let pricing: WeeklyMealPricingResource
    private let recipesByID: [CuratedRecipeID: CuratedRecipeRecord]

    convenience init(bundle: Bundle = .main, manifestResource: String = "manifest-v1.json") throws {
        try self.init(loader: BundleWeeklyMealsResourceLoader(bundle: bundle), manifestResource: manifestResource)
    }

    init(loader: WeeklyMealsResourceLoading, manifestResource: String = "manifest-v1.json") throws {
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(WeeklyMealsManifest.self, from: loader.data(resource: manifestResource))
        let recipes = try decoder.decode(WeeklyMealRecipesResource.self, from: loader.data(resource: manifest.recipesResource))
        let collections = try manifest.collectionResources.map {
            try decoder.decode(WeeklyMealCollection.self, from: loader.data(resource: $0))
        }
        let pricing = try WeeklyMealPricingResourceDecoder.decode(loader.data(resource: manifest.pricingResource))
        let issues = WeeklyMealManifestValidator.issues(manifest: manifest, recipes: recipes, collections: collections)
        guard issues.isEmpty else { throw WeeklyMealRepositoryError.invalidManifest(issues) }
        self.manifest = manifest
        self.recipes = recipes
        self.collections = collections
        self.pricing = pricing
        recipesByID = Dictionary(uniqueKeysWithValues: recipes.recipes.map { ($0.id, $0) })
    }

    func activeCollection(on date: Date, calendar: Calendar) throws -> ResolvedWeeklyMealCollection {
        let localDate = LocalCalendarDate(date, calendar: calendar)
        let validCollections = collections.filter { collection in
            collection.weekStartDate <= localDate && localDate < collection.weekEndDateExclusive
        }
        let active = validCollections.max { $0.weekStartDate < $1.weekStartDate }
        let archived = collections.filter { $0.weekEndDateExclusive <= localDate }.max { $0.weekEndDateExclusive < $1.weekEndDateExclusive }
        let fallback = collections.first { $0.id == manifest.fallbackCollectionID }
        guard let collection = active ?? archived ?? fallback else {
            throw WeeklyMealRepositoryError.noValidCollection
        }
        let meals = try collection.entries.sorted { $0.displayOrder < $1.displayOrder }.map { entry in
            ResolvedWeeklyMeal(entry: entry, recipe: try recipe(for: entry.recipeReference))
        }
        return ResolvedWeeklyMealCollection(collection: collection, meals: meals)
    }

    func recipe(for reference: CuratedRecipeReference) throws -> CuratedRecipeRecord {
        guard let recipe = recipesByID[reference.recipeID] else {
            throw WeeklyMealRepositoryError.missingRecipe(reference.recipeID)
        }
        guard recipe.contentVersion == reference.contentVersion else {
            throw WeeklyMealRepositoryError.recipeVersionMismatch(
                reference.recipeID,
                expected: reference.contentVersion,
                actual: recipe.contentVersion
            )
        }
        return recipe
    }

    func pricingResource() throws -> WeeklyMealPricingResource { pricing }
}
