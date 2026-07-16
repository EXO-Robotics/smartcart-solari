import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case lists
    case pantry
    case store
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .lists: "Lists"
        case .pantry: "Pantry"
        case .store: "Store"
        case .account: "Account"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .lists: "checklist"
        case .pantry: "cabinet.fill"
        case .store: "storefront.fill"
        case .account: "person.crop.circle.fill"
        }
    }
}

enum SmartRoute: Hashable {
    case ingredientReview
    case servingAdjustment
    case pantryCheck
    case storeSelection
    case matching
    case shoppingList
    case guidedShopping
}

enum ImportMethod: String, CaseIterable, Identifiable, Hashable {
    case camera
    case photoLibrary
    case recipeLink
    case pinterest
    case recipeText
    case sample

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Take a photo"
        case .photoLibrary: "Upload photo"
        case .recipeLink: "Paste a link"
        case .pinterest: "Pinterest"
        case .recipeText: "Paste recipe"
        case .sample: "Try a sample"
        }
    }

    var shortTitle: String {
        switch self {
        case .camera: "Camera"
        case .photoLibrary: "Photos"
        case .recipeLink: "Link"
        case .pinterest: "Pinterest"
        case .recipeText: "Text"
        case .sample: "Sample"
        }
    }

    var subtitle: String {
        switch self {
        case .camera: "Scan a cookbook or card"
        case .photoLibrary: "Use a saved screenshot"
        case .recipeLink: "Import recipe page data"
        case .pinterest: "Use a recipe pin link"
        case .recipeText: "Paste an ingredient list"
        case .sample: "Explore the complete flow"
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .photoLibrary: "photo.on.rectangle.angled"
        case .recipeLink: "link"
        case .pinterest: "p.circle.fill"
        case .recipeText: "doc.text.fill"
        case .sample: "takeoutbag.and.cup.and.straw.fill"
        }
    }

    var tint: Color {
        switch self {
        case .camera: GatherTheme.walmartBlue
        case .photoLibrary: Color(red: 0.37, green: 0.36, blue: 0.82)
        case .recipeLink: GatherTheme.navy
        case .pinterest: Color(red: 0.83, green: 0.08, blue: 0.17)
        case .recipeText: GatherTheme.green
        case .sample: GatherTheme.amber
        }
    }
}

enum SheetDestination: Identifiable {
    case importer(ImportMethod)

    var id: String {
        switch self {
        case .importer(let method): "importer-\(method.rawValue)"
        }
    }
}

enum RecipeSource: String, CaseIterable, Hashable {
    case photo = "Recipe photo"
    case link = "Recipe link"
    case pinterest = "Pinterest"
    case text = "Pasted text"
    case sample = "SmartCart sample"
}

struct Recipe: Identifiable, Hashable {
    let id: UUID
    var title: String
    var source: RecipeSource
    var sourceDetail: String
    var heroSymbol: String
    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var ingredients: [Ingredient]

    init(
        id: UUID = UUID(),
        title: String,
        source: RecipeSource,
        sourceDetail: String,
        heroSymbol: String,
        servings: Int,
        prepMinutes: Int,
        cookMinutes: Int,
        ingredients: [Ingredient]
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.sourceDetail = sourceDetail
        self.heroSymbol = heroSymbol
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.ingredients = ingredients
    }

    var totalMinutes: Int { prepMinutes + cookMinutes }
}

struct Ingredient: Identifiable, Hashable {
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

    init(
        id: UUID = UUID(),
        rawText: String = "",
        name: String,
        quantity: Double = 1,
        unit: String = "",
        preparation: String = "",
        category: GroceryCategory = .pantry,
        confidence: IngredientConfidence = .high,
        includeInList: Bool = true,
        pantryState: PantryState = .needToBuy,
        preferenceNote: String = ""
    ) {
        self.id = id
        self.rawText = rawText.isEmpty ? "\(quantity) \(unit) \(name)" : rawText
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.preparation = preparation
        self.category = category
        self.confidence = confidence
        self.includeInList = includeInList
        self.pantryState = pantryState
        self.preferenceNote = preferenceNote
    }

    var displayQuantity: String {
        Self.quantityText(quantity, unit: unit)
    }

    static func quantityText(_ quantity: Double, unit: String) -> String {
        let value: String
        if quantity.rounded() == quantity {
            value = String(Int(quantity))
        } else if quantity < 1 {
            value = String(format: "%.2g", quantity)
        } else {
            value = String(format: "%.1f", quantity)
        }
        return unit.isEmpty ? value : "\(value) \(unit)"
    }
}

enum IngredientConfidence: String, CaseIterable, Identifiable, Hashable {
    case high = "High confidence"
    case review = "Review suggested"
    case unknown = "Could not identify"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: "High confidence"
        case .review: "Review"
        case .unknown: "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .high: "checkmark.circle.fill"
        case .review: "exclamationmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .high: GatherTheme.green
        case .review: GatherTheme.amber
        case .unknown: GatherTheme.coral
        }
    }
}

