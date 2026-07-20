import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .home
    var homePath: [SmartRoute] = []
    var presentedSheet: SheetDestination?

    var activeRecipe: Recipe {
        didSet { persistState() }
    }
    var recipes: [Recipe] {
        didSet { persistState() }
    }
    private(set) var savedRecipeIDs: Set<UUID> {
        didSet { persistState() }
    }
    var desiredServings: Int {
        didSet { persistState() }
    }
    var preferences: ShoppingPreferences {
        didSet { persistState() }
    }
    var featureFlags: AppFeatureFlags {
        didSet { persistState() }
    }

    var storeStrategy: StoreStrategy {
        didSet { persistState() }
    }
    var fulfillmentMode: FulfillmentMode {
        didSet { persistState() }
    }
    var selectedStoreIDs: Set<UUID> {
        didSet { persistState() }
    }
    var zipCode: String {
        didSet { persistState() }
    }
    var pickupDay: String {
        didSet { persistState() }
    }
    var pickupTime: String {
        didSet { persistState() }
    }

    var shoppingItems: [ShoppingListItem] {
        didSet { persistState() }
    }
    var matchProgress = 0.0
    var matchStage = "Ready to match"
    var isMatching = false
    var guidedIndex: Int {
        didSet { persistState() }
    }

    var savedLists: [SavedShoppingList] {
        didSet { persistState() }
    }
    var preferredDeliveryPartnerName: String? {
        didSet { persistState() }
    }
    var pantryInventory: [PantryInventoryItem] {
        didSet { persistState() }
    }
    var preferredProductIDsByIngredient: [String: String] {
        didSet { persistState() }
    }
    var analyticsEvents: [AnalyticsEvent] {
        didSet { persistState() }
    }
    var walmartWishlistReference: WalmartWishlistReference? {
        didSet { persistState() }
    }
    var shoppingSessions: [ShoppingSession] {
        didSet { persistState() }
    }
    var activeShoppingSessionID: UUID? {
        didSet { persistState() }
    }
    var shoppingScope: ShoppingScope? {
        didSet { persistState() }
    }
    var mealPrepDraft: MealPrepDraft? {
        didSet { persistState() }
    }
    var mealPrepPlan: MealPrepPlanSnapshot? {
        didSet { persistState() }
    }
    var selectedRetailer: ShoppingRetailer {
        didSet { commerceDefaults.set(selectedRetailer.rawValue, forKey: Self.selectedRetailerKey) }
    }
    var retailerSetupCompletedIDs: Set<String> = [] {
        didSet {
            commerceDefaults.set(
                retailerSetupCompletedIDs.sorted(),
                forKey: Self.retailerSetupCompletedKey
            )
        }
    }
    var shoppingRoute: ShoppingRoutePreference {
        didSet { commerceDefaults.set(shoppingRoute.rawValue, forKey: Self.shoppingRouteKey) }
    }
    var instacartRetailerPreference: InstacartRetailerPreference {
        didSet { commerceDefaults.set(instacartRetailerPreference.rawValue, forKey: Self.instacartRetailerKey) }
    }
    var commerceFulfillmentPreference: CommerceFulfillmentPreference {
        didSet {
            commerceDefaults.set(commerceFulfillmentPreference.rawValue, forKey: Self.commerceFulfillmentKey)
            if commerceFulfillmentPreference == .pickup { fulfillmentMode = .pickup }
            if commerceFulfillmentPreference == .delivery { fulfillmentMode = .delivery }
        }
    }
    var latestHandoffFeedback: CommerceHandoffFeedback? {
        didSet { commerceDefaults.set(latestHandoffFeedback?.rawValue, forKey: Self.handoffFeedbackKey) }
    }
    var isPreparingCommerceHandoff = false
    var commerceHandoffStage = "Ready to prepare"
    var lastInstacartHandoff: InstacartHandoffResponse?
    var lastImportReport: RecipeImportReport?
    var toastMessage: String?
    private(set) var persistenceIssue: String?

    /// Whole-recipe opens, newest first. Stored in UserDefaults rather than
    /// the JSON state schema because this is UI history, not shopping state.
    private(set) var recentRecipeRecords: [RecentRecipeRecord] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(recentRecipeRecords) {
                commerceDefaults.set(data, forKey: Self.recentRecipeRecordsKey)
            }
            // Retain the former ordering key for downgrade compatibility.
            commerceDefaults.set(recentRecipeIDs.map(\.uuidString), forKey: Self.legacyRecentRecipesKey)
        }
    }

    private static let recentRecipeRecordsKey = "smartcart.recentRecipeRecords"
    private static let legacyRecentRecipesKey = "smartcart.recentRecipeIDs"
    private static let selectedRetailerKey = "smartcart.commerce.selectedRetailer"
    private static let retailerSetupCompletedKey = "smartcart.commerce.retailerSetupCompleted"
    private static let shoppingRouteKey = "smartcart.commerce.shoppingRoute"
    private static let instacartRetailerKey = "smartcart.commerce.instacartRetailer"
    private static let commerceFulfillmentKey = "smartcart.commerce.fulfillment"
    private static let handoffFeedbackKey = "smartcart.commerce.lastFeedback"

    var recentRecipeIDs: [UUID] { recentRecipeRecords.map(\.recipeID) }

    /// Records remain available for trip/history resolution even after the
    /// person removes their membership from the Saved Recipes library.
    var savedRecipes: [Recipe] {
        recipes.filter { savedRecipeIDs.contains($0.id) }
    }

    /// A dedicated immutable catalog prevents imported or historical records
    /// from leaking into Try a Sample.
    var sampleRecipes: [Recipe] { SampleData.recipes }

    var recentRecipes: [Recipe] {
        recentRecipeRecords.compactMap { record in
            recipes.first { $0.id == record.recipeID }
        }
    }

    var hasCompletedShoppingTrip: Bool {
        shoppingSessions.contains { $0.isGuideComplete || $0.isCommitted }
    }

    var hasExperiencedUserState: Bool {
        hasCompletedShoppingTrip ||
            recipes.contains { $0.source != .sample } ||
            !shoppingItems.isEmpty ||
            !savedLists.isEmpty ||
            !shoppingSessions.isEmpty ||
            !pantryInventory.isEmpty ||
            !retailerSetupCompletedIDs.isEmpty
    }

    var mostRecentShoppedRecipe: Recipe? {
        shoppingSessions
            .filter { $0.isGuideComplete || $0.isCommitted }
            .sorted { $0.startedAt > $1.startedAt }
            .lazy
            .compactMap { session in self.recipes.first { $0.id == session.recipeID } }
            .first
    }

    let stores: [RetailerStore]
    let deliveryPartners: [DeliveryPartner]

    @ObservationIgnored
    private let stateStore: any SmartCartStateStoring
    @ObservationIgnored
    private let retailerEngine: RetailerGuideEngine
    @ObservationIgnored
    private let instacartHandoffService: any InstacartHandoffServicing
    @ObservationIgnored
    private let commerceDefaults: UserDefaults
    @ObservationIgnored
    private var persistenceReady = false
    @ObservationIgnored
    private var suppressPersistence = false
    @ObservationIgnored
    private var matchingGeneration: UInt = 0

    init(
        stateStore: any SmartCartStateStoring = JSONSmartCartStateStore(),
        retailerAdapters: [ShoppingRetailer: any RetailerGuideAdapter]? = nil,
        instacartHandoffService: any InstacartHandoffServicing = InstacartHandoffClient(),
        commerceDefaults: UserDefaults = .standard,
        seedDemoShoppingState: Bool = false
    ) {
        var availableAdapters: [ShoppingRetailer: any RetailerGuideAdapter] = [
            .walmart: DemoWalmartCatalogService(),
            .target: DemoTargetCatalogService()
        ]
        retailerAdapters?.forEach {
            guard $0.key == $0.value.retailer else { return }
            availableAdapters[$0.key] = $0.value
        }
        let restoredState: SmartCartPersistedState?
        let stateLoadError: Error?
        let stateLoadWarning: SmartCartStateStoreWarning?
        do {
            restoredState = try stateStore.load()
            stateLoadError = nil
            stateLoadWarning = stateStore.lastLoadWarning
        } catch {
            restoredState = nil
            stateLoadError = error
            stateLoadWarning = nil
        }

        func supportedRetailer(rawValue: String?) -> ShoppingRetailer? {
            guard let rawValue,
                  let retailer = ShoppingRetailer(rawValue: rawValue),
                  retailer.configuration.isAvailable,
                  availableAdapters[retailer] != nil
            else { return nil }
            return retailer
        }

        let activeItemRetailerIDs = Set(
            (restoredState?.shoppingItems ?? []).map(\.product.retailerID)
        )
        let activeItemRetailer = activeItemRetailerIDs.count == 1
            ? supportedRetailer(rawValue: activeItemRetailerIDs.first)
            : nil
        let defaultsRetailer = supportedRetailer(
            rawValue: commerceDefaults.string(forKey: Self.selectedRetailerKey)
        )
        let latestManifestRetailer = restoredState?.savedLists
            .map(\.manifest)
            .sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { supportedRetailer(rawValue: $0.retailerID) }
            .first
        let initialRetailer = activeItemRetailer
            ?? (seedDemoShoppingState ? .walmart : nil)
            ?? defaultsRetailer
            ?? latestManifestRetailer
            ?? .walmart

        self.stateStore = stateStore
        self.retailerEngine = RetailerGuideEngine(adapters: availableAdapters)
        self.instacartHandoffService = instacartHandoffService
        self.commerceDefaults = commerceDefaults

        selectedRetailer = initialRetailer
        retailerSetupCompletedIDs = Set(
            commerceDefaults.stringArray(forKey: Self.retailerSetupCompletedKey) ?? []
        )

        // Retailer guides are user-driven Safari handoffs. Hidden legacy
        // preferences remain decodable so changing the visible MVP does not
        // destroy an older user's local choices.
        shoppingRoute = commerceDefaults.string(forKey: Self.shoppingRouteKey)
            .flatMap(ShoppingRoutePreference.init(rawValue:)) ?? .walmartDirect
        instacartRetailerPreference = commerceDefaults.string(forKey: Self.instacartRetailerKey)
            .flatMap(InstacartRetailerPreference.init(rawValue:)) ?? .bestAvailable
        commerceFulfillmentPreference = commerceDefaults.string(forKey: Self.commerceFulfillmentKey)
            .flatMap(CommerceFulfillmentPreference.init(rawValue:)) ?? .decideInInstacart
        latestHandoffFeedback = commerceDefaults.string(forKey: Self.handoffFeedbackKey)
            .flatMap(CommerceHandoffFeedback.init(rawValue:))

        let availableStores = [
            RetailerStore(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                retailerStoreID: "walmart-5206",
                name: "Walmart Supercenter A",
                format: "Supercenter",
                address: "6433 Fallbrook Ave, West Hills",
                distance: 2.3,
                pickupWindow: "Today, 4:30–5:30 PM"
            ),
            RetailerStore(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                retailerStoreID: "walmart-2526",
                name: "Walmart Supercenter B",
                format: "Supercenter",
                address: "19821 Rinaldi St, Porter Ranch",
                distance: 6.1,
                pickupWindow: "Today, 5:00–6:00 PM",
                supportsDelivery: false
            ),
            RetailerStore(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
                retailerStoreID: "walmart-5601",
                name: "Walmart Neighborhood Market",
                format: "Neighborhood Market",
                address: "14441 Inglewood Ave, Hawthorne",
                distance: 8.0,
                pickupWindow: "Tomorrow, 9:00–10:00 AM"
            ),
            RetailerStore(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                retailerID: "target",
                retailerStoreID: "target-online",
                name: "Target",
                format: "Online catalog",
                address: "Choose and confirm your store in Target",
                distance: 0,
                pickupWindow: "Confirmed by Target",
                supportsPickup: false,
                supportsDelivery: false
            )
        ]
        stores = availableStores

        deliveryPartners = [
            DeliveryPartner(
                name: "Instacart",
                symbol: "carrot.fill",
                color: Color(red: 0.20, green: 0.62, blue: 0.16),
                url: URL(string: "https://www.instacart.com")!
            ),
            DeliveryPartner(
                name: "DoorDash",
                symbol: "bag.fill",
                color: Color(red: 0.93, green: 0.10, blue: 0.13),
                url: URL(string: "https://www.doordash.com")!
            ),
            DeliveryPartner(
                name: "Uber Eats",
                symbol: "bicycle",
                color: .black,
                url: URL(string: "https://www.ubereats.com")!
            )
        ]

        let sampleRecipes = SampleData.recipes
        let initialRecipes = restoredState?.recipes ?? sampleRecipes
        let initialRecipe = restoredState?.activeRecipe ?? sampleRecipes[0]
        let initialServings = restoredState?.desiredServings ?? sampleRecipes[0].servings
        let initialPreferences = restoredState?.preferences ?? ShoppingPreferences()
        let initialFeatureFlags = restoredState?.featureFlags ?? AppFeatureFlags()
        let initialStoreStrategy = restoredState?.storeStrategy ?? .oneStore
        let initialFulfillment = restoredState?.fulfillmentMode ?? .pickup
        let validRecipeIDs = Set(initialRecipes.map(\.id))
        let initialSavedRecipeIDs: Set<UUID>
        if let restoredState {
            initialSavedRecipeIDs = (
                restoredState.savedRecipeIDs
                    ?? Set(initialRecipes.filter { $0.source != .sample }.map(\.id))
            ).intersection(validRecipeIDs)
        } else {
            initialSavedRecipeIDs = []
        }

        recipes = initialRecipes
        savedRecipeIDs = initialSavedRecipeIDs
        activeRecipe = initialRecipe
        desiredServings = initialServings
        preferences = initialPreferences
        featureFlags = initialFeatureFlags
        storeStrategy = initialStoreStrategy
        fulfillmentMode = initialFulfillment
        zipCode = restoredState?.zipCode ?? "90210"
        pickupDay = restoredState?.pickupDay ?? "Today"
        pickupTime = restoredState?.pickupTime ?? "4:30–5:30 PM"
        guidedIndex = restoredState?.guidedIndex ?? 0
        savedLists = restoredState?.savedLists ?? []
        preferredDeliveryPartnerName = restoredState?.preferredDeliveryPartnerName
        pantryInventory = restoredState?.pantryInventory ?? []
        preferredProductIDsByIngredient = restoredState?.preferredProductIDsByIngredient ?? [:]
        analyticsEvents = restoredState?.analyticsEvents ?? []
        walmartWishlistReference = restoredState?.walmartWishlistReference
        shoppingSessions = restoredState?.shoppingSessions ?? []
        activeShoppingSessionID = restoredState?.activeShoppingSessionID
        shoppingScope = restoredState?.shoppingScope
        mealPrepDraft = restoredState?.mealPrepDraft
        mealPrepPlan = restoredState?.mealPrepPlan

        let retailerStores = availableStores.filter { $0.retailerID == initialRetailer.rawValue }
        let validStoreIDs = Set(availableStores.map(\.id))
        let restoredStoreIDs = restoredState?.selectedStoreIDs.intersection(validStoreIDs) ?? []
        var initialStoreIDs = restoredStoreIDs
        if !retailerStores.contains(where: { initialStoreIDs.contains($0.id) }),
           let defaultStore = retailerStores.first {
            initialStoreIDs.insert(defaultStore.id)
        }
        selectedStoreIDs = initialStoreIDs

        if let restoredItems = restoredState?.shoppingItems,
           restoredItems.allSatisfy({ $0.product.retailerID == initialRetailer.rawValue }) {
            shoppingItems = restoredItems
        } else if seedDemoShoppingState, initialRetailer == .walmart {
            shoppingItems = Self.makeShoppingItems(
                recipe: initialRecipe,
                desiredServings: initialServings,
                store: availableStores[0],
                fulfillmentMode: initialFulfillment,
                preferences: initialPreferences
            )
        } else {
            // Recipes may be available as samples, but a fresh install must
            // never imply the user already created a shopping trip.
            shoppingItems = []
        }

        guidedIndex = min(max(0, guidedIndex), max(0, shoppingItems.count - 1))
        if let data = commerceDefaults.data(forKey: Self.recentRecipeRecordsKey),
           let records = try? JSONDecoder().decode([RecentRecipeRecord].self, from: data) {
            recentRecipeRecords = records
                .filter { record in recipes.contains { $0.id == record.recipeID } }
                .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
                .prefix(5)
                .map { $0 }
        } else {
            let migrationDate = Date()
            recentRecipeRecords = (commerceDefaults.stringArray(forKey: Self.legacyRecentRecipesKey) ?? [])
                .compactMap(UUID.init(uuidString:))
                .enumerated()
                .map { index, recipeID in
                    RecentRecipeRecord(
                        recipeID: recipeID,
                        lastOpenedAt: migrationDate.addingTimeInterval(-Double(index))
                    )
                }
                .filter { record in recipes.contains { $0.id == record.recipeID } }
                .prefix(5)
                .map { $0 }
        }
        if let stateLoadError {
            persistenceIssue = stateLoadError.localizedDescription
            persistenceReady = false
        } else {
            persistenceReady = true
            persistenceIssue = stateLoadWarning?.localizedDescription
        }

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let routeIndex = arguments.firstIndex(of: "-SmartCartDemoRoute"),
           arguments.indices.contains(routeIndex + 1) {
            switch arguments[routeIndex + 1] {
            case "ingredient":
                shoppingItems = []
                homePath = [.ingredientReview]
            case "servings":
                shoppingItems = []
                homePath = [.servingAdjustment]
            case "pantry":
                shoppingItems = []
                homePath = [.pantryCheck]
            case "pantry-match":
                pantryInventory = [
                    PantryInventoryItem(
                        name: "All-purpose flour",
                        quantity: 1,
                        unit: "bag",
                        packageSize: 1,
                        packageUnit: "cup"
                    )
                ]
                beginRecipe(
                    RecipeParser.parse(
                        title: "Brown Butter Cookies",
                        text: "2 cups all-purpose flour\n1 cup brown sugar\n2 eggs\n1 tsp vanilla extract"
                    )
                )
                shoppingItems = []
                homePath = [.pantryCheck]
            case "preferences":
                shoppingItems = []
                homePath = [.preferences]
            case "store":
                shoppingItems = []
                homePath = [.storeSelection]
            case "matching":
                shoppingItems = []
                homePath = [.matching]
            case "shopping":
                homePath = [.shoppingList]
            case "guided":
                homePath = [.guidedShopping]
            case "walmart-guide":
                startRetailerGuide(.walmart)
                if shoppingItems.isEmpty {
                    shoppingItems = Self.makeShoppingItems(
                        recipe: activeRecipe,
                        desiredServings: desiredServings,
                        store: primaryStore,
                        fulfillmentMode: fulfillmentMode,
                        preferences: preferences
                    )
                }
                homePath = [.guidedShopping]
            case "target-guide":
                startRetailerGuide(.target)
                if shoppingItems.isEmpty {
                    shoppingItems = Self.makeShoppingItems(
                        recipe: activeRecipe,
                        desiredServings: desiredServings,
                        store: primaryStore,
                        fulfillmentMode: fulfillmentMode,
                        preferences: preferences
                    )
                }
                homePath = [.guidedShopping]
            case "import":
                presentedSheet = .importer(.sample)
            default:
                break
            }
        }
        #endif
    }

    var selectedStores: [RetailerStore] {
        let selected = stores.filter {
            $0.retailerID == selectedRetailer.rawValue && selectedStoreIDs.contains($0.id)
        }
        if featureFlags.advancedToolsEnabled, storeStrategy == .multipleStops {
            return selected
        }
        return Array(selected.prefix(1))
    }

    var primaryStore: RetailerStore {
        selectedStores.first ?? stores.first { $0.retailerID == selectedRetailer.rawValue } ?? stores[0]
    }

    var storesForSelectedRetailer: [RetailerStore] {
        stores.filter { $0.retailerID == selectedRetailer.rawValue }
    }

    var retailerConfiguration: RetailerGuideConfiguration {
        selectedRetailer.configuration
    }

    private var activeRetailerAdapter: any RetailerGuideAdapter {
        if let adapter = retailerEngine.adapter(for: selectedRetailer) {
            return adapter
        }
        preconditionFailure("Missing adapter for \(selectedRetailer.rawValue)")
    }

    var includedIngredientCount: Int {
        if let plan = currentShoppingMealPrepSnapshot {
            return plan.lines.filter(\.participatesInCurrentTrip).count
        }
        return activeRecipe.ingredients.filter(\.includeInList).count
    }

    var unresolvedQuantityReviewCount: Int {
        if let plan = currentShoppingMealPrepSnapshot { return plan.unresolvedReviewCount }
        return activeRecipe.ingredients.filter { $0.includeInList && $0.quantityReviewRequired == true }.count
    }

    var ingredientsToBuy: [Ingredient] {
        if let plan = currentShoppingMealPrepSnapshot {
            return plan.lines.compactMap(mealPrepIngredient)
        }
        return activeRecipe.ingredients.filter {
            quantityToBuy(for: $0) > 0
        }
    }

    var pantrySkipCount: Int {
        if let plan = currentShoppingMealPrepSnapshot {
            return plan.lines.filter {
                $0.participatesInCurrentTrip && $0.quantityToBuy <= 0
            }.count
        }
        return activeRecipe.ingredients.filter {
            $0.includeInList && quantityToBuy(for: $0) == 0
        }.count
    }

    var pantrySuggestionCount: Int {
        if let plan = currentShoppingMealPrepSnapshot {
            return plan.lines.filter { !$0.pantryDeductions.isEmpty }.count
        }
        return activeRecipe.ingredients.filter { $0.pantrySuggestion != nil }.count
    }

    var activeCommerceCapabilities: CommerceCapabilities {
        .walmartGuided
    }

    var unresolvedAlternativeCount: Int {
        ingredientsToBuy.filter {
            $0.alternativeGroup != nil && $0.name.range(
                of: #"\s+or\s+"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }.count
    }

    var commerceBlockingIssues: [String] {
        var issues: [String] = []
        if ingredientsToBuy.isEmpty {
            issues.append("Add at least one ingredient to the shopping list.")
        }
        if unresolvedQuantityReviewCount > 0 {
            issues.append("Confirm \(unresolvedQuantityReviewCount) uncertain quantity value(s).")
        }
        if unresolvedAlternativeCount > 0 {
            issues.append("Choose one option for \(unresolvedAlternativeCount) unresolved alternative ingredient(s).")
        }
        let postalCode = zipCode.filter(\.isNumber)
        if postalCode.count != 5 {
            issues.append("Enter a five-digit US ZIP code.")
        }
        return issues
    }

    var instacartManifestDraft: InstacartManifestDraft {
        let filters = instacartHealthFilters
        let items = ingredientsToBuy.map { ingredient in
            let quantity = isMealPrepShopping ? ingredient.quantity : quantityToBuy(for: ingredient)
            let quantityText = Ingredient.quantityText(quantity, unit: ingredient.unit)
            let preparation = ingredient.preparation.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = preparation.isEmpty ? ingredient.name : "\(ingredient.name), \(preparation)"
            return InstacartManifestLineItem(
                ingredientID: ingredient.id,
                name: ingredient.name,
                displayText: "\(quantityText) \(displayName)",
                quantity: quantity,
                unit: ingredient.unit,
                healthFilters: filters,
                exactUPC: nil,
                quantityConfirmed: ingredient.quantityReviewRequired != true,
                unresolvedAlternative: ingredient.alternativeGroup != nil && ingredient.name.range(
                    of: #"\s+or\s+"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil
            )
        }
        return InstacartManifestDraft(
            localManifestID: currentSavedManifest?.id ?? currentShoppingScopeID,
            recipeID: currentShoppingScopeID,
            title: currentShoppingTitle,
            desiredServings: isMealPrepShopping ? 0 : desiredServings,
            items: items,
            pantryItemsRemoved: pantrySkipCount
        )
    }

    private var instacartHealthFilters: [String] {
        var filters: Set<String> = []
        if preferences.organicPolicy != .noPreference { filters.insert("ORGANIC") }
        if preferences.dietaryRestrictions.contains(.glutenFree) { filters.insert("GLUTEN_FREE") }
        if preferences.dietaryRestrictions.contains(.vegan) { filters.insert("VEGAN") }
        if preferences.dietaryRestrictions.contains(.kosher) { filters.insert("KOSHER") }
        return filters.sorted()
    }

    var estimatedTotal: Double {
        shoppingItems.reduce(0) { $0 + $1.lineTotal }
    }

    var matchedItemCount: Int {
        shoppingItems.filter(\.product.isExactProductLink).count
    }

    var lowConfidenceItemCount: Int {
        shoppingItems.filter { !$0.product.isExactProductLink || $0.product.confidence != .high }.count
    }

    var searchFallbackCount: Int {
        shoppingItems.filter { $0.product.linkKind == .searchResults }.count
    }

    /// Pre-trip matches that require an explicit keep-or-skip decision.
    /// A review applies only to the exact matching input fingerprint, so a
    /// quantity edit safely reopens the decision.
    var unresolvedMatchingExceptionItems: [ShoppingListItem] {
        guard activeShoppingSessionID == nil else { return [] }
        return shoppingItems.filter { item in
            guard item.status == .waiting,
                  !matchingExceptionReasons(for: item).isEmpty else { return false }
            guard let input = item.matchingInputFingerprint else { return true }
            return item.reviewedMatchingFingerprint != input
        }
    }

    func matchingExceptionReasons(for item: ShoppingListItem) -> [String] {
        var reasons: [String] = []
        if item.product.linkKind == .searchResults {
            reasons.append("Retailer search fallback requires review")
        }
        if item.product.confidence != .high {
            reasons.append("Product match is not high confidence")
        }
        if item.product.availability == .outOfStock {
            reasons.append("Product is out of stock")
        }
        if PackageMath.resolvedPackageCount(
            product: item.product,
            requestedQuantity: requestedQuantityForShoppingItem(item),
            requestedUnit: item.ingredient.unit
        ) == nil {
            reasons.append("Package quantity cannot be resolved safely")
        }
        return reasons
    }

    var pricedItemCount: Int {
        shoppingItems.filter(\.product.hasObservedPrice).count
    }

    var guidedCompletedCount: Int {
        shoppingItems.filter { $0.status.isCompleted }.count
    }

    var retailerVisitedCount: Int {
        shoppingItems.filter { $0.status == .visited }.count
    }

    var savedForLaterCount: Int {
        shoppingItems.filter { $0.status == .savedToWishlist || $0.status == .added }.count
    }

    var retailerAddedCount: Int {
        shoppingItems.filter { $0.status == .addedToCart }.count
    }

    var retailerUnavailableCount: Int {
        shoppingItems.filter { $0.status == .unavailable }.count
    }

    var retailerSkippedCount: Int {
        shoppingItems.filter { $0.status == .skipped }.count
    }

    var retailerGuideIsComplete: Bool {
        !shoppingItems.isEmpty && shoppingItems.allSatisfy { $0.status.isCompleted }
    }

    var retailerSetupIsComplete: Bool {
        retailerSetupCompletedIDs.contains(selectedRetailer.rawValue) ||
            (selectedRetailer == .walmart && walmartWishlistReference != nil)
    }

    var retailerSessionIsInProgress: Bool {
        currentSavedManifest?.handoffProgress == .inProgress && !retailerGuideIsComplete
    }

    var hasResumableRetailerSession: Bool {
        guard !shoppingItems.isEmpty, !retailerGuideIsComplete else { return false }
        return currentSavedManifest?.handoffProgress == .inProgress ||
            currentSavedManifest?.handoffProgress == .paused
    }

    var pendingShoppingSessions: [ShoppingSession] {
        let committed = shoppingSessions.filter(\.isCommitted)
        let candidates = shoppingSessions
            .filter { session in
                !session.isCommitted &&
                    !session.items.isEmpty &&
                    (session.isReusable || session.hasPendingPantryUpdateReminder) &&
                    !committed.contains { shoppingSessionsRepresentSameTrip($0, session) }
            }
            .sorted { lhs, rhs in
                let lhsIsActiveIncomplete = lhs.id == activeShoppingSessionID && !lhs.isGuideComplete
                let rhsIsActiveIncomplete = rhs.id == activeShoppingSessionID && !rhs.isGuideComplete
                if lhsIsActiveIncomplete != rhsIsActiveIncomplete {
                    return lhsIsActiveIncomplete
                }
                return lhs.startedAt > rhs.startedAt
            }
        return candidates.reduce(into: []) { result, session in
            guard !result.contains(where: { shoppingSessionsRepresentSameTrip($0, session) }) else { return }
            result.append(session)
        }
    }

    var mostRecentPendingShoppingSession: ShoppingSession? { pendingShoppingSessions.first }

    var retailerSessionRemainingCount: Int {
        shoppingItems.filter { !$0.status.isCompleted }.count
    }

    var retailerSessionProgressText: String {
        "\(guidedCompletedCount) of \(shoppingItems.count) advanced"
    }

    // Compatibility aliases keep schema-v3 tests and saved Walmart workflows
    // readable while active UI uses retailer-neutral guide terminology.
    var walmartWishlistSavedCount: Int { savedForLaterCount }
    var walmartCartAddedCount: Int { retailerAddedCount }
    var walmartUnavailableCount: Int { retailerUnavailableCount }
    var walmartSkippedCount: Int { retailerSkippedCount }
    var walmartGuideIsComplete: Bool { retailerGuideIsComplete }

    var currentGuidedItem: ShoppingListItem? {
        guard shoppingItems.indices.contains(guidedIndex) else { return nil }
        return shoppingItems[guidedIndex]
    }

    var selectedPickupSummary: String {
        "\(pickupDay), \(pickupTime)"
    }

    var linkedDeliveryPartnerName: String? {
        preferredDeliveryPartnerName
    }

    var retailerCapabilities: RetailerCapabilities {
        activeRetailerAdapter.capabilities
    }

    var shareText: String {
        var lines = [
            "SmartCart · \(currentShoppingTitle)",
            "\(shoppingItems.count) products at \(primaryStore.name)",
            "\(matchedItemCount) exact product links · \(searchFallbackCount) retailer searches",
            "Observed-price subtotal: \(estimatedTotal.formatted(.currency(code: "USD"))) (\(pricedItemCount)/\(shoppingItems.count) items priced)",
            ""
        ]

        lines += shoppingItems.map {
            let price = $0.product.hasObservedPrice
                ? $0.lineTotal.formatted(.currency(code: "USD"))
                : "price unavailable"
            return "• \($0.product.brand) \($0.product.name), \($0.product.package) — \(price) [\($0.product.linkKind.label)]"
        }

        lines += [
            "",
            "SmartCart does not create or submit a retailer cart. Prices and availability may change; tax, fees, tips, substitutions, pickup reservations, and variable-weight adjustments are finalized by the retailer."
        ]
        return lines.joined(separator: "\n")
    }

    func openImporter(_ method: ImportMethod, initialText: String? = nil) {
        track(.importStarted, properties: ["method": method.rawValue])
        presentedSheet = .importer(method, initialText)
    }

    @discardableResult
    func beginRecipe(_ recipe: Recipe) -> Bool {
        guard !recipe.ingredients.isEmpty else {
            showToast("Add at least one ingredient before continuing")
            return false
        }
        var recipe = recipe
        desiredServings = recipe.servings
        applyPantrySuggestions(to: &recipe)
        activeRecipe = recipe
        shoppingScope = .singleRecipe(recipe.id)
        mealPrepPlan = nil
        let isNewRecipeRecord = !recipes.contains { $0.id == recipe.id }
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }
        if isNewRecipeRecord && recipe.source != .sample {
            savedRecipeIDs.insert(recipe.id)
        }
        recordRecipeOpened(recipe.id)
        shoppingItems = []
        activeShoppingSessionID = nil
        matchProgress = 0
        matchStage = "Ready to match"
        isMatching = false
        guidedIndex = 0
        selectedTab = .home
        presentedSheet = nil
        homePath = [.recipeReady]
        track(
            .extractionCompleted,
            properties: [
                "source": recipe.source.rawValue,
                "ingredient_count": String(recipe.ingredients.count)
            ]
        )
        return true
    }

    func isRecipeSaved(_ id: UUID) -> Bool {
        savedRecipeIDs.contains(id)
    }

    /// Explicitly saves the retained record. If the active working copy has
    /// edits, those edits become the saved record in the same persisted write.
    @discardableResult
    func saveRecipeToLibrary(_ id: UUID) -> Bool {
        guard recipes.contains(where: { $0.id == id }) || activeRecipe.id == id else {
            return false
        }
        if savedRecipeIDs.contains(id), activeRecipe.id != id { return true }

        let previousRecipes = recipes
        let previousSavedRecipeIDs = savedRecipeIDs
        var updatedRecipes = recipes
        if activeRecipe.id == id {
            if let index = updatedRecipes.firstIndex(where: { $0.id == id }) {
                updatedRecipes[index] = activeRecipe
            } else {
                updatedRecipes.insert(activeRecipe, at: 0)
            }
        }
        var updatedSavedRecipeIDs = savedRecipeIDs
        updatedSavedRecipeIDs.insert(id)

        return persistLibraryMutation(
            recipes: updatedRecipes,
            savedRecipeIDs: updatedSavedRecipeIDs,
            rollbackRecipes: previousRecipes,
            rollbackSavedRecipeIDs: previousSavedRecipeIDs
        )
    }

    /// Removes only Saved Recipes membership. Historical records and frozen
    /// shopping/Meal Prep state continue referencing the retained Recipe.
    @discardableResult
    func removeRecipeFromLibrary(_ id: UUID) -> Bool {
        guard savedRecipeIDs.contains(id) else { return false }
        let previousRecipes = recipes
        let previousSavedRecipeIDs = savedRecipeIDs
        var updatedSavedRecipeIDs = savedRecipeIDs
        updatedSavedRecipeIDs.remove(id)

        guard persistLibraryMutation(
            recipes: recipes,
            savedRecipeIDs: updatedSavedRecipeIDs,
            rollbackRecipes: previousRecipes,
            rollbackSavedRecipeIDs: previousSavedRecipeIDs
        ) else { return false }

        // Recents are UI history stored separately from the JSON state. Prune
        // only after membership persistence succeeds so a failed removal never
        // leaves the two surfaces disagreeing.
        recentRecipeRecords.removeAll { $0.recipeID == id }
        return true
    }

    /// Records only an intentional whole-recipe open. Retailer pages,
    /// shopping-trip resume, replacements, and reconciliation never call it.
    func recordRecipeOpened(_ recipeID: UUID, at openedAt: Date = .now) {
        guard recipes.contains(where: { $0.id == recipeID }) else { return }
        recentRecipeRecords = (
            [RecentRecipeRecord(recipeID: recipeID, lastOpenedAt: openedAt)] +
                recentRecipeRecords.filter { $0.recipeID != recipeID }
        )
        .prefix(5)
        .map { $0 }
    }

    var currentShoppingTitle: String {
        currentShoppingMealPrepSnapshot?.title ?? activeRecipe.title
    }

    var currentShoppingScopeID: UUID {
        shoppingScope?.identifier ?? activeRecipe.id
    }

    var isMealPrepShopping: Bool {
        shoppingScope?.kind == .mealPrepBeta && currentShoppingMealPrepSnapshot != nil
    }

    /// The reviewed plan that belongs to the current editable draft. Opening
    /// a frozen historical trip never replaces this value.
    var currentMealPrepPlan: MealPrepPlanSnapshot? {
        guard let draftID = mealPrepDraft?.id,
              mealPrepPlan?.id == draftID else { return nil }
        return mealPrepPlan
    }

    /// Frozen provenance for the shopping trip currently being displayed or
    /// reconciled. Historical session A wins over editable draft/plan B.
    var currentShoppingMealPrepSnapshot: MealPrepPlanSnapshot? {
        guard let scope = shoppingScope, scope.kind == .mealPrepBeta else { return nil }
        if let sessionID = activeShoppingSessionID,
           let session = shoppingSession(id: sessionID),
           (session.shoppingScope ?? .singleRecipe(session.recipeID)) == scope,
           let snapshot = session.mealPrepSnapshot {
            return snapshot
        }
        if let editable = currentMealPrepPlan, editable.id == scope.identifier {
            return editable
        }
        return savedLists
            .map(\.manifest)
            .first {
                ($0.shoppingScope ?? .singleRecipe($0.recipeID)) == scope &&
                    $0.retailerID == selectedRetailer.rawValue &&
                    $0.storeID == primaryStore.retailerStoreID
            }?
            .mealPrepSnapshot
    }

    func startMealPrepDraft() {
        let existingDraftWasCompleted = mealPrepDraft.map { draft in
            shoppingSessions.contains {
                ($0.shoppingScope ?? .singleRecipe($0.recipeID)) == draft.shoppingScope &&
                ($0.isCommitted || $0.isGuideComplete)
            } || savedLists.contains {
                ($0.manifest.shoppingScope ?? .singleRecipe($0.manifest.recipeID)) == draft.shoppingScope &&
                $0.manifest.handoffProgress == .completed
            }
        } ?? false
        if mealPrepDraft == nil || mealPrepDraft?.selections.isEmpty == true || existingDraftWasCompleted {
            let succeeded = performAtomicMealPrepTransition {
                mealPrepDraft = MealPrepDraft()
                mealPrepPlan = nil
                shoppingScope = nil
                invalidateShoppingPlan()
            }
            guard succeeded else {
                showToast("Meal Prep draft could not be saved")
                return
            }
        } else if let draft = mealPrepDraft,
                  shoppingScope != draft.shoppingScope || activeShoppingSessionID != nil {
            // Leave the historical trip frozen in shoppingSessions and return
            // explicitly to the independently persisted editable work.
            let succeeded = performAtomicMealPrepTransition {
                shoppingScope = draft.shoppingScope
                activeShoppingSessionID = nil
                shoppingItems = []
                guidedIndex = 0
            }
            guard succeeded else {
                showToast("Meal Prep draft could not be opened")
                return
            }
        }
        selectedTab = .home
        if let plan = currentMealPrepPlan {
            homePath = [.mealPrepSelection, .mealPrepReview]
            if plan.unresolvedReviewCount == 0 {
                homePath.append(.recipeReady)
            }
        } else {
            homePath = [.mealPrepSelection]
        }
    }

    func isRecipeSelectedForMealPrep(_ recipeID: UUID) -> Bool {
        mealPrepDraft?.selections.contains { $0.recipeSnapshot.id == recipeID } == true
    }

    func toggleMealPrepRecipe(_ recipe: Recipe) {
        var draft = mealPrepDraft ?? MealPrepDraft()
        if let index = draft.selections.firstIndex(where: { $0.recipeSnapshot.id == recipe.id }) {
            draft.selections.remove(at: index)
            draft.updatedAt = .now
        } else if draft.selections.count < MealPrepDraft.selectionLimit {
            draft.selections.append(
                MealPrepSelection(recipe: recipe, targetServings: Double(max(1, recipe.servings)))
            )
            draft.updatedAt = .now
        } else {
            showToast("Meal Prep supports up to five recipes in this beta")
            return
        }
        updateMealPrepDraftAndPlan(draft)
    }

    func updateMealPrepServings(selectionID: UUID, delta: Double) {
        guard var draft = mealPrepDraft,
              let index = draft.selections.firstIndex(where: { $0.id == selectionID }) else { return }
        draft.selections[index].targetServings = min(48, max(1, draft.selections[index].targetServings + delta))
        draft.updatedAt = .now
        updateMealPrepDraftAndPlan(draft)
    }

    @discardableResult
    func buildMealPrepPlan() -> Bool {
        guard let draft = mealPrepDraft else { return false }
        let succeeded = performAtomicMealPrepTransition {
            let rebuilt = try rebuiltMealPrepPlan(
                draft: draft,
                preserving: currentMealPrepPlan,
                pantryInventory: pantryInventory
            )
            mealPrepPlan = rebuilt
            shoppingScope = draft.shoppingScope
            invalidateShoppingPlan()
        }
        if succeeded {
            homePath = [.mealPrepSelection, .mealPrepReview]
            return true
        }
        showToast("Meal Prep plan could not be saved")
        return false
    }

    func confirmMealPrepLineSeparate(_ lineID: String) {
        guard var decisions = mealPrepPlan,
              let index = decisions.lines.firstIndex(where: { $0.id == lineID }),
              !decisions.lines[index].mergeReviewReasons.contains(.alternative),
              !decisions.lines[index].mergeReviewReasons.contains(.uncertainQuantity) else { return }
        decisions.lines[index].mergeReviewState = .confirmedSeparate
        decisions.updatedAt = .now
        rebuildMealPrepPlanPreservingDecisions(decisions)
    }

    func confirmMealPrepQuantity(_ lineID: String) {
        guard var decisions = mealPrepPlan,
              let index = decisions.lines.firstIndex(where: { $0.id == lineID }) else { return }
        decisions.lines[index].mergeReviewReasons.remove(.uncertainQuantity)
        if decisions.lines[index].mergeReviewReasons.isEmpty {
            decisions.lines[index].mergeReviewState = .confirmedQuantity
        } else if decisions.lines[index].mergeReviewReasons == [.alternative] {
            decisions.lines[index].mergeReviewState = .alternativeChoice
        } else {
            decisions.lines[index].mergeReviewState = .reviewRequired
        }
        decisions.updatedAt = .now
        rebuildMealPrepPlanPreservingDecisions(decisions)
    }

    func selectMealPrepAlternative(_ lineID: String) {
        guard var decisions = mealPrepPlan,
              let selectedIndex = decisions.lines.firstIndex(where: { $0.id == lineID }),
              let group = decisions.lines[selectedIndex].uncertainDuplicateGroup,
              decisions.lines[selectedIndex].mergeReviewReasons.contains(.alternative) else { return }
        for index in decisions.lines.indices where decisions.lines[index].uncertainDuplicateGroup == group {
            if index == selectedIndex {
                decisions.lines[index].mergeReviewReasons.remove(.alternative)
                decisions.lines[index].mergeReviewState = decisions.lines[index].mergeReviewReasons.isEmpty
                    ? .selectedAlternative
                    : .reviewRequired
            } else {
                decisions.lines[index].mergeReviewReasons.remove(.alternative)
                decisions.lines[index].mergeReviewState = .excludedAlternative
            }
        }
        decisions.updatedAt = .now
        rebuildMealPrepPlanPreservingDecisions(decisions)
    }

    func keepMealPrepAlternativeGroup(_ lineID: String) {
        updateMealPrepAlternativeGroup(lineID: lineID, state: .confirmedSeparate)
    }

    func excludeMealPrepAlternativeGroup(_ lineID: String) {
        updateMealPrepAlternativeGroup(lineID: lineID, state: .excludedAlternative)
    }

    func deferMealPrepAlternativeGroup(_ lineID: String) {
        updateMealPrepAlternativeGroup(lineID: lineID, state: .deferredAlternative)
    }

    func reopenMealPrepAlternativeGroup(lineID: String) {
        guard var decisions = mealPrepPlan,
              let selectedIndex = decisions.lines.firstIndex(where: { $0.id == lineID }),
              let group = decisions.lines[selectedIndex].uncertainDuplicateGroup else { return }
        for index in decisions.lines.indices
        where decisions.lines[index].uncertainDuplicateGroup == group {
            decisions.lines[index].mergeReviewReasons.insert(.alternative)
            decisions.lines[index].mergeReviewState = .alternativeChoice
        }
        decisions.updatedAt = .now
        rebuildMealPrepPlanPreservingDecisions(decisions)
    }

    func restoreDeferredMealPrepAlternativeGroup(_ lineID: String) {
        reopenMealPrepAlternativeGroup(lineID: lineID)
    }

    func setMealPrepPantryOverride(lineID: String, buyFull: Bool) {
        guard var decisions = mealPrepPlan,
              let index = decisions.lines.firstIndex(where: { $0.id == lineID }) else { return }
        decisions.lines[index].buyFullOverride = buyFull
        decisions.updatedAt = .now
        rebuildMealPrepPlanPreservingDecisions(decisions)
    }

    func openMealPrepDashboard() {
        guard currentMealPrepPlan?.unresolvedReviewCount == 0 else {
            showToast("Review every possible duplicate before shopping")
            return
        }
        homePath.append(.recipeReady)
    }

    func beginMealPrepShopping() {
        // The compatibility dashboard now rejoins the shared confirmation
        // surface instead of trying to launch the retired matching route.
        openMealPrepDashboard()
    }

    private func mealPrepIngredient(_ line: CombinedIngredientLine) -> Ingredient? {
        guard line.participatesInCurrentTrip,
              line.quantityToBuy > 0,
              let source = line.sources.first else { return nil }
        return Ingredient(
            id: line.shoppingItemID ?? source.ingredient.id,
            rawText: Ingredient.quantityText(line.quantityToBuy, unit: line.unit.symbol) + " " + line.name,
            name: line.name,
            quantity: line.quantityToBuy,
            unit: line.unit.symbol == "count" ? "" : line.unit.symbol,
            preparation: source.ingredient.preparation,
            category: line.category,
            confidence: source.ingredient.confidence,
            includeInList: true,
            pantryState: .needToBuy,
            preferenceNote: source.ingredient.preferenceNote,
            brandNote: source.ingredient.brandNote,
            alternativeGroup: source.ingredient.alternativeGroup,
            quantityReviewRequired: false
        )
    }

    private func updateMealPrepAlternativeGroup(
        lineID: String,
        state: MergeReviewState
    ) {
        guard var decisions = mealPrepPlan,
              let selectedIndex = decisions.lines.firstIndex(where: { $0.id == lineID }),
              let group = decisions.lines[selectedIndex].uncertainDuplicateGroup else { return }
        for index in decisions.lines.indices where decisions.lines[index].uncertainDuplicateGroup == group {
            if state == .deferredAlternative {
                decisions.lines[index].mergeReviewReasons.insert(.alternative)
            } else {
                decisions.lines[index].mergeReviewReasons.remove(.alternative)
            }
            if decisions.lines[index].mergeReviewReasons.isEmpty {
                decisions.lines[index].mergeReviewState = state
            } else if state == .excludedAlternative || state == .deferredAlternative {
                decisions.lines[index].mergeReviewState = state
            } else {
                decisions.lines[index].mergeReviewState = .reviewRequired
            }
        }
        decisions.updatedAt = .now
        rebuildMealPrepPlanPreservingDecisions(decisions)
    }

    private func updateMealPrepDraftAndPlan(_ draft: MealPrepDraft) {
        let succeeded = performAtomicMealPrepTransition {
            let rebuilt = try mealPrepPlan.map {
                try rebuiltMealPrepPlan(
                    draft: draft,
                    preserving: $0,
                    pantryInventory: pantryInventory
                )
            }
            mealPrepDraft = draft
            mealPrepPlan = rebuilt
            shoppingScope = rebuilt == nil ? nil : draft.shoppingScope
            invalidateShoppingPlan()
        }
        if !succeeded {
            showToast("Meal Prep changes could not be saved")
        }
    }

    private func rebuildMealPrepPlanPreservingDecisions(
        _ decisions: MealPrepPlanSnapshot
    ) {
        guard let draft = mealPrepDraft else { return }
        let succeeded = performAtomicMealPrepTransition {
            mealPrepPlan = try rebuiltMealPrepPlan(
                draft: draft,
                preserving: decisions,
                pantryInventory: pantryInventory
            )
            shoppingScope = draft.shoppingScope
            invalidateShoppingPlan()
        }
        if !succeeded {
            showToast("Meal Prep review change could not be saved")
        }
    }

    private func rebuiltMealPrepPlan(
        draft: MealPrepDraft,
        preserving previous: MealPrepPlanSnapshot?,
        pantryInventory: [PantryInventoryItem]
    ) throws -> MealPrepPlanSnapshot {
        let aggregation = try MealPrepAggregationService.aggregate(
            draft: draft,
            pantryInventory: []
        )
        var rebuilt = MealPrepPlanSnapshot(draft: draft, lines: aggregation.lines)
        let previousByID = Dictionary(uniqueKeysWithValues: (previous?.lines ?? []).map { ($0.id, $0) })

        for index in rebuilt.lines.indices {
            guard let old = previousByID[rebuilt.lines[index].id] else { continue }
            rebuilt.lines[index].shoppingItemID = old.shoppingItemID ?? rebuilt.lines[index].shoppingItemID
            rebuilt.lines[index].mergeReviewState = old.mergeReviewState
            rebuilt.lines[index].mergeReviewReasons = old.mergeReviewReasons
            rebuilt.lines[index].uncertainDuplicateGroup = old.uncertainDuplicateGroup
            rebuilt.lines[index].buyFullOverride = old.buyFullOverride
        }

        MealPrepAggregationService.recomputePantry(pantryInventory, for: &rebuilt.lines)
        rebuilt.updatedAt = .now
        return rebuilt
    }

    private struct MealPrepTransitionBackup {
        var activeRecipe: Recipe
        var draft: MealPrepDraft?
        var plan: MealPrepPlanSnapshot?
        var scope: ShoppingScope?
        var shoppingItems: [ShoppingListItem]
        var guidedIndex: Int
        var activeSessionID: UUID?
        var pantryInventory: [PantryInventoryItem]
    }

    private struct IngredientDeletionBackup {
        var activeRecipe: Recipe
        var recipes: [Recipe]
        var shoppingItems: [ShoppingListItem]
        var activeShoppingSessionID: UUID?
        var guidedIndex: Int
        var matchProgress: Double
        var matchStage: String
        var isMatching: Bool
    }

    @discardableResult
    private func performAtomicMealPrepTransition(
        _ mutation: () throws -> Void
    ) -> Bool {
        guard persistenceReady else { return false }
        let backup = MealPrepTransitionBackup(
            activeRecipe: activeRecipe,
            draft: mealPrepDraft,
            plan: mealPrepPlan,
            scope: shoppingScope,
            shoppingItems: shoppingItems,
            guidedIndex: guidedIndex,
            activeSessionID: activeShoppingSessionID,
            pantryInventory: pantryInventory
        )
        suppressPersistence = true
        do {
            try mutation()
            try stateStore.save(stateSnapshot())
            persistenceIssue = nil
            suppressPersistence = false
            return true
        } catch {
            activeRecipe = backup.activeRecipe
            mealPrepDraft = backup.draft
            mealPrepPlan = backup.plan
            shoppingScope = backup.scope
            shoppingItems = backup.shoppingItems
            guidedIndex = backup.guidedIndex
            activeShoppingSessionID = backup.activeSessionID
            pantryInventory = backup.pantryInventory
            persistenceIssue = error.localizedDescription
            suppressPersistence = false
            return false
        }
    }

    func scaledQuantity(for ingredient: Ingredient) -> Double {
        guard activeRecipe.servings > 0 else { return ingredient.quantity }
        return ingredient.quantity * Double(desiredServings) / Double(activeRecipe.servings)
    }

    func scaledQuantityText(for ingredient: Ingredient) -> String {
        Ingredient.quantityText(scaledQuantity(for: ingredient), unit: ingredient.unit)
    }

    func quantityToBuy(for ingredient: Ingredient) -> Double {
        PantryMatchingService.quantityToBuy(
            for: ingredient,
            requiredQuantity: scaledQuantity(for: ingredient)
        )
    }

    func quantityToBuyText(for ingredient: Ingredient) -> String {
        Ingredient.quantityText(quantityToBuy(for: ingredient), unit: ingredient.unit)
    }

    func updateServings(by delta: Int) {
        desiredServings = min(24, max(1, desiredServings + delta))
        refreshPantrySuggestions()
        invalidateShoppingPlan()
    }

    @discardableResult
    func updateIngredient(id: UUID, with updatedIngredient: Ingredient) -> Bool {
        guard updatedIngredient.id == id,
              let index = activeRecipe.ingredients.firstIndex(where: { $0.id == id })
        else { return false }
        activeRecipe.ingredients[index] = updatedIngredient
        return true
    }

    @discardableResult
    func removeIngredient(id: UUID) -> Bool {
        guard let index = activeRecipe.ingredients.firstIndex(where: { $0.id == id }) else {
            return false
        }

        var updatedRecipe = activeRecipe
        updatedRecipe.ingredients.remove(at: index)
        rebuildSharedPantryAllocations(in: &updatedRecipe, mode: .deletionRebuild)

        var updatedRecipes = recipes
        if let recipeIndex = updatedRecipes.firstIndex(where: { $0.id == updatedRecipe.id }) {
            updatedRecipes[recipeIndex] = updatedRecipe
        } else {
            updatedRecipes.insert(updatedRecipe, at: 0)
        }

        let hadActiveSession = activeShoppingSessionID != nil
        let updatedShoppingItems = hadActiveSession
            ? []
            : refreshedPreTripItems(
                afterRemoving: id,
                using: updatedRecipe
            )
        let backup = IngredientDeletionBackup(
            activeRecipe: activeRecipe,
            recipes: recipes,
            shoppingItems: shoppingItems,
            activeShoppingSessionID: activeShoppingSessionID,
            guidedIndex: guidedIndex,
            matchProgress: matchProgress,
            matchStage: matchStage,
            isMatching: isMatching
        )

        guard persistIngredientDeletion(
            recipe: updatedRecipe,
            recipes: updatedRecipes,
            shoppingItems: updatedShoppingItems,
            activeShoppingSessionID: hadActiveSession ? nil : activeShoppingSessionID,
            backup: backup
        ) else { return false }

        matchingGeneration &+= 1
        matchProgress = 0
        matchStage = "Ready to match"
        isMatching = false
        return true
    }

    private enum SharedPantryAllocationMode {
        case deletionRebuild
        case explicitUseSafeMatches
    }

    private func rebuildSharedPantryAllocations(
        in recipe: inout Recipe,
        mode: SharedPantryAllocationMode
    ) {
        var remainingInventory = pantryInventory
        let multiplier = Double(desiredServings) / Double(max(1, recipe.servings))

        for index in recipe.ingredients.indices {
            let previousDecision = recipe.ingredients[index].pantryDecision
            let previousSuggestion = recipe.ingredients[index].pantrySuggestion
            let requiredQuantity = recipe.ingredients[index].quantity * multiplier
            let suggestion = PantryMatchingService.bestSuggestion(
                for: recipe.ingredients[index],
                requiredQuantity: requiredQuantity,
                inventory: remainingInventory
            )
            recipe.ingredients[index].pantrySuggestion = suggestion

            if mode == .deletionRebuild, previousDecision == .buyFull {
                recipe.ingredients[index].pantryDecision = .buyFull
                recipe.ingredients[index].pantryState = .needToBuy
                continue
            }

            guard recipe.ingredients[index].includeInList,
                  let suggestion,
                  suggestion.coverage != .possible,
                  suggestion.availableQuantity > 0,
                  let pantryIndex = remainingInventory.firstIndex(where: {
                      $0.id == suggestion.pantryItemID
                  }) else {
                if previousDecision == .useAvailable || suggestion != nil {
                    recipe.ingredients[index].pantryDecision = .review
                    recipe.ingredients[index].pantryState = .alwaysAsk
                } else {
                    recipe.ingredients[index].pantryDecision = nil
                }
                continue
            }

            let wasBlockedByExhaustedSharedStock = previousDecision == .review &&
                previousSuggestion?.pantryItemID == suggestion.pantryItemID &&
                (previousSuggestion?.availableQuantity ?? .infinity) <= 0.0001
            let shouldUseAvailable = mode == .explicitUseSafeMatches ||
                previousDecision == .useAvailable ||
                wasBlockedByExhaustedSharedStock
            guard shouldUseAvailable else {
                recipe.ingredients[index].pantryDecision = .review
                recipe.ingredients[index].pantryState = .alwaysAsk
                continue
            }

            var pantryItem = remainingInventory[pantryIndex]
            let amountUsed = min(requiredQuantity, suggestion.availableQuantity)
            guard let pantryAmountUsed = PantryMatchingService.convertedQuantity(
                amountUsed,
                from: recipe.ingredients[index].unit,
                to: pantryItem.remainingUnit
            ) else {
                recipe.ingredients[index].pantryDecision = .review
                recipe.ingredients[index].pantryState = .alwaysAsk
                continue
            }

            recipe.ingredients[index].pantryDecision = .useAvailable
            recipe.ingredients[index].pantryState = .runningLow
            pantryItem.remainingAmount = max(0, pantryItem.remainingAmount - pantryAmountUsed)
            remainingInventory[pantryIndex] = pantryItem
        }
    }

    private func refreshedPreTripItems(
        afterRemoving removedIngredientID: UUID,
        using recipe: Recipe
    ) -> [ShoppingListItem] {
        let ingredientsByID = Dictionary(
            uniqueKeysWithValues: recipe.ingredients.map { ($0.id, $0) }
        )
        let multiplier = Double(desiredServings) / Double(max(1, recipe.servings))

        return shoppingItems.compactMap { existing in
            guard existing.ingredient.id != removedIngredientID,
                  let ingredient = ingredientsByID[existing.ingredient.id] else { return nil }
            guard ingredient != existing.ingredient else { return existing }

            let requestedQuantity = PantryMatchingService.quantityToBuy(
                for: ingredient,
                requiredQuantity: ingredient.quantity * multiplier
            )
            guard requestedQuantity > 0 else { return nil }

            var refreshed = existing
            refreshed.ingredient = ingredient
            refreshed.requestedQuantity = Ingredient.quantityText(
                requestedQuantity,
                unit: ingredient.unit
            )
            refreshed.requestedAmount = requestedQuantity
            refreshed.purchaseQuantity = PackageMath.packageCount(
                product: refreshed.product,
                requestedQuantity: requestedQuantity,
                requestedUnit: ingredient.unit
            )
            refreshed.matchingInputFingerprint = matchingInputFingerprint(
                contextFingerprint: refreshed.matchingContextFingerprint ?? matchingContextFingerprint(
                    for: ingredient,
                    retailerID: selectedRetailer.rawValue,
                    store: primaryStore,
                    fulfillmentMethod: fulfillmentMode == .pickup ? .pickup : .delivery,
                    preferences: preferences
                ),
                requestedQuantity: requestedQuantity,
                pantryDecision: ingredient.pantryDecision,
                pantryState: ingredient.pantryState
            )
            return refreshed
        }
    }

    private func persistIngredientDeletion(
        recipe: Recipe,
        recipes updatedRecipes: [Recipe],
        shoppingItems updatedShoppingItems: [ShoppingListItem],
        activeShoppingSessionID updatedSessionID: UUID?,
        backup: IngredientDeletionBackup
    ) -> Bool {
        guard persistenceReady else { return false }

        suppressPersistence = true
        activeRecipe = recipe
        recipes = updatedRecipes
        shoppingItems = updatedShoppingItems
        activeShoppingSessionID = updatedSessionID
        guidedIndex = 0
        suppressPersistence = false

        do {
            try stateStore.save(stateSnapshot())
            persistenceIssue = nil
            return true
        } catch {
            suppressPersistence = true
            activeRecipe = backup.activeRecipe
            recipes = backup.recipes
            shoppingItems = backup.shoppingItems
            activeShoppingSessionID = backup.activeShoppingSessionID
            guidedIndex = backup.guidedIndex
            suppressPersistence = false
            matchProgress = backup.matchProgress
            matchStage = backup.matchStage
            isMatching = backup.isMatching
            persistenceIssue = error.localizedDescription
            return false
        }
    }

    func setPantryDecision(_ decision: PantryDecision, for ingredientID: UUID) {
        guard let index = activeRecipe.ingredients.firstIndex(where: { $0.id == ingredientID }) else { return }
        activeRecipe.ingredients[index].pantryDecision = decision
        switch decision {
        case .useAvailable:
            activeRecipe.ingredients[index].pantryState = .runningLow
        case .buyFull:
            activeRecipe.ingredients[index].pantryState = .needToBuy
        case .review:
            activeRecipe.ingredients[index].pantryState = .alwaysAsk
        }
        invalidateShoppingPlan()
    }

    func refreshPantrySuggestions() {
        guard persistenceReady else { return }
        var recipe = activeRecipe
        applyPantrySuggestions(to: &recipe)
        activeRecipe = recipe
    }

    private func applyPantrySuggestions(
        to recipe: inout Recipe,
        inventory: [PantryInventoryItem]? = nil
    ) {
        let inventory = inventory ?? pantryInventory
        let multiplier = Double(desiredServings) / Double(max(1, recipe.servings))
        for index in recipe.ingredients.indices {
            let previousItemID = recipe.ingredients[index].pantrySuggestion?.pantryItemID
            let suggestion = PantryMatchingService.bestSuggestion(
                for: recipe.ingredients[index],
                requiredQuantity: recipe.ingredients[index].quantity * multiplier,
                inventory: inventory
            )
            recipe.ingredients[index].pantrySuggestion = suggestion
            if suggestion == nil {
                recipe.ingredients[index].pantryDecision = nil
            } else if previousItemID != suggestion?.pantryItemID || recipe.ingredients[index].pantryDecision == nil {
                recipe.ingredients[index].pantryDecision = .review
                recipe.ingredients[index].pantryState = .alwaysAsk
            }
        }
    }

    @discardableResult
    private func commitPantryInventoryChange(
        _ updatedInventory: [PantryInventoryItem]
    ) -> Bool {
        var updatedRecipe = activeRecipe
        applyPantrySuggestions(to: &updatedRecipe, inventory: updatedInventory)
        return performAtomicMealPrepTransition {
            pantryInventory = updatedInventory
            activeRecipe = updatedRecipe
            if let draft = mealPrepDraft, let plan = currentMealPrepPlan {
                mealPrepPlan = try rebuiltMealPrepPlan(
                    draft: draft,
                    preserving: plan,
                    pantryInventory: updatedInventory
                )
                shoppingScope = draft.shoppingScope
                invalidateShoppingPlan()
            }
        }
    }

    func continueTo(_ route: SmartRoute) {
        if route == .matching {
            // Preferences, pantry decisions, servings, or store selection may
            // have changed while navigating back. Rebuild from the confirmed
            // recipe instead of reusing product matches from an older plan.
            if !isMealPrepShopping {
                synchronizeActiveRecipeRecord()
            }
            invalidateShoppingPlan()
        }
        homePath.append(route)
    }

    func commitIngredientReview() {
        synchronizeActiveRecipeRecord()
        invalidateShoppingPlan()
        track(
            .ingredientsCorrected,
            properties: [
                "included": String(includedIngredientCount),
                "review_required": String(unresolvedQuantityReviewCount)
            ]
        )
        continueTo(.servingAdjustment)
    }

    var recipeReadyBlockingIssueCount: Int {
        if isMealPrepShopping {
            return currentShoppingMealPrepSnapshot?.unresolvedReviewCount ?? 0
        }
        return unresolvedQuantityReviewCount + unresolvedAlternativeCount
    }

    var recipeReadyPantrySuggestionCount: Int {
        if isMealPrepShopping {
            return currentShoppingMealPrepSnapshot?.lines.filter {
                $0.participatesInCurrentTrip && !$0.pantryDeductions.isEmpty
            }.count ?? 0
        }
        return activeRecipe.ingredients.filter {
            $0.includeInList && $0.pantrySuggestion != nil
        }.count
    }

    var recipeReadyExpectedPurchaseCount: Int {
        ingredientsToBuy.count
    }

    var recipeReadyCanStartShopping: Bool {
        recipeReadyBlockingIssueCount == 0 && !ingredientsToBuy.isEmpty
    }

    var recipeReadyDisabledExplanation: String? {
        if recipeReadyBlockingIssueCount > 0 {
            return "Resolve \(recipeReadyBlockingIssueCount) ingredient issue\(recipeReadyBlockingIssueCount == 1 ? "" : "s") before shopping."
        }
        if ingredientsToBuy.isEmpty {
            return "Include at least one ingredient that still needs to be purchased."
        }
        return nil
    }

    func useSafePantrySuggestions() {
        guard !isMealPrepShopping else { return }
        var recipe = activeRecipe
        rebuildSharedPantryAllocations(in: &recipe, mode: .explicitUseSafeMatches)
        activeRecipe = recipe
        invalidateShoppingPlan()
    }

    func buyFullRecipeReadyIngredients() {
        guard !isMealPrepShopping else { return }
        for index in activeRecipe.ingredients.indices where activeRecipe.ingredients[index].includeInList {
            activeRecipe.ingredients[index].pantryDecision = .buyFull
            activeRecipe.ingredients[index].pantryState = .needToBuy
        }
        invalidateShoppingPlan()
    }

    @discardableResult
    func beginShoppingFromRecipeReady() -> Bool {
        guard recipeReadyCanStartShopping else {
            if let explanation = recipeReadyDisabledExplanation {
                showToast(explanation)
            }
            return false
        }
        if !isMealPrepShopping {
            synchronizeActiveRecipeRecord()
            track(
                .ingredientsCorrected,
                properties: [
                    "included": String(includedIngredientCount),
                    "review_required": String(unresolvedQuantityReviewCount)
                ]
            )
        }
        prepareRetailerSafariWorkflow()
        invalidateShoppingPlan()
        selectedTab = .home
        return true
    }

    private func synchronizeActiveRecipeRecord() {
        if let index = recipes.firstIndex(where: { $0.id == activeRecipe.id }) {
            recipes[index] = activeRecipe
        } else {
            recipes.insert(activeRecipe, at: 0)
        }
    }

    private func invalidateShoppingPlan(preservingMatches: Bool = true) {
        matchingGeneration &+= 1
        // Waiting pre-trip matches are a cache. Keep them long enough for the
        // next matching pass to reconcile unchanged inputs selectively. Once
        // a retailer session exists, its snapshot is historical trip state and
        // must never become that cache; detach and rebuild an editable plan.
        if !preservingMatches || activeShoppingSessionID != nil {
            shoppingItems = []
            activeShoppingSessionID = nil
        }
        matchProgress = 0
        matchStage = "Ready to match"
        isMatching = false
        guidedIndex = 0
    }

    func setStoreStrategy(_ strategy: StoreStrategy) {
        guard featureFlags.advancedToolsEnabled || strategy == .oneStore else {
            storeStrategy = .oneStore
            showToast("Multiple-stop planning is an experimental advanced tool")
            return
        }

        storeStrategy = strategy
        if storeStrategy == .oneStore {
            retainOnlyStore(primaryStore.id, for: selectedRetailer)
        } else if selectedStores.count == 1,
                  let second = storesForSelectedRetailer.first(where: { !selectedStoreIDs.contains($0.id) }) {
            selectedStoreIDs.insert(second.id)
        }
        invalidateShoppingPlan()
    }

    func selectStore(_ store: RetailerStore) {
        guard store.retailerID == selectedRetailer.rawValue else { return }
        retainOnlyStore(store.id, for: selectedRetailer)
        invalidateShoppingPlan(preservingMatches: false)
    }

    func startRetailerGuide(_ retailer: ShoppingRetailer) {
        let configuration = retailer.configuration
        guard retailerEngine.supports(retailer) else {
            showToast("\(configuration.displayName) support is coming soon")
            return
        }

        let retailerChanged = selectedRetailer != retailer
        selectedRetailer = retailer
        if let store = stores.first(where: { $0.retailerID == retailer.rawValue }) {
            retainOnlyStore(store.id, for: retailer)
        }
        if retailerChanged || shoppingItems.contains(where: { $0.product.retailerID != retailer.rawValue }) {
            invalidateShoppingPlan(preservingMatches: false)
        }
    }

    func prepareRetailerSafariWorkflow() {
        if selectedStores.isEmpty,
           let store = storesForSelectedRetailer.first {
            retainOnlyStore(store.id, for: selectedRetailer)
        }
    }

    func prepareWalmartSafariWorkflow() {
        startRetailerGuide(.walmart)
    }

    private func retainOnlyStore(_ storeID: UUID, for retailer: ShoppingRetailer) {
        let retailerStoreIDs = Set(
            stores.filter { $0.retailerID == retailer.rawValue }.map(\.id)
        )
        selectedStoreIDs.subtract(retailerStoreIDs)
        selectedStoreIDs.insert(storeID)
    }

    func setAdvancedToolsEnabled(_ enabled: Bool) {
        featureFlags.advancedToolsEnabled = enabled
        guard !enabled else { return }
        storeStrategy = .oneStore
        fulfillmentMode = .pickup
        retainOnlyStore(primaryStore.id, for: selectedRetailer)
    }

    func startMatching(force: Bool = false) async {
        prepareRetailerSafariWorkflow()
        matchingGeneration &+= 1
        let generation = matchingGeneration
        let mayReusePreTripItems = activeShoppingSessionID == nil && !force
        let reusableItems = mayReusePreTripItems ? shoppingItems : []
        if activeShoppingSessionID != nil {
            // Preserve the session-owned snapshot in `shoppingSessions`; the
            // newly matched list is an independent editable fork.
            shoppingItems = []
            activeShoppingSessionID = nil
        }
        isMatching = true
        matchProgress = 0
        matchStage = "Matching products"
        matchProgress = 0.1

        let matchedItems = await buildShoppingItems(reusing: reusableItems)
        guard !Task.isCancelled, generation == matchingGeneration else { return }
        shoppingItems = matchedItems
        withAnimation(.easeOut(duration: 0.35)) {
            matchProgress = 1
        }
        matchStage = "\(matchedItemCount) exact products · \(searchFallbackCount) searches"
        isMatching = false
        track(
            .matchingCompleted,
            properties: [
                "items": String(shoppingItems.count),
                "exact_links": String(matchedItemCount),
                "fallbacks": String(searchFallbackCount),
                "retailer": selectedRetailer.rawValue
            ]
        )
    }

    @discardableResult
    func acceptMatchingException(itemID: UUID) -> Bool {
        guard activeShoppingSessionID == nil,
              let index = shoppingItems.firstIndex(where: { $0.id == itemID }),
              shoppingItems[index].status == .waiting,
              !matchingExceptionReasons(for: shoppingItems[index]).isEmpty else { return false }
        ensureMatchingFingerprints(at: index)
        shoppingItems[index].reviewedMatchingFingerprint = shoppingItems[index].matchingInputFingerprint
        return true
    }

    @discardableResult
    func skipMatchingException(itemID: UUID) -> Bool {
        guard activeShoppingSessionID == nil,
              let index = shoppingItems.firstIndex(where: { $0.id == itemID }),
              shoppingItems[index].status == .waiting,
              !matchingExceptionReasons(for: shoppingItems[index]).isEmpty else { return false }
        ensureMatchingFingerprints(at: index)
        shoppingItems[index].reviewedMatchingFingerprint = shoppingItems[index].matchingInputFingerprint
        shoppingItems[index].status = .skipped
        return true
    }

    @discardableResult
    func applyMatchingExceptionDecisions(_ shouldOrderByItemID: [UUID: Bool]) -> Bool {
        guard persistenceReady, activeShoppingSessionID == nil else { return false }

        let unresolvedIDs = Set(unresolvedMatchingExceptionItems.map(\.id))
        guard !unresolvedIDs.isEmpty,
              Set(shouldOrderByItemID.keys) == unresolvedIDs else {
            showToast("Product choices changed. Review the updated list and try again.")
            return false
        }

        let originalItems = shoppingItems
        suppressPersistence = true

        for itemID in unresolvedIDs {
            guard let index = shoppingItems.firstIndex(where: { $0.id == itemID }) else {
                shoppingItems = originalItems
                suppressPersistence = false
                return false
            }
            ensureMatchingFingerprints(at: index)
            shoppingItems[index].reviewedMatchingFingerprint = shoppingItems[index].matchingInputFingerprint
            if shouldOrderByItemID[itemID] == false {
                shoppingItems[index].status = .skipped
            }
        }

        guard shoppingItems.contains(where: { $0.status == .waiting }) else {
            shoppingItems = originalItems
            suppressPersistence = false
            showToast("Keep at least one shopping item before continuing")
            return false
        }

        suppressPersistence = false
        do {
            try stateStore.save(stateSnapshot())
            persistenceIssue = nil
            return true
        } catch {
            suppressPersistence = true
            shoppingItems = originalItems
            suppressPersistence = false
            persistenceIssue = error.localizedDescription
            showToast("Product choices could not be saved")
            return false
        }
    }

    @discardableResult
    func continueToShoppingTrip() -> Bool {
        guard !shoppingItems.isEmpty else {
            showToast("Match at least one shopping item before continuing")
            return false
        }
        guard unresolvedMatchingExceptionItems.isEmpty else {
            showToast("Review or skip every matching exception before continuing")
            return false
        }
        guard shoppingItems.contains(where: { $0.status == .waiting }) else {
            showToast("Keep at least one shopping item before continuing")
            return false
        }
        selectedTab = .home
        if homePath.last != .shoppingTrip {
            homePath.append(.shoppingTrip)
        }
        return true
    }

    func updatePurchaseQuantity(for itemID: UUID, delta: Int) {
        guard !activeShoppingSessionIsImmutable else {
            showToast("Completed trips are read-only. Edit as a new trip instead.")
            return
        }
        guard let index = shoppingItems.firstIndex(where: { $0.id == itemID }) else { return }
        shoppingItems[index].purchaseQuantity = max(1, shoppingItems[index].purchaseQuantity + delta)
    }

    @discardableResult
    func selectAlternative(itemID: UUID, candidateID: UUID) -> Bool {
        guard persistenceReady,
            !activeShoppingSessionIsImmutable,
            let itemIndex = shoppingItems.firstIndex(where: { $0.id == itemID }),
            let candidateIndex = shoppingItems[itemIndex].alternatives.firstIndex(where: { $0.id == candidateID })
        else { return false }
        let candidate = shoppingItems[itemIndex].alternatives[candidateIndex]
        guard let replacementPackageCount = resolvedReplacementPackageCount(
            for: shoppingItems[itemIndex],
            product: candidate
        ) else {
            showToast("Confirm a compatible package size before replacing this product")
            return false
        }

        let originalItems = shoppingItems
        let originalSessions = shoppingSessions
        let originalLists = savedLists
        let originalPreferences = preferredProductIDsByIngredient
        let originalEvents = analyticsEvents
        let manifestProgress = currentSavedManifest?.handoffProgress
        suppressPersistence = true

        let previous = shoppingItems[itemIndex].product
        let replacement = shoppingItems[itemIndex].alternatives.remove(at: candidateIndex)
        shoppingItems[itemIndex].alternatives.append(previous)
        shoppingItems[itemIndex].product = replacement
        shoppingItems[itemIndex].purchaseQuantity = replacementPackageCount
        ensureMatchingFingerprints(at: itemIndex)
        shoppingItems[itemIndex].reviewedMatchingFingerprint = matchingExceptionReasons(
            for: shoppingItems[itemIndex]
        ).isEmpty ? shoppingItems[itemIndex].matchingInputFingerprint : nil
        if let activeShoppingSessionID {
            synchronizeCurrentShoppingSessionItems(sessionID: activeShoppingSessionID)
        }
        preferredProductIDsByIngredient[productPreferenceKey(
            for: shoppingItems[itemIndex].ingredient.name,
            retailerID: replacement.retailerID
        )] = replacement.retailerProductID
        track(.productReplaced, properties: ["link_kind": replacement.linkKind.rawValue])
        if let manifestProgress {
            persistCurrentManifest(progress: manifestProgress)
        }
        do {
            try stateStore.save(stateSnapshot())
            persistenceIssue = nil
            suppressPersistence = false
            showToast("Product replacement selected")
            return true
        } catch {
            shoppingItems = originalItems
            shoppingSessions = originalSessions
            savedLists = originalLists
            preferredProductIDsByIngredient = originalPreferences
            analyticsEvents = originalEvents
            suppressPersistence = false
            persistenceIssue = error.localizedDescription
            showToast("Product replacement could not be saved")
            return false
        }
    }

    private func requestedQuantityForShoppingItem(_ item: ShoppingListItem) -> Double {
        if let requestedAmount = item.requestedAmount,
           requestedAmount.isFinite,
           requestedAmount >= 0 {
            return requestedAmount
        }
        if isMealPrepShopping { return item.ingredient.quantity }
        return PantryMatchingService.quantityToBuy(
            for: item.ingredient,
            requiredQuantity: scaledQuantity(for: item.ingredient)
        )
    }

    func resolvedReplacementPackageCount(
        for item: ShoppingListItem,
        product: RetailerProductRecord
    ) -> Int? {
        PackageMath.resolvedPackageCount(
            product: product,
            requestedQuantity: requestedQuantityForShoppingItem(item),
            requestedUnit: item.ingredient.unit
        )
    }

    func markCurrentGuidedItem(_ status: GuidedItemStatus) {
        guard !activeShoppingSessionIsImmutable else { return }
        guard shoppingItems.indices.contains(guidedIndex) else { return }
        shoppingItems[guidedIndex].status = status
        track(.guidedItemCompleted, properties: ["status": status.rawValue])
        persistCurrentManifest(progress: .inProgress)
    }

    func advanceGuidedItem() {
        guard let sessionID = activeShoppingSessionID,
              let item = currentGuidedItem,
              item.status == .waiting else { return }
        _ = recordRetailerOutcome(.visited, for: item.id, sessionID: sessionID)
    }

    func moveGuidedItem(by delta: Int) {
        guard !shoppingItems.isEmpty else { return }
        guidedIndex = min(shoppingItems.count - 1, max(0, guidedIndex + delta))
    }

    func saveCurrentList() {
        persistCurrentManifest(progress: currentSavedManifest?.handoffProgress ?? .notStarted)
        showToast("Shopping list saved")
    }

    func beginGuidedShopping() {
        continueTo(.shoppingTrip)
    }

    @discardableResult
    func startOrResumeRetailerShoppingSession() -> Bool {
        guard persistenceReady else {
            showToast(persistenceIssue ?? "SmartCart storage is unavailable")
            return false
        }
        guard !shoppingItems.isEmpty,
              retailerSetupIsComplete else {
            showToast("Complete retailer setup before starting")
            return false
        }
        guard !retailerGuideIsComplete, !activeShoppingSessionIsImmutable else {
            showToast("Completed trips are read-only. Edit as a new trip instead.")
            return false
        }
        let originalItems = shoppingItems
        let originalIndex = guidedIndex
        let originalLists = savedLists
        let originalSessions = shoppingSessions
        let originalEvents = analyticsEvents
        let originalActiveSessionID = activeShoppingSessionID
        let wasStarted = currentSavedManifest?.handoffProgress == .inProgress ||
            currentSavedManifest?.handoffProgress == .paused

        suppressPersistence = true
        if !shoppingItems.indices.contains(guidedIndex) || shoppingItems[guidedIndex].status.isCompleted {
            guidedIndex = shoppingItems.firstIndex(where: { !$0.status.isCompleted }) ?? 0
        }

        do {
            let sessionID = try createOrReuseCurrentShoppingSession()
            activeShoppingSessionID = sessionID
            persistCurrentManifest(progress: .inProgress)
            if let index = shoppingSessions.firstIndex(where: { $0.id == sessionID }) {
                shoppingSessions[index].items = shoppingItems
                shoppingSessions[index].manifestID = currentSavedManifest?.id
                shoppingSessions[index].retailerID = selectedRetailer.rawValue
                shoppingSessions[index].desiredServings = isMealPrepShopping ? nil : desiredServings
                shoppingSessions[index].fulfillmentMode = fulfillmentMode
                shoppingSessions[index].shoppingScope = shoppingScope ?? .singleRecipe(activeRecipe.id)
                shoppingSessions[index].mealPrepSnapshot = currentShoppingMealPrepSnapshot
            }
            track(
                wasStarted ? .shoppingSessionResumed : .shoppingSessionStarted,
                properties: [
                    "retailer": selectedRetailer.rawValue,
                    "items": String(shoppingItems.count),
                    "remaining": String(retailerSessionRemainingCount)
                ]
            )
            try stateStore.save(stateSnapshot())
            persistenceIssue = nil
            suppressPersistence = false
            return true
        } catch {
            shoppingItems = originalItems
            guidedIndex = originalIndex
            savedLists = originalLists
            shoppingSessions = originalSessions
            analyticsEvents = originalEvents
            activeShoppingSessionID = originalActiveSessionID
            suppressPersistence = false
            persistenceIssue = error.localizedDescription
            showToast("Shopping trip could not be started")
            return false
        }
    }

    @discardableResult
    func pauseRetailerShoppingSession() -> Bool {
        guard persistenceReady else {
            showToast(persistenceIssue ?? "SmartCart storage is unavailable")
            return false
        }
        guard !shoppingItems.isEmpty,
              !retailerGuideIsComplete,
              !activeShoppingSessionIsImmutable,
              let sessionID = activeShoppingSessionID else { return false }
        let originalLists = savedLists
        let originalSessions = shoppingSessions
        let originalEvents = analyticsEvents
        suppressPersistence = true
        persistCurrentManifest(progress: .paused)
        synchronizeCurrentShoppingSessionItems(sessionID: sessionID)
        track(
            .shoppingSessionPaused,
            properties: [
                "retailer": selectedRetailer.rawValue,
                "remaining": String(retailerSessionRemainingCount)
            ]
        )
        do {
            try stateStore.save(stateSnapshot())
            persistenceIssue = nil
            suppressPersistence = false
            showToast("Shopping trip saved")
            return true
        } catch {
            savedLists = originalLists
            shoppingSessions = originalSessions
            analyticsEvents = originalEvents
            suppressPersistence = false
            persistenceIssue = error.localizedDescription
            showToast("Shopping trip could not be paused")
            return false
        }
    }

    /// Native Safari close and an interactive sheet dismissal are ambiguous:
    /// neither proves that the current product was handled. Preserve the
    /// waiting item and pause the durable trip at exactly the same position.
    @discardableResult
    func handleAmbiguousRetailerBrowserDismissal(
        sessionID: UUID,
        itemID: UUID
    ) -> Bool {
        guard activeShoppingSessionID == sessionID,
              currentGuidedItem?.id == itemID,
              currentGuidedItem?.status == .waiting,
              currentSavedManifest?.handoffProgress == .inProgress else { return false }
        return pauseRetailerShoppingSession()
    }

    func completeRetailerSetup() {
        retailerSetupCompletedIDs.insert(selectedRetailer.rawValue)
        track(.retailerSetupCompleted, properties: ["retailer": selectedRetailer.rawValue])
        showToast("\(retailerConfiguration.displayName) setup saved")
    }

    func resetRetailerSetup() {
        retailerSetupCompletedIDs.remove(selectedRetailer.rawValue)
        showToast("\(retailerConfiguration.displayName) setup can be confirmed again")
    }

    @discardableResult
    func openShoppingSession(_ sessionID: UUID) -> Bool {
        guard persistenceReady,
              let session = shoppingSession(id: sessionID),
              !session.items.isEmpty else { return false }
        let retailer = session.retailerID.flatMap(ShoppingRetailer.init(rawValue:)) ??
            session.items.first.flatMap { ShoppingRetailer(rawValue: $0.product.retailerID) } ?? .walmart

        let originalActiveSessionID = activeShoppingSessionID
        let originalShoppingScope = shoppingScope
        let originalRetailer = selectedRetailer
        let originalStoreIDs = selectedStoreIDs
        let originalRecipe = activeRecipe
        let originalDesiredServings = desiredServings
        let originalFulfillmentMode = fulfillmentMode
        let originalItems = shoppingItems
        let originalGuidedIndex = guidedIndex

        suppressPersistence = true
        activeShoppingSessionID = sessionID
        shoppingScope = session.shoppingScope ?? .singleRecipe(session.recipeID)
        selectedRetailer = retailer
        if let store = stores.first(where: { $0.retailerStoreID == session.storeID }) {
            retainOnlyStore(store.id, for: retailer)
        }
        if shoppingScope?.kind == .singleRecipe,
           let recipe = recipes.first(where: { $0.id == session.recipeID }) {
            activeRecipe = recipe
            desiredServings = session.desiredServings ?? recipe.servings
        }
        fulfillmentMode = session.fulfillmentMode ?? fulfillmentMode
        shoppingItems = session.items
        guidedIndex = shoppingItems.firstIndex(where: { !$0.status.isCompleted }) ?? 0
        do {
            try stateStore.save(stateSnapshot())
            persistenceIssue = nil
            suppressPersistence = false
            selectedTab = .home
            homePath = [.shoppingTrip]
            return true
        } catch {
            activeShoppingSessionID = originalActiveSessionID
            shoppingScope = originalShoppingScope
            selectedRetailer = originalRetailer
            selectedStoreIDs = originalStoreIDs
            activeRecipe = originalRecipe
            desiredServings = originalDesiredServings
            fulfillmentMode = originalFulfillmentMode
            shoppingItems = originalItems
            guidedIndex = originalGuidedIndex
            suppressPersistence = false
            persistenceIssue = error.localizedDescription
            showToast("Shopping trip could not be opened")
            return false
        }
    }

    func openSavedList(_ listID: UUID) {
        guard let saved = savedLists.first(where: { $0.id == listID }) else { return }
        let manifest = saved.manifest
        let identitySession = manifest.logicalTripID.flatMap { logicalTripID in
            shoppingSessions
                .filter { $0.reconciliationIdentity == logicalTripID }
                .max { $0.startedAt < $1.startedAt }
        }
        let manifestSession = shoppingSessions
            .filter { $0.manifestID == manifest.id }
            .max { $0.startedAt < $1.startedAt }
        if let session = identitySession ?? manifestSession {
            if openShoppingSession(session.id) {
                homePath = [.shoppingList]
            }
            return
        }
        let retailer = ShoppingRetailer(rawValue: manifest.retailerID) ?? .walmart
        let store = stores.first(where: { $0.retailerStoreID == manifest.storeID }) ?? primaryStore
        let recipe = recipes.first(where: { $0.id == manifest.recipeID })

        suppressPersistence = true
        activeShoppingSessionID = nil
        shoppingScope = manifest.shoppingScope ?? .singleRecipe(manifest.recipeID)
        selectedRetailer = retailer
        retainOnlyStore(store.id, for: retailer)
        if shoppingScope?.kind == .singleRecipe, let recipe {
            activeRecipe = recipe
        }
        desiredServings = manifest.desiredServings
        fulfillmentMode = manifest.fulfillmentMode
        shoppingItems = manifest.items.map { line in
            let source = line.sourceContributions?.first
            let ingredient = recipe?.ingredients.first(where: { $0.id == line.ingredientID }) ?? Ingredient(
                id: line.ingredientID,
                name: line.ingredientName,
                quantity: source?.scaledQuantity ?? 1,
                unit: source?.ingredient.unit ?? "",
                category: source?.ingredient.category ?? .pantry
            )
            return ShoppingListItem(
                id: line.id,
                ingredient: ingredient,
                requestedQuantity: line.requestedQuantity,
                requestedAmount: line.requestedAmount,
                purchaseQuantity: line.purchaseQuantity,
                product: line.product,
                alternatives: [],
                storeID: store.id,
                status: line.status,
                matchScore: 0,
                selectionReasons: ["Restored from saved list"]
            )
        }
        guidedIndex = shoppingItems.firstIndex(where: { !$0.status.isCompleted }) ?? 0
        suppressPersistence = false
        persistState()

        selectedTab = .home
        homePath = [.shoppingList]
    }

    func retailerSetupURL() -> URL {
        retailerConfiguration.listURL
    }

    func recordWalmartSetupStarted() {
        track(.walmartSetupStarted)
    }

    func recordRetailerSetupStarted() {
        track(.retailerSetupStarted, properties: ["retailer": selectedRetailer.rawValue])
        if selectedRetailer == .walmart {
            recordWalmartSetupStarted()
        }
    }

    func saveWalmartWishlistReference(displayName: String, rawURL: String) throws {
        let url = try WalmartWishlistURLValidator.validate(rawURL)
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = walmartWishlistReference
        walmartWishlistReference = WalmartWishlistReference(
            id: existing?.id ?? UUID(),
            displayName: cleanName.isEmpty ? "SmartCart Groceries" : cleanName,
            sharedURL: url,
            createdAt: existing?.createdAt ?? .now,
            lastOpenedAt: existing?.lastOpenedAt
        )
        track(.walmartWishlistURLSaved, properties: ["reference_saved": "true"])
        showToast("Walmart Wishlist reference saved")
    }

    func removeWalmartWishlistReference() {
        walmartWishlistReference = nil
        showToast("Walmart Wishlist reference removed")
    }

    func recordRetailerProductOpened(itemID: UUID) {
        guard let item = shoppingItems.first(where: { $0.id == itemID }) else { return }
        let properties = [
            "retailer": item.product.retailerID,
            "link_kind": item.product.linkKind.rawValue
        ]
        if item.product.retailerID == ShoppingRetailer.walmart.rawValue {
            track(.walmartProductOpened, properties: properties)
        }
        track(.retailerLinkOpened, properties: properties)
    }

    @discardableResult
    func recordRetailerOutcome(
        _ outcome: GuidedItemStatus,
        for itemID: UUID,
        sessionID requestedSessionID: UUID? = nil
    ) -> Bool {
        guard persistenceReady else {
            showToast(persistenceIssue ?? "SmartCart storage is unavailable")
            return false
        }
        let sessionID = requestedSessionID ?? activeShoppingSessionID
        guard outcome != .waiting,
              let sessionID,
              activeShoppingSessionID == sessionID,
              shoppingSessions.contains(where: { $0.id == sessionID && $0.isReusable }),
              let itemIndex = shoppingItems.firstIndex(where: { $0.id == itemID }),
              shoppingItems[itemIndex].status == .waiting
        else { return false }

        let originalItems = shoppingItems
        let originalIndex = guidedIndex
        let originalLists = savedLists
        let originalSessions = shoppingSessions
        let originalEvents = analyticsEvents
        let retailerID = shoppingItems[itemIndex].product.retailerID
        let wasComplete = retailerGuideIsComplete
        var completedNow = false

        suppressPersistence = true
        shoppingItems[itemIndex].status = outcome
        synchronizeCurrentShoppingSessionItems(sessionID: sessionID)
        track(.guidedItemCompleted, properties: ["status": outcome.rawValue, "retailer": retailerID])
        if retailerID == ShoppingRetailer.walmart.rawValue, outcome == .savedToWishlist {
            track(.walmartProductSelfReportedSaved)
        }

        if let nextIndex = nextWaitingRetailerItem(after: itemIndex) {
            guidedIndex = nextIndex
            persistCurrentManifest(progress: .inProgress)
        } else {
            persistCurrentManifest(progress: .completed)
            if !wasComplete {
                completedNow = true
                let properties = [
                    "retailer": retailerID,
                    "visited": String(retailerVisitedCount),
                    "saved": String(savedForLaterCount),
                    "cart": String(retailerAddedCount),
                    "unavailable": String(retailerUnavailableCount),
                    "skipped": String(retailerSkippedCount)
                ]
                if retailerID == ShoppingRetailer.walmart.rawValue {
                    track(.walmartGuidedFlowCompleted, properties: properties)
                }
                track(.guidedShoppingCompleted, properties: properties)
            }
        }

        do {
            try stateStore.save(stateSnapshot())
            persistenceIssue = nil
            suppressPersistence = false
            if completedNow {
                showToast("\(retailerConfiguration.displayName) shopping trip complete")
            }
            return true
        } catch {
            shoppingItems = originalItems
            guidedIndex = originalIndex
            savedLists = originalLists
            shoppingSessions = originalSessions
            analyticsEvents = originalEvents
            suppressPersistence = false
            persistenceIssue = error.localizedDescription
            showToast("That result could not be saved. Try again.")
            return false
        }
    }

    func recordWalmartProductOpened(itemID: UUID) {
        recordRetailerProductOpened(itemID: itemID)
    }

    func recordWalmartOutcome(_ outcome: GuidedItemStatus, for itemID: UUID) {
        guard let sessionID = activeShoppingSessionID ?? ensureCurrentShoppingSession() else { return }
        recordRetailerOutcome(outcome, for: itemID, sessionID: sessionID)
    }

    func openSavedWalmartWishlist() -> URL? {
        guard var reference = walmartWishlistReference else { return nil }
        reference.lastOpenedAt = .now
        walmartWishlistReference = reference
        track(.walmartWishlistOpened)
        return reference.sharedURL
    }

    func walmartListsURL() -> URL {
        ShoppingRetailer.walmart.configuration.listURL
    }

    func retailerListsURL() -> URL {
        retailerConfiguration.listURL
    }

    func shoppingSession(id: UUID) -> ShoppingSession? {
        shoppingSessions.first { $0.id == id }
    }

    var activeShoppingSessionIsImmutable: Bool {
        guard let sessionID = activeShoppingSessionID,
              let session = shoppingSession(id: sessionID) else { return false }
        return session.isGuideComplete || session.isCommitted
    }

    /// Explicitly forks the displayed completed list into a new editable trip.
    /// The historical session remains byte-for-byte unchanged.
    @discardableResult
    func forkCompletedShoppingTrip() -> Bool {
        guard persistenceReady, activeShoppingSessionIsImmutable else { return false }
        let originalItems = shoppingItems
        let originalLists = savedLists
        let originalActiveSessionID = activeShoppingSessionID
        let originalGuidedIndex = guidedIndex
        let newLogicalTripID = UUID()

        suppressPersistence = true
        shoppingItems = shoppingItems.map { item in
            var editable = item
            editable.status = .waiting
            return editable
        }
        activeShoppingSessionID = nil
        guidedIndex = 0
        persistCurrentManifest(
            progress: .notStarted,
            logicalTripID: newLogicalTripID,
            forceNewTrip: true
        )

        do {
            try stateStore.save(stateSnapshot())
            suppressPersistence = false
            persistenceIssue = nil
            showToast("New editable trip created")
            return true
        } catch {
            shoppingItems = originalItems
            savedLists = originalLists
            activeShoppingSessionID = originalActiveSessionID
            guidedIndex = originalGuidedIndex
            suppressPersistence = false
            persistenceIssue = error.localizedDescription
            showToast("The new trip could not be saved")
            return false
        }
    }

    func saveShoppingReconciliationDraft(
        sessionID: UUID,
        outcome: ShoppingTripOutcome?,
        purchasedItemIDs: Set<UUID>,
        substitutions: [ShoppingSubstitutionFeedback]
    ) {
        guard let index = shoppingSessions.firstIndex(where: { $0.id == sessionID }),
              shoppingSessions[index].reconciliation == nil
        else { return }
        let validIDs = Set(shoppingSessions[index].items.map(\.id))
        shoppingSessions[index].reconciliationDraft = ShoppingReconciliationDraft(
            outcome: outcome,
            purchasedItemIDs: purchasedItemIDs.intersection(validIDs),
            substitutions: substitutions.filter { validIDs.contains($0.originalItemID) },
            updatedAt: .now
        )
    }

    func defaultPurchasedItemIDs(
        for outcome: ShoppingTripOutcome,
        sessionID: UUID
    ) -> Set<UUID> {
        guard let session = shoppingSession(id: sessionID) else { return [] }
        switch outcome {
        case .boughtEverything, .boughtMost:
            return Set(session.items.compactMap { item in
                item.status == .unavailable || item.status == .skipped ? nil : item.id
            })
        case .boughtFew, .didNotShop:
            return []
        }
    }

    @discardableResult
    func ensureCurrentShoppingSession() -> UUID? {
        do {
            if let activeShoppingSessionID,
               let activeSession = shoppingSession(id: activeShoppingSessionID),
               !activeSession.isCommitted,
               (activeSession.isReusable ||
                    (retailerGuideIsComplete && activeSession.isGuideComplete)) {
                if activeSession.isGuideComplete {
                    return activeShoppingSessionID
                }
                let currentFingerprint = shoppingSessionFingerprint(
                    scope: shoppingScope ?? .singleRecipe(activeRecipe.id),
                    retailerID: selectedRetailer.rawValue,
                    storeID: primaryStore.retailerStoreID,
                    fulfillment: fulfillmentMode,
                    plan: currentShoppingMealPrepSnapshot,
                    items: shoppingItems
                )
                if activeSession.stateFingerprint == currentFingerprint {
                    return activeShoppingSessionID
                }
            }
            if retailerGuideIsComplete,
               let recoveredSession = completedUncommittedSessionMatchingCurrentTrip() {
                activeShoppingSessionID = recoveredSession.id
                return recoveredSession.id
            }
            let sessionID = try createOrReuseCurrentShoppingSession()
            activeShoppingSessionID = sessionID
            return sessionID
        } catch {
            persistenceIssue = error.localizedDescription
            showToast("Shopping progress could not be saved")
            return nil
        }
    }

    func startShoppingReconciliation() {
        if let activeShoppingSessionID,
           let activeSession = shoppingSession(id: activeShoppingSessionID) {
            guard !activeSession.isCommitted else {
                showToast("This shopping trip already updated the pantry")
                return
            }
        }
        guard let sessionID = ensureCurrentShoppingSession() else { return }
        track(.shoppingReconciliationStarted)
        continueTo(.shoppingReconciliation(sessionID))
    }

    /// Hides only the repeated pantry-update reminder. It does not create a
    /// shopping outcome, change pantry or product preferences, or remove the
    /// frozen trip from local history.
    @discardableResult
    func archivePantryUpdateReminder(sessionID: UUID) -> Bool {
        guard persistenceReady else {
            showToast(persistenceIssue ?? "SmartCart storage is unavailable")
            return false
        }
        guard let target = shoppingSession(id: sessionID),
              target.isGuideComplete,
              !target.isCommitted,
              let manifestID = target.manifestID,
              savedLists.contains(where: { $0.manifest.id == manifestID }) else {
            showToast("This completed shopping trip is not available in history")
            return false
        }

        let relatedIndices = shoppingSessions.indices.filter { index in
            let candidate = shoppingSessions[index]
            return candidate.isGuideComplete &&
                !candidate.isCommitted &&
                shoppingSessionsRepresentSameTrip(candidate, target)
        }
        guard !relatedIndices.isEmpty else { return false }
        if relatedIndices.allSatisfy({ shoppingSessions[$0].pantryUpdateReminderArchivedAt != nil }) {
            return true
        }

        var updatedSessions = shoppingSessions
        let archivedAt = Date.now
        for index in relatedIndices {
            updatedSessions[index].pantryUpdateReminderArchivedAt = archivedAt
        }

        do {
            try stateStore.save(stateSnapshot(shoppingSessions: updatedSessions))
            suppressPersistence = true
            shoppingSessions = updatedSessions
            suppressPersistence = false
            persistenceIssue = nil
            showToast("Pantry update reminder archived")
            return true
        } catch {
            persistenceIssue = error.localizedDescription
            showToast("Pantry update reminder could not be archived")
            return false
        }
    }

    /// Permanently discards an unfinished shopping trip and its generated
    /// manifest. Guide-complete and committed trips are history and must use
    /// the reminder archive or reconciliation paths instead.
    @discardableResult
    func discardPendingShoppingSession(_ sessionID: UUID) -> Bool {
        guard persistenceReady else {
            showToast(persistenceIssue ?? "SmartCart storage is unavailable")
            return false
        }
        guard let target = shoppingSession(id: sessionID),
              !target.isGuideComplete,
              !target.isCommitted else {
            showToast("Completed shopping trips stay in history")
            return false
        }

        let relatedSessions = shoppingSessions.filter {
            shoppingSessionsRepresentSameTrip($0, target)
        }
        guard relatedSessions.allSatisfy({ !$0.isGuideComplete && !$0.isCommitted }) else {
            showToast("Completed shopping trips stay in history")
            return false
        }
        let relatedSessionIDs = Set(relatedSessions.map(\.id))
        let relatedManifestIDs = Set(relatedSessions.compactMap(\.manifestID))
        let relatedLogicalTripIDs = Set(relatedSessions.compactMap(\.reconciliationIdentity))

        let originalSessions = shoppingSessions
        let originalLists = savedLists
        let originalActiveSessionID = activeShoppingSessionID
        let originalItems = shoppingItems
        let originalGuidedIndex = guidedIndex

        suppressPersistence = true
        shoppingSessions.removeAll { relatedSessionIDs.contains($0.id) }
        savedLists.removeAll { list in
            relatedManifestIDs.contains(list.manifest.id) ||
                list.manifest.logicalTripID.map(relatedLogicalTripIDs.contains) == true
        }
        if let activeShoppingSessionID, relatedSessionIDs.contains(activeShoppingSessionID) {
            self.activeShoppingSessionID = nil
            shoppingItems = []
            guidedIndex = 0
        }

        do {
            try stateStore.save(stateSnapshot())
            suppressPersistence = false
            persistenceIssue = nil
            showToast("Shopping trip deleted")
            return true
        } catch {
            shoppingSessions = originalSessions
            savedLists = originalLists
            activeShoppingSessionID = originalActiveSessionID
            shoppingItems = originalItems
            guidedIndex = originalGuidedIndex
            suppressPersistence = false
            persistenceIssue = error.localizedDescription
            showToast("Shopping trip could not be deleted")
            return false
        }
    }

    func commitShoppingReconciliation(
        sessionID: UUID,
        outcome: ShoppingTripOutcome,
        purchasedItemIDs: Set<UUID>,
        substitutions: [ShoppingSubstitutionFeedback]
    ) throws {
        guard persistenceReady else {
            throw ShoppingReconciliationError.persistenceUnavailable(
                persistenceIssue ?? "SmartCart storage is unavailable."
            )
        }
        guard let sessionIndex = shoppingSessions.firstIndex(where: { $0.id == sessionID }) else {
            throw ShoppingReconciliationError.sessionNotFound
        }
        if shoppingSessions[sessionIndex].isCommitted {
            return
        }

        let session = shoppingSessions[sessionIndex]
        if let committedDuplicate = shoppingSessions.first(where: {
            $0.id != session.id &&
                $0.reconciliation != nil &&
                shoppingSessionsRepresentSameTrip($0, session)
        }), let reconciliation = committedDuplicate.reconciliation {
            var deduplicatedSessions = shoppingSessions
            deduplicatedSessions[sessionIndex].logicalTripID =
                committedDuplicate.reconciliationIdentity ?? reconciliation.logicalTripID
            deduplicatedSessions[sessionIndex].tripID = deduplicatedSessions[sessionIndex].logicalTripID
            deduplicatedSessions[sessionIndex].reconciliation = remappedReconciliation(
                reconciliation,
                from: committedDuplicate,
                to: session
            )
            deduplicatedSessions[sessionIndex].reconciliationDraft = nil
            try stateStore.save(stateSnapshot(shoppingSessions: deduplicatedSessions))
            suppressPersistence = true
            shoppingSessions = deduplicatedSessions
            suppressPersistence = false
            persistenceIssue = nil
            showToast("This shopping trip already updated the pantry")
            return
        }
        let validItemIDs = Set(session.items.map(\.id))
        let confirmedPurchasedIDs: Set<UUID> = outcome == .didNotShop
            ? []
            : purchasedItemIDs.intersection(validItemIDs)
        let validSubstitutions = substitutions.filter {
            confirmedPurchasedIDs.contains($0.originalItemID)
        }
        if let unresolved = validSubstitutions.first(where: {
            guard let amount = $0.replacementAmount else { return true }
            return !amount.isFinite || amount <= 0
        }) {
            throw ShoppingReconciliationError.replacementQuantityConfirmationRequired(
                unresolved.originalItemID
            )
        }

        var updatedPantry = pantryInventory
        var updatedPreferences = preferredProductIDsByIngredient
        var touchedPantryIDs = Set<UUID>()
        var acquisitions: [PantryAcquisition] = []
        for item in session.items where confirmedPurchasedIDs.contains(item.id) {
            let substitution = validSubstitutions.first { $0.originalItemID == item.id }
            let pantryID = mergePurchasedItem(
                item,
                substitution: substitution,
                into: &updatedPantry
            )
            touchedPantryIDs.insert(pantryID)
            let sources = session.mealPrepSnapshot?.lines.first {
                $0.shoppingItemID == item.ingredient.id ||
                    $0.sources.first?.ingredient.id == item.ingredient.id
            }?.sources ?? []
            acquisitions.append(
                PantryAcquisition(
                    shoppingItemID: item.id,
                    pantryItemID: pantryID,
                    amount: substitution?.replacementAmount ?? Double(max(1, item.purchaseQuantity)),
                    sourceContributions: sources
                )
            )

            if let substitution,
               substitution.preferNextTime,
               let retailerProductID = substitution.replacementRetailerProductID,
               !retailerProductID.isEmpty {
                updatedPreferences[productPreferenceKey(
                    for: item.ingredient.name,
                    retailerID: item.product.retailerID
                )] = retailerProductID
            }
        }

        var updatedSessions = shoppingSessions
        let reconciliationTripID = session.reconciliationIdentity ?? session.id
        updatedSessions[sessionIndex].logicalTripID = reconciliationTripID
        updatedSessions[sessionIndex].tripID = reconciliationTripID
        updatedSessions[sessionIndex].reconciliation = ShoppingReconciliationRecord(
            outcome: outcome,
            purchasedItemIDs: confirmedPurchasedIDs,
            substitutions: validSubstitutions,
            pantryItemIDs: touchedPantryIDs,
            committedAt: .now,
            acquisitions: acquisitions,
            logicalTripID: reconciliationTripID
        )
        updatedSessions[sessionIndex].reconciliationDraft = nil

        // Persist the complete transaction before changing observable state.
        // A retry therefore cannot add the same purchase twice.
        try stateStore.save(
            stateSnapshot(
                pantryInventory: updatedPantry,
                preferredProductIDs: updatedPreferences,
                shoppingSessions: updatedSessions
            )
        )

        suppressPersistence = true
        pantryInventory = updatedPantry
        preferredProductIDsByIngredient = updatedPreferences
        shoppingSessions = updatedSessions
        suppressPersistence = false
        persistenceIssue = nil

        track(
            .shoppingOutcomeRecorded,
            properties: [
                "outcome": outcome.rawValue,
                "purchased": String(confirmedPurchasedIDs.count)
            ]
        )
        track(
            .pantryReconciliationCommitted,
            properties: ["items": String(touchedPantryIDs.count)]
        )
        if !validSubstitutions.isEmpty {
            track(
                .substitutionRecorded,
                properties: ["count": String(validSubstitutions.count)]
            )
        }
        showToast(outcome == .didNotShop ? "Pantry left unchanged" : "Pantry updated")
    }

    private func createOrReuseCurrentShoppingSession() throws -> UUID {
        guard persistenceReady else {
            throw ShoppingReconciliationError.persistenceUnavailable(
                persistenceIssue ?? "SmartCart storage is unavailable."
            )
        }
        guard !shoppingItems.isEmpty else { throw ShoppingReconciliationError.emptyShoppingList }

        let currentFingerprint = shoppingSessionFingerprint(
            scope: shoppingScope ?? .singleRecipe(activeRecipe.id),
            retailerID: selectedRetailer.rawValue,
            storeID: primaryStore.retailerStoreID,
            fulfillment: fulfillmentMode,
            plan: currentShoppingMealPrepSnapshot,
            items: shoppingItems
        )
        if let existing = shoppingSessions.first(where: {
            guard ($0.shoppingScope ?? .singleRecipe($0.recipeID)) == (shoppingScope ?? .singleRecipe(activeRecipe.id)),
                  $0.storeID == primaryStore.retailerStoreID,
                  $0.isReusable
            else { return false }
            if $0.stateFingerprint == currentFingerprint {
                return true
            }
            guard $0.shoppingScope?.kind != .mealPrepBeta else { return false }
            let existingFingerprint = shoppingSessionFingerprint(
                scope: $0.shoppingScope ?? .singleRecipe($0.recipeID),
                retailerID: $0.retailerID ?? $0.items.first?.product.retailerID ?? selectedRetailer.rawValue,
                storeID: $0.storeID,
                fulfillment: $0.fulfillmentMode ?? fulfillmentMode,
                plan: $0.mealPrepSnapshot,
                items: $0.items
            )
            return existingFingerprint == currentFingerprint
        }) {
            return existing.id
        }

        let logicalTripID = currentSavedManifest?.logicalTripID ?? UUID()
        let session = ShoppingSession(
            logicalTripID: logicalTripID,
            recipeID: currentShoppingScopeID,
            recipeTitle: currentShoppingTitle,
            manifestID: currentSavedManifest?.id,
            storeID: primaryStore.retailerStoreID,
            retailerID: selectedRetailer.rawValue,
            desiredServings: isMealPrepShopping ? nil : desiredServings,
            fulfillmentMode: fulfillmentMode,
            shoppingScope: shoppingScope ?? .singleRecipe(activeRecipe.id),
            mealPrepSnapshot: currentShoppingMealPrepSnapshot,
            items: shoppingItems,
            stateFingerprint: currentFingerprint
        )
        var updatedSessions = shoppingSessions
        updatedSessions.insert(session, at: 0)
        if suppressPersistence {
            shoppingSessions = updatedSessions
        } else {
            try stateStore.save(stateSnapshot(shoppingSessions: updatedSessions))
            suppressPersistence = true
            shoppingSessions = updatedSessions
            suppressPersistence = false
        }
        persistenceIssue = nil
        return session.id
    }

    private func remappedReconciliation(
        _ record: ShoppingReconciliationRecord,
        from source: ShoppingSession,
        to target: ShoppingSession
    ) -> ShoppingReconciliationRecord {
        var targetIDsBySemanticIdentity = Dictionary(
            grouping: target.items,
            by: shoppingItemSemanticIdentity
        ).mapValues { $0.map(\.id).sorted { $0.uuidString < $1.uuidString } }
        var itemIDMap: [UUID: UUID] = [:]

        for item in source.items.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let identity = shoppingItemSemanticIdentity(item)
            guard var candidates = targetIDsBySemanticIdentity[identity],
                  !candidates.isEmpty else { continue }
            itemIDMap[item.id] = candidates.removeFirst()
            targetIDsBySemanticIdentity[identity] = candidates
        }

        let purchasedItemIDs = Set(record.purchasedItemIDs.compactMap { itemIDMap[$0] })
        let substitutions = record.substitutions.compactMap { substitution -> ShoppingSubstitutionFeedback? in
            guard let targetID = itemIDMap[substitution.originalItemID] else { return nil }
            var remapped = substitution
            remapped.originalItemID = targetID
            return remapped
        }
        let acquisitions = record.acquisitions?.compactMap { acquisition -> PantryAcquisition? in
            guard let targetID = itemIDMap[acquisition.shoppingItemID] else { return nil }
            var remapped = acquisition
            remapped.shoppingItemID = targetID
            return remapped
        }

        return ShoppingReconciliationRecord(
            outcome: record.outcome,
            purchasedItemIDs: purchasedItemIDs,
            substitutions: substitutions,
            pantryItemIDs: record.pantryItemIDs,
            committedAt: record.committedAt,
            acquisitions: acquisitions,
            logicalTripID: target.reconciliationIdentity ?? source.reconciliationIdentity ?? record.logicalTripID
        )
    }

    private func mergePurchasedItem(
        _ item: ShoppingListItem,
        substitution: ShoppingSubstitutionFeedback?,
        into inventory: inout [PantryInventoryItem]
    ) -> UUID {
        let product = item.product
        let replacementName = substitution?.replacementName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = replacementName?.isEmpty == false
            ? replacementName!
            : (product.linkKind == .exactProduct ? product.name : item.ingredient.name)
        let brand = substitution?.replacementBrand ?? (product.linkKind == .exactProduct ? product.brand : "")
        let retailerProductID = substitution == nil
            ? (product.linkKind == .exactProduct ? product.retailerProductID : nil)
            : substitution?.replacementRetailerProductID
        let scopedRetailerProductID = retailerProductID.map {
            "\(product.retailerID):\($0)"
        }
        let gtin14 = normalizedGTIN14(
            substitution == nil ? product.gtin : substitution?.replacementGTIN14
        )
        let packageQuantity = substitution == nil
            ? (product.variableWeight ? nil : product.packageQuantity)
            : substitution?.packageQuantity
        let packageUnit = substitution == nil
            ? (product.variableWeight ? nil : product.packageUnit)
            : substitution?.packageUnit
        let hasUnknownPackageMass = packageQuantity == nil || packageUnit?.isEmpty != false
        let amount = max(
            0.01,
            substitution == nil
                ? Double(max(1, item.purchaseQuantity))
                : (substitution?.replacementAmount ?? 0)
        )

        let matchIndex = inventory.firstIndex { existing in
            if let gtin14 {
                let identities = Set((existing.barcodeGTINs ?? []) + [existing.gtin14].compactMap { $0 })
                if identities.contains(gtin14) {
                    return packagesAreCompatible(
                        existingSize: existing.packageSize,
                        existingUnit: existing.packageUnit,
                        incomingSize: packageQuantity,
                        incomingUnit: packageUnit
                    )
                }
            }
            if let scopedRetailerProductID {
                if existing.preferredRetailerProductID == scopedRetailerProductID {
                    return packagesAreCompatible(
                        existingSize: existing.packageSize,
                        existingUnit: existing.packageUnit,
                        incomingSize: packageQuantity,
                        incomingUnit: packageUnit
                    )
                }
                if product.retailerID == ShoppingRetailer.walmart.rawValue,
                   existing.preferredRetailerProductID == retailerProductID {
                    return packagesAreCompatible(
                        existingSize: existing.packageSize,
                        existingUnit: existing.packageUnit,
                        incomingSize: packageQuantity,
                        incomingUnit: packageUnit
                    )
                }
            }
            let existingBrand = preferenceKey(for: existing.brand)
            let incomingBrand = preferenceKey(for: brand)
            return !existingBrand.isEmpty
                && existingBrand == incomingBrand
                && preferenceKey(for: existing.name) == preferenceKey(for: name)
                && packagesAreCompatible(
                    existingSize: existing.packageSize,
                    existingUnit: existing.packageUnit,
                    incomingSize: packageQuantity,
                    incomingUnit: packageUnit
                )
        }

        if let matchIndex {
            inventory[matchIndex].addPackages(
                amount,
                packageSize: packageQuantity,
                packageUnit: packageUnit
            )
            inventory[matchIndex].updatedAt = .now
            inventory[matchIndex].preferredRetailerProductID =
                inventory[matchIndex].preferredRetailerProductID ?? scopedRetailerProductID
            inventory[matchIndex].packageSize = inventory[matchIndex].packageSize ?? packageQuantity
            inventory[matchIndex].packageUnit = inventory[matchIndex].packageUnit ?? packageUnit
            inventory[matchIndex].hasUnknownPackageMass =
                inventory[matchIndex].hasUnknownPackageMass == true || hasUnknownPackageMass
            if let gtin14 {
                inventory[matchIndex].gtin14 = inventory[matchIndex].gtin14 ?? gtin14
                var identities = inventory[matchIndex].barcodeGTINs ?? []
                if !identities.contains(gtin14) { identities.append(gtin14) }
                inventory[matchIndex].barcodeGTINs = identities.sorted()
            }
            return inventory[matchIndex].id
        }

        let pantryItem = PantryInventoryItem(
            name: name,
            brand: brand,
            quantity: amount,
            unit: "package",
            preferredRetailerProductID: scopedRetailerProductID,
            source: .recipe,
            packageCount: amount,
            packageSize: packageQuantity,
            packageUnit: packageUnit,
            requiresUserNaming: false,
            gtin14: gtin14,
            barcodeGTINs: gtin14.map { [$0] },
            hasUnknownPackageMass: hasUnknownPackageMass
        )
        inventory.insert(pantryItem, at: 0)
        return pantryItem.id
    }

    private func shoppingSessionFingerprint(
        scope: ShoppingScope,
        retailerID: String,
        storeID: String,
        fulfillment: FulfillmentMode,
        plan: MealPrepPlanSnapshot?,
        items: [ShoppingListItem]
    ) -> String {
        let itemState = items
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { item in
                [
                    item.id.uuidString,
                    item.requestedQuantity,
                    String(item.purchaseQuantity),
                    item.product.retailerID,
                    item.product.retailerProductID,
                    item.product.gtin ?? "",
                    item.product.packageQuantity.map { String($0.bitPattern) } ?? "",
                    item.product.packageUnit ?? ""
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
        let planState = plan.map { plan in
            let selections = plan.selections
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { "\($0.recipeSnapshot.id.uuidString)|\($0.id.uuidString)|\($0.targetServings)" }
                .joined(separator: "\n")
            let lines = plan.lines
                .sorted { $0.id < $1.id }
                .map { line in
                    let sources = line.sources.map(\.id).sorted().joined(separator: ",")
                    let pantry = line.pantryDeductions
                        .sorted { $0.pantryItemID.uuidString < $1.pantryItemID.uuidString }
                        .map { "\($0.pantryItemID.uuidString):\($0.quantity):\($0.unit)" }
                        .joined(separator: ",")
                    let pantryOverride = line.buyFullOverride == true ? "buy-full" : "use-pantry"
                    return "\(line.id)|\(line.quantityToBuy)|\(line.unit.symbol)|\(line.mergeReviewState.rawValue)|\(pantryOverride)|\(sources)|\(pantry)"
                }
                .joined(separator: "\n")
            return "\(selections)\n\(lines)"
        } ?? "single:\(desiredServings)"
        let canonical = "v4|\(scope.fingerprintInput)|\(retailerID)|\(storeID)|\(fulfillment.rawValue)\n\(planState)\n\(itemState)"

        // Swift's Hasher is intentionally randomized between launches. FNV-1a
        // keeps this local identity stable without introducing account data.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in canonical.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "v4:" + String(format: "%016llx", hash)
    }

    private func synchronizeCurrentShoppingSessionItems(sessionID: UUID) {
        let currentFingerprint = shoppingSessionFingerprint(
            scope: shoppingScope ?? .singleRecipe(activeRecipe.id),
            retailerID: selectedRetailer.rawValue,
            storeID: primaryStore.retailerStoreID,
            fulfillment: fulfillmentMode,
            plan: currentShoppingMealPrepSnapshot,
            items: shoppingItems
        )
        guard let index = shoppingSessions.firstIndex(where: {
            $0.id == sessionID && $0.isReusable
        }) else { return }
        shoppingSessions[index].items = shoppingItems
        shoppingSessions[index].stateFingerprint = currentFingerprint
        shoppingSessions[index].shoppingScope = shoppingScope ?? .singleRecipe(activeRecipe.id)
        shoppingSessions[index].mealPrepSnapshot = currentShoppingMealPrepSnapshot
    }

    private func completedUncommittedSessionMatchingCurrentTrip() -> ShoppingSession? {
        let manifestID = currentSavedManifest?.id
        let currentSignature = shoppingTripSemanticSignature(
            scope: shoppingScope ?? .singleRecipe(activeRecipe.id),
            retailerID: selectedRetailer.rawValue,
            storeID: primaryStore.retailerStoreID,
            fulfillment: fulfillmentMode,
            items: shoppingItems
        )
        return shoppingSessions.first { session in
            guard !session.isCommitted,
                  session.isGuideComplete,
                  manifestID == nil || session.manifestID == manifestID else { return false }
            return shoppingTripSemanticSignature(for: session) == currentSignature
        }
    }

    private func shoppingSessionsRepresentSameTrip(
        _ lhs: ShoppingSession,
        _ rhs: ShoppingSession
    ) -> Bool {
        if let leftTripID = lhs.logicalTripID,
           let rightTripID = rhs.logicalTripID {
            return leftTripID == rightTripID
        }

        // A nil manifest is compatible with one manifest-backed legacy alias,
        // but it must never bridge two distinct manifests. Resolve legacy
        // equivalence across the full collection so compatibility remains
        // transitive and a real repeat trip cannot be reconciled as an alias.
        let clusterIDs = legacyShoppingSessionClusterIDs()
        guard let leftClusterID = clusterIDs[lhs.id],
              let rightClusterID = clusterIDs[rhs.id] else { return false }
        return leftClusterID == rightClusterID
    }

    private func legacyShoppingSessionClusterIDs() -> [UUID: Int] {
        let orderedIndices = shoppingSessions.indices.sorted { lhs, rhs in
            if shoppingSessions[lhs].startedAt == shoppingSessions[rhs].startedAt {
                return shoppingSessions[lhs].id.uuidString < shoppingSessions[rhs].id.uuidString
            }
            return shoppingSessions[lhs].startedAt < shoppingSessions[rhs].startedAt
        }
        var clusters: [[Int]] = []

        for index in orderedIndices {
            let candidate = shoppingSessions[index]
            let matchingClusterIndex = clusters.indices.reversed().first { clusterIndex in
                guard let representativeIndex = clusters[clusterIndex].first,
                      shoppingTripSemanticSignature(for: shoppingSessions[representativeIndex]) ==
                        shoppingTripSemanticSignature(for: candidate) else { return false }

                let manifestIDs = Set(
                    clusters[clusterIndex].compactMap { shoppingSessions[$0].manifestID }
                )
                if let manifestID = candidate.manifestID,
                   !manifestIDs.isEmpty,
                   !manifestIDs.contains(manifestID) {
                    return false
                }

                let logicalTripIDs = Set(
                    clusters[clusterIndex].compactMap { shoppingSessions[$0].logicalTripID }
                )
                if let logicalTripID = candidate.logicalTripID,
                   !logicalTripIDs.isEmpty,
                   !logicalTripIDs.contains(logicalTripID) {
                    return false
                }

                let committedThrough = clusters[clusterIndex]
                    .compactMap { shoppingSessions[$0].reconciliation?.committedAt }
                    .max()
                guard let committedThrough else {
                    return true
                }
                return candidate.startedAt <= committedThrough
            }

            if let matchingClusterIndex {
                clusters[matchingClusterIndex].append(index)
            } else {
                clusters.append([index])
            }
        }

        var clusterIDs: [UUID: Int] = [:]
        for (clusterID, cluster) in clusters.enumerated() {
            for index in cluster {
                clusterIDs[shoppingSessions[index].id] = clusterID
            }
        }
        return clusterIDs
    }

    private func shoppingTripSemanticSignature(for session: ShoppingSession) -> String {
        shoppingTripSemanticSignature(
            scope: session.shoppingScope ?? .singleRecipe(session.recipeID),
            retailerID: session.retailerID ?? session.items.first?.product.retailerID ?? "",
            storeID: session.storeID,
            fulfillment: session.fulfillmentMode ?? .pickup,
            items: session.items
        )
    }

    private func shoppingTripSemanticSignature(
        scope: ShoppingScope,
        retailerID: String,
        storeID: String,
        fulfillment: FulfillmentMode,
        items: [ShoppingListItem]
    ) -> String {
        let itemState = items.map(shoppingItemSemanticIdentity)
        .sorted()
        .joined(separator: "\n")
        return "\(scope.fingerprintInput)|\(retailerID)|\(storeID)|\(fulfillment.rawValue)\n\(itemState)"
    }

    private func shoppingItemSemanticIdentity(_ item: ShoppingListItem) -> String {
        [
            preferenceKey(for: item.ingredient.name),
            preferenceKey(for: item.requestedQuantity),
            String(item.purchaseQuantity),
            preferenceKey(for: item.product.retailerID),
            preferenceKey(for: item.product.retailerProductID),
            item.product.exactURL.absoluteString.lowercased(),
            item.product.packageQuantity.map { String($0.bitPattern) } ?? "",
            preferenceKey(for: item.product.packageUnit ?? "")
        ].joined(separator: "|")
    }

    private func normalizedGTIN14(_ value: String?) -> String? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        guard (8...14).contains(digits.count) else { return nil }
        return String(repeating: "0", count: 14 - digits.count) + digits
    }

    private func packagesAreCompatible(
        existingSize: Double?,
        existingUnit: String?,
        incomingSize: Double?,
        incomingUnit: String?
    ) -> Bool {
        if existingSize == nil, incomingSize == nil,
           existingUnit == nil, incomingUnit == nil {
            return true
        }
        guard let existingSize,
              let incomingSize,
              let existingUnit,
              let incomingUnit,
              preferenceKey(for: existingUnit) == preferenceKey(for: incomingUnit)
        else { return false }
        return abs(existingSize - incomingSize) < 0.001
    }

    private func nextWaitingRetailerItem(after index: Int) -> Int? {
        let later = shoppingItems.indices.first {
            $0 > index && shoppingItems[$0].status == .waiting
        }
        return later ?? shoppingItems.indices.first {
            shoppingItems[$0].status == .waiting
        }
    }

    func linkDeliveryPartner(_ partner: DeliveryPartner) {
        preferredDeliveryPartnerName = partner.name
        if featureFlags.advancedToolsEnabled {
            fulfillmentMode = .delivery
        }
        showToast("\(partner.name) saved as a preferred provider")
    }

    func store(for id: UUID) -> RetailerStore {
        stores.first(where: { $0.id == id }) ?? stores[0]
    }

    func productURL(for item: ShoppingListItem) -> URL {
        item.product.exactURL
    }

    func productHandoffLabel(for item: ShoppingListItem) -> String {
        item.product.isExactProductLink
            ? "Open exact product"
            : "Search at \(retailerConfiguration.displayName)"
    }

    func retailerURL() -> URL {
        retailerConfiguration.homeURL
    }

    func prepareInstacartHandoff() async -> InstacartHandoffResponse? {
        guard activeCommerceCapabilities.preparesShoppingList else {
            showToast("This shopping route cannot transfer a prepared list")
            return nil
        }
        guard commerceBlockingIssues.isEmpty else {
            showToast(commerceBlockingIssues.first ?? "Review the shopping list before continuing")
            return nil
        }

        isPreparingCommerceHandoff = true
        defer { isPreparingCommerceHandoff = false }
        let stages = [
            "Preparing your shoppable list…",
            "Converting quantities…",
            "Applying preferences…",
            "Creating secure Instacart handoff…"
        ]
        for stage in stages {
            commerceHandoffStage = stage
            try? await Task.sleep(for: .milliseconds(320))
        }

        do {
            let handoff = try await instacartHandoffService.createHandoff(
                draft: instacartManifestDraft,
                postalCode: zipCode.filter(\.isNumber),
                preferredRetailer: instacartRetailerPreference,
                fulfillment: commerceFulfillmentPreference
            )
            lastInstacartHandoff = handoff
            commerceHandoffStage = "Instacart handoff ready"
            track(.retailerLinkOpened, properties: [
                "retailer": "instacart",
                "mode": "manifest_transfer"
            ])
            return handoff
        } catch {
            commerceHandoffStage = "Handoff needs attention"
            showToast(error.localizedDescription)
            return nil
        }
    }

    func recordHandoffFeedback(_ feedback: CommerceHandoffFeedback) {
        latestHandoffFeedback = feedback
        track(.handoffFeedbackRecorded, properties: ["result": feedback.rawValue])
        showToast("Shopping feedback saved")
    }

    func prepareRetailerHandoff() async -> RetailerHandoff? {
        persistCurrentManifest(progress: .inProgress)
        guard let manifest = currentSavedManifest else { return nil }
        do {
            let handoff = try await retailerEngine.createHandoff(
                for: selectedRetailer,
                manifest: manifest
            )
            track(.retailerLinkOpened, properties: ["retailer": handoff.retailerID, "mode": handoff.mode.rawValue])
            return handoff
        } catch {
            showToast(error.localizedDescription)
            return nil
        }
    }

    func completeRetailerHandoff() {
        persistCurrentManifest(progress: .completed)
    }

    func resetFlow() {
        homePath = []
        selectedTab = .home
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    func persistNow() {
        persistState()
    }

    func setInternalTesterModeEnabled(_ enabled: Bool) {
        featureFlags.internalTesterModeEnabled = enabled
    }

    func setLocalAnalyticsEnabled(_ enabled: Bool) {
        featureFlags.localAnalyticsEnabled = enabled
    }

    func clearLocalAnalytics() {
        analyticsEvents = []
        showToast("On-device tester events cleared")
    }

    func markIngredientsCorrected(count: Int = 1) {
        track(.ingredientsCorrected, properties: ["count": String(max(1, count))])
    }

    func addPantryItem(upc: String) {
        let normalizedUPC = upc.filter(\.isNumber)
        guard !normalizedUPC.isEmpty else {
            showToast("Enter a valid UPC")
            return
        }
        let normalizedBarcode: NormalizedBarcode?
        if case .success(let normalized) = BarcodeNormalizer.normalize(normalizedUPC) {
            normalizedBarcode = normalized
        } else {
            normalizedBarcode = nil
        }
        let record = OfflineBarcodeCatalog.lookup(upc: normalizedUPC)
        var updatedInventory = pantryInventory
        if let index = updatedInventory.firstIndex(where: { item in
            if let normalizedBarcode {
                return item.matches(barcode: normalizedBarcode)
            }
            return item.upc == normalizedUPC
        }) {
            updatedInventory[index].addPackages(1)
            updatedInventory[index].updatedAt = .now
            if let normalizedBarcode {
                updatedInventory[index].register(
                    barcode: normalizedBarcode,
                    rawValue: upc,
                    symbology: nil
                )
            }
        } else {
            updatedInventory.insert(
                PantryInventoryItem(
                    upc: normalizedUPC,
                    name: record?.name ?? "Unknown Product",
                    brand: record?.brand ?? "",
                    preferredRetailerProductID: record?.retailerProductID,
                    source: .barcode,
                    requiresUserNaming: record == nil,
                    rawBarcode: upc,
                    gtin14: normalizedBarcode?.canonicalGTIN14
                ),
                at: 0
            )
        }
        guard commitPantryInventoryChange(updatedInventory) else {
            showToast("Pantry change could not be saved")
            return
        }
        track(.barcodeScanned, properties: ["matched": record == nil ? "false" : "true"])
        track(.pantryItemAdded, properties: ["source": PantryItemSource.barcode.rawValue])
        showToast(record == nil ? "UPC saved for later matching" : "\(record!.name) added to pantry")
    }

    func addPantryItem(
        submission: PantryBarcodeSubmission,
        duplicateAction: BarcodeDuplicateResolutionAction = .increment
    ) {
        var updatedInventory = pantryInventory
        if let index = updatedInventory.firstIndex(where: { $0.matches(barcode: submission.barcode) }) {
            switch duplicateAction {
            case .increment:
                updatedInventory[index].addPackages(1)
                updatedInventory[index].updatedAt = .now
                updatedInventory[index].register(
                    barcode: submission.barcode,
                    rawValue: submission.scan.rawBarcode,
                    symbology: submission.scan.rawSymbology
                )
            case .replace:
                let existingQuantity = updatedInventory[index].packageCount
                let knownBarcodes = updatedInventory[index].barcodeGTINs ?? []
                updatedInventory[index] = pantryItem(from: submission, quantity: existingQuantity)
                updatedInventory[index].barcodeGTINs = Array(
                    Set(knownBarcodes + [submission.barcode.canonicalGTIN14])
                ).sorted()
            case .cancel:
                return
            }
        } else {
            updatedInventory.insert(pantryItem(from: submission), at: 0)
        }
        guard commitPantryInventoryChange(updatedInventory) else {
            showToast("Pantry change could not be saved")
            return
        }
        track(.barcodeScanned, properties: ["matched": submission.requiresUserNaming ? "false" : "true"])
        track(.pantryItemAdded, properties: ["source": PantryItemSource.barcode.rawValue])
        showToast(submission.requiresUserNaming ? "Barcode saved — product name required" : "\(submission.name) added to pantry")
    }

    private func pantryItem(from submission: PantryBarcodeSubmission, quantity: Double = 1) -> PantryInventoryItem {
        PantryInventoryItem(
            upc: submission.barcode.digits,
            name: submission.name,
            brand: submission.brand,
            quantity: quantity,
            preferredRetailerProductID: submission.externalProductID,
            source: .barcode,
            requiresUserNaming: submission.requiresUserNaming,
            rawBarcode: submission.scan.rawBarcode,
            barcodeSymbology: submission.scan.rawSymbology,
            gtin14: submission.barcode.canonicalGTIN14
        )
    }

    func addManualPantryItem(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updatedInventory = pantryInventory
        updatedInventory.insert(PantryInventoryItem(name: trimmed, source: .manual), at: 0)
        guard commitPantryInventoryChange(updatedInventory) else {
            showToast("Pantry change could not be saved")
            return
        }
        track(.pantryItemAdded, properties: ["source": PantryItemSource.manual.rawValue])
    }

    func updatePantryItem(_ item: PantryInventoryItem) {
        var updatedInventory = pantryInventory
        guard let index = updatedInventory.firstIndex(where: { $0.id == item.id }) else { return }
        updatedInventory[index] = item
        updatedInventory[index].updatedAt = .now
        if !commitPantryInventoryChange(updatedInventory) {
            showToast("Pantry change could not be saved")
        }
    }

    func removePantryItems(at offsets: IndexSet) {
        var updatedInventory = pantryInventory
        updatedInventory.remove(atOffsets: offsets)
        if !commitPantryInventoryChange(updatedInventory) {
            showToast("Pantry change could not be saved")
        }
    }

    /// Existing pantry items whose names match a partial query, prefix
    /// matches first. Drives autocomplete while naming a scanned item.
    func pantryNameSuggestions(for query: String, limit: Int = 3) -> [PantryInventoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        let matches = pantryInventory.filter { item in
            let name = item.name.lowercased()
            return name != trimmed && name.contains(trimmed)
        }
        let ranked = matches.sorted { first, second in
            let firstPrefix = first.name.lowercased().hasPrefix(trimmed)
            let secondPrefix = second.name.lowercased().hasPrefix(trimmed)
            if firstPrefix != secondPrefix { return firstPrefix }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
        return Array(ranked.prefix(limit))
    }

    /// Case-insensitive exact-name match against saved pantry stock.
    func pantryItem(named name: String) -> PantryInventoryItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return pantryInventory.first {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// Finds stock already associated with a normalized barcode, regardless of
    /// whether the scanner or user uses a different display name this time.
    func pantryItem(matching barcode: NormalizedBarcode) -> PantryInventoryItem? {
        pantryInventory.first { $0.matches(barcode: barcode) }
    }

    func pantryMergeTarget(
        named name: String,
        submission: PantryBarcodeSubmission?
    ) -> PantryInventoryItem? {
        if let submission, let barcodeMatch = pantryItem(matching: submission.barcode) {
            return barcodeMatch
        }
        return pantryItem(named: name)
    }

    /// Adds scanned or manual stock: merges into an existing item when the
    /// name already exists, otherwise creates a new pantry item.
    func addPantryStock(name: String, amount: Double, submission: PantryBarcodeSubmission? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, amount > 0 else { return }

        var updatedInventory = pantryInventory
        let successMessage: String
        if let existing = pantryMergeTarget(named: trimmed, submission: submission),
           let index = updatedInventory.firstIndex(where: { $0.id == existing.id }) {
            updatedInventory[index].addPackages(amount)
            updatedInventory[index].updatedAt = .now
            if let submission {
                updatedInventory[index].register(
                    barcode: submission.barcode,
                    rawValue: submission.scan.rawBarcode,
                    symbology: submission.scan.rawSymbology
                )
                if updatedInventory[index].requiresUserNaming == true {
                    updatedInventory[index].name = trimmed
                    updatedInventory[index].requiresUserNaming = false
                }
            }
            successMessage = "Added \(amount.formatted()) to \(updatedInventory[index].name)"
        } else {
            updatedInventory.insert(
                PantryInventoryItem(
                    upc: submission?.barcode.digits,
                    name: trimmed,
                    brand: submission?.brand ?? "",
                    quantity: amount,
                    preferredRetailerProductID: submission?.externalProductID,
                    source: submission == nil ? .manual : .barcode,
                    requiresUserNaming: false,
                    rawBarcode: submission?.scan.rawBarcode,
                    barcodeSymbology: submission?.scan.rawSymbology,
                    gtin14: submission?.barcode.canonicalGTIN14
                ),
                at: 0
            )
            successMessage = "\(trimmed) added to pantry"
        }

        guard commitPantryInventoryChange(updatedInventory) else {
            showToast("Pantry change could not be saved")
            return
        }
        showToast(successMessage)

        if submission != nil {
            track(.barcodeScanned, properties: ["matched": "named"])
        }
        track(.pantryItemAdded, properties: [
            "source": (submission == nil ? PantryItemSource.manual : PantryItemSource.barcode).rawValue
        ])
    }

    func track(_ name: AnalyticsEventName, properties: [String: String] = [:]) {
        guard featureFlags.localAnalyticsEnabled else { return }
        let safeProperties = properties.filter { key, _ in
            !["recipe_text", "url", "upc", "address", "email"].contains(key.lowercased())
        }
        analyticsEvents.append(AnalyticsEvent(name: name, properties: safeProperties))
        if analyticsEvents.count > 500 {
            analyticsEvents.removeFirst(analyticsEvents.count - 500)
        }
    }

    private var currentSavedManifest: ShoppingManifest? {
        if let sessionID = activeShoppingSessionID,
           let session = shoppingSession(id: sessionID) {
            if let manifestID = session.manifestID,
               let exact = savedLists.first(where: { $0.manifest.id == manifestID })?.manifest {
                return exact
            }
            if let logicalTripID = session.reconciliationIdentity,
               let exact = savedLists.first(where: {
                   $0.manifest.logicalTripID == logicalTripID
               })?.manifest {
                return exact
            }
        }
        return savedLists.first {
            ($0.manifest.shoppingScope ?? .singleRecipe($0.manifest.recipeID)) == (shoppingScope ?? .singleRecipe(activeRecipe.id)) &&
            $0.manifest.retailerID == selectedRetailer.rawValue &&
            $0.manifest.storeID == primaryStore.retailerStoreID &&
            $0.manifest.handoffProgress != .completed
        }?.manifest
    }

    private func persistCurrentManifest(
        progress: ManifestHandoffProgress,
        logicalTripID requestedLogicalTripID: UUID? = nil,
        forceNewTrip: Bool = false
    ) {
        let activeSession = activeShoppingSessionID.flatMap(shoppingSession(id:))
        let existingIndex: Int? = forceNewTrip ? nil : {
            if let manifestID = activeSession?.manifestID,
               let index = savedLists.firstIndex(where: { $0.manifest.id == manifestID }) {
                return index
            }
            let logicalTripID = requestedLogicalTripID ?? activeSession?.reconciliationIdentity
            if let logicalTripID,
               let index = savedLists.firstIndex(where: {
                   $0.manifest.logicalTripID == logicalTripID
               }) {
                return index
            }
            return savedLists.firstIndex {
                ($0.manifest.shoppingScope ?? .singleRecipe($0.manifest.recipeID)) == (shoppingScope ?? .singleRecipe(activeRecipe.id)) &&
                $0.manifest.retailerID == selectedRetailer.rawValue &&
                $0.manifest.storeID == primaryStore.retailerStoreID &&
                $0.manifest.handoffProgress != .completed
            }
        }()
        let existing = existingIndex.map { savedLists[$0].manifest }
        let logicalTripID = requestedLogicalTripID ??
            activeSession?.reconciliationIdentity ??
            existing?.logicalTripID ??
            existing?.id ??
            UUID()
        let manifest = ShoppingManifest(
            id: existing?.id ?? UUID(),
            logicalTripID: logicalTripID,
            recipeID: currentShoppingScopeID,
            recipeTitle: currentShoppingTitle,
            retailerID: primaryStore.retailerID,
            storeID: primaryStore.retailerStoreID,
            storeName: primaryStore.name,
            desiredServings: isMealPrepShopping ? 0 : desiredServings,
            fulfillmentMode: fulfillmentMode,
            items: shoppingItems.map {
                ManifestLineItem(
                    id: $0.id,
                    ingredientID: $0.ingredient.id,
                    ingredientName: $0.ingredient.name,
                    requestedQuantity: $0.requestedQuantity,
                    requestedAmount: $0.requestedAmount,
                    purchaseQuantity: $0.purchaseQuantity,
                    product: $0.product,
                    status: $0.status,
                    sourceContributions: currentMealPrepSources(for: $0.ingredient.id)
                )
            },
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now,
            handoffProgress: progress,
            shoppingScope: shoppingScope ?? .singleRecipe(activeRecipe.id),
            mealPrepSnapshot: currentShoppingMealPrepSnapshot
        )

        if let existingIndex {
            savedLists.remove(at: existingIndex)
        }
        savedLists.insert(SavedShoppingList(manifest: manifest), at: 0)
    }

    private func buildShoppingItems(reusing reusableItems: [ShoppingListItem]) async -> [ShoppingListItem] {
        let mealPrepShopping = isMealPrepShopping
        let multiplier = mealPrepShopping ? 1 : Double(desiredServings) / Double(max(1, activeRecipe.servings))
        let method: FulfillmentMethod = fulfillmentMode == .pickup ? .pickup : .delivery
        let store = primaryStore
        let retailer = selectedRetailer
        let matchingPreferences = preferences
        let productPreferences = preferredProductIDsByIngredient
        let ingredients = ingredientsToBuy
        var reusableByIngredientID: [UUID: ShoppingListItem] = [:]
        for item in reusableItems where item.status == .waiting {
            reusableByIngredientID[item.ingredient.id] = reusableByIngredientID[item.ingredient.id] ?? item
        }
        var results: [ShoppingListItem] = []

        for ingredient in ingredients {
            let requestedQuantity = mealPrepShopping
                ? ingredient.quantity
                : PantryMatchingService.quantityToBuy(
                    for: ingredient,
                    requiredQuantity: ingredient.quantity * multiplier
                )
            let contextFingerprint = matchingContextFingerprint(
                for: ingredient,
                retailerID: retailer.rawValue,
                store: store,
                fulfillmentMethod: method,
                preferences: matchingPreferences
            )
            let inputFingerprint = matchingInputFingerprint(
                contextFingerprint: contextFingerprint,
                requestedQuantity: requestedQuantity,
                pantryDecision: ingredient.pantryDecision,
                pantryState: ingredient.pantryState
            )
            if var reused = reusableByIngredientID[ingredient.id],
               reused.matchingContextFingerprint == contextFingerprint {
                reused.ingredient = ingredient
                reused.requestedQuantity = Ingredient.quantityText(
                    requestedQuantity,
                    unit: ingredient.unit
                )
                reused.requestedAmount = requestedQuantity
                reused.purchaseQuantity = PackageMath.packageCount(
                    product: reused.product,
                    requestedQuantity: requestedQuantity,
                    requestedUnit: ingredient.unit
                )
                reused.storeID = store.id
                reused.matchingContextFingerprint = contextFingerprint
                reused.matchingInputFingerprint = inputFingerprint
                results.append(reused)
                continue
            }
            let request = RetailerProductSearchRequest(
                ingredient: ingredient,
                retailerID: retailer.rawValue,
                requestedQuantity: requestedQuantity,
                requestedUnit: ingredient.unit,
                storeID: store.retailerStoreID,
                fulfillmentMethod: method
            )
            var ranked = await retailerEngine.rankedProducts(
                for: request,
                preferences: matchingPreferences
            )
            let retailerPreferenceKey = productPreferenceKey(
                for: ingredient.name,
                retailerID: retailer.rawValue
            )
            let legacyWalmartPreference = retailer == .walmart
                ? productPreferences[preferenceKey(for: ingredient.name)]
                : nil
            if let preferredID = productPreferences[retailerPreferenceKey] ?? legacyWalmartPreference,
               let preferredIndex = ranked.firstIndex(where: { $0.product.retailerProductID == preferredID }) {
                let preferred = ranked.remove(at: preferredIndex)
                ranked.insert(preferred, at: 0)
            }
            guard let selected = ranked.first else { continue }

            results.append(
                ShoppingListItem(
                    id: ingredient.id,
                    ingredient: ingredient,
                    requestedQuantity: Ingredient.quantityText(
                        requestedQuantity,
                        unit: ingredient.unit
                    ),
                    requestedAmount: requestedQuantity,
                    purchaseQuantity: PackageMath.packageCount(
                        product: selected.product,
                        requestedQuantity: requestedQuantity,
                        requestedUnit: ingredient.unit
                    ),
                    product: selected.product,
                    alternatives: Array(ranked.dropFirst().map(\.product)),
                    storeID: store.id,
                    matchScore: selected.score,
                    selectionReasons: selected.reasons,
                    matchingContextFingerprint: contextFingerprint,
                    matchingInputFingerprint: inputFingerprint
                )
            )
        }
        return results
    }

    private func ensureMatchingFingerprints(at index: Int) {
        guard shoppingItems.indices.contains(index) else { return }
        guard shoppingItems[index].matchingContextFingerprint == nil ||
                shoppingItems[index].matchingInputFingerprint == nil else { return }
        let requestedQuantity = requestedQuantityForShoppingItem(shoppingItems[index])
        let method: FulfillmentMethod = fulfillmentMode == .pickup ? .pickup : .delivery
        let context = shoppingItems[index].matchingContextFingerprint ?? matchingContextFingerprint(
                for: shoppingItems[index].ingredient,
                retailerID: selectedRetailer.rawValue,
                store: primaryStore,
                fulfillmentMethod: method,
                preferences: preferences
            )
        shoppingItems[index].matchingContextFingerprint = context
        shoppingItems[index].matchingInputFingerprint = matchingInputFingerprint(
            contextFingerprint: context,
            requestedQuantity: requestedQuantity,
            pantryDecision: shoppingItems[index].ingredient.pantryDecision,
            pantryState: shoppingItems[index].ingredient.pantryState
        )
    }

    private func matchingContextFingerprint(
        for ingredient: Ingredient,
        retailerID: String,
        store: RetailerStore,
        fulfillmentMethod: FulfillmentMethod,
        preferences: ShoppingPreferences
    ) -> String {
        stableMatchingFingerprint(
            version: "matching-context-v1",
            fields: [
                ingredient.id.uuidString.lowercased(),
                ingredient.name,
                ingredient.unit,
                ingredient.preparation,
                ingredient.includeInList ? "included" : "excluded",
                ingredient.category.rawValue,
                ingredient.brandNote ?? "",
                ingredient.preferenceNote,
                retailerID,
                store.id.uuidString.lowercased(),
                store.retailerStoreID,
                fulfillmentMethod.rawValue,
                preferences.organicPolicy.rawValue,
                preferences.budgetPriority.rawValue,
                preferences.dietaryRestrictions.map(\.rawValue).sorted().joined(separator: "\u{1f}"),
                preferences.storeBrandPreference.rawValue,
                preferences.preferredBrands.map { $0.lowercased() }.sorted().joined(separator: "\u{1f}")
            ]
        )
    }

    private func matchingInputFingerprint(
        contextFingerprint: String,
        requestedQuantity: Double,
        pantryDecision: PantryDecision?,
        pantryState: PantryState
    ) -> String {
        let quantityBits = requestedQuantity == 0 ? "0" : String(requestedQuantity.bitPattern)
        return stableMatchingFingerprint(
            version: "matching-input-v1",
            fields: [
                contextFingerprint,
                quantityBits,
                pantryDecision?.rawValue ?? "unreviewed",
                pantryState.rawValue
            ]
        )
    }

    private func stableMatchingFingerprint(version: String, fields: [String]) -> String {
        // Length-prefix every field so arbitrary ingredient text cannot create
        // delimiter collisions. FNV-1a is deterministic across launches,
        // unlike Swift's intentionally randomized Hasher.
        let canonical = ([version] + fields).map { value in
            "\(value.utf8.count):\(value)"
        }.joined()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in canonical.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return version + ":" + String(format: "%016llx", hash)
    }

    private func currentMealPrepSources(for ingredientID: UUID) -> [CombinedIngredientSource] {
        currentShoppingMealPrepSnapshot?.lines.first {
            $0.shoppingItemID == ingredientID ||
                $0.sources.first?.ingredient.id == ingredientID
        }?.sources ?? []
    }

    private static func makeShoppingItems(
        recipe: Recipe,
        desiredServings: Int,
        store: RetailerStore,
        fulfillmentMode: FulfillmentMode,
        preferences: ShoppingPreferences
    ) -> [ShoppingListItem] {
        let multiplier = Double(desiredServings) / Double(max(1, recipe.servings))
        let eligible = recipe.ingredients.filter {
            $0.includeInList &&
            $0.pantryState != .haveEnough &&
            $0.pantryState != .exclude
        }

        return eligible.compactMap { ingredient in
            let requestedQuantity = ingredient.quantity * multiplier
            let request = RetailerProductSearchRequest(
                ingredient: ingredient,
                requestedQuantity: requestedQuantity,
                requestedUnit: ingredient.unit,
                storeID: store.retailerStoreID,
                fulfillmentMethod: fulfillmentMode == .pickup ? .pickup : .delivery
            )
            var ranked = RetailerProductMatcher.rank(
                DemoWalmartCatalogService.seededProducts(
                    for: ingredient,
                    storeID: store.retailerStoreID
                ),
                for: request,
                preferences: preferences
            )
            if ranked.isEmpty {
                ranked = RetailerProductMatcher.rank(
                    [
                        DemoWalmartCatalogService.searchFallback(
                            for: ingredient,
                            storeID: store.retailerStoreID,
                            preferences: preferences
                        )
                    ],
                    for: request,
                    preferences: preferences
                )
            }
            guard let selected = ranked.first else { return nil }

            return ShoppingListItem(
                id: ingredient.id,
                ingredient: ingredient,
                requestedQuantity: Ingredient.quantityText(
                    requestedQuantity,
                    unit: ingredient.unit
                ),
                requestedAmount: requestedQuantity,
                purchaseQuantity: PackageMath.packageCount(
                    product: selected.product,
                    requestedQuantity: requestedQuantity,
                    requestedUnit: ingredient.unit
                ),
                product: selected.product,
                alternatives: Array(ranked.dropFirst().map(\.product)),
                storeID: store.id,
                matchScore: selected.score,
                selectionReasons: selected.reasons
            )
        }
    }

    private func persistState() {
        guard persistenceReady, !suppressPersistence else { return }
        do {
            try stateStore.save(stateSnapshot())
            persistenceIssue = nil
        } catch {
            persistenceIssue = error.localizedDescription
        }
    }

    private func persistLibraryMutation(
        recipes updatedRecipes: [Recipe],
        savedRecipeIDs updatedSavedRecipeIDs: Set<UUID>,
        rollbackRecipes: [Recipe],
        rollbackSavedRecipeIDs: Set<UUID>
    ) -> Bool {
        guard persistenceReady else { return false }

        suppressPersistence = true
        recipes = updatedRecipes
        savedRecipeIDs = updatedSavedRecipeIDs
        suppressPersistence = false

        do {
            try stateStore.save(stateSnapshot())
            persistenceIssue = nil
            return true
        } catch {
            suppressPersistence = true
            recipes = rollbackRecipes
            savedRecipeIDs = rollbackSavedRecipeIDs
            suppressPersistence = false
            persistenceIssue = error.localizedDescription
            return false
        }
    }

    private func stateSnapshot(
        pantryInventory pantryOverride: [PantryInventoryItem]? = nil,
        preferredProductIDs preferenceOverride: [String: String]? = nil,
        shoppingSessions sessionOverride: [ShoppingSession]? = nil
    ) -> SmartCartPersistedState {
        SmartCartPersistedState(
            recipes: recipes,
            activeRecipe: activeRecipe,
            desiredServings: desiredServings,
            preferences: preferences,
            featureFlags: featureFlags,
            storeStrategy: storeStrategy,
            fulfillmentMode: fulfillmentMode,
            selectedStoreIDs: selectedStoreIDs,
            zipCode: zipCode,
            pickupDay: pickupDay,
            pickupTime: pickupTime,
            shoppingItems: shoppingItems,
            guidedIndex: guidedIndex,
            savedLists: savedLists,
            preferredDeliveryPartnerName: preferredDeliveryPartnerName,
            pantryInventory: pantryOverride ?? pantryInventory,
            preferredProductIDsByIngredient: preferenceOverride ?? preferredProductIDsByIngredient,
            analyticsEvents: analyticsEvents,
            walmartWishlistReference: walmartWishlistReference,
            shoppingSessions: sessionOverride ?? shoppingSessions,
            activeShoppingSessionID: activeShoppingSessionID,
            shoppingScope: shoppingScope,
            mealPrepDraft: mealPrepDraft,
            mealPrepPlan: mealPrepPlan,
            savedRecipeIDs: savedRecipeIDs
        )
    }

    private func preferenceKey(for ingredientName: String) -> String {
        ingredientName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func productPreferenceKey(for ingredientName: String, retailerID: String) -> String {
        "\(retailerID):\(preferenceKey(for: ingredientName))"
    }
}

enum ShoppingReconciliationError: LocalizedError, Equatable {
    case sessionNotFound
    case emptyShoppingList
    case persistenceUnavailable(String)
    case replacementQuantityConfirmationRequired(UUID)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            "That shopping trip is no longer available. Return to the current Shopping Trip or start a new one."
        case .emptyShoppingList:
            "There are no shopping items to reconcile."
        case .persistenceUnavailable(let message):
            "SmartCart cannot safely update the pantry: \(message)"
        case .replacementQuantityConfirmationRequired:
            "Confirm how many replacement packages you bought before updating the pantry."
        }
    }
}

enum RecipeParser {
    struct SanitizedIngredientCandidate: Equatable {
        let ingredientText: String
        let originalText: String
        let removedSuffix: String?
        let requiresReview: Bool
        let reviewReasons: [String]
    }

    #if DEBUG
    struct ContextualShadowReport: Equatable {
        let source: ContextualIngredientFilter.DocumentSource
        let records: [ContextualIngredientFilter.LineRecord]
        let authoritativeAcceptedLineIDs: [String]
        let contextualResult: ContextualIngredientFilter.FilterResult
        let divergence: ContextualIngredientFilter.DivergenceReport
    }
    #endif

    static func parse(
        title: String,
        text: String,
        source: RecipeSource = .text,
        sourceDetail: String = "Pasted into SmartCart",
        sourceLines: [OCRSourceLine] = []
    ) -> Recipe {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var sectionName: String?
        var isInsideIngredientSection = false
        var ingredients: [Ingredient] = []
        var remainingSourceLines = sourceLines
        #if DEBUG
        var authoritativeAcceptedLineOrdinals: [Int] = []
        #endif
        for (lineOrdinal, line) in lines.prefix(120).enumerated() {
            if isInstructionHeading(line) { break }
            if isIngredientHeading(line) {
                isInsideIngredientSection = true
                sectionName = nil
                continue
            }
            if isSectionHeading(line) {
                sectionName = line.trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
                isInsideIngredientSection = true
                continue
            }

            let candidate = sanitizedIngredientCandidate(from: line)
            let ingredientLine = candidate.ingredientText
            guard !ingredientLine.isEmpty else { continue }

            let exactSourceIndex = remainingSourceLines.firstIndex(where: {
                normalizedSourceText($0.text) == normalizedSourceText(line)
            })
            let sourceIndex = exactSourceIndex
                ?? bestSourceLineIndex(matching: line, in: remainingSourceLines)
            let hasStructuredIngredientContext = source == .link || source == .pinterest
            let hasOCRIngredientEvidence = sourceIndex != nil
            let contextAllowsQuantitylessLine = isInsideIngredientSection
                || hasStructuredIngredientContext
                || hasOCRIngredientEvidence

            if isLikelyInstruction(ingredientLine) {
                if !ingredients.isEmpty { break }
                continue
            }
            guard isLikelyIngredient(
                ingredientLine,
                contextAllowsQuantitylessLine: contextAllowsQuantitylessLine
            ),
                  ingredients.count < 60
            else { continue }
            var ingredient = parseIngredient(ingredientLine, source: source)
            if let sourceIndex {
                let sourceLine = remainingSourceLines.remove(at: sourceIndex)
                apply(sourceLine: sourceLine, to: &ingredient, source: source)
            }
            apply(candidate: candidate, to: &ingredient)
            ingredient.sectionName = sectionName
            ingredients.append(ingredient)
            #if DEBUG
            authoritativeAcceptedLineOrdinals.append(lineOrdinal)
            #endif
        }

        #if DEBUG
        _ = contextualShadowReport(
            text: text,
            source: source,
            sourceDetail: sourceDetail,
            sourceLines: sourceLines,
            authoritativeAcceptedLineOrdinals: authoritativeAcceptedLineOrdinals
        )
        #endif

        return Recipe(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? inferredTitle(from: lines) : title,
            source: source,
            sourceDetail: sourceDetail,
            heroSymbol: heroSymbol(for: title + " " + text),
            servings: inferredServings(from: text),
            prepMinutes: 15,
            cookMinutes: inferredCookTime(from: text),
            ingredients: ingredients
        )
    }

    #if DEBUG
    /// Builds lossless source-line evidence for development comparison only.
    /// The returned contextual result never feeds the shipping parser output.
    static func contextualShadowReport(
        text: String,
        source: RecipeSource = .text,
        sourceDetail: String = "Pasted into SmartCart",
        sourceLines: [OCRSourceLine] = [],
        authoritativeAcceptedLineOrdinals: [Int]
    ) -> ContextualShadowReport {
        let documentSource = ContextualIngredientFilter.DocumentSource(
            kind: contextualShadowSourceKind(
                for: source,
                sourceDetail: sourceDetail,
                sourceLines: sourceLines
            ),
            documentID: "recipe-parser-shadow",
            detail: sourceDetail
        )
        let records = contextualShadowLineRecords(text: text, sourceLines: sourceLines)
        let parserInputRecords = records.filter {
            !$0.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let authoritativeAcceptedLineIDs = authoritativeAcceptedLineOrdinals.compactMap { ordinal in
            parserInputRecords.indices.contains(ordinal) ? parserInputRecords[ordinal].id : nil
        }
        let contextualResult = ContextualIngredientFilter.filter(
            records,
            source: documentSource,
            using: .contextual
        )
        let authoritativeAcceptedIDSet = Set(authoritativeAcceptedLineIDs)
        let contextualByID = Dictionary(
            uniqueKeysWithValues: contextualResult.decisions.map { ($0.lineID, $0) }
        )
        let divergences = records.compactMap { record -> ContextualIngredientFilter.Divergence? in
            guard let contextual = contextualByID[record.id] else { return nil }
            let authoritativeDisposition: ContextualIngredientFilter.Disposition =
                authoritativeAcceptedIDSet.contains(record.id) ? .accepted : .ignored
            guard authoritativeDisposition != contextual.disposition else { return nil }
            return ContextualIngredientFilter.Divergence(
                lineID: record.id,
                originalText: record.originalText,
                legacyDisposition: authoritativeDisposition,
                contextualDisposition: contextual.disposition,
                legacyReason: nil,
                contextualReason: contextual.acceptanceReason,
                contextualIgnoredReasons: contextual.ignoredReasons
            )
        }
        return ContextualShadowReport(
            source: documentSource,
            records: records,
            authoritativeAcceptedLineIDs: authoritativeAcceptedLineIDs,
            contextualResult: contextualResult,
            divergence: ContextualIngredientFilter.DivergenceReport(
                comparedLineCount: records.count,
                agreementCount: records.count - divergences.count,
                divergences: divergences
            )
        )
    }

    private static func contextualShadowLineRecords(
        text: String,
        sourceLines: [OCRSourceLine]
    ) -> [ContextualIngredientFilter.LineRecord] {
        let originalLines = text.components(separatedBy: .newlines)
        var remainingSourceLines = sourceLines
        var matchedSourceLines: [Int: OCRSourceLine] = [:]

        // Reserve exact matches across the whole document before considering
        // corrected-text fuzzy matches, and consume every OCR line at most once.
        for (index, originalText) in originalLines.enumerated() {
            let normalized = normalizedSourceText(originalText)
            guard !normalized.isEmpty,
                  let sourceIndex = remainingSourceLines.firstIndex(where: {
                      normalizedSourceText($0.text) == normalized
                  })
            else { continue }
            matchedSourceLines[index] = remainingSourceLines.remove(at: sourceIndex)
        }

        for (index, originalText) in originalLines.enumerated()
        where matchedSourceLines[index] == nil {
            guard let sourceIndex = bestSourceLineIndex(
                matching: originalText,
                in: remainingSourceLines
            ) else { continue }
            matchedSourceLines[index] = remainingSourceLines.remove(at: sourceIndex)
        }

        return originalLines.enumerated().map { index, originalText in
            let evidence: ContextualIngredientFilter.LineEvidence
            if let sourceLine = matchedSourceLines[index] {
                evidence = ContextualIngredientFilter.LineEvidence(
                    ocrSourceLine: sourceLine,
                    sectionID: "ocr-ingredient-stream",
                    sectionName: "Ingredients"
                )
            } else {
                evidence = .none
            }
            return ContextualIngredientFilter.LineRecord(
                id: String(format: "recipe-parser-shadow-line-%04d", index + 1),
                originalText: originalText,
                ordinal: index,
                evidence: evidence
            )
        }
    }

    private static func contextualShadowSourceKind(
        for source: RecipeSource,
        sourceDetail: String,
        sourceLines: [OCRSourceLine]
    ) -> ContextualIngredientFilter.DocumentSource.Kind {
        switch source {
        case .photo:
            if sourceLines.contains(where: { $0.pageIndex > 0 })
                || Set(sourceLines.map(\.pageIndex)).count > 1 {
                return .multiPageScan
            }
            let detail = sourceDetail.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            if detail.localizedCaseInsensitiveContains("captured") {
                return .cameraPhoto
            }
            if detail.localizedCaseInsensitiveContains("photos") {
                return .photoLibrary
            }
            return .screenshot
        case .link:
            return .structuredURL
        case .pinterest:
            return .pinterest
        case .text:
            return .pastedText
        case .sample:
            return .groceryList
        }
    }
    #endif

    static func importReport(
        for recipe: Recipe,
        recognizedText: String,
        sourcePageCount: Int = 1,
        retryCount: Int = 0,
        duration: TimeInterval = 0
    ) -> RecipeImportReport {
        let nonemptyLines = recognizedText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let candidateLineCount = candidateIngredientLineCount(in: nonemptyLines)
        return RecipeImportReport(
            sourcePageCount: max(1, sourcePageCount),
            recognizedLineCount: nonemptyLines.count,
            ingredientLineCount: recipe.ingredients.count,
            highConfidenceCount: recipe.ingredients.filter { $0.confidence == .high }.count,
            reviewCount: recipe.ingredients.filter { $0.confidence == .review }.count,
            unknownCount: recipe.ingredients.filter { $0.confidence == .unknown }.count,
            retryCount: max(0, retryCount),
            duration: max(0, duration),
            omittedCandidateLineCount: max(0, candidateLineCount - recipe.ingredients.count),
            requiredConfirmationCount: recipe.ingredients.filter { $0.quantityReviewRequired == true }.count
        )
    }

    static func sanitizedIngredientCandidate(from line: String) -> SanitizedIngredientCandidate {
        let originalText = line
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return SanitizedIngredientCandidate(
                ingredientText: "",
                originalText: originalText,
                removedSuffix: nil,
                requiresReview: false,
                reviewReasons: []
            )
        }

        // A continuation that lost its ingredient anchor is not independently
        // purchasable. Keep this deliberately narrow; broader contextual
        // ingredient filtering is handled separately.
        if text.range(
            of: #"^\s*[-•*☐✓]?\s*for\s+topping[.!]?\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return SanitizedIngredientCandidate(
                ingredientText: "",
                originalText: originalText,
                removedSuffix: nil,
                requiresReview: true,
                reviewReasons: ["preparation_only"]
            )
        }

        guard let boundary = strongInstructionBoundary(in: text) else {
            return SanitizedIngredientCandidate(
                ingredientText: text,
                originalText: originalText,
                removedSuffix: nil,
                requiresReview: false,
                reviewReasons: []
            )
        }

        let ingredientText = text[..<boundary]
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?"))
        let removedSuffix = text[boundary...]
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: ",;:")
                )
            )

        return SanitizedIngredientCandidate(
            ingredientText: ingredientText,
            originalText: originalText,
            removedSuffix: removedSuffix.isEmpty ? nil : removedSuffix,
            requiresReview: true,
            reviewReasons: ["instruction_suffix_removed"]
        )
    }

    private static func strongInstructionBoundary(in text: String) -> String.Index? {
        // These are intentionally high-signal imperative starts. Ambiguous
        // grocery nouns/verbs such as cream, toast, roll, slice, blend, and
        // juice do not belong here.
        let strongImperative = #"(?:preheat|heat|mix|stir|whisk|combine|add|bake|cook|simmer|boil|roast|grill|fold|beat|place|transfer|spread|pour|arrange|season|chill|refrigerate|freeze|serve|mash|let|set|grease|melt|bring)"#
        let sentenceStartPattern = #"(?i)(?:^|[.!?]\s*)(?:step\s+\d{1,2}\s*[:.)-]?\s*)?("#
            + strongImperative
            + #")\b"#
        guard let match = text.range(of: sentenceStartPattern, options: .regularExpression),
              let verb = text[match].range(
                of: strongImperative,
                options: [.regularExpression, .caseInsensitive]
              )
        else { return nil }

        var boundary = match.lowerBound

        // A compact promotional instruction banner can sit between the final
        // ingredient delimiter and the first imperative sentence. Once an
        // imperative has confirmed the transition, remove that banner too.
        let bannerPrefix = text[..<verb.lowerBound]
        if let banner = bannerPrefix.range(
            of: #"(?i),\s*easy\s+as\s+\d+(?:\s*[-–—]\s*\d+)+\s*[.!?]?\s*$"#,
            options: .regularExpression
        ) {
            boundary = banner.lowerBound
        }
        return boundary
    }

    private static func apply(
        candidate: SanitizedIngredientCandidate,
        to ingredient: inout Ingredient
    ) {
        if candidate.requiresReview {
            ingredient.confidence = .review
        }
        guard candidate.removedSuffix != nil,
              var evidence = ingredient.sourceEvidence
        else { return }
        // The parsed shopping fields use only the sanitized ingredient text,
        // while review keeps the complete source line, including what was cut.
        evidence.rawText = candidate.originalText
        if evidence.originalLine == nil {
            evidence.originalLine = candidate.originalText
        }
        evidence.removedSuffix = candidate.removedSuffix
        var reviewReasons = evidence.reviewReasons ?? []
        for reason in candidate.reviewReasons where !reviewReasons.contains(reason) {
            reviewReasons.append(reason)
        }
        evidence.reviewReasons = reviewReasons.isEmpty ? nil : reviewReasons
        ingredient.sourceEvidence = evidence
    }

    private static func isLikelyIngredient(
        _ line: String,
        contextAllowsQuantitylessLine: Bool = false
    ) -> Bool {
        let value = line.lowercased()
        guard !isLikelyInstruction(line), !isRecipeMetadata(line) else { return false }
        if line.range(
            of: #"^\s*[-•*☐✓]?\s*(?:about\s+|approximately\s+|~\s*)?(?:\d|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|a\b|an\b|one\b|two\b|three\b|four\b|five\b|six\b|seven\b|eight\b|nine\b|ten\b|half\b|quarter\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil { return true }
        if value.range(
            of: #"\b(cups?|tbsp|tablespoons?|tsp|teaspoons?|oz|ounces?|lbs?|pounds?|grams?|kg|ml|liters?|cloves?|cans?|jars?|packages?|pinch(?:es)?|bunch(?:es)?|to taste|as needed)\b"#,
            options: .regularExpression
        ) != nil { return true }
        if ["salt", "pepper", "oil", "parsley", "cilantro", "water", "basil", "thyme", "rosemary"].contains(where: {
            value.hasPrefix($0) || value.contains(" \($0)")
        }) { return true }
        guard contextAllowsQuantitylessLine else { return false }
        let wordCount = line.split(whereSeparator: \Character.isWhitespace).count
        return (1...14).contains(wordCount) && !line.hasSuffix(".")
    }

    private static func isIngredientHeading(_ line: String) -> Bool {
        let key = headingKey(line)
        return ["ingredients", "ingredient", "what you need", "you will need"].contains(key)
    }

    private static func isInstructionHeading(_ line: String) -> Bool {
        let key = headingKey(line)
        let exact = ["directions", "instructions", "method", "steps", "preparation", "how to make"]
        return exact.contains(key)
            || key.hasPrefix("directions ")
            || key.hasPrefix("instructions ")
    }

    private static func isSectionHeading(_ line: String) -> Bool {
        let key = headingKey(line)
        if isIngredientHeading(line) { return false }
        let common = ["cake", "frosting", "filling", "syrup", "sauce", "dough", "topping", "garnish", "marinade", "dry ingredients", "wet ingredients"]
        if common.contains(key) { return true }
        guard line.hasSuffix(":"),
              line.split(whereSeparator: \Character.isWhitespace).count <= 7,
              line.range(
                of: #"\b(cups?|tbsp|tsp|oz|lbs?|grams?|kg|ml|cloves?|cans?|packages?)\b"#,
                options: [.regularExpression, .caseInsensitive]
              ) == nil
        else { return false }
        return true
    }

    private static func isLikelyInstruction(_ line: String) -> Bool {
        if isInstructionHeading(line) { return true }
        var value = headingKey(line)
        value = value.replacingOccurrences(
            of: #"^\d{1,2}[.)]\s*"#,
            with: "",
            options: .regularExpression
        )
        let actions = [
            "preheat", "heat", "mix", "stir", "whisk", "combine", "add", "bake",
            "cook", "simmer", "boil", "roast", "grill", "fold", "beat", "place",
            "transfer", "spread", "pour", "arrange", "season", "chill", "refrigerate",
            "freeze", "serve", "mash", "let", "set", "line", "grease", "melt", "bring"
        ]
        return actions.contains { value == $0 || value.hasPrefix($0 + " ") }
    }

    private static func isRecipeMetadata(_ line: String) -> Bool {
        let value = headingKey(line)
        if value.range(
            of: #"^(prep|preparation|cook|bake|total)\s+time\b|^(serves|servings|yield|makes|calories)\b"#,
            options: .regularExpression
        ) != nil { return true }
        return value.range(of: #"^\d+\s*°\s*[fc]\b"#, options: .regularExpression) != nil
    }

    private static func headingKey(_ line: String) -> String {
        line.lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func candidateIngredientLineCount(in lines: [String]) -> Int {
        var isInsideIngredientSection = false
        var count = 0
        for rawLine in lines.prefix(120) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if isInstructionHeading(line) { break }
            if isIngredientHeading(line) {
                isInsideIngredientSection = true
                continue
            }
            if isSectionHeading(line) {
                isInsideIngredientSection = true
                continue
            }
            let candidate = sanitizedIngredientCandidate(from: line)
            let ingredientLine = candidate.ingredientText
            guard !ingredientLine.isEmpty else { continue }
            if isLikelyInstruction(ingredientLine) {
                if count > 0 { break }
                continue
            }
            if isLikelyIngredient(
                ingredientLine,
                contextAllowsQuantitylessLine: isInsideIngredientSection
            ) {
                count += 1
            }
        }
        return count
    }

    private static func parseIngredient(_ line: String, source: RecipeSource) -> Ingredient {
        let isOptional = line.range(
            of: #"\b(optional|if desired|as desired)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        var cleaned = normalizedIngredientText(line)
        let isApproximate = cleaned.range(
            of: #"^(?:about|approximately|approx\.?|~)\s*"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        cleaned = cleaned.replacingOccurrences(
            of: #"^(?:about|approximately|approx\.?|~)\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        let tokens = cleaned.split(separator: " ").map(String.init)
        let leadingQuantity = parseLeadingQuantity(tokens)
        let consumed = leadingQuantity?.consumedTokenCount ?? 0
        var quantity = leadingQuantity?.upperBound ?? 1
        let quantityLowerBound = leadingQuantity.flatMap { parsed in
            parsed.lowerBound < parsed.upperBound ? parsed.lowerBound : nil
        }
        let foundQuantity = leadingQuantity != nil

        let knownUnits = [
            "cup", "cups", "c", "tbsp", "tbs", "tbsps", "tablespoon", "tablespoons",
            "tsp", "tsps", "teaspoon", "teaspoons",
            "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "g", "gram", "grams",
            "kg", "kilogram", "kilograms", "ml", "milliliter", "milliliters", "l", "liter", "liters",
            "clove", "cloves", "can", "cans", "jar", "jars", "bag", "bags", "bunch",
            "bunches", "package", "packages", "pkg", "pinch", "pinches", "slice", "slices",
            "stick", "sticks", "head", "heads", "sprig", "sprigs", "ea", "each", "count"
        ]
        var remainingTokens = Array(tokens.dropFirst(consumed))
        if remainingTokens.first?.lowercased() == "x" {
            remainingTokens.removeFirst()
        }
        let packageMeasurement = consumeLeadingPackageMeasurement(from: &remainingTokens)

        var unit = ""
        if remainingTokens.count >= 2,
           ["fl", "fluid"].contains(remainingTokens[0].lowercased().trimmingCharacters(in: .punctuationCharacters)),
           ["oz", "ounce", "ounces"].contains(remainingTokens[1].lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            unit = "fl oz"
            remainingTokens.removeFirst(2)
        } else if let firstRemaining = remainingTokens.first {
            let candidate = firstRemaining.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if knownUnits.contains(candidate) {
                unit = normalizedUnit(candidate)
                remainingTokens.removeFirst()
            } else if remainingTokens.count >= 2,
                      ["small", "medium", "large"].contains(candidate),
                      ["egg", "eggs"].contains(
                        remainingTokens[1].lowercased().trimmingCharacters(in: .punctuationCharacters)
                      ) {
                unit = candidate
                remainingTokens.removeFirst()
            }
        }

        var compoundMeasurements: [IngredientMeasurement] = []
        var compoundMeasurementNeedsReview = false
        if foundQuantity {
            compoundMeasurements.append(IngredientMeasurement(quantity: quantity, unit: unit))
        }
        if remainingTokens.first == "+", remainingTokens.count >= 3,
           let additionalQuantity = parseQuantity(remainingTokens[1]) {
            var extraConsumed = 2
            if remainingTokens.count > 3,
               let fraction = parseFraction(remainingTokens[2]),
               !remainingTokens[2].contains("-") {
                extraConsumed = 3
                compoundMeasurements.append(
                    IngredientMeasurement(quantity: additionalQuantity + fraction, unit: normalizedUnit(remainingTokens[3].lowercased().trimmingCharacters(in: .punctuationCharacters)))
                )
                extraConsumed += 1
            } else {
                let extraUnit = normalizedUnit(remainingTokens[2].lowercased().trimmingCharacters(in: .punctuationCharacters))
                compoundMeasurements.append(IngredientMeasurement(quantity: additionalQuantity, unit: extraUnit))
                extraConsumed += 1
            }
            remainingTokens.removeFirst(min(extraConsumed, remainingTokens.count))
        }
        if compoundMeasurements.count > 1,
           let primary = compoundMeasurements.first {
            if let total = totalQuantity(compoundMeasurements, in: primary.unit) {
                quantity = total
            } else {
                compoundMeasurementNeedsReview = true
            }
        }

        let remaining = remainingTokens.joined(separator: " ")
        let commaParts = remaining.split(separator: ",", omittingEmptySubsequences: true).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let preparationPattern = #"(?i)\b(optional|if desired|as desired|as needed|divided|softened|melted|sifted|packed|room temperature|at room temperature|chopped|roughly chopped|finely chopped|minced|drained|rinsed|cubed|diced|peeled|seeded|zested|juiced|crushed|grated|shredded|plus more[^,]*|for serving|for garnish|for topping|to taste)\b"#
        var nameParts: [String] = []
        var commaPreparationParts: [String] = []
        for (index, part) in commaParts.enumerated() {
            if index > 0, isPreparationText(part, pattern: preparationPattern) {
                commaPreparationParts.append(part)
            } else {
                nameParts.append(part)
            }
        }
        let rawName = nameParts.isEmpty ? remaining : nameParts.joined(separator: ", ")
        let parentheticals = matches(pattern: #"\(([^)]*)\)"#, in: rawName, capture: 1)
        var equivalentMeasurements = parentheticals.compactMap(parseMeasurement)
        if let packageMeasurement,
           !equivalentMeasurements.contains(packageMeasurement) {
            equivalentMeasurements.insert(packageMeasurement, at: 0)
        }
        let brandNote = parentheticals.first {
            parseMeasurement($0) == nil
                && !isPreparationText($0, pattern: preparationPattern)
                && $0.range(of: #"(?i)\bor\b"#, options: .regularExpression) == nil
        }
        // For cans, jars, and other packaged foods, descriptors such as
        // "diced" or "crushed" identify the product a shopper must match;
        // they are not merely kitchen instructions. Comma-separated notes
        // (for example, "drained") were already extracted above.
        let isPackagedProduct = packageMeasurement != nil
            || ["can", "cans", "jar", "jars", "bag", "bags", "pkg"].contains(unit)
        let inlinePreparationPattern = isPackagedProduct
            ? #"(?i)\b(optional|if desired|as desired|as needed|divided|plus more[^,]*|for serving|for garnish|for topping|to taste)\b"#
            : preparationPattern
        let inlinePreparation = matches(pattern: inlinePreparationPattern, in: rawName, capture: 0)
        let name = rawName
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: inlinePreparationPattern, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^of\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
        let preparation = (commaPreparationParts + inlinePreparation)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            .replacingOccurrences(of: "optional", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
        let normalizedName = normalizeIngredientName(name.isEmpty ? cleaned : name)
        let category = category(for: normalizedName)
        let staple = normalizedName.lowercased()
        let pantryState: PantryState
        if staple.contains("salt") || staple.contains("black pepper") {
            pantryState = .haveEnough
        } else if staple.contains("olive oil") || staple.contains("flour") {
            pantryState = .runningLow
        } else {
            pantryState = .needToBuy
        }

        let malformedFraction = line.range(
            of: #"(?<!\d)[?/]|\d\s*/\s*[^\d\s]"#,
            options: .regularExpression
        ) != nil
        let suspiciousOCRQuantity = cleaned.range(
            of: #"^(?:[Il]/\d|\d+[OIl]\b|[Il]\s+(?:cups?|tbsp|tsp|oz|lbs?|grams?|ml)\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let malformedQuantity = malformedFraction
            || suspiciousOCRQuantity
            || compoundMeasurementNeedsReview
        let strategy: IngredientExtractionStrategy = switch source {
        case .photo: .visionOCR
        case .link, .pinterest: .structuredData
        case .text: .pastedText
        case .sample: .sample
        }
        let parserConfidence: Double
        if malformedQuantity || normalizedName.isEmpty {
            parserConfidence = 0.42
        } else if isApproximate || quantityLowerBound != nil {
            parserConfidence = 0.84
        } else if foundQuantity {
            parserConfidence = 0.94
        } else {
            parserConfidence = 0.66
        }
        let alternativeGroup = line.range(of: #"(?i)\bor\b"#, options: .regularExpression) == nil
            ? nil
            : UUID().uuidString

        return Ingredient(
            rawText: line,
            name: normalizedName.capitalized,
            quantity: quantity,
            quantityLowerBound: quantityLowerBound,
            unit: unit,
            preparation: preparation,
            category: category,
            confidence: foundQuantity && !normalizedName.isEmpty && !malformedQuantity && !isApproximate && quantityLowerBound == nil
                ? .high
                : .review,
            includeInList: !isOptional,
            pantryState: pantryState,
            brandNote: brandNote,
            compoundMeasurements: compoundMeasurements.count > 1 ? compoundMeasurements : nil,
            equivalentMeasurements: equivalentMeasurements.isEmpty ? nil : equivalentMeasurements,
            alternativeGroup: alternativeGroup,
            sourceEvidence: IngredientSourceEvidence(
                rawText: line,
                pageIndex: nil,
                boundingBox: nil,
                extractionStrategy: strategy,
                ocrConfidence: nil,
                layoutConfidence: nil,
                parserConfidence: parserConfidence,
                normalizationConfidence: normalizedName.isEmpty ? 0.35 : 0.92,
                alternateQuantityCandidates: malformedQuantity
                    ? []
                    : [quantityLowerBound, quantity].compactMap { $0 }
            ),
            quantityReviewRequired: malformedQuantity
        )
    }

    private static func apply(
        sourceLine: OCRSourceLine,
        to ingredient: inout Ingredient,
        source: RecipeSource
    ) {
        guard var evidence = ingredient.sourceEvidence else { return }
        evidence.rawText = sourceLine.text
        evidence.pageIndex = sourceLine.pageIndex
        evidence.boundingBox = NormalizedSourceRect(
            x: sourceLine.boundingBox.x,
            y: sourceLine.boundingBox.y,
            width: sourceLine.boundingBox.width,
            height: sourceLine.boundingBox.height
        )
        evidence.ocrConfidence = sourceLine.confidence
        evidence.ocrColumnIndex = sourceLine.columnIndex
        evidence.sourceObservationIDs = sourceLine.sourceObservationIDs
        evidence.continuationAttached = sourceLine.continuationAttached
        evidence.reconstructionConfidence = sourceLine.reconstructionConfidence

        let credibleAlternatives = sourceLine.alternateCandidates.filter { alternative in
            let purchasingCritical = containsPurchasingCriticalMeasurement(sourceLine.text)
                || containsPurchasingCriticalMeasurement(alternative.text)
            return alternative.confidence >= (
                purchasingCritical ? 0.35 : max(0.35, sourceLine.confidence - 0.12)
            )
        }
        evidence.alternateSourceTexts = credibleAlternatives.isEmpty
            ? nil
            : credibleAlternatives.map(\.text)

        var quantityCandidates = [ingredient.quantity]
        var quantityOrUnitDiffers = false
        var parsedMeaningDiffers = false
        for alternative in credibleAlternatives {
            guard isLikelyIngredient(alternative.text) else { continue }
            let parsed = parseIngredient(alternative.text, source: source)
            guard (parsed.sourceEvidence?.parserConfidence ?? 0) >= 0.8 else { continue }
            if !quantityCandidates.contains(where: { abs($0 - parsed.quantity) < 0.0001 }) {
                quantityCandidates.append(parsed.quantity)
            }
            if abs(parsed.quantity - ingredient.quantity) >= 0.0001 || parsed.unit != ingredient.unit {
                quantityOrUnitDiffers = true
            }
            if parsed.name.caseInsensitiveCompare(ingredient.name) != .orderedSame {
                parsedMeaningDiffers = true
            }
        }
        evidence.alternateQuantityCandidates = quantityCandidates
        ingredient.sourceEvidence = evidence

        if sourceLine.confidence < 0.72 || quantityOrUnitDiffers || parsedMeaningDiffers {
            ingredient.confidence = .review
        }
        if quantityOrUnitDiffers {
            ingredient.quantityReviewRequired = true
        }
    }

    private static func normalizedSourceText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"^[-•*☐✓]\s*"#, with: "", options: .regularExpression)
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    /// Keeps corrected OCR ingredients attached to their original image evidence.
    /// A fuzzy match is accepted only when it is strong and unambiguous; otherwise
    /// review evidence is intentionally left unattached instead of guessing.
    private static func bestSourceLineIndex(
        matching line: String,
        in sourceLines: [OCRSourceLine]
    ) -> Int? {
        let targetTokens = sourceAlignmentTokens(line)
        guard !targetTokens.isEmpty else { return nil }

        let ranked = sourceLines.enumerated().compactMap { index, sourceLine -> (Int, Double)? in
            let candidateTokens = sourceAlignmentTokens(sourceLine.text)
            guard !candidateTokens.isEmpty else { return nil }
            let overlap = targetTokens.intersection(candidateTokens).count
            guard overlap > 0 else { return nil }

            var score = Double(overlap) / Double(max(targetTokens.count, candidateTokens.count))
            if containsPurchasingCriticalMeasurement(line)
                && containsPurchasingCriticalMeasurement(sourceLine.text) {
                score += 0.05
            }
            return (index, min(score, 1))
        }
        .sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1
        }

        guard let best = ranked.first, best.1 >= 0.65 else { return nil }
        if ranked.count > 1, best.1 - ranked[1].1 < 0.15 { return nil }
        return best.0
    }

    private static func sourceAlignmentTokens(_ text: String) -> Set<String> {
        Set(
            normalizedSourceText(text)
                .split { !$0.isLetter && !$0.isNumber }
                .map { token in
                    let value = String(token)
                    guard value.contains(where: { $0.isNumber }) else { return value }
                    return value
                        .replacingOccurrences(of: "o", with: "0")
                        .replacingOccurrences(of: "l", with: "1")
                }
                .filter { !$0.isEmpty }
        )
    }

    private static func containsPurchasingCriticalMeasurement(_ text: String) -> Bool {
        text.range(
            of: #"[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|\d\s*[⁄/]\s*\d|^\s*[-•*☐✓]?\s*\d|\b(cups?|tbsp|tsp|oz|lbs?|grams?|kg|ml|liters?|cloves?|cans?|packages?)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private struct LeadingQuantity {
        var lowerBound: Double
        var upperBound: Double
        var consumedTokenCount: Int
    }

    private static func normalizedIngredientText(_ line: String) -> String {
        let fractionMap: [Character: String] = [
            "½": "1/2", "¼": "1/4", "¾": "3/4", "⅓": "1/3", "⅔": "2/3",
            "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8", "⅙": "1/6",
            "⅚": "5/6"
        ]
        var expanded = ""
        for character in line {
            if let fraction = fractionMap[character] {
                if expanded.last?.isNumber == true { expanded.append(" ") }
                expanded.append(fraction)
            } else {
                expanded.append(character)
            }
        }
        return expanded
            .replacingOccurrences(of: #"^[-•*☐✓]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "⁄", with: "/")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseLeadingQuantity(_ tokens: [String]) -> LeadingQuantity? {
        guard let first = tokens.first else { return nil }
        let token = first.trimmingCharacters(in: CharacterSet(charactersIn: "~≈+,"))

        // A hyphen between a whole number and a fraction is conventional mixed
        // number notation ("1-1/2"), not a range.
        if let regex = try? NSRegularExpression(pattern: #"^(\d+)-(\d+)/(\d+)$"#),
           let match = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
           let wholeRange = Range(match.range(at: 1), in: token),
           let numeratorRange = Range(match.range(at: 2), in: token),
           let denominatorRange = Range(match.range(at: 3), in: token),
           let whole = Double(token[wholeRange]),
           let numerator = Double(token[numeratorRange]),
           let denominator = Double(token[denominatorRange]),
           denominator != 0 {
            let value = whole + (numerator / denominator)
            return LeadingQuantity(lowerBound: value, upperBound: value, consumedTokenCount: 1)
        }

        if token.contains("-") {
            let rangeParts = token.split(separator: "-", maxSplits: 1).map(String.init)
            if rangeParts.count == 2,
               let firstValue = parseQuantity(rangeParts[0]),
               let secondValue = parseQuantity(rangeParts[1]) {
                return LeadingQuantity(
                    lowerBound: min(firstValue, secondValue),
                    upperBound: max(firstValue, secondValue),
                    consumedTokenCount: 1
                )
            }
        }

        if tokens.count >= 3,
           tokens[1].lowercased() == "to",
           let firstValue = parseQuantity(token),
           let secondValue = parseQuantity(tokens[2]) {
            return LeadingQuantity(
                lowerBound: min(firstValue, secondValue),
                upperBound: max(firstValue, secondValue),
                consumedTokenCount: 3
            )
        }

        guard var value = parseQuantity(token) else { return nil }
        var consumed = 1
        if tokens.count > 1,
           let fraction = parseFraction(tokens[1]),
           !tokens[1].contains("-") {
            value += fraction
            consumed = 2
        } else if tokens.count > 2,
                  tokens[1].lowercased() == "and",
                  let fraction = parseFraction(tokens[2]) {
            value += fraction
            consumed = 3
        }
        return LeadingQuantity(lowerBound: value, upperBound: value, consumedTokenCount: consumed)
    }

    private static func consumeLeadingPackageMeasurement(
        from tokens: inout [String]
    ) -> IngredientMeasurement? {
        guard !tokens.isEmpty else { return nil }
        if tokens[0].hasPrefix("("),
           let closingIndex = tokens.firstIndex(where: { $0.contains(")") }) {
            let candidate = tokens[0...closingIndex].joined(separator: " ")
            if let measurement = parseMeasurement(candidate) {
                tokens.removeFirst(closingIndex + 1)
                return measurement
            }
        }
        if let measurement = parseMeasurement(tokens[0]) {
            tokens.removeFirst()
            return measurement
        }
        return nil
    }

    private static func matches(pattern: String, in text: String, capture: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > capture,
                  let range = Range(match.range(at: capture), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func isPreparationText(_ text: String, pattern: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(of: pattern, options: .regularExpression) != nil { return true }
        let lowercased = trimmed.lowercased()
        return lowercased.hasPrefix("for ") || lowercased.hasPrefix("plus ")
    }

    private static func parseMeasurement(_ text: String) -> IngredientMeasurement? {
        let normalized = text
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "()")))
            .replacingOccurrences(
                of: #"(?<=\d)-(?=[A-Za-z])"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?<=\d)(?=[A-Za-z])"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let pattern = #"^\s*([0-9]+(?:\s+[0-9]+/[0-9]+|\.[0-9]+|/[0-9]+)?)\s+([A-Za-z]+(?:\s+oz)?)\s*$"#
        guard normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }
        let parts = normalized.split(separator: " ").map(String.init)
        guard let first = parts.first, var quantity = parseQuantity(first) else { return nil }
        var unitIndex = 1
        if parts.count > 2, let fraction = parseFraction(parts[1]) {
            quantity += fraction
            unitIndex = 2
        }
        guard parts.indices.contains(unitIndex) else { return nil }
        let rawUnit = parts[unitIndex...].joined(separator: " ").lowercased()
        return IngredientMeasurement(quantity: quantity, unit: normalizedUnit(rawUnit), rawText: text)
    }

    private static func totalQuantity(_ measurements: [IngredientMeasurement], in destinationUnit: String) -> Double? {
        var total = 0.0
        for measurement in measurements {
            if measurement.unit == destinationUnit {
                total += measurement.quantity
            } else if destinationUnit == "cup", measurement.unit == "tbsp" {
                total += measurement.quantity / 16
            } else if destinationUnit == "cup", measurement.unit == "tsp" {
                total += measurement.quantity / 48
            } else if destinationUnit == "tbsp", measurement.unit == "tsp" {
                total += measurement.quantity / 3
            } else if destinationUnit == "lb", measurement.unit == "oz" {
                total += measurement.quantity / 16
            } else if destinationUnit == "kg", measurement.unit == "g" {
                total += measurement.quantity / 1_000
            } else if destinationUnit == "l", measurement.unit == "ml" {
                total += measurement.quantity / 1_000
            } else {
                return nil
            }
        }
        return total
    }

    private static func parseQuantity(_ value: String) -> Double? {
        let cleaned = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "~≈+,"))
        let numberWords: [String: Double] = [
            "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4,
            "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "half": 0.5, "quarter": 0.25
        ]
        return parseFraction(cleaned) ?? Double(cleaned) ?? numberWords[cleaned.lowercased()]
    }

    private static func parseFraction(_ value: String) -> Double? {
        let parts = value.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return nil }
        return parts[0] / parts[1]
    }

    private static func normalizedUnit(_ unit: String) -> String {
        switch unit {
        case "tablespoon", "tablespoons", "tbs", "tbsps": "tbsp"
        case "teaspoon", "teaspoons", "tsps": "tsp"
        case "ounce", "ounces": "oz"
        case "fluid ounce", "fluid ounces", "fl ounce", "fl ounces": "fl oz"
        case "pound", "pounds", "lbs": "lb"
        case "packages", "package": "pkg"
        case "c": "cup"
        case "ea", "each", "count": "item"
        case "gram", "grams": "g"
        case "kilogram", "kilograms": "kg"
        case "milliliter", "milliliters": "ml"
        case "liter", "liters": "l"
        default: unit
        }
    }

    private static func normalizeIngredientName(_ name: String) -> String {
        var value = name
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = [
            "chicken breasts": "chicken breast",
            "boneless skinless chicken breast": "chicken breast",
            "boneless, skinless chicken breast": "chicken breast",
            "extra virgin olive oil": "olive oil",
            "evoo": "olive oil",
            "scallions": "green onion",
            "confectioners sugar": "powdered sugar",
            "garbanzo beans": "chickpeas"
        ]
        let lowercased = value.lowercased()
        if let alias = aliases[lowercased] {
            value = alias
        }
        return value
    }

    private static func category(for name: String) -> GroceryCategory {
        let value = name.lowercased()
        if ["milk", "cream", "cheese", "butter", "yogurt", "egg", "parmesan"].contains(where: value.contains) {
            return .dairy
        }
        if ["chicken", "beef", "pork", "salmon", "shrimp", "turkey", "sausage"].contains(where: value.contains) {
            return .meat
        }
        if ["bread", "tortilla", "bun", "bagel", "pita"].contains(where: value.contains) {
            return .bakery
        }
        if ["frozen", "ice cream"].contains(where: value.contains) {
            return .frozen
        }
        if [
            "onion", "garlic", "tomato", "spinach", "lime", "lemon", "pepper", "avocado",
            "cabbage", "carrot", "potato", "parsley", "cilantro", "broccoli", "bean"
        ].contains(where: value.contains) {
            return .produce
        }
        return .pantry
    }

    private static func inferredTitle(from lines: [String]) -> String {
        guard let first = lines.first, first.range(of: #"\d"#, options: .regularExpression) == nil else {
            return "Imported Recipe"
        }
        return String(first.prefix(48))
    }

    private static func inferredServings(from text: String) -> Int {
        let pattern = #"(?i)(serves|servings|yield)[:\s]+(\d+)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 2), in: text),
            let value = Int(text[range])
        else { return 4 }
        return value
    }

    private static func inferredCookTime(from text: String) -> Int {
        let pattern = #"(?i)(cook|bake)[^\d]{0,12}(\d+)\s*(minutes|min)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 2), in: text),
            let value = Int(text[range])
        else { return 30 }
        return value
    }

    private static func heroSymbol(for text: String) -> String {
        let value = text.lowercased()
        if value.contains("taco") { return "takeoutbag.and.cup.and.straw.fill" }
        if value.contains("pasta") || value.contains("spaghetti") { return "fork.knife" }
        if value.contains("soup") { return "cup.and.saucer.fill" }
        if value.contains("pizza") { return "circle.grid.cross.fill" }
        if value.contains("salad") { return "leaf.fill" }
        if value.contains("chicken") { return "flame.fill" }
        return "fork.knife"
    }
}

enum LegacyRecipeLinkImporter {
    static func importRecipe(from url: URL, source: RecipeSource) async throws -> Recipe {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<400 ~= http.statusCode else {
            throw RecipeImportError.unavailable
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw RecipeImportError.unreadable
        }

        let blocks = jsonLDBlocks(in: html)
        for block in blocks {
            let decoded = decodeHTMLEntities(block)
            guard let jsonData = decoded.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: jsonData),
                  let recipeObject = findRecipe(in: root)
            else { continue }

            let ingredients = recipeObject["recipeIngredient"] as? [String] ?? []
            guard !ingredients.isEmpty else { continue }
            let title = recipeObject["name"] as? String ?? url.host ?? "Imported Recipe"
            var recipe = RecipeParser.parse(
                title: title,
                text: ingredients.joined(separator: "\n"),
                source: source,
                sourceDetail: url.host ?? url.absoluteString
            )
            recipe.prepMinutes = durationMinutes(recipeObject["prepTime"] as? String) ?? recipe.prepMinutes
            recipe.cookMinutes = durationMinutes(recipeObject["cookTime"] as? String) ?? recipe.cookMinutes
            recipe.servings = servings(from: recipeObject["recipeYield"]) ?? recipe.servings
            return recipe
        }

        throw RecipeImportError.noStructuredRecipe
    }

    private static func jsonLDBlocks(in html: String) -> [String] {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[swiftRange])
        }
    }

    private static func findRecipe(in object: Any) -> [String: Any]? {
        if let dictionary = object as? [String: Any] {
            if isRecipeType(dictionary["@type"]) {
                return dictionary
            }
            if let graph = dictionary["@graph"], let result = findRecipe(in: graph) {
                return result
            }
            for value in dictionary.values {
                if let result = findRecipe(in: value) {
                    return result
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let result = findRecipe(in: value) {
                    return result
                }
            }
        }
        return nil
    }

    private static func isRecipeType(_ value: Any?) -> Bool {
        if let string = value as? String {
            return string.lowercased() == "recipe"
        }
        if let values = value as? [String] {
            return values.contains { $0.lowercased() == "recipe" }
        }
        return false
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func durationMinutes(_ duration: String?) -> Int? {
        guard let duration else { return nil }
        let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: duration, range: NSRange(duration.startIndex..., in: duration))
        else { return nil }

        var total = 0
        if let range = Range(match.range(at: 1), in: duration), let hours = Int(duration[range]) {
            total += hours * 60
        }
        if let range = Range(match.range(at: 2), in: duration), let minutes = Int(duration[range]) {
            total += minutes
        }
        return total > 0 ? total : nil
    }

    private static func servings(from value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let string = value as? String {
            return Int(string.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
        }
        if let values = value as? [String], let first = values.first {
            return Int(first.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
        }
        return nil
    }
}

enum RecipeImportError: LocalizedError {
    case unavailable
    case unreadable
    case noStructuredRecipe
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "That page could not be reached."
        case .unreadable:
            "SmartCart could not read that page."
        case .noStructuredRecipe:
            "No structured ingredient list was found. Try a recipe photo or paste the text instead."
        case .invalidURL:
            "Enter a complete recipe link beginning with https://."
        }
    }
}

private enum SampleData {
    static let recipes: [Recipe] = [
        Recipe(
            title: "Lemon Herb Chicken Pasta",
            source: .sample,
            sourceDetail: "SmartCart sample recipe",
            heroSymbol: "fork.knife",
            servings: 4,
            prepMinutes: 15,
            cookMinutes: 30,
            ingredients: [
                Ingredient(name: "Chicken breasts", quantity: 1, unit: "lb", category: .meat),
                Ingredient(name: "Penne pasta", quantity: 8, unit: "oz", category: .pantry),
                Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp", category: .pantry, pantryState: .runningLow),
                Ingredient(name: "Lemon zest and juice", quantity: 1, unit: "lemon", category: .produce),
                Ingredient(name: "Garlic", quantity: 2, unit: "cloves", preparation: "minced", category: .produce),
                Ingredient(name: "Heavy cream", quantity: 0.5, unit: "cup", category: .dairy),
                Ingredient(name: "Parmesan cheese", quantity: 0.5, unit: "cup", category: .dairy),
                Ingredient(name: "Fresh parsley", quantity: 1, unit: "bunch", category: .produce),
                Ingredient(name: "Salt", quantity: 1, unit: "tsp", category: .pantry, pantryState: .haveEnough)
            ]
        ),
        Recipe(
            title: "Creamy Garlic Parmesan Pasta",
            source: .sample,
            sourceDetail: "SmartCart sample recipe",
            heroSymbol: "fork.knife",
            servings: 6,
            prepMinutes: 10,
            cookMinutes: 25,
            ingredients: [
                Ingredient(name: "Fettuccine pasta", quantity: 16, unit: "oz", category: .pantry),
                Ingredient(name: "Butter", quantity: 4, unit: "tbsp", category: .dairy),
                Ingredient(name: "Garlic", quantity: 4, unit: "cloves", preparation: "minced", category: .produce),
                Ingredient(name: "Heavy cream", quantity: 2, unit: "cups", category: .dairy),
                Ingredient(name: "Parmesan cheese", quantity: 1, unit: "cup", category: .dairy)
            ]
        ),
        Recipe(
            title: "Weeknight Beef Stroganoff",
            source: .sample,
            sourceDetail: "SmartCart sample recipe",
            heroSymbol: "flame.fill",
            servings: 4,
            prepMinutes: 15,
            cookMinutes: 25,
            ingredients: [
                Ingredient(name: "Ground beef", quantity: 1, unit: "lb", category: .meat),
                Ingredient(name: "Egg noodles", quantity: 12, unit: "oz", category: .pantry),
                Ingredient(name: "Mushrooms", quantity: 8, unit: "oz", category: .produce),
                Ingredient(name: "Sour cream", quantity: 1, unit: "cup", category: .dairy),
                Ingredient(name: "Yellow onion", quantity: 1, category: .produce)
            ]
        )
    ]
}
