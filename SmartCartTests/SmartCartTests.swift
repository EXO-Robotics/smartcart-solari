import Foundation
import UIKit
import XCTest
@testable import SmartCart

final class SmartCartTests: XCTestCase {
    func testRecipeParserHandlesFractionsUnitsAndOptionalItems() {
        let recipe = RecipeParser.parse(
            title: "Test Pasta",
            text: """
            1 1/2 cups heavy cream
            2 cloves garlic, minced
            1/4 cup parsley, optional
            """
        )

        XCTAssertEqual(recipe.ingredients.count, 3)
        XCTAssertEqual(recipe.ingredients[0].quantity, 1.5, accuracy: 0.001)
        XCTAssertEqual(recipe.ingredients[0].unit, "cups")
        XCTAssertEqual(recipe.ingredients[1].quantity, 2, accuracy: 0.001)
        XCTAssertEqual(recipe.ingredients[1].unit, "cloves")
        XCTAssertFalse(recipe.ingredients[2].includeInList)
    }

    func testGoldenRecipeCorpusParsesCommonFormats() {
        let corpus: [(String, Int, String, Double)] = [
            ("½ cup heavy cream\n2 cloves garlic, minced", 2, "Heavy Cream", 0.5),
            ("2-3 large lemons\nSalt and pepper to taste", 2, "Large Lemons", 3),
            ("one bunch parsley\n1 1/2 lb chicken breasts", 2, "Parsley", 1),
            ("1 tbsp EVOO\n¼ cup scallions", 2, "Olive Oil", 1)
        ]

        for (text, count, firstName, firstQuantity) in corpus {
            let recipe = RecipeParser.parse(title: "Golden", text: text)
            XCTAssertEqual(recipe.ingredients.count, count, "Failed corpus text: \(text)")
            XCTAssertEqual(recipe.ingredients[0].name, firstName, "Failed corpus text: \(text)")
            XCTAssertEqual(recipe.ingredients[0].quantity, firstQuantity, accuracy: 0.001)
        }
    }

    func testParserPreservesMixedFractionsAndConservativeRanges() throws {
        let recipe = RecipeParser.parse(
            title: "Fraction Matrix",
            text: """
            2½ cups flour
            1-1/2 cups milk
            ⅜ cup olive oil
            2 to 3 lemons
            """
        )

        XCTAssertEqual(recipe.ingredients.count, 4)
        XCTAssertEqual(recipe.ingredients[0].quantity, 2.5, accuracy: 0.001)
        XCTAssertEqual(recipe.ingredients[1].quantity, 1.5, accuracy: 0.001)
        XCTAssertEqual(recipe.ingredients[2].quantity, 0.375, accuracy: 0.001)
        XCTAssertEqual(recipe.ingredients[3].quantityLowerBound, 2)
        XCTAssertEqual(recipe.ingredients[3].quantity, 3, accuracy: 0.001)
        XCTAssertEqual(recipe.ingredients[3].displayQuantity, "2–3")
        XCTAssertEqual(recipe.ingredients[3].confidence, .review)
        XCTAssertFalse(recipe.ingredients[3].quantityReviewRequired ?? false)
    }

    func testParserKeepsCommaNamesAndPackageMeasurements() throws {
        let recipe = RecipeParser.parse(
            title: "Weeknight Dinner",
            text: """
            1 lb boneless, skinless chicken breasts
            2 (14 oz) cans diced tomatoes, drained
            """
        )

        XCTAssertEqual(recipe.ingredients.count, 2)
        XCTAssertEqual(recipe.ingredients[0].name, "Boneless, Skinless Chicken Breasts")
        let tomatoes = recipe.ingredients[1]
        XCTAssertEqual(tomatoes.quantity, 2, accuracy: 0.001)
        XCTAssertEqual(tomatoes.unit, "cans")
        XCTAssertEqual(tomatoes.name, "Diced Tomatoes")
        XCTAssertEqual(tomatoes.preparation, "drained")
        let packages = try tomatoes.equivalentMeasurements.firstUnwrapped()
        let package = try packages.firstUnwrapped()
        XCTAssertEqual(package.quantity, 14, accuracy: 0.001)
        XCTAssertEqual(package.unit, "oz")
    }

    func testIngredientSectionAllowsQuantitylessItemsAndRejectsDirections() {
        let recipe = RecipeParser.parse(
            title: "Sauce",
            text: """
            Ingredients
            Cooking spray
            Hot sauce, to taste
            Eggs as needed
            Instructions (continued)
            Add 2 eggs and whisk until smooth.
            """
        )

        XCTAssertEqual(recipe.ingredients.map(\.name), ["Cooking Spray", "Hot Sauce", "Eggs"])
        XCTAssertTrue(recipe.ingredients.allSatisfy { !$0.name.localizedCaseInsensitiveContains("add") })
        XCTAssertTrue(recipe.ingredients.allSatisfy { $0.confidence == .review })
    }

    func testImportReportSurfacesDroppedCandidatesAndRequiredConfirmation() {
        let text = "Ingredients\n1/? cup flour\n2 eggs\nDirections\nBake for 20 minutes"
        let recipe = RecipeParser.parse(title: "Review", text: text)
        let report = RecipeParser.importReport(for: recipe, recognizedText: text)

        XCTAssertEqual(report.requiredConfirmationCount, 1)
        XCTAssertEqual(report.confidenceLabel, "Needs review")
        XCTAssertGreaterThanOrEqual(report.omittedCandidateLineCount, 0)
    }

    func testImportReportProducesBoundedConfidenceAndPageMetrics() {
        let text = "1 cup rice\nSalt to taste\n2 tbsp olive oil"
        let recipe = RecipeParser.parse(title: "Rice", text: text)
        let report = RecipeParser.importReport(
            for: recipe,
            recognizedText: text,
            sourcePageCount: 3,
            retryCount: 1,
            duration: 0.42
        )

        XCTAssertEqual(report.sourcePageCount, 3)
        XCTAssertEqual(report.recognizedLineCount, 3)
        XCTAssertEqual(report.ingredientLineCount, 3)
        XCTAssertEqual(report.retryCount, 1)
        XCTAssertGreaterThanOrEqual(report.confidenceScore, 0)
        XCTAssertLessThanOrEqual(report.confidenceScore, 1)
    }

    func testPackageMathConvertsAndRoundsUp() throws {
        let product = try exactProducts(for: "Penne pasta", unit: "oz").firstUnwrapped()

        XCTAssertEqual(
            PackageMath.packageCount(
                product: product,
                requestedQuantity: 24,
                requestedUnit: "oz"
            ),
            2
        )
        XCTAssertEqual(
            PackageMath.packageCount(
                product: product,
                requestedQuantity: 2,
                requestedUnit: "lb"
            ),
            2
        )
    }

    func testOrganicOnlyIsAHardConstraint() throws {
        let request = searchRequest(for: "Olive oil", unit: "tbsp")
        var preferences = ShoppingPreferences()
        preferences.organicPolicy = .only

        let ranked = RetailerProductMatcher.rank(
            DemoWalmartCatalogService.seededProducts(
                for: request.ingredient,
                storeID: request.storeID
            ),
            for: request,
            preferences: preferences
        )

        XCTAssertFalse(ranked.isEmpty)
        XCTAssertTrue(ranked.allSatisfy(\.product.organicStatus.isOrganic))
        XCTAssertEqual(ranked.first?.product.retailerProductID, "51630343")
    }

    func testOrganicWhenAvailableRanksOrganicButKeepsFallback() {
        let request = searchRequest(for: "Olive oil", unit: "tbsp")
        var preferences = ShoppingPreferences()
        preferences.organicPolicy = .whenAvailable

        let ranked = RetailerProductMatcher.rank(
            DemoWalmartCatalogService.seededProducts(
                for: request.ingredient,
                storeID: request.storeID
            ),
            for: request,
            preferences: preferences
        )

        XCTAssertEqual(ranked.first?.product.retailerProductID, "51630343")
        XCTAssertTrue(ranked.contains { !$0.product.organicStatus.isOrganic })
    }

    func testOrganicOnlyUsesLabeledSearchWhenNoOrganicExactProductExists() {
        let request = searchRequest(for: "Parmesan cheese", unit: "oz")
        var preferences = ShoppingPreferences()
        preferences.organicPolicy = .only

        let exactRanked = RetailerProductMatcher.rank(
            DemoWalmartCatalogService.seededProducts(
                for: request.ingredient,
                storeID: request.storeID
            ),
            for: request,
            preferences: preferences
        )
        XCTAssertTrue(exactRanked.isEmpty)

        let fallback = DemoWalmartCatalogService.searchFallback(
            for: request.ingredient,
            storeID: request.storeID,
            preferences: preferences
        )
        let fallbackRanked = RetailerProductMatcher.rank(
            [fallback],
            for: request,
            preferences: preferences
        )

        XCTAssertEqual(fallbackRanked.first?.product.linkKind, .searchResults)
        XCTAssertEqual(fallbackRanked.first?.product.dataSource, .searchFallback)
        XCTAssertNil(fallbackRanked.first?.product.observedPrice)
    }

    func testDietaryRestrictionFiltersIneligibleProducts() {
        let request = searchRequest(for: "Penne pasta", unit: "oz")
        var preferences = ShoppingPreferences()
        preferences.organicPolicy = .noPreference
        preferences.dietaryRestrictions = [.glutenFree]

        let ranked = RetailerProductMatcher.rank(
            DemoWalmartCatalogService.seededProducts(
                for: request.ingredient,
                storeID: request.storeID
            ),
            for: request,
            preferences: preferences
        )

        XCTAssertEqual(ranked.first?.product.retailerProductID, "623835750")
        XCTAssertTrue(ranked.allSatisfy { $0.product.dietaryAttributes.contains(.glutenFree) })
    }

    func testLowestTotalRanksCheapestEligibleExactProduct() {
        let request = searchRequest(for: "Olive oil", unit: "tbsp")
        var preferences = ShoppingPreferences()
        preferences.organicPolicy = .noPreference
        preferences.budgetPriority = .lowestTotal

        let ranked = RetailerProductMatcher.rank(
            DemoWalmartCatalogService.seededProducts(
                for: request.ingredient,
                storeID: request.storeID
            ),
            for: request,
            preferences: preferences
        )

        XCTAssertEqual(ranked.first?.product.retailerProductID, "10315102")
    }

    func testMatcherReturnsNoMatchWhenHardConstraintsCannotBeMet() throws {
        let request = searchRequest(for: "Heavy cream", unit: "cup")
        var preferences = ShoppingPreferences()
        preferences.dietaryRestrictions = [.vegan]
        let conventional = try exactProducts(for: "Heavy cream", unit: "cup").firstUnwrapped()

        let ranked = RetailerProductMatcher.rank(
            [conventional],
            for: request,
            preferences: preferences
        )

        XCTAssertTrue(ranked.isEmpty)
    }

    func testSearchFallbackIsExplicitAndUnpriced() {
        let ingredient = Ingredient(name: "Dragon fruit jam")
        let product = DemoWalmartCatalogService.searchFallback(
            for: ingredient,
            storeID: "walmart-5206",
            preferences: ShoppingPreferences()
        )

        XCTAssertEqual(product.linkKind, .searchResults)
        XCTAssertEqual(product.dataSource, .searchFallback)
        XCTAssertNil(product.observedPrice)
        XCTAssertEqual(product.storeID, "walmart-5206")
        XCTAssertTrue(product.exactURL.absoluteString.contains("/search"))
    }

    func testSeededCatalogLinksAndPriceDisclosuresAreTruthful() {
        let ingredients = [
            "Chicken breast",
            "Penne pasta",
            "Olive oil",
            "Heavy cream",
            "Parmesan cheese",
            "Garlic",
            "Lemon",
            "Parsley"
        ]
        let products = ingredients.flatMap {
            DemoWalmartCatalogService.seededProducts(
                for: Ingredient(name: $0),
                storeID: "walmart-5206"
            )
        }

        for product in products {
            XCTAssertEqual(product.exactURL.host, "www.walmart.com")
            if product.isExactProductLink {
                XCTAssertEqual(product.dataSource, .demoSeed)
                XCTAssertEqual(product.exactURL.path, "/ip/\(product.retailerProductID)")
                XCTAssertNotNil(product.observedPrice)
                XCTAssertTrue(product.priceDisclosure.localizedCaseInsensitiveContains("demo"))
                XCTAssertTrue(product.priceDisclosure.localizedCaseInsensitiveContains("not live"))
            } else {
                XCTAssertEqual(product.linkKind, .searchResults)
                XCTAssertEqual(product.dataSource, .searchFallback)
                XCTAssertEqual(product.exactURL.path, "/search")
                XCTAssertNil(product.observedPrice)
            }
        }
    }

    func testProductRecordRoundTripsAndDetectsStalePrice() throws {
        var product = try exactProducts(for: "Penne pasta", unit: "oz").firstUnwrapped()
        product.observedAt = Date(timeIntervalSince1970: 100)

        let data = try JSONEncoder().encode(product)
        let decoded = try JSONDecoder().decode(RetailerProductRecord.self, from: data)

        XCTAssertEqual(decoded, product)
        XCTAssertTrue(
            decoded.isPriceStale(
                relativeTo: Date(timeIntervalSince1970: 100 + 86_401)
            )
        )
        XCTAssertEqual(decoded.availability, .inStock)
    }

