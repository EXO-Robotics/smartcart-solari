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
    var toastMessage: String?
    private(set) var persistenceIssue: String?

    let stores: [RetailerStore]
    let deliveryPartners: [DeliveryPartner]

    @ObservationIgnored
    private let stateStore: any SmartCartStateStoring
    @ObservationIgnored
    private let retailerService: any RetailerCatalogService
    @ObservationIgnored
    private var persistenceReady = false

    init(
        stateStore: any SmartCartStateStoring = JSONSmartCartStateStore(),
        retailerService: any RetailerCatalogService = DemoWalmartCatalogService()
    ) {
        self.stateStore = stateStore
        self.retailerService = retailerService

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
        let restoredState = try? stateStore.load()
        let initialRecipes = restoredState?.recipes ?? sampleRecipes
        let initialRecipe = restoredState?.activeRecipe ?? sampleRecipes[0]
        let initialServings = restoredState?.desiredServings ?? sampleRecipes[0].servings
        let initialPreferences = restoredState?.preferences ?? ShoppingPreferences()
        let initialFeatureFlags = restoredState?.featureFlags ?? AppFeatureFlags()
        let initialStoreStrategy = restoredState?.storeStrategy ?? StoreStrategy.oneStore
        let initialFulfillment = restoredState?.fulfillmentMode ?? FulfillmentMode.pickup

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

        let validStoreIDs = Set(availableStores.map(\.id))
        let restoredStoreIDs = restoredState?.selectedStoreIDs.intersection(validStoreIDs) ?? []
        selectedStoreIDs = restoredStoreIDs.isEmpty ? [availableStores[0].id] : restoredStoreIDs

        if let restoredItems = restoredState?.shoppingItems, !restoredItems.isEmpty {
            shoppingItems = restoredItems
        } else {
            shoppingItems = Self.makeShoppingItems(
                recipe: initialRecipe,
                desiredServings: initialServings,
                store: availableStores[0],
                fulfillmentMode: initialFulfillment,
                preferences: initialPreferences
            )
        }

        if !featureFlags.advancedToolsEnabled {
            storeStrategy = .oneStore
            fulfillmentMode = .pickup
            selectedStoreIDs = [selectedStoreIDs.first ?? availableStores[0].id]
        }
        guidedIndex = min(max(0, guidedIndex), max(0, shoppingItems.count - 1))
        persistenceReady = true
        persistState()

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
            case "import":
                presentedSheet = .importer(.sample)
            default:
                break
            }
        }
        #endif
    }

    var selectedStores: [RetailerStore] {
        let selected = stores.filter { selectedStoreIDs.contains($0.id) }
        if featureFlags.advancedToolsEnabled, storeStrategy == .multipleStops {
            return selected
        }
        return Array(selected.prefix(1))
    }

    var primaryStore: RetailerStore {
        selectedStores.first ?? stores[0]
    }

    var includedIngredientCount: Int {
        activeRecipe.ingredients.filter(\.includeInList).count
    }

    var ingredientsToBuy: [Ingredient] {
        activeRecipe.ingredients.filter {
            $0.includeInList &&
            $0.pantryState != .haveEnough &&
            $0.pantryState != .exclude
        }
    }

    var pantrySkipCount: Int {
        activeRecipe.ingredients.filter {
            !$0.includeInList || $0.pantryState == .haveEnough || $0.pantryState == .exclude
        }.count
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
        shoppingItems.filter { $0.status != .waiting }.count
    }

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
        retailerService.capabilities
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
        presentedSheet = .importer(method)
    }

    func beginRecipe(_ recipe: Recipe) {
        activeRecipe = recipe
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }
        desiredServings = recipe.servings
        shoppingItems = []
        matchProgress = 0
        matchStage = "Ready to match"
        isMatching = false
        guidedIndex = 0
        selectedTab = .home
        presentedSheet = nil
        homePath = [.ingredientReview]
    }

    func scaledQuantity(for ingredient: Ingredient) -> Double {
        guard activeRecipe.servings > 0 else { return ingredient.quantity }
        return ingredient.quantity * Double(desiredServings) / Double(activeRecipe.servings)
    }

    func scaledQuantityText(for ingredient: Ingredient) -> String {
        Ingredient.quantityText(scaledQuantity(for: ingredient), unit: ingredient.unit)
    }

    func updateServings(by delta: Int) {
        desiredServings = min(24, max(1, desiredServings + delta))
    }

    func continueTo(_ route: SmartRoute) {
        homePath.append(route)
    }

    func setStoreStrategy(_ strategy: StoreStrategy) {
        guard featureFlags.advancedToolsEnabled || strategy == .oneStore else {
            storeStrategy = .oneStore
            showToast("Multiple-stop planning is an experimental advanced tool")
            return
        }

        storeStrategy = strategy
        if storeStrategy == .oneStore {
            selectedStoreIDs = [primaryStore.id]
        } else if selectedStoreIDs.count == 1, let second = stores.first(where: { !selectedStoreIDs.contains($0.id) }) {
            selectedStoreIDs.insert(second.id)
        }
    }

    func selectStore(_ store: RetailerStore) {
        if storeStrategy == .oneStore || !featureFlags.advancedToolsEnabled {
            selectedStoreIDs = [store.id]
        } else if selectedStoreIDs.contains(store.id) {
            guard selectedStoreIDs.count > 1 else {
                showToast("Keep at least one stop selected")
                return
            }
            selectedStoreIDs.remove(store.id)
        } else {
            selectedStoreIDs.insert(store.id)
        }
    }

    func setAdvancedToolsEnabled(_ enabled: Bool) {
        featureFlags.advancedToolsEnabled = enabled
        guard !enabled else { return }
        storeStrategy = .oneStore
        fulfillmentMode = .pickup
        selectedStoreIDs = [primaryStore.id]
    }

    func startMatching(force: Bool = false) async {
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
        showToast("Product replacement selected")
    }

    func markCurrentGuidedItem(_ status: GuidedItemStatus) {
        guard shoppingItems.indices.contains(guidedIndex) else { return }
        shoppingItems[guidedIndex].status = status
        persistCurrentManifest(progress: .inProgress)
    }

    func advanceGuidedItem() {
        guard !shoppingItems.isEmpty else { return }
        if guidedIndex < shoppingItems.count - 1 {
            guidedIndex += 1
        } else {
            persistCurrentManifest(progress: .completed)
            showToast("Guided shopping complete")
        }
    }

    func moveGuidedItem(by delta: Int) {
        guard !shoppingItems.isEmpty else { return }
        guidedIndex = min(shoppingItems.count - 1, max(0, guidedIndex + delta))
    }

    func saveCurrentList() {
        persistCurrentManifest(progress: .notStarted)
        showToast("Shopping manifest saved")
    }

    func beginGuidedShopping() {
        guidedIndex = 0
        persistCurrentManifest(progress: .inProgress)
        continueTo(.guidedShopping)
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
        item.product.isExactProductLink ? "Open exact product" : "Search at Walmart"
    }

    func retailerURL() -> URL {
        URL(string: "https://www.walmart.com/cp/grocery-pickup-and-delivery/9524000")!
    }

    func prepareRetailerHandoff() async -> RetailerHandoff? {
        persistCurrentManifest(progress: .inProgress)
        guard let manifest = currentSavedManifest else { return nil }
        do {
            return try await retailerService.createHandoff(manifest: manifest)
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

    private var currentSavedManifest: ShoppingManifest? {
        savedLists.first {
            $0.manifest.recipeID == activeRecipe.id &&
            $0.manifest.storeID == primaryStore.retailerStoreID
        }?.manifest
    }

    private func persistCurrentManifest(progress: ManifestHandoffProgress) {
        let existingIndex = savedLists.firstIndex {
            $0.manifest.recipeID == activeRecipe.id &&
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
            let requestedQuantity = ingredient.quantity * multiplier
            let request = RetailerProductSearchRequest(
                ingredient: ingredient,
                requestedQuantity: requestedQuantity,
                requestedUnit: ingredient.unit,
                storeID: store.retailerStoreID,
                fulfillmentMethod: method
            )
            let candidates = (try? await retailerService.searchProducts(for: request)) ?? []
            var ranked = RetailerProductMatcher.rank(
                candidates,
                for: request,
                preferences: preferences
            )
            if ranked.isEmpty {
                let fallback = DemoWalmartCatalogService.searchFallback(
                    for: ingredient,
                    storeID: store.retailerStoreID,
                    preferences: preferences
                )
                ranked = RetailerProductMatcher.rank(
                    [fallback],
                    for: request,
                    preferences: preferences
                )
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
        guard persistenceReady else { return }
        do {
            try stateStore.save(
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
                    preferredDeliveryPartnerName: preferredDeliveryPartnerName
                )
            )
            persistenceIssue = nil
        } catch {
            persistenceIssue = error.localizedDescription
        }
    }
}

enum RecipeParser {
    static func parse(
        title: String,
        text: String,
        source: RecipeSource = .text,
        sourceDetail: String = "Pasted into SmartCart"
    ) -> Recipe {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let ingredientLines = lines
            .filter(isLikelyIngredient)
            .prefix(30)

        let ingredients = ingredientLines.map(parseIngredient)
        let fallback = [
            Ingredient(name: "Yellow onion", category: .produce, confidence: .review),
            Ingredient(name: "Garlic", quantity: 3, unit: "cloves", category: .produce),
            Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp", category: .pantry, pantryState: .runningLow)
        ]

        return Recipe(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? inferredTitle(from: lines) : title,
            source: source,
            sourceDetail: sourceDetail,
            heroSymbol: heroSymbol(for: title + " " + text),
            servings: inferredServings(from: text),
            prepMinutes: 15,
            cookMinutes: inferredCookTime(from: text),
            ingredients: ingredients.isEmpty ? fallback : Array(ingredients)
        )
    }

    private static func isLikelyIngredient(_ line: String) -> Bool {
        let value = line.lowercased()
        let instructionPrefixes = [
            "step ", "directions", "instructions", "method", "preheat", "bake ",
            "cook ", "stir ", "serve ", "heat ", "add the", "mix "
        ]
        guard !instructionPrefixes.contains(where: value.hasPrefix) else { return false }
        if value.contains("minute") && !value.contains("to taste") { return false }
        if line.range(of: #"\d|[¼½¾⅓⅔⅛]"#, options: .regularExpression) != nil { return true }
        return ["salt", "pepper", "oil", "parsley", "cilantro", "water"].contains {
            value.hasPrefix($0) || value.contains(" \($0)")
        }
    }

    private static func parseIngredient(_ line: String) -> Ingredient {
        let isOptional = line.range(
            of: #"\boptional\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        var cleaned = line
            .replacingOccurrences(of: #"^[-•*☐✓]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "½", with: "1/2")
            .replacingOccurrences(of: "¼", with: "1/4")
            .replacingOccurrences(of: "¾", with: "3/4")
            .replacingOccurrences(of: "⅓", with: "1/3")
            .replacingOccurrences(of: "⅔", with: "2/3")
            .replacingOccurrences(of: "⅛", with: "1/8")
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let tokens = cleaned.split(separator: " ").map(String.init)
        var consumed = 0
        var quantity = 1.0
        var foundQuantity = false

        if let first = tokens.first, let firstValue = parseQuantity(first) {
            quantity = firstValue
            consumed = 1
            foundQuantity = true
            if tokens.count > 1, let fraction = parseFraction(tokens[1]), !tokens[1].contains("-") {
                quantity += fraction
                consumed = 2
            }
        }

        let knownUnits = [
            "cup", "cups", "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons",
            "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "g", "kg", "ml", "l",
            "clove", "cloves", "can", "cans", "jar", "jars", "bag", "bags", "bunch",
            "bunches", "package", "packages", "pkg", "pinch", "slice", "slices"
        ]
        var unit = ""
        if tokens.indices.contains(consumed) {
            let candidate = tokens[consumed].lowercased().trimmingCharacters(in: .punctuationCharacters)
            if knownUnits.contains(candidate) {
                unit = normalizedUnit(candidate)
                consumed += 1
            }
        }

        let remaining = tokens.dropFirst(consumed).joined(separator: " ")
        let commaParts = remaining.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let rawName = commaParts.first ?? remaining
        let name = rawName
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
        let preparation = commaParts.count > 1 ? commaParts[1] : ""
        let normalizedName = name.isEmpty ? cleaned : name
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

        return Ingredient(
            rawText: line,
            name: normalizedName.capitalized,
            quantity: quantity,
            unit: unit,
            preparation: preparation,
            category: category,
            confidence: foundQuantity && !normalizedName.isEmpty ? .high : .review,
            includeInList: !isOptional,
            pantryState: pantryState
        )
    }

    private static func parseQuantity(_ value: String) -> Double? {
        let cleaned = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "~≈+,"))
            .split(separator: "-")
            .first
            .map(String.init) ?? value
        return parseFraction(cleaned) ?? Double(cleaned)
    }

    private static func parseFraction(_ value: String) -> Double? {
        let parts = value.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return nil }
        return parts[0] / parts[1]
    }

    private static func normalizedUnit(_ unit: String) -> String {
        switch unit {
        case "tablespoon", "tablespoons": "tbsp"
        case "teaspoon", "teaspoons": "tsp"
        case "ounce", "ounces": "oz"
        case "pound", "pounds", "lbs": "lb"
        case "packages", "package": "pkg"
        default: unit
        }
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

enum RecipeLinkImporter {
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