enum PantryState: String, CaseIterable, Identifiable, Hashable {
    case haveEnough = "Have enough"
    case runningLow = "Running low"
    case needToBuy = "Need to buy"
    case alwaysAsk = "Always ask"
    case exclude = "Exclude"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .haveEnough: "Have enough"
        case .runningLow: "Running low"
        case .needToBuy: "Need to buy"
        case .alwaysAsk: "Ask me"
        case .exclude: "Exclude"
        }
    }

    var symbol: String {
        switch self {
        case .haveEnough: "checkmark.seal.fill"
        case .runningLow: "clock.badge.exclamationmark.fill"
        case .needToBuy: "cart.badge.plus"
        case .alwaysAsk: "questionmark.bubble.fill"
        case .exclude: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .haveEnough: GatherTheme.green
        case .runningLow: GatherTheme.amber
        case .needToBuy: GatherTheme.walmartBlue
        case .alwaysAsk: GatherTheme.purple
        case .exclude: GatherTheme.secondaryInk
        }
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
        case .meat: "fork.knife"
        case .bakery: "birthday.cake.fill"
        case .pantry: "cabinet.fill"
        case .frozen: "snowflake"
        }
    }
}

enum StoreStrategy: String, CaseIterable, Identifiable, Hashable {
    case oneStore = "One store"
    case multipleStops = "Multiple stops"

    var id: String { rawValue }
}

enum FulfillmentMode: String, CaseIterable, Identifiable, Hashable {
    case pickup = "Pickup"
    case delivery = "Delivery"

    var id: String { rawValue }
}

struct RetailerStore: Identifiable, Hashable {
    let id: UUID
    var name: String
    var format: String
    var address: String
    var distance: Double
    var pickupWindow: String
    var supportsPickup: Bool
    var supportsDelivery: Bool

    init(
        id: UUID = UUID(),
        name: String,
        format: String,
        address: String,
        distance: Double,
        pickupWindow: String,
        supportsPickup: Bool = true,
        supportsDelivery: Bool = true
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.address = address
        self.distance = distance
        self.pickupWindow = pickupWindow
        self.supportsPickup = supportsPickup
        self.supportsDelivery = supportsDelivery
    }
}

struct ProductCandidate: Identifiable, Hashable {
    let id: UUID
    var brand: String
    var name: String
    var package: String
    var price: Double
    var unitPrice: String
    var symbol: String
    var confidence: IngredientConfidence
    var variableWeight: Bool

    init(
        id: UUID = UUID(),
        brand: String,
        name: String,
        package: String,
        price: Double,
        unitPrice: String,
        symbol: String,
        confidence: IngredientConfidence = .high,
        variableWeight: Bool = false
    ) {
        self.id = id
        self.brand = brand
        self.name = name
        self.package = package
        self.price = price
        self.unitPrice = unitPrice
        self.symbol = symbol
        self.confidence = confidence
        self.variableWeight = variableWeight
    }
}

enum GuidedItemStatus: String, Hashable {
    case waiting
    case added
    case skipped
}

struct ShoppingListItem: Identifiable, Hashable {
    let id: UUID
    var ingredient: Ingredient
    var requestedQuantity: String
    var purchaseQuantity: Int
    var product: ProductCandidate
    var alternatives: [ProductCandidate]
    var storeID: UUID
    var status: GuidedItemStatus

    init(
        id: UUID = UUID(),
        ingredient: Ingredient,
        requestedQuantity: String,
        purchaseQuantity: Int = 1,
        product: ProductCandidate,
        alternatives: [ProductCandidate],
        storeID: UUID,
        status: GuidedItemStatus = .waiting
    ) {
        self.id = id
        self.ingredient = ingredient
        self.requestedQuantity = requestedQuantity
        self.purchaseQuantity = purchaseQuantity
        self.product = product
        self.alternatives = alternatives
        self.storeID = storeID
        self.status = status
    }

    var lineTotal: Double {
        product.price * Double(purchaseQuantity)
    }
}

struct SavedShoppingList: Identifiable, Hashable {
    let id: UUID
    var recipeTitle: String
    var storeName: String
    var itemCount: Int
    var total: Double
    var savedAt: Date

    init(
        id: UUID = UUID(),
        recipeTitle: String,
        storeName: String,
        itemCount: Int,
        total: Double,
        savedAt: Date = .now
    ) {
        self.id = id
        self.recipeTitle = recipeTitle
        self.storeName = storeName
        self.itemCount = itemCount
        self.total = total
        self.savedAt = savedAt
    }
}

struct DeliveryPartner: Identifiable, Hashable {
    let id: UUID
    var name: String
    var symbol: String
    var color: Color
    var url: URL

    init(id: UUID = UUID(), name: String, symbol: String, color: Color, url: URL) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.url = url
    }
}
