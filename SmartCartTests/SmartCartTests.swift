import Foundation
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

    func testRetailConnectorRegistryIsCredentialTruthful() async throws {
        XCTAssertEqual(RetailConnectorRegistry.profiles.count, 6)
        let walmart = try XCTUnwrap(RetailConnectorRegistry.profile(id: "walmart"))
        XCTAssertEqual(walmart.state, .demoReady)
        XCTAssertFalse(walmart.supportsCart)
        XCTAssertFalse(walmart.supportsWishlist)

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
        let model = AppModel(stateStore: store)
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
        let model = AppModel(stateStore: store)
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
