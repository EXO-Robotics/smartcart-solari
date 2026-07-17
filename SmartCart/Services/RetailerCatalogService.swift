import Foundation

protocol RetailerCatalogService {
    var retailerID: String { get }
    var capabilities: RetailerCapabilities { get }

    func searchProducts(
        for request: RetailerProductSearchRequest
    ) async throws -> [RetailerProductRecord]

    func resolveProduct(
        retailerProductID: String,
        storeID: String?
    ) async throws -> RetailerProductRecord

    func refresh(
        product: RetailerProductRecord
    ) async throws -> RetailerProductRecord

    func createHandoff(
        manifest: ShoppingManifest
    ) async throws -> RetailerHandoff
}

enum RetailerServiceError: LocalizedError, Equatable {
    case productNotFound(String)
    case unsupportedCapability(String)

    var errorDescription: String? {
        switch self {
        case .productNotFound(let productID):
            "No retailer product was found for \(productID)."
        case .unsupportedCapability(let capability):
            "\(capability) is not supported by this retailer adapter."
        }
    }
}

struct DemoWalmartCatalogService: RetailerCatalogService {
    let retailerID = "walmart"
    let capabilities: RetailerCapabilities = [
        .catalogSearch,
        .exactProductLinks,
        .pickup,
        .delivery,
        .guidedProductHandoff
    ]

    func searchProducts(
        for request: RetailerProductSearchRequest
    ) async throws -> [RetailerProductRecord] {
        Self.seededProducts(
            for: request.ingredient,
            storeID: request.storeID
        )
    }

    func resolveProduct(
        retailerProductID: String,
        storeID: String?
    ) async throws -> RetailerProductRecord {
        guard var product = DemoProductCatalog.allProducts.first(where: {
            $0.retailerProductID == retailerProductID
        }) else {
            throw RetailerServiceError.productNotFound(retailerProductID)
        }
        product.storeID = storeID
        return product
    }

    func refresh(
        product: RetailerProductRecord
    ) async throws -> RetailerProductRecord {
        throw RetailerServiceError.unsupportedCapability("Live price refresh")
    }

    func createHandoff(
        manifest: ShoppingManifest
    ) async throws -> RetailerHandoff {
        RetailerHandoff(
            retailerID: retailerID,
            mode: .guidedProducts,
            url: URL(string: "https://www.walmart.com/cp/grocery-pickup-and-delivery/9524000")!,
            title: "Visit Walmart",
            disclosure: "SmartCart saved this manifest and can open each exact product or labeled search. It did not transfer a cart, link an account, modify a Wishlist, reserve pickup, or submit payment."
        )
    }

    static func seededProducts(
        for ingredient: Ingredient,
        storeID: String
    ) -> [RetailerProductRecord] {
        DemoProductCatalog.products(for: ingredient).map {
            var product = $0
            product.storeID = storeID
            return product
        }
    }

    static func searchFallback(
        for ingredient: Ingredient,
        storeID: String,
        preferences: ShoppingPreferences
    ) -> RetailerProductRecord {
        var product = DemoProductCatalog.searchFallback(
            title: ingredient.name,
            query: ingredient.name,
            symbol: ingredient.category.symbol,
            organicStatus: preferences.organicPolicy == .only ? .certified : .unknown,
            dietaryAttributes: preferences.dietaryRestrictions
        )
        product.storeID = storeID
        return product
    }
}

enum RetailerProductMatcher {
    static func rank(
        _ candidates: [RetailerProductRecord],
        for request: RetailerProductSearchRequest,
        preferences: ShoppingPreferences
    ) -> [RankedRetailerProduct] {
        let hardFiltered = candidates.filter { candidate in
            guard candidate.availability != .outOfStock else { return false }
            guard candidate.fulfillmentMethods.contains(request.fulfillmentMethod) else { return false }
            guard candidate.dietaryAttributes.isSuperset(of: preferences.dietaryRestrictions) else {
                return false
            }
            if preferences.organicPolicy == .only {
                return candidate.organicStatus.isOrganic
            }
            return true
        }

        let exactCandidates = hardFiltered.filter(\.isExactProductLink)
        let eligible = exactCandidates.isEmpty ? hardFiltered : exactCandidates

        return eligible
            .map { candidate in
                RankedRetailerProduct(
                    product: candidate,
                    score: score(
                        candidate,
                        request: request,
                        preferences: preferences
                    ),
                    reasons: reasons(
                        candidate,
                        request: request,
                        preferences: preferences
                    )
                )
            }
            .sorted { lhs, rhs in
                let leftKey = sortKey(
                    lhs.product,
                    request: request,
                    preferences: preferences
                )
                let rightKey = sortKey(
                    rhs.product,
                    request: request,
                    preferences: preferences
                )

                if leftKey != rightKey {
                    return leftKey.lexicographicallyPrecedes(rightKey) == false
                }
                return lhs.product.retailerProductID < rhs.product.retailerProductID
            }
    }

