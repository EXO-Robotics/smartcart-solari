import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case plan
    case cart
    case orders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "Plan"
        case .cart: "Cart"
        case .orders: "Orders"
        }
    }

    var symbol: String {
        switch self {
        case .plan: "fork.knife"
        case .cart: "basket.fill"
        case .orders: "clock.arrow.circlepath"
        }
    }
}

struct Recipe: Identifiable, Hashable {
    let id: UUID
    var title: String
    var subtitle: String
    var emoji: String
    var timeMinutes: Int
    var servings: Int
    var ingredients: [Ingredient]
    var gradient: [Color]

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        emoji: String,
        timeMinutes: Int,
        servings: Int,
        ingredients: [Ingredient],
        gradient: [Color]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.emoji = emoji
        self.timeMinutes = timeMinutes
        self.servings = servings
        self.ingredients = ingredients
        self.gradient = gradient
    }
}

struct Ingredient: Identifiable, Hashable {
    let id: UUID
    var name: String
    var quantity: Double
    var unit: String
    var category: GroceryCategory

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double = 1,
        unit: String = "",
        category: GroceryCategory = .pantry
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
    }

    var displayQuantity: String {
        let value = quantity.rounded() == quantity
            ? String(Int(quantity))
            : String(format: "%.1f", quantity)
        return unit.isEmpty ? value : "\(value) \(unit)"
    }
}

enum GroceryCategory: String, CaseIterable, Hashable {
    case produce = "Produce"
    case dairy = "Dairy"
    case meat = "Meat & Seafood"
    case bakery = "Bakery"
    case pantry = "Pantry"
    case frozen = "Frozen"

    var symbol: String {
        switch self {
        case .produce: "leaf.fill"
        case .dairy: "waterbottle.fill"
        case .meat: "fish.fill"
        case .bakery: "birthday.cake.fill"
        case .pantry: "cabinet.fill"
        case .frozen: "snowflake"
        }
    }
}

struct GroceryStore: Identifiable, Hashable {
    let id: UUID
    var name: String
    var shortName: String
    var distance: Double
    var color: Color
    var symbol: String
    var pickupFee: Double
    var nextPickup: String

    init(
        id: UUID = UUID(),
        name: String,
        shortName: String,
        distance: Double,
        color: Color,
        symbol: String,
        pickupFee: Double,
        nextPickup: String
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.distance = distance
        self.color = color
        self.symbol = symbol
        self.pickupFee = pickupFee
        self.nextPickup = nextPickup
    }
}

struct CartItem: Identifiable, Hashable {
    let id: UUID
    var ingredient: Ingredient
    var recipeName: String
    var quantity: Int
    var price: Double
    var storeID: UUID
    var isChecked: Bool

    init(
        id: UUID = UUID(),
        ingredient: Ingredient,
        recipeName: String,
        quantity: Int = 1,
        price: Double,
        storeID: UUID,
        isChecked: Bool = false
    ) {
        self.id = id
        self.ingredient = ingredient
        self.recipeName = recipeName
        self.quantity = quantity
        self.price = price
        self.storeID = storeID
        self.isChecked = isChecked
    }

    var lineTotal: Double { price * Double(quantity) }
}

struct PickupReservation: Identifiable, Hashable {
    let id = UUID()
    var storeName: String
    var day: String
    var time: String
    var itemCount: Int
    var total: Double
    var confirmation: String
}

enum FulfillmentMode: String, CaseIterable, Identifiable {
    case pickup = "Pickup"
    case delivery = "Delivery"

    var id: String { rawValue }
}

enum StoreStrategy: String, CaseIterable, Identifiable {
    case oneStore = "One store"
    case smartSplit = "Smart split"

    var id: String { rawValue }
}

struct DeliveryPartner: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var symbol: String
    var color: Color
    var status: String
    var url: URL?
}

enum SheetDestination: Identifiable {
    case recipeComposer
    case pickupScheduler
    case storePicker

    var id: String {
        switch self {
        case .recipeComposer: "recipe-composer"
        case .pickupScheduler: "pickup-scheduler"
        case .storePicker: "store-picker"
        }
    }
}
