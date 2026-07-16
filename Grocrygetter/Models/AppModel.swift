import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .plan
    var presentedSheet: SheetDestination?
    var storeStrategy: StoreStrategy = .smartSplit
    var fulfillmentMode: FulfillmentMode = .pickup
    var selectedStoreIDs: Set<UUID> = []
    var recipes: [Recipe] = []
    var cartItems: [CartItem] = []
    var reservations: [PickupReservation] = []
    var connectedPartnerName: String?
    var toastMessage: String?

    let stores: [GroceryStore]
    let deliveryPartners: [DeliveryPartner]

    init() {
        let freshMarket = GroceryStore(
            name: "Fresh Market",
            shortName: "Fresh",
            distance: 1.2,
            color: Color(red: 0.16, green: 0.43, blue: 0.27),
            symbol: "leaf.fill",
            pickupFee: 0,
            nextPickup: "Today, 5:30 PM"
        )
        let target = GroceryStore(
            name: "Target",
            shortName: "Target",
            distance: 2.4,
            color: Color(red: 0.80, green: 0.12, blue: 0.14),
            symbol: "scope",
            pickupFee: 0,
            nextPickup: "Today, 6:00 PM"
        )
        let wholeFoods = GroceryStore(
            name: "Whole Foods",
            shortName: "Whole",
            distance: 3.1,
            color: Color(red: 0.08, green: 0.38, blue: 0.20),
            symbol: "apple.logo",
            pickupFee: 1.99,
            nextPickup: "Tomorrow, 9:00 AM"
        )

        stores = [freshMarket, target, wholeFoods]
        selectedStoreIDs = [freshMarket.id, target.id]

        deliveryPartners = [
            DeliveryPartner(
                name: "Instacart",
                symbol: "carrot.fill",
                color: Color(red: 0.25, green: 0.64, blue: 0.19),
                status: "Link account",
                url: URL(string: "https://www.instacart.com")
            ),
            DeliveryPartner(
                name: "DoorDash",
                symbol: "bag.fill",
                color: Color(red: 0.93, green: 0.13, blue: 0.16),
                status: "Link account",
                url: URL(string: "https://www.doordash.com")
            ),
            DeliveryPartner(
                name: "Uber Eats",
                symbol: "bicycle",
                color: Color.black,
                status: "Link account",
                url: URL(string: "https://www.ubereats.com")
            )
        ]

        let pasta = Recipe(
            title: "Creamy Tuscan Pasta",
            subtitle: "Silky, garlicky, weeknight comfort",
            emoji: "🍝",
            timeMinutes: 30,
            servings: 4,
            ingredients: [
                Ingredient(name: "Rigatoni", quantity: 12, unit: "oz", category: .pantry),
                Ingredient(name: "Baby spinach", quantity: 5, unit: "oz", category: .produce),
                Ingredient(name: "Sun-dried tomatoes", quantity: 1, unit: "jar", category: .pantry),
                Ingredient(name: "Heavy cream", quantity: 1, unit: "cup", category: .dairy),
                Ingredient(name: "Parmesan", quantity: 1, unit: "wedge", category: .dairy),
                Ingredient(name: "Garlic", quantity: 4, unit: "cloves", category: .produce)
            ],
            gradient: [Color(red: 0.95, green: 0.48, blue: 0.26), Color(red: 0.98, green: 0.77, blue: 0.43)]
        )

        let tacos = Recipe(
            title: "Crispy Lime Tacos",
            subtitle: "Bright slaw, avocado, smoky beans",
            emoji: "🌮",
            timeMinutes: 25,
            servings: 4,
            ingredients: [
                Ingredient(name: "Corn tortillas", quantity: 12, unit: "", category: .bakery),
                Ingredient(name: "Black beans", quantity: 2, unit: "cans", category: .pantry),
                Ingredient(name: "Avocados", quantity: 2, unit: "", category: .produce),
                Ingredient(name: "Limes", quantity: 3, unit: "", category: .produce),
                Ingredient(name: "Shredded cabbage", quantity: 1, unit: "bag", category: .produce)
            ],
            gradient: [Color(red: 0.35, green: 0.62, blue: 0.26), Color(red: 0.84, green: 0.79, blue: 0.25)]
        )

        recipes = [pasta, tacos]
        addRecipeIngredientsToCart(pasta, showToast: false)
    }

    var selectedStores: [GroceryStore] {
        stores.filter { selectedStoreIDs.contains($0.id) }
    }

    var cartSubtotal: Double {
        cartItems.reduce(0) { $0 + $1.lineTotal }
    }

    var activeCartItemCount: Int {
        cartItems.filter { !$0.isChecked }.count
    }

    var estimatedSavings: Double {
        storeStrategy == .smartSplit ? 8.42 : 0
    }

    func toggleStore(_ store: GroceryStore) {
        if selectedStoreIDs.contains(store.id) {
            guard selectedStoreIDs.count > 1 else {
                showToast("Keep at least one store selected")
                return
            }
            selectedStoreIDs.remove(store.id)
        } else {
            selectedStoreIDs.insert(store.id)
        }
        rebalanceCart()
    }

    func useOnlyStore(_ store: GroceryStore) {
        selectedStoreIDs = [store.id]
        storeStrategy = .oneStore
        rebalanceCart()
    }

    func applyStoreStrategy() {
        if storeStrategy == .oneStore {
            let storeID = selectedStores.first?.id ?? stores[0].id
            selectedStoreIDs = [storeID]
        }
        rebalanceCart()
    }

    func addRecipe(_ recipe: Recipe) {
        recipes.insert(recipe, at: 0)
        addRecipeIngredientsToCart(recipe)
    }

    func addRecipeIngredientsToCart(_ recipe: Recipe, showToast shouldShowToast: Bool = true) {
        let availableStores = selectedStores.isEmpty ? stores : selectedStores

        for (index, ingredient) in recipe.ingredients.enumerated() {
            let normalized = ingredient.name.lowercased()
            if let existingIndex = cartItems.firstIndex(where: {
                $0.ingredient.name.lowercased() == normalized
            }) {
                cartItems[existingIndex].quantity += 1
                continue
            }

            let store = availableStores[index % availableStores.count]
            cartItems.append(
                CartItem(
                    ingredient: ingredient,
                    recipeName: recipe.title,
                    price: estimatedPrice(for: ingredient, store: store, index: index),
                    storeID: store.id
                )
            )
        }

        rebalanceCart()
        if shouldShowToast {
            self.showToast("\(recipe.ingredients.count) ingredients added to your cart")
        }
    }

    func rebalanceCart() {
        let available = selectedStores.isEmpty ? [stores[0]] : selectedStores

        for index in cartItems.indices {
            let assignedStore: GroceryStore
            if storeStrategy == .oneStore {
                assignedStore = available[0]
            } else {
                assignedStore = available[index % available.count]
            }
            cartItems[index].storeID = assignedStore.id
            cartItems[index].price = estimatedPrice(
                for: cartItems[index].ingredient,
                store: assignedStore,
                index: index
            )
        }
    }

    func updateQuantity(for itemID: UUID, delta: Int) {
        guard let index = cartItems.firstIndex(where: { $0.id == itemID }) else { return }
        cartItems[index].quantity = max(1, cartItems[index].quantity + delta)
    }

    func toggleChecked(_ itemID: UUID) {
        guard let index = cartItems.firstIndex(where: { $0.id == itemID }) else { return }
        cartItems[index].isChecked.toggle()
    }

    func moveItem(_ itemID: UUID, to store: GroceryStore) {
        guard let index = cartItems.firstIndex(where: { $0.id == itemID }) else { return }
        selectedStoreIDs.insert(store.id)
        cartItems[index].storeID = store.id
        cartItems[index].price = estimatedPrice(
            for: cartItems[index].ingredient,
            store: store,
            index: index
        )
    }

    func reservePickup(day: String, time: String) {
        let store = selectedStores.first ?? stores[0]
        let confirmation = "GA-\(Int.random(in: 2400...9899))"
        reservations.insert(
            PickupReservation(
                storeName: store.name,
                day: day,
                time: time,
                itemCount: activeCartItemCount,
                total: cartSubtotal,
                confirmation: confirmation
            ),
            at: 0
        )
        presentedSheet = nil
        selectedTab = .orders
        showToast("Pickup reserved for \(day) at \(time)")
    }

    func connect(_ partner: DeliveryPartner) {
        connectedPartnerName = partner.name
        showToast("\(partner.name) is ready for cart handoff")
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    func store(for id: UUID) -> GroceryStore {
        stores.first(where: { $0.id == id }) ?? stores[0]
    }

    private func estimatedPrice(for ingredient: Ingredient, store: GroceryStore, index: Int) -> Double {
        let categoryBase: Double = switch ingredient.category {
        case .produce: 2.49
        case .dairy: 4.79
        case .meat: 8.99
        case .bakery: 3.69
        case .pantry: 3.29
        case .frozen: 5.49
        }

        let storeAdjustment = store.name == "Target" ? -0.35 : (store.name == "Whole Foods" ? 0.9 : 0)
        let variation = Double(index % 4) * 0.31
        return max(0.99, categoryBase + storeAdjustment + variation)
    }
}