    private static func sortKey(
        _ product: RetailerProductRecord,
        request: RetailerProductSearchRequest,
        preferences: ShoppingPreferences
    ) -> [Int] {
        let correctness = ingredientCorrectness(product, ingredient: request.ingredient)
        let organic: Int
        switch preferences.organicPolicy {
        case .noPreference:
            organic = 0
        case .whenAvailable, .only:
            organic = product.organicStatus.isOrganic ? 2 : 0
        }

        let fulfillment = product.fulfillmentMethods.contains(request.fulfillmentMethod) ? 1 : 0
        let sufficient = PackageMath.isPackageSufficient(
            product: product,
            requestedQuantity: request.requestedQuantity,
            requestedUnit: request.requestedUnit
        ) ? 1 : 0
        let priceCents = product.observedPrice.map {
            Int((NSDecimalNumber(decimal: $0).doubleValue * 100).rounded())
        } ?? Int.max / 4
        let priceRank: Int
        switch preferences.budgetPriority {
        case .lowestTotal:
            priceRank = -priceCents * 3
        case .balanced:
            priceRank = -priceCents
        case .qualityFirst:
            priceRank = product.priceType == .exact ? 1 : 0
        }
        let brandRank: Int
        if preferences.preferredBrands.contains(where: {
            $0.caseInsensitiveCompare(product.brand) == .orderedSame
        }) {
            brandRank = 3
        } else {
            switch preferences.storeBrandPreference {
            case .prefer:
                brandRank = product.isStoreBrand ? 2 : 0
            case .neutral:
                brandRank = 0
            case .avoid:
                brandRank = product.isStoreBrand ? -2 : 1
            }
        }
        let unitPriceRank = product.unitPriceValue.map {
            -Int((NSDecimalNumber(decimal: $0).doubleValue * 10_000).rounded())
        } ?? Int.min / 4

        return [
            correctness,
            organic,
            product.availability.rankingValue,
            fulfillment,
            sufficient,
            priceRank,
            brandRank,
            unitPriceRank
        ]
    }

    private static func score(
        _ product: RetailerProductRecord,
        request: RetailerProductSearchRequest,
        preferences: ShoppingPreferences
    ) -> Double {
        let key = sortKey(product, request: request, preferences: preferences)
        return Double(key[0] * 20 + key[1] * 12 + key[2] * 6 + key[3] * 4 + key[4] * 3)
    }

    private static func reasons(
        _ product: RetailerProductRecord,
        request: RetailerProductSearchRequest,
        preferences: ShoppingPreferences
    ) -> [String] {
        var values = ["Matches \(request.ingredient.name.lowercased())"]

        if preferences.organicPolicy != .noPreference, product.organicStatus.isOrganic {
            values.append(product.organicStatus.label)
        }
        if product.availability == .inStock {
            values.append("Available for \(request.fulfillmentMethod.rawValue)")
        }
        if PackageMath.isPackageSufficient(
            product: product,
            requestedQuantity: request.requestedQuantity,
            requestedUnit: request.requestedUnit
        ) {
            values.append("Package covers recipe amount")
        }
        if preferences.budgetPriority == .lowestTotal {
            values.append("Lowest eligible purchase price")
        }
        if product.isStoreBrand, preferences.storeBrandPreference == .prefer {
            values.append("Preferred store brand")
        }
        if product.linkKind == .searchResults {
            values.append("No exact eligible record; retailer search fallback")
        }
        return values
    }

    private static func ingredientCorrectness(
        _ product: RetailerProductRecord,
        ingredient: Ingredient
    ) -> Int {
        let ingredientTokens = normalizedTokens(ingredient.name)
        let productTokens = normalizedTokens(product.title)
            .union(product.matchKeywords.map { $0.lowercased() })
        let overlap = ingredientTokens.intersection(productTokens).count
        if overlap >= max(1, ingredientTokens.count / 2) {
            return product.isExactProductLink ? 3 : 2
        }
        return product.isExactProductLink ? 1 : 0
    }

