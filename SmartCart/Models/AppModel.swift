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
    var selectedRetailer: ShoppingRetailer {
        didSet { commerceDefaults.set(selectedRetailer.rawValue, forKey: Self.selectedRetailerKey) }
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

    /// Most-recently-shopped recipe ids, newest first. Stored in UserDefaults
    /// (not the JSON state schema) because it is pure UI ordering data.
    var recentRecipeIDs: [UUID] = [] {
        didSet {
            UserDefaults.standard.set(recentRecipeIDs.map(\.uuidString), forKey: Self.recentRecipesKey)
        }
    }

    private static let recentRecipesKey = "smartcart.recentRecipeIDs"
    private static let selectedRetailerKey = "smartcart.commerce.selectedRetailer"
    private static let shoppingRouteKey = "smartcart.commerce.shoppingRoute"
    private static let instacartRetailerKey = "smartcart.commerce.instacartRetailer"
    private static let commerceFulfillmentKey = "smartcart.commerce.fulfillment"
    private static let handoffFeedbackKey = "smartcart.commerce.lastFeedback"

    var recentRecipes: [Recipe] {
        recentRecipeIDs.compactMap { id in recipes.first { $0.id == id } }
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
        do {
            restoredState = try stateStore.load()
            stateLoadError = nil
        } catch {
            restoredState = nil
            stateLoadError = error
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

        recipes = initialRecipes
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
        recentRecipeIDs = (UserDefaults.standard.stringArray(forKey: Self.recentRecipesKey) ?? [])
            .compactMap(UUID.init(uuidString:))
        if let stateLoadError {
            persistenceIssue = stateLoadError.localizedDescription
            persistenceReady = false
        } else {
            persistenceReady = true
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
                homePath = [.guidedShopping]
            case "target-guide":
                startRetailerGuide(.target)
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
        activeRecipe.ingredients.filter(\.includeInList).count
    }

    var unresolvedQuantityReviewCount: Int {
        activeRecipe.ingredients.filter { $0.includeInList && $0.quantityReviewRequired == true }.count
    }

    var ingredientsToBuy: [Ingredient] {
        activeRecipe.ingredients.filter {
            quantityToBuy(for: $0) > 0
        }
    }

    var pantrySkipCount: Int {
        activeRecipe.ingredients.filter {
            $0.includeInList && quantityToBuy(for: $0) == 0
        }.count
    }

    var pantrySuggestionCount: Int {
        activeRecipe.ingredients.filter { $0.pantrySuggestion != nil }.count
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
            let quantity = quantityToBuy(for: ingredient)
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
            localManifestID: currentSavedManifest?.id ?? activeRecipe.id,
            recipeID: activeRecipe.id,
            title: activeRecipe.title,
            desiredServings: desiredServings,
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

    var pricedItemCount: Int {
        shoppingItems.filter(\.product.hasObservedPrice).count
    }

    var guidedCompletedCount: Int {
        shoppingItems.filter { $0.status.isCompleted }.count
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
            "SmartCart · \(activeRecipe.title)",
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

    func openImporter(_ method: ImportMethod) {
        track(.importStarted, properties: ["method": method.rawValue])
        presentedSheet = .importer(method)
    }

    func beginRecipe(_ recipe: Recipe) {
        var recipe = recipe
        desiredServings = recipe.servings
        applyPantrySuggestions(to: &recipe)
        activeRecipe = recipe
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }
        recentRecipeIDs = ([recipe.id] + recentRecipeIDs.filter { $0 != recipe.id }).prefix(5).map { $0 }
        shoppingItems = []
        matchProgress = 0
        matchStage = "Ready to match"
        isMatching = false
        guidedIndex = 0
        selectedTab = .home
        presentedSheet = nil
        homePath = [.ingredientReview]
        track(
            .extractionCompleted,
            properties: [
                "source": recipe.source.rawValue,
                "ingredient_count": String(recipe.ingredients.count)
            ]
        )
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

    private func applyPantrySuggestions(to recipe: inout Recipe) {
        let multiplier = Double(desiredServings) / Double(max(1, recipe.servings))
        for index in recipe.ingredients.indices {
            let previousItemID = recipe.ingredients[index].pantrySuggestion?.pantryItemID
            let suggestion = PantryMatchingService.bestSuggestion(
                for: recipe.ingredients[index],
                requiredQuantity: recipe.ingredients[index].quantity * multiplier,
                inventory: pantryInventory
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

    func continueTo(_ route: SmartRoute) {
        if route == .matching {
            // Preferences, pantry decisions, servings, or store selection may
            // have changed while navigating back. Rebuild from the confirmed
            // recipe instead of reusing product matches from an older plan.
            synchronizeActiveRecipeRecord()
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

    private func synchronizeActiveRecipeRecord() {
        if let index = recipes.firstIndex(where: { $0.id == activeRecipe.id }) {
            recipes[index] = activeRecipe
        } else {
            recipes.insert(activeRecipe, at: 0)
        }
    }

    private func invalidateShoppingPlan() {
        shoppingItems = []
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
        invalidateShoppingPlan()
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
            invalidateShoppingPlan()
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

        if !shoppingItems.isEmpty && !force {
            matchProgress = 1
            matchStage = "\(shoppingItems.count) products ready"
            return
        }

        isMatching = true
        matchProgress = 0
        shoppingItems = []

        let stages = [
            ("Reading saved shopping preferences", 0.12),
            ("Searching \(primaryStore.name)", 0.28),
            ("Checking package sizes", 0.38),
            ("Applying dietary and organic rules", 0.55),
            ("Ranking eligible products", 0.74),
            ("Building a retailer handoff manifest", 0.94)
        ]

        for (stage, progress) in stages {
            matchStage = stage
            withAnimation(.easeInOut(duration: 0.28)) {
                matchProgress = progress
            }
            try? await Task.sleep(for: .milliseconds(330))
        }

        shoppingItems = await buildShoppingItems()
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

    func updatePurchaseQuantity(for itemID: UUID, delta: Int) {
        guard let index = shoppingItems.firstIndex(where: { $0.id == itemID }) else { return }
        shoppingItems[index].purchaseQuantity = max(1, shoppingItems[index].purchaseQuantity + delta)
    }

    func selectAlternative(itemID: UUID, candidateID: UUID) {
        guard
            let itemIndex = shoppingItems.firstIndex(where: { $0.id == itemID }),
            let candidateIndex = shoppingItems[itemIndex].alternatives.firstIndex(where: { $0.id == candidateID })
        else { return }

        let previous = shoppingItems[itemIndex].product
        let replacement = shoppingItems[itemIndex].alternatives.remove(at: candidateIndex)
        shoppingItems[itemIndex].alternatives.append(previous)
        shoppingItems[itemIndex].product = replacement
        preferredProductIDsByIngredient[productPreferenceKey(
            for: shoppingItems[itemIndex].ingredient.name,
            retailerID: replacement.retailerID
        )] = replacement.retailerProductID
        track(.productReplaced, properties: ["link_kind": replacement.linkKind.rawValue])
        showToast("Product replacement selected")
    }

    func markCurrentGuidedItem(_ status: GuidedItemStatus) {
        guard shoppingItems.indices.contains(guidedIndex) else { return }
        shoppingItems[guidedIndex].status = status
        track(.guidedItemCompleted, properties: ["status": status.rawValue])
        persistCurrentManifest(progress: .inProgress)
    }

    func advanceGuidedItem() {
        guard !shoppingItems.isEmpty else { return }
        if guidedIndex < shoppingItems.count - 1 {
            guidedIndex += 1
        } else {
            persistCurrentManifest(progress: .completed)
            track(.guidedShoppingCompleted, properties: ["items": String(shoppingItems.count)])
            showToast("Guided shopping complete")
        }
    }

    func moveGuidedItem(by delta: Int) {
        guard !shoppingItems.isEmpty else { return }
        guidedIndex = min(shoppingItems.count - 1, max(0, guidedIndex + delta))
    }

    func saveCurrentList() {
        persistCurrentManifest(progress: currentSavedManifest?.handoffProgress ?? .notStarted)
        showToast("Shopping manifest saved")
    }

    func beginGuidedShopping() {
        if let firstWaiting = shoppingItems.firstIndex(where: { $0.status == .waiting }) {
            guidedIndex = firstWaiting
        } else {
            guidedIndex = 0
        }
        persistCurrentManifest(progress: .inProgress)
        continueTo(.guidedShopping)
    }

    func recordWalmartSetupStarted() {
        track(.walmartSetupStarted)
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

    func recordRetailerOutcome(_ outcome: GuidedItemStatus, for itemID: UUID) {
        guard outcome != .waiting,
              let itemIndex = shoppingItems.firstIndex(where: { $0.id == itemID })
        else { return }

        let retailerID = shoppingItems[itemIndex].product.retailerID
        let wasComplete = retailerGuideIsComplete
        shoppingItems[itemIndex].status = outcome
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
                let properties = [
                    "retailer": retailerID,
                    "saved": String(savedForLaterCount),
                    "cart": String(retailerAddedCount),
                    "unavailable": String(retailerUnavailableCount),
                    "skipped": String(retailerSkippedCount)
                ]
                if retailerID == ShoppingRetailer.walmart.rawValue {
                    track(.walmartGuidedFlowCompleted, properties: properties)
                }
                track(.guidedShoppingCompleted, properties: properties)
                showToast("\(retailerConfiguration.displayName) shopping guide complete")
            }
        }
    }

    func recordWalmartProductOpened(itemID: UUID) {
        recordRetailerProductOpened(itemID: itemID)
    }

    func recordWalmartOutcome(_ outcome: GuidedItemStatus, for itemID: UUID) {
        recordRetailerOutcome(outcome, for: itemID)
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
            return try createOrReuseCurrentShoppingSession()
        } catch {
            persistenceIssue = error.localizedDescription
            showToast("Shopping progress could not be saved")
            return nil
        }
    }

    func startShoppingReconciliation() {
        guard let sessionID = ensureCurrentShoppingSession() else { return }
        track(.shoppingReconciliationStarted)
        continueTo(.shoppingReconciliation(sessionID))
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
        let validItemIDs = Set(session.items.map(\.id))
        let confirmedPurchasedIDs: Set<UUID> = outcome == .didNotShop
            ? []
            : purchasedItemIDs.intersection(validItemIDs)
        let validSubstitutions = substitutions.filter {
            confirmedPurchasedIDs.contains($0.originalItemID)
        }

        var updatedPantry = pantryInventory
        var updatedPreferences = preferredProductIDsByIngredient
        var touchedPantryIDs = Set<UUID>()
        for item in session.items where confirmedPurchasedIDs.contains(item.id) {
            let substitution = validSubstitutions.first { $0.originalItemID == item.id }
            let pantryID = mergePurchasedItem(
                item,
                substitution: substitution,
                into: &updatedPantry
            )
            touchedPantryIDs.insert(pantryID)

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
        updatedSessions[sessionIndex].reconciliation = ShoppingReconciliationRecord(
            outcome: outcome,
            purchasedItemIDs: confirmedPurchasedIDs,
            substitutions: validSubstitutions,
            pantryItemIDs: touchedPantryIDs,
            committedAt: .now
        )

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
            recipeID: activeRecipe.id,
            storeID: primaryStore.retailerStoreID,
            items: shoppingItems
        )
        if let existing = shoppingSessions.first(where: {
            guard $0.recipeID == activeRecipe.id else { return false }
            let existingFingerprint = $0.stateFingerprint ?? shoppingSessionFingerprint(
                recipeID: $0.recipeID,
                storeID: $0.storeID,
                items: $0.items
            )
            return existingFingerprint == currentFingerprint
        }) {
            return existing.id
        }

        let session = ShoppingSession(
            recipeID: activeRecipe.id,
            recipeTitle: activeRecipe.title,
            manifestID: currentSavedManifest?.id,
            storeID: primaryStore.retailerStoreID,
            items: shoppingItems,
            stateFingerprint: currentFingerprint
        )
        var updatedSessions = shoppingSessions
        updatedSessions.insert(session, at: 0)
        try stateStore.save(stateSnapshot(shoppingSessions: updatedSessions))
        suppressPersistence = true
        shoppingSessions = updatedSessions
        suppressPersistence = false
        persistenceIssue = nil
        return session.id
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
        let retailerProductID = substitution?.replacementRetailerProductID
            ?? (product.linkKind == .exactProduct ? product.retailerProductID : nil)
        let scopedRetailerProductID = retailerProductID.map {
            "\(product.retailerID):\($0)"
        }
        let gtin14 = normalizedGTIN14(substitution?.replacementGTIN14 ?? product.gtin)
        let packageQuantity = substitution?.packageQuantity ?? product.packageQuantity
        let packageUnit = substitution?.packageUnit ?? product.packageUnit
        let amount = max(0.01, substitution?.replacementAmount ?? Double(max(1, item.purchaseQuantity)))

        let matchIndex = inventory.firstIndex { existing in
            if let gtin14 {
                let identities = Set((existing.barcodeGTINs ?? []) + [existing.gtin14].compactMap { $0 })
                if identities.contains(gtin14) { return true }
            }
            if let scopedRetailerProductID {
                if existing.preferredRetailerProductID == scopedRetailerProductID {
                    return true
                }
                if product.retailerID == ShoppingRetailer.walmart.rawValue,
                   existing.preferredRetailerProductID == retailerProductID {
                    return true
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
            barcodeGTINs: gtin14.map { [$0] }
        )
        inventory.insert(pantryItem, at: 0)
        return pantryItem.id
    }

    private func shoppingSessionFingerprint(
        recipeID: UUID,
        storeID: String,
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
                    item.product.packageQuantity?.formatted() ?? "",
                    item.product.packageUnit ?? "",
                    item.status.rawValue
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
        let canonical = "\(recipeID.uuidString)|\(storeID)\n\(itemState)"

        // Swift's Hasher is intentionally randomized between launches. FNV-1a
        // keeps this local identity stable without introducing account data.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in canonical.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
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
        if let index = pantryInventory.firstIndex(where: { item in
            if let normalizedBarcode {
                return item.matches(barcode: normalizedBarcode)
            }
            return item.upc == normalizedUPC
        }) {
            pantryInventory[index].addPackages(1)
            pantryInventory[index].updatedAt = .now
            if let normalizedBarcode {
                pantryInventory[index].register(
                    barcode: normalizedBarcode,
                    rawValue: upc,
                    symbology: nil
                )
            }
        } else {
            pantryInventory.insert(
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
        track(.barcodeScanned, properties: ["matched": record == nil ? "false" : "true"])
        track(.pantryItemAdded, properties: ["source": PantryItemSource.barcode.rawValue])
        showToast(record == nil ? "UPC saved for later matching" : "\(record!.name) added to pantry")
        refreshPantrySuggestions()
    }

    func addPantryItem(
        submission: PantryBarcodeSubmission,
        duplicateAction: BarcodeDuplicateResolutionAction = .increment
    ) {
        if let index = pantryInventory.firstIndex(where: { $0.matches(barcode: submission.barcode) }) {
            switch duplicateAction {
            case .increment:
                pantryInventory[index].addPackages(1)
                pantryInventory[index].updatedAt = .now
                pantryInventory[index].register(
                    barcode: submission.barcode,
                    rawValue: submission.scan.rawBarcode,
                    symbology: submission.scan.rawSymbology
                )
            case .replace:
                let existingQuantity = pantryInventory[index].packageCount
                let knownBarcodes = pantryInventory[index].barcodeGTINs ?? []
                pantryInventory[index] = pantryItem(from: submission, quantity: existingQuantity)
                pantryInventory[index].barcodeGTINs = Array(
                    Set(knownBarcodes + [submission.barcode.canonicalGTIN14])
                ).sorted()
            case .cancel:
                return
            }
        } else {
            pantryInventory.insert(pantryItem(from: submission), at: 0)
        }
        track(.barcodeScanned, properties: ["matched": submission.requiresUserNaming ? "false" : "true"])
        track(.pantryItemAdded, properties: ["source": PantryItemSource.barcode.rawValue])
        showToast(submission.requiresUserNaming ? "Barcode saved — product name required" : "\(submission.name) added to pantry")
        refreshPantrySuggestions()
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
        pantryInventory.insert(PantryInventoryItem(name: trimmed, source: .manual), at: 0)
        track(.pantryItemAdded, properties: ["source": PantryItemSource.manual.rawValue])
        refreshPantrySuggestions()
    }

    func updatePantryItem(_ item: PantryInventoryItem) {
        guard let index = pantryInventory.firstIndex(where: { $0.id == item.id }) else { return }
        pantryInventory[index] = item
        pantryInventory[index].updatedAt = .now
        refreshPantrySuggestions()
    }

    func removePantryItems(at offsets: IndexSet) {
        pantryInventory.remove(atOffsets: offsets)
        refreshPantrySuggestions()
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

        if let existing = pantryMergeTarget(named: trimmed, submission: submission),
           let index = pantryInventory.firstIndex(where: { $0.id == existing.id }) {
            pantryInventory[index].addPackages(amount)
            pantryInventory[index].updatedAt = .now
            if let submission {
                pantryInventory[index].register(
                    barcode: submission.barcode,
                    rawValue: submission.scan.rawBarcode,
                    symbology: submission.scan.rawSymbology
                )
                if pantryInventory[index].requiresUserNaming == true {
                    pantryInventory[index].name = trimmed
                    pantryInventory[index].requiresUserNaming = false
                }
            }
            showToast("Added \(amount.formatted()) to \(pantryInventory[index].name)")
        } else {
            pantryInventory.insert(
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
            showToast("\(trimmed) added to pantry")
        }

        if submission != nil {
            track(.barcodeScanned, properties: ["matched": "named"])
        }
        track(.pantryItemAdded, properties: [
            "source": (submission == nil ? PantryItemSource.manual : PantryItemSource.barcode).rawValue
        ])
        refreshPantrySuggestions()
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
        savedLists.first {
            $0.manifest.recipeID == activeRecipe.id &&
            $0.manifest.retailerID == selectedRetailer.rawValue &&
            $0.manifest.storeID == primaryStore.retailerStoreID
        }?.manifest
    }

    private func persistCurrentManifest(progress: ManifestHandoffProgress) {
        let existingIndex = savedLists.firstIndex {
            $0.manifest.recipeID == activeRecipe.id &&
            $0.manifest.retailerID == selectedRetailer.rawValue &&
            $0.manifest.storeID == primaryStore.retailerStoreID
        }
        let existing = existingIndex.map { savedLists[$0].manifest }
        let manifest = ShoppingManifest(
            id: existing?.id ?? UUID(),
            recipeID: activeRecipe.id,
            recipeTitle: activeRecipe.title,
            retailerID: primaryStore.retailerID,
            storeID: primaryStore.retailerStoreID,
            storeName: primaryStore.name,
            desiredServings: desiredServings,
            fulfillmentMode: fulfillmentMode,
            items: shoppingItems.map {
                ManifestLineItem(
                    ingredientID: $0.ingredient.id,
                    ingredientName: $0.ingredient.name,
                    requestedQuantity: $0.requestedQuantity,
                    purchaseQuantity: $0.purchaseQuantity,
                    product: $0.product,
                    status: $0.status
                )
            },
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now,
            handoffProgress: progress
        )

        if let existingIndex {
            savedLists.remove(at: existingIndex)
        }
        savedLists.insert(SavedShoppingList(manifest: manifest), at: 0)
    }

    private func buildShoppingItems() async -> [ShoppingListItem] {
        let multiplier = Double(desiredServings) / Double(max(1, activeRecipe.servings))
        let method: FulfillmentMethod = fulfillmentMode == .pickup ? .pickup : .delivery
        let store = primaryStore
        var results: [ShoppingListItem] = []

        for ingredient in ingredientsToBuy {
            let requestedQuantity = PantryMatchingService.quantityToBuy(
                for: ingredient,
                requiredQuantity: ingredient.quantity * multiplier
            )
            let request = RetailerProductSearchRequest(
                ingredient: ingredient,
                retailerID: selectedRetailer.rawValue,
                requestedQuantity: requestedQuantity,
                requestedUnit: ingredient.unit,
                storeID: store.retailerStoreID,
                fulfillmentMethod: method
            )
            var ranked = await retailerEngine.rankedProducts(
                for: request,
                preferences: preferences
            )
            let retailerPreferenceKey = productPreferenceKey(
                for: ingredient.name,
                retailerID: selectedRetailer.rawValue
            )
            let legacyWalmartPreference = selectedRetailer == .walmart
                ? preferredProductIDsByIngredient[preferenceKey(for: ingredient.name)]
                : nil
            if let preferredID = preferredProductIDsByIngredient[retailerPreferenceKey] ?? legacyWalmartPreference,
               let preferredIndex = ranked.firstIndex(where: { $0.product.retailerProductID == preferredID }) {
                let preferred = ranked.remove(at: preferredIndex)
                ranked.insert(preferred, at: 0)
            }
            guard let selected = ranked.first else { continue }

            results.append(
                ShoppingListItem(
                    ingredient: ingredient,
                    requestedQuantity: Ingredient.quantityText(
                        requestedQuantity,
                        unit: ingredient.unit
                    ),
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
            )
        }
        return results
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
                ingredient: ingredient,
                requestedQuantity: Ingredient.quantityText(
                    requestedQuantity,
                    unit: ingredient.unit
                ),
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
            shoppingSessions: sessionOverride ?? shoppingSessions
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

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            "That shopping session is no longer available. Start from the current shopping guide."
        case .emptyShoppingList:
            "There are no shopping items to reconcile."
        case .persistenceUnavailable(let message):
            "SmartCart cannot safely update the pantry: \(message)"
        }
    }
}

enum RecipeParser {
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
        for line in lines.prefix(120) {
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

            if isLikelyInstruction(line) {
                if !ingredients.isEmpty { break }
                continue
            }
            guard isLikelyIngredient(line, contextAllowsQuantitylessLine: contextAllowsQuantitylessLine),
                  ingredients.count < 60
            else { continue }
            var ingredient = parseIngredient(line, source: source)
            if let sourceIndex {
                let sourceLine = remainingSourceLines.remove(at: sourceIndex)
                apply(sourceLine: sourceLine, to: &ingredient, source: source)
            }
            ingredient.sectionName = sectionName
            ingredients.append(ingredient)
        }

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
            "freeze", "serve", "let", "set", "line", "grease", "melt", "bring"
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
            if isLikelyInstruction(line) {
                if count > 0 { break }
                continue
            }
            if isLikelyIngredient(line, contextAllowsQuantitylessLine: isInsideIngredientSection) {
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
        let preparationPattern = #"(?i)\b(optional|if desired|as desired|as needed|divided|softened|melted|sifted|packed|room temperature|at room temperature|chopped|roughly chopped|finely chopped|minced|drained|rinsed|cubed|diced|peeled|seeded|zested|juiced|crushed|grated|shredded|plus more[^,]*|for serving|for garnish|to taste)\b"#
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
            ? #"(?i)\b(optional|if desired|as desired|as needed|divided|plus more[^,]*|for serving|for garnish|to taste)\b"#
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