enum RecipeParser {
    static func parse(title: String, text: String) -> Recipe {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let ingredients = lines
            .filter { line in
                line.range(of: #"\d"#, options: .regularExpression) != nil &&
                !line.lowercased().contains("minute") &&
                !line.lowercased().hasPrefix("step")
            }
            .prefix(12)
            .map(parseIngredient)

        let fallback = [
            Ingredient(name: "Yellow onion", quantity: 1, category: .produce),
            Ingredient(name: "Garlic", quantity: 3, unit: "cloves", category: .produce),
            Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp", category: .pantry)
        ]

        return Recipe(
            title: title.isEmpty ? "Untitled recipe" : title,
            subtitle: "Imported from your recipe",
            emoji: emoji(for: title + " " + text),
            timeMinutes: 35,
            servings: 4,
            ingredients: ingredients.isEmpty ? fallback : Array(ingredients),
            gradient: [GatherTheme.tomato, GatherTheme.peach]
        )
    }

    private static func parseIngredient(_ line: String) -> Ingredient {
        let cleaned = line
            .replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression)
        let parts = cleaned.split(separator: " ", maxSplits: 2).map(String.init)

        let quantity = parts.first.flatMap(parseQuantity) ?? 1
        let knownUnits = ["cup", "cups", "tbsp", "tsp", "oz", "lb", "lbs", "clove", "cloves", "can", "cans", "jar", "bag"]
        let possibleUnit = parts.count > 1 ? parts[1].lowercased() : ""
        let hasUnit = knownUnits.contains(possibleUnit)
        let nameStart = hasUnit ? 2 : 1
        let name = parts.count > nameStart
            ? parts[nameStart...].joined(separator: " ")
            : (parts.last ?? cleaned)

        return Ingredient(
            name: name.trimmingCharacters(in: CharacterSet(charactersIn: ", ")).capitalized,
            quantity: quantity,
            unit: hasUnit ? parts[1] : "",
            category: category(for: name)
        )
    }