    private static func normalizedTokens(_ value: String) -> Set<String> {
        Set(
            value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
                .map { token in
                    token.hasSuffix("s") ? String(token.dropLast()) : token
                }
        )
    }
}

enum PackageMath {
    static func packageCount(
        product: RetailerProductRecord,
        requestedQuantity: Double,
        requestedUnit: String
    ) -> Int {
        guard
            let packageQuantity = product.packageQuantity,
            packageQuantity > 0,
            let converted = convertedQuantity(
                requestedQuantity,
                from: requestedUnit,
                to: product.packageUnit ?? ""
            )
        else {
            return 1
        }
        return max(1, Int(ceil(converted / packageQuantity)))
    }

    static func isPackageSufficient(
        product: RetailerProductRecord,
        requestedQuantity: Double,
        requestedUnit: String
    ) -> Bool {
        guard
            let packageQuantity = product.packageQuantity,
            let converted = convertedQuantity(
                requestedQuantity,
                from: requestedUnit,
                to: product.packageUnit ?? ""
            )
        else {
            return true
        }
        return packageQuantity >= converted
    }

    private static func convertedQuantity(
        _ quantity: Double,
        from sourceUnit: String,
        to destinationUnit: String
    ) -> Double? {
        let source = normalizedUnit(sourceUnit)
        let destination = normalizedUnit(destinationUnit)
        if source.isEmpty || destination.isEmpty || source == destination {
            return quantity
        }

        switch (source, destination) {
        case ("lb", "oz"):
            return quantity * 16
        case ("oz", "lb"):
            return quantity / 16
        case ("cup", "fl oz"):
            return quantity * 8
        case ("fl oz", "cup"):
            return quantity / 8
        case ("tbsp", "fl oz"):
            return quantity / 2
        case ("tsp", "fl oz"):
            return quantity / 6
        case ("clove", "count"), ("lemon", "count"), ("bunch", "count"):
            return quantity
        default:
            return nil
        }
    }

    private static func normalizedUnit(_ unit: String) -> String {
        switch unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "lbs", "pound", "pounds": "lb"
        case "ounce", "ounces": "oz"
        case "cups": "cup"
        case "fluid ounce", "fluid ounces", "floz": "fl oz"
        case "tablespoon", "tablespoons": "tbsp"
        case "teaspoon", "teaspoons": "tsp"
        case "cloves": "clove"
        case "lemons": "lemon"
        case "bunches": "bunch"
        case "each", "ea": "count"
        default: unit.lowercased()
        }
    }
}