    func testJSONPersistenceSavesAndReloadsState() throws {
        let directory = temporaryDirectory()
        let store = JSONSmartCartStateStore(
            fileURL: directory.appendingPathComponent("state.json")
        )
        let state = try makeState()

        try store.save(state)
        let restored = try XCTUnwrap(store.load())

        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.shoppingItems.first?.product.storeID, "walmart-5206")
    }

    @MainActor
    func testFreshInstallDoesNotManufactureShoppingProgress() {
        let model = AppModel(stateStore: InMemorySmartCartStateStore())

        XCTAssertTrue(model.shoppingItems.isEmpty)
        XCTAssertTrue(model.savedLists.isEmpty)
        XCTAssertTrue(model.shoppingSessions.isEmpty)
        XCTAssertFalse(model.walmartGuideIsComplete)
    }

    func testLegacyStateMigratesWithDefaultPreferences() throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("state.json")
        let store = JSONSmartCartStateStore(fileURL: fileURL)
        let state = try makeState()
        let legacy = LegacySmartCartPersistedStateV0(
            recipes: state.recipes,
            activeRecipe: state.activeRecipe,
            desiredServings: state.desiredServings,
            storeStrategy: state.storeStrategy,
            fulfillmentMode: state.fulfillmentMode,
            selectedStoreIDs: state.selectedStoreIDs,
            zipCode: state.zipCode,
            pickupDay: state.pickupDay,
            pickupTime: state.pickupTime,
            shoppingItems: state.shoppingItems,
            guidedIndex: state.guidedIndex,
            savedLists: state.savedLists
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(to: fileURL, options: .atomic)

        let migrated = try XCTUnwrap(store.load())

        XCTAssertEqual(migrated.schemaVersion, SmartCartPersistedState.currentSchemaVersion)
        XCTAssertEqual(migrated.preferences, ShoppingPreferences())
        XCTAssertNil(migrated.preferredDeliveryPartnerName)
    }

    func testBeta2StateMigratesPantryAndAnalyticsDefaults() throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("state.json")
        let store = JSONSmartCartStateStore(fileURL: fileURL)
        let state = try makeState()
        let legacy = LegacySmartCartPersistedStateV1(
            recipes: state.recipes,
            activeRecipe: state.activeRecipe,
            desiredServings: state.desiredServings,
            preferences: state.preferences,
            featureFlags: AppFeatureFlags(advancedToolsEnabled: true),
            storeStrategy: state.storeStrategy,
            fulfillmentMode: state.fulfillmentMode,
            selectedStoreIDs: state.selectedStoreIDs,
            zipCode: state.zipCode,
            pickupDay: state.pickupDay,
            pickupTime: state.pickupTime,
            shoppingItems: state.shoppingItems,
            guidedIndex: state.guidedIndex,
            savedLists: state.savedLists,
            preferredDeliveryPartnerName: "Instacart"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(to: fileURL, options: .atomic)

        let migrated = try XCTUnwrap(store.load())

        XCTAssertEqual(migrated.schemaVersion, SmartCartPersistedState.currentSchemaVersion)
        XCTAssertTrue(migrated.featureFlags.advancedToolsEnabled)
        XCTAssertEqual(migrated.preferredDeliveryPartnerName, "Instacart")
        XCTAssertTrue(migrated.pantryInventory.isEmpty)
        XCTAssertTrue(migrated.analyticsEvents.isEmpty)
        XCTAssertTrue(migrated.preferredProductIDsByIngredient.isEmpty)
    }

    func testSchema3MigratesWithNoInventedWalmartWishlistReference() throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("state.json")
        let store = JSONSmartCartStateStore(fileURL: fileURL)
        let state = try makeState()
        let legacy = LegacySmartCartPersistedStateV3(
            recipes: state.recipes,
            activeRecipe: state.activeRecipe,
            desiredServings: state.desiredServings,
            preferences: state.preferences,
            featureFlags: state.featureFlags,
            storeStrategy: state.storeStrategy,
            fulfillmentMode: state.fulfillmentMode,
            selectedStoreIDs: state.selectedStoreIDs,
            zipCode: state.zipCode,
            pickupDay: state.pickupDay,
            pickupTime: state.pickupTime,
            shoppingItems: state.shoppingItems,
            guidedIndex: state.guidedIndex,
            savedLists: state.savedLists,
            preferredDeliveryPartnerName: state.preferredDeliveryPartnerName,
            pantryInventory: state.pantryInventory,
            preferredProductIDsByIngredient: state.preferredProductIDsByIngredient,
            analyticsEvents: state.analyticsEvents
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(to: fileURL, options: .atomic)

        let migrated = try XCTUnwrap(store.load())

        XCTAssertEqual(migrated.schemaVersion, SmartCartPersistedState.currentSchemaVersion)
        XCTAssertNil(migrated.walmartWishlistReference)
        XCTAssertEqual(migrated.shoppingItems, state.shoppingItems)
    }

    func testSchema4MigratesWishlistAndStartsWithNoShoppingSessions() throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("state.json")
        let store = JSONSmartCartStateStore(fileURL: fileURL)
        var state = try makeState()
        state.walmartWishlistReference = WalmartWishlistReference(
            displayName: "SmartCart Groceries",
            sharedURL: URL(string: "https://www.walmart.com/lists/shared/WL/test")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let legacy = LegacySmartCartPersistedStateV4(
            recipes: state.recipes,
            activeRecipe: state.activeRecipe,
            desiredServings: state.desiredServings,
            preferences: state.preferences,
            featureFlags: state.featureFlags,
            storeStrategy: state.storeStrategy,
            fulfillmentMode: state.fulfillmentMode,
            selectedStoreIDs: state.selectedStoreIDs,
            zipCode: state.zipCode,
            pickupDay: state.pickupDay,
            pickupTime: state.pickupTime,
            shoppingItems: state.shoppingItems,
            guidedIndex: state.guidedIndex,
            savedLists: state.savedLists,
            preferredDeliveryPartnerName: state.preferredDeliveryPartnerName,
            pantryInventory: state.pantryInventory,
            preferredProductIDsByIngredient: state.preferredProductIDsByIngredient,
            analyticsEvents: state.analyticsEvents,
            walmartWishlistReference: state.walmartWishlistReference
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(to: fileURL, options: .atomic)

        let migrated = try XCTUnwrap(store.load())

        XCTAssertEqual(migrated.schemaVersion, SmartCartPersistedState.currentSchemaVersion)
        XCTAssertEqual(migrated.walmartWishlistReference, state.walmartWishlistReference)
        XCTAssertTrue(migrated.shoppingSessions.isEmpty)
    }

    @MainActor
    func testFutureSchemaIsPreservedAndNeverOverwrittenByOlderBuild() throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("state.json")
        let original = Data(#"{"schemaVersion":999,"future":"keep-me"}"#.utf8)
        try original.write(to: fileURL, options: .atomic)
        let store = JSONSmartCartStateStore(fileURL: fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? SmartCartStateStoreError, .unsupportedSchema(999))
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), original)

        let model = AppModel(stateStore: store)
        XCTAssertNotNil(model.persistenceIssue)
        model.persistNow()
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).allSatisfy { !$0.lastPathComponent.contains("corrupt-") }
        )
    }

    func testCorruptPersistenceIsQuarantined() throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("state.json")
        try Data("not json".utf8).write(to: fileURL)
        let store = JSONSmartCartStateStore(fileURL: fileURL)

        XCTAssertNil(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(backups.contains { $0.lastPathComponent.contains("corrupt-") })
    }

    func testManifestPreservesStoreQuantityAndTimestamps() throws {
        let state = try makeState()
        let manifest = try state.savedLists.firstUnwrapped().manifest

        XCTAssertEqual(manifest.storeID, "walmart-5206")
        XCTAssertEqual(manifest.items.first?.purchaseQuantity, 2)
        XCTAssertLessThanOrEqual(manifest.createdAt, manifest.updatedAt)
        XCTAssertEqual(manifest.items.first?.product.storeID, manifest.storeID)
    }

    func testRetailerHandoffUsesTruthfulGuidedModeAndCapabilities() async throws {
        let service = DemoWalmartCatalogService()
        let manifest = try makeState().savedLists.firstUnwrapped().manifest

        XCTAssertTrue(service.capabilities.contains(.exactProductLinks))
        XCTAssertTrue(service.capabilities.contains(.guidedProductHandoff))
        XCTAssertFalse(service.capabilities.contains(.cartCreation))
        XCTAssertFalse(service.capabilities.contains(.wishlist))

        let handoff = try await service.createHandoff(manifest: manifest)
        XCTAssertEqual(handoff.mode, .guidedProducts)
        XCTAssertTrue(handoff.disclosure.contains("did not transfer a cart"))
    }

    func testUnsupportedPriceRefreshThrowsCapabilityError() async throws {
        let service = DemoWalmartCatalogService()
        let product = try exactProducts(for: "Penne pasta", unit: "oz").firstUnwrapped()

        do {
            _ = try await service.refresh(product: product)
            XCTFail("Expected unsupported capability")
        } catch let error as RetailerServiceError {
            XCTAssertEqual(error, .unsupportedCapability("Live price refresh"))
        }
    }

    func testTargetAdapterUsesExactOfficialProductDestinations() async throws {
        let service = DemoTargetCatalogService()
        let request = RetailerProductSearchRequest(
            ingredient: Ingredient(name: "Penne pasta", quantity: 16, unit: "oz"),
            retailerID: "target",
            requestedQuantity: 16,
            requestedUnit: "oz",
            storeID: "target-online",
            fulfillmentMethod: .pickup
        )

        let products = try await service.searchProducts(for: request)
        let product = try products.firstUnwrapped()

        XCTAssertEqual(service.retailer, .target)
        XCTAssertEqual(product.retailerID, "target")
        XCTAssertEqual(product.storeID, "target-online")
        XCTAssertEqual(product.retailerProductID, "13156215")
        XCTAssertEqual(product.exactURL.host, "www.target.com")
        XCTAssertEqual(product.exactURL.path, "/p/-/A-13156215")
        XCTAssertEqual(product.linkKind, .exactProduct)
        XCTAssertEqual(product.dataSource, .manualVerification)
        XCTAssertEqual(product.availability, .unknown)
        XCTAssertTrue(product.fulfillmentMethods.isEmpty)
        XCTAssertTrue(product.priceDisclosure.localizedCaseInsensitiveContains("last-known"))
        XCTAssertTrue(product.priceDisclosure.localizedCaseInsensitiveContains("not live"))
    }

    func testTargetAdapterContractAndHandoffMatchRegistry() async throws {
        let service = DemoTargetCatalogService()
        let profile = try XCTUnwrap(RetailConnectorRegistry.profile(id: "target"))
        let manifest = try makeState().savedLists.firstUnwrapped().manifest

        XCTAssertEqual(profile.state, .demoReady)
        XCTAssertEqual(profile.capabilities, service.capabilities)
        XCTAssertFalse(service.capabilities.contains(.cartCreation))
        XCTAssertFalse(service.capabilities.contains(.pickup))
        XCTAssertFalse(service.capabilities.contains(.delivery))

        let handoff = try await service.createHandoff(manifest: manifest)
        XCTAssertEqual(handoff.retailerID, "target")
        XCTAssertEqual(handoff.mode, .guidedProducts)
        XCTAssertEqual(handoff.url, URL(string: "https://www.target.com/lists"))
        XCTAssertTrue(handoff.disclosure.contains("did not transfer a cart"))
    }

    func testTargetSearchFallbackEncodesPreferencesWithoutInventingClaims() {
        var preferences = ShoppingPreferences()
        preferences.organicPolicy = .only
        preferences.dietaryRestrictions = [.glutenFree]

        let fallback = DemoTargetCatalogService.searchFallback(
            for: Ingredient(name: "Dragon fruit jam"),
            storeID: "target-online",
            preferences: preferences
        )

        XCTAssertEqual(fallback.retailerID, "target")
        XCTAssertEqual(fallback.storeID, "target-online")
        XCTAssertEqual(fallback.linkKind, .searchResults)
        XCTAssertEqual(fallback.dataSource, .searchFallback)
        XCTAssertEqual(fallback.organicStatus, .unknown)
        XCTAssertTrue(fallback.dietaryAttributes.isEmpty)
        XCTAssertNil(fallback.observedPrice)
        XCTAssertTrue(fallback.exactURL.absoluteString.localizedCaseInsensitiveContains("organic"))
        XCTAssertTrue(fallback.exactURL.absoluteString.localizedCaseInsensitiveContains("gluten"))
        XCTAssertEqual(fallback.exactURL.host, "www.target.com")
    }

    func testMatcherRejectsCrossRetailerProductsButAllowsUnknownFulfillment() {
        let ingredient = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let products = DemoTargetCatalogService.seededProducts(
            for: ingredient,
            storeID: "target-online"
        )
        let targetRequest = RetailerProductSearchRequest(
            ingredient: ingredient,
            retailerID: "target",
            requestedQuantity: 16,
            requestedUnit: "oz",
            storeID: "target-online",
            fulfillmentMethod: .pickup
        )
        let walmartRequest = RetailerProductSearchRequest(
            ingredient: ingredient,
            retailerID: "walmart",
            requestedQuantity: 16,
            requestedUnit: "oz",
            storeID: "target-online",
            fulfillmentMethod: .pickup
        )

        XCTAssertFalse(
            RetailerProductMatcher.rank(
                products,
                for: targetRequest,
                preferences: ShoppingPreferences()
            ).isEmpty
        )
        XCTAssertTrue(
            RetailerProductMatcher.rank(
                products,
                for: walmartRequest,
                preferences: ShoppingPreferences()
            ).isEmpty
        )
    }

    func testRetailerGuideEngineRejectsMismatchedAdapterRegistration() {
        let engine = RetailerGuideEngine(
            adapters: [.walmart: DemoTargetCatalogService()]
        )

        XCTAssertFalse(engine.supports(.walmart))
        XCTAssertNil(engine.adapter(for: .walmart))
    }

    func testRetailConnectorRegistryIsCredentialTruthful() async throws {
        XCTAssertEqual(RetailConnectorRegistry.profiles.count, 6)
        let walmart = try XCTUnwrap(RetailConnectorRegistry.profile(id: "walmart"))
        XCTAssertEqual(walmart.state, .demoReady)
        XCTAssertFalse(walmart.supportsCart)
        XCTAssertFalse(walmart.supportsWishlist)

        let target = try XCTUnwrap(RetailConnectorRegistry.profile(id: "target"))
        XCTAssertEqual(target.state, .demoReady)
        XCTAssertTrue(target.supportsLookup)
        XCTAssertFalse(target.supportsCart)
        XCTAssertFalse(target.supportsDelivery)

        let instacart = try XCTUnwrap(RetailConnectorRegistry.profile(id: "instacart"))
        let connector = CredentialFreeRetailConnector(profile: instacart)
        do {
            _ = try await connector.searchProducts(for: searchRequest(for: "Garlic", unit: "clove"))
            XCTFail("Credential-free connector must not pretend a live catalog exists")
        } catch let error as RetailerServiceError {
            guard case .unsupportedCapability(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("without approved credentials"))
        }
    }

    func testOfflineBarcodeCatalogMatchesKnownUPCAndRejectsUnknown() {
        let pasta = OfflineBarcodeCatalog.lookup(upc: "078742002166")
        XCTAssertEqual(pasta?.name, "Penne Pasta")
        XCTAssertEqual(pasta?.retailerProductID, "10534084")
        XCTAssertNil(OfflineBarcodeCatalog.lookup(upc: "000000000000"))
    }

    @MainActor
    func testManualReplacementAndPreferencesSurviveRelaunch() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, seedDemoShoppingState: true)
        var updatedPreferences = model.preferences
        updatedPreferences.organicPolicy = .only
        updatedPreferences.dietaryRestrictions = [.glutenFree]
        model.preferences = updatedPreferences

        let item = try model.shoppingItems.first(where: { !$0.alternatives.isEmpty }).firstUnwrapped()
        let replacementID = try item.alternatives.firstUnwrapped().id
        model.selectAlternative(itemID: item.id, candidateID: replacementID)
        let selectedProductID = try model.shoppingItems
            .first(where: { $0.id == item.id })
            .firstUnwrapped()
            .product
            .retailerProductID
        model.saveCurrentList()
        model.persistNow()

        let restored = AppModel(stateStore: store)

        XCTAssertEqual(restored.preferences, updatedPreferences)
        XCTAssertEqual(
            restored.shoppingItems.first(where: { $0.id == item.id })?.product.retailerProductID,
            selectedProductID
        )
        XCTAssertFalse(restored.savedLists.isEmpty)
    }

    @MainActor
    func testUnavailableProductSubstitutionSurvivesRelaunch() throws {
        var state = try makeState()
        let candidates = exactProducts(for: "Penne pasta", unit: "oz")
        var unavailable = try candidates.firstUnwrapped()
        unavailable.availability = .outOfStock
        let replacement = try XCTUnwrap(candidates.dropFirst().first)
        state.shoppingItems[0].product = unavailable
        state.shoppingItems[0].alternatives = [replacement]

        let store = InMemorySmartCartStateStore(state: state)
        let model = AppModel(stateStore: store)
        model.selectAlternative(
            itemID: state.shoppingItems[0].id,
            candidateID: replacement.id
        )
        model.persistNow()

        let restored = AppModel(stateStore: store)
        let restoredItem = try restored.shoppingItems.firstUnwrapped()

        XCTAssertEqual(restoredItem.product.retailerProductID, replacement.retailerProductID)
        XCTAssertNotEqual(restoredItem.product.availability, .outOfStock)
        XCTAssertTrue(
            restoredItem.alternatives.contains {
                $0.retailerProductID == unavailable.retailerProductID &&
                $0.availability == .outOfStock
            }
        )
    }

    @MainActor
    func testCompleteSavedFlowRestoresAcrossRelaunch() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, seedDemoShoppingState: true)
        var updatedPreferences = model.preferences
        updatedPreferences.organicPolicy = .only
        updatedPreferences.budgetPriority = .qualityFirst
        model.preferences = updatedPreferences
        model.desiredServings = 6
        model.zipCode = "10001"
        model.pickupDay = "Tomorrow"
        model.pickupTime = "6:30–7:30 PM"
        model.markCurrentGuidedItem(.added)
        model.saveCurrentList()
        model.persistNow()

        let restored = AppModel(stateStore: store)

        XCTAssertEqual(restored.activeRecipe.id, model.activeRecipe.id)
        XCTAssertEqual(restored.activeRecipe.ingredients, model.activeRecipe.ingredients)
        XCTAssertEqual(restored.preferences, updatedPreferences)
        XCTAssertEqual(restored.desiredServings, 6)
        XCTAssertEqual(restored.zipCode, "10001")
        XCTAssertEqual(restored.selectedPickupSummary, "Tomorrow, 6:30–7:30 PM")
        XCTAssertEqual(restored.shoppingItems.first?.status, .added)
        XCTAssertEqual(restored.savedLists.first?.manifest.items.first?.status, .added)
        XCTAssertEqual(restored.savedLists.first?.manifest.storeID, restored.primaryStore.retailerStoreID)
    }

    @MainActor
    func testPantryBarcodePreferencesAndAnalyticsSurviveRelaunch() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store)
        model.addPantryItem(upc: "078742002166")
        model.track(.retailerLinkOpened, properties: ["retailer": "walmart", "upc": "secret"])
        model.persistNow()

        let restored = AppModel(stateStore: store)

        XCTAssertEqual(restored.pantryInventory.first?.name, "Penne Pasta")
        XCTAssertEqual(restored.pantryInventory.first?.preferredRetailerProductID, "10534084")
        XCTAssertTrue(restored.analyticsEvents.contains { $0.name == .barcodeScanned })
        XCTAssertFalse(restored.analyticsEvents.contains { $0.properties["upc"] != nil })
    }

    func testRedVelvetRegressionFixturePreservesTwentyIngredientsAndSections() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Recipes/red-velvet-20.txt")
        let text = try String(contentsOf: fixtureURL, encoding: .utf8)
        let recipe = RecipeParser.parse(title: "Red Velvet Cake", text: text)

        XCTAssertEqual(recipe.ingredients.count, 20)
        XCTAssertEqual(Set(recipe.ingredients.compactMap(\.sectionName)), ["Cake", "Filling", "Frosting"])
        XCTAssertEqual(recipe.ingredients.first?.equivalentMeasurements?.first?.quantity, 300)
        XCTAssertEqual(recipe.ingredients.first?.brandNote, "King Arthur preferred")
        let cream = try recipe.ingredients.first(where: { $0.name.localizedCaseInsensitiveContains("Heavy Cream") }).firstUnwrapped()
        XCTAssertEqual(cream.quantity, 0.375, accuracy: 0.001)
        XCTAssertEqual(cream.compoundMeasurements?.count, 2)
        XCTAssertNotNil(recipe.ingredients.first(where: { $0.alternativeGroup != nil }))
    }

    func testMalformedFractionRemainsReviewRequired() throws {
        let recipe = RecipeParser.parse(title: "Needs Review", text: "1/? cup flour")
        let ingredient = try recipe.ingredients.firstUnwrapped()
        XCTAssertEqual(ingredient.confidence, .review)
        XCTAssertEqual(ingredient.quantityReviewRequired, true)
        XCTAssertEqual(ingredient.rawText, "1/? cup flour")
    }

    func testOCRFixtureReconstructsColumnsAndStopsAtInstructions() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/OCR/two_column_chocolate_chip_observations.json")
        let data = try Data(contentsOf: fixtureURL)
        let observations = try JSONDecoder().decode([OCRTextObservation].self, from: data)
        let result = OCRLayoutReconstructor.reconstruct(observations)

        XCTAssertEqual(result.detectedColumnCount, 2)
        XCTAssertEqual(result.ingredientLines.count, 5)
        XCTAssertEqual(result.ignoredInstructionLines.count, 3)
        XCTAssertGreaterThan(result.layoutConfidence, 0.9)
        let expectedURL = fixtureURL.deletingLastPathComponent()
            .appendingPathComponent("two_column_chocolate_chip_expected.txt")
        let expected = try String(contentsOf: expectedURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(result.reconstructedText, expected)
        XCTAssertEqual(result.ingredientSourceLines.count, result.ingredientLines.count)
        XCTAssertTrue(result.ingredientSourceLines.allSatisfy { $0.boundingBox.isUsable })
    }

    func testChocolateChipCookieBarsGoldenVisionObservationsReconstructAndParse() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/OCR/chocolate_chip_cookie_bars_vision_observations.json")
        let observations = try JSONDecoder().decode(
            [OCRTextObservation].self,
            from: Data(contentsOf: fixtureURL)
        )

        XCTAssertEqual(observations.count, 16)
        XCTAssertEqual(Set(observations.compactMap(\.observationID)).count, observations.count)

        let reconstruction = OCRLayoutReconstructor.reconstruct(observations)

        XCTAssertEqual(reconstruction.suggestedTitle, "Chocolate Chip Cookie Bars")
        XCTAssertEqual(reconstruction.ingredientLines.count, 5)
        XCTAssertEqual(reconstruction.ingredientSourceLines.count, 5)
        XCTAssertFalse(reconstruction.ingredientLines.contains {
            $0.localizedCaseInsensitiveContains("cookie bars")
        })

        let butterSource = try reconstruction.ingredientSourceLines.first(where: {
            $0.text.localizedCaseInsensitiveContains("unsalted butter")
        }).firstUnwrapped()
        XCTAssertEqual(butterSource.columnIndex, 0)
        XCTAssertEqual(
            butterSource.sourceObservationIDs,
            ["cookie-bars-ingredient-combined-butter-chocolate"]
        )
        XCTAssertFalse(butterSource.continuationAttached)
        XCTAssertTrue(butterSource.boundingBox.isUsable)
        XCTAssertGreaterThan(butterSource.reconstructionConfidence, 0)
        XCTAssertLessThanOrEqual(butterSource.reconstructionConfidence, 1)

        let chocolateSource = try reconstruction.ingredientSourceLines.first(where: {
            $0.text.localizedCaseInsensitiveContains("chocolate chips")
        }).firstUnwrapped()
        XCTAssertEqual(chocolateSource.columnIndex, 1)
        XCTAssertEqual(
            chocolateSource.sourceObservationIDs,
            [
                "cookie-bars-ingredient-combined-butter-chocolate",
                "cookie-bars-ingredient-chocolate-chips-continuation"
            ]
        )
        XCTAssertTrue(chocolateSource.continuationAttached)
        XCTAssertTrue(chocolateSource.boundingBox.isUsable)
        XCTAssertLessThanOrEqual(chocolateSource.boundingBox.minX, 0.531250)
        XCTAssertGreaterThanOrEqual(chocolateSource.boundingBox.maxX, 0.593750)
        XCTAssertGreaterThan(chocolateSource.reconstructionConfidence, 0)
        XCTAssertLessThanOrEqual(chocolateSource.reconstructionConfidence, 1)

        let recipe = RecipeParser.parse(
            title: try reconstruction.suggestedTitle.firstUnwrapped(),
            text: reconstruction.reconstructedText,
            source: .photo,
            sourceLines: reconstruction.ingredientSourceLines
        )

        XCTAssertEqual(recipe.title, "Chocolate Chip Cookie Bars")
        XCTAssertEqual(recipe.ingredients.count, 5)

        let butter = try recipe.ingredients.first(where: {
            $0.name.localizedCaseInsensitiveContains("unsalted butter")
        }).firstUnwrapped()
        XCTAssertEqual(butter.quantity, 1.5, accuracy: 0.001)
        XCTAssertEqual(butter.unit, "cup")
        XCTAssertEqual(butter.preparation.lowercased(), "melted")

        let brownSugar = try recipe.ingredients.first(where: {
            $0.name.localizedCaseInsensitiveContains("brown sugar")
        }).firstUnwrapped()
        XCTAssertEqual(brownSugar.quantity, 1, accuracy: 0.001)
        XCTAssertFalse(brownSugar.name.localizedCaseInsensitiveContains("chips"))

        let egg = try recipe.ingredients.first(where: {
            $0.name.localizedCaseInsensitiveContains("egg")
        }).firstUnwrapped()
        XCTAssertEqual(egg.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(egg.unit, "large")

        let vanilla = try recipe.ingredients.first(where: {
            $0.name.localizedCaseInsensitiveContains("vanilla extract")
        }).firstUnwrapped()
        XCTAssertEqual(vanilla.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(vanilla.unit, "tsp")

        let chocolate = try recipe.ingredients.first(where: {
            $0.name.localizedCaseInsensitiveContains("semi-sweet chocolate chips")
        }).firstUnwrapped()
        XCTAssertEqual(chocolate.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(chocolate.unit, "cup")

        XCTAssertFalse(recipe.ingredients.contains {
            $0.name.localizedCaseInsensitiveContains("cookie bars")
        })
        XCTAssertFalse(recipe.ingredients.contains {
            $0.name.localizedCaseInsensitiveContains("brown sugar chips")
        })
    }

    func testChocolateChipCookieBarsExactJPEGEndToEndVisionImport() async throws {
        let imageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/OCR/chocolate_chip_cookie_bars_exact.jpeg")
        let image = try UIImage(contentsOfFile: imageURL.path).firstUnwrapped()

        let result = try await RecipeVisionReader.recognizeText(in: [image])

        XCTAssertEqual(result.suggestedTitle, "Chocolate Chip Cookie Bars")
        XCTAssertEqual(result.pageCount, 1)
        XCTAssertEqual(result.sourceLines.count, 5)
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("unsalted butter"))
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("semi-sweet chocolate chips"))
        XCTAssertFalse(result.text.localizedCaseInsensitiveContains("instructions"))
        XCTAssertGreaterThan(result.confidence, 0)
        XCTAssertGreaterThan(result.layoutConfidence, 0)

        let recipe = RecipeParser.parse(
            title: try result.suggestedTitle.firstUnwrapped(),
            text: result.text,
            source: .photo,
            sourceLines: result.sourceLines
        )

        XCTAssertEqual(recipe.title, "Chocolate Chip Cookie Bars")
        XCTAssertEqual(recipe.ingredients.count, 5)
        XCTAssertTrue(recipe.ingredients.contains {
            $0.name.localizedCaseInsensitiveContains("unsalted butter")
                && abs($0.quantity - 1.5) < 0.001
        })
        XCTAssertTrue(recipe.ingredients.contains {
            $0.name.localizedCaseInsensitiveContains("brown sugar")
        })
        XCTAssertTrue(recipe.ingredients.contains {
            $0.name.localizedCaseInsensitiveContains("egg") && $0.unit == "large"
        })
        XCTAssertTrue(recipe.ingredients.contains {
            $0.name.localizedCaseInsensitiveContains("vanilla extract")
        })
        XCTAssertTrue(recipe.ingredients.contains {
            $0.name.localizedCaseInsensitiveContains("semi-sweet chocolate chips")
        })
        XCTAssertFalse(recipe.ingredients.contains {
            $0.name.localizedCaseInsensitiveContains("cookie bars")
                || $0.name.localizedCaseInsensitiveContains("brown sugar chips")
        })
    }

    func testParserNeverInventsFallbackGroceriesForFailedImports() {
        for source in [RecipeSource.photo, .text, .link] {
            let recipe = RecipeParser.parse(
                title: "Unreadable",
                text: "Instructions\nMix until smooth\nBake for 20 minutes",
                source: source
            )
            XCTAssertTrue(recipe.ingredients.isEmpty, "Failed \(source.rawValue) imports must stay empty")
        }
    }

    func testSpanningInstructionHeadingStopsEveryColumnAtPageLevel() {
        let observations = [
            OCRTextObservation(text: "1 cup flour", boundingBox: .init(x: 0.05, y: 0.82, width: 0.30, height: 0.05), confidence: 0.95),
            OCRTextObservation(text: "2 eggs", boundingBox: .init(x: 0.58, y: 0.82, width: 0.24, height: 0.05), confidence: 0.95),
            OCRTextObservation(text: "1 tsp salt", boundingBox: .init(x: 0.05, y: 0.70, width: 0.30, height: 0.05), confidence: 0.94),
            OCRTextObservation(text: "1 cup sugar", boundingBox: .init(x: 0.58, y: 0.70, width: 0.28, height: 0.05), confidence: 0.94),
            OCRTextObservation(text: "INSTRUCTIONS", boundingBox: .init(x: 0.08, y: 0.56, width: 0.80, height: 0.06), confidence: 0.99),
            OCRTextObservation(text: "Mix the flour and eggs", boundingBox: .init(x: 0.05, y: 0.43, width: 0.38, height: 0.05), confidence: 0.94),
            OCRTextObservation(text: "Bake for 20 minutes", boundingBox: .init(x: 0.58, y: 0.43, width: 0.34, height: 0.05), confidence: 0.94)
        ]

        let result = OCRLayoutReconstructor.reconstruct(observations)

        XCTAssertEqual(result.ingredientLines.count, 4)
        XCTAssertFalse(result.ingredientLines.contains { $0.localizedCaseInsensitiveContains("bake") })
        XCTAssertTrue(result.ignoredInstructionLines.contains { $0 == "INSTRUCTIONS" })
        XCTAssertTrue(result.ignoredInstructionLines.contains { $0.localizedCaseInsensitiveContains("mix") })
    }

    func testOCRAlternativesAndGeometryReachIngredientReviewEvidence() throws {
        let observation = OCRTextObservation(
            text: "2 cups flour",
            boundingBox: .init(x: 0.12, y: 0.66, width: 0.52, height: 0.07),
            confidence: 0.68,
            pageIndex: 1,
            alternateCandidates: [
                OCRTextAlternative(text: "12 cups flour", confidence: 0.64)
            ]
        )
        let reconstruction = OCRLayoutReconstructor.reconstruct([observation])
        let recipe = RecipeParser.parse(
            title: "Evidence",
            text: reconstruction.reconstructedText,
            source: .photo,
            sourceLines: reconstruction.ingredientSourceLines
        )
        let ingredient = try recipe.ingredients.firstUnwrapped()
        let evidence = try ingredient.sourceEvidence.firstUnwrapped()
        let box = try evidence.boundingBox.firstUnwrapped()
        let ocrConfidence = try evidence.ocrConfidence.firstUnwrapped()

        XCTAssertEqual(evidence.pageIndex, 1)
        XCTAssertEqual(box.x, 0.12, accuracy: 0.0001)
        XCTAssertEqual(ocrConfidence, 0.68, accuracy: 0.0001)
        XCTAssertEqual(evidence.alternateSourceTexts, ["12 cups flour"])
        XCTAssertEqual(evidence.alternateQuantityCandidates, [2, 12])
        XCTAssertEqual(ingredient.confidence, .review)
        XCTAssertEqual(ingredient.quantityReviewRequired, true)
    }

    func testCorrectedOCRTextRetainsUnambiguousOriginalEvidence() throws {
        let sourceLine = OCRSourceLine(
            text: "1O oz flour",
            pageIndex: 2,
            boundingBox: .init(x: 0.18, y: 0.62, width: 0.44, height: 0.06),
            confidence: 0.61,
            alternateCandidates: []
        )

        let recipe = RecipeParser.parse(
            title: "Corrected Evidence",
            text: "10 oz flour",
            source: .photo,
            sourceLines: [sourceLine]
        )
        let ingredient = try recipe.ingredients.firstUnwrapped()
        let evidence = try ingredient.sourceEvidence.firstUnwrapped()

        XCTAssertEqual(ingredient.quantity, 10, accuracy: 0.001)
        XCTAssertEqual(evidence.rawText, "1O oz flour")
        XCTAssertEqual(evidence.pageIndex, 2)
        XCTAssertEqual(evidence.boundingBox?.x, 0.18)
        XCTAssertEqual(evidence.ocrConfidence, 0.61)
        XCTAssertEqual(ingredient.confidence, .review)
    }

    func testCorrectedOCRTextDoesNotGuessBetweenAmbiguousSourceLines() throws {
        let sourceLines = [
            OCRSourceLine(
                text: "1 cup brown sugar",
                pageIndex: 0,
                boundingBox: .init(x: 0.1, y: 0.7, width: 0.4, height: 0.05),
                confidence: 0.9,
                alternateCandidates: []
            ),
            OCRSourceLine(
                text: "1 cup white sugar",
                pageIndex: 1,
                boundingBox: .init(x: 0.1, y: 0.5, width: 0.4, height: 0.05),
                confidence: 0.9,
                alternateCandidates: []
            )
        ]

        let recipe = RecipeParser.parse(
            title: "Ambiguous Evidence",
            text: "1 cup sugar",
            source: .photo,
            sourceLines: sourceLines
        )
        let evidence = try recipe.ingredients.firstUnwrapped().sourceEvidence.firstUnwrapped()

        XCTAssertEqual(evidence.rawText, "1 cup sugar")
        XCTAssertNil(evidence.pageIndex)
        XCTAssertNil(evidence.boundingBox)
    }

    func testOCRVocabularyIsBoundedAndCriticalLinesPreserveAlternatives() {
        let contextual = (0..<150).map { "PantryItem\($0)" }
        let words = RecipeOCRPolicy.boundedCustomWords(contextual)

        XCTAssertLessThanOrEqual(words.count, RecipeOCRPolicy.maximumCustomWordCount)
        XCTAssertTrue(words.contains("gochujang"))
        XCTAssertTrue(words.contains("tbsp"))
        XCTAssertTrue(RecipeOCRPolicy.shouldPreserveAlternatives(in: "1/2 cup cream", confidence: 0.95))
        XCTAssertTrue(RecipeOCRPolicy.shouldPreserveAlternatives(in: "mascarpone", confidence: 0.60))
        XCTAssertFalse(RecipeOCRPolicy.shouldPreserveAlternatives(in: "fresh parsley", confidence: 0.95))
        XCTAssertEqual(RecipeOCRPolicy.leadingBulletMarker(in: "• 2 cups flour"), "•")
        XCTAssertNil(RecipeOCRPolicy.leadingBulletMarker(in: "2 cups flour"))
        XCTAssertTrue(
            RecipeOCRPolicy.shouldRunEnhancedPass(
                confidence: 0.70,
                layoutConfidence: 0.95,
                ambiguityCount: 0,
                sourceLineCount: 8
            )
        )
        XCTAssertFalse(
            RecipeOCRPolicy.shouldRunEnhancedPass(
                confidence: 0.92,
                layoutConfidence: 0.94,
                ambiguityCount: 0,
                sourceLineCount: 8
            )
        )
        XCTAssertGreaterThan(
            RecipeOCRPolicy.qualityScore(
                confidence: 0.92,
                layoutConfidence: 0.94,
                ambiguityCount: 0,
                sourceLineCount: 8
            ),
            RecipeOCRPolicy.qualityScore(
                confidence: 0.65,
                layoutConfidence: 0.60,
                ambiguityCount: 2,
                sourceLineCount: 2
            )
        )
    }

    func testBarcodeNormalizationPreservesLeadingZerosAndValidatesGTINs() throws {
        for code in ["0762111380135", "0785357023567"] {
            let result = BarcodeNormalizer.normalize(BarcodeScan(rawBarcode: code, rawSymbology: "ean13"))
            guard case .success(let barcode) = result else { return XCTFail("Expected valid barcode \(code)") }
            XCTAssertEqual(barcode.digits, code)
            XCTAssertEqual(barcode.format, .ean13)
            XCTAssertEqual(barcode.canonicalGTIN14, "0\(code)")
        }
    }

    func testSchemaV2MigratesInferredBarcodeNamesWithoutLosingBarcode() throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("state.json")
        let state = try makeState()
        let legacy = LegacySmartCartPersistedStateV2(
            recipes: state.recipes,
            activeRecipe: state.activeRecipe,
            desiredServings: state.desiredServings,
            preferences: state.preferences,
            featureFlags: state.featureFlags,
            storeStrategy: state.storeStrategy,
            fulfillmentMode: state.fulfillmentMode,
            selectedStoreIDs: state.selectedStoreIDs,
            zipCode: state.zipCode,
            pickupDay: state.pickupDay,
            pickupTime: state.pickupTime,
            shoppingItems: state.shoppingItems,
            guidedIndex: state.guidedIndex,
            savedLists: state.savedLists,
            preferredDeliveryPartnerName: state.preferredDeliveryPartnerName,
            pantryInventory: [
                PantryInventoryItem(
                    upc: "0785357023567",
                    name: "Scanned item 3567",
                    brand: "Unmatched UPC",
                    source: .barcode
                )
            ],
            preferredProductIDsByIngredient: state.preferredProductIDsByIngredient,
            analyticsEvents: state.analyticsEvents
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(to: fileURL)

        let migrated = try JSONSmartCartStateStore(fileURL: fileURL).load()
        XCTAssertEqual(migrated?.schemaVersion, SmartCartPersistedState.currentSchemaVersion)
        XCTAssertEqual(migrated?.pantryInventory.first?.name, "Unknown Product")
        XCTAssertEqual(migrated?.pantryInventory.first?.upc, "0785357023567")
        XCTAssertEqual(migrated?.pantryInventory.first?.requiresUserNaming, true)
    }

    @MainActor
    func testImportedRecipeSuggestsPantryWithoutSilentlySkippingAndSupportsRemainder() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.pantryInventory = [
            PantryInventoryItem(
                name: "All-purpose flour",
                quantity: 1,
                unit: "bag",
                packageSize: 1,
                packageUnit: "cup"
            )
        ]
        let recipe = RecipeParser.parse(title: "Cookies", text: "2 cups all-purpose flour")
        model.beginRecipe(recipe)

        let imported = try model.activeRecipe.ingredients.firstUnwrapped()
        XCTAssertEqual(imported.pantrySuggestion?.coverage, .partial)
        XCTAssertEqual(imported.pantryDecision, .review)
        XCTAssertEqual(model.quantityToBuy(for: imported), 2, accuracy: 0.001, "Unreviewed matches must buy the full amount")

        model.setPantryDecision(.useAvailable, for: imported.id)
        let confirmed = try model.activeRecipe.ingredients.firstUnwrapped()
        XCTAssertEqual(model.quantityToBuy(for: confirmed), 1, accuracy: 0.001)

        model.setPantryDecision(.buyFull, for: imported.id)
        let overridden = try model.activeRecipe.ingredients.firstUnwrapped()
        XCTAssertEqual(model.quantityToBuy(for: overridden), 2, accuracy: 0.001)
    }

    @MainActor
    func testBulkUsePantryAllocatesOneSharedStockAmountAcrossDuplicateIngredients() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.pantryInventory = [
            PantryInventoryItem(name: "All-purpose flour", remainingAmount: 1, remainingUnit: "cup")
        ]
        let recipe = Recipe(
            title: "Two-Part Bake",
            source: .text,
            sourceDetail: "Test",
            heroSymbol: "fork.knife",
            servings: 1,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: [
                Ingredient(name: "All-purpose flour", quantity: 1, unit: "cup"),
                Ingredient(name: "All-purpose flour", quantity: 1, unit: "cup")
            ]
        )
        model.beginRecipe(recipe)

        XCTAssertEqual(
            model.activeRecipe.ingredients.reduce(0) { $0 + model.quantityToBuy(for: $1) },
            2,
            accuracy: 0.001,
            "Suggestions must buy full until Use Pantry is explicit"
        )

        model.useSafePantrySuggestions()

        let required = model.activeRecipe.ingredients.reduce(0) { $0 + model.scaledQuantity(for: $1) }
        let quantityToBuy = model.activeRecipe.ingredients.reduce(0) { $0 + model.quantityToBuy(for: $1) }
        XCTAssertEqual(required, 2, accuracy: 0.001)
        XCTAssertEqual(quantityToBuy, 1, accuracy: 0.001)
        XCTAssertEqual(required - quantityToBuy, 1, accuracy: 0.001)
        XCTAssertTrue(model.activeRecipe.ingredients.allSatisfy { model.quantityToBuy(for: $0) >= 0 })
    }

    @MainActor
    func testPantryAutocompleteAndCaseInsensitiveNameMerge() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.pantryInventory = [
            PantryInventoryItem(name: "Flour", quantity: 2, unit: "bag"),
            PantryInventoryItem(name: "Olive oil", quantity: 1, unit: "bottle")
        ]

        XCTAssertEqual(model.pantryNameSuggestions(for: "Fl").map(\.name), ["Flour"])

        model.addPantryStock(name: "flour", amount: 1.5)

        XCTAssertEqual(model.pantryInventory.count, 2)
        let merged = try model.pantryItem(named: "FLOUR").firstUnwrapped()
        XCTAssertEqual(merged.quantity, 3.5, accuracy: 0.001)
    }

    func testLegacyPantryItemDecodingDerivesExplicitPackageAndRemainingFields() throws {
        let legacy = PantryInventoryItem(
            name: "Flour",
            quantity: 2,
            unit: "bag",
            packageSize: 5,
            packageUnit: "lb"
        )
        let encoded = try JSONEncoder().encode(legacy)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "packageCount")
        object.removeValue(forKey: "remainingAmount")
        object.removeValue(forKey: "remainingUnit")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(PantryInventoryItem.self, from: legacyData)

        XCTAssertEqual(decoded.packageCount, 2, accuracy: 0.001)
        XCTAssertEqual(decoded.remainingAmount, 10, accuracy: 0.001)
        XCTAssertEqual(decoded.remainingUnit, "lb")
        XCTAssertEqual(decoded.quantity, decoded.packageCount)
    }

    func testPantryMatchingUsesRemainingAmountInsteadOfFullPackageCapacity() throws {
        let ingredient = Ingredient(name: "Flour", quantity: 8, unit: "oz")
        let pantry = PantryInventoryItem(
            name: "Flour",
            quantity: 2,
            unit: "bag",
            packageSize: 16,
            packageUnit: "oz",
            remainingAmount: 4,
            remainingUnit: "oz"
        )

        let suggestion = try PantryMatchingService.bestSuggestion(
            for: ingredient,
            inventory: [pantry]
        ).firstUnwrapped()

        XCTAssertEqual(suggestion.coverage, .partial)
        XCTAssertEqual(suggestion.availableQuantity, 4, accuracy: 0.001)
    }

    @MainActor
    func testPantryBarcodeMergeUsesGTINBeforeDisplayName() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        let barcode: NormalizedBarcode
        switch BarcodeNormalizer.normalize("078742002163") {
        case .success(let normalized):
            barcode = normalized
        case .failure(let error):
            return XCTFail("Fixture barcode should be valid: \(error)")
        }

        model.pantryInventory = [
            PantryInventoryItem(
                upc: barcode.digits,
                name: "Pasta",
                quantity: 2,
                unit: "box",
                source: .barcode,
                gtin14: barcode.canonicalGTIN14
            )
        ]
        let submission = PantryBarcodeSubmission(
            scan: BarcodeScan(rawBarcode: barcode.digits, rawSymbology: "test"),
            barcode: barcode,
            name: "Great Value Penne",
            brand: "Great Value",
            externalProductID: "fixture",
            requiresUserNaming: false
        )

        model.addPantryStock(name: "Penne Pasta", amount: 3, submission: submission)

        XCTAssertEqual(model.pantryInventory.count, 1)
        XCTAssertEqual(model.pantryInventory[0].quantity, 5, accuracy: 0.001)
        XCTAssertEqual(model.pantryInventory[0].name, "Pasta")
    }

    @MainActor
    func testEveryScannedBarcodePersistsAndRestacksAfterRelaunch() throws {
        let store = JSONSmartCartStateStore(
            fileURL: temporaryDirectory().appendingPathComponent("barcode-state.json")
        )
        let firstBarcode: NormalizedBarcode
        let alternateBarcode: NormalizedBarcode
        switch (
            BarcodeNormalizer.normalize("078742002163"),
            BarcodeNormalizer.normalize("078742131917")
        ) {
        case (.success(let first), .success(let alternate)):
            firstBarcode = first
            alternateBarcode = alternate
        default:
            return XCTFail("Fixture barcodes should be valid")
        }

        func submission(_ barcode: NormalizedBarcode) -> PantryBarcodeSubmission {
            PantryBarcodeSubmission(
                scan: BarcodeScan(rawBarcode: barcode.digits, rawSymbology: "test"),
                barcode: barcode,
                name: "Pantry staple",
                brand: "Test",
                externalProductID: nil,
                requiresUserNaming: false
            )
        }

        let model = AppModel(stateStore: store)
        model.addPantryStock(
            name: "Pantry staple",
            amount: 1,
            submission: submission(firstBarcode)
        )
        model.addPantryStock(
            name: "Pantry staple",
            amount: 2,
            submission: submission(alternateBarcode)
        )

        let restored = AppModel(stateStore: store)
        XCTAssertEqual(restored.pantryInventory.count, 1)
        XCTAssertEqual(restored.pantryInventory[0].quantity, 3, accuracy: 0.001)
        XCTAssertEqual(
            Set(restored.pantryInventory[0].barcodeGTINs ?? []),
            Set([firstBarcode.canonicalGTIN14, alternateBarcode.canonicalGTIN14])
        )
        XCTAssertEqual(restored.pantryItem(matching: alternateBarcode)?.id, restored.pantryInventory[0].id)

        restored.addPantryStock(
            name: "A different catalog name",
            amount: 4,
            submission: submission(alternateBarcode)
        )

        let relaunchedAgain = AppModel(stateStore: store)
        XCTAssertEqual(relaunchedAgain.pantryInventory.count, 1)
        XCTAssertEqual(relaunchedAgain.pantryInventory[0].quantity, 7, accuracy: 0.001)
        XCTAssertEqual(relaunchedAgain.pantryInventory[0].name, "Pantry staple")
    }

    @MainActor
    func testWalmartSafariWorkflowIsTheOnlyRestoredPublicRoute() {
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            instacartHandoffService: RecordingInstacartHandoffService(),
            commerceDefaults: defaults
        )

        XCTAssertEqual(model.shoppingRoute, .walmartDirect)
        XCTAssertTrue(model.activeCommerceCapabilities.preparesShoppingList)
        XCTAssertFalse(model.activeCommerceCapabilities.livePricing)
        XCTAssertFalse(model.activeCommerceCapabilities.pickup)
        XCTAssertFalse(model.activeCommerceCapabilities.delivery)
        XCTAssertFalse(model.activeCommerceCapabilities.checkout)
        XCTAssertFalse(model.activeCommerceCapabilities.embeddedCheckout)

        model.instacartRetailerPreference = .aldi
        model.commerceFulfillmentPreference = .delivery
        model.recordHandoffFeedback(.savedForLater)

        let restored = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            instacartHandoffService: RecordingInstacartHandoffService(),
            commerceDefaults: defaults
        )
        XCTAssertEqual(restored.shoppingRoute, .walmartDirect)
        XCTAssertEqual(restored.instacartRetailerPreference, .aldi)
        XCTAssertEqual(restored.commerceFulfillmentPreference, .delivery)
        XCTAssertEqual(restored.latestHandoffFeedback, .savedForLater)
    }

    @MainActor
    func testPreparingWalmartSafariWorkflowPreservesHiddenLegacyPreferences() {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        model.shoppingRoute = .otherRetailerLinks
        model.featureFlags.advancedToolsEnabled = true
        model.storeStrategy = .multipleStops
        model.fulfillmentMode = .delivery
        model.selectedStoreIDs = Set(model.stores.prefix(2).map(\.id))

        model.prepareWalmartSafariWorkflow()

        XCTAssertEqual(model.selectedRetailer, .walmart)
        XCTAssertEqual(model.shoppingRoute, .otherRetailerLinks)
        XCTAssertEqual(model.storeStrategy, .multipleStops)
        XCTAssertEqual(model.fulfillmentMode, .delivery)
        XCTAssertTrue(model.featureFlags.advancedToolsEnabled)
        XCTAssertEqual(model.selectedStoreIDs, [model.primaryStore.id])
    }

    @MainActor
    func testTargetGuideSelectionMatchingAndPersistenceUseSharedWorkflow() async throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: defaults,
            seedDemoShoppingState: true
        )
        XCTAssertTrue(model.shoppingItems.allSatisfy { $0.product.retailerID == "walmart" })

        model.startRetailerGuide(.target)

        XCTAssertEqual(model.selectedRetailer, .target)
        XCTAssertEqual(model.primaryStore.retailerID, "target")
        XCTAssertTrue(model.shoppingItems.isEmpty)
        XCTAssertEqual(model.retailerConfiguration.guideLabel, "Shopping List")

        let recipe = Recipe(
            title: "Target Adapter Test",
            source: .text,
            sourceDetail: "Tests",
            heroSymbol: "fork.knife",
            servings: 2,
            prepMinutes: 5,
            cookMinutes: 10,
            ingredients: [
                Ingredient(name: "Penne pasta", quantity: 16, unit: "oz"),
                Ingredient(name: "Dragon fruit jam", quantity: 1, unit: "jar")
            ]
        )
        model.beginRecipe(recipe)
        await model.startMatching(force: true)
        model.saveCurrentList()

        XCTAssertEqual(model.shoppingItems.count, 2)
        XCTAssertTrue(model.shoppingItems.allSatisfy { $0.product.retailerID == "target" })
        XCTAssertTrue(model.shoppingItems.contains { $0.product.linkKind == .exactProduct })
        XCTAssertTrue(model.shoppingItems.contains { $0.product.linkKind == .searchResults })
        XCTAssertEqual(model.savedLists.first?.manifest.retailerID, "target")
        XCTAssertEqual(model.savedLists.first?.manifest.storeID, "target-online")

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.selectedRetailer, .target)
        XCTAssertEqual(restored.primaryStore.retailerID, "target")
        XCTAssertEqual(restored.shoppingItems.map(\.product.retailerID), ["target", "target"])
        XCTAssertEqual(restored.retailerURL().host, "www.target.com")
        XCTAssertEqual(restored.retailerListsURL().path, "/lists")
    }

    @MainActor
    func testPersistedTargetItemsOverrideMissingOrStaleRetailerDefaults() async {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(stateStore: store, commerceDefaults: defaults)
        model.startRetailerGuide(.target)
        await model.startMatching(force: true)
        XCTAssertFalse(model.shoppingItems.isEmpty)
        XCTAssertTrue(model.shoppingItems.allSatisfy { $0.product.retailerID == "target" })

        defaults.removeObject(forKey: "smartcart.commerce.selectedRetailer")
        let withoutDefault = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(withoutDefault.selectedRetailer, .target)
        XCTAssertFalse(withoutDefault.shoppingItems.isEmpty)

        defaults.set("walmart", forKey: "smartcart.commerce.selectedRetailer")
        let withStaleDefault = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(withStaleDefault.selectedRetailer, .target)
        XCTAssertTrue(withStaleDefault.shoppingItems.allSatisfy { $0.product.retailerID == "target" })
    }

    @MainActor
    func testUnknownFutureRetailerDefaultIsNotOverwrittenOnLaunch() {
        let defaults = isolatedCommerceDefaults()
        defaults.set("future-retailer", forKey: "smartcart.commerce.selectedRetailer")

        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: defaults
        )

        XCTAssertEqual(model.selectedRetailer, .walmart)
        XCTAssertEqual(
            defaults.string(forKey: "smartcart.commerce.selectedRetailer"),
            "future-retailer"
        )
    }

    @MainActor
    func testWalmartAndTargetManifestsForSameRecipeRemainDistinct() async {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.saveCurrentList()
        let recipeID = model.activeRecipe.id

        model.startRetailerGuide(.target)
        await model.startMatching(force: true)
        model.saveCurrentList()

        let manifests = model.savedLists
            .map(\.manifest)
            .filter { $0.recipeID == recipeID }
        XCTAssertEqual(Set(manifests.map(\.retailerID)), ["walmart", "target"])
        XCTAssertEqual(manifests.count, 2)
    }

    @MainActor
    func testInstacartManifestExcludesPantryAndOptionalItemsAndPreservesPreferences() {
        let defaults = isolatedCommerceDefaults()
        var flour = Ingredient(name: "Flour", quantity: 2, unit: "cups")
        flour.pantryState = .needToBuy
        var butter = Ingredient(name: "Butter", quantity: 0.5, unit: "cup")
        butter.pantryState = .haveEnough
        let optionalParsley = Ingredient(name: "Parsley", quantity: 1, unit: "bunch", includeInList: false)
        let recipe = Recipe(
            title: "Cookies",
            source: .text,
            sourceDetail: "Test",
            heroSymbol: "birthday.cake.fill",
            servings: 4,
            prepMinutes: 10,
            cookMinutes: 12,
            ingredients: [flour, butter, optionalParsley]
        )
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            instacartHandoffService: RecordingInstacartHandoffService(),
            commerceDefaults: defaults
        )
        model.activeRecipe = recipe
        model.desiredServings = 4
        model.preferences.organicPolicy = .only
        model.preferences.dietaryRestrictions = [.glutenFree, .vegan, .dairyFree]

        let draft = model.instacartManifestDraft
        XCTAssertEqual(draft.items.count, 1)
        XCTAssertEqual(draft.items[0].name, "Flour")
        XCTAssertEqual(draft.items[0].quantity, 2, accuracy: 0.001)
        XCTAssertEqual(draft.items[0].unit, "cups")
        XCTAssertEqual(draft.items[0].healthFilters, ["GLUTEN_FREE", "ORGANIC", "VEGAN"])
        XCTAssertNil(draft.items[0].exactUPC)
        XCTAssertEqual(draft.pantryItemsRemoved, 1)
    }

    @MainActor
    func testInstacartManifestBlocksUnconfirmedQuantitiesAndUnresolvedAlternatives() {
        let defaults = isolatedCommerceDefaults()
        let ingredient = Ingredient(
            name: "Sugar or honey",
            quantity: 1,
            unit: "cup",
            alternativeGroup: "Sugar or honey",
            quantityReviewRequired: true
        )
        let recipe = Recipe(
            title: "Sweet Test",
            source: .text,
            sourceDetail: "Test",
            heroSymbol: "fork.knife",
            servings: 2,
            prepMinutes: 1,
            cookMinutes: 1,
            ingredients: [ingredient]
        )
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            instacartHandoffService: RecordingInstacartHandoffService(),
            commerceDefaults: defaults
        )
        model.activeRecipe = recipe

        XCTAssertEqual(model.unresolvedQuantityReviewCount, 1)
        XCTAssertEqual(model.unresolvedAlternativeCount, 1)
        XCTAssertTrue(model.commerceBlockingIssues.contains { $0.contains("uncertain quantity") })
        XCTAssertTrue(model.commerceBlockingIssues.contains { $0.contains("unresolved alternative") })
    }

    func testWalmartWishlistURLValidatorAcceptsOnlyOfficialSharedListLinks() throws {
        let accepted = try WalmartWishlistURLValidator.validate(
            "  https://www.walmart.com/lists/shared/WL/32828e97-d743-4b80-922a-0099b56c83bf#items  "
        )
        XCTAssertEqual(accepted.host, "www.walmart.com")
        XCTAssertEqual(accepted.path, "/lists/shared/WL/32828e97-d743-4b80-922a-0099b56c83bf")
        XCTAssertNil(accepted.fragment)

        XCTAssertThrowsError(try WalmartWishlistURLValidator.validate("http://www.walmart.com/lists/shared/WL/test")) {
            XCTAssertEqual($0 as? WalmartWishlistURLValidationError, .insecureURL)
        }
        XCTAssertThrowsError(try WalmartWishlistURLValidator.validate("https://walmart.com.evil.example/lists/shared/WL/test")) {
            XCTAssertEqual($0 as? WalmartWishlistURLValidationError, .unsupportedHost)
        }
        XCTAssertThrowsError(try WalmartWishlistURLValidator.validate("https://www.walmart.com/ip/10414680")) {
            XCTAssertEqual($0 as? WalmartWishlistURLValidationError, .notSharedWishlist)
        }
    }

    func testVisitedGuidedItemStatusRoundTripsAndIsCompleted() throws {
        let encoded = try JSONEncoder().encode(GuidedItemStatus.visited)

        XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"visited\"")
        XCTAssertEqual(try JSONDecoder().decode(GuidedItemStatus.self, from: encoded), .visited)
        XCTAssertTrue(GuidedItemStatus.visited.isCompleted)
        XCTAssertFalse(GuidedItemStatus.waiting.isCompleted)
    }

    func testRetailerTripPageLoadStateOnlyAllowsVisitedAfterSuccessfulLoad() {
        XCTAssertFalse(RetailerTripPageLoadState.loading.canRecordVisited)
        XCTAssertTrue(RetailerTripPageLoadState.loaded.canRecordVisited)
        XCTAssertFalse(RetailerTripPageLoadState.failed.canRecordVisited)
    }

    @MainActor
    func testRetailerSetupCompletionIsScopedAndPersistsWithoutCredentials() {
        let defaults = isolatedCommerceDefaults()
        let store = InMemorySmartCartStateStore()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: defaults,
            seedDemoShoppingState: true
        )

        XCTAssertFalse(model.retailerSetupIsComplete)
        model.completeRetailerSetup()
        XCTAssertTrue(model.retailerSetupIsComplete)

        model.startRetailerGuide(.target)
        XCTAssertFalse(model.retailerSetupIsComplete)
        model.completeRetailerSetup()
        XCTAssertTrue(model.retailerSetupIsComplete)

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.selectedRetailer, .target)
        XCTAssertTrue(restored.retailerSetupIsComplete)
        XCTAssertEqual(
            Set(defaults.stringArray(forKey: "smartcart.commerce.retailerSetupCompleted") ?? []),
            ["target", "walmart"]
        )
    }

    @MainActor
    func testShoppingSessionStartsPausesAndResumesAtFirstWaitingItem() throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: defaults,
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()

        model.startOrResumeRetailerShoppingSession()
        XCTAssertTrue(model.retailerSessionIsInProgress)
        XCTAssertTrue(model.hasResumableRetailerSession)

        let firstID = try model.currentGuidedItem.firstUnwrapped().id
        model.recordRetailerOutcome(.savedToWishlist, for: firstID)
        let expectedIndex = try model.shoppingItems.firstIndex(where: { !$0.status.isCompleted }).firstUnwrapped()
        XCTAssertEqual(model.guidedIndex, expectedIndex)

        model.pauseRetailerShoppingSession()
        XCTAssertEqual(model.savedLists.first?.manifest.handoffProgress, .paused)
        XCTAssertFalse(model.retailerSessionIsInProgress)
        XCTAssertTrue(model.hasResumableRetailerSession)
        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertTrue(restored.hasResumableRetailerSession)
        XCTAssertEqual(restored.guidedIndex, expectedIndex)
        XCTAssertEqual(restored.guidedCompletedCount, 1)

        restored.startOrResumeRetailerShoppingSession()
        XCTAssertEqual(restored.currentGuidedItem?.id, restored.shoppingItems[expectedIndex].id)
        XCTAssertTrue(restored.analyticsEvents.contains { $0.name == .shoppingSessionResumed })
    }

    @MainActor
    func testVisitedOutcomeAdvancesAndSynchronizesEveryTripSnapshot() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        XCTAssertGreaterThanOrEqual(model.shoppingItems.count, 2)
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())

        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let itemIndex = model.guidedIndex
        let itemID = model.shoppingItems[itemIndex].id
        let nextIndex = try XCTUnwrap(
            model.shoppingItems.indices.first {
                $0 > itemIndex && model.shoppingItems[$0].status == .waiting
            } ?? model.shoppingItems.indices.first {
                $0 != itemIndex && model.shoppingItems[$0].status == .waiting
            }
        )

        XCTAssertTrue(model.recordRetailerOutcome(.visited, for: itemID, sessionID: sessionID))

        XCTAssertEqual(model.shoppingItems[itemIndex].status, .visited)
        XCTAssertEqual(model.guidedIndex, nextIndex)
        XCTAssertEqual(
            model.shoppingSession(id: sessionID)?.items.first(where: { $0.id == itemID })?.status,
            .visited
        )
        let manifestID = try XCTUnwrap(model.shoppingSession(id: sessionID)?.manifestID)
        let manifest = try XCTUnwrap(
            model.savedLists.first(where: { $0.manifest.id == manifestID })?.manifest
        )
        XCTAssertEqual(manifest.handoffProgress, .inProgress)
        XCTAssertEqual(manifest.items.first(where: { $0.id == itemID })?.status, .visited)
        XCTAssertEqual(store.state?.shoppingItems[itemIndex].status, .visited)
        XCTAssertEqual(
            store.state?.shoppingSessions.first(where: { $0.id == sessionID })?
                .items.first(where: { $0.id == itemID })?.status,
            .visited
        )
        XCTAssertEqual(
            store.state?.savedLists.first(where: { $0.manifest.id == manifestID })?
                .manifest.items.first(where: { $0.id == itemID })?.status,
            .visited
        )
    }

    @MainActor
    func testVisitingLastWaitingItemCompletesTripExactlyOnce() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let itemID = try XCTUnwrap(model.currentGuidedItem?.id)
        let completionCountBefore = model.analyticsEvents.filter {
            $0.name == .guidedShoppingCompleted
        }.count

        XCTAssertTrue(model.recordRetailerOutcome(.visited, for: itemID, sessionID: sessionID))

        XCTAssertTrue(model.retailerGuideIsComplete)
        XCTAssertEqual(model.shoppingItems.first?.status, .visited)
        XCTAssertEqual(model.shoppingSession(id: sessionID)?.items.first?.status, .visited)
        XCTAssertEqual(model.savedLists.first?.manifest.handoffProgress, .completed)
        XCTAssertEqual(
            model.analyticsEvents.filter { $0.name == .guidedShoppingCompleted }.count,
            completionCountBefore + 1
        )

        let completedItems = model.shoppingItems
        let completedLists = model.savedLists
        let completedSessions = model.shoppingSessions
        let completedEvents = model.analyticsEvents
        XCTAssertFalse(model.recordRetailerOutcome(.visited, for: itemID, sessionID: sessionID))
        XCTAssertEqual(model.shoppingItems, completedItems)
        XCTAssertEqual(model.savedLists, completedLists)
        XCTAssertEqual(model.shoppingSessions, completedSessions)
        XCTAssertEqual(model.analyticsEvents, completedEvents)
    }

    @MainActor
    func testExactAmbiguousDismissalPausesAndRelaunchResumesSameWaitingItem() throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: defaults,
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let itemID = try XCTUnwrap(model.currentGuidedItem?.id)
        let originalItems = model.shoppingItems
        let originalIndex = model.guidedIndex

        XCTAssertFalse(
            model.handleAmbiguousRetailerBrowserDismissal(
                sessionID: UUID(),
                itemID: itemID
            )
        )
        XCTAssertFalse(
            model.handleAmbiguousRetailerBrowserDismissal(
                sessionID: sessionID,
                itemID: UUID()
            )
        )
        XCTAssertTrue(model.retailerSessionIsInProgress)

        XCTAssertTrue(
            model.handleAmbiguousRetailerBrowserDismissal(
                sessionID: sessionID,
                itemID: itemID
            )
        )
        XCTAssertEqual(model.shoppingItems, originalItems)
        XCTAssertEqual(model.guidedIndex, originalIndex)
        XCTAssertEqual(model.currentGuidedItem?.status, .waiting)
        XCTAssertEqual(model.savedLists.first?.manifest.handoffProgress, .paused)
        XCTAssertEqual(model.shoppingSession(id: sessionID)?.items, originalItems)

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.activeShoppingSessionID, sessionID)
        XCTAssertEqual(restored.guidedIndex, originalIndex)
        XCTAssertEqual(restored.currentGuidedItem?.id, itemID)
        XCTAssertEqual(restored.currentGuidedItem?.status, .waiting)
        XCTAssertTrue(restored.hasResumableRetailerSession)
        XCTAssertTrue(restored.startOrResumeRetailerShoppingSession())
        XCTAssertEqual(restored.currentGuidedItem?.id, itemID)
        XCTAssertEqual(restored.currentGuidedItem?.status, .waiting)
        XCTAssertTrue(restored.retailerSessionIsInProgress)
    }

    @MainActor
    func testGuideNavigationDoesNotStartUntilSetupAndExplicitStart() {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )

        model.beginGuidedShopping()
        XCTAssertEqual(model.homePath.last, .shoppingTrip)
        XCTAssertFalse(model.retailerSessionIsInProgress)
        XCTAssertTrue(model.shoppingSessions.isEmpty)

        model.startOrResumeRetailerShoppingSession()
        XCTAssertFalse(model.retailerSessionIsInProgress)
        model.completeRetailerSetup()
        model.startOrResumeRetailerShoppingSession()
        XCTAssertTrue(model.retailerSessionIsInProgress)
        XCTAssertEqual(model.shoppingSessions.count, 1)
    }

    @MainActor
    func testPausedSessionCanReopenAfterStartingAnotherRecipe() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.desiredServings = 6
        model.fulfillmentMode = .delivery
        model.startOrResumeRetailerShoppingSession()
        let originalRecipeID = model.activeRecipe.id
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        model.pauseRetailerShoppingSession()

        let replacementRecipe = RecipeParser.parse(
            title: "Later Dinner",
            text: "1 cup rice\n2 cups water"
        )
        model.beginRecipe(replacementRecipe)
        XCTAssertTrue(model.shoppingItems.isEmpty)

        XCTAssertTrue(model.openShoppingSession(sessionID))
        XCTAssertEqual(model.activeRecipe.id, originalRecipeID)
        XCTAssertEqual(model.desiredServings, 6)
        XCTAssertEqual(model.fulfillmentMode, .delivery)
        XCTAssertFalse(model.shoppingItems.isEmpty)
        XCTAssertEqual(model.homePath, [.shoppingTrip])
        XCTAssertEqual(model.mostRecentPendingShoppingSession?.id, sessionID)
    }

    @MainActor
    func testRetailerOutcomeWriteFailureRollsBackAllVisibleSessionState() throws {
        let store = ControllableSmartCartStateStore()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let itemID = try model.shoppingItems.firstUnwrapped().id
        let originalItems = model.shoppingItems
        let originalIndex = model.guidedIndex
        let originalLists = model.savedLists
        let originalSessions = model.shoppingSessions
        let originalEvents = model.analyticsEvents
        let originalActiveSessionID = model.activeShoppingSessionID
        let originalPersistedState = store.state
        store.failNextSave = true

        XCTAssertFalse(model.recordRetailerOutcome(.unavailable, for: itemID))

        XCTAssertEqual(model.shoppingItems, originalItems)
        XCTAssertEqual(model.guidedIndex, originalIndex)
        XCTAssertEqual(model.savedLists, originalLists)
        XCTAssertEqual(model.shoppingSessions, originalSessions)
        XCTAssertEqual(model.analyticsEvents, originalEvents)
        XCTAssertEqual(model.activeShoppingSessionID, originalActiveSessionID)
        XCTAssertEqual(store.state, originalPersistedState)
        XCTAssertNotNil(model.persistenceIssue)
    }

    @MainActor
    func testReplacementSucceedsWithoutAdvancingWaitingItem() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        let itemIndex = try XCTUnwrap(
            model.shoppingItems.indices.first { index in
                model.shoppingItems[index].alternatives.contains { candidate in
                    model.resolvedReplacementPackageCount(
                        for: model.shoppingItems[index],
                        product: candidate
                    ) != nil
                }
            }
        )
        model.guidedIndex = itemIndex
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let item = model.shoppingItems[itemIndex]
        let candidate = try XCTUnwrap(
            item.alternatives.first {
                model.resolvedReplacementPackageCount(for: item, product: $0) != nil
            }
        )

        XCTAssertTrue(model.selectAlternative(itemID: item.id, candidateID: candidate.id))

        XCTAssertEqual(model.guidedIndex, itemIndex)
        XCTAssertEqual(model.currentGuidedItem?.id, item.id)
        XCTAssertEqual(model.currentGuidedItem?.status, .waiting)
        XCTAssertEqual(model.currentGuidedItem?.product.id, candidate.id)
        XCTAssertEqual(
            model.shoppingSession(id: sessionID)?.items.first(where: { $0.id == item.id })?.status,
            .waiting
        )
        XCTAssertEqual(
            model.savedLists.first?.manifest.items.first(where: { $0.id == item.id })?.status,
            .waiting
        )
        XCTAssertTrue(model.retailerSessionIsInProgress)
    }

    @MainActor
    func testVisitedDefaultsToPurchasedWhileUnavailableAndSkippedStayExcluded() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        XCTAssertGreaterThanOrEqual(model.shoppingItems.count, 3)
        model.shoppingItems = Array(model.shoppingItems.prefix(3))
        let itemIDs = model.shoppingItems.map(\.id)
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)

        XCTAssertTrue(model.recordRetailerOutcome(.visited, for: itemIDs[0], sessionID: sessionID))
        XCTAssertTrue(model.recordRetailerOutcome(.unavailable, for: itemIDs[1], sessionID: sessionID))
        XCTAssertTrue(model.recordRetailerOutcome(.skipped, for: itemIDs[2], sessionID: sessionID))

        XCTAssertEqual(
            model.defaultPurchasedItemIDs(for: .boughtEverything, sessionID: sessionID),
            Set([itemIDs[0]])
        )
        XCTAssertEqual(
            model.defaultPurchasedItemIDs(for: .boughtMost, sessionID: sessionID),
            Set([itemIDs[0]])
        )
    }

    @MainActor
    func testVisitedCannotOverwriteUnavailableOrSkippedOutcomes() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        XCTAssertGreaterThanOrEqual(model.shoppingItems.count, 3)
        model.shoppingItems = Array(model.shoppingItems.prefix(3))
        let itemIDs = model.shoppingItems.map(\.id)
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)

        XCTAssertTrue(model.recordRetailerOutcome(.unavailable, for: itemIDs[0], sessionID: sessionID))
        XCTAssertFalse(model.recordRetailerOutcome(.visited, for: itemIDs[0], sessionID: sessionID))
        XCTAssertTrue(model.recordRetailerOutcome(.skipped, for: itemIDs[1], sessionID: sessionID))
        XCTAssertFalse(model.recordRetailerOutcome(.visited, for: itemIDs[1], sessionID: sessionID))

        XCTAssertEqual(model.shoppingItems[0].status, .unavailable)
        XCTAssertEqual(model.shoppingItems[1].status, .skipped)
        XCTAssertEqual(model.currentGuidedItem?.id, itemIDs[2])
        XCTAssertEqual(model.currentGuidedItem?.status, .waiting)
        XCTAssertEqual(model.shoppingSession(id: sessionID)?.items[0].status, .unavailable)
        XCTAssertEqual(model.shoppingSession(id: sessionID)?.items[1].status, .skipped)
        XCTAssertEqual(model.savedLists.first?.manifest.items[0].status, .unavailable)
        XCTAssertEqual(model.savedLists.first?.manifest.items[1].status, .skipped)
    }

    @MainActor
    func testCompletedSessionRejectsFurtherOutcomeAndReplacementMutation() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        let item = try model.shoppingItems.first(where: { !$0.alternatives.isEmpty }).firstUnwrapped()
        let candidateID = try item.alternatives.firstUnwrapped().id
        model.shoppingItems = [item]
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        XCTAssertTrue(model.recordRetailerOutcome(.visited, for: item.id, sessionID: sessionID))
        XCTAssertTrue(model.activeShoppingSessionIsImmutable)
        let completedItems = model.shoppingItems
        let completedLists = model.savedLists
        let completedSessions = model.shoppingSessions
        let completedEvents = model.analyticsEvents

        XCTAssertFalse(model.recordRetailerOutcome(.addedToCart, for: item.id, sessionID: sessionID))
        XCTAssertFalse(model.selectAlternative(itemID: item.id, candidateID: candidateID))

        XCTAssertEqual(model.shoppingItems, completedItems)
        XCTAssertEqual(model.savedLists, completedLists)
        XCTAssertEqual(model.shoppingSessions, completedSessions)
        XCTAssertEqual(model.analyticsEvents, completedEvents)
    }

    @MainActor
    func testOpenShoppingSessionSaveFailureRollsBackVisibleState() throws {
        let store = ControllableSmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: defaults,
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        XCTAssertTrue(model.pauseRetailerShoppingSession())

        let otherRecipe = RecipeParser.parse(
            title: "Visible Recipe",
            text: "1 cup rice\n2 cups water"
        )
        model.beginRecipe(otherRecipe)
        model.desiredServings = 3
        model.fulfillmentMode = .delivery
        model.startRetailerGuide(.target)
        model.selectedTab = .pantry
        model.homePath = [.recipeReady, .preferences]

        let originalActiveSessionID = model.activeShoppingSessionID
        let originalScope = model.shoppingScope
        let originalRetailer = model.selectedRetailer
        let originalStoreIDs = model.selectedStoreIDs
        let originalRecipe = model.activeRecipe
        let originalServings = model.desiredServings
        let originalFulfillment = model.fulfillmentMode
        let originalItems = model.shoppingItems
        let originalIndex = model.guidedIndex
        let originalTab = model.selectedTab
        let originalPath = model.homePath
        let originalPersistedState = store.state
        store.failNextSave = true

        XCTAssertFalse(model.openShoppingSession(sessionID))

        XCTAssertEqual(model.activeShoppingSessionID, originalActiveSessionID)
        XCTAssertEqual(model.shoppingScope, originalScope)
        XCTAssertEqual(model.selectedRetailer, originalRetailer)
        XCTAssertEqual(model.selectedStoreIDs, originalStoreIDs)
        XCTAssertEqual(model.activeRecipe, originalRecipe)
        XCTAssertEqual(model.desiredServings, originalServings)
        XCTAssertEqual(model.fulfillmentMode, originalFulfillment)
        XCTAssertEqual(model.shoppingItems, originalItems)
        XCTAssertEqual(model.guidedIndex, originalIndex)
        XCTAssertEqual(model.selectedTab, originalTab)
        XCTAssertEqual(model.homePath, originalPath)
        XCTAssertEqual(store.state, originalPersistedState)
        XCTAssertNotNil(model.persistenceIssue)
    }

    @MainActor
    func testStartAndPauseFailuresRollBackSessionPhase() {
        let store = ControllableSmartCartStateStore()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()

        store.failNextSave = true
        XCTAssertFalse(model.startOrResumeRetailerShoppingSession())
        XCTAssertTrue(model.shoppingSessions.isEmpty)
        XCTAssertFalse(model.retailerSessionIsInProgress)

        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        XCTAssertTrue(model.retailerSessionIsInProgress)
        store.failNextSave = true
        XCTAssertFalse(model.pauseRetailerShoppingSession())
        XCTAssertTrue(model.retailerSessionIsInProgress)
        XCTAssertEqual(model.savedLists.first?.manifest.handoffProgress, .inProgress)
    }

    @MainActor
    func testShoppingReconciliationDraftSurvivesRelaunchAndClearsOnCommit() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, seedDemoShoppingState: true)
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        let purchasedID = try model.shoppingItems.firstUnwrapped().id

        model.saveShoppingReconciliationDraft(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [purchasedID],
            substitutions: []
        )

        let restored = AppModel(stateStore: store)
        XCTAssertEqual(restored.shoppingSession(id: sessionID)?.reconciliationDraft?.outcome, .boughtFew)
        XCTAssertEqual(
            restored.shoppingSession(id: sessionID)?.reconciliationDraft?.purchasedItemIDs,
            [purchasedID]
        )

        try restored.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [purchasedID],
            substitutions: []
        )
        XCTAssertNil(restored.shoppingSession(id: sessionID)?.reconciliationDraft)
    }

    @MainActor
    func testReplacingProductKeepsOneActivePendingSession() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.startOrResumeRetailerShoppingSession()
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        let item = try model.shoppingItems.first(where: { !$0.alternatives.isEmpty }).firstUnwrapped()
        let replacement = try item.alternatives.firstUnwrapped()
        let savedListID = try model.savedLists.firstUnwrapped().id
        XCTAssertTrue(Set(model.savedLists[0].manifest.items.map(\.id)).isSubset(of: Set(model.shoppingItems.map(\.id))))

        model.selectAlternative(itemID: item.id, candidateID: replacement.id)

        XCTAssertEqual(model.ensureCurrentShoppingSession(), sessionID)
        XCTAssertEqual(model.pendingShoppingSessions.count, 1)
        XCTAssertEqual(
            model.shoppingSession(id: sessionID)?.items.first(where: { $0.id == item.id })?.product.id,
            replacement.id
        )
        XCTAssertEqual(
            model.savedLists[0].manifest.items.first(where: { $0.id == item.id })?.product.id,
            replacement.id
        )

        model.openSavedList(savedListID)
        XCTAssertEqual(model.pendingShoppingSessions.count, 1)
        XCTAssertEqual(model.ensureCurrentShoppingSession(), sessionID)
    }

    @MainActor
    func testAllPendingSessionsRemainReopenable() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        let firstItems = model.shoppingItems
        let firstRecipeID = model.activeRecipe.id
        model.startOrResumeRetailerShoppingSession()
        let firstSessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        model.pauseRetailerShoppingSession()

        let secondRecipe = RecipeParser.parse(title: "Second Trip", text: "1 cup rice")
        model.beginRecipe(secondRecipe)
        model.shoppingItems = firstItems.map { item in
            var copy = item
            copy.status = .waiting
            return copy
        }
        model.startOrResumeRetailerShoppingSession()
        model.pauseRetailerShoppingSession()

        XCTAssertEqual(model.pendingShoppingSessions.count, 2)
        XCTAssertTrue(model.openShoppingSession(firstSessionID))
        XCTAssertEqual(model.activeRecipe.id, firstRecipeID)
        XCTAssertEqual(model.homePath, [.shoppingTrip])
    }

    @MainActor
    func testSavedManifestCanBeReopenedForReview() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.saveCurrentList()
        let savedID = try model.savedLists.firstUnwrapped().id
        let expectedProductIDs = model.shoppingItems.map(\.product.retailerProductID)
        model.beginRecipe(RecipeParser.parse(title: "Different", text: "1 cup rice"))
        model.fulfillmentMode = .delivery

        model.openSavedList(savedID)

        XCTAssertEqual(model.homePath, [.shoppingList])
        XCTAssertEqual(model.fulfillmentMode, .pickup)
        XCTAssertEqual(model.shoppingItems.map(\.product.retailerProductID), expectedProductIDs)
    }

    @MainActor
    func testGuidedOutcomesUpdateOneStableShoppingSessionSnapshot() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.startOrResumeRetailerShoppingSession()
        let originalSessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        let itemID = try model.shoppingItems.firstUnwrapped().id

        model.recordRetailerOutcome(.addedToCart, for: itemID)

        XCTAssertEqual(model.ensureCurrentShoppingSession(), originalSessionID)
        XCTAssertEqual(model.shoppingSessions.count, 1)
        XCTAssertEqual(
            model.shoppingSession(id: originalSessionID)?.items.first(where: { $0.id == itemID })?.status,
            .addedToCart
        )
    }

    @MainActor
    func testCompletedSingleRecipeTripRequiresExplicitForkBeforeNewSession() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]

        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let completedSessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let completedTripID = try XCTUnwrap(model.shoppingSession(id: completedSessionID)?.tripID)
        let itemID = try model.shoppingItems.firstUnwrapped().id
        model.recordRetailerOutcome(.savedToWishlist, for: itemID, sessionID: completedSessionID)
        XCTAssertTrue(model.shoppingSession(id: completedSessionID)?.isGuideComplete == true)

        XCTAssertFalse(model.startOrResumeRetailerShoppingSession())
        XCTAssertTrue(model.forkCompletedShoppingTrip())
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let newSessionID = try XCTUnwrap(model.activeShoppingSessionID)

        XCTAssertNotEqual(newSessionID, completedSessionID)
        XCTAssertNotEqual(model.shoppingSession(id: newSessionID)?.tripID, completedTripID)
        XCTAssertEqual(model.shoppingSessions.count, 2)
        XCTAssertTrue(model.shoppingSession(id: completedSessionID)?.isGuideComplete == true)
    }

    @MainActor
    func testCompletedGuideReconcilesOriginalSessionWithoutDuplication() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let itemID = try model.shoppingItems.firstUnwrapped().id
        model.recordRetailerOutcome(.savedToWishlist, for: itemID, sessionID: sessionID)

        model.startShoppingReconciliation()
        XCTAssertEqual(model.homePath.last, .shoppingReconciliation(sessionID))
        XCTAssertEqual(model.shoppingSessions.count, 1)
        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .didNotShop,
            purchasedItemIDs: [],
            substitutions: []
        )

        model.startShoppingReconciliation()
        XCTAssertEqual(model.shoppingSessions.count, 1)
        XCTAssertTrue(model.shoppingSession(id: sessionID)?.isCommitted == true)
    }

    @MainActor
    func testCompletedGuideOpeningRetailerListAndSavedListRetainsOriginalSession() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let itemID = try model.shoppingItems.firstUnwrapped().id
        model.recordRetailerOutcome(.savedToWishlist, for: itemID, sessionID: sessionID)
        let listID = try model.savedLists.firstUnwrapped().id

        _ = model.retailerListsURL()
        XCTAssertEqual(model.ensureCurrentShoppingSession(), sessionID)
        model.openSavedList(listID)

        XCTAssertEqual(model.activeShoppingSessionID, sessionID)
        XCTAssertEqual(model.shoppingSessions.count, 1)
    }

    @MainActor
    func testCompletedUncommittedSessionRestoresDirectlyIntoReconciliation() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let itemID = try model.shoppingItems.firstUnwrapped().id
        model.recordRetailerOutcome(.savedToWishlist, for: itemID, sessionID: sessionID)
        store.state?.activeShoppingSessionID = nil

        let restored = AppModel(stateStore: store, commerceDefaults: isolatedCommerceDefaults())
        restored.startShoppingReconciliation()

        XCTAssertEqual(restored.homePath.last, .shoppingReconciliation(sessionID))
        XCTAssertEqual(restored.activeShoppingSessionID, sessionID)
        XCTAssertEqual(restored.shoppingSessions.count, 1)
    }

    @MainActor
    func testCompletedSessionRemainsFrozenBeforeReconciliation() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let itemID = try model.shoppingItems.firstUnwrapped().id
        model.recordRetailerOutcome(.savedToWishlist, for: itemID, sessionID: sessionID)
        let frozenSession = try XCTUnwrap(model.shoppingSession(id: sessionID))
        let frozenQuantity = try XCTUnwrap(frozenSession.items.first?.purchaseQuantity)

        model.updatePurchaseQuantity(for: itemID, delta: 1)
        XCTAssertEqual(model.shoppingItems.first?.purchaseQuantity, frozenQuantity)

        // Even if a caller changes the display copy directly, reconciliation
        // must continue to consume the completed session's frozen snapshot.
        model.shoppingItems[0].purchaseQuantity += 1

        model.startShoppingReconciliation()

        XCTAssertEqual(model.homePath.last, .shoppingReconciliation(sessionID))
        XCTAssertEqual(model.shoppingSessions.count, 1)
        XCTAssertEqual(
            model.shoppingSession(id: sessionID)?.items.first?.purchaseQuantity,
            frozenQuantity
        )
        XCTAssertEqual(model.shoppingSession(id: sessionID), frozenSession)

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [itemID],
            substitutions: []
        )
        XCTAssertEqual(
            model.shoppingSession(id: sessionID)?.reconciliation?.acquisitions?.first?.amount,
            Double(frozenQuantity)
        )
    }

    @MainActor
    func testEditingCompletedListForksNewLogicalTrip() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let completedSessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let completedTripID = try XCTUnwrap(
            model.shoppingSession(id: completedSessionID)?.reconciliationIdentity
        )
        let itemID = try XCTUnwrap(model.shoppingItems.first?.id)
        model.recordRetailerOutcome(.addedToCart, for: itemID, sessionID: completedSessionID)
        let frozenSession = try XCTUnwrap(model.shoppingSession(id: completedSessionID))

        XCTAssertTrue(model.forkCompletedShoppingTrip())
        let forkedManifest = try XCTUnwrap(model.savedLists.first?.manifest)

        XCTAssertNil(model.activeShoppingSessionID)
        XCTAssertNotEqual(forkedManifest.logicalTripID, completedTripID)
        XCTAssertEqual(model.shoppingItems.first?.status, .waiting)
        model.updatePurchaseQuantity(for: itemID, delta: 1)
        XCTAssertNotEqual(
            model.shoppingItems.first?.purchaseQuantity,
            frozenSession.items.first?.purchaseQuantity
        )
        XCTAssertEqual(model.shoppingSession(id: completedSessionID), frozenSession)
    }

    @MainActor
    func testHistoricalMealPrepSessionDoesNotReplaceCurrentEditableDraft() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, seedDemoShoppingState: true)
        let shoppingItems = model.shoppingItems.map { item in
            var completed = item
            completed.status = .addedToCart
            return completed
        }
        let recipeA = Recipe(
            title: "Trip A",
            source: .text,
            sourceDetail: "Test",
            heroSymbol: "fork.knife",
            servings: 2,
            prepMinutes: 1,
            cookMinutes: 1,
            ingredients: [Ingredient(name: "Rice", quantity: 1, unit: "cup")]
        )
        let draftA = MealPrepDraft(selections: [
            MealPrepSelection(recipe: recipeA, targetServings: 2)
        ])
        model.mealPrepDraft = draftA
        XCTAssertTrue(model.buildMealPrepPlan())
        let planA = try XCTUnwrap(model.mealPrepPlan)
        let sessionA = ShoppingSession(
            logicalTripID: UUID(),
            recipeID: planA.id,
            recipeTitle: planA.title,
            storeID: model.primaryStore.retailerStoreID,
            retailerID: model.selectedRetailer.rawValue,
            fulfillmentMode: model.fulfillmentMode,
            shoppingScope: planA.shoppingScope,
            mealPrepSnapshot: planA,
            items: shoppingItems
        )

        let recipeB = Recipe(
            title: "Draft B",
            source: .text,
            sourceDetail: "Test",
            heroSymbol: "fork.knife",
            servings: 4,
            prepMinutes: 1,
            cookMinutes: 1,
            ingredients: [Ingredient(name: "Beans", quantity: 2, unit: "cups")]
        )
        let draftB = MealPrepDraft(selections: [
            MealPrepSelection(recipe: recipeB, targetServings: 6)
        ])
        model.mealPrepDraft = draftB
        XCTAssertTrue(model.buildMealPrepPlan())
        let planB = try XCTUnwrap(model.mealPrepPlan)
        model.shoppingSessions = [sessionA]

        model.openShoppingSession(sessionA.id)

        XCTAssertEqual(model.mealPrepDraft, draftB)
        XCTAssertEqual(model.mealPrepPlan, planB)
        XCTAssertEqual(model.currentShoppingMealPrepSnapshot, planA)
        XCTAssertEqual(model.shoppingScope, planA.shoppingScope)

        let restored = AppModel(stateStore: store)
        XCTAssertEqual(restored.mealPrepDraft, draftB)
        XCTAssertEqual(restored.mealPrepPlan, planB)
        XCTAssertEqual(restored.currentShoppingMealPrepSnapshot, planA)
        XCTAssertEqual(restored.shoppingScope, planA.shoppingScope)
        restored.startMealPrepDraft()
        XCTAssertEqual(restored.shoppingScope, draftB.shoppingScope)
        XCTAssertEqual(restored.currentMealPrepPlan, planB)
        XCTAssertEqual(restored.shoppingSession(id: sessionA.id), sessionA)
    }

    @MainActor
    func testSimilarPendingSessionsReceiveOutcomeByExactSessionID() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let first = try XCTUnwrap(model.shoppingSessions.first)
        let second = ShoppingSession(
            recipeID: first.recipeID,
            recipeTitle: first.recipeTitle,
            manifestID: first.manifestID,
            storeID: first.storeID,
            retailerID: first.retailerID,
            desiredServings: first.desiredServings,
            fulfillmentMode: first.fulfillmentMode,
            shoppingScope: first.shoppingScope,
            mealPrepSnapshot: first.mealPrepSnapshot,
            startedAt: first.startedAt.addingTimeInterval(1),
            items: first.items,
            stateFingerprint: first.stateFingerprint
        )
        model.shoppingSessions.insert(second, at: 0)
        model.activeShoppingSessionID = second.id
        model.shoppingItems = second.items
        let itemID = try second.items.firstUnwrapped().id

        model.recordRetailerOutcome(.addedToCart, for: itemID, sessionID: second.id)

        XCTAssertEqual(
            model.shoppingSession(id: second.id)?.items.first(where: { $0.id == itemID })?.status,
            .addedToCart
        )
        XCTAssertEqual(
            model.shoppingSession(id: first.id)?.items.first(where: { $0.id == itemID })?.status,
            .waiting
        )

        model.recordRetailerOutcome(.savedToWishlist, for: itemID, sessionID: first.id)
        XCTAssertEqual(
            model.shoppingSession(id: first.id)?.items.first(where: { $0.id == itemID })?.status,
            .waiting,
            "A stale callback cannot mutate a session that is not active"
        )
    }

    @MainActor
    func testProductReplacementRefreshesPackageMetadataAndCount() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore(), seedDemoShoppingState: true)
        let itemIndex = try XCTUnwrap(model.shoppingItems.firstIndex(where: { !$0.alternatives.isEmpty }))
        let original = model.shoppingItems[itemIndex]
        var replacement = try original.alternatives.firstUnwrapped()
        replacement.packageDescription = "8 oz replacement package"
        replacement.packageQuantity = 8
        replacement.packageUnit = "oz"
        model.shoppingItems[itemIndex].ingredient.quantity = 9
        model.shoppingItems[itemIndex].ingredient.unit = "lb"
        model.shoppingItems[itemIndex].requestedQuantity = "2 lb"
        model.shoppingItems[itemIndex].requestedAmount = 2
        model.shoppingItems[itemIndex].alternatives = [replacement]

        model.selectAlternative(itemID: original.id, candidateID: replacement.id)

        let updated = try XCTUnwrap(model.shoppingItems.first(where: { $0.id == original.id }))
        XCTAssertEqual(updated.product.id, replacement.id)
        XCTAssertEqual(updated.product.packageDescription, "8 oz replacement package")
        XCTAssertEqual(updated.product.packageQuantity, 8)
        XCTAssertEqual(updated.product.packageUnit, "oz")
        XCTAssertEqual(updated.purchaseQuantity, 4)
    }

    @MainActor
    func testWalmartWishlistReferenceAndGuidedOutcomesSurviveRelaunch() throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: defaults,
            seedDemoShoppingState: true
        )
        model.shoppingRoute = .walmartDirect
        try model.saveWalmartWishlistReference(
            displayName: "SmartCart Groceries",
            rawURL: "https://www.walmart.com/lists/shared/WL/32828e97-d743-4b80-922a-0099b56c83bf"
        )

        let itemIDs = model.shoppingItems.map(\.id)
        for (index, itemID) in itemIDs.enumerated() {
            let outcome: GuidedItemStatus = switch index % 4 {
            case 0: .savedToWishlist
            case 1: .addedToCart
            case 2: .unavailable
            default: .skipped
            }
            model.recordWalmartOutcome(outcome, for: itemID)
        }
        model.saveCurrentList()
        XCTAssertEqual(model.savedLists.first?.manifest.handoffProgress, .completed)
        let openedURL = model.openSavedWalmartWishlist()

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)

        XCTAssertEqual(openedURL, restored.walmartWishlistReference?.sharedURL)
        XCTAssertEqual(restored.walmartWishlistReference?.displayName, "SmartCart Groceries")
        XCTAssertNotNil(restored.walmartWishlistReference?.lastOpenedAt)
        XCTAssertTrue(restored.walmartGuideIsComplete)
        XCTAssertEqual(restored.guidedCompletedCount, restored.shoppingItems.count)
        XCTAssertTrue(restored.analyticsEvents.contains { $0.name == .walmartWishlistURLSaved })
        XCTAssertTrue(restored.analyticsEvents.contains { $0.name == .walmartProductSelfReportedSaved })
        XCTAssertEqual(
            restored.analyticsEvents.filter { $0.name == .walmartGuidedFlowCompleted }.count,
            1
        )
        XCTAssertTrue(restored.analyticsEvents.contains { $0.name == .walmartWishlistOpened })
        XCTAssertFalse(restored.analyticsEvents.contains { event in
            event.properties.keys.contains { $0.localizedCaseInsensitiveContains("url") }
        })
    }

    @MainActor
    func testShoppingOutcomeDefaultsExcludeUnavailableItems() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            seedDemoShoppingState: true
        )
        let unavailableID = try model.shoppingItems.firstUnwrapped().id
        model.shoppingItems[0].status = .unavailable
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()

        let everything = model.defaultPurchasedItemIDs(
            for: .boughtEverything,
            sessionID: sessionID
        )
        let most = model.defaultPurchasedItemIDs(for: .boughtMost, sessionID: sessionID)

        XCTAssertFalse(everything.contains(unavailableID))
        XCTAssertEqual(everything, most)
        XCTAssertTrue(model.defaultPurchasedItemIDs(for: .boughtFew, sessionID: sessionID).isEmpty)
        XCTAssertTrue(model.defaultPurchasedItemIDs(for: .didNotShop, sessionID: sessionID).isEmpty)
    }

    @MainActor
    func testPantryReconciliationIsAtomicIdempotentAndPersists() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, seedDemoShoppingState: true)
        let item = try XCTUnwrap(model.shoppingItems.first { !$0.product.variableWeight })
        XCTAssertFalse(item.product.variableWeight)
        model.pantryInventory = [
            PantryInventoryItem(
                name: item.product.name,
                brand: item.product.brand,
                quantity: 2,
                unit: "item",
                preferredRetailerProductID: item.product.retailerProductID,
                packageSize: item.product.packageQuantity,
                packageUnit: item.product.packageUnit
            )
        ]
        let existingID = try model.pantryInventory.firstUnwrapped().id
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: []
        )
        let expectedQuantity = 2 + Double(item.purchaseQuantity)
        XCTAssertEqual(model.pantryInventory.count, 1)
        XCTAssertEqual(model.pantryInventory[0].id, existingID)
        XCTAssertEqual(model.pantryInventory[0].quantity, expectedQuantity, accuracy: 0.001)
        XCTAssertEqual(model.pantryInventory[0].packageCount, expectedQuantity, accuracy: 0.001)
        if let packageSize = item.product.packageQuantity {
            XCTAssertEqual(
                model.pantryInventory[0].remainingAmount,
                expectedQuantity * packageSize,
                accuracy: 0.001
            )
            XCTAssertEqual(model.pantryInventory[0].remainingUnit, item.product.packageUnit)
        }

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: []
        )
        XCTAssertEqual(model.pantryInventory[0].quantity, expectedQuantity, accuracy: 0.001)

        let restored = AppModel(stateStore: store)
        XCTAssertEqual(restored.pantryInventory[0].quantity, expectedQuantity, accuracy: 0.001)
        let restoredSession = try restored.shoppingSession(id: sessionID).firstUnwrapped()
        let restoredRecord = try restoredSession.reconciliation.firstUnwrapped()
        XCTAssertEqual(restoredRecord.purchasedItemIDs, Set([item.id]))
    }

    @MainActor
    func testDuplicateLegacySessionsCannotApplyPantryTwice() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let source = try model.shoppingSessions.firstUnwrapped()
        let firstItems = source.items.map { item in
            ShoppingListItem(
                id: UUID(),
                ingredient: item.ingredient,
                requestedQuantity: item.requestedQuantity,
                requestedAmount: item.requestedAmount,
                purchaseQuantity: item.purchaseQuantity,
                product: item.product,
                alternatives: item.alternatives,
                storeID: item.storeID,
                status: item.status,
                matchScore: item.matchScore,
                selectionReasons: item.selectionReasons
            )
        }
        let secondItems = source.items.map { item in
            ShoppingListItem(
                id: UUID(),
                ingredient: item.ingredient,
                requestedQuantity: item.requestedQuantity,
                requestedAmount: item.requestedAmount,
                purchaseQuantity: item.purchaseQuantity,
                product: item.product,
                alternatives: item.alternatives,
                storeID: item.storeID,
                status: item.status,
                matchScore: item.matchScore,
                selectionReasons: item.selectionReasons
            )
        }
        let thirdItems = source.items.map { item in
            ShoppingListItem(
                id: UUID(),
                ingredient: item.ingredient,
                requestedQuantity: item.requestedQuantity,
                requestedAmount: item.requestedAmount,
                purchaseQuantity: item.purchaseQuantity,
                product: item.product,
                alternatives: item.alternatives,
                storeID: item.storeID,
                status: item.status,
                matchScore: item.matchScore,
                selectionReasons: item.selectionReasons
            )
        }
        XCTAssertTrue(Set(firstItems.map(\.id)).isDisjoint(with: Set(secondItems.map(\.id))))
        XCTAssertTrue(Set(firstItems.map(\.id)).isDisjoint(with: Set(thirdItems.map(\.id))))
        XCTAssertTrue(Set(secondItems.map(\.id)).isDisjoint(with: Set(thirdItems.map(\.id))))
        let firstLegacyTripID = UUID()
        let secondLegacyTripID = UUID()
        let thirdLegacyTripID = UUID()
        let firstManifestID = UUID()
        let secondManifestID = UUID()
        let legacyStartedAt = Date(timeIntervalSince1970: 1_700_200_000)
        XCTAssertNotEqual(firstLegacyTripID, secondLegacyTripID)
        var first = ShoppingSession(
            tripID: firstLegacyTripID,
            recipeID: source.recipeID,
            recipeTitle: source.recipeTitle,
            manifestID: firstManifestID,
            storeID: source.storeID,
            retailerID: source.retailerID,
            desiredServings: source.desiredServings,
            fulfillmentMode: source.fulfillmentMode,
            shoppingScope: source.shoppingScope,
            mealPrepSnapshot: source.mealPrepSnapshot,
            startedAt: legacyStartedAt.addingTimeInterval(1),
            items: firstItems,
            stateFingerprint: source.stateFingerprint
        )
        first.logicalTripID = nil
        var second = ShoppingSession(
            tripID: secondLegacyTripID,
            recipeID: source.recipeID,
            recipeTitle: source.recipeTitle,
            manifestID: nil,
            storeID: source.storeID,
            retailerID: source.retailerID,
            desiredServings: source.desiredServings,
            fulfillmentMode: source.fulfillmentMode,
            shoppingScope: source.shoppingScope,
            mealPrepSnapshot: source.mealPrepSnapshot,
            startedAt: legacyStartedAt,
            items: secondItems,
            stateFingerprint: source.stateFingerprint
        )
        second.logicalTripID = nil
        var third = ShoppingSession(
            tripID: thirdLegacyTripID,
            recipeID: source.recipeID,
            recipeTitle: source.recipeTitle,
            manifestID: secondManifestID,
            storeID: source.storeID,
            retailerID: source.retailerID,
            desiredServings: source.desiredServings,
            fulfillmentMode: source.fulfillmentMode,
            shoppingScope: source.shoppingScope,
            mealPrepSnapshot: source.mealPrepSnapshot,
            startedAt: legacyStartedAt.addingTimeInterval(2),
            items: thirdItems,
            stateFingerprint: source.stateFingerprint
        )
        third.logicalTripID = nil
        model.shoppingSessions = [first, second, third]
        model.activeShoppingSessionID = first.id
        let firstItem = try firstItems.firstUnwrapped()
        let secondItem = try secondItems.firstUnwrapped()
        let thirdItem = try thirdItems.firstUnwrapped()

        try model.commitShoppingReconciliation(
            sessionID: first.id,
            outcome: .boughtFew,
            purchasedItemIDs: [firstItem.id],
            substitutions: []
        )
        let pantryAfterFirstCommit = model.pantryInventory

        try model.commitShoppingReconciliation(
            sessionID: second.id,
            outcome: .boughtFew,
            purchasedItemIDs: [secondItem.id],
            substitutions: []
        )

        XCTAssertEqual(model.pantryInventory, pantryAfterFirstCommit)
        XCTAssertTrue(model.shoppingSession(id: first.id)?.isCommitted == true)
        XCTAssertTrue(model.shoppingSession(id: second.id)?.isCommitted == true)
        XCTAssertEqual(
            model.shoppingSession(id: first.id)?.reconciliationIdentity,
            model.shoppingSession(id: second.id)?.reconciliationIdentity
        )
        XCTAssertEqual(
            model.shoppingSession(id: second.id)?.reconciliation?.purchasedItemIDs,
            [secondItem.id]
        )

        try model.commitShoppingReconciliation(
            sessionID: third.id,
            outcome: .boughtFew,
            purchasedItemIDs: [thirdItem.id],
            substitutions: []
        )
        XCTAssertNotEqual(model.pantryInventory, pantryAfterFirstCommit)
        XCTAssertTrue(model.shoppingSession(id: third.id)?.isCommitted == true)
        XCTAssertNotEqual(
            model.shoppingSession(id: first.id)?.reconciliationIdentity,
            model.shoppingSession(id: third.id)?.reconciliationIdentity
        )
    }

    @MainActor
    func testDistinctLegacyTripsWithReusedManifestCanBothUpdatePantry() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let source = try model.shoppingSessions.firstUnwrapped()
        let first = ShoppingSession(
            tripID: nil,
            recipeID: source.recipeID,
            recipeTitle: source.recipeTitle,
            manifestID: source.manifestID,
            storeID: source.storeID,
            retailerID: source.retailerID,
            desiredServings: source.desiredServings,
            fulfillmentMode: source.fulfillmentMode,
            shoppingScope: source.shoppingScope,
            mealPrepSnapshot: source.mealPrepSnapshot,
            startedAt: source.startedAt,
            items: source.items,
            stateFingerprint: source.stateFingerprint
        )
        model.shoppingSessions = [first]
        let item = try source.items.firstUnwrapped()

        try model.commitShoppingReconciliation(
            sessionID: first.id,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: []
        )
        let firstCommittedAt = try XCTUnwrap(
            model.shoppingSession(id: first.id)?.reconciliation?.committedAt
        )
        let second = ShoppingSession(
            tripID: nil,
            recipeID: source.recipeID,
            recipeTitle: source.recipeTitle,
            manifestID: source.manifestID,
            storeID: source.storeID,
            retailerID: source.retailerID,
            desiredServings: source.desiredServings,
            fulfillmentMode: source.fulfillmentMode,
            shoppingScope: source.shoppingScope,
            mealPrepSnapshot: source.mealPrepSnapshot,
            startedAt: firstCommittedAt.addingTimeInterval(60),
            items: source.items,
            stateFingerprint: source.stateFingerprint
        )
        model.shoppingSessions.append(second)
        try model.commitShoppingReconciliation(
            sessionID: second.id,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: []
        )

        XCTAssertEqual(
            model.pantryInventory.first?.packageCount,
            Double(item.purchaseQuantity * 2)
        )
        XCTAssertTrue(model.shoppingSession(id: first.id)?.isCommitted == true)
        XCTAssertTrue(model.shoppingSession(id: second.id)?.isCommitted == true)
        XCTAssertNotEqual(
            model.shoppingSession(id: first.id)?.reconciliationIdentity,
            model.shoppingSession(id: second.id)?.reconciliationIdentity
        )
    }

    @MainActor
    func testSubstitutionUpdatesPantryAndPreferenceOnlyWithExplicitOptIn() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, seedDemoShoppingState: true)
        let item = try model.shoppingItems.first(where: { !$0.alternatives.isEmpty }).firstUnwrapped()
        let replacement = try item.alternatives.firstUnwrapped()
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        let feedback = ShoppingSubstitutionFeedback(
            originalItemID: item.id,
            replacementName: replacement.name,
            replacementBrand: replacement.brand,
            replacementRetailerProductID: replacement.retailerProductID,
            replacementGTIN14: replacement.gtin,
            packageQuantity: replacement.packageQuantity,
            packageUnit: replacement.packageUnit,
            replacementAmount: 3,
            preferNextTime: true
        )

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: [feedback]
        )

        XCTAssertEqual(model.pantryInventory.first?.name, replacement.name)
        XCTAssertEqual(model.pantryInventory.first?.quantity, 3)
        XCTAssertEqual(model.pantryInventory.first?.packageCount, 3)
        if let packageSize = replacement.packageQuantity {
            XCTAssertEqual(model.pantryInventory.first?.remainingAmount, 3 * packageSize)
            XCTAssertEqual(model.pantryInventory.first?.remainingUnit, replacement.packageUnit)
        }
        XCTAssertEqual(
            model.pantryInventory.first?.preferredRetailerProductID,
            "\(replacement.retailerID):\(replacement.retailerProductID)"
        )
        XCTAssertTrue(model.preferredProductIDsByIngredient.values.contains(replacement.retailerProductID))
        XCTAssertEqual(
            model.shoppingSession(id: sessionID)?.reconciliation?.substitutions.first?.replacementName,
            replacement.name
        )
    }

    @MainActor
    func testReplacementPackageSizeDerivesAndCommitsCorrectPantryAmount() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore(), seedDemoShoppingState: true)
        let itemIndex = try XCTUnwrap(model.shoppingItems.firstIndex(where: { !$0.alternatives.isEmpty }))
        model.shoppingItems[itemIndex].ingredient.quantity = 2
        model.shoppingItems[itemIndex].ingredient.unit = "lb"
        model.shoppingItems[itemIndex].requestedQuantity = "2 lb"
        model.shoppingItems[itemIndex].requestedAmount = 2
        var replacement = try model.shoppingItems[itemIndex].alternatives.firstUnwrapped()
        replacement.packageDescription = "8 oz replacement package"
        replacement.packageQuantity = 8
        replacement.packageUnit = "oz"
        let item = model.shoppingItems[itemIndex]
        let derivedCount = try XCTUnwrap(
            model.resolvedReplacementPackageCount(for: item, product: replacement)
        )
        XCTAssertEqual(derivedCount, 4)
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        let feedback = ShoppingSubstitutionFeedback(
            originalItemID: item.id,
            replacementName: replacement.name,
            replacementBrand: replacement.brand,
            replacementRetailerProductID: replacement.retailerProductID,
            replacementGTIN14: replacement.gtin,
            packageQuantity: replacement.packageQuantity,
            packageUnit: replacement.packageUnit,
            replacementAmount: Double(derivedCount)
        )

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: [feedback]
        )

        XCTAssertEqual(model.pantryInventory.first?.packageCount, 4)
        XCTAssertEqual(model.pantryInventory.first?.packageSize, 8)
        XCTAssertEqual(model.pantryInventory.first?.packageUnit, "oz")
        XCTAssertEqual(model.pantryInventory.first?.remainingAmount, 32)
        XCTAssertEqual(
            model.shoppingSession(id: sessionID)?.reconciliation?.acquisitions?.first?.amount,
            4
        )
    }

    @MainActor
    func testUnknownReplacementQuantityBlocksPantryCommit() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore(), seedDemoShoppingState: true)
        let item = try model.shoppingItems.firstUnwrapped()
        var unknownProduct = item.product
        unknownProduct.packageQuantity = nil
        unknownProduct.packageUnit = nil
        XCTAssertNil(model.resolvedReplacementPackageCount(for: item, product: unknownProduct))
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        let originalPantry = model.pantryInventory
        let feedback = ShoppingSubstitutionFeedback(
            originalItemID: item.id,
            replacementName: "Unmeasured replacement",
            packageQuantity: nil,
            packageUnit: nil,
            replacementAmount: nil
        )

        XCTAssertThrowsError(
            try model.commitShoppingReconciliation(
                sessionID: sessionID,
                outcome: .boughtFew,
                purchasedItemIDs: [item.id],
                substitutions: [feedback]
            )
        ) { error in
            XCTAssertEqual(
                error as? ShoppingReconciliationError,
                .replacementQuantityConfirmationRequired(item.id)
            )
        }
        XCTAssertEqual(model.pantryInventory, originalPantry)
        XCTAssertFalse(model.shoppingSession(id: sessionID)?.isCommitted == true)
    }

    @MainActor
    func testConfirmedUnknownReplacementDoesNotInheritOriginalPackageMetadata() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore(), seedDemoShoppingState: true)
        let item = try model.shoppingItems.firstUnwrapped()
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        let feedback = ShoppingSubstitutionFeedback(
            originalItemID: item.id,
            replacementName: "Loose market replacement",
            replacementBrand: "Market counter",
            packageQuantity: nil,
            packageUnit: nil,
            replacementAmount: 2
        )

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: [feedback]
        )

        let added = try XCTUnwrap(model.pantryInventory.first)
        XCTAssertEqual(added.packageCount, 2)
        XCTAssertNil(added.packageSize)
        XCTAssertNil(added.packageUnit)
        XCTAssertEqual(added.remainingAmount, 2)
        XCTAssertEqual(added.remainingUnit, "package")
        XCTAssertNil(added.preferredRetailerProductID)
    }

    @MainActor
    func testCrossDomainPreShoppingReplacementIsRejectedWithoutMutation() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore(), seedDemoShoppingState: true)
        let index = try XCTUnwrap(model.shoppingItems.firstIndex(where: { !$0.alternatives.isEmpty }))
        let original = model.shoppingItems[index]
        var incompatible = try original.alternatives.firstUnwrapped()
        incompatible.packageQuantity = 16
        incompatible.packageUnit = "oz"
        model.shoppingItems[index].ingredient.unit = "count"
        model.shoppingItems[index].requestedAmount = 2
        model.shoppingItems[index].alternatives = [incompatible]

        model.selectAlternative(itemID: original.id, candidateID: incompatible.id)

        let unchanged = try XCTUnwrap(model.shoppingItems.first(where: { $0.id == original.id }))
        XCTAssertEqual(unchanged.product.id, original.product.id)
        XCTAssertEqual(unchanged.purchaseQuantity, original.purchaseQuantity)
    }

    @MainActor
    func testDidNotShopLeavesPantryAndPreferencesUnchanged() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            seedDemoShoppingState: true
        )
        model.pantryInventory = [PantryInventoryItem(name: "Flour", quantity: 1, unit: "bag")]
        let originalPantry = model.pantryInventory
        let originalPreferences = model.preferredProductIDsByIngredient
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .didNotShop,
            purchasedItemIDs: Set(model.shoppingItems.map(\.id)),
            substitutions: []
        )

        XCTAssertEqual(model.pantryInventory, originalPantry)
        XCTAssertEqual(model.preferredProductIDsByIngredient, originalPreferences)
        XCTAssertTrue(
            model.shoppingSession(id: sessionID)?.reconciliation?.purchasedItemIDs.isEmpty == true
        )
    }

    @MainActor
    func testReconciliationDoesNotMergeGenericOrVariantNameFallbacks() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            seedDemoShoppingState: true
        )
        let item = try model.shoppingItems.firstUnwrapped()
        model.pantryInventory = [
            PantryInventoryItem(
                name: item.product.name,
                brand: "",
                quantity: 1,
                unit: "package",
                packageSize: item.product.packageQuantity,
                packageUnit: item.product.packageUnit
            ),
            PantryInventoryItem(
                name: "Low Fat \(item.product.name)",
                brand: item.product.brand,
                quantity: 1,
                unit: "package",
                packageSize: item.product.packageQuantity,
                packageUnit: item.product.packageUnit
            )
        ]
        let originalIDs = Set(model.pantryInventory.map(\.id))
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: []
        )

        XCTAssertEqual(model.pantryInventory.count, 3)
        XCTAssertTrue(originalIDs.isSubset(of: Set(model.pantryInventory.map(\.id))))
    }

    @MainActor
    func testShoppingSessionFingerprintForksCommittedQuantityButUpdatesActiveProduct() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            seedDemoShoppingState: true
        )
        let originalItemIDs = model.shoppingItems.map(\.id)
        let firstSessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        try model.commitShoppingReconciliation(
            sessionID: firstSessionID,
            outcome: .didNotShop,
            purchasedItemIDs: [],
            substitutions: []
        )

        let replacementTripID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        XCTAssertNotEqual(replacementTripID, firstSessionID)

        model.shoppingItems[0].purchaseQuantity += 1
        let quantitySessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        XCTAssertNotEqual(quantitySessionID, replacementTripID)
        XCTAssertEqual(model.shoppingItems.map(\.id), originalItemIDs)

        let replaceableItem = try model.shoppingItems
            .first(where: { !$0.alternatives.isEmpty })
            .firstUnwrapped()
        let alternative = try replaceableItem.alternatives.firstUnwrapped()
        model.selectAlternative(
            itemID: replaceableItem.id,
            candidateID: alternative.id
        )
        let productSessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        XCTAssertEqual(productSessionID, quantitySessionID)
        XCTAssertEqual(model.shoppingItems.map(\.id), originalItemIDs)
    }

    @MainActor
    func testBeginRecipeEntersRecipeReadyAndPantrySuggestionDefaultsToBuyingFullAmount() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.pantryInventory = [
            PantryInventoryItem(
                name: "All-purpose flour",
                quantity: 1,
                unit: "bag",
                packageSize: 1,
                packageUnit: "cup"
            )
        ]

        model.beginRecipe(RecipeParser.parse(title: "Cookies", text: "2 cups all-purpose flour"))

        let ingredient = try model.activeRecipe.ingredients.firstUnwrapped()
        XCTAssertEqual(model.homePath, [.recipeReady])
        XCTAssertEqual(ingredient.pantryDecision, .review)
        XCTAssertEqual(model.quantityToBuy(for: ingredient), 2, accuracy: 0.001)
        XCTAssertEqual(model.recipeReadyPantrySuggestionCount, 1)
        XCTAssertTrue(model.recipeReadyCanStartShopping)
    }

    @MainActor
    func testRecipeReadyServingChangeUpdatesScaledQuantityAndRefreshesPantrySuggestion() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.pantryInventory = [
            PantryInventoryItem(name: "Flour", remainingAmount: 1, remainingUnit: "cup")
        ]
        let recipe = Recipe(
            title: "Bread",
            source: .text,
            sourceDetail: "Test",
            heroSymbol: "fork.knife",
            servings: 2,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: [Ingredient(name: "Flour", quantity: 2, unit: "cup")]
        )
        model.beginRecipe(recipe)
        let ingredientID = try model.activeRecipe.ingredients.firstUnwrapped().id

        model.updateServings(by: 2)

        let updated = try model.activeRecipe.ingredients.first { $0.id == ingredientID }.firstUnwrapped()
        XCTAssertEqual(model.desiredServings, 4)
        XCTAssertEqual(model.scaledQuantity(for: updated), 4, accuracy: 0.001)
        XCTAssertEqual(updated.pantrySuggestion?.coverage, .partial)
        XCTAssertEqual(updated.pantryDecision, .review)
        XCTAssertEqual(model.quantityToBuy(for: updated), 4, accuracy: 0.001)
    }

    @MainActor
    func testRecipeReadyReusesPersistedRetailerPreferencesAndDetectsMissingSetup() {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let fresh = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertFalse(fresh.retailerSetupIsComplete)

        fresh.preferences.organicPolicy = .only
        fresh.preferences.dietaryRestrictions = [.glutenFree]
        fresh.startRetailerGuide(.target)
        fresh.completeRetailerSetup()

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.selectedRetailer, .target)
        XCTAssertEqual(restored.preferences.organicPolicy, .only)
        XCTAssertEqual(restored.preferences.dietaryRestrictions, [.glutenFree])
        XCTAssertTrue(restored.retailerSetupIsComplete)
    }

    @MainActor
    func testMealPrepReviewConvergesIntoRecipeReady() {
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        let recipe = Recipe(
            title: "Pasta",
            source: .text,
            sourceDetail: "Test",
            heroSymbol: "fork.knife",
            servings: 2,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: [Ingredient(name: "Penne pasta", quantity: 8, unit: "oz")]
        )
        model.mealPrepDraft = MealPrepDraft(selections: [
            MealPrepSelection(recipe: recipe, targetServings: 2)
        ])

        XCTAssertTrue(model.buildMealPrepPlan())
        model.openMealPrepDashboard()

        XCTAssertEqual(model.homePath.last, .recipeReady)
        XCTAssertEqual(model.recipeReadyBlockingIssueCount, 0)
        XCTAssertEqual(model.recipeReadyExpectedPurchaseCount, 1)
    }

    func testMatchingPipelineContainsNoArtificialSleep() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("SmartCart/Models/AppModel.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "    func startMatching(")?.lowerBound)
        let end = try XCTUnwrap(
            source.range(
                of: "    func updatePurchaseQuantity",
                range: start..<source.endIndex
            )?.lowerBound
        )

        XCTAssertFalse(source[start..<end].contains("Task.sleep"))
    }

    @MainActor
    func testAllHighConfidenceExactMatchesHaveNoExceptions() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        model.beginRecipe(
            phase2Recipe(ingredients: [
                Ingredient(name: "Penne pasta", quantity: 16, unit: "oz"),
                Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
            ])
        )

        await model.startMatching()

        XCTAssertEqual(model.shoppingItems.count, 2)
        XCTAssertTrue(model.shoppingItems.allSatisfy {
            $0.product.isExactProductLink && $0.product.confidence == .high
        })
        XCTAssertTrue(model.unresolvedMatchingExceptionItems.isEmpty)
        XCTAssertTrue(model.continueToShoppingTrip())
        XCTAssertEqual(model.homePath.last, .shoppingTrip)
    }

    @MainActor
    func testFallbackAndLowConfidenceMatchesBlockOnlyUntilEachIsAccepted() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        model.beginRecipe(
            phase2Recipe(ingredients: [
                Ingredient(name: "Dragon fruit jam", quantity: 1, unit: "jar"),
                Ingredient(name: "Garlic", quantity: 2, unit: "count")
            ])
        )
        model.startRetailerGuide(.target)

        await model.startMatching()

        let fallback = try model.unresolvedMatchingExceptionItems
            .first(where: { $0.product.linkKind == .searchResults })
            .firstUnwrapped()
        let lowConfidence = try model.unresolvedMatchingExceptionItems
            .first(where: {
                $0.product.isExactProductLink && $0.product.confidence != .high
            })
            .firstUnwrapped()
        XCTAssertEqual(model.unresolvedMatchingExceptionItems.count, 2)
        XCTAssertFalse(model.matchingExceptionReasons(for: fallback).isEmpty)
        XCTAssertFalse(model.matchingExceptionReasons(for: lowConfidence).isEmpty)
        XCTAssertFalse(model.continueToShoppingTrip())

        XCTAssertTrue(model.acceptMatchingException(itemID: fallback.id))
        XCTAssertEqual(model.unresolvedMatchingExceptionItems.map(\.id), [lowConfidence.id])
        XCTAssertFalse(model.continueToShoppingTrip())

        XCTAssertTrue(model.acceptMatchingException(itemID: lowConfidence.id))
        XCTAssertTrue(model.unresolvedMatchingExceptionItems.isEmpty)
        for itemID in [fallback.id, lowConfidence.id] {
            let reviewed = try model.shoppingItems
                .first(where: { $0.id == itemID })
                .firstUnwrapped()
            XCTAssertEqual(reviewed.reviewedMatchingFingerprint, reviewed.matchingInputFingerprint)
        }
        XCTAssertTrue(model.continueToShoppingTrip())
        XCTAssertEqual(model.homePath.last, .shoppingTrip)
    }

    @MainActor
    func testManualProductSelectionSurvivesUnrelatedIngredientEdit() async throws {
        let pasta = Ingredient(name: "Penne pasta", quantity: 8, unit: "oz")
        let oil = Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        model.beginRecipe(phase2Recipe(ingredients: [pasta, oil]))
        await model.startMatching()

        let originalPasta = try model.shoppingItems
            .first(where: { $0.id == pasta.id })
            .firstUnwrapped()
        let originalOil = try model.shoppingItems
            .first(where: { $0.id == oil.id })
            .firstUnwrapped()
        let alternative = try originalPasta.alternatives
            .first(where: { $0.isExactProductLink && $0.confidence == .high })
            .firstUnwrapped()
        model.selectAlternative(itemID: pasta.id, candidateID: alternative.id)
        let manuallySelected = try model.shoppingItems
            .first(where: { $0.id == pasta.id })
            .firstUnwrapped()
        XCTAssertEqual(manuallySelected.product.id, alternative.id)

        // Remove the durable preference so this assertion exercises plan reuse,
        // rather than the catalog independently choosing the same saved product.
        model.preferredProductIDsByIngredient = [:]
        var editedRecipe = model.activeRecipe
        let oilIndex = try XCTUnwrap(editedRecipe.ingredients.firstIndex(where: { $0.id == oil.id }))
        editedRecipe.ingredients[oilIndex].name = "Heavy cream"
        model.activeRecipe = editedRecipe

        await model.startMatching()

        let preservedPasta = try model.shoppingItems
            .first(where: { $0.id == pasta.id })
            .firstUnwrapped()
        let rebuiltOtherItem = try model.shoppingItems
            .first(where: { $0.id == oil.id })
            .firstUnwrapped()
        XCTAssertEqual(preservedPasta.product.id, manuallySelected.product.id)
        XCTAssertEqual(
            preservedPasta.matchingInputFingerprint,
            manuallySelected.matchingInputFingerprint
        )
        XCTAssertNotEqual(rebuiltOtherItem.ingredient.name, oil.name)
        XCTAssertNotEqual(
            rebuiltOtherItem.matchingInputFingerprint,
            originalOil.matchingInputFingerprint
        )
    }

    @MainActor
    func testQuantityOnlyChangePreservesProductAndRecalculatesPackages() async throws {
        let pasta = Ingredient(name: "Penne pasta", quantity: 8, unit: "oz")
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        model.beginRecipe(phase2Recipe(ingredients: [pasta]))
        await model.startMatching()

        let original = try model.shoppingItems.firstUnwrapped()
        let alternative = try original.alternatives
            .first(where: { $0.isExactProductLink && $0.confidence == .high })
            .firstUnwrapped()
        model.selectAlternative(itemID: pasta.id, candidateID: alternative.id)
        let selected = try model.shoppingItems.firstUnwrapped()
        model.preferredProductIDsByIngredient = [:]

        var editedRecipe = model.activeRecipe
        editedRecipe.ingredients[0].quantity = 40
        model.activeRecipe = editedRecipe
        await model.startMatching()

        let updated = try model.shoppingItems.firstUnwrapped()
        XCTAssertEqual(updated.product.id, selected.product.id)
        XCTAssertEqual(updated.requestedAmount ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(
            updated.purchaseQuantity,
            PackageMath.packageCount(
                product: selected.product,
                requestedQuantity: 40,
                requestedUnit: "oz"
            )
        )
        XCTAssertNotEqual(updated.purchaseQuantity, selected.purchaseQuantity)
        XCTAssertNotEqual(updated.matchingInputFingerprint, selected.matchingInputFingerprint)
    }

    @MainActor
    func testRetailerAndStoreChangesRebuildMatchingContext() async throws {
        let pasta = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        model.beginRecipe(phase2Recipe(ingredients: [pasta]))
        await model.startMatching()
        let original = try model.shoppingItems.firstUnwrapped()
        XCTAssertNotNil(original.matchingContextFingerprint)

        let otherWalmartStore = try model.stores
            .first(where: {
                $0.retailerID == ShoppingRetailer.walmart.rawValue &&
                    $0.id != model.primaryStore.id
            })
            .firstUnwrapped()
        model.selectStore(otherWalmartStore)
        await model.startMatching()
        let storeRebuilt = try model.shoppingItems.firstUnwrapped()

        XCTAssertEqual(storeRebuilt.product.storeID, otherWalmartStore.retailerStoreID)
        XCTAssertNotEqual(
            storeRebuilt.matchingContextFingerprint,
            original.matchingContextFingerprint
        )

        model.startRetailerGuide(.target)
        await model.startMatching()
        let retailerRebuilt = try model.shoppingItems.firstUnwrapped()

        XCTAssertEqual(retailerRebuilt.product.retailerID, ShoppingRetailer.target.rawValue)
        XCTAssertNotEqual(
            retailerRebuilt.matchingContextFingerprint,
            storeRebuilt.matchingContextFingerprint
        )
    }

    @MainActor
    func testOrganicAndDietaryChangesRebuildAffectedMatches() async throws {
        let organicModel = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        var initialPreferences = organicModel.preferences
        initialPreferences.organicPolicy = .noPreference
        organicModel.preferences = initialPreferences
        organicModel.beginRecipe(
            phase2Recipe(ingredients: [
                Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
            ])
        )
        await organicModel.startMatching()
        let conventional = try organicModel.shoppingItems.firstUnwrapped()
        XCTAssertFalse(conventional.product.organicStatus.isOrganic)

        var organicOnly = organicModel.preferences
        organicOnly.organicPolicy = .only
        organicModel.preferences = organicOnly
        await organicModel.startMatching()
        let organic = try organicModel.shoppingItems.firstUnwrapped()

        XCTAssertTrue(organic.product.organicStatus.isOrganic)
        XCTAssertNotEqual(organic.product.id, conventional.product.id)
        XCTAssertNotEqual(
            organic.matchingContextFingerprint,
            conventional.matchingContextFingerprint
        )

        let dietaryModel = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        var unrestricted = dietaryModel.preferences
        unrestricted.organicPolicy = .noPreference
        dietaryModel.preferences = unrestricted
        dietaryModel.beginRecipe(
            phase2Recipe(ingredients: [
                Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
            ])
        )
        await dietaryModel.startMatching()
        let standard = try dietaryModel.shoppingItems.firstUnwrapped()
        XCTAssertFalse(standard.product.dietaryAttributes.contains(.glutenFree))

        var glutenFree = dietaryModel.preferences
        glutenFree.dietaryRestrictions = [.glutenFree]
        dietaryModel.preferences = glutenFree
        await dietaryModel.startMatching()
        let restricted = try dietaryModel.shoppingItems.firstUnwrapped()

        XCTAssertTrue(restricted.product.dietaryAttributes.contains(.glutenFree))
        XCTAssertNotEqual(restricted.product.id, standard.product.id)
        XCTAssertNotEqual(
            restricted.matchingContextFingerprint,
            standard.matchingContextFingerprint
        )
    }

    @MainActor
    func testAddingAndRemovingIngredientsPreservesUnchangedSelection() async throws {
        let pasta = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let oil = Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
        let cream = Ingredient(name: "Heavy cream", quantity: 1, unit: "cup")
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        model.beginRecipe(phase2Recipe(ingredients: [pasta, oil]))
        await model.startMatching()

        let originalOil = try model.shoppingItems
            .first(where: { $0.id == oil.id })
            .firstUnwrapped()
        let alternative = try originalOil.alternatives
            .first(where: { $0.isExactProductLink && $0.confidence == .high })
            .firstUnwrapped()
        model.selectAlternative(itemID: oil.id, candidateID: alternative.id)
        let selectedOil = try model.shoppingItems
            .first(where: { $0.id == oil.id })
            .firstUnwrapped()
        model.preferredProductIDsByIngredient = [:]

        var addedRecipe = model.activeRecipe
        addedRecipe.ingredients.append(cream)
        model.activeRecipe = addedRecipe
        await model.startMatching()

        XCTAssertEqual(
            Set(model.shoppingItems.map(\.id)),
            Set([pasta.id, oil.id, cream.id])
        )
        XCTAssertEqual(
            model.shoppingItems.first(where: { $0.id == oil.id })?.product.id,
            selectedOil.product.id
        )

        var removedRecipe = model.activeRecipe
        removedRecipe.ingredients.removeAll { $0.id == pasta.id }
        model.activeRecipe = removedRecipe
        await model.startMatching()

        XCTAssertEqual(Set(model.shoppingItems.map(\.id)), Set([oil.id, cream.id]))
        XCTAssertEqual(
            model.shoppingItems.first(where: { $0.id == oil.id })?.product.id,
            selectedOil.product.id
        )
    }

    @MainActor
    func testActiveAndCompletedSessionItemsAreNeverReusedOrMutated() async throws {
        let activePasta = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let activeOil = Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
        let activeModel = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        activeModel.beginRecipe(phase2Recipe(ingredients: [activePasta, activeOil]))
        await activeModel.startMatching()
        activeModel.completeRetailerSetup()
        XCTAssertTrue(activeModel.startOrResumeRetailerShoppingSession())
        let activeSessionID = try XCTUnwrap(activeModel.activeShoppingSessionID)
        activeModel.recordRetailerOutcome(
            .unavailable,
            for: activePasta.id,
            sessionID: activeSessionID
        )
        XCTAssertFalse(activeModel.retailerGuideIsComplete)
        let activeSnapshot = try XCTUnwrap(activeModel.shoppingSession(id: activeSessionID))

        var editedActiveRecipe = activeModel.activeRecipe
        editedActiveRecipe.ingredients[0].quantity = 40
        activeModel.activeRecipe = editedActiveRecipe
        await activeModel.startMatching()

        XCTAssertNil(activeModel.activeShoppingSessionID)
        XCTAssertEqual(activeModel.shoppingSession(id: activeSessionID), activeSnapshot)
        XCTAssertTrue(activeModel.shoppingItems.allSatisfy { $0.status == .waiting })

        let completedPasta = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let completedModel = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        completedModel.beginRecipe(phase2Recipe(ingredients: [completedPasta]))
        await completedModel.startMatching()
        completedModel.completeRetailerSetup()
        XCTAssertTrue(completedModel.startOrResumeRetailerShoppingSession())
        let completedSessionID = try XCTUnwrap(completedModel.activeShoppingSessionID)
        completedModel.recordRetailerOutcome(
            .savedToWishlist,
            for: completedPasta.id,
            sessionID: completedSessionID
        )
        XCTAssertTrue(completedModel.retailerGuideIsComplete)
        let completedSnapshot = try XCTUnwrap(
            completedModel.shoppingSession(id: completedSessionID)
        )

        var editedCompletedRecipe = completedModel.activeRecipe
        editedCompletedRecipe.ingredients[0].quantity = 40
        completedModel.activeRecipe = editedCompletedRecipe
        await completedModel.startMatching()

        XCTAssertNil(completedModel.activeShoppingSessionID)
        XCTAssertEqual(
            completedModel.shoppingSession(id: completedSessionID),
            completedSnapshot
        )
        XCTAssertTrue(completedModel.shoppingItems.allSatisfy { $0.status == .waiting })
    }

    private func phase2Recipe(ingredients: [Ingredient]) -> Recipe {
        Recipe(
            title: "Phase 2 Matching",
            source: .text,
            sourceDetail: "Tests",
            heroSymbol: "cart.fill",
            servings: 2,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: ingredients
        )
    }

    private func searchRequest(
        for name: String,
        quantity: Double = 1,
        unit: String
    ) -> RetailerProductSearchRequest {
        RetailerProductSearchRequest(
            ingredient: Ingredient(name: name, quantity: quantity, unit: unit),
            requestedQuantity: quantity,
            requestedUnit: unit,
            storeID: "walmart-5206",
            fulfillmentMethod: .pickup
        )
    }

    private func exactProducts(
        for name: String,
        unit: String
    ) -> [RetailerProductRecord] {
        let ingredient = Ingredient(name: name, unit: unit)
        return DemoWalmartCatalogService.seededProducts(
            for: ingredient,
            storeID: "walmart-5206"
        )
        .filter(\.isExactProductLink)
    }

    private func makeState() throws -> SmartCartPersistedState {
        let recipe = Recipe(
            title: "Pasta",
            source: .sample,
            sourceDetail: "Tests",
            heroSymbol: "fork.knife",
            servings: 4,
            prepMinutes: 10,
            cookMinutes: 20,
            ingredients: [Ingredient(name: "Penne pasta", quantity: 24, unit: "oz")]
        )
        let product = try exactProducts(for: "Penne pasta", unit: "oz").firstUnwrapped()
        let item = ShoppingListItem(
            ingredient: recipe.ingredients[0],
            requestedQuantity: "24 oz",
            purchaseQuantity: 2,
            product: product,
            alternatives: [],
            storeID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            matchScore: 100,
            selectionReasons: ["Exact product"]
        )
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let manifest = ShoppingManifest(
            recipeID: recipe.id,
            recipeTitle: recipe.title,
            retailerID: "walmart",
            storeID: "walmart-5206",
            storeName: "Walmart Supercenter A",
            desiredServings: 4,
            fulfillmentMode: .pickup,
            items: [
                ManifestLineItem(
                    ingredientID: item.ingredient.id,
                    ingredientName: item.ingredient.name,
                    requestedQuantity: item.requestedQuantity,
                    purchaseQuantity: item.purchaseQuantity,
                    product: item.product,
                    status: .waiting
                )
            ],
            createdAt: timestamp,
            updatedAt: timestamp.addingTimeInterval(60)
        )

        return SmartCartPersistedState(
            recipes: [recipe],
            activeRecipe: recipe,
            desiredServings: 4,
            preferences: ShoppingPreferences(),
            featureFlags: AppFeatureFlags(),
            storeStrategy: .oneStore,
            fulfillmentMode: .pickup,
            selectedStoreIDs: [item.storeID],
            zipCode: "90210",
            pickupDay: "Today",
            pickupTime: "4:30–5:30 PM",
            shoppingItems: [item],
            guidedIndex: 0,
            savedLists: [SavedShoppingList(manifest: manifest)],
            preferredDeliveryPartnerName: nil,
            pantryInventory: [],
            preferredProductIDsByIngredient: [:],
            analyticsEvents: []
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartCartTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func isolatedCommerceDefaults() -> UserDefaults {
        let name = "SmartCartTests-Commerce-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }
}

private actor RecordingInstacartHandoffService: InstacartHandoffServicing {
    func createHandoff(
        draft: InstacartManifestDraft,
        postalCode: String,
        preferredRetailer: InstacartRetailerPreference,
        fulfillment: CommerceFulfillmentPreference
    ) async throws -> InstacartHandoffResponse {
        InstacartHandoffResponse(
            provider: "instacart",
            url: URL(string: "https://www.instacart.com/store/shopping_lists/test")!,
            manifestFingerprint: "sha256:test",
            createdAt: Date(timeIntervalSince1970: 0),
            presentationMode: "in_app_safari"
        )
    }
}

private final class ControllableSmartCartStateStore: SmartCartStateStoring {
    enum Failure: Error { case requested }

    var state: SmartCartPersistedState?
    var failNextSave = false

    func load() throws -> SmartCartPersistedState? { state }

    func save(_ state: SmartCartPersistedState) throws {
        if failNextSave {
            failNextSave = false
            throw Failure.requested
        }
        self.state = state
    }
}

private extension Optional {
    func firstUnwrapped(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Wrapped {
        try XCTUnwrap(self, file: file, line: line)
    }
}

private extension Array {
    func firstUnwrapped(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Element {
        try first.firstUnwrapped(file: file, line: line)
    }
}
