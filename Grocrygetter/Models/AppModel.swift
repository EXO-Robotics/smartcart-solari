import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .home
    var homePath: [SmartRoute] = []
    var presentedSheet: SheetDestination?

    var activeRecipe: Recipe
    var recipes: [Recipe]
    var desiredServings: Int

    var storeStrategy: StoreStrategy = .oneStore
    var fulfillmentMode: FulfillmentMode = .pickup
    var selectedStoreIDs: Set<UUID>
    var zipCode = "90210"
    var pickupDay = "Today"
    var pickupTime = "4:30–5:30 PM"

    var shoppingItems: [ShoppingListItem] = []
    var matchProgress = 0.0
    var matchStage = "Ready to match"
    var isMatching = false
    var guidedIndex = 0

    var savedLists: [SavedShoppingList] = []
    var linkedDeliveryPartnerName: String?
    var toastMessage: String?

    let stores: [RetailerStore]
    let deliveryPartners: [DeliveryPartner]

    init() {
        let availableStores = [
            RetailerStore(
                name: "Walmart Supercenter A",
                format: "Supercenter",
                address: "6433 Fallbrook Ave, West Hills",
                distance: 2.3,
                pickupWindow: "Today, 4:30–5:30 PM"
            ),
            RetailerStore(
                name: "Walmart Supercenter B",
                format: "Supercenter",
                address: "19821 Rinaldi St, Porter Ranch",
                distance: 6.1,
                pickupWindow: "Today, 5:00–6:00 PM",
                supportsDelivery: false
            ),
            RetailerStore(
                name: "Walmart Neighborhood Market",
                format: "Neighborhood Market",
                address: "14441 Inglewood Ave, Hawthorne",
                distance: 8.0,
                pickupWindow: "Tomorrow, 9:00–10:00 AM"
            )
        ]
        stores = availableStores
        selectedStoreIDs = [availableStores[0].id]

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
        recipes = sampleRecipes
        activeRecipe = sampleRecipes[0]
        desiredServings = sampleRecipes[0].servings

        // Give the simulator a complete, useful first-run surface.
        shoppingItems = Self.makeShoppingItems(
            recipe: sampleRecipes[0],
            desiredServings: sampleRecipes[0].servings,
            stores: [availableStores[0]]
        )

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
        stores.filter { selectedStoreIDs.contains($0.id) }
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
        shoppingItems.filter { $0.product.confidence == .high }.count
    }

    var lowConfidenceItemCount: Int {
        shoppingItems.filter { $0.product.confidence != .high }.count
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

    var shareText: String {
        var lines = [
            "SmartCart · \(activeRecipe.title)",
            "\(shoppingItems.count) products at \(primaryStore.name)",
            "Estimated product total: \(estimatedTotal.formatted(.currency(code: "USD")))",
            ""
        ]

        lines += shoppingItems.map {
            "• \($0.product.brand) \($0.product.name), \($0.product.package) — \($0.lineTotal.formatted(.currency(code: "USD")))"
        }

        lines += [
            "",
            "Prices and availability may change. Tax, fees, tips, substitutions, and variable-weight adjustments are finalized by Walmart."
        ]
        return lines.joined(separator: "\n")
    }

    func openImporter(_ method: ImportMethod) {
        presentedSheet = .importer(method)
    }

    func beginRecipe(_ recipe: Recipe) {
        activeRecipe = recipe
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
        storeStrategy = strategy
        if strategy == .oneStore {
            selectedStoreIDs = [primaryStore.id]
        } else if selectedStoreIDs.count == 1, let second = stores.first(where: { !selectedStoreIDs.contains($0.id) }) {
            selectedStoreIDs.insert(second.id)
        }
    }

    func selectStore(_ store: RetailerStore) {
        if storeStrategy == .oneStore {
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
            ("Searching selected Walmart stores", 0.18),
            ("Checking package sizes", 0.38),
            ("Comparing prices", 0.58),
            ("Applying pantry and brand preferences", 0.78),
            ("Building your shopping list", 0.94)
        ]

        for (stage, progress) in stages {
            matchStage = stage
            withAnimation(.easeInOut(duration: 0.28)) {
                matchProgress = progress
            }
            try? await Task.sleep(for: .milliseconds(330))
        }

        shoppingItems = Self.makeShoppingItems(
            recipe: activeRecipe,
            desiredServings: desiredServings,
            stores: selectedStores.isEmpty ? [stores[0]] : selectedStores
        )
        withAnimation(.easeOut(duration: 0.35)) {
            matchProgress = 1
        }
        matchStage = "\(shoppingItems.count) products ready"
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
    }

    func advanceGuidedItem() {
        guard !shoppingItems.isEmpty else { return }
        if guidedIndex < shoppingItems.count - 1 {
            guidedIndex += 1
        } else {
            showToast("Guided shopping complete")
        }
    }

    func moveGuidedItem(by delta: Int) {
        guard !shoppingItems.isEmpty else { return }
        guidedIndex = min(shoppingItems.count - 1, max(0, guidedIndex + delta))
    }

    func saveCurrentList() {
        let saved = SavedShoppingList(
            recipeTitle: activeRecipe.title,
            storeName: storeStrategy == .oneStore ? primaryStore.name : "\(selectedStores.count) Walmart stops",
            itemCount: shoppingItems.count,
            total: estimatedTotal
        )
        savedLists.insert(saved, at: 0)
        showToast("Shopping list saved")
    }

    func linkDeliveryPartner(_ partner: DeliveryPartner) {
        linkedDeliveryPartnerName = partner.name
        fulfillmentMode = .delivery
        showToast("\(partner.name) selected for handoff")
    }

    func store(for id: UUID) -> RetailerStore {
        stores.first(where: { $0.id == id }) ?? stores[0]
    }

    func productURL(for item: ShoppingListItem) -> URL {
        let query = "\(item.product.brand) \(item.product.name) \(item.product.package)"
        var components = URLComponents(string: "https://www.walmart.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
    }

    func retailerURL() -> URL {
        URL(string: "https://www.walmart.com/cp/grocery-pickup-and-delivery/9524000")!
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

    private static func makeShoppingItems(
        recipe: Recipe,
        desiredServings: Int,
        stores: [RetailerStore]
    ) -> [ShoppingListItem] {
        let multiplier = Double(desiredServings) / Double(max(1, recipe.servings))
        let eligible = recipe.ingredients.filter {
            $0.includeInList &&
            $0.pantryState != .haveEnough &&
            $0.pantryState != .exclude
        }

        return eligible.enumerated().map { index, ingredient in
            let candidates = ProductCatalog.candidates(for: ingredient)
            let requestedQuantity = Ingredient.quantityText(
                ingredient.quantity * multiplier,
                unit: ingredient.unit
            )
            let purchaseQuantity = ProductCatalog.packageCount(
                for: ingredient,
                scaledQuantity: ingredient.quantity * multiplier
            )
            let store = stores[index % max(stores.count, 1)]

            return ShoppingListItem(
                ingredient: ingredient,
                requestedQuantity: requestedQuantity,
                purchaseQuantity: purchaseQuantity,
                product: candidates[0],
                alternatives: Array(candidates.dropFirst()),
                storeID: store.id
            )
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

private enum ProductCatalog {
    static func candidates(for ingredient: Ingredient) -> [ProductCandidate] {
        let value = ingredient.name.lowercased()

        if value.contains("chicken") {
            return [
                candidate("Great Value", "Boneless Skinless Chicken Breasts", "3 lb", 10.94, "$3.65/lb", "fork.knife", variable: true),
                candidate("Perdue", "Fresh Chicken Breast Tenderloins", "1.5 lb", 8.47, "$5.65/lb", "fork.knife", variable: true),
                candidate("Tyson", "All Natural Chicken Breasts", "2.5 lb", 11.82, "$4.73/lb", "fork.knife", variable: true)
            ]
        }
        if value.contains("pasta") || value.contains("rigatoni") || value.contains("penne") || value.contains("spaghetti") {
            return [
                candidate("Great Value", "Penne Pasta", "16 oz", 1.28, "8¢/oz", "takeoutbag.and.cup.and.straw.fill"),
                candidate("Barilla", "Penne Pasta", "16 oz", 1.84, "12¢/oz", "takeoutbag.and.cup.and.straw.fill"),
                candidate("Rao's", "Penne Rigate", "16 oz", 2.98, "19¢/oz", "takeoutbag.and.cup.and.straw.fill")
            ]
        }
        if value.contains("olive oil") {
            return [
                candidate("Great Value", "Extra Virgin Olive Oil", "17 fl oz", 6.97, "41¢/fl oz", "waterbottle.fill"),
                candidate("Bertolli", "Extra Virgin Olive Oil", "16.9 fl oz", 9.48, "56¢/fl oz", "waterbottle.fill"),
                candidate("Pompeian", "Smooth Extra Virgin Olive Oil", "16 fl oz", 8.96, "56¢/fl oz", "waterbottle.fill")
            ]
        }
        if value.contains("parmesan") {
            return [
                candidate("Great Value", "Shredded Parmesan Cheese", "6 oz", 2.22, "37¢/oz", "waterbottle.fill"),
                candidate("Kraft", "Shredded Parmesan Cheese", "7 oz", 3.48, "50¢/oz", "waterbottle.fill"),
                candidate("BelGioioso", "Freshly Shredded Parmesan", "5 oz", 4.12, "82¢/oz", "waterbottle.fill")
            ]
        }
        if value.contains("cream") {
            return [
                candidate("Great Value", "Heavy Whipping Cream", "16 fl oz", 2.87, "18¢/fl oz", "waterbottle.fill"),
                candidate("Horizon Organic", "Heavy Whipping Cream", "16 fl oz", 5.44, "34¢/fl oz", "waterbottle.fill"),
                candidate("Land O Lakes", "Heavy Whipping Cream", "16 fl oz", 4.38, "27¢/fl oz", "waterbottle.fill")
            ]
        }
        if value.contains("garlic") {
            return [
                candidate("Fresh", "Garlic Bulbs", "3 count", 0.78, "26¢/ea", "leaf.fill"),
                candidate("Spice World", "Fresh Peeled Garlic", "6 oz", 3.97, "66¢/oz", "leaf.fill"),
                candidate("Great Value", "Minced Garlic", "8 oz", 2.48, "31¢/oz", "leaf.fill")
            ]
        }
        if value.contains("lemon") || value.contains("lime") {
            return [
                candidate("Fresh", value.contains("lime") ? "Limes" : "Lemons", "2 lb bag", 3.97, "$1.99/lb", "leaf.fill", variable: true),
                candidate("Fresh", value.contains("lime") ? "Lime" : "Lemon", "each", 0.68, "68¢/ea", "leaf.fill", variable: true),
                candidate("ReaLemon", "100% Lemon Juice", "15 fl oz", 2.14, "14¢/fl oz", "waterbottle.fill", confidence: .review)
            ]
        }
        if value.contains("parsley") || value.contains("cilantro") {
            return [
                candidate("Fresh", ingredient.name, "1 bunch", 0.98, "98¢/ea", "leaf.fill", variable: true),
                candidate("Organic", ingredient.name, "1 bunch", 1.78, "$1.78/ea", "leaf.fill", variable: true),
                candidate("Litehouse", "Freeze Dried Herbs", "0.35 oz", 4.98, "$14.23/oz", "leaf.fill", confidence: .review)
            ]
        }

        let basePrice: Double = switch ingredient.category {
        case .produce: 2.48
        case .dairy: 3.87
        case .meat: 8.96
        case .bakery: 3.24
        case .pantry: 2.72
        case .frozen: 4.98
        }
        let symbol = ingredient.category.symbol
        return [
            candidate("Great Value", ingredient.name, "standard size", basePrice, "Best value", symbol, confidence: ingredient.confidence),
            candidate("Marketside", ingredient.name, "family size", basePrice + 1.26, "Family size", symbol, confidence: .review),
            candidate("Organic", ingredient.name, "standard size", basePrice + 2.11, "Organic option", symbol, confidence: .review)
        ]
    }

    static func packageCount(for ingredient: Ingredient, scaledQuantity: Double) -> Int {
        let value = ingredient.name.lowercased()
        if value.contains("chicken"), ingredient.unit == "lb" {
            return max(1, Int(ceil(scaledQuantity / 3)))
        }
        if value.contains("pasta") && (ingredient.unit == "oz") {
            return max(1, Int(ceil(scaledQuantity / 16)))
        }
        return 1
    }

    private static func candidate(
        _ brand: String,
        _ name: String,
        _ package: String,
        _ price: Double,
        _ unitPrice: String,
        _ symbol: String,
        confidence: IngredientConfidence = .high,
        variable: Bool = false
    ) -> ProductCandidate {
        ProductCandidate(
            brand: brand,
            name: name,
            package: package,
            price: price,
            unitPrice: unitPrice,
            symbol: symbol,
            confidence: confidence,
            variableWeight: variable
        )
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
