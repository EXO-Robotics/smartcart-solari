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

    @MainActor
    func testTargetComparisonURLResearchesCurrentIngredientWithoutChangingRetailer() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            seedDemoShoppingState: true
        )
        model.preferences.organicPolicy = .only
        let item = try XCTUnwrap(model.shoppingItems.first)
        let selectedRetailer = model.selectedRetailer
        let selectedProduct = item.product

        let url = model.targetSearchURL(for: item)

        XCTAssertEqual(url.host, "www.target.com")
        XCTAssertTrue(url.absoluteString.localizedCaseInsensitiveContains("organic"))
        for term in item.ingredient.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            XCTAssertTrue(url.absoluteString.localizedCaseInsensitiveContains(term))
        }
        XCTAssertEqual(model.selectedRetailer, selectedRetailer)
        XCTAssertEqual(model.shoppingItems.first?.product, selectedProduct)
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

    func testCrossRegionBananaPeanutButterOCRContaminationRegression() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Fixtures/OCR/cross_region_banana_peanut_butter_observations.json"
            )
        let observations = try JSONDecoder().decode(
            [OCRTextObservation].self,
            from: Data(contentsOf: fixtureURL)
        )

        let reconstruction = OCRLayoutReconstructor.reconstruct(observations)
        let saltLine = try reconstruction.ingredientSourceLines.first(where: {
            $0.sourceObservationIDs.contains("salt")
        }).firstUnwrapped()

        XCTAssertEqual(saltLine.text, "• Flaky Sea Salt for topping")
        XCTAssertEqual(
            saltLine.sourceObservationIDs,
            ["salt", "salt-continuation"]
        )
        XCTAssertFalse(saltLine.text.localizedCaseInsensitiveContains("sourdough"))
        XCTAssertFalse(saltLine.text.localizedCaseInsensitiveContains("mash banana"))
        XCTAssertFalse(reconstruction.ingredientLines.contains {
            $0.localizedCaseInsensitiveContains("stir in peanut butter")
        })

        let recipe = RecipeParser.parse(
            title: "Banana Peanut Butter Card",
            text: reconstruction.reconstructedText,
            source: .photo,
            sourceLines: reconstruction.ingredientSourceLines
        )
        XCTAssertEqual(recipe.ingredients.map(\.name), ["Flaky Sea Salt"])
        let salt = try recipe.ingredients.firstUnwrapped()
        XCTAssertEqual(salt.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(salt.preparation, "for topping")
        XCTAssertEqual(salt.confidence, .review)
    }

    func testOCRPhysicalRowsRequireHorizontalContinuity() {
        let observations = [
            OCRTextObservation(
                observationID: "left",
                text: "Sourdough Discard",
                boundingBox: .init(x: 0.06, y: 0.72, width: 0.22, height: 0.04),
                confidence: 0.96
            ),
            OCRTextObservation(
                observationID: "right",
                text: "Vanilla",
                boundingBox: .init(x: 0.68, y: 0.72, width: 0.12, height: 0.04),
                confidence: 0.96
            )
        ]

        let reconstruction = OCRLayoutReconstructor.reconstruct(observations)

        XCTAssertFalse(reconstruction.ingredientSourceLines.contains { line in
            line.sourceObservationIDs.contains("left")
                && line.sourceObservationIDs.contains("right")
        })
        XCTAssertFalse(reconstruction.ingredientLines.contains {
            $0.localizedCaseInsensitiveContains("sourdough discard vanilla")
        })
    }

    func testOCRRightHandBulletAlwaysStartsItsOwnPhysicalLine() throws {
        let observations = [
            OCRTextObservation(
                observationID: "left-copy",
                text: "Neighboring card copy",
                boundingBox: .init(x: 0.10, y: 0.70, width: 0.28, height: 0.04),
                confidence: 0.95
            ),
            OCRTextObservation(
                observationID: "right-bullet",
                text: "• 1 cup brown sugar",
                boundingBox: .init(x: 0.42, y: 0.70, width: 0.30, height: 0.04),
                confidence: 0.97,
                bulletMarker: "•"
            )
        ]

        let reconstruction = OCRLayoutReconstructor.reconstruct(observations)
        let bulletLine = try reconstruction.ingredientSourceLines.first(where: {
            $0.sourceObservationIDs.contains("right-bullet")
        }).firstUnwrapped()

        XCTAssertEqual(bulletLine.sourceObservationIDs, ["right-bullet"])
        XCTAssertFalse(bulletLine.text.localizedCaseInsensitiveContains("neighboring"))
    }

    func testOCRContinuationRequiresAnchorOverlap() throws {
        let observations = [
            OCRTextObservation(
                observationID: "salt",
                text: "• Flaky sea salt",
                boundingBox: .init(x: 0.08, y: 0.78, width: 0.25, height: 0.04),
                confidence: 0.96,
                bulletMarker: "•"
            ),
            OCRTextObservation(
                observationID: "far-right",
                text: "for topping",
                boundingBox: .init(x: 0.52, y: 0.73, width: 0.18, height: 0.04),
                confidence: 0.94
            )
        ]

        let reconstruction = OCRLayoutReconstructor.reconstruct(observations)
        let saltLine = try reconstruction.ingredientSourceLines.first(where: {
            $0.sourceObservationIDs.contains("salt")
        }).firstUnwrapped()

        XCTAssertEqual(saltLine.sourceObservationIDs, ["salt"])
        XCTAssertFalse(saltLine.continuationAttached)
    }

    func testOCRContinuationCannotChainIndefinitelyAwayFromBulletAnchor() throws {
        let observations = [
            OCRTextObservation(
                observationID: "bullet",
                text: "• 1 cup semi-sweet chocolate",
                boundingBox: .init(x: 0.08, y: 0.80, width: 0.34, height: 0.04),
                confidence: 0.97,
                bulletMarker: "•"
            ),
            OCRTextObservation(
                observationID: "wrap-1",
                text: "chips plus more",
                boundingBox: .init(x: 0.11, y: 0.75, width: 0.24, height: 0.04),
                confidence: 0.95
            ),
            OCRTextObservation(
                observationID: "wrap-2",
                text: "for serving",
                boundingBox: .init(x: 0.12, y: 0.70, width: 0.20, height: 0.04),
                confidence: 0.94
            ),
            OCRTextObservation(
                observationID: "drifted-copy",
                text: "banana bread is delicious",
                boundingBox: .init(x: 0.13, y: 0.63, width: 0.30, height: 0.04),
                confidence: 0.94
            )
        ]

        let reconstruction = OCRLayoutReconstructor.reconstruct(observations)
        let bulletLine = try reconstruction.ingredientSourceLines.first(where: {
            $0.sourceObservationIDs.contains("bullet")
        }).firstUnwrapped()

        XCTAssertTrue(bulletLine.sourceObservationIDs.contains("wrap-1"))
        XCTAssertTrue(bulletLine.sourceObservationIDs.contains("wrap-2"))
        XCTAssertFalse(bulletLine.sourceObservationIDs.contains("drifted-copy"))
        XCTAssertFalse(bulletLine.text.localizedCaseInsensitiveContains("banana bread"))
    }

    func testParserRemovesEmbeddedInstructionSuffixAndRetainsReviewEvidence() throws {
        let original = "1 tsp flaky sea salt, EASY AS 1-2-3! Mash banana. Stir in peanut butter."
        let sourceLine = OCRSourceLine(
            text: original,
            pageIndex: 0,
            boundingBox: .init(x: 0.08, y: 0.72, width: 0.84, height: 0.05),
            confidence: 0.91,
            alternateCandidates: [],
            sourceObservationIDs: ["mixed-line"]
        )

        let recipe = RecipeParser.parse(
            title: "Mixed OCR line",
            text: original,
            source: .photo,
            sourceLines: [sourceLine]
        )

        XCTAssertEqual(recipe.ingredients.count, 1)
        let ingredient = try recipe.ingredients.firstUnwrapped()
        XCTAssertEqual(ingredient.name.lowercased(), "flaky sea salt")
        XCTAssertEqual(ingredient.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(ingredient.unit, "tsp")
        XCTAssertEqual(ingredient.confidence, .review)
        let evidence = try ingredient.sourceEvidence.firstUnwrapped()
        XCTAssertEqual(evidence.rawText, original)
        XCTAssertEqual(evidence.originalLine, original)
        XCTAssertEqual(
            evidence.removedSuffix,
            "EASY AS 1-2-3! Mash banana. Stir in peanut butter."
        )
        XCTAssertTrue(evidence.reviewReasons?.contains("instruction_suffix_removed") == true)
    }

    func testParserTreatsForToppingPreparationTheSameWithOrWithoutComma() throws {
        let variants = [
            "1 tsp flaky sea salt for topping",
            "1 tsp flaky sea salt, for topping"
        ]

        let parsed = variants.map {
            RecipeParser.parse(title: "Salt", text: $0).ingredients.first
        }

        XCTAssertEqual(parsed.compactMap(\.self).count, variants.count)
        for ingredient in parsed.compactMap(\.self) {
            XCTAssertEqual(ingredient.name.lowercased(), "flaky sea salt")
            XCTAssertEqual(ingredient.preparation.lowercased(), "for topping")
        }
    }

    func testParserRejectsStandaloneForToppingEvenWithOCREvidence() {
        let sourceLine = OCRSourceLine(
            text: "for topping",
            pageIndex: 0,
            boundingBox: .init(x: 0.14, y: 0.52, width: 0.22, height: 0.04),
            confidence: 0.94,
            alternateCandidates: [],
            sourceObservationIDs: ["orphan-preparation"]
        )

        let recipe = RecipeParser.parse(
            title: "Orphan preparation",
            text: sourceLine.text,
            source: .photo,
            sourceLines: [sourceLine]
        )

        XCTAssertTrue(recipe.ingredients.isEmpty)
    }

    func testInstructionSanitizerPreservesRangesHyphensAndCommaIngredientNames() throws {
        let text = """
        Ingredients
        2–3 Honeycrisp apples, peeled
        1 cup extra-virgin olive oil
        1 cup tomatoes, fire-roasted
        """
        let recipe = RecipeParser.parse(title: "Valid punctuation", text: text)

        XCTAssertEqual(recipe.ingredients.count, 3)
        let apples = try recipe.ingredients.first(where: {
            $0.name.localizedCaseInsensitiveContains("Honeycrisp apples")
        }).firstUnwrapped()
        XCTAssertEqual(apples.quantityLowerBound, 2)
        XCTAssertEqual(apples.quantity, 3, accuracy: 0.001)
        XCTAssertEqual(apples.preparation.lowercased(), "peeled")
        XCTAssertTrue(recipe.ingredients.contains {
            $0.name.localizedCaseInsensitiveContains("extra-virgin olive oil")
        })
        XCTAssertTrue(recipe.ingredients.contains {
            $0.name.localizedCaseInsensitiveContains("tomatoes")
                && $0.name.localizedCaseInsensitiveContains("fire-roasted")
        })
    }

    func testRecipeSourceDocumentCodableRoundTripPreservesRawAndDerivedRepresentations() throws {
        let focusRegion = OCRFocusRegion(x: 0.12, y: 0.18, width: 0.72, height: 0.54)
        let sourceDocument = RecipeSourceDocument(
            rawRecognizedText: "INGREDIENTS\n1 cup flour\nINSTRUCTIONS\nWhisk until smooth",
            reconstructedText: "1 cup flour",
            filteredIngredientLines: ["1 cup flour"],
            ignoredSourceLines: ["INSTRUCTIONS", "Whisk until smooth"],
            observations: [
                RecipeSourceObservation(
                    observationID: "page-0-vision-0",
                    text: "1 cup flour",
                    pageIndex: 0,
                    boundingBox: .init(x: 0.1, y: 0.7, width: 0.4, height: 0.05),
                    confidence: 0.93,
                    alternatives: [
                        .init(text: "I cup flour", confidence: 0.61)
                    ]
                )
            ],
            focusRegions: [focusRegion]
        )
        let recipe = Recipe(
            title: "Source preservation",
            source: .photo,
            sourceDetail: "Camera",
            heroSymbol: "camera",
            servings: 2,
            prepMinutes: 5,
            cookMinutes: 0,
            ingredients: [Ingredient(name: "Flour", quantity: 1, unit: "cup")],
            rawSourceText: sourceDocument.rawRecognizedText,
            sourceDocument: sourceDocument
        )

        let decoded = try JSONDecoder().decode(
            Recipe.self,
            from: JSONEncoder().encode(recipe)
        )

        XCTAssertEqual(decoded, recipe)
        XCTAssertNotEqual(decoded.sourceDocument?.rawRecognizedText, decoded.sourceDocument?.reconstructedText)
        XCTAssertEqual(decoded.sourceDocument?.ignoredSourceLines.count, 2)
        XCTAssertEqual(decoded.sourceDocument?.observations.first?.observationID, "page-0-vision-0")
        XCTAssertEqual(decoded.sourceDocument?.focusRegions, [focusRegion])
    }

    func testRecipeSourceDocumentDecodesLegacyPayloadWithoutFocusRegions() throws {
        let json = """
        {
          "rawRecognizedText": "1 cup flour",
          "reconstructedText": "1 cup flour",
          "filteredIngredientLines": ["1 cup flour"],
          "ignoredSourceLines": [],
          "observations": []
        }
        """

        let decoded = try JSONDecoder().decode(
            RecipeSourceDocument.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(decoded.focusRegions)
    }

    func testOCRFocusRegionClampsAndRemapsVisionCoordinates() {
        let invalid = OCRFocusRegion(x: .nan, y: 0, width: 0.5, height: 0.5)
        XCTAssertEqual(invalid.normalized(), .fullImage)

        let tiny = OCRFocusRegion(x: 0.98, y: 0.99, width: 0.001, height: 0.001).normalized()
        XCTAssertEqual(tiny.width, 0.08, accuracy: 0.0001)
        XCTAssertEqual(tiny.height, 0.08, accuracy: 0.0001)
        XCTAssertEqual(tiny.x, 0.92, accuracy: 0.0001)
        XCTAssertEqual(tiny.y, 0.92, accuracy: 0.0001)

        let focus = OCRFocusRegion(x: 0.20, y: 0.10, width: 0.50, height: 0.60)
        let remapped = focus.remappingVisionBox(
            OCRNormalizedBoundingBox(x: 0.10, y: 0.20, width: 0.40, height: 0.30)
        )
        XCTAssertEqual(remapped.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(remapped.y, 0.42, accuracy: 0.0001)
        XCTAssertEqual(remapped.width, 0.20, accuracy: 0.0001)
        XCTAssertEqual(remapped.height, 0.18, accuracy: 0.0001)
    }

    func testOCRFocusSuggestionFindsPaddedIngredientBlock() {
        let candidates = [
            focusCandidate("Ingredients", x: 0.12, y: 0.88, width: 0.30),
            focusCandidate("2 cups flour", x: 0.12, y: 0.79, width: 0.42),
            focusCandidate("1 tsp salt", x: 0.12, y: 0.71, width: 0.36),
            focusCandidate("2 large eggs", x: 0.12, y: 0.63, width: 0.38),
            focusCandidate("1 tbsp olive oil", x: 0.12, y: 0.55, width: 0.44),
            focusCandidate("Instructions", x: 0.10, y: 0.42, width: 0.34),
            focusCandidate("Whisk the eggs until smooth and then fold everything together.", x: 0.10, y: 0.34, width: 0.78)
        ]

        let suggestion = OCRFocusRegionSuggester.suggestion(from: candidates)

        XCTAssertGreaterThanOrEqual(suggestion.confidence, 0.70)
        XCTAssertFalse(suggestion.region.isFullImage)
        XCTAssertLessThan(suggestion.region.x, 0.12)
        XCTAssertGreaterThan(suggestion.region.width, 0.44)
        XCTAssertLessThan(suggestion.region.y, 0.07)
        XCTAssertLessThan(suggestion.region.y + suggestion.region.height, 0.50)
    }

    func testOCRFocusSuggestionFallsBackToFullImageWhenUncertain() {
        let suggestion = OCRFocusRegionSuggester.suggestion(
            from: [focusCandidate("A family recipe passed down for generations", x: 0.08, y: 0.75, width: 0.80)]
        )

        XCTAssertEqual(suggestion.region, .fullImage)
        XCTAssertLessThan(suggestion.confidence, 0.70)
    }

    func testFocusedImageUsesTransientAxisAlignedCrop() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 100, height: 200),
            format: format
        ).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }

        let cropped = RecipeImagePreprocessor.focusedImage(
            image,
            region: OCRFocusRegion(x: 0.25, y: 0.25, width: 0.50, height: 0.50)
        )

        let cgImage = try cropped.cgImage.firstUnwrapped()
        XCTAssertEqual(cgImage.width, 50)
        XCTAssertEqual(cgImage.height, 100)
        XCTAssertEqual(image.cgImage?.width, 100, "The original image must remain intact")
        XCTAssertEqual(image.cgImage?.height, 200, "The original image must remain intact")
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
        XCTAssertEqual(result.sourceDocument.reconstructedText, result.text)
        XCTAssertEqual(result.sourceDocument.filteredIngredientLines.count, 5)
        XCTAssertFalse(result.sourceDocument.ignoredSourceLines.isEmpty)
        XCTAssertFalse(result.sourceDocument.observations.isEmpty)
        XCTAssertNotEqual(result.sourceDocument.rawRecognizedText, result.text)
        let rawObservationIDs = Set(result.sourceDocument.observations.map(\.observationID))
        XCTAssertTrue(result.sourceLines.allSatisfy { line in
            line.sourceObservationIDs.allSatisfy(rawObservationIDs.contains)
        })

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

    func testFocusedChocolateChipJPEGScansCropAndRemapsEvidenceToOriginalImage() async throws {
        let imageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/OCR/chocolate_chip_cookie_bars_exact.jpeg")
        let image = try UIImage(contentsOfFile: imageURL.path).firstUnwrapped()
        let focus = OCRFocusRegion(x: 0.08, y: 0.56, width: 0.84, height: 0.27)

        let result = try await RecipeVisionReader.recognizeText(
            in: [image],
            focusRegions: [focus]
        )

        XCTAssertEqual(result.sourceDocument.focusRegions, [focus])
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("unsalted butter"))
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("vanilla extract"))
        XCTAssertFalse(result.text.localizedCaseInsensitiveContains("preheat oven"))
        XCTAssertFalse(result.sourceDocument.observations.isEmpty)

        let visionBottom = 1 - focus.y - focus.height
        let tolerance = 0.025
        XCTAssertTrue(result.sourceDocument.observations.allSatisfy { observation in
            observation.boundingBox.x >= focus.x - tolerance
                && observation.boundingBox.x + observation.boundingBox.width
                    <= focus.x + focus.width + tolerance
                && observation.boundingBox.y >= visionBottom - tolerance
                && observation.boundingBox.y + observation.boundingBox.height
                    <= 1 - focus.y + tolerance
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

        guard case .success(let ean8) = BarcodeNormalizer.normalize("96385074") else {
            return XCTFail("Expected valid EAN-8")
        }
        XCTAssertEqual(ean8.format, .ean8)
        XCTAssertEqual(ean8.canonicalGTIN14, "00000096385074")

        let equivalentTradeItems = [
            "078742002163",
            "0078742002163",
            "00078742002163"
        ]
        let canonicalIdentities = try equivalentTradeItems.map { rawValue in
            switch BarcodeNormalizer.normalize(rawValue) {
            case .success(let barcode):
                return barcode.canonicalGTIN14
            case .failure(let error):
                throw error
            }
        }
        XCTAssertEqual(Set(canonicalIdentities), ["00078742002163"])
    }

    func testBundledBarcodeFixtureUsesCurrentIdentityWithoutRetailClaims() async {
        let resolver = BarcodeResolutionService(
            userEditedCache: InMemoryBarcodeUserEditedCache(),
            fixtures: .smartCart,
            adapters: [ThrowingBarcodeAdapter()]
        )

        let result = await resolver.resolve(BarcodeScan(rawBarcode: "078742002163"))
        guard case .resolved(let resolved) = result else {
            return XCTFail("The bundled demo barcode should resolve before network access")
        }
        XCTAssertEqual(resolved.source, .bundledFixture)
        XCTAssertEqual(resolved.product.name, "Kettle Cooked Original Potato Chips with Sea Salt")
        XCTAssertEqual(resolved.product.brand, "Great Value")
        XCTAssertNil(resolved.product.externalReference)
    }

    func testBarcodeBackendConfigurationUsesRequiredPrecedenceAndBuildRules() throws {
        let bundleInfo: [String: Any] = [
            BarcodeBackendConfiguration.bundleKey: "https://bundle.smartcart.app"
        ]
        let environment = [
            "SMARTCART_BARCODE_BACKEND_URL": "http://localhost:8787"
        ]

        let injected = try BarcodeBackendConfiguration.resolve(
            explicitURL: URL(string: "https://injected.smartcart.app")!,
            environment: environment,
            bundleInfo: bundleInfo,
            buildMode: .release
        ).get()
        XCTAssertEqual(injected.source, .injected)
        XCTAssertEqual(injected.baseURL.host, "injected.smartcart.app")

        let debug = try BarcodeBackendConfiguration.resolve(
            environment: environment,
            bundleInfo: bundleInfo,
            buildMode: .debug
        ).get()
        XCTAssertEqual(debug.source, .debugEnvironment)
        XCTAssertEqual(debug.baseURL.absoluteString, "http://localhost:8787")

        let release = try BarcodeBackendConfiguration.resolve(
            environment: environment,
            bundleInfo: bundleInfo,
            buildMode: .release
        ).get()
        XCTAssertEqual(release.source, .bundle)
        XCTAssertEqual(release.baseURL.absoluteString, "https://bundle.smartcart.app")
    }

    func testBarcodeBuildConfigurationEmbedsVerifiedPublicServiceInDebugAndRelease() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let debugInfoData = try Data(
            contentsOf: repositoryRoot.appendingPathComponent("SmartCart/Info.plist")
        )
        let debugInfo = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: debugInfoData, format: nil)
                as? [String: Any]
        )
        XCTAssertEqual(
            debugInfo[BarcodeBackendConfiguration.bundleKey] as? String,
            "$(SMARTCART_BARCODE_BACKEND_URL)"
        )
        let debugATS = try XCTUnwrap(
            debugInfo["NSAppTransportSecurity"] as? [String: Any]
        )
        XCTAssertEqual(debugATS["NSAllowsLocalNetworking"] as? Bool, true)
        XCTAssertNotNil(debugInfo["NSLocalNetworkUsageDescription"] as? String)

        let releaseInfoData = try Data(
            contentsOf: repositoryRoot.appendingPathComponent("SmartCart/Info-Release.plist")
        )
        let releaseInfo = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: releaseInfoData, format: nil)
                as? [String: Any]
        )
        XCTAssertEqual(
            releaseInfo[BarcodeBackendConfiguration.bundleKey] as? String,
            "$(SMARTCART_BARCODE_BACKEND_URL)"
        )
        XCTAssertNil(releaseInfo["NSAppTransportSecurity"])
        XCTAssertNil(releaseInfo["NSLocalNetworkUsageDescription"])

        let debug = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Config/Debug.xcconfig"),
            encoding: .utf8
        )
        let publicBarcodeEndpoint =
            "SMARTCART_BARCODE_BACKEND_URL = https:/$()/smartcart-barcode-api-omega.vercel.app"
        XCTAssertTrue(debug.contains(publicBarcodeEndpoint))
        XCTAssertFalse(debug.contains("SMARTCART_BARCODE_BACKEND_URL = http:/$()/localhost"))

        let release = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Config/Release.xcconfig"),
            encoding: .utf8
        )
        XCTAssertTrue(release.contains(publicBarcodeEndpoint))
        XCTAssertFalse(release.contains("localhost"))

        let configuredURL = try XCTUnwrap(
            URL(string: "https://smartcart-barcode-api-omega.vercel.app")
        )
        let validatedRelease = try BarcodeBackendConfiguration.resolve(
            explicitURL: configuredURL,
            buildMode: .release
        ).get()
        XCTAssertEqual(validatedRelease.baseURL, configuredURL)
    }

    func testBarcodeBackendConfigurationRejectsUnsafeReleaseEndpoints() {
        let unsafeValues = [
            "http://catalog.smartcart.example.net",
            "https://localhost:8787",
            "https://localhost.",
            "https://127.0.0.1",
            "https://[::1]",
            "https://[0:0:0:0:0:0:0:1]",
            "https://[fd00::1]",
            "https://[::ffff:127.0.0.1]",
            "https://[::ffff:192.168.1.12]",
            "https://192.168.1.12",
            "https://catalog.example.com",
            "https://catalog.example.com.",
            "https://catalog.example.net",
            "https://catalog.test",
            "https://api.example",
            "https://backend",
            "https://not_a_host.com",
            "https://-bad.com",
            "https://bad-.com",
            "https://bad..com",
            "not a url"
        ]

        for value in unsafeValues {
            let result = BarcodeBackendConfiguration.resolve(
                environment: [:],
                bundleInfo: [BarcodeBackendConfiguration.bundleKey: value],
                buildMode: .release
            )
            guard case .failure = result else {
                return XCTFail("Release configuration should reject \(value)")
            }
        }

        let missing = BarcodeBackendConfiguration.resolve(
            environment: [:],
            bundleInfo: [:],
            buildMode: .release
        )
        XCTAssertThrowsError(try missing.get())
        if case .failure(let error) = missing {
            XCTAssertEqual(error, .missing)
        } else {
            XCTFail("Missing Release configuration must remain explicit")
        }

        XCTAssertNoThrow(
            try BarcodeBackendConfiguration.resolve(
                environment: [:],
                bundleInfo: [BarcodeBackendConfiguration.bundleKey: "https://fcatalog.com"],
                buildMode: .release
            ).get()
        )
    }

    @MainActor
    func testUserNamedBarcodeResolvesFromDurablePantryMappingAfterRelaunch() async throws {
        let store = JSONSmartCartStateStore(
            fileURL: temporaryDirectory().appendingPathComponent("barcode-name-state.json")
        )
        let barcode: NormalizedBarcode
        switch BarcodeNormalizer.normalize("96385074") {
        case .success(let normalized): barcode = normalized
        case .failure(let error): return XCTFail("Fixture barcode should be valid: \(error)")
        }
        let submission = PantryBarcodeSubmission(
            scan: BarcodeScan(rawBarcode: barcode.digits, rawSymbology: "ean8"),
            barcode: barcode,
            name: "",
            brand: "Kitchen Test",
            externalProductID: nil,
            requiresUserNaming: true
        )

        let model = AppModel(stateStore: store)
        model.addPantryStock(name: "Rice Crackers", amount: 1, submission: submission)
        let restored = AppModel(stateStore: store)
        let resolver = BarcodeResolutionService(
            userEditedCache: PantryBarcodeUserEditedCache(items: restored.pantryInventory),
            fixtures: BundledBarcodeFixtureCatalog(fixtures: []),
            adapters: [ThrowingBarcodeAdapter()]
        )

        let result = await resolver.resolve(submission.scan)
        guard case .resolved(let resolved) = result else {
            return XCTFail("Saved pantry mapping should resolve before the network adapter")
        }
        XCTAssertEqual(resolved.source, .localUserEditedCache)
        XCTAssertEqual(resolved.product.name, "Rice Crackers")
        XCTAssertEqual(resolved.product.brand, "Kitchen Test")
        XCTAssertEqual(restored.pantryInventory.first?.requiresUserNaming, false)
    }

    func testBarcodeNetworkFailureRemainsUnavailableWithManualNamingState() async {
        let resolver = BarcodeResolutionService(
            userEditedCache: InMemoryBarcodeUserEditedCache(),
            fixtures: BundledBarcodeFixtureCatalog(fixtures: []),
            adapters: [ThrowingBarcodeAdapter()]
        )

        let result = await resolver.resolve(BarcodeScan(rawBarcode: "4006381333931"))

        guard case .unavailable(let unresolved, let failure) = result else {
            return XCTFail("Network failure must remain distinct from a catalog miss")
        }
        XCTAssertEqual(unresolved.reason, .noMatch)
        XCTAssertEqual(unresolved.attemptedAdapterIdentifiers, ["failing-test-adapter"])
        XCTAssertEqual(unresolved.adapterFailures.count, 1)
        XCTAssertEqual(failure, .serverError)
        XCTAssertNotNil(unresolved.normalizedBarcode)
    }

    func testSmartCartBarcodeAdapterMapsOfflineAndMissingReleaseConfiguration() async {
        let offlineResolver = BarcodeResolutionService(
            userEditedCache: InMemoryBarcodeUserEditedCache(),
            fixtures: BundledBarcodeFixtureCatalog(fixtures: []),
            adapters: [makeBarcodeAdapter(protocolClass: BarcodeOfflineURLProtocolStub.self)]
        )
        let offline = await offlineResolver.resolve(BarcodeScan(rawBarcode: "4006381333931"))
        guard case .unavailable(_, let offlineFailure) = offline else {
            return XCTFail("A URLSession connectivity failure must remain unavailable")
        }
        XCTAssertEqual(offlineFailure, .offline)

        let missingConfigurationResolver = BarcodeResolutionService(
            userEditedCache: InMemoryBarcodeUserEditedCache(),
            fixtures: BundledBarcodeFixtureCatalog(fixtures: []),
            adapters: [
                SmartCartBackendBarcodeAdapter(
                    environment: [:],
                    bundleInfo: [:],
                    buildMode: .release
                )
            ]
        )
        let missing = await missingConfigurationResolver.resolve(
            BarcodeScan(rawBarcode: "4006381333931")
        )
        guard case .unavailable(_, let missingFailure) = missing else {
            return XCTFail("Missing Release configuration must remain unavailable")
        }
        XCTAssertEqual(missingFailure, .configurationMissing)
    }

    func testSmartCartBarcodeAdapterDecodesIdentityWithoutRetailClaims() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BarcodeURLProtocolStub.self]
        let adapter = SmartCartBackendBarcodeAdapter(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://barcode.smartcart.app")!,
            buildMode: .release
        )
        let barcode: NormalizedBarcode
        switch BarcodeNormalizer.normalize("5449000000996") {
        case .success(let normalized): barcode = normalized
        case .failure(let error): return XCTFail("Known barcode should be valid: \(error)")
        }

        let product = try await adapter.resolve(barcode)

        XCTAssertEqual(product?.name, "Coca-Cola")
        XCTAssertEqual(product?.brand, "Coca-Cola")
        XCTAssertEqual(product?.packageDisplayText, "33 cl")
        XCTAssertEqual(product?.imageURL, URL(string: "https://images.openfoodfacts.org/coca-cola.jpg"))
        XCTAssertEqual(product?.catalogSource, "open_food_facts")
        XCTAssertEqual(product?.isVerified, false)
        XCTAssertNil(product?.externalReference)
    }

    func testSmartCartBarcodeAdapterDropsUnsafeImageURLWithoutLosingIdentity() async throws {
        let adapter = makeBarcodeAdapter(protocolClass: BarcodeUnsafeImageURLProtocolStub.self)
        let barcode = try BarcodeNormalizer.normalize("5449000000996").get()

        let product = try await adapter.resolve(barcode)

        XCTAssertEqual(product?.name, "Coca-Cola")
        XCTAssertEqual(product?.packageDisplayText, "33 cl")
        XCTAssertNil(product?.imageURL)
    }

    func testSmartCartBarcodeAdapterRejectsMismatchedResponseIdentity() async throws {
        let adapter = makeBarcodeAdapter(protocolClass: BarcodeMismatchedIdentityURLProtocolStub.self)
        let barcode = try BarcodeNormalizer.normalize("5449000000996").get()

        do {
            _ = try await adapter.resolve(barcode)
            XCTFail("A response for a different barcode must not be accepted")
        } catch let error as SmartCartBarcodeAdapterError {
            XCTAssertEqual(error, .failure(.malformedResponse))
        }
    }

    func testBarcodeBackendTrueMissIsNotFound() async {
        for protocolClass in [
            BarcodeNotFoundURLProtocolStub.self,
            BarcodeHTTPNotFoundURLProtocolStub.self
        ] {
            let resolver = BarcodeResolutionService(
                userEditedCache: InMemoryBarcodeUserEditedCache(),
                fixtures: BundledBarcodeFixtureCatalog(fixtures: []),
                adapters: [makeBarcodeAdapter(protocolClass: protocolClass)]
            )

            let result = await resolver.resolve(BarcodeScan(rawBarcode: "4006381333931"))
            guard case .notFound(let unresolved) = result else {
                return XCTFail("An explicit catalog miss should be notFound")
            }
            XCTAssertEqual(unresolved.reason, .noMatch)
            XCTAssertTrue(unresolved.adapterFailures.isEmpty)
        }
    }

    func testBarcodeBackendRouteNotFoundRemainsUnavailable() async {
        let resolver = BarcodeResolutionService(
            userEditedCache: InMemoryBarcodeUserEditedCache(),
            fixtures: BundledBarcodeFixtureCatalog(fixtures: []),
            adapters: [makeBarcodeAdapter(protocolClass: BarcodeRouteNotFoundURLProtocolStub.self)]
        )

        let result = await resolver.resolve(BarcodeScan(rawBarcode: "4006381333931"))
        guard case .unavailable(_, let failure) = result else {
            return XCTFail("A deployment route 404 must not become product-not-found")
        }
        XCTAssertEqual(failure, .serverError)
    }

    func testBarcodeBackendTimeoutRateLimitServerAndMalformedResponsesAreUnavailable() async {
        let cases: [(URLProtocol.Type, BarcodeLookupFailure)] = [
            (BarcodeTimeoutURLProtocolStub.self, .timedOut),
            (BarcodeRateLimitURLProtocolStub.self, .rateLimited),
            (BarcodeInternalServerErrorURLProtocolStub.self, .serverError),
            (BarcodeServerErrorURLProtocolStub.self, .serverError),
            (BarcodeMalformedURLProtocolStub.self, .malformedResponse)
        ]

        for (protocolClass, expectedFailure) in cases {
            let resolver = BarcodeResolutionService(
                userEditedCache: InMemoryBarcodeUserEditedCache(),
                fixtures: BundledBarcodeFixtureCatalog(fixtures: []),
                adapters: [makeBarcodeAdapter(protocolClass: protocolClass)]
            )
            let result = await resolver.resolve(BarcodeScan(rawBarcode: "4006381333931"))
            guard case .unavailable(_, let failure) = result else {
                return XCTFail("\(protocolClass) must not become product-not-found")
            }
            XCTAssertEqual(failure, expectedFailure)
        }
    }

    func testBarcodeScannerWiresCatalogManualNamingAndCameraDebounce() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Pantry/BarcodeScannerView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("PantryBarcodeUserEditedCache(items: appModel.pantryInventory)"))
        XCTAssertTrue(source.contains("adapters: [SmartCartBackendBarcodeAdapter()]"))
        XCTAssertTrue(source.contains("heading: \"Product not found\""))
        XCTAssertTrue(source.contains("title: \"Product lookup unavailable\""))
        XCTAssertTrue(source.contains("Label(\"Retry Lookup\""))
        XCTAssertTrue(source.contains("Text(\"Name Manually\")"))
        XCTAssertTrue(source.contains("resolved.product.catalogSource"))
        XCTAssertTrue(source.contains("resolved.product.isVerified == true"))
        XCTAssertTrue(source.contains("requiresUserNaming: true"))
        XCTAssertTrue(source.contains("try await Task.sleep(for: .milliseconds(300))"))
        XCTAssertTrue(source.contains("text: Binding("))
        XCTAssertTrue(source.contains("resetResolutionForManualCodeChange()"))
        XCTAssertFalse(source.contains(".onChange(of: manualCode)"))
        XCTAssertTrue(source.contains("activeCodes.insert(code).inserted"))
        XCTAssertTrue(source.contains("didRemove removedItems"))
        XCTAssertTrue(source.contains(".barcode(symbologies: [.ean13, .ean8, .code128])"))
        XCTAssertFalse(source.contains(".upce"))
    }

    private func makeBarcodeAdapter(
        protocolClass: URLProtocol.Type
    ) -> SmartCartBackendBarcodeAdapter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return SmartCartBackendBarcodeAdapter(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://barcode.smartcart.app")!,
            buildMode: .release
        )
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
        XCTAssertTrue(decoded.identityClaims.isEmpty)
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
                identityClaims: [.observedBarcode(barcode)],
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
    func testScannedBarcodeClaimsPersistAndConflictingBarcodesStaySeparate() throws {
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
        XCTAssertEqual(restored.pantryInventory.count, 2)
        XCTAssertEqual(
            restored.pantryItem(matching: firstBarcode)?.claimedGTIN14s,
            Set([firstBarcode.canonicalGTIN14])
        )
        XCTAssertEqual(
            restored.pantryItem(matching: alternateBarcode)?.claimedGTIN14s,
            Set([alternateBarcode.canonicalGTIN14])
        )

        restored.addPantryStock(
            name: "A different catalog name",
            amount: 4,
            submission: submission(alternateBarcode)
        )

        let relaunchedAgain = AppModel(stateStore: store)
        XCTAssertEqual(relaunchedAgain.pantryInventory.count, 2)
        let alternateItem = try XCTUnwrap(relaunchedAgain.pantryItem(matching: alternateBarcode))
        XCTAssertEqual(alternateItem.packageCount, 6, accuracy: 0.001)
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
        XCTAssertEqual(model.retailerConfiguration.guideLabel, "Shopping Trip")

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

    func testRetailerTripPrimaryActionStateIsReachableOnlyAfterSuccessfulLoad() {
        XCTAssertFalse(RetailerTripPageLoadState.loading.canRecordVisited)
        XCTAssertEqual(
            RetailerTripPageLoadState.loading.accessibilityDescription,
            "Retailer page loading"
        )
        XCTAssertTrue(RetailerTripPageLoadState.loaded.canRecordVisited)
        XCTAssertEqual(
            RetailerTripPageLoadState.loaded.accessibilityDescription,
            "Retailer page loaded"
        )
        XCTAssertFalse(RetailerTripPageLoadState.failed.canRecordVisited)
        XCTAssertEqual(
            RetailerTripPageLoadState.failed.accessibilityDescription,
            "Retailer page failed to load"
        )
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
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: defaults,
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
        let logicalTripID = model.shoppingSession(id: sessionID)?.reconciliationIdentity
        let item = model.shoppingItems[itemIndex]
        let originalProvenance = item.purchaseGroup?.contributions
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
        XCTAssertEqual(model.shoppingSession(id: sessionID)?.reconciliationIdentity, logicalTripID)
        XCTAssertEqual(model.currentGuidedItem?.purchaseGroup?.contributions, originalProvenance)

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.activeShoppingSessionID, sessionID)
        XCTAssertEqual(restored.currentGuidedItem?.product.id, candidate.id)
        XCTAssertEqual(restored.currentGuidedItem?.status, .waiting)
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
        model.persistNow()

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
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: defaults,
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.startOrResumeRetailerShoppingSession()
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()
        let logicalTripID = model.shoppingSession(id: sessionID)?.reconciliationIdentity
        let item = try model.shoppingItems.first(where: { !$0.alternatives.isEmpty }).firstUnwrapped()
        let replacement = try item.alternatives.firstUnwrapped()
        let savedListID = try model.savedLists.firstUnwrapped().id
        XCTAssertTrue(Set(model.savedLists[0].manifest.items.map(\.id)).isSubset(of: Set(model.shoppingItems.map(\.id))))

        model.selectAlternative(itemID: item.id, candidateID: replacement.id)

        XCTAssertEqual(model.ensureCurrentShoppingSession(), sessionID)
        XCTAssertEqual(model.pendingShoppingSessions.count, 1)
        XCTAssertEqual(
            model.shoppingSessions.filter {
                $0.isReusable && $0.reconciliationIdentity == logicalTripID
            }.count,
            1
        )
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

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.activeShoppingSessionID, sessionID)
        XCTAssertEqual(restored.shoppingSession(id: sessionID)?.reconciliationIdentity, logicalTripID)
        XCTAssertEqual(
            restored.shoppingSession(id: sessionID)?.items.first(where: { $0.id == item.id })?.product.id,
            replacement.id
        )
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
        model.persistNow()

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
        let exactClaims = ExactProductIdentity.all(for: item.product).compactMap { identity in
            switch identity.kind {
            case .retailerProductID:
                return PantryIdentityClaim.exactPurchaseRetailerProductID(
                    "\(identity.retailerID):\(identity.normalizedValue)"
                )
            case .gtin:
                return PantryIdentityClaim.exactPurchaseGTIN(identity.normalizedValue)
            case .exactURL:
                return nil
            }
        }
        model.pantryInventory = [
            PantryInventoryItem(
                name: item.product.name,
                brand: item.product.brand,
                quantity: 2,
                unit: "item",
                preferredRetailerProductID: item.product.retailerProductID,
                identityClaims: exactClaims,
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
        XCTAssertNil(model.pantryInventory.first?.preferredRetailerProductID)
        XCTAssertFalse(model.pantryInventory.first?.requiresUserNaming == true)
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
    func testConflictingRetailerProductIdentityPreventsGTINOnlyPantryMerge() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            seedDemoShoppingState: true
        )
        var item = try model.shoppingItems.firstUnwrapped()
        item.product.gtin = "078742002163"
        item.purchaseGroup = nil
        model.shoppingItems = [item]
        let gtin = try XCTUnwrap(
            ExactProductIdentity.all(for: item.product).first { $0.kind == .gtin }?.normalizedValue
        )
        let existing = PantryInventoryItem(
            name: item.product.name,
            brand: item.product.brand,
            quantity: 1,
            unit: "package",
            identityClaims: [
                .exactPurchaseRetailerProductID("\(item.product.retailerID):conflicting-product"),
                .exactPurchaseGTIN(gtin)
            ],
            source: .recipe,
            packageSize: item.product.packageQuantity,
            packageUnit: item.product.packageUnit
        )
        model.pantryInventory = [existing]
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: []
        )

        XCTAssertEqual(model.pantryInventory.count, 2)
        XCTAssertEqual(
            model.pantryInventory.first(where: { $0.id == existing.id })?.packageCount,
            1
        )
    }

    @MainActor
    func testVariableWeightPurchaseDoesNotBecomeConfirmedPackageMass() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            seedDemoShoppingState: true
        )
        let item = try model.shoppingItems.first(where: { $0.product.variableWeight }).firstUnwrapped()
        let sessionID = try model.ensureCurrentShoppingSession().firstUnwrapped()

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: []
        )

        let pantryItem = try model.pantryInventory.firstUnwrapped()
        XCTAssertNil(pantryItem.packageSize)
        XCTAssertNil(pantryItem.packageUnit)
        XCTAssertTrue(pantryItem.hasUnknownPackageMass == true)
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
        fresh.persistNow()

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

    func testRetailerTripSheetTransitionsStayExplicitAndPauseReturnsHome() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Orders/WalmartWishlistViews.swift"
            ),
            encoding: .utf8
        )

        let advanceStart = try XCTUnwrap(
            source.range(of: "    private func advanceFromProduct(")?.lowerBound
        )
        let replacementStart = try XCTUnwrap(
            source.range(
                of: "    private func replaceCurrentProduct",
                range: advanceStart..<source.endIndex
            )?.lowerBound
        )
        let pauseStart = try XCTUnwrap(
            source.range(
                of: "    private func pauseTripAndReturnHome",
                range: replacementStart..<source.endIndex
            )?.lowerBound
        )
        let prewarmStart = try XCTUnwrap(
            source.range(
                of: "    private func prewarmAfterItem",
                range: pauseStart..<source.endIndex
            )?.lowerBound
        )

        XCTAssertTrue(
            source[advanceStart..<replacementStart].contains("isExplicitTransition: true")
        )
        XCTAssertTrue(
            source[replacementStart..<pauseStart].contains("isExplicitTransition: true")
        )
        XCTAssertTrue(source[pauseStart..<prewarmStart].contains("appModel.homePath = []"))
    }

    func testRetailerTripPlacesMoreBelowPauseAndTargetBelowNext() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let tripSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Orders/WalmartWishlistViews.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(tripSource.contains("private var checkTargetButton: some View"))
        XCTAssertTrue(tripSource.contains("Label(\"Check Target\", systemImage: \"magnifyingglass\")"))
        XCTAssertTrue(tripSource.contains("checkedTargetURL = targetSearchURL"))
        XCTAssertTrue(tripSource.contains("url: displayedURL"))
        XCTAssertTrue(tripSource.contains("retailer-trip-check-target"))
        XCTAssertFalse(tripSource.contains("Button(\"Check Target\", systemImage: \"magnifyingglass\")"))
        XCTAssertTrue(tripSource.contains("VStack(spacing: 6) {\n                        pauseButton\n                        moreMenu"))
        XCTAssertTrue(tripSource.contains("VStack(spacing: 6) {\n                        nextButton\n                        checkTargetButton"))
        XCTAssertFalse(tripSource.contains("retailerOwnershipLabel"))
        XCTAssertFalse(tripSource.contains("Shopping stays with"))
        XCTAssertFalse(tripSource.contains(".frame(minWidth: 72, minHeight: 48)"))

        let moreStart = try XCTUnwrap(tripSource.range(of: "    private var moreMenu")?.lowerBound)
        let displayedURLStart = try XCTUnwrap(
            tripSource.range(of: "    private var displayedURL", range: moreStart..<tripSource.endIndex)?.lowerBound
        )
        let moreMenuSource = tripSource[moreStart..<displayedURLStart]
        XCTAssertTrue(moreMenuSource.contains(".font(.caption.bold())"))
        XCTAssertTrue(moreMenuSource.contains(".frame(width: compactSecondaryActionWidth)"))
        XCTAssertTrue(moreMenuSource.contains(".frame(minHeight: 38)"))
        XCTAssertTrue(moreMenuSource.contains(".frame(minHeight: 44)"))
        XCTAssertTrue(tripSource.contains("dynamicTypeSize.isAccessibilitySize ? nil : 128"))
    }

    func testHomeUsesActionFirstLayoutAndRecipeImportersAutoPresentMediaTools() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Home/HomeView.swift"
            ),
            encoding: .utf8
        )
        let composerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Home/RecipeComposerSheet.swift"
            ),
            encoding: .utf8
        )
        let recipesSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Cart/CartView.swift"
            ),
            encoding: .utf8
        )
        let themeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Theme/SmartCartTheme.swift"
            ),
            encoding: .utf8
        )

        let bodyStart = try XCTUnwrap(homeSource.range(of: "    var body: some View")?.lowerBound)
        let headerStart = try XCTUnwrap(
            homeSource.range(of: "    private var header", range: bodyStart..<homeSource.endIndex)?.lowerBound
        )
        let body = homeSource[bodyStart..<headerStart]
        let headerIndex = try XCTUnwrap(body.range(of: "header")?.lowerBound)
        let startIndex = try XCTUnwrap(body.range(of: "startShoppingSection")?.lowerBound)

        XCTAssertLessThan(headerIndex, startIndex)
        XCTAssertTrue(homeSource.contains("SmartCartFoodBackground()"))
        XCTAssertTrue(homeSource.contains("@Environment(\\.colorScheme) private var colorScheme"))
        XCTAssertTrue(homeSource.contains("colorScheme == .light ? SmartCartTheme.ink : .white"))
        XCTAssertTrue(themeSource.contains("Color.white.opacity(min(0.82, 0.62 + darkness * 0.25))"))
        XCTAssertTrue(homeSource.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(homeSource.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(homeSource.contains("ScrollView {"))
        XCTAssertTrue(homeSource.contains(".scrollIndicators(.hidden)"))
        XCTAssertTrue(homeSource.contains("SmartCartLogo()"))
        XCTAssertTrue(homeSource.contains(".frame(maxWidth: .infinity, alignment: .center)"))
        XCTAssertFalse(homeSource.contains("Image(systemName: \"leaf.fill\")"))
        XCTAssertTrue(homeSource.contains("Text(\"Start a Shopping Trip\")"))
        XCTAssertTrue(homeSource.contains(".multilineTextAlignment(.center)"))
        XCTAssertTrue(homeSource.contains("Text(\"Take Photo\")"))
        XCTAssertTrue(homeSource.contains("Text(\"Choose Photo\")"))
        XCTAssertTrue(homeSource.contains("Text(\"Paste Recipe\")"))
        XCTAssertTrue(homeSource.contains("Text(\"Meal Prep Mode\")"))
        XCTAssertTrue(homeSource.contains("Text(\"Combine up to five saved recipes\")"))
        XCTAssertTrue(homeSource.contains(".frame(maxWidth: .infinity, minHeight: 82)"))
        XCTAssertTrue(homeSource.contains(".frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)"))
        XCTAssertTrue(homeSource.contains(".padding(.bottom, 24)"))
        XCTAssertTrue(homeSource.contains("HomeGlassSurface(radius: 30, darkness: 0.16)"))
        XCTAssertTrue(themeSource.contains("Color.white.opacity(0.10)"))
        XCTAssertTrue(homeSource.contains("accessibilityIdentifier(\"home-import-camera\")"))
        XCTAssertTrue(homeSource.contains("accessibilityIdentifier(\"home-import-photos\")"))
        XCTAssertTrue(homeSource.contains("accessibilityIdentifier(\"home-paste-recipe\")"))
        XCTAssertTrue(homeSource.contains("accessibilityIdentifier(\"home-start-meal-prep\")"))
        XCTAssertTrue(homeSource.contains("accessibilityIdentifier(\"home-import-more\")"))
        XCTAssertTrue(homeSource.contains("appModel.openImporter(.camera)"))
        XCTAssertTrue(homeSource.contains("appModel.openImporter(.photoLibrary)"))
        XCTAssertTrue(homeSource.contains("appModel.startMealPrepDraft()"))
        XCTAssertTrue(homeSource.contains("pasteRecipeFromClipboard"))
        XCTAssertTrue(homeSource.contains("RecipeLinkInput.validHTTPSURL(from:)"))
        XCTAssertTrue(homeSource.contains("appModel.openImporter(.recipeLink, initialText: validatedURL.absoluteString)"))
        XCTAssertTrue(homeSource.contains("appModel.openImporter(.recipeText, initialText: trimmedText)"))
        XCTAssertTrue(homeSource.contains("Label(\"Enter Manually\", systemImage: \"keyboard\")"))
        XCTAssertTrue(homeSource.contains("Label(\"Try a Sample\", systemImage: \"takeoutbag.and.cup.and.straw.fill\")"))

        let panelStart = try XCTUnwrap(homeSource.range(of: "    private var startShoppingPanel")?.lowerBound)
        let mealPrepStart = try XCTUnwrap(
            homeSource.range(of: "    private var mealPrepLaunchButton", range: panelStart..<homeSource.endIndex)?.lowerBound
        )
        let panel = homeSource[panelStart..<mealPrepStart]
        let cameraIndex = try XCTUnwrap(panel.range(of: "Text(\"Take Photo\")")?.lowerBound)
        let photosIndex = try XCTUnwrap(panel.range(of: "Text(\"Choose Photo\")")?.lowerBound)
        let pasteIndex = try XCTUnwrap(panel.range(of: "Text(\"Paste Recipe\")")?.lowerBound)
        let mealPrepIndex = try XCTUnwrap(panel.range(of: "mealPrepLaunchButton")?.lowerBound)
        XCTAssertLessThan(cameraIndex, photosIndex)
        XCTAssertLessThan(photosIndex, pasteIndex)
        XCTAssertLessThan(pasteIndex, mealPrepIndex)

        XCTAssertFalse(homeSource.contains("appModel.pendingShoppingSessions"))
        XCTAssertTrue(homeSource.contains("let hasTripActions = !tripActionPresentations.isEmpty"))
        XCTAssertTrue(homeSource.contains("if hasTripActions {"))
        XCTAssertTrue(homeSource.contains("continueShoppingTripsDrawer("))
        XCTAssertTrue(homeSource.contains("HomePullUpShape"))
        XCTAssertTrue(homeSource.contains("ZStack(alignment: .top)"))
        XCTAssertTrue(homeSource.contains("WoodGrainBackground()"))
        XCTAssertTrue(homeSource.contains("SmartCartDrawerGlassSurface(\n                    shape: HomePullUpShape(),\n                    darkness: 0.28\n                )"))
        XCTAssertFalse(homeSource.contains(".shadow(color: .black.opacity(0.34), radius: 22, y: -8)"))
        XCTAssertTrue(homeSource.contains(".clipShape(HomePullUpShape())"))
        XCTAssertTrue(homeSource.contains("let woodWrapDepth: CGFloat = shoppingTripsExpanded ? 26 : 0"))
        XCTAssertTrue(homeSource.contains("let joinOverlap: CGFloat = shoppingTripsExpanded ? 2 : 0"))
        XCTAssertTrue(homeSource.contains(".clipShape(SmartCartDrawerWoodWrapShape(depth: woodWrapDepth))"))
        XCTAssertTrue(homeSource.contains("collapsedShoppingTripsDrawerHeight - woodWrapDepth - joinOverlap"))
        XCTAssertTrue(homeSource.contains("collapsedShoppingTripsDrawerHeight - joinOverlap"))
        XCTAssertFalse(homeSource.contains("continueShoppingTripsHandle(collapsedOffset: collapsedOffset)\n\n            Divider()"))
        XCTAssertTrue(homeSource.contains(".frame(height: collapsedShoppingTripsDrawerHeight)"))
        XCTAssertFalse(homeSource.contains("HomePullUpGlassSurface"))
        XCTAssertTrue(homeSource.contains("accessibilityIdentifier(\"home-continue-shopping-drawer\")"))
        XCTAssertTrue(homeSource.contains("Label(shoppingTripsTitle, systemImage: \"cart.badge.clock\")"))
        XCTAssertTrue(homeSource.contains("ForEach(tripActionPresentations)"))
        XCTAssertTrue(homeSource.contains("appModel.performHomeTripAction(presentation.action)"))
        XCTAssertFalse(homeSource.contains("hasPendingPantryUpdateReminder"))
        XCTAssertFalse(homeSource.contains("home-finish-last-trip"))
        XCTAssertFalse(homeSource.contains("Finish your last trip"))
        XCTAssertFalse(homeSource.contains("appModel.startShoppingReconciliation()"))
        XCTAssertTrue(homeSource.contains("@State private var pendingDiscardAction: HomeTripActionPresentation?"))
        XCTAssertTrue(homeSource.contains("pendingDiscardAction = presentation"))
        XCTAssertTrue(homeSource.contains("\"Clear this paused order?\""))
        XCTAssertTrue(homeSource.contains("Button(\"Clear Order\", role: .destructive)"))
        XCTAssertTrue(homeSource.contains("appModel.discardPendingShoppingSession(pendingDiscardAction.id)"))
        XCTAssertTrue(homeSource.contains("accessibilityIdentifier(\"home-clear-paused-"))
        XCTAssertTrue(homeSource.contains("dynamicTypeSize.isAccessibilitySize ? 148 : 92"))
        XCTAssertFalse(homeSource.contains("measuredShoppingTripsHandleHeight"))
        XCTAssertFalse(homeSource.contains("home-resume-shopping"))
        XCTAssertFalse(homeSource.contains("home-shopping-trips-strip"))
        XCTAssertFalse(homeSource.contains("No paused trips"))
        XCTAssertFalse(homeSource.contains("Toggle("))
        XCTAssertFalse(homeSource.contains("Paste Ingredients"))
        XCTAssertFalse(homeSource.contains("TextEditor("))
        XCTAssertFalse(homeSource.contains("Text(\"Paste Link\")"))
        XCTAssertFalse(homeSource.contains("Text(\"Paste Copied Link\")"))
        XCTAssertFalse(homeSource.contains("Label(\"Saved Recipes\""))
        XCTAssertFalse(homeSource.contains("selectedTab = .lists"))
        XCTAssertFalse(homeSource.contains("SMARTCART_HOME_TRIPS_DRAWER"))
        XCTAssertFalse(homeSource.contains("PageTabViewStyle"))
        XCTAssertFalse(homeSource.contains("shopAgainCard"))
        XCTAssertFalse(homeSource.contains("home-shop-again"))
        XCTAssertFalse(homeSource.contains("Shop Again"))
        XCTAssertFalse(homeSource.contains("storeCard"))
        XCTAssertFalse(homeSource.contains("trustStrip"))

        let homeBackgroundAsset = repositoryRoot.appendingPathComponent(
            "SmartCart/Assets.xcassets/SmartCartHomeBackground.imageset/smartcart-home-food-background.png"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: homeBackgroundAsset.path))

        XCTAssertTrue(composerSource.contains("@State private var showPhotoLibrary = false"))
        XCTAssertTrue(composerSource.contains("@State private var hasAttemptedInitialMediaPresentation = false"))
        XCTAssertTrue(composerSource.contains(".photosPicker(\n            isPresented: $showPhotoLibrary"))
        XCTAssertTrue(composerSource.contains("await presentInitialMediaToolIfNeeded()"))
        XCTAssertTrue(composerSource.contains("guard initialMethod == .camera || initialMethod == .photoLibrary else { return }"))
        XCTAssertTrue(composerSource.contains("try? await Task.sleep(for: .milliseconds(300))"))
        XCTAssertTrue(composerSource.contains("guard !Task.isCancelled, selectedMethod == initialMethod else { return }"))
        XCTAssertTrue(composerSource.contains("showCamera = true"))
        XCTAssertTrue(composerSource.contains("showPhotoLibrary = true"))
        XCTAssertTrue(composerSource.contains(".frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)"))
        XCTAssertFalse(recipesSource.contains("private var mealPrepLaunchCard"))
    }

    @MainActor
    func testPendingShoppingSessionsAreUniqueAndOnlyActiveIncompleteTripIsPromoted() throws {
        let state = try makeState()
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(state: state),
            commerceDefaults: isolatedCommerceDefaults()
        )
        let waitingItem = try state.shoppingItems.firstUnwrapped()
        var completedItem = waitingItem
        completedItem.status = .visited
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = olderDate.addingTimeInterval(60)

        let olderIncomplete = ShoppingSession(
            tripID: UUID(),
            recipeID: state.activeRecipe.id,
            recipeTitle: "Older active",
            storeID: "walmart-5206",
            startedAt: olderDate,
            items: [waitingItem]
        )
        let newerIncomplete = ShoppingSession(
            tripID: UUID(),
            recipeID: state.activeRecipe.id,
            recipeTitle: "Newer waiting",
            storeID: "walmart-5206",
            startedAt: newerDate,
            items: [waitingItem]
        )
        let duplicateNewer = phase4Alias(of: newerIncomplete)

        model.shoppingSessions = [newerIncomplete, olderIncomplete, duplicateNewer]
        model.activeShoppingSessionID = olderIncomplete.id
        XCTAssertEqual(model.pendingShoppingSessions.first?.id, olderIncomplete.id)
        XCTAssertEqual(model.pendingShoppingSessions.count, 2)
        XCTAssertEqual(
            Set(model.pendingShoppingSessions.map(\.id)).count,
            model.pendingShoppingSessions.count
        )

        let olderCompleted = ShoppingSession(
            id: olderIncomplete.id,
            tripID: olderIncomplete.tripID,
            logicalTripID: olderIncomplete.logicalTripID,
            recipeID: olderIncomplete.recipeID,
            recipeTitle: "Older pantry update",
            storeID: olderIncomplete.storeID,
            startedAt: olderDate,
            items: [completedItem]
        )
        model.shoppingSessions = [olderCompleted, newerIncomplete]
        model.activeShoppingSessionID = olderCompleted.id
        XCTAssertTrue(olderCompleted.isGuideComplete)
        XCTAssertEqual(model.pendingShoppingSessions.first?.id, newerIncomplete.id)
        XCTAssertEqual(
            model.pendingShoppingSessions.first(where: \.isReusable)?.id,
            newerIncomplete.id
        )
        XCTAssertEqual(
            model.pendingShoppingSessions.first(where: \.hasPendingPantryUpdateReminder)?.id,
            olderCompleted.id
        )
        XCTAssertEqual(
            model.homeTripActions,
            [
                .resume(sessionID: newerIncomplete.id),
                .updatePantry(sessionID: olderCompleted.id)
            ]
        )
        XCTAssertEqual(
            model.homeTripActionPresentations.map(\.title),
            [newerIncomplete.recipeTitle, olderCompleted.recipeTitle]
        )
        XCTAssertEqual(
            model.shoppingSessions,
            [olderCompleted, newerIncomplete],
            "Home projection must not rewrite frozen sessions"
        )
    }

    @MainActor
    func testHomeTripActionsPersistResumeAndPantryUpdateAcrossRelaunch() throws {
        let resumeStore = InMemorySmartCartStateStore()
        let resumeDefaults = isolatedCommerceDefaults()
        let started = try startIncompleteShoppingTrip(
            stateStore: resumeStore,
            commerceDefaults: resumeDefaults
        )
        XCTAssertEqual(started.model.homeTripActions, [.resume(sessionID: started.sessionID)])

        let restoredResume = AppModel(
            stateStore: resumeStore,
            commerceDefaults: resumeDefaults
        )
        XCTAssertEqual(restoredResume.homeTripActions, [.resume(sessionID: started.sessionID)])

        let pantryStore = InMemorySmartCartStateStore()
        let pantryDefaults = isolatedCommerceDefaults()
        let completed = try completePhase4Trip(
            stateStore: pantryStore,
            commerceDefaults: pantryDefaults
        )
        XCTAssertEqual(
            completed.model.homeTripActions,
            [.updatePantry(sessionID: completed.sessionID)]
        )

        let restoredPantry = AppModel(
            stateStore: pantryStore,
            commerceDefaults: pantryDefaults
        )
        XCTAssertEqual(
            restoredPantry.homeTripActions,
            [.updatePantry(sessionID: completed.sessionID)]
        )
        XCTAssertTrue(restoredPantry.pantryInventory.isEmpty)
    }

    @MainActor
    func testHomeTripActionsExcludeCommittedArchivedEmptyAndAliasedHistory() throws {
        let state = try makeState()
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(state: state),
            commerceDefaults: isolatedCommerceDefaults()
        )
        let waitingItem = try state.shoppingItems.firstUnwrapped()
        var completedItem = waitingItem
        completedItem.status = .visited
        let logicalTripID = UUID()
        let completed = ShoppingSession(
            tripID: logicalTripID,
            logicalTripID: logicalTripID,
            recipeID: state.activeRecipe.id,
            recipeTitle: "Completed",
            storeID: "walmart-5206",
            items: [completedItem]
        )
        var archived = completed
        archived.pantryUpdateReminderArchivedAt = .now
        var committed = completed
        committed.reconciliation = ShoppingReconciliationRecord(
            outcome: .boughtEverything,
            purchasedItemIDs: [completedItem.id],
            substitutions: [],
            pantryItemIDs: [],
            committedAt: .now,
            logicalTripID: logicalTripID
        )
        let empty = ShoppingSession(
            tripID: UUID(),
            recipeID: state.activeRecipe.id,
            recipeTitle: "Empty",
            storeID: "walmart-5206",
            items: []
        )

        model.shoppingSessions = [archived, committed, empty]

        XCTAssertTrue(model.pendingShoppingSessions.isEmpty)
        XCTAssertTrue(model.homeTripActions.isEmpty)
        XCTAssertTrue(model.homeTripActionPresentations.isEmpty)
    }

    @MainActor
    func testHomeTripActionsKeepRepeatedTripsDistinctAndRejectDanglingOrStaleActions() throws {
        let state = try makeState()
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(state: state),
            commerceDefaults: isolatedCommerceDefaults()
        )
        let waitingItem = try state.shoppingItems.firstUnwrapped()
        let earlier = ShoppingSession(
            tripID: UUID(),
            recipeID: state.activeRecipe.id,
            recipeTitle: "Weekly Dinner",
            storeID: "walmart-5206",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            items: [waitingItem]
        )
        let later = ShoppingSession(
            tripID: UUID(),
            recipeID: state.activeRecipe.id,
            recipeTitle: "Weekly Dinner",
            storeID: "walmart-5206",
            startedAt: Date(timeIntervalSince1970: 1_700_000_060),
            items: [waitingItem]
        )
        model.shoppingSessions = [earlier, later]
        model.activeShoppingSessionID = nil

        XCTAssertEqual(
            model.homeTripActions,
            [.resume(sessionID: later.id), .resume(sessionID: earlier.id)]
        )
        let originalPath = model.homePath
        let originalActiveSessionID = model.activeShoppingSessionID
        XCTAssertFalse(model.performHomeTripAction(.resume(sessionID: UUID())))
        XCTAssertFalse(model.performHomeTripAction(.updatePantry(sessionID: later.id)))
        XCTAssertEqual(model.homePath, originalPath)
        XCTAssertEqual(model.activeShoppingSessionID, originalActiveSessionID)
    }

    @MainActor
    func testHomeTripActionsRouteResumeAndUpdatePantryLocally() throws {
        let resumeStore = InMemorySmartCartStateStore()
        let resumeDefaults = isolatedCommerceDefaults()
        let started = try startIncompleteShoppingTrip(
            stateStore: resumeStore,
            commerceDefaults: resumeDefaults
        )
        started.model.homePath = []
        XCTAssertTrue(started.model.performHomeTripAction(.resume(sessionID: started.sessionID)))
        XCTAssertEqual(started.model.activeShoppingSessionID, started.sessionID)
        XCTAssertEqual(started.model.homePath, [.shoppingTrip])

        let pantryStore = InMemorySmartCartStateStore()
        let pantryDefaults = isolatedCommerceDefaults()
        let completed = try completePhase4Trip(
            stateStore: pantryStore,
            commerceDefaults: pantryDefaults
        )
        completed.model.homePath = []
        XCTAssertTrue(
            completed.model.performHomeTripAction(.updatePantry(sessionID: completed.sessionID))
        )
        XCTAssertEqual(completed.model.activeShoppingSessionID, completed.sessionID)
        XCTAssertEqual(
            completed.model.homePath,
            [.shoppingReconciliation(completed.sessionID)]
        )
    }

    @MainActor
    func testDiscardPendingShoppingSessionRemovesActiveTripAndPersistsAcrossRelaunch() throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let started = try startIncompleteShoppingTrip(
            stateStore: store,
            commerceDefaults: defaults
        )
        let model = started.model

        XCTAssertNotNil(model.shoppingSession(id: started.sessionID))
        XCTAssertTrue(model.savedLists.contains { $0.manifest.id == started.manifestID })
        XCTAssertEqual(model.activeShoppingSessionID, started.sessionID)
        XCTAssertFalse(model.shoppingItems.isEmpty)

        XCTAssertTrue(model.discardPendingShoppingSession(started.sessionID))

        XCTAssertNil(model.shoppingSession(id: started.sessionID))
        XCTAssertFalse(model.savedLists.contains { $0.manifest.id == started.manifestID })
        XCTAssertNil(model.activeShoppingSessionID)
        XCTAssertTrue(model.shoppingItems.isEmpty)
        XCTAssertEqual(model.guidedIndex, 0)

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertNil(restored.shoppingSession(id: started.sessionID))
        XCTAssertFalse(restored.savedLists.contains { $0.manifest.id == started.manifestID })
        XCTAssertNil(restored.activeShoppingSessionID)
        XCTAssertTrue(restored.shoppingItems.isEmpty)
        XCTAssertEqual(restored.guidedIndex, 0)
    }

    @MainActor
    func testDiscardPendingShoppingSessionSaveFailureRollsBackEveryMutatedSurface() throws {
        let store = ControllableSmartCartStateStore()
        let started = try startIncompleteShoppingTrip(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults()
        )
        let model = started.model
        let sessionsBefore = model.shoppingSessions
        let listsBefore = model.savedLists
        let activeSessionBefore = model.activeShoppingSessionID
        let itemsBefore = model.shoppingItems
        let guidedIndexBefore = model.guidedIndex
        let persistedBefore = store.state
        store.failNextSave = true

        XCTAssertFalse(model.discardPendingShoppingSession(started.sessionID))

        XCTAssertEqual(model.shoppingSessions, sessionsBefore)
        XCTAssertEqual(model.savedLists, listsBefore)
        XCTAssertEqual(model.activeShoppingSessionID, activeSessionBefore)
        XCTAssertEqual(model.shoppingItems, itemsBefore)
        XCTAssertEqual(model.guidedIndex, guidedIndexBefore)
        XCTAssertEqual(store.state, persistedBefore)
        XCTAssertNotNil(model.persistenceIssue)
    }

    @MainActor
    func testDiscardPendingShoppingSessionRejectsGuideCompleteHistory() throws {
        let store = InMemorySmartCartStateStore()
        let completed = try completePhase4Trip(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults()
        )
        let sessionsBefore = completed.model.shoppingSessions
        let listsBefore = completed.model.savedLists
        let activeSessionBefore = completed.model.activeShoppingSessionID
        let itemsBefore = completed.model.shoppingItems
        let persistedBefore = store.state

        XCTAssertTrue(
            completed.model.shoppingSession(id: completed.sessionID)?.isGuideComplete == true
        )
        XCTAssertFalse(completed.model.discardPendingShoppingSession(completed.sessionID))

        XCTAssertEqual(completed.model.shoppingSessions, sessionsBefore)
        XCTAssertEqual(completed.model.savedLists, listsBefore)
        XCTAssertEqual(completed.model.activeShoppingSessionID, activeSessionBefore)
        XCTAssertEqual(completed.model.shoppingItems, itemsBefore)
        XCTAssertEqual(store.state, persistedBefore)
        XCTAssertTrue(
            completed.model.shoppingSession(id: completed.sessionID)?.hasPendingPantryUpdateReminder == true
        )
    }

    @MainActor
    func testDiscardPendingShoppingSessionRejectsMixedCompletedAliasCluster() throws {
        let store = InMemorySmartCartStateStore()
        let started = try startIncompleteShoppingTrip(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults()
        )
        let model = started.model
        let unfinished = try XCTUnwrap(model.shoppingSession(id: started.sessionID))
        var completedAlias = phase4Alias(of: unfinished)
        completedAlias.items = completedAlias.items.map { item in
            var completed = item
            completed.status = .visited
            return completed
        }
        XCTAssertTrue(completedAlias.isGuideComplete)

        model.shoppingSessions = [unfinished, completedAlias]
        model.activeShoppingSessionID = unfinished.id
        let sessionsBefore = model.shoppingSessions
        let listsBefore = model.savedLists
        let persistedBefore = store.state

        XCTAssertFalse(model.discardPendingShoppingSession(unfinished.id))

        XCTAssertEqual(model.shoppingSessions, sessionsBefore)
        XCTAssertEqual(model.savedLists, listsBefore)
        XCTAssertEqual(model.activeShoppingSessionID, unfinished.id)
        XCTAssertEqual(store.state, persistedBefore)
        XCTAssertTrue(model.savedLists.contains { $0.manifest.id == started.manifestID })
        XCTAssertTrue(model.shoppingSession(id: completedAlias.id)?.isGuideComplete == true)
    }

    func testRecipesTabUsesSavedLibraryAndRecentRecipeDrawer() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let recipesSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Cart/CartView.swift"
            ),
            encoding: .utf8
        )
        let rootSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("SmartCart/RootView.swift"),
            encoding: .utf8
        )
        let themeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Theme/SmartCartTheme.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(recipesSource.contains("TextField(\"Search saved recipes\""))
        XCTAssertTrue(recipesSource.contains("Label(\"Recent Recipes\", systemImage: \"clock.fill\")"))
        XCTAssertTrue(recipesSource.contains("accessibilityIdentifier(\"recipes-recent-drawer\")"))
        XCTAssertTrue(recipesSource.contains("recentDragGesture"))
        XCTAssertTrue(recipesSource.contains("WoodGrainBackground()"))
        XCTAssertTrue(recipesSource.contains("SmartCartDrawerGlassSurface(\n                    shape: RecipesPullUpShape(),\n                    darkness: 0.28\n                )"))
        XCTAssertFalse(recipesSource.contains(".shadow(color: .black.opacity(0.28), radius: 22, y: -8)"))
        XCTAssertTrue(recipesSource.contains(".clipShape(RecipesPullUpShape())"))
        XCTAssertTrue(recipesSource.contains("let woodWrapDepth: CGFloat = recentDrawerExpanded ? 26 : 0"))
        XCTAssertTrue(recipesSource.contains("let joinOverlap: CGFloat = recentDrawerExpanded ? 2 : 0"))
        XCTAssertTrue(recipesSource.contains(".clipShape(SmartCartDrawerWoodWrapShape(depth: woodWrapDepth))"))
        XCTAssertTrue(recipesSource.contains("collapsedDrawerHeight - woodWrapDepth - joinOverlap"))
        XCTAssertTrue(recipesSource.contains(".frame(height: collapsedDrawerHeight - joinOverlap)"))
        XCTAssertFalse(recipesSource.contains("recentDrawerHandle(collapsedOffset: collapsedOffset)\n\n            Divider()"))
        XCTAssertTrue(recipesSource.contains(".frame(height: collapsedDrawerHeight)"))
        XCTAssertTrue(rootSource.contains("SmartCartFoodBackground()"))
        XCTAssertFalse(rootSource.contains("WoodGrainBackground()"))
        XCTAssertTrue(themeSource.contains("struct SmartCartFoodBackground: View"))
        XCTAssertTrue(themeSource.contains("struct SmartCartSmokedGlassSurface: View"))
        XCTAssertTrue(themeSource.contains("struct SmartCartDrawerGlassSurface<SurfaceShape: Shape>: View"))
        XCTAssertTrue(themeSource.contains("struct SmartCartDrawerWoodWrapShape: Shape"))
        XCTAssertTrue(themeSource.contains("Image(\"SmartCartHomeBackground\")"))
        XCTAssertTrue(themeSource.contains("func smartCartBackground() -> some View"))
        XCTAssertTrue(themeSource.contains("SmartCartFoodBackground()"))
        XCTAssertFalse(recipesSource.contains("enum RecipesPage"))
        XCTAssertFalse(recipesSource.contains("Text(\"Recently opened\")"))
        XCTAssertFalse(recipesSource.contains("private var mealPrepLaunchCard"))
        XCTAssertFalse(recipesSource.contains("private var currentListCard"))
    }

    func testPullUpDrawersUseOneExplicitSettleAnimation() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Home/HomeView.swift"
            ),
            encoding: .utf8
        )
        let recipesSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Cart/CartView.swift"
            ),
            encoding: .utf8
        )
        let pantrySource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Cart/PickupSchedulerSheet.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(homeSource.contains("@State private var shoppingTripsDrag: CGFloat = 0"))
        XCTAssertTrue(homeSource.contains("settleShoppingTripsDrawer(expanded:"))
        XCTAssertTrue(homeSource.contains("height: drawerHeight - shoppingTripsDrawerOffset("))
        XCTAssertTrue(homeSource.contains(".frame(height: collapsedShoppingTripsDrawerHeight)"))
        XCTAssertFalse(homeSource.contains("@GestureState private var shoppingTripsDrag"))

        XCTAssertTrue(recipesSource.contains("@State private var recentDrawerDrag: CGFloat = 0"))
        XCTAssertTrue(recipesSource.contains("settleRecentDrawer(expanded:"))
        XCTAssertTrue(recipesSource.contains("height: drawerHeight - recentDrawerOffset("))
        XCTAssertTrue(recipesSource.contains(".overlay(alignment: .top)"))
        XCTAssertFalse(recipesSource.contains("@GestureState private var recentDrawerDrag"))
        XCTAssertFalse(recipesSource.contains(".simultaneousGesture(recentDragGesture"))

        XCTAssertTrue(pantrySource.contains("@State private var scannerDrag: CGFloat = 0"))
        XCTAssertTrue(pantrySource.contains("settleScannerDrawer(expanded:"))
        XCTAssertTrue(pantrySource.contains("height: drawerHeight - scannerDrawerOffset("))
        XCTAssertTrue(pantrySource.contains(".overlay(alignment: .top)"))
        XCTAssertTrue(pantrySource.contains("let joinOverlap: CGFloat = scannerExpanded ? 2 : 0"))
        XCTAssertTrue(pantrySource.contains("SmartCartDrawerGlassSurface(\n                    shape: PantryPullUpShape(),\n                    darkness: 0.28\n                )"))
        XCTAssertTrue(pantrySource.contains(".padding(.top, collapsedDrawerHeight - joinOverlap)"))
        XCTAssertFalse(pantrySource.contains("scannerDrawerHandle(collapsedOffset: collapsedOffset)\n\n            Divider()"))
        XCTAssertFalse(pantrySource.contains(".shadow(color: .black.opacity(0.28), radius: 22, y: -8)"))
        XCTAssertFalse(pantrySource.contains("@GestureState private var scannerDrag"))

        for source in [homeSource, recipesSource, pantrySource] {
            XCTAssertTrue(source.contains("DragGesture(minimumDistance: 6, coordinateSpace: .global)"))
            XCTAssertTrue(source.contains("transaction.animation = nil"))
            XCTAssertTrue(source.contains("withAnimation(reduceMotion ? nil"))
        }
    }

    func testPremiumMotionUsesNativeWorkspaceTransitionsAndReduceMotionFallbacks() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let themeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Theme/SmartCartTheme.swift"
            ),
            encoding: .utf8
        )
        let rootSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("SmartCart/RootView.swift"),
            encoding: .utf8
        )
        let homeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Home/HomeView.swift"
            ),
            encoding: .utf8
        )
        let composerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Home/RecipeComposerSheet.swift"
            ),
            encoding: .utf8
        )
        let cartSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Cart/CartView.swift"
            ),
            encoding: .utf8
        )
        let reconciliationSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Orders/ShoppingReconciliationView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(themeSource.contains("enum SmartCartMotion"))
        XCTAssertTrue(themeSource.contains("static let quick = Animation.easeOut(duration: 0.12)"))
        XCTAssertTrue(themeSource.contains("static let standard = Animation.spring(response: 0.30"))
        XCTAssertTrue(themeSource.contains("static let signature = Animation.spring(response: 0.52"))
        XCTAssertTrue(themeSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(themeSource.contains("content.navigationTransition(.zoom"))
        XCTAssertTrue(themeSource.contains("content.matchedTransitionSource"))
        XCTAssertTrue(rootSource.contains("@Namespace private var workspaceTransition"))
        XCTAssertTrue(rootSource.contains("SmartCartTransitionID.recipeWorkspace"))
        XCTAssertTrue(rootSource.contains("SmartCartTransitionID.shoppingWorkspace"))
        XCTAssertTrue(homeSource.contains("SmartCartMotion.signature"))
        XCTAssertTrue(composerSource.contains("RecipeScanningLine(isActive: isProcessing)"))
        XCTAssertTrue(composerSource.contains("repeatForever(autoreverses: true)"))
        XCTAssertTrue(composerSource.contains("Double(index) * 0.045"))
        XCTAssertTrue(cartSource.contains("ShoppingLaunchOverlay("))
        XCTAssertTrue(cartSource.contains("Launching Shopping Trip"))
        XCTAssertTrue(cartSource.contains("accessibilityIdentifier(\"shopping-launch-transition\")"))
        XCTAssertTrue(reconciliationSource.contains(".sensoryFeedback(.success"))
        XCTAssertTrue(reconciliationSource.contains(".symbolEffect(.bounce"))
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
        let continued = model.continueToShoppingTrip()
        XCTAssertTrue(continued, model.toastMessage ?? "No continuation failure message")
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
        XCTAssertTrue(model.unresolvedMatchingExceptionItems.contains(where: { $0.id == lowConfidence.id }))
        XCTAssertFalse(model.continueToShoppingTrip())

        XCTAssertTrue(model.acceptMatchingException(itemID: lowConfidence.id))
        let unresolvedPackageItems = model.unresolvedMatchingExceptionItems
        XCTAssertTrue(unresolvedPackageItems.allSatisfy { $0.purchaseQuantity == 0 })
        if !unresolvedPackageItems.isEmpty {
            XCTAssertTrue(
                model.applyMatchingExceptionDecisions(
                    Dictionary(uniqueKeysWithValues: unresolvedPackageItems.map { ($0.id, true) }),
                    confirmingUnresolvedPackageCount: 1
                )
            )
        }
        XCTAssertTrue(model.unresolvedMatchingExceptionItems.isEmpty)
        for itemID in [fallback.id, lowConfidence.id] {
            let reviewed = try model.shoppingItems
                .first(where: { $0.id == itemID })
                .firstUnwrapped()
            XCTAssertEqual(reviewed.reviewedMatchingFingerprint, reviewed.matchingInputFingerprint)
        }
        XCTAssertEqual(model.shoppingItems.map(\.purchaseQuantity), [1, 1])
        XCTAssertFalse(model.hasUnresolvedMatchingWork)
        XCTAssertEqual(model.ingredientResolutions.count, 2)
        XCTAssertEqual(
            Set(model.shoppingItems.flatMap {
                $0.purchaseGroup?.contributions.map(\.sourceIngredientID) ?? [$0.ingredient.id]
            }),
            Set(model.ingredientResolutions.map(\.id))
        )
        XCTAssertTrue(model.editableResolutionActionsAreComplete)
        let continued = model.continueToShoppingTrip()
        XCTAssertTrue(continued, model.toastMessage ?? "No continuation failure message")
        XCTAssertEqual(model.homePath.last, .shoppingTrip)
    }

    @MainActor
    func testMatchingExceptionDecisionsApplyOrderDefaultsAndSkipsTogether() async throws {
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

        let exceptions = model.unresolvedMatchingExceptionItems
        let skippedID = try exceptions.firstUnwrapped().id
        let decisions = Dictionary(
            uniqueKeysWithValues: exceptions.map { ($0.id, $0.id != skippedID) }
        )

        XCTAssertTrue(model.applyMatchingExceptionDecisions(decisions))
        XCTAssertTrue(model.unresolvedMatchingExceptionItems.isEmpty)
        XCTAssertEqual(model.shoppingItems.first(where: { $0.id == skippedID })?.status, .skipped)
        XCTAssertTrue(model.shoppingItems.filter { $0.id != skippedID }.allSatisfy { $0.status == .waiting })
        XCTAssertTrue(model.continueToShoppingTrip())
        XCTAssertEqual(model.homePath.last, .shoppingTrip)
        XCTAssertEqual(model.homePath.filter { $0 == .shoppingTrip }.count, 1)
        XCTAssertTrue(model.continueToShoppingTrip())
        XCTAssertEqual(model.homePath.filter { $0 == .shoppingTrip }.count, 1)
    }

    @MainActor
    func testMatchingExceptionConfirmationResolvesUnknownPackageCountAndContinuesOnce() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        let recipe = Recipe(
            title: "Meal Prep Search Fallback",
            source: .text,
            sourceDetail: "Test",
            heroSymbol: "fork.knife",
            servings: 1,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: [Ingredient(name: "Baking powder", quantity: 0.25, unit: "tsp")]
        )
        model.mealPrepDraft = MealPrepDraft(selections: [
            MealPrepSelection(recipe: recipe, targetServings: 1)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())

        await model.startMatching()

        let exception = try model.unresolvedMatchingExceptionItems.firstUnwrapped()
        XCTAssertEqual(exception.purchaseQuantity, 0)

        // A previously accepted product match must not bypass package-count
        // confirmation when restored with an unresolved zero quantity.
        XCTAssertTrue(model.acceptMatchingException(itemID: exception.id))
        let reviewed = try model.shoppingItems.firstUnwrapped()
        XCTAssertEqual(reviewed.reviewedMatchingFingerprint, reviewed.matchingInputFingerprint)
        XCTAssertEqual(model.unresolvedMatchingExceptionItems.map(\.id), [exception.id])
        XCTAssertFalse(model.continueToShoppingTrip())
        XCTAssertEqual(model.toastMessage, "Review or skip every matching exception before continuing")

        XCTAssertTrue(
            model.applyMatchingExceptionDecisions(
                [exception.id: true],
                confirmingUnresolvedPackageCount: 1
            )
        )
        XCTAssertEqual(model.shoppingItems.first?.purchaseQuantity, 1)
        XCTAssertFalse(model.hasUnresolvedMatchingWork)
        XCTAssertTrue(model.continueToShoppingTrip())
        XCTAssertEqual(model.homePath.filter { $0 == .shoppingTrip }.count, 1)
    }

    @MainActor
    func testMatchingExceptionsRemainBlockedUntilFinalDecisionThenContinueOnce() async throws {
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
        let initialPublished = await model.startMatching()
        XCTAssertTrue(initialPublished)
        let exceptions = model.unresolvedMatchingExceptionItems
        XCTAssertGreaterThanOrEqual(exceptions.count, 2)

        XCTAssertTrue(model.acceptMatchingException(itemID: exceptions[0].id))
        XCTAssertFalse(model.continueToShoppingTrip())
        XCTAssertEqual(model.homePath.last, .recipeReady)

        for exception in exceptions.dropFirst() {
            XCTAssertTrue(model.acceptMatchingException(itemID: exception.id))
        }
        for item in model.shoppingItems where item.status == .waiting && item.purchaseQuantity == 0 {
            model.updatePurchaseQuantity(for: item.id, delta: 1)
        }
        XCTAssertTrue(model.continueToShoppingTrip())
        XCTAssertEqual(model.homePath.filter { $0 == .shoppingTrip }.count, 1)
    }

    @MainActor
    func testMatchingExceptionDecisionBatchRollsBackWhenPersistenceFails() async throws {
        let store = ControllableSmartCartStateStore()
        let model = AppModel(
            stateStore: store,
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

        let originalItems = model.shoppingItems
        let exceptions = model.unresolvedMatchingExceptionItems
        let decisions = Dictionary(uniqueKeysWithValues: exceptions.map { ($0.id, true) })
        store.failNextSave = true

        XCTAssertFalse(model.applyMatchingExceptionDecisions(decisions))
        XCTAssertEqual(model.shoppingItems, originalItems)
        XCTAssertEqual(model.unresolvedMatchingExceptionItems.map(\.id), exceptions.map(\.id))
        XCTAssertNotNil(model.persistenceIssue)
    }

    func testProductExceptionReviewUsesDefaultOrderTogglesAndOneContinueAction() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let ordersSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Orders/OrdersView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(ordersSource.contains("shouldOrderByItemID[$0.id] ?? true"))
        XCTAssertTrue(ordersSource.contains("product-exception-order-toggle-"))
        XCTAssertTrue(ordersSource.contains("product-exception-continue"))
        XCTAssertFalse(ordersSource.contains("product-exception-search-"))
        XCTAssertFalse(ordersSource.contains("Search at "))
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
        let savedProductPreferences = model.preferredProductIDsByIngredient
        let originalSourceRecipeIDs = selected.purchaseGroup?.contributions.map(\.sourceRecipeID)
        let originalIngredientIDs = selected.purchaseGroup?.contributions.map(\.sourceIngredientID)
        let originalSourceContributions = selected.purchaseGroup?.contributions.map(\.sourceContributions)
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
        XCTAssertEqual(updated.purchaseGroup?.packagePlan?.requiredQuantity?.dimension, .mass)
        XCTAssertEqual(updated.purchaseGroup?.contributions.map(\.sourceRecipeID), originalSourceRecipeIDs)
        XCTAssertEqual(updated.purchaseGroup?.contributions.map(\.sourceIngredientID), originalIngredientIDs)
        XCTAssertEqual(updated.purchaseGroup?.contributions.map(\.sourceContributions), originalSourceContributions)

        editedRecipe = model.activeRecipe
        editedRecipe.ingredients[0].quantity = 4
        model.activeRecipe = editedRecipe
        let reducedPublished = await model.startMatching()
        XCTAssertTrue(reducedPublished)
        let reduced = try model.shoppingItems.firstUnwrapped()
        XCTAssertEqual(reduced.product.id, selected.product.id)
        XCTAssertLessThanOrEqual(reduced.purchaseQuantity, updated.purchaseQuantity)

        editedRecipe = model.activeRecipe
        editedRecipe.ingredients[0].quantity = 453.59237
        editedRecipe.ingredients[0].unit = "g"
        model.activeRecipe = editedRecipe
        model.preferredProductIDsByIngredient = savedProductPreferences
        let metricPublished = await model.startMatching()
        XCTAssertTrue(metricPublished)
        let metric = try model.shoppingItems.firstUnwrapped()
        XCTAssertEqual(metric.product.id, selected.product.id)
        XCTAssertEqual(metric.purchaseGroup?.packagePlan?.requiredQuantity?.dimension, .mass)
        XCTAssertEqual(metric.purchaseGroup?.contributions.map(\.sourceIngredientID), [pasta.id])
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
    func testRemoveIngredientByStableIDHandlesEveryArrayPositionAndRepeatedRequests() {
        for targetIndex in 0..<3 {
            let ingredients = [
                Ingredient(name: "First", quantity: 1, unit: "cup"),
                Ingredient(name: "Middle", quantity: 2, unit: "tbsp"),
                Ingredient(name: "Last", quantity: 3, unit: "tsp")
            ]
            let model = AppModel(stateStore: InMemorySmartCartStateStore())
            XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: ingredients)))
            let removedID = ingredients[targetIndex].id

            XCTAssertTrue(model.removeIngredient(id: removedID))
            XCTAssertEqual(
                model.activeRecipe.ingredients.map(\.id),
                ingredients.map(\.id).filter { $0 != removedID }
            )
            XCTAssertFalse(model.removeIngredient(id: removedID))
        }

        let onlyIngredient = Ingredient(name: "Only ingredient")
        let onlyModel = AppModel(stateStore: InMemorySmartCartStateStore())
        XCTAssertTrue(onlyModel.beginRecipe(phase2Recipe(ingredients: [onlyIngredient])))
        XCTAssertTrue(onlyModel.removeIngredient(id: onlyIngredient.id))
        XCTAssertTrue(onlyModel.activeRecipe.ingredients.isEmpty)
        XCTAssertFalse(onlyModel.recipeReadyCanStartShopping)
        XCTAssertEqual(
            onlyModel.recipeReadyDisabledExplanation,
            "Include at least one ingredient that still needs to be purchased."
        )
    }

    func testRecipeReadyDeletionUsesParentOwnedStableIDConfirmation() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "SmartCart/Features/Cart/CartView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ForEach(appModel.activeRecipe.ingredients) { ingredient in"))
        XCTAssertFalse(source.contains("ForEach(appModel.activeRecipe.ingredients) { $ingredient in"))
        XCTAssertTrue(source.contains("pendingIngredientDeletion = PendingIngredientDeletion"))
        XCTAssertTrue(source.contains("appModel.removeIngredient(id: deletion.id)"))
        XCTAssertTrue(source.contains("Remove “\\($0.name)” from this recipe?"))
        XCTAssertTrue(source.contains("Button(\"Remove\", role: .destructive"))
    }

    @MainActor
    func testIngredientRemovalPersistsAndSynchronizesRetainedRecipeWithoutMutatingPantry() throws {
        let store = InMemorySmartCartStateStore()
        let removed = Ingredient(name: "Flaky Sea Salt", quantity: 1, unit: "tsp")
        let survivor = Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
        let model = AppModel(stateStore: store)
        model.pantryInventory = [
            PantryInventoryItem(
                name: "Sea Salt",
                quantity: 1,
                unit: "jar",
                packageCount: 1,
                packageSize: 12,
                packageUnit: "oz",
                remainingAmount: 8,
                remainingUnit: "oz"
            )
        ]
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [removed, survivor])))

        var draft = model.activeRecipe
        draft.ingredients[0].pantrySuggestion = PantrySuggestion(
            pantryItemID: try XCTUnwrap(model.pantryInventory.first?.id),
            pantryItemName: "Sea Salt",
            coverage: .partial,
            availableQuantity: 1,
            availableUnit: "tsp",
            requiredQuantity: 2,
            requiredUnit: "tsp",
            matchScore: 0.95
        )
        draft.ingredients[0].pantryDecision = .review
        draft.ingredients[1].pantryDecision = .buyFull
        model.activeRecipe = draft
        let pantrySnapshot = model.pantryInventory

        XCTAssertTrue(model.removeIngredient(id: removed.id))
        XCTAssertEqual(model.activeRecipe.ingredients.map(\.id), [survivor.id])
        XCTAssertEqual(model.activeRecipe.ingredients.first?.pantryDecision, .buyFull)
        XCTAssertEqual(model.pantryInventory, pantrySnapshot)
        XCTAssertEqual(
            model.recipes.first(where: { $0.id == model.activeRecipe.id }),
            model.activeRecipe
        )

        let restored = AppModel(stateStore: store)
        XCTAssertEqual(restored.activeRecipe.ingredients.map(\.id), [survivor.id])
        XCTAssertEqual(
            restored.recipes.first(where: { $0.id == restored.activeRecipe.id }),
            restored.activeRecipe
        )
        XCTAssertEqual(restored.pantryInventory, pantrySnapshot)
    }

    @MainActor
    func testSharedPantryAllocationLetsOnlyOneDuplicateClaimFiniteInventory() {
        let first = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let second = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let model = pantryAllocationModel(
            ingredients: [first, second],
            remainingAmount: 1
        )

        model.useSafePantrySuggestions()

        XCTAssertEqual(model.activeRecipe.ingredients[0].pantryDecision, .useAvailable)
        XCTAssertEqual(model.activeRecipe.ingredients[1].pantryDecision, .review)
        XCTAssertEqual(
            model.activeRecipe.ingredients
                .filter { $0.pantryDecision == .useAvailable }
                .compactMap(\.pantrySuggestion)
                .reduce(0) { $0 + $1.availableQuantity },
            1,
            accuracy: 0.000_001
        )
    }

    @MainActor
    func testDeletingAllocatedDuplicateReallocatesPantryAndRefreshesPurchaseQuantity() async throws {
        let first = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let second = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let model = pantryAllocationModel(
            ingredients: [first, second],
            remainingAmount: 1
        )
        model.useSafePantrySuggestions()
        await model.startMatching()
        XCTAssertEqual(model.shoppingItems.map(\.ingredient.id), [second.id])

        XCTAssertTrue(model.removeIngredient(id: first.id))

        let survivor = try XCTUnwrap(model.activeRecipe.ingredients.first)
        XCTAssertEqual(survivor.id, second.id)
        XCTAssertEqual(survivor.pantryDecision, .useAvailable)
        XCTAssertEqual(model.quantityToBuy(for: survivor), 0, accuracy: 0.000_001)
        XCTAssertTrue(model.shoppingItems.isEmpty)
    }

    @MainActor
    func testDeletingUnallocatedDuplicateDoesNotDisturbValidAllocation() {
        let first = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let second = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let model = pantryAllocationModel(
            ingredients: [first, second],
            remainingAmount: 1
        )
        model.useSafePantrySuggestions()
        let firstSuggestion = model.activeRecipe.ingredients[0].pantrySuggestion

        XCTAssertTrue(model.removeIngredient(id: second.id))

        XCTAssertEqual(model.activeRecipe.ingredients.first?.id, first.id)
        XCTAssertEqual(model.activeRecipe.ingredients.first?.pantryDecision, .useAvailable)
        XCTAssertEqual(model.activeRecipe.ingredients.first?.pantrySuggestion, firstSuggestion)
    }

    @MainActor
    func testThreeDuplicateRowsWithPartialInventoryNeverOverallocate() {
        let ingredients = (0..<3).map { _ in
            Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        }
        let model = pantryAllocationModel(
            ingredients: ingredients,
            remainingAmount: 1.5
        )

        model.useSafePantrySuggestions()

        XCTAssertEqual(
            model.activeRecipe.ingredients.map(\.pantryDecision),
            [.useAvailable, .useAvailable, .review]
        )
        let allocated = model.activeRecipe.ingredients
            .filter { $0.pantryDecision == .useAvailable }
            .compactMap(\.pantrySuggestion)
            .reduce(0) { $0 + min($1.requiredQuantity, $1.availableQuantity) }
        XCTAssertEqual(allocated, 1.5, accuracy: 0.000_001)
    }

    @MainActor
    func testExplicitBuyFullSurvivesSharedPantryRebuild() {
        let buyFull = Ingredient(
            name: "Sea salt",
            quantity: 1,
            unit: "tsp",
            pantryDecision: .buyFull
        )
        let survivor = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let removed = Ingredient(name: "Olive oil", quantity: 1, unit: "tbsp")
        let model = pantryAllocationModel(
            ingredients: [buyFull, survivor, removed],
            remainingAmount: 1
        )
        model.activeRecipe.ingredients[0].pantryDecision = .buyFull
        model.activeRecipe.ingredients[0].pantryState = .needToBuy

        XCTAssertTrue(model.removeIngredient(id: removed.id))

        XCTAssertEqual(model.activeRecipe.ingredients[0].pantryDecision, .buyFull)
        XCTAssertEqual(model.activeRecipe.ingredients[1].pantryDecision, .review)
    }

    @MainActor
    func testDeletingUnrelatedRowDoesNotOptUnreviewedSafeMatchIntoPantryUse() {
        let unresolved = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let removed = Ingredient(name: "Olive oil", quantity: 1, unit: "tbsp")
        let model = pantryAllocationModel(
            ingredients: [unresolved, removed],
            remainingAmount: 1
        )
        XCTAssertEqual(model.activeRecipe.ingredients[0].pantryDecision, .review)

        XCTAssertTrue(model.removeIngredient(id: removed.id))

        XCTAssertEqual(model.activeRecipe.ingredients[0].pantryDecision, .review)
        XCTAssertEqual(model.quantityToBuy(for: model.activeRecipe.ingredients[0]), 1)
    }

    @MainActor
    func testExplicitUseSafeMatchesOverridesEarlierBuyFullChoice() {
        let ingredient = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let model = pantryAllocationModel(
            ingredients: [ingredient],
            remainingAmount: 1
        )
        model.setPantryDecision(.buyFull, for: ingredient.id)

        model.useSafePantrySuggestions()

        XCTAssertEqual(model.activeRecipe.ingredients[0].pantryDecision, .useAvailable)
        XCTAssertEqual(model.quantityToBuy(for: model.activeRecipe.ingredients[0]), 0)
    }

    @MainActor
    func testInvalidUseAvailableBecomesReviewDuringSharedPantryRebuild() {
        let stale = Ingredient(
            name: "Garlic",
            quantity: 1,
            unit: "clove",
            pantryState: .runningLow,
            pantryDecision: .useAvailable
        )
        let removed = Ingredient(name: "Olive oil", quantity: 1, unit: "tbsp")
        let model = pantryAllocationModel(
            ingredients: [stale, removed],
            remainingAmount: 1
        )
        model.activeRecipe.ingredients[0].pantryDecision = .useAvailable
        model.activeRecipe.ingredients[0].pantryState = .runningLow

        XCTAssertTrue(model.removeIngredient(id: removed.id))

        XCTAssertNil(model.activeRecipe.ingredients[0].pantrySuggestion)
        XCTAssertEqual(model.activeRecipe.ingredients[0].pantryDecision, .review)
        XCTAssertEqual(model.activeRecipe.ingredients[0].pantryState, .alwaysAsk)
    }

    @MainActor
    func testPossiblePantryMatchRemainsOptInDuringSharedRebuild() {
        let oil = Ingredient(name: "Olive oil", quantity: 1, unit: "tbsp")
        let removed = Ingredient(name: "Garlic", quantity: 1, unit: "clove")
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.pantryInventory = [
            PantryInventoryItem(
                name: "Olive oil",
                quantity: 1,
                unit: "package",
                remainingAmount: 1,
                remainingUnit: "package",
                hasUnknownPackageMass: true
            )
        ]
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [oil, removed])))

        XCTAssertTrue(model.removeIngredient(id: removed.id))

        XCTAssertEqual(model.activeRecipe.ingredients[0].pantrySuggestion?.coverage, .possible)
        XCTAssertEqual(model.activeRecipe.ingredients[0].pantryDecision, .review)
        XCTAssertEqual(model.quantityToBuy(for: model.activeRecipe.ingredients[0]), 1)
    }

    @MainActor
    func testRelaunchPreservesRebuiltSharedPantryAllocations() throws {
        let store = InMemorySmartCartStateStore()
        let first = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let second = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let model = pantryAllocationModel(
            ingredients: [first, second],
            remainingAmount: 1,
            store: store
        )
        model.useSafePantrySuggestions()
        XCTAssertTrue(model.removeIngredient(id: first.id))

        let restored = AppModel(stateStore: store)
        let survivor = try XCTUnwrap(restored.activeRecipe.ingredients.first)
        XCTAssertEqual(survivor.id, second.id)
        XCTAssertEqual(survivor.pantryDecision, .useAvailable)
        XCTAssertEqual(survivor.pantrySuggestion?.availableQuantity, 1)
        XCTAssertEqual(
            restored.recipes.first(where: { $0.id == restored.activeRecipe.id }),
            restored.activeRecipe
        )
    }

    @MainActor
    func testDeletionReallocationDoesNotMutateCompletedTripSnapshots() async throws {
        let first = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let second = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let model = pantryAllocationModel(
            ingredients: [first, second],
            remainingAmount: 1
        )
        model.useSafePantrySuggestions()
        await model.startMatching()
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let sessionsBefore = model.shoppingSessions
        let listsBefore = model.savedLists

        XCTAssertTrue(model.removeIngredient(id: first.id))

        XCTAssertEqual(model.shoppingSessions, sessionsBefore)
        XCTAssertEqual(model.savedLists, listsBefore)
        XCTAssertEqual(model.shoppingSession(id: sessionID), sessionsBefore.first { $0.id == sessionID })
    }

    @MainActor
    func testDeletionPersistenceFailureRollsBackRecipeAllocationAndPreTripState() async throws {
        let store = ControllableSmartCartStateStore()
        let first = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let second = Ingredient(name: "Sea salt", quantity: 1, unit: "tsp")
        let model = pantryAllocationModel(
            ingredients: [first, second],
            remainingAmount: 1,
            store: store
        )
        model.useSafePantrySuggestions()
        await model.startMatching()
        let activeBefore = model.activeRecipe
        let recipesBefore = model.recipes
        let itemsBefore = model.shoppingItems
        let persistedBefore = store.state
        store.failNextSave = true

        XCTAssertFalse(model.removeIngredient(id: first.id))

        XCTAssertEqual(model.activeRecipe, activeBefore)
        XCTAssertEqual(model.recipes, recipesBefore)
        XCTAssertEqual(model.shoppingItems, itemsBefore)
        XCTAssertEqual(store.state, persistedBefore)
        XCTAssertNotNil(model.persistenceIssue)
    }

    @MainActor
    private func pantryAllocationModel(
        ingredients: [Ingredient],
        remainingAmount: Double,
        store: any SmartCartStateStoring = InMemorySmartCartStateStore()
    ) -> AppModel {
        let model = AppModel(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults()
        )
        model.pantryInventory = [
            PantryInventoryItem(
                name: "Sea salt",
                quantity: 1,
                unit: "tsp",
                remainingAmount: remainingAmount,
                remainingUnit: "tsp"
            )
        ]
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: ingredients)))
        return model
    }

    @MainActor
    func testIngredientRemovalInvalidatesOnlyItsPreTripProductMatch() async throws {
        let removed = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let survivor = Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [removed, survivor])))
        await model.startMatching()

        let survivorItem = try model.shoppingItems
            .first(where: { $0.ingredient.id == survivor.id })
            .firstUnwrapped()
        let alternative = try survivorItem.alternatives
            .first(where: { $0.isExactProductLink })
            .firstUnwrapped()
        model.selectAlternative(itemID: survivorItem.id, candidateID: alternative.id)
        let selectedSurvivor = try model.shoppingItems
            .first(where: { $0.ingredient.id == survivor.id })
            .firstUnwrapped()
        model.preferredProductIDsByIngredient = [:]

        XCTAssertTrue(model.removeIngredient(id: removed.id))
        XCTAssertEqual(model.shoppingItems.map(\.ingredient.id), [survivor.id])
        XCTAssertEqual(model.shoppingItems.first?.product.id, selectedSurvivor.product.id)

        await model.startMatching()
        XCTAssertEqual(model.shoppingItems.map(\.ingredient.id), [survivor.id])
        XCTAssertEqual(model.shoppingItems.first?.product.id, selectedSurvivor.product.id)
    }

    @MainActor
    func testIngredientRemovalNeverMutatesCommittedTripState() async throws {
        let removed = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let survivor = Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [removed, survivor])))
        await model.startMatching()
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        for ingredientID in [removed.id, survivor.id] {
            model.recordRetailerOutcome(.visited, for: ingredientID, sessionID: sessionID)
        }
        let sessionsSnapshot = model.shoppingSessions
        let savedListsSnapshot = model.savedLists
        let pantrySnapshot = model.pantryInventory
        let preferenceSnapshot = model.preferredProductIDsByIngredient

        XCTAssertTrue(model.removeIngredient(id: removed.id))
        XCTAssertEqual(model.shoppingSessions, sessionsSnapshot)
        XCTAssertEqual(model.savedLists, savedListsSnapshot)
        XCTAssertEqual(model.pantryInventory, pantrySnapshot)
        XCTAssertEqual(model.preferredProductIDsByIngredient, preferenceSnapshot)
        XCTAssertNil(model.activeShoppingSessionID)
    }

    @MainActor
    func testIngredientRemovalRejectsStaleInFlightMatchingResults() async throws {
        let removed = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let survivor = Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: DelayedWalmartGuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [removed, survivor])))

        let matchingTask = Task { await model.startMatching() }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.removeIngredient(id: removed.id))
        _ = await matchingTask.value

        XCTAssertFalse(model.isMatching)
        XCTAssertFalse(model.shoppingItems.contains { $0.ingredient.id == removed.id })
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

    func testPhase4RecipeLinksRequireHTTPSAndClassifyPinterestHosts() throws {
        let trimmed = try XCTUnwrap(
            RecipeLinkInput.validHTTPSURL(from: "  https://example.com/recipes/pasta  ")
        )
        XCTAssertEqual(trimmed.absoluteString, "https://example.com/recipes/pasta")

        for invalid in [
            "", "www.example.com/recipe", "http://example.com/recipe",
            "ftp://example.com/recipe", "https:///recipe"
        ] {
            XCTAssertNil(RecipeLinkInput.validHTTPSURL(from: invalid), invalid)
        }

        for address in [
            "https://pin.it/abc123",
            "https://pinterest.com/pin/1",
            "https://www.pinterest.com/pin/2",
            "https://uk.pinterest.com/pin/3"
        ] {
            let url = try XCTUnwrap(RecipeLinkInput.validHTTPSURL(from: address))
            XCTAssertEqual(RecipeLinkInput.source(for: url), .pinterest, address)
        }

        for address in [
            "https://example.com/recipe",
            "https://notpinterest.com/recipe",
            "https://pinterest.com.evil.example/recipe"
        ] {
            let url = try XCTUnwrap(RecipeLinkInput.validHTTPSURL(from: address))
            XCTAssertEqual(RecipeLinkInput.source(for: url), .link, address)
        }

        let destination = SheetDestination.importer(.pinterest, trimmed.absoluteString)
        guard case let .importer(method, initialText) = destination else {
            return XCTFail("Expected importer destination")
        }
        XCTAssertEqual(method, .pinterest)
        XCTAssertEqual(initialText, trimmed.absoluteString)
        XCTAssertEqual(destination.id, "importer-pinterest")
    }

    @MainActor
    func testPhase4EmptyRecipeRejectionPreservesFlowAndActiveRecipe() {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        let active = phase4Recipe(title: "Active recipe")
        XCTAssertTrue(model.beginRecipe(active))
        model.selectedTab = .pantry
        model.homePath = [.recipeReady, .preferences]
        model.openImporter(.recipeText, initialText: "draft ingredients")

        let originalPath = model.homePath
        let originalRecents = model.recentRecipeIDs
        let originalRecipes = model.recipes
        let originalActiveSessionID = model.activeShoppingSessionID
        let empty = Recipe(
            title: "Empty recipe",
            source: .text,
            sourceDetail: "Tests",
            heroSymbol: "fork.knife",
            servings: 2,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: []
        )

        XCTAssertFalse(model.beginRecipe(empty))

        XCTAssertEqual(model.selectedTab, .pantry)
        XCTAssertEqual(model.homePath, originalPath)
        XCTAssertEqual(model.recentRecipeIDs, originalRecents)
        XCTAssertEqual(model.recipes, originalRecipes)
        XCTAssertEqual(model.activeRecipe, active)
        XCTAssertEqual(model.activeShoppingSessionID, originalActiveSessionID)
        guard case let .importer(method, initialText) = model.presentedSheet else {
            return XCTFail("Recipe rejection should leave the importer presented")
        }
        XCTAssertEqual(method, .recipeText)
        XCTAssertEqual(initialText, "draft ingredients")
    }

    @MainActor
    func testPhase4SuccessfulBeginRecipeRoutesAndOrdersRecents() {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        let first = phase4Recipe(title: "First")
        let second = phase4Recipe(title: "Second")

        XCTAssertTrue(model.beginRecipe(first))
        XCTAssertTrue(model.beginRecipe(second))
        model.selectedTab = .lists
        model.openImporter(.recipeLink, initialText: "https://example.com/first")
        XCTAssertTrue(model.beginRecipe(first))

        XCTAssertEqual(model.selectedTab, .home)
        XCTAssertEqual(model.homePath, [.recipeReady])
        XCTAssertNil(model.presentedSheet)
        XCTAssertEqual(model.activeRecipe.id, first.id)
        XCTAssertEqual(model.recentRecipeIDs, [first.id, second.id])
        XCTAssertEqual(model.recentRecipes.map(\.id), [first.id, second.id])
    }

    @MainActor
    func testPhase4ExperiencedAndCompletedUserSignalsStayDistinct() throws {
        let fresh = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertFalse(fresh.hasExperiencedUserState)
        XCTAssertFalse(fresh.hasCompletedShoppingTrip)
        XCTAssertNil(fresh.mostRecentShoppedRecipe)

        XCTAssertTrue(fresh.beginRecipe(phase4Recipe(title: "Imported", source: .link)))
        XCTAssertTrue(fresh.hasExperiencedUserState)
        XCTAssertFalse(fresh.hasCompletedShoppingTrip)
        XCTAssertNil(fresh.mostRecentShoppedRecipe)

        let completed = try completePhase4Trip(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertTrue(completed.model.hasExperiencedUserState)
        XCTAssertTrue(completed.model.hasCompletedShoppingTrip)
        XCTAssertEqual(completed.model.mostRecentShoppedRecipe?.id, completed.model.activeRecipe.id)
    }

    @MainActor
    func testPhase4RecentRecipesUseInjectedIsolatedDefaults() {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let first = phase4Recipe(title: "First recent")
        let second = phase4Recipe(title: "Second recent")
        let model = AppModel(stateStore: store, commerceDefaults: defaults)

        XCTAssertTrue(model.beginRecipe(first))
        XCTAssertTrue(model.beginRecipe(second))
        XCTAssertTrue(model.beginRecipe(first))

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.recentRecipeIDs, [first.id, second.id])
        XCTAssertEqual(restored.recentRecipes.map(\.title), [first.title, second.title])

        let separatelyIsolated = AppModel(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertTrue(separatelyIsolated.recentRecipeIDs.isEmpty)
    }

    @MainActor
    func testRetailerQueueActionsNeverAlterRecentRecipeHistory() async throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: defaults
        )
        let recipe = phase2Recipe(ingredients: [
            Ingredient(name: "Penne pasta", quantity: 16, unit: "oz"),
            Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
        ])
        XCTAssertTrue(model.beginRecipe(recipe))
        XCTAssertTrue(model.saveRecipeToLibrary(recipe.id))
        model.completeRetailerSetup()
        let initialPublished = await model.startMatching()
        XCTAssertTrue(initialPublished)
        let retryPublished = await model.startMatching(force: true)
        XCTAssertTrue(retryPublished)
        for item in model.unresolvedMatchingExceptionItems {
            XCTAssertTrue(model.acceptMatchingException(itemID: item.id))
        }
        XCTAssertTrue(model.continueToShoppingTrip())
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())

        let originalRecents = model.recentRecipeRecords
        let originalRecipes = model.recipes
        let originalSavedRecipeIDs = model.savedRecipeIDs
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let currentItemID = try XCTUnwrap(model.currentGuidedItem?.id)

        func assertRecipeHistoryUnchanged() {
            XCTAssertEqual(model.recentRecipeRecords, originalRecents)
            XCTAssertEqual(model.recipes, originalRecipes)
            XCTAssertEqual(model.savedRecipeIDs, originalSavedRecipeIDs)
        }

        model.recordRetailerProductOpened(itemID: currentItemID)
        assertRecipeHistoryUnchanged()
        if let currentItem = model.currentGuidedItem,
           let alternative = currentItem.alternatives.first(where: {
               model.resolvedReplacementPackageCount(for: currentItem, product: $0) != nil
            }) {
            XCTAssertTrue(model.selectAlternative(itemID: currentItemID, candidateID: alternative.id))
            assertRecipeHistoryUnchanged()
        }

        XCTAssertTrue(
            model.handleAmbiguousRetailerBrowserDismissal(
                sessionID: sessionID,
                itemID: currentItemID
            )
        )
        assertRecipeHistoryUnchanged()
        XCTAssertTrue(model.openShoppingSession(sessionID))
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())

        model.advanceGuidedItem()
        assertRecipeHistoryUnchanged()
        XCTAssertTrue(model.pauseRetailerShoppingSession())
        assertRecipeHistoryUnchanged()
        XCTAssertTrue(model.openShoppingSession(sessionID))
        assertRecipeHistoryUnchanged()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        assertRecipeHistoryUnchanged()

        for item in model.shoppingItems where item.status == .waiting {
            XCTAssertTrue(model.recordRetailerOutcome(.visited, for: item.id, sessionID: sessionID))
            assertRecipeHistoryUnchanged()
        }
        model.startShoppingReconciliation()
        assertRecipeHistoryUnchanged()

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.recentRecipeRecords, originalRecents)
        XCTAssertEqual(restored.recipes, originalRecipes)
        XCTAssertEqual(restored.savedRecipeIDs, originalSavedRecipeIDs)
    }

    @MainActor
    func testPhase4NotYetLeavesCompletedTripPendingAcrossRelaunch() throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let completed = try completePhase4Trip(
            stateStore: store,
            commerceDefaults: defaults
        )

        XCTAssertTrue(
            completed.model.shoppingSession(id: completed.sessionID)?.hasPendingPantryUpdateReminder == true
        )
        XCTAssertEqual(completed.model.pendingShoppingSessions.map(\.id), [completed.sessionID])
        XCTAssertNil(completed.model.shoppingSession(id: completed.sessionID)?.reconciliation)
        XCTAssertNil(
            completed.model.shoppingSession(id: completed.sessionID)?.pantryUpdateReminderArchivedAt
        )

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        let restoredSession = try XCTUnwrap(restored.shoppingSession(id: completed.sessionID))
        XCTAssertTrue(restoredSession.isGuideComplete)
        XCTAssertFalse(restoredSession.isCommitted)
        XCTAssertTrue(restoredSession.hasPendingPantryUpdateReminder)
        XCTAssertNil(restoredSession.reconciliation)
        XCTAssertNil(restoredSession.pantryUpdateReminderArchivedAt)
        XCTAssertEqual(restored.pendingShoppingSessions.map(\.id), [completed.sessionID])
        XCTAssertTrue(restored.pantryInventory.isEmpty)
    }

    @MainActor
    func testPhase4ArchiveSuppressesOnlyReminderAndPersists() throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let completed = try completePhase4Trip(
            stateStore: store,
            commerceDefaults: defaults
        )
        let model = completed.model
        model.pantryInventory = [PantryInventoryItem(name: "Rice", quantity: 1, unit: "bag")]
        model.preferredProductIDsByIngredient = ["rice|walmart": "preferred-product"]
        model.saveShoppingReconciliationDraft(
            sessionID: completed.sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [completed.itemID],
            substitutions: []
        )
        let sessionBefore = try XCTUnwrap(model.shoppingSession(id: completed.sessionID))
        let pantryBefore = model.pantryInventory
        let shoppingPreferencesBefore = model.preferences
        let productPreferencesBefore = model.preferredProductIDsByIngredient
        let itemsBefore = model.shoppingItems
        let listsBefore = model.savedLists

        XCTAssertTrue(model.archivePantryUpdateReminder(sessionID: completed.sessionID))

        let archived = try XCTUnwrap(model.shoppingSession(id: completed.sessionID))
        let archivedAt = try XCTUnwrap(archived.pantryUpdateReminderArchivedAt)
        var expectedSession = sessionBefore
        expectedSession.pantryUpdateReminderArchivedAt = archivedAt
        XCTAssertEqual(archived, expectedSession)
        XCTAssertFalse(archived.hasPendingPantryUpdateReminder)
        XCTAssertNil(archived.reconciliation)
        XCTAssertEqual(archived.reconciliationDraft, sessionBefore.reconciliationDraft)
        XCTAssertEqual(model.pantryInventory, pantryBefore)
        XCTAssertEqual(model.preferences, shoppingPreferencesBefore)
        XCTAssertEqual(model.preferredProductIDsByIngredient, productPreferencesBefore)
        XCTAssertEqual(model.shoppingItems, itemsBefore)
        XCTAssertEqual(model.savedLists, listsBefore)
        XCTAssertFalse(model.pendingShoppingSessions.contains { $0.id == completed.sessionID })

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.shoppingSession(id: completed.sessionID), archived)
        XCTAssertEqual(restored.pantryInventory, pantryBefore)
        XCTAssertEqual(restored.preferences, shoppingPreferencesBefore)
        XCTAssertEqual(restored.preferredProductIDsByIngredient, productPreferencesBefore)
        XCTAssertEqual(restored.shoppingItems, itemsBefore)
        XCTAssertEqual(restored.savedLists, listsBefore)
        XCTAssertFalse(restored.pendingShoppingSessions.contains { $0.id == completed.sessionID })
    }

    @MainActor
    func testPhase4ArchiveSaveFailureRollsBackReminderState() throws {
        let store = ControllableSmartCartStateStore()
        let completed = try completePhase4Trip(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults()
        )
        let sessionsBefore = completed.model.shoppingSessions
        let itemsBefore = completed.model.shoppingItems
        let listsBefore = completed.model.savedLists
        let persistedBefore = store.state
        store.failNextSave = true

        XCTAssertFalse(
            completed.model.archivePantryUpdateReminder(sessionID: completed.sessionID)
        )

        XCTAssertEqual(completed.model.shoppingSessions, sessionsBefore)
        XCTAssertEqual(completed.model.shoppingItems, itemsBefore)
        XCTAssertEqual(completed.model.savedLists, listsBefore)
        XCTAssertEqual(store.state, persistedBefore)
        XCTAssertTrue(
            completed.model.shoppingSession(id: completed.sessionID)?.hasPendingPantryUpdateReminder == true
        )
        XCTAssertNotNil(completed.model.persistenceIssue)
    }

    @MainActor
    func testPhase4ArchivedTripReopensFromSavedListAndCanReconcileLater() throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let completed = try completePhase4Trip(
            stateStore: store,
            commerceDefaults: defaults
        )
        let model = completed.model
        XCTAssertTrue(model.archivePantryUpdateReminder(sessionID: completed.sessionID))
        let archivedAt = try XCTUnwrap(
            model.shoppingSession(id: completed.sessionID)?.pantryUpdateReminderArchivedAt
        )
        XCTAssertTrue(model.beginRecipe(phase4Recipe(title: "Later recipe")))

        model.openSavedList(completed.listID)

        XCTAssertEqual(model.activeShoppingSessionID, completed.sessionID)
        XCTAssertEqual(model.homePath, [.shoppingList])
        XCTAssertEqual(
            model.shoppingSession(id: completed.sessionID)?.pantryUpdateReminderArchivedAt,
            archivedAt
        )
        model.startShoppingReconciliation()
        XCTAssertEqual(model.homePath.last, .shoppingReconciliation(completed.sessionID))

        try model.commitShoppingReconciliation(
            sessionID: completed.sessionID,
            outcome: .didNotShop,
            purchasedItemIDs: [],
            substitutions: []
        )
        XCTAssertTrue(model.shoppingSession(id: completed.sessionID)?.isCommitted == true)
        XCTAssertEqual(
            model.shoppingSession(id: completed.sessionID)?.pantryUpdateReminderArchivedAt,
            archivedAt
        )
        XCTAssertTrue(model.pantryInventory.isEmpty)
    }

    @MainActor
    func testPhase4ArchiveSuppressesEveryAliasOfSameLogicalTrip() throws {
        let completed = try completePhase4Trip(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults()
        )
        let source = try XCTUnwrap(completed.model.shoppingSession(id: completed.sessionID))
        let alias = phase4Alias(of: source)
        completed.model.shoppingSessions.append(alias)
        XCTAssertEqual(completed.model.pendingShoppingSessions.count, 1)

        XCTAssertTrue(
            completed.model.archivePantryUpdateReminder(sessionID: completed.sessionID)
        )

        let sourceArchiveDate = try XCTUnwrap(
            completed.model.shoppingSession(id: completed.sessionID)?
                .pantryUpdateReminderArchivedAt
        )
        XCTAssertEqual(
            completed.model.shoppingSession(id: alias.id)?.pantryUpdateReminderArchivedAt,
            sourceArchiveDate
        )
        XCTAssertTrue(completed.model.pendingShoppingSessions.isEmpty)
    }

    func testPhase4ShoppingSessionArchiveFieldRoundTripsAndDecodesWhenMissing() throws {
        let state = try makeState()
        let item = try state.shoppingItems.firstUnwrapped()
        let archivedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ShoppingSession(
            recipeID: state.activeRecipe.id,
            recipeTitle: state.activeRecipe.title,
            storeID: try XCTUnwrap(item.product.storeID),
            items: [item],
            pantryUpdateReminderArchivedAt: archivedAt
        )
        let data = try JSONEncoder().encode(session)
        let roundTripped = try JSONDecoder().decode(ShoppingSession.self, from: data)
        XCTAssertEqual(roundTripped, session)
        XCTAssertEqual(roundTripped.pantryUpdateReminderArchivedAt, archivedAt)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNotNil(object.removeValue(forKey: "pantryUpdateReminderArchivedAt"))
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decodedLegacy = try JSONDecoder().decode(ShoppingSession.self, from: legacyData)
        XCTAssertNil(decodedLegacy.pantryUpdateReminderArchivedAt)
        XCTAssertEqual(decodedLegacy.id, session.id)
        XCTAssertEqual(decodedLegacy.items, session.items)
    }

    func testPhase4RecipeSourceTextRoundTripsAndDecodesWhenMissing() throws {
        var recipe = phase4Recipe(title: "Source-preserving recipe", source: .photo)
        recipe.rawSourceText = "INGREDIENTS\n1 cup rice\n\nDIRECTIONS\nSimmer until tender."

        let data = try JSONEncoder().encode(recipe)
        let roundTripped = try JSONDecoder().decode(Recipe.self, from: data)
        XCTAssertEqual(roundTripped, recipe)
        XCTAssertEqual(roundTripped.rawSourceText, recipe.rawSourceText)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNotNil(object.removeValue(forKey: "rawSourceText"))
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decodedLegacy = try JSONDecoder().decode(Recipe.self, from: legacyData)
        XCTAssertNil(decodedLegacy.rawSourceText)
        XCTAssertEqual(decodedLegacy.id, recipe.id)
        XCTAssertEqual(decodedLegacy.ingredients, recipe.ingredients)
    }

    @MainActor
    func testPhase4ShopAgainUsesCurrentPantryRetailerStoreAndPreferencesWithoutOutcomes() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        var staleOutcome = try model.shoppingItems.firstUnwrapped()
        staleOutcome.status = .addedToCart

        model.startRetailerGuide(.target)
        model.preferences.organicPolicy = .only
        model.preferences.dietaryRestrictions = [.glutenFree]
        model.fulfillmentMode = .delivery
        let expectedStoreID = model.primaryStore.id
        model.pantryInventory = [
            PantryInventoryItem(
                name: "Rice",
                quantity: 1,
                unit: "cup",
                remainingAmount: 0.5,
                remainingUnit: "cup"
            )
        ]
        model.shoppingItems = [staleOutcome]

        XCTAssertTrue(model.beginRecipe(phase4Recipe(title: "Shop Again")))

        XCTAssertEqual(model.selectedRetailer, .target)
        XCTAssertEqual(model.primaryStore.id, expectedStoreID)
        XCTAssertEqual(model.fulfillmentMode, .delivery)
        XCTAssertEqual(model.preferences.organicPolicy, .only)
        XCTAssertEqual(model.preferences.dietaryRestrictions, [.glutenFree])
        XCTAssertEqual(model.activeRecipe.ingredients.first?.pantrySuggestion?.coverage, .partial)
        XCTAssertEqual(model.activeRecipe.ingredients.first?.pantryDecision, .review)
        XCTAssertTrue(model.shoppingItems.isEmpty)
        XCTAssertNil(model.activeShoppingSessionID)
        XCTAssertEqual(model.homePath, [.recipeReady])
    }

    @MainActor
    func testSavedRecipeMembershipStartsEmptyAndNewImportsDoNotPolluteSamples() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults()
        )

        XCTAssertTrue(model.savedRecipes.isEmpty)
        XCTAssertEqual(model.sampleRecipes.count, 3)
        XCTAssertTrue(model.sampleRecipes.allSatisfy { $0.source == .sample })
        XCTAssertTrue(model.recipes.allSatisfy { !model.isRecipeSaved($0.id) })

        let imported = phase4Recipe(title: "Imported library recipe")
        XCTAssertTrue(model.beginRecipe(imported))
        XCTAssertEqual(model.savedRecipes.map(\.id), [imported.id])
        XCTAssertEqual(model.sampleRecipes.count, 3)
        XCTAssertTrue(model.sampleRecipes.allSatisfy { $0.source == .sample })

        let restored = AppModel(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertEqual(restored.savedRecipes.map(\.id), [imported.id])
        XCTAssertEqual(restored.sampleRecipes.count, 3)
    }

    @MainActor
    func testRemovingSavedMembershipPreservesTripsSnapshotsPantryAndPreferences() throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let completed = try completePhase4Trip(
            stateStore: store,
            commerceDefaults: defaults
        )
        let model = completed.model
        let recipeID = model.activeRecipe.id
        XCTAssertTrue(model.saveRecipeToLibrary(recipeID))
        model.recordRecipeOpened(recipeID)
        model.pantryInventory = [PantryInventoryItem(name: "Rice", quantity: 2, unit: "cup")]
        model.preferredProductIDsByIngredient = ["rice|walmart": "preferred-rice"]
        model.mealPrepDraft = MealPrepDraft(selections: [
            MealPrepSelection(recipe: model.activeRecipe, targetServings: 4)
        ])

        let recipesBefore = model.recipes
        let sessionsBefore = model.shoppingSessions
        let savedListsBefore = model.savedLists
        let pantryBefore = model.pantryInventory
        let preferencesBefore = model.preferences
        let productPreferencesBefore = model.preferredProductIDsByIngredient
        let analyticsBefore = model.analyticsEvents
        let draftBefore = model.mealPrepDraft

        XCTAssertTrue(model.removeRecipeFromLibrary(recipeID))
        XCTAssertFalse(model.isRecipeSaved(recipeID))
        XCTAssertEqual(model.recipes, recipesBefore)
        XCTAssertEqual(model.shoppingSessions, sessionsBefore)
        XCTAssertEqual(model.savedLists, savedListsBefore)
        XCTAssertEqual(model.pantryInventory, pantryBefore)
        XCTAssertEqual(model.preferences, preferencesBefore)
        XCTAssertEqual(model.preferredProductIDsByIngredient, productPreferencesBefore)
        XCTAssertEqual(model.analyticsEvents, analyticsBefore)
        XCTAssertEqual(model.mealPrepDraft, draftBefore)
        XCTAssertFalse(model.recentRecipeIDs.contains(recipeID))
        XCTAssertFalse(model.removeRecipeFromLibrary(recipeID))

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertFalse(restored.isRecipeSaved(recipeID))
        XCTAssertTrue(restored.recipes.contains { $0.id == recipeID })
        XCTAssertEqual(restored.shoppingSessions, sessionsBefore)
        XCTAssertEqual(restored.savedLists, savedListsBefore)
        XCTAssertEqual(restored.pantryInventory, pantryBefore)
        XCTAssertEqual(restored.preferredProductIDsByIngredient, productPreferencesBefore)
        XCTAssertEqual(restored.mealPrepDraft, draftBefore)
    }

    @MainActor
    func testOpeningAndEditingRetainedUnsavedRecipeDoesNotResaveUntilExplicitSave() {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(stateStore: store, commerceDefaults: defaults)
        let imported = phase4Recipe(title: "Keep history, not membership")

        XCTAssertTrue(model.beginRecipe(imported))
        XCTAssertTrue(model.removeRecipeFromLibrary(imported.id))
        model.activeRecipe.title = "Edited while unsaved"
        XCTAssertTrue(model.beginRecipe(model.activeRecipe))
        XCTAssertFalse(model.isRecipeSaved(imported.id))

        var restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertFalse(restored.isRecipeSaved(imported.id))
        XCTAssertEqual(
            restored.recipes.first(where: { $0.id == imported.id })?.title,
            "Edited while unsaved"
        )

        XCTAssertTrue(restored.saveRecipeToLibrary(imported.id))
        XCTAssertTrue(restored.isRecipeSaved(imported.id))
        restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertTrue(restored.isRecipeSaved(imported.id))
        XCTAssertEqual(restored.savedRecipes.first?.title, "Edited while unsaved")
    }

    @MainActor
    func testSavedMembershipRemovalFailureRollsBackMembershipAndRecency() {
        let store = ControllableSmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(stateStore: store, commerceDefaults: defaults)
        let imported = phase4Recipe(title: "Rollback recipe")
        XCTAssertTrue(model.beginRecipe(imported))
        let persistedBefore = store.state
        let recentsBefore = model.recentRecipeRecords

        store.failNextSave = true
        XCTAssertFalse(model.removeRecipeFromLibrary(imported.id))

        XCTAssertTrue(model.isRecipeSaved(imported.id))
        XCTAssertEqual(model.recentRecipeRecords, recentsBefore)
        XCTAssertEqual(store.state, persistedBefore)
        XCTAssertNotNil(model.persistenceIssue)
    }

    @MainActor
    func testSchema6MissingMembershipInfersNonSamplesAndInvalidIDsAreDiscarded() throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("schema6-without-membership.json")
        let seedStore = InMemorySmartCartStateStore()
        let seed = AppModel(
            stateStore: seedStore,
            commerceDefaults: isolatedCommerceDefaults()
        )
        let imported = phase4Recipe(title: "Existing schema 6 recipe")
        XCTAssertTrue(seed.beginRecipe(imported))
        var state = try XCTUnwrap(seedStore.state)
        state.savedRecipeIDs = nil

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
        let payload = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(payload.contains("savedRecipeIDs"))

        let store = JSONSmartCartStateStore(fileURL: fileURL)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertNil(loaded.savedRecipeIDs)
        let restored = AppModel(
            stateStore: InMemorySmartCartStateStore(state: loaded),
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertEqual(restored.savedRecipeIDs, [imported.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.contains("corrupt-") }
        )

        var invalidState = loaded
        invalidState.savedRecipeIDs = [imported.id, UUID()]
        let normalized = AppModel(
            stateStore: InMemorySmartCartStateStore(state: invalidState),
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertEqual(normalized.savedRecipeIDs, [imported.id])
    }

    func testSavedRecipeUISurfacesUseMembershipAndDedicatedSampleCatalog() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cart = try String(
            contentsOf: repositoryRoot.appendingPathComponent("SmartCart/Features/Cart/CartView.swift"),
            encoding: .utf8
        )
        let mealPrep = try String(
            contentsOf: repositoryRoot.appendingPathComponent("SmartCart/Features/MealPrep/MealPrepViews.swift"),
            encoding: .utf8
        )
        let composer = try String(
            contentsOf: repositoryRoot.appendingPathComponent("SmartCart/Features/Home/RecipeComposerSheet.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(cart.contains("Text(\"Saved Recipes\")"))
        XCTAssertTrue(cart.contains("appModel.savedRecipes"))
        XCTAssertTrue(cart.contains("Remove from Saved Recipes"))
        XCTAssertTrue(cart.contains("Existing Shopping Trips and pantry history will remain available."))
        XCTAssertTrue(cart.contains("recipe-ready-save-recipe"))
        XCTAssertTrue(mealPrep.contains("ForEach(appModel.savedRecipes)"))
        XCTAssertFalse(mealPrep.contains("ForEach(appModel.recipes)"))
        XCTAssertTrue(composer.contains("appModel.sampleRecipes"))
    }

    @MainActor
    func testExhaustiveMatchingPublishesMixedTerminalStatesInDemandOrder() async throws {
        let recorder = Slice3MatchingRequestRecorder()
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter(recorder: recorder)],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let exact = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let fallback = Ingredient(name: "Dragon fruit jam", quantity: 1, unit: "jar")
        let unresolved = Ingredient(name: "Mystery ingredient", quantity: 1, unit: "item")
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [exact, fallback, unresolved])))

        await model.startMatching()

        XCTAssertEqual(model.ingredientResolutions.map(\.id), [exact.id, fallback.id, unresolved.id])
        XCTAssertEqual(model.ingredientResolutions.count, 3)
        XCTAssertEqual(model.shoppingItems.map(\.ingredient.id), [exact.id, fallback.id])
        if case .exactProduct = model.ingredientResolutions[0].resolution {} else {
            XCTFail("The first demand should be an exact product")
        }
        if case .searchFallback = model.ingredientResolutions[1].resolution {} else {
            XCTFail("The second demand should remain a labeled search fallback")
        }
        XCTAssertEqual(
            model.ingredientResolutions[2].resolution,
            .unresolved(.fallbackUnavailable)
        )
        XCTAssertEqual(model.unresolvedIngredientResolutions.map(\.id), [unresolved.id])
    }

    @MainActor
    func testZeroCandidatesAndProviderFailureRemainTypedAndVisible() async throws {
        let zeroModel = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let zero = Ingredient(name: "Mystery ingredient", quantity: 1, unit: "item")
        XCTAssertTrue(zeroModel.beginRecipe(phase2Recipe(ingredients: [zero])))
        await zeroModel.startMatching()
        XCTAssertEqual(
            zeroModel.ingredientResolutions.first?.resolution,
            .unresolved(.fallbackUnavailable)
        )
        XCTAssertTrue(zeroModel.shoppingItems.isEmpty)

        let failureModel = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let failure = Ingredient(name: "Provider failure", quantity: 1, unit: "item")
        XCTAssertTrue(failureModel.beginRecipe(phase2Recipe(ingredients: [failure])))
        await failureModel.startMatching()
        XCTAssertEqual(
            failureModel.ingredientResolutions.first?.resolution,
            .unresolved(.transientProviderFailure)
        )
        XCTAssertEqual(
            failureModel.matchingFailureDescription(for: try failureModel.ingredientResolutions.firstUnwrapped()),
            "The retailer catalog could not be reached."
        )
    }

    @MainActor
    func testUnresolvedBlocksTripUntilDeliberateExclusion() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let exact = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let unresolved = Ingredient(name: "Mystery ingredient", quantity: 1, unit: "item")
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [exact, unresolved])))
        await model.startMatching()

        XCTAssertFalse(model.continueToShoppingTrip())
        XCTAssertTrue(model.excludeUnresolvedIngredient(unresolved.id))
        for item in model.unresolvedMatchingExceptionItems {
            XCTAssertTrue(model.acceptMatchingException(itemID: item.id))
        }
        XCTAssertFalse(model.hasUnresolvedMatchingWork)
        XCTAssertEqual(
            model.ingredientResolutions.first(where: { $0.id == unresolved.id })?.resolution,
            .userExcluded
        )
        XCTAssertTrue(model.continueToShoppingTrip())
    }

    @MainActor
    func testUnresolvedResolutionSurvivesRelaunch() async throws {
        let store = InMemorySmartCartStateStore()
        let ingredient = Ingredient(name: "Mystery ingredient", quantity: 1, unit: "item")
        var model: AppModel? = AppModel(
            stateStore: store,
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertTrue(model?.beginRecipe(phase2Recipe(ingredients: [ingredient])) == true)
        await model?.startMatching()
        XCTAssertEqual(model?.unresolvedIngredientResolutions.map(\.id), [ingredient.id])
        model = nil

        let restored = AppModel(
            stateStore: store,
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        XCTAssertEqual(restored.unresolvedIngredientResolutions.map(\.id), [ingredient.id])
        XCTAssertFalse(restored.continueToShoppingTrip())
    }

    @MainActor
    func testForcedRetryFetchesOnlyPreviouslyUnresolvedDemand() async throws {
        let recorder = Slice3MatchingRequestRecorder()
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter(recorder: recorder)],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let exact = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let fallback = Ingredient(name: "Dragon fruit jam", quantity: 1, unit: "jar")
        let unresolved = Ingredient(name: "Mystery ingredient", quantity: 1, unit: "item")
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [exact, fallback, unresolved])))
        await model.startMatching()
        await recorder.reset()

        await model.startMatching(force: true)

        let recordedNames = await recorder.names()
        XCTAssertEqual(recordedNames, ["Mystery ingredient"])
        XCTAssertEqual(model.ingredientResolutions.map(\.id), [exact.id, fallback.id, unresolved.id])
    }

    @MainActor
    func testMatchingCancellationPublishesNoPartialPlan() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter(delay: .milliseconds(150))],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let ingredients = [
            Ingredient(name: "Penne pasta", quantity: 16, unit: "oz"),
            Ingredient(name: "Olive oil", quantity: 2, unit: "tbsp")
        ]
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: ingredients)))

        let task = Task { await model.startMatching() }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        let published = await task.value

        XCTAssertFalse(published)
        XCTAssertTrue(model.shoppingItems.isEmpty)
        XCTAssertTrue(model.ingredientResolutions.isEmpty)
        XCTAssertFalse(model.isMatching)
        XCTAssertNotEqual(model.homePath.last, .shoppingTrip)
    }

    @MainActor
    func testStaleMatchingGenerationCannotOverwriteNewerRecipe() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter(delay: .milliseconds(100))],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let stale = Ingredient(name: "Mystery ingredient", quantity: 1, unit: "item")
        let current = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [stale])))
        let staleTask = Task { await model.startMatching() }
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [current])))
        let currentPublished = await model.startMatching()
        XCTAssertTrue(currentPublished)
        let stalePublished = await staleTask.value

        XCTAssertFalse(stalePublished)
        XCTAssertEqual(model.ingredientResolutions.map(\.id), [current.id])
        XCTAssertEqual(model.shoppingItems.map(\.ingredient.id), [current.id])
        XCTAssertNotEqual(model.homePath.last, .shoppingTrip)
    }

    @MainActor
    func testExactMatchingConsolidatesSameSKUWithEveryDemandTraceable() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let first = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let second = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [first, second])))

        await model.startMatching()

        let row = try model.shoppingItems.firstUnwrapped()
        XCTAssertEqual(model.shoppingItems.count, 1)
        XCTAssertEqual(row.purchaseGroup?.contributions.map(\.sourceIngredientID), [first.id, second.id])
        XCTAssertEqual(row.purchaseQuantity, 2)
        XCTAssertEqual(row.purchaseGroup?.packagePlan?.requiredQuantity?.dimension, .mass)
    }

    @MainActor
    func testMatchingKeepsEquivalentSearchFallbacksAsSeparateActions() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let first = Ingredient(name: "Dragon fruit jam", quantity: 1, unit: "jar")
        let second = Ingredient(name: "Dragon fruit jam", quantity: 1, unit: "jar")
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [first, second])))

        await model.startMatching()

        XCTAssertEqual(model.shoppingItems.count, 2)
        XCTAssertEqual(model.shoppingItems.map { $0.purchaseGroup?.contributions.count }, [1, 1])
        XCTAssertTrue(model.shoppingItems.allSatisfy { $0.purchaseGroup?.exactProductIdentity == nil })
    }

    @MainActor
    func testReplacementBeforeTripStartRegroupsWhenItCreatesExactProductCollision() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let pasta = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let garlic = Ingredient(name: "Garlic", quantity: 8, unit: "oz")
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [pasta, garlic])))
        await model.startMatching()
        XCTAssertEqual(model.shoppingItems.count, 2)

        let collisionProduct = try model.shoppingItems.first(where: {
            $0.ingredient.id == pasta.id
        }).firstUnwrapped().product
        let replacedID = garlic.id
        let replacedIndex = try XCTUnwrap(
            model.shoppingItems.firstIndex(where: { $0.ingredient.id == replacedID })
        )
        model.shoppingItems[replacedIndex].alternatives = [collisionProduct]

        XCTAssertTrue(
            model.selectAlternative(itemID: replacedID, candidateID: collisionProduct.id)
        )
        XCTAssertEqual(model.shoppingItems.count, 1)
        XCTAssertEqual(
            Set(try model.shoppingItems.firstUnwrapped().purchaseGroup?.contributions.map(\.sourceIngredientID) ?? []),
            Set([pasta.id, garlic.id])
        )
    }

    @MainActor
    func testReplacementCollisionKeepsCurrentActionAndOneDurablePendingSession() async throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(
            stateStore: store,
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: defaults
        )
        let pasta = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let garlic = Ingredient(name: "Garlic", quantity: 8, unit: "oz")
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [pasta, garlic])))
        let initialPublished = await model.startMatching()
        XCTAssertTrue(initialPublished)
        let collisionProduct = try model.shoppingItems
            .first(where: { $0.ingredient.id == pasta.id })
            .firstUnwrapped().product
        let garlicIndex = try XCTUnwrap(
            model.shoppingItems.firstIndex(where: { $0.ingredient.id == garlic.id })
        )
        model.shoppingItems[garlicIndex].alternatives = [collisionProduct]
        model.guidedIndex = garlicIndex
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let logicalTripID = model.shoppingSession(id: sessionID)?.reconciliationIdentity

        XCTAssertTrue(
            model.selectAlternative(
                itemID: garlic.id,
                candidateID: collisionProduct.id,
                sessionID: sessionID
            )
        )

        XCTAssertEqual(model.shoppingItems.count, 1)
        XCTAssertEqual(
            Set(model.currentGuidedItem?.purchaseGroup?.contributions.map(\.sourceIngredientID) ?? []),
            Set([pasta.id, garlic.id])
        )
        XCTAssertEqual(model.currentGuidedItem?.status, .waiting)
        XCTAssertEqual(model.activeShoppingSessionID, sessionID)
        XCTAssertEqual(model.shoppingSession(id: sessionID)?.reconciliationIdentity, logicalTripID)
        XCTAssertEqual(
            model.shoppingSessions.filter {
                $0.isReusable && $0.reconciliationIdentity == logicalTripID
            }.count,
            1
        )

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.activeShoppingSessionID, sessionID)
        XCTAssertEqual(restored.shoppingSession(id: sessionID)?.items.count, 1)
        XCTAssertEqual(restored.currentGuidedItem?.status, .waiting)
    }

    @MainActor
    func testReplacementWithStaleSessionIDFailsClosedWithoutMutation() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        let item = try model.shoppingItems
            .first(where: { !$0.alternatives.isEmpty })
            .firstUnwrapped()
        let replacement = try item.alternatives.firstUnwrapped()
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let originalItems = model.shoppingItems
        let originalSessions = model.shoppingSessions
        let originalLists = model.savedLists

        XCTAssertFalse(
            model.selectAlternative(
                itemID: item.id,
                candidateID: replacement.id,
                sessionID: UUID()
            )
        )
        XCTAssertEqual(model.shoppingItems, originalItems)
        XCTAssertEqual(model.shoppingSessions, originalSessions)
        XCTAssertEqual(model.savedLists, originalLists)
    }

    @MainActor
    func testActiveReplacementPreservesCurrentItemAcrossExactAndFallbackTransitions() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        let itemIndex = try XCTUnwrap(
            model.shoppingItems.indices.first { index in
                let item = model.shoppingItems[index]
                return model.resolvedReplacementPackageCount(for: item, product: item.product) != nil &&
                    item.alternatives.contains {
                        model.resolvedReplacementPackageCount(for: item, product: $0) != nil
                    }
            }
        )
        let original = model.shoppingItems[itemIndex]
        var fallback = try XCTUnwrap(
            original.alternatives.first {
                model.resolvedReplacementPackageCount(for: original, product: $0) != nil
            }
        )
        fallback.dataSource = .searchFallback
        fallback.linkKind = .searchResults
        fallback.packageQuantity = original.product.packageQuantity
        fallback.packageUnit = original.product.packageUnit
        fallback.variableWeight = original.product.variableWeight
        model.shoppingItems[itemIndex].alternatives = [fallback]
        model.guidedIndex = itemIndex
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)

        XCTAssertTrue(
            model.selectAlternative(
                itemID: original.id,
                candidateID: fallback.id,
                sessionID: sessionID
            )
        )
        XCTAssertEqual(model.currentGuidedItem?.product.linkKind, .searchResults)
        XCTAssertEqual(model.currentGuidedItem?.status, .waiting)
        let exact = try XCTUnwrap(
            model.currentGuidedItem?.alternatives.first(where: { $0.id == original.product.id })
        )

        XCTAssertTrue(
            model.selectAlternative(
                itemID: try XCTUnwrap(model.currentGuidedItem?.id),
                candidateID: exact.id,
                sessionID: sessionID
            )
        )
        XCTAssertEqual(model.currentGuidedItem?.product.id, original.product.id)
        XCTAssertEqual(model.currentGuidedItem?.status, .waiting)
        XCTAssertEqual(model.activeShoppingSessionID, sessionID)
    }

    @MainActor
    func testStartedGroupedTripDoesNotRegroupOrChangeQuantity() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let first = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let second = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [first, second])))
        await model.startMatching()
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let frozen = model.shoppingItems
        let row = try frozen.firstUnwrapped()

        model.updatePurchaseQuantity(for: row.id, delta: 1)
        XCTAssertFalse(model.selectAlternative(itemID: row.id, candidateID: UUID()))

        XCTAssertEqual(model.shoppingItems, frozen)
        XCTAssertEqual(model.shoppingSession(id: try XCTUnwrap(model.activeShoppingSessionID))?.items, frozen)
    }

    @MainActor
    func testOnePurchaseGroupCreatesOneReconciliationAcquisition() async throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            retailerAdapters: [.walmart: Slice3GuideAdapter()],
            commerceDefaults: isolatedCommerceDefaults()
        )
        let first = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        let second = Ingredient(name: "Penne pasta", quantity: 16, unit: "oz")
        XCTAssertTrue(model.beginRecipe(phase2Recipe(ingredients: [first, second])))
        await model.startMatching()
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let row = try model.shoppingItems.firstUnwrapped()
        XCTAssertTrue(model.recordRetailerOutcome(.addedToCart, for: row.id, sessionID: sessionID))

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtEverything,
            purchasedItemIDs: [row.id],
            substitutions: []
        )

        let acquisitions = model.shoppingSession(id: sessionID)?.reconciliation?.acquisitions
        XCTAssertEqual(acquisitions?.count, 1)
        XCTAssertEqual(acquisitions?.first?.shoppingItemID, row.id)
        XCTAssertEqual(acquisitions?.first?.amount, Double(row.purchaseQuantity))
    }

    @MainActor
    func testDomainUndoRestoresRemovedPantryItemDurablyAndIsIdempotent() async throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, commerceDefaults: isolatedCommerceDefaults())
        let inventory = [
            PantryInventoryItem(name: "Rice", quantity: 2, unit: "cup"),
            PantryInventoryItem(name: "Beans", quantity: 1, unit: "can")
        ]
        model.pantryInventory = inventory
        await model.flushPendingPersistence()

        model.removePantryItems(at: IndexSet(integer: 0))
        XCTAssertEqual(model.pantryInventory.map(\.name), ["Beans"])
        XCTAssertEqual(model.domainUndoAction?.actionTitle, "Undo")

        let didUndo = await model.undoPendingDomainAction()
        XCTAssertTrue(didUndo)
        XCTAssertEqual(model.pantryInventory, inventory)
        XCTAssertEqual(store.state?.pantryInventory, inventory)
        XCTAssertNil(model.domainUndoAction)
        let repeatedUndo = await model.undoPendingDomainAction()
        XCTAssertFalse(repeatedUndo)

        let restored = AppModel(stateStore: store, commerceDefaults: isolatedCommerceDefaults())
        XCTAssertEqual(restored.pantryInventory, inventory)
        XCTAssertNil(restored.domainUndoAction)
    }

    @MainActor
    func testDomainUndoRestoresSavedRecipeMembershipAndRecency() async throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(stateStore: store, commerceDefaults: defaults)
        let recipe = phase4Recipe(title: "Undo library recipe")
        XCTAssertTrue(model.beginRecipe(recipe))
        model.recordRecipeOpened(recipe.id)
        let recipesBefore = model.recipes
        let recentsBefore = model.recentRecipeRecords

        XCTAssertTrue(model.removeRecipeFromLibrary(recipe.id))
        XCTAssertFalse(model.isRecipeSaved(recipe.id))
        XCTAssertFalse(model.recentRecipeIDs.contains(recipe.id))

        let didUndo = await model.undoPendingDomainAction()
        XCTAssertTrue(didUndo)
        XCTAssertTrue(model.isRecipeSaved(recipe.id))
        XCTAssertEqual(model.recipes, recipesBefore)
        XCTAssertEqual(model.recentRecipeRecords, recentsBefore)
        XCTAssertEqual(store.state?.savedRecipeIDs, model.savedRecipeIDs)
    }

    @MainActor
    func testDomainUndoRestoresRemovedMealPrepRecipe() async throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, commerceDefaults: isolatedCommerceDefaults())
        let recipe = phase4Recipe(title: "Undo Meal Prep recipe")
        XCTAssertTrue(model.beginRecipe(recipe))
        model.startMealPrepDraft()
        model.toggleMealPrepRecipe(recipe)
        let draftBeforeRemoval = try XCTUnwrap(model.mealPrepDraft)

        model.toggleMealPrepRecipe(recipe)
        XCTAssertFalse(model.isRecipeSelectedForMealPrep(recipe.id))
        XCTAssertEqual(model.domainUndoAction?.message, "Recipe removed from Meal Prep")

        let didUndo = await model.undoPendingDomainAction()
        XCTAssertTrue(didUndo)
        XCTAssertEqual(model.mealPrepDraft, draftBeforeRemoval)
        XCTAssertEqual(store.state?.mealPrepDraft, draftBeforeRemoval)
    }

    @MainActor
    func testFailedDomainUndoPreservesOpportunityAndRetryRestoresState() async throws {
        let store = ControllableSmartCartStateStore()
        let model = AppModel(stateStore: store, commerceDefaults: isolatedCommerceDefaults())
        let item = PantryInventoryItem(name: "Oats", quantity: 1, unit: "bag")
        model.pantryInventory = [item]
        await model.flushPendingPersistence()
        model.removePantryItems(at: IndexSet(integer: 0))

        store.failNextSave = true
        let failedUndo = await model.undoPendingDomainAction()
        XCTAssertFalse(failedUndo)
        XCTAssertTrue(model.pantryInventory.isEmpty)
        XCTAssertEqual(model.domainUndoAction?.actionTitle, "Retry")

        let retrySucceeded = await model.undoPendingDomainAction()
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(model.pantryInventory, [item])
        XCTAssertNil(model.domainUndoAction)
    }

    @MainActor
    func testDomainUndoRejectsStaleRevisionAndClearsSensitiveSnapshot() async throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, commerceDefaults: isolatedCommerceDefaults())
        model.pantryInventory = [PantryInventoryItem(name: "Flour")]
        await model.flushPendingPersistence()
        model.removePantryItems(at: IndexSet(integer: 0))

        model.zipCode = "10001"
        await model.flushPendingPersistence()

        let didUndo = await model.undoPendingDomainAction()
        XCTAssertFalse(didUndo)
        XCTAssertTrue(model.pantryInventory.isEmpty)
        XCTAssertNil(model.domainUndoAction)
        XCTAssertTrue(store.state?.pantryInventory.isEmpty == true)
    }

    @MainActor
    func testNewerDomainOperationInvalidatesOlderUndo() async throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, commerceDefaults: isolatedCommerceDefaults())
        let rice = PantryInventoryItem(name: "Rice")
        let beans = PantryInventoryItem(name: "Beans")
        let oats = PantryInventoryItem(name: "Oats")
        model.pantryInventory = [rice, beans, oats]
        await model.flushPendingPersistence()

        model.removePantryItems(at: IndexSet(integer: 0))
        let firstUndoID = try XCTUnwrap(model.domainUndoAction?.id)
        model.removePantryItems(at: IndexSet(integer: 0))
        XCTAssertNotEqual(model.domainUndoAction?.id, firstUndoID)

        let didUndo = await model.undoPendingDomainAction()
        XCTAssertTrue(didUndo)
        XCTAssertEqual(model.pantryInventory, [beans, oats])
        XCTAssertFalse(model.pantryInventory.contains(rice))
    }

    @MainActor
    func testPreTripSkipUndoRestoresCompleteShoppingItemAndResolutionState() async throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(
            stateStore: store,
            commerceDefaults: isolatedCommerceDefaults(),
            seedDemoShoppingState: true
        )
        var item = try model.shoppingItems.firstUnwrapped()
        item.product.confidence = .review
        model.shoppingItems = [item]
        await model.flushPendingPersistence()
        let itemsBefore = model.shoppingItems
        let resolutionsBefore = model.ingredientResolutions

        XCTAssertTrue(model.skipMatchingException(itemID: item.id))
        XCTAssertEqual(model.shoppingItems.first?.status, .skipped)
        let didUndo = await model.undoPendingDomainAction()
        XCTAssertTrue(didUndo)

        XCTAssertEqual(model.shoppingItems, itemsBefore)
        XCTAssertEqual(model.ingredientResolutions, resolutionsBefore)
        XCTAssertEqual(store.state?.shoppingItems, itemsBefore)
    }

    @MainActor
    func testArchiveUndoRestoresFrozenTripExactlyAndRelaunchDoesNotOfferOldUndo() async throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let completed = try completePhase4Trip(stateStore: store, commerceDefaults: defaults)
        let sessionsBefore = completed.model.shoppingSessions
        let listsBefore = completed.model.savedLists

        XCTAssertTrue(completed.model.archivePantryUpdateReminder(sessionID: completed.sessionID))
        let didUndo = await completed.model.undoPendingDomainAction()
        XCTAssertTrue(didUndo)
        XCTAssertEqual(completed.model.shoppingSessions, sessionsBefore)
        XCTAssertEqual(completed.model.savedLists, listsBefore)

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertEqual(restored.shoppingSessions, sessionsBefore)
        XCTAssertEqual(restored.savedLists, listsBefore)
        XCTAssertNil(restored.domainUndoAction)
    }

    @MainActor
    func testUnappliedDomainUndoDoesNotSurviveRelaunch() async throws {
        let store = InMemorySmartCartStateStore()
        let defaults = isolatedCommerceDefaults()
        let model = AppModel(stateStore: store, commerceDefaults: defaults)
        model.pantryInventory = [PantryInventoryItem(name: "Sugar")]
        await model.flushPendingPersistence()
        model.removePantryItems(at: IndexSet(integer: 0))
        XCTAssertNotNil(model.domainUndoAction)

        let restored = AppModel(stateStore: store, commerceDefaults: defaults)
        XCTAssertTrue(restored.pantryInventory.isEmpty)
        XCTAssertNil(restored.domainUndoAction)
    }

    private func phase4Recipe(
        title: String,
        source: RecipeSource = .text
    ) -> Recipe {
        Recipe(
            title: title,
            source: source,
            sourceDetail: "Phase 4 tests",
            heroSymbol: "fork.knife",
            servings: 2,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: [Ingredient(name: "Rice", quantity: 1, unit: "cup")]
        )
    }

    @MainActor
    private func startIncompleteShoppingTrip(
        stateStore: any SmartCartStateStoring,
        commerceDefaults: UserDefaults
    ) throws -> (model: AppModel, sessionID: UUID, manifestID: UUID) {
        let model = AppModel(
            stateStore: stateStore,
            commerceDefaults: commerceDefaults,
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let session = try XCTUnwrap(model.shoppingSession(id: sessionID))
        XCTAssertFalse(session.isGuideComplete)
        let manifestID = try XCTUnwrap(session.manifestID)
        XCTAssertTrue(model.savedLists.contains { $0.manifest.id == manifestID })
        return (model, sessionID, manifestID)
    }

    @MainActor
    private func completePhase4Trip(
        stateStore: any SmartCartStateStoring,
        commerceDefaults: UserDefaults
    ) throws -> (model: AppModel, sessionID: UUID, itemID: UUID, listID: UUID) {
        let model = AppModel(
            stateStore: stateStore,
            commerceDefaults: commerceDefaults,
            seedDemoShoppingState: true
        )
        model.completeRetailerSetup()
        model.shoppingItems = [try model.shoppingItems.firstUnwrapped()]
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let sessionID = try XCTUnwrap(model.activeShoppingSessionID)
        let itemID = try model.shoppingItems.firstUnwrapped().id
        XCTAssertTrue(
            model.recordRetailerOutcome(
                .savedToWishlist,
                for: itemID,
                sessionID: sessionID
            )
        )
        let manifestID = try XCTUnwrap(model.shoppingSession(id: sessionID)?.manifestID)
        let listID = try XCTUnwrap(
            model.savedLists.first(where: { $0.manifest.id == manifestID })?.id
        )
        return (model, sessionID, itemID, listID)
    }

    private func phase4Alias(of source: ShoppingSession) -> ShoppingSession {
        ShoppingSession(
            tripID: source.tripID,
            logicalTripID: source.logicalTripID,
            recipeID: source.recipeID,
            recipeTitle: source.recipeTitle,
            manifestID: source.manifestID,
            storeID: source.storeID,
            retailerID: source.retailerID,
            desiredServings: source.desiredServings,
            fulfillmentMode: source.fulfillmentMode,
            shoppingScope: source.shoppingScope,
            mealPrepSnapshot: source.mealPrepSnapshot,
            startedAt: source.startedAt.addingTimeInterval(1),
            items: source.items,
            stateFingerprint: source.stateFingerprint,
            reconciliationDraft: source.reconciliationDraft,
            reconciliation: source.reconciliation,
            pantryUpdateReminderArchivedAt: source.pantryUpdateReminderArchivedAt
        )
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

    private func focusCandidate(
        _ text: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double = 0.05,
        confidence: Double = 0.95
    ) -> OCRFocusTextCandidate {
        OCRFocusTextCandidate(
            text: text,
            boundingBox: OCRNormalizedBoundingBox(
                x: x,
                y: y,
                width: width,
                height: height
            ),
            confidence: confidence
        )
    }
}

private actor Slice3MatchingRequestRecorder {
    private var recordedNames: [String] = []

    func record(_ name: String) {
        recordedNames.append(name)
    }

    func reset() {
        recordedNames = []
    }

    func names() -> [String] {
        recordedNames
    }
}

private struct Slice3GuideAdapter: RetailerGuideAdapter {
    enum Failure: Error { case provider }

    private let base = DemoWalmartCatalogService()
    private let recorder: Slice3MatchingRequestRecorder?
    private let delay: Duration?

    init(
        recorder: Slice3MatchingRequestRecorder? = nil,
        delay: Duration? = nil
    ) {
        self.recorder = recorder
        self.delay = delay
    }

    var retailer: ShoppingRetailer { .walmart }
    var retailerID: String { base.retailerID }
    var capabilities: RetailerCapabilities { base.capabilities }

    func searchProducts(
        for request: RetailerProductSearchRequest
    ) async throws -> [RetailerProductRecord] {
        await recorder?.record(request.ingredient.name)
        if let delay { try await Task.sleep(for: delay) }
        if request.ingredient.name == "Provider failure" { throw Failure.provider }
        return try await base.searchProducts(for: request)
    }

    func resolveProduct(
        retailerProductID: String,
        storeID: String?
    ) async throws -> RetailerProductRecord {
        try await base.resolveProduct(retailerProductID: retailerProductID, storeID: storeID)
    }

    func refresh(product: RetailerProductRecord) async throws -> RetailerProductRecord {
        try await base.refresh(product: product)
    }

    func createHandoff(manifest: ShoppingManifest) async throws -> RetailerHandoff {
        try await base.createHandoff(manifest: manifest)
    }

    func searchFallback(
        for ingredient: Ingredient,
        storeID: String,
        preferences: ShoppingPreferences
    ) -> RetailerProductRecord {
        base.searchFallback(for: ingredient, storeID: storeID, preferences: preferences)
    }

    func batchSearchFallback(
        for ingredient: Ingredient,
        storeID: String,
        preferences: ShoppingPreferences
    ) -> RetailerProductRecord? {
        guard ingredient.name == "Dragon fruit jam" else { return nil }
        return base.searchFallback(for: ingredient, storeID: storeID, preferences: preferences)
    }
}

private struct DelayedWalmartGuideAdapter: RetailerGuideAdapter {
    private let base = DemoWalmartCatalogService()

    var retailer: ShoppingRetailer { .walmart }
    var retailerID: String { base.retailerID }
    var capabilities: RetailerCapabilities { base.capabilities }

    func searchProducts(
        for request: RetailerProductSearchRequest
    ) async throws -> [RetailerProductRecord] {
        try await Task.sleep(for: .milliseconds(120))
        return try await base.searchProducts(for: request)
    }

    func resolveProduct(
        retailerProductID: String,
        storeID: String?
    ) async throws -> RetailerProductRecord {
        try await base.resolveProduct(
            retailerProductID: retailerProductID,
            storeID: storeID
        )
    }

    func refresh(product: RetailerProductRecord) async throws -> RetailerProductRecord {
        try await base.refresh(product: product)
    }

    func createHandoff(manifest: ShoppingManifest) async throws -> RetailerHandoff {
        try await base.createHandoff(manifest: manifest)
    }

    func searchFallback(
        for ingredient: Ingredient,
        storeID: String,
        preferences: ShoppingPreferences
    ) -> RetailerProductRecord {
        base.searchFallback(
            for: ingredient,
            storeID: storeID,
            preferences: preferences
        )
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

private struct ThrowingBarcodeAdapter: BarcodeProductAdapter {
    enum Failure: Error { case offline }

    let identifier = "failing-test-adapter"

    func resolve(_ barcode: NormalizedBarcode) async throws -> BarcodeProduct? {
        throw Failure.offline
    }
}

private final class BarcodeURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.url?.path == "/v1/barcodes/05449000000996" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let payload = """
        {
          "status": "resolved",
          "barcode": "05449000000996",
          "product": {
            "name": "Coca-Cola",
            "brand": "Coca-Cola",
            "quantity": "33 cl",
            "imageURL": "https://images.openfoodfacts.org/coca-cola.jpg"
          },
          "source": "open_food_facts",
          "verified": false
        }
        """.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class BarcodeNotFoundURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let payload = """
        {"status":"not_found","barcode":"04006381333931"}
        """.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class BarcodeHTTPNotFoundURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let payload = Data(
            #"{"status":"not_found","barcode":"04006381333931"}"#.utf8
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 404,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class BarcodeRouteNotFoundURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let payload = Data(
            #"{"error":{"code":"route_not_found","message":"Route does not exist"}}"#.utf8
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 404,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class BarcodeTimeoutURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
    }
    override func stopLoading() {}
}

private final class BarcodeOfflineURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

private final class BarcodeRateLimitURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { respond(statusCode: 429) }
    override func stopLoading() {}

    private func respond(statusCode: Int) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class BarcodeServerErrorURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 503,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class BarcodeInternalServerErrorURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 500,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class BarcodeUnsafeImageURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let payload = """
        {
          "status": "resolved",
          "barcode": "05449000000996",
          "product": {
            "name": "Coca-Cola",
            "brand": "Coca-Cola",
            "quantity": "33 cl",
            "imageURL": "http://images.openfoodfacts.org/coca-cola.jpg"
          },
          "source": "open_food_facts",
          "verified": false
        }
        """.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class BarcodeMismatchedIdentityURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let payload = """
        {
          "status": "resolved",
          "barcode": "04006381333931",
          "product": {
            "name": "Wrong product",
            "brand": "Wrong catalog identity",
            "quantity": "1 item",
            "imageURL": "https://images.openfoodfacts.org/wrong.jpg"
          },
          "source": "open_food_facts",
          "verified": false
        }
        """.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class BarcodeMalformedURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("not-json".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
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