private enum DemoProductCatalog {
    static let observedAt: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 7
        components.day = 16
        components.hour = 12
        return components.date!
    }()

    static var allProducts: [RetailerProductRecord] {
        chicken + pasta + oliveOil + heavyCream + parmesan + garlic + lemon + parsley
    }

    static func products(for ingredient: Ingredient) -> [RetailerProductRecord] {
        let value = ingredient.name.lowercased()
        if value.contains("chicken") { return chicken }
        if ["pasta", "rigatoni", "penne", "spaghetti", "fettuccine", "noodle"].contains(where: value.contains) {
            return pasta
        }
        if value.contains("olive oil") { return oliveOil }
        if value.contains("cream") { return heavyCream }
        if value.contains("parmesan") { return parmesan }
        if value.contains("garlic") { return garlic }
        if value.contains("lemon") || value.contains("lime") { return lemon }
        if value.contains("parsley") || value.contains("cilantro") { return parsley }

        return [
            searchFallback(
                title: ingredient.name,
                query: ingredient.name,
                symbol: ingredient.category.symbol,
                organicStatus: .unknown,
                dietaryAttributes: []
            )
        ]
    }

    static let chicken = [
        product(
            id: "10414680",
            title: "All Natural Boneless Skinless Chicken Breasts",
            brand: "Great Value",
            url: "https://www.walmart.com/ip/10414680",
            package: "3 lb frozen bag",
            packageQuantity: 3,
            packageUnit: "lb",
            price: "9.47",
            unitPriceValue: "3.16",
            unitPriceText: "$3.16/lb",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.glutenFree, .nutFree],
            symbol: "fork.knife",
            variableWeight: false,
            keywords: ["chicken", "breast"],
            storeBrand: true
        ),
        product(
            id: "145781250",
            title: "Organic Fresh Boneless Chicken Breast",
            brand: "Perdue Harvestland",
            url: "https://www.walmart.com/ip/145781250",
            package: "1–2 lb tray",
            packageQuantity: 1.5,
            packageUnit: "lb",
            price: "8.76",
            unitPriceValue: "6.74",
            unitPriceText: "$6.74/lb est.",
            priceType: .variableWeight,
            organic: .certified,
            dietary: [.glutenFree, .nutFree],
            symbol: "fork.knife",
            variableWeight: true,
            keywords: ["chicken", "breast"]
        ),
        product(
            id: "19400236",
            title: "Free Range Fresh Boneless Chicken Breast",
            brand: "Perdue Harvestland",
            url: "https://www.walmart.com/ip/19400236",
            package: "2.75–3.6 lb tray",
            packageQuantity: 3,
            packageUnit: "lb",
            price: "13.92",
            unitPriceValue: "4.64",
            unitPriceText: "$4.64/lb est.",
            priceType: .variableWeight,
            organic: .notOrganic,
            dietary: [.glutenFree, .nutFree],
            symbol: "fork.knife",
            variableWeight: true,
            keywords: ["chicken", "breast"]
        )
    ]

    static let pasta = [
        product(
            id: "10534084",
            title: "Penne Pasta",
            brand: "Great Value",
            url: "https://www.walmart.com/ip/10534084",
            package: "16 oz box",
            packageQuantity: 16,
            packageUnit: "oz",
            price: "1.24",
            unitPriceValue: "0.078",
            unitPriceText: "7.8¢/oz",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .vegan, .nutFree, .kosher],
            symbol: "takeoutbag.and.cup.and.straw.fill",
            keywords: ["pasta", "penne"],
            storeBrand: true
        ),
        product(
            id: "623835750",
            title: "Gluten Free Penne Pasta",
            brand: "Barilla",
            url: "https://www.walmart.com/ip/623835750",
            package: "2 × 12 oz",
            packageQuantity: 24,
            packageUnit: "oz",
            price: "11.98",
            unitPriceValue: "0.499",
            unitPriceText: "49.9¢/oz",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree],
            symbol: "takeoutbag.and.cup.and.straw.fill",
            keywords: ["pasta", "penne"]
        ),
        searchFallback(
            title: "Organic Penne Pasta",
            query: "organic penne pasta",
            symbol: "takeoutbag.and.cup.and.straw.fill",
            organicStatus: .certified,
            dietaryAttributes: [.vegetarian, .vegan, .dairyFree, .nutFree]
        )
    ]

    static let oliveOil = [
        product(
            id: "10315102",
            title: "Extra Virgin Olive Oil",
            brand: "Great Value",
            url: "https://www.walmart.com/ip/10315102",
            package: "17 fl oz",
            packageQuantity: 17,
            packageUnit: "fl oz",
            price: "6.12",
            unitPriceValue: "0.36",
            unitPriceText: "36¢/fl oz",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree, .kosher],
            symbol: "waterbottle.fill",
            keywords: ["olive", "oil"],
            storeBrand: true
        ),
        product(
            id: "51630343",
            title: "Organic Extra Virgin Olive Oil",
            brand: "Great Value",
            url: "https://www.walmart.com/ip/51630343",
            package: "17 fl oz",
            packageQuantity: 17,
            packageUnit: "fl oz",
            price: "7.36",
            unitPriceValue: "0.433",
            unitPriceText: "43.3¢/fl oz",
            priceType: .exact,
            organic: .certified,
            dietary: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree, .kosher],
            symbol: "waterbottle.fill",
            keywords: ["olive", "oil"],
            storeBrand: true
        ),
        product(
            id: "176946682",
            title: "Smooth Extra Virgin Olive Oil",
            brand: "Pompeian",
            url: "https://www.walmart.com/ip/176946682",
            package: "16 fl oz",
            packageQuantity: 16,
            packageUnit: "fl oz",
            price: "7.38",
            unitPriceValue: "0.461",
            unitPriceText: "46.1¢/fl oz",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree, .kosher],
            symbol: "waterbottle.fill",
            keywords: ["olive", "oil"]
        )
    ]

    static let heavyCream = [
        product(
            id: "10450339",
            title: "Heavy Whipping Cream",
            brand: "Great Value",
            url: "https://www.walmart.com/ip/10450339",
            package: "16 fl oz carton",
            packageQuantity: 16,
            packageUnit: "fl oz",
            price: "2.96",
            unitPriceValue: "0.185",
            unitPriceText: "18.5¢/fl oz",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .glutenFree, .nutFree],
            symbol: "waterbottle.fill",
            keywords: ["heavy", "cream"],
            storeBrand: true
        ),
        product(
            id: "53986354",
            title: "Organic Heavy Whipping Cream",
            brand: "Horizon Organic",
            url: "https://www.walmart.com/ip/53986354",
            package: "16 fl oz carton",
            packageQuantity: 16,
            packageUnit: "fl oz",
            price: "5.87",
            unitPriceValue: "0.367",
            unitPriceText: "36.7¢/fl oz",
            priceType: .exact,
            organic: .certified,
            dietary: [.vegetarian, .glutenFree, .nutFree],
            symbol: "waterbottle.fill",
            keywords: ["heavy", "cream"]
        ),
        searchFallback(
            title: "Dairy-Free Heavy Whipping Cream",
            query: "dairy free heavy whipping cream",
            symbol: "waterbottle.fill",
            organicStatus: .unknown,
            dietaryAttributes: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree]
        )
    ]

    static let parmesan = [
        product(
            id: "10452414",
            title: "Finely Shredded Parmesan Cheese",
            brand: "Great Value",
            url: "https://www.walmart.com/ip/10452414",
            package: "6 oz bag",
            packageQuantity: 6,
            packageUnit: "oz",
            price: "2.08",
            unitPriceValue: "0.347",
            unitPriceText: "34.7¢/oz",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .glutenFree, .nutFree],
            symbol: "waterbottle.fill",
            keywords: ["parmesan", "cheese"],
            storeBrand: true
        ),
        product(
            id: "10307238",
            title: "Shredded Parmesan Cheese",
            brand: "Frigo",
            url: "https://www.walmart.com/ip/10307238",
            package: "5 oz cup",
            packageQuantity: 5,
            packageUnit: "oz",
            price: "3.28",
            unitPriceValue: "0.656",
            unitPriceText: "65.6¢/oz",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .glutenFree, .nutFree],
            symbol: "waterbottle.fill",
            keywords: ["parmesan", "cheese"]
        ),
        product(
            id: "47088917",
            title: "Finely Shredded Parmesan Cheese",
            brand: "Kraft",
            url: "https://www.walmart.com/ip/47088917",
            package: "6 oz bag",
            packageQuantity: 6,
            packageUnit: "oz",
            price: "4.98",
            unitPriceValue: "0.83",
            unitPriceText: "83¢/oz",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .glutenFree, .nutFree],
            symbol: "waterbottle.fill",
            keywords: ["parmesan", "cheese"]
        )
    ]

    static let garlic = [
        product(
            id: "44391100",
            title: "Fresh Whole Garlic Bulb",
            brand: "Fresh Produce",
            url: "https://www.walmart.com/ip/44391100",
            package: "1 bulb",
            packageQuantity: 8,
            packageUnit: "count",
            price: "0.78",
            unitPriceValue: "0.098",
            unitPriceText: "Approx. 8 cloves",
            priceType: .estimated,
            organic: .notOrganic,
            dietary: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree],
            symbol: "leaf.fill",
            keywords: ["garlic", "clove"]
        ),
        product(
            id: "44391024",
            title: "Fresh Peeled Garlic",
            brand: "Spice World",
            url: "https://www.walmart.com/ip/44391024",
            package: "6 oz pouch",
            packageQuantity: 6,
            packageUnit: "oz",
            price: "3.07",
            unitPriceValue: "0.512",
            unitPriceText: "51.2¢/oz",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree, .kosher],
            symbol: "leaf.fill",
            keywords: ["garlic", "clove"]
        ),
        product(
            id: "131236350",
            title: "Minced Garlic in Extra Virgin Olive Oil",
            brand: "Great Value",
            url: "https://www.walmart.com/ip/131236350",
            package: "8 oz jar",
            packageQuantity: 8,
            packageUnit: "oz",
            price: "3.12",
            unitPriceValue: "0.39",
            unitPriceText: "39¢/oz",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree],
            symbol: "leaf.fill",
            confidence: .review,
            keywords: ["garlic", "minced"],
            storeBrand: true
        )
    ]

    static let lemon = [
        product(
            id: "41752773",
            title: "Fresh Lemon",
            brand: "Fresh Produce",
            url: "https://www.walmart.com/ip/41752773",
            package: "Each",
            packageQuantity: 1,
            packageUnit: "count",
            price: "0.64",
            unitPriceValue: "0.64",
            unitPriceText: "64¢/ea",
            priceType: .exact,
            organic: .notOrganic,
            dietary: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree],
            symbol: "leaf.fill",
            variableWeight: true,
            keywords: ["lemon", "citrus"]
        ),
        product(
            id: "51259193",
            title: "Organic Lemons",
            brand: "Marketside",
            url: "https://www.walmart.com/ip/51259193",
            package: "2 lb bag",
            packageQuantity: 2,
            packageUnit: "lb",
            price: "3.92",
            unitPriceValue: "1.96",
            unitPriceText: "$1.96/lb",
            priceType: .exact,
            organic: .certified,
            dietary: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree],
            symbol: "leaf.fill",
            variableWeight: true,
            keywords: ["lemon", "citrus"]
        )
    ]

    static let parsley = [
        product(
            id: "44391167",
            title: "Fresh Cut Parsley",
            brand: "Fresh Produce",
            url: "https://www.walmart.com/ip/44391167",
            package: "1 bunch",
            packageQuantity: 1,
            packageUnit: "count",
            price: "0.98",
            unitPriceValue: "0.98",
            unitPriceText: "98¢/bunch",
            priceType: .estimated,
            organic: .notOrganic,
            dietary: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree],
            symbol: "leaf.fill",
            variableWeight: true,
            keywords: ["parsley", "herb"]
        ),
        searchFallback(
            title: "Organic Fresh Parsley",
            query: "organic fresh parsley bunch",
            symbol: "leaf.fill",
            organicStatus: .certified,
            dietaryAttributes: [.vegetarian, .vegan, .glutenFree, .dairyFree, .nutFree]
        )
    ]

    private static func product(
        id: String,
        title: String,
        brand: String,
        url: String,
        package: String,
        packageQuantity: Double?,
        packageUnit: String?,
        price: String,
        unitPriceValue: String?,
        unitPriceText: String,
        priceType: PriceType,
        organic: OrganicStatus,
        dietary: Set<DietaryAttribute>,
        symbol: String,
        confidence: IngredientConfidence = .high,
        variableWeight: Bool = false,
        keywords: Set<String>,
        storeBrand: Bool = false
    ) -> RetailerProductRecord {
        RetailerProductRecord(
            retailerID: "walmart",
            storeID: nil,
            retailerProductID: id,
            title: title,
            brand: brand,
            exactURL: URL(string: url)!,
            packageDescription: package,
            packageQuantity: packageQuantity,
            packageUnit: packageUnit,
            observedPrice: Decimal(string: price),
            unitPriceValue: unitPriceValue.flatMap { Decimal(string: $0) },
            unitPriceText: unitPriceText,
            priceType: priceType,
            availability: .inStock,
            fulfillmentMethods: [.pickup, .delivery],
            organicStatus: organic,
            dietaryAttributes: dietary,
            dataSource: .demoSeed,
            observedAt: observedAt,
            linkKind: .exactProduct,
            symbol: symbol,
            confidence: confidence,
            variableWeight: variableWeight,
            matchKeywords: keywords,
            isStoreBrand: storeBrand
        )
    }

    fileprivate static func searchFallback(
        title: String,
        query: String,
        symbol: String,
        organicStatus: OrganicStatus,
        dietaryAttributes: Set<DietaryAttribute>
    ) -> RetailerProductRecord {
        var components = URLComponents(string: "https://www.walmart.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        return RetailerProductRecord(
            retailerID: "walmart",
            storeID: nil,
            retailerProductID: "search:\(query.lowercased().replacingOccurrences(of: " ", with: "-"))",
            title: title,
            brand: "Search fallback",
            exactURL: components.url!,
            packageDescription: "Choose at retailer",
            observedPrice: nil,
            unitPriceText: "Price unavailable",
            priceType: .unavailable,
            availability: .unknown,
            fulfillmentMethods: [.pickup, .delivery],
            organicStatus: organicStatus,
            dietaryAttributes: dietaryAttributes,
            dataSource: .searchFallback,
            observedAt: observedAt,
            linkKind: .searchResults,
            symbol: symbol,
            confidence: .unknown,
            matchKeywords: Set(
                query
                    .lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }
            )
        )
    }
}