    private static func parseQuantity(_ value: String) -> Double? {
        if value.contains("/") {
            let fraction = value.split(separator: "/").compactMap { Double($0) }
            if fraction.count == 2, fraction[1] != 0 {
                return fraction[0] / fraction[1]
            }
        }
        return Double(value)
    }

    private static func category(for name: String) -> GroceryCategory {
        let value = name.lowercased()
        if ["milk", "cream", "cheese", "butter", "yogurt", "egg"].contains(where: value.contains) {
            return .dairy
        }
        if ["chicken", "beef", "pork", "salmon", "shrimp", "turkey"].contains(where: value.contains) {
            return .meat
        }
        if ["bread", "tortilla", "bun", "bagel"].contains(where: value.contains) {
            return .bakery
        }
        if ["frozen", "ice cream"].contains(where: value.contains) {
            return .frozen
        }
        if ["onion", "garlic", "tomato", "spinach", "lime", "lemon", "pepper", "avocado", "cabbage", "carrot"].contains(where: value.contains) {
            return .produce
        }
        return .pantry
    }

    private static func emoji(for text: String) -> String {
        let value = text.lowercased()
        if value.contains("taco") { return "🌮" }
        if value.contains("pasta") || value.contains("spaghetti") { return "🍝" }
        if value.contains("soup") { return "🍲" }
        if value.contains("pizza") { return "🍕" }
        if value.contains("salad") { return "🥗" }
        if value.contains("chicken") { return "🍗" }
        return "🍽️"
    }
}
