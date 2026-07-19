import XCTest
@testable import SmartCart

final class ReleaseBlockerMigrationTests: XCTestCase {
    private enum InjectedRewriteFailure: Error {
        case requested
    }

    @MainActor
    func testV5MigrationRewriteFailureReturnsMigratedStateAndRestoresLegacyBytes() throws {
        let fixture = try makeV5Fixture(zipCode: "13579")
        var rewriteAttempts = 0
        let store = JSONSmartCartStateStore(
            fileURL: fixture.fileURL,
            atomicWriter: { _, destination in
                rewriteAttempts += 1
                try FileManager.default.removeItem(at: destination)
                throw InjectedRewriteFailure.requested
            }
        )

        let migrated = try XCTUnwrap(store.load())

        XCTAssertEqual(rewriteAttempts, 1)
        XCTAssertEqual(migrated.schemaVersion, SmartCartPersistedState.currentSchemaVersion)
        XCTAssertEqual(migrated.zipCode, "13579")
        XCTAssertEqual(migrated.shoppingScope, .singleRecipe(fixture.legacy.activeRecipe.id))
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), fixture.originalData)
        XCTAssertEqual(
            store.lastLoadWarning,
            .migrationRewriteFailed(
                sourceSchemaVersion: 5,
                targetSchemaVersion: 6,
                preservedStateURL: fixture.fileURL
            )
        )
    }

    @MainActor
    func testAppModelLoadsMigratedV5StateInsteadOfDefaultsWhenRewriteFails() throws {
        let fixture = try makeV5Fixture(zipCode: "24680")
        let store = JSONSmartCartStateStore(
            fileURL: fixture.fileURL,
            atomicWriter: { _, _ in throw InjectedRewriteFailure.requested }
        )

        let model = AppModel(stateStore: store)
        let warningSource: any SmartCartStateStoring = store

        XCTAssertEqual(model.zipCode, "24680")
        XCTAssertEqual(model.activeRecipe.id, fixture.legacy.activeRecipe.id)
        XCTAssertEqual(model.shoppingItems, fixture.legacy.shoppingItems)
        XCTAssertNotNil(warningSource.lastLoadWarning)
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), fixture.originalData)
    }

    @MainActor
    func testV5MigrationRestoresExactActiveUnfinishedSessionID() throws {
        let fixture = try makeV5Fixture(zipCode: "11223", includeActiveSession: true)

        let migrated = try XCTUnwrap(JSONSmartCartStateStore(fileURL: fixture.fileURL).load())
        let expectedSession = try XCTUnwrap(fixture.legacy.shoppingSessions.first)

        XCTAssertEqual(migrated.activeShoppingSessionID, expectedSession.id)
        XCTAssertNotNil(migrated.shoppingSessions.first?.tripID)
        let restored = AppModel(stateStore: InMemorySmartCartStateStore(state: migrated))
        XCTAssertEqual(restored.activeShoppingSessionID, expectedSession.id)
        let itemID = try XCTUnwrap(restored.shoppingItems.first?.id)
        restored.recordRetailerOutcome(.savedToWishlist, for: itemID, sessionID: expectedSession.id)
        XCTAssertEqual(
            restored.shoppingSession(id: expectedSession.id)?.items.first?.status,
            .savedToWishlist
        )
    }

    @MainActor
    func testV5MigrationRestoresCompletedGuideForIdempotentReconciliation() throws {
        let fixture = try makeV5Fixture(
            zipCode: "11224",
            includeActiveSession: true,
            sessionGuideCompleted: true
        )

        let migrated = try XCTUnwrap(JSONSmartCartStateStore(fileURL: fixture.fileURL).load())
        let expectedSession = try XCTUnwrap(fixture.legacy.shoppingSessions.first)
        XCTAssertEqual(migrated.activeShoppingSessionID, expectedSession.id)

        let restored = AppModel(stateStore: InMemorySmartCartStateStore(state: migrated))
        XCTAssertTrue(restored.retailerGuideIsComplete)
        restored.startShoppingReconciliation()

        XCTAssertEqual(restored.homePath.last, .shoppingReconciliation(expectedSession.id))
        XCTAssertEqual(restored.shoppingSessions.count, 1)
    }

    @MainActor
    func testV5InProgressManifestWithoutSessionSynthesizesExactRecoverySession() throws {
        let fixture = try makeV5Fixture(
            zipCode: "11225",
            includeResumableManifest: true
        )
        XCTAssertTrue(fixture.legacy.shoppingSessions.isEmpty)
        let manifestItemIDs = Set(try XCTUnwrap(fixture.legacy.savedLists.first).manifest.items.map(\.id))
        let shoppingItemIDs = Set(fixture.legacy.shoppingItems.map(\.id))
        XCTAssertTrue(manifestItemIDs.isDisjoint(with: shoppingItemIDs))
        XCTAssertEqual(
            Set(try XCTUnwrap(fixture.legacy.savedLists.first).manifest.items.map(\.ingredientID)),
            Set(fixture.legacy.shoppingItems.map(\.ingredient.id))
        )

        let migrated = try XCTUnwrap(JSONSmartCartStateStore(fileURL: fixture.fileURL).load())
        let recoveredSessionID = try XCTUnwrap(migrated.activeShoppingSessionID)
        XCTAssertEqual(migrated.shoppingSessions.count, 1)
        XCTAssertEqual(migrated.shoppingSessions.first?.id, recoveredSessionID)
        XCTAssertEqual(migrated.shoppingSessions.first?.items, fixture.legacy.shoppingItems)
        XCTAssertEqual(
            migrated.shoppingSessions.first?.manifestID,
            fixture.legacy.savedLists.first?.manifest.id
        )

        let restored = AppModel(stateStore: InMemorySmartCartStateStore(state: migrated))
        XCTAssertTrue(restored.retailerSessionIsInProgress)
        XCTAssertEqual(restored.activeShoppingSessionID, recoveredSessionID)
        let itemID = try XCTUnwrap(restored.shoppingItems.first?.id)
        restored.recordRetailerOutcome(.savedToWishlist, for: itemID, sessionID: recoveredSessionID)
        XCTAssertEqual(restored.shoppingSession(id: recoveredSessionID)?.items.first?.status, .savedToWishlist)
    }

    @MainActor
    func testV5RecoveryRejectsStaleManifestWithMatchingIngredientIDs() throws {
        let fixture = try makeV5Fixture(
            zipCode: "11226",
            includeResumableManifest: true
        )
        var staleLegacy = fixture.legacy
        staleLegacy.shoppingItems[0].purchaseQuantity += 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(staleLegacy).write(to: fixture.fileURL, options: [.atomic])

        let migrated = try XCTUnwrap(JSONSmartCartStateStore(fileURL: fixture.fileURL).load())

        XCTAssertNil(migrated.activeShoppingSessionID)
        XCTAssertTrue(migrated.shoppingSessions.isEmpty)
    }

    @MainActor
    func testV5IdentityClustersDuplicateAliasesWithoutCollapsingLaterRepeat() throws {
        let fixture = try makeV5Fixture(
            zipCode: "11228",
            includeResumableManifest: true
        )
        var legacy = fixture.legacy
        let manifest = try XCTUnwrap(legacy.savedLists.first?.manifest)
        let tripAItems = clonedLegacyItems(legacy.shoppingItems)
        let tripAAliasItems = clonedLegacyItems(legacy.shoppingItems)
        let tripBItems = clonedLegacyItems(legacy.shoppingItems)
        let tripAID = UUID()
        let tripAAliasID = UUID()
        let tripBID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let committedAt = startedAt.addingTimeInterval(10)

        var tripA = ShoppingSession(
            tripID: tripAID,
            recipeID: legacy.activeRecipe.id,
            recipeTitle: legacy.activeRecipe.title,
            manifestID: manifest.id,
            storeID: manifest.storeID,
            retailerID: manifest.retailerID,
            desiredServings: legacy.desiredServings,
            fulfillmentMode: manifest.fulfillmentMode,
            shoppingScope: .singleRecipe(legacy.activeRecipe.id),
            startedAt: startedAt,
            items: tripAItems,
            reconciliation: ShoppingReconciliationRecord(
                outcome: .boughtFew,
                purchasedItemIDs: Set(tripAItems.map(\.id)),
                substitutions: [],
                pantryItemIDs: [],
                committedAt: committedAt
            )
        )
        tripA.logicalTripID = nil
        var tripAAlias = ShoppingSession(
            tripID: tripAAliasID,
            recipeID: legacy.activeRecipe.id,
            recipeTitle: legacy.activeRecipe.title,
            manifestID: nil,
            storeID: manifest.storeID,
            retailerID: manifest.retailerID,
            desiredServings: legacy.desiredServings,
            fulfillmentMode: manifest.fulfillmentMode,
            shoppingScope: .singleRecipe(legacy.activeRecipe.id),
            startedAt: startedAt.addingTimeInterval(5),
            items: tripAAliasItems
        )
        tripAAlias.logicalTripID = nil
        var tripB = ShoppingSession(
            tripID: tripBID,
            recipeID: legacy.activeRecipe.id,
            recipeTitle: legacy.activeRecipe.title,
            manifestID: manifest.id,
            storeID: manifest.storeID,
            retailerID: manifest.retailerID,
            desiredServings: legacy.desiredServings,
            fulfillmentMode: manifest.fulfillmentMode,
            shoppingScope: .singleRecipe(legacy.activeRecipe.id),
            startedAt: committedAt.addingTimeInterval(60),
            items: tripBItems
        )
        tripB.logicalTripID = nil
        legacy.shoppingSessions = [tripAAlias, tripB, tripA]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(legacy).write(to: fixture.fileURL, options: [.atomic])

        let migrated = try XCTUnwrap(
            JSONSmartCartStateStore(fileURL: fixture.fileURL).load()
        )
        let migratedA = try XCTUnwrap(migrated.shoppingSessions.first { $0.id == tripA.id })
        let migratedAlias = try XCTUnwrap(
            migrated.shoppingSessions.first { $0.id == tripAAlias.id }
        )
        let migratedB = try XCTUnwrap(migrated.shoppingSessions.first { $0.id == tripB.id })
        XCTAssertEqual(migratedA.reconciliationIdentity, migratedAlias.reconciliationIdentity)
        XCTAssertNotEqual(migratedA.reconciliationIdentity, migratedB.reconciliationIdentity)
        XCTAssertEqual(migrated.activeShoppingSessionID, tripB.id)

        let restored = AppModel(stateStore: InMemorySmartCartStateStore(state: migrated))
        XCTAssertEqual(restored.activeShoppingSessionID, tripB.id)
        restored.openSavedList(try XCTUnwrap(restored.savedLists.first?.id))
        XCTAssertEqual(restored.activeShoppingSessionID, tripB.id)
        let pantryBeforeAlias = restored.pantryInventory
        try restored.commitShoppingReconciliation(
            sessionID: tripAAlias.id,
            outcome: .boughtFew,
            purchasedItemIDs: Set(tripAAliasItems.map(\.id)),
            substitutions: []
        )
        XCTAssertEqual(restored.pantryInventory, pantryBeforeAlias)
        try restored.commitShoppingReconciliation(
            sessionID: tripB.id,
            outcome: .boughtFew,
            purchasedItemIDs: Set(tripBItems.map(\.id)),
            substitutions: []
        )
        XCTAssertNotEqual(restored.pantryInventory, pantryBeforeAlias)
    }

    @MainActor
    func testV5NilManifestAliasCannotBridgeDistinctManifestTrips() throws {
        let fixture = try makeV5Fixture(
            zipCode: "11229",
            includeResumableManifest: true
        )
        var legacy = fixture.legacy
        let manifestX = try XCTUnwrap(legacy.savedLists.first?.manifest.id)
        let manifestY = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_100_000)

        var nilManifestAlias = ShoppingSession(
            tripID: UUID(),
            recipeID: legacy.activeRecipe.id,
            recipeTitle: legacy.activeRecipe.title,
            manifestID: nil,
            storeID: legacy.savedLists[0].manifest.storeID,
            retailerID: legacy.savedLists[0].manifest.retailerID,
            desiredServings: legacy.desiredServings,
            fulfillmentMode: legacy.savedLists[0].manifest.fulfillmentMode,
            shoppingScope: .singleRecipe(legacy.activeRecipe.id),
            startedAt: startedAt,
            items: clonedLegacyItems(legacy.shoppingItems)
        )
        nilManifestAlias.logicalTripID = nil
        var tripX = ShoppingSession(
            tripID: UUID(),
            recipeID: legacy.activeRecipe.id,
            recipeTitle: legacy.activeRecipe.title,
            manifestID: manifestX,
            storeID: legacy.savedLists[0].manifest.storeID,
            retailerID: legacy.savedLists[0].manifest.retailerID,
            desiredServings: legacy.desiredServings,
            fulfillmentMode: legacy.savedLists[0].manifest.fulfillmentMode,
            shoppingScope: .singleRecipe(legacy.activeRecipe.id),
            startedAt: startedAt.addingTimeInterval(1),
            items: clonedLegacyItems(legacy.shoppingItems)
        )
        tripX.logicalTripID = nil
        var tripY = ShoppingSession(
            tripID: UUID(),
            recipeID: legacy.activeRecipe.id,
            recipeTitle: legacy.activeRecipe.title,
            manifestID: manifestY,
            storeID: legacy.savedLists[0].manifest.storeID,
            retailerID: legacy.savedLists[0].manifest.retailerID,
            desiredServings: legacy.desiredServings,
            fulfillmentMode: legacy.savedLists[0].manifest.fulfillmentMode,
            shoppingScope: .singleRecipe(legacy.activeRecipe.id),
            startedAt: startedAt.addingTimeInterval(2),
            items: clonedLegacyItems(legacy.shoppingItems)
        )
        tripY.logicalTripID = nil
        legacy.shoppingSessions = [tripY, nilManifestAlias, tripX]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(legacy).write(to: fixture.fileURL, options: [.atomic])

        let migrated = try XCTUnwrap(
            JSONSmartCartStateStore(fileURL: fixture.fileURL).load()
        )
        let migratedAlias = try XCTUnwrap(
            migrated.shoppingSessions.first { $0.id == nilManifestAlias.id }
        )
        let migratedX = try XCTUnwrap(
            migrated.shoppingSessions.first { $0.id == tripX.id }
        )
        let migratedY = try XCTUnwrap(
            migrated.shoppingSessions.first { $0.id == tripY.id }
        )

        XCTAssertEqual(migratedAlias.manifestID, manifestX)
        XCTAssertEqual(migratedAlias.reconciliationIdentity, migratedX.reconciliationIdentity)
        XCTAssertNotEqual(migratedAlias.reconciliationIdentity, migratedY.reconciliationIdentity)
        XCTAssertNotEqual(migratedX.reconciliationIdentity, migratedY.reconciliationIdentity)
        XCTAssertEqual(migratedY.manifestID, manifestY)
    }

    @MainActor
    func testCompletedV1ManifestMigratesReadOnlyAndRequiresExplicitFork() throws {
        let expectation = try XCTUnwrap(
            fixedLegacyFixtureExpectations.first { $0.version == 1 }
        )
        let fixture = try makeFixedLegacyFixture(expectation)
        let migrated = try XCTUnwrap(
            JSONSmartCartStateStore(fileURL: fixture.fileURL).load()
        )
        let recoveredSessionID = try XCTUnwrap(migrated.activeShoppingSessionID)
        let recoveredSession = try XCTUnwrap(
            migrated.shoppingSessions.first { $0.id == recoveredSessionID }
        )
        XCTAssertTrue(recoveredSession.isGuideComplete)

        let model = AppModel(stateStore: InMemorySmartCartStateStore(state: migrated))
        let listID = try XCTUnwrap(model.savedLists.first?.id)
        model.openSavedList(listID)
        XCTAssertTrue(model.activeShoppingSessionIsImmutable)
        let frozenItems = model.shoppingItems
        let itemID = try XCTUnwrap(frozenItems.first?.id)
        model.updatePurchaseQuantity(for: itemID, delta: 1)
        XCTAssertEqual(model.shoppingItems, frozenItems)

        let priorListCount = model.savedLists.count
        let historicalTripID = recoveredSession.reconciliationIdentity
        XCTAssertTrue(model.forkCompletedShoppingTrip())
        XCTAssertFalse(model.activeShoppingSessionIsImmutable)
        XCTAssertNil(model.activeShoppingSessionID)
        XCTAssertEqual(model.savedLists.count, priorListCount + 1)
        XCTAssertTrue(model.shoppingItems.allSatisfy { $0.status == .waiting })
        XCTAssertNotEqual(model.savedLists.first?.manifest.logicalTripID, historicalTripID)
    }

    @MainActor
    func testTransientReadFailureDoesNotQuarantineOrReplaceValidState() throws {
        let fixture = try makeV5Fixture(zipCode: "11227")
        let store = JSONSmartCartStateStore(
            fileURL: fixture.fileURL,
            dataReader: { _ in throw InjectedRewriteFailure.requested }
        )

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), fixture.originalData)
        let siblingNames = try FileManager.default.contentsOfDirectory(
            atPath: fixture.fileURL.deletingLastPathComponent().path
        )
        XCTAssertFalse(siblingNames.contains { $0.contains("corrupt-") })
    }

    @MainActor
    func testFixedLegacyFixturesSurviveRewriteFailureRetryAndRelaunch() throws {
        for expectation in fixedLegacyFixtureExpectations {
            let fixture = try makeFixedLegacyFixture(expectation)
            var attempts = 0
            let store = JSONSmartCartStateStore(
                fileURL: fixture.fileURL,
                atomicWriter: { _, destination in
                    attempts += 1
                    try FileManager.default.removeItem(at: destination)
                    throw InjectedRewriteFailure.requested
                }
            )

            let migrated = try XCTUnwrap(store.load(), "schema \(expectation.version)")

            XCTAssertEqual(attempts, 1, "schema \(expectation.version)")
            try assertDurableFields(in: migrated, match: expectation)
            XCTAssertEqual(try Data(contentsOf: fixture.fileURL), fixture.originalData)
            XCTAssertEqual(
                store.lastLoadWarning,
                .migrationRewriteFailed(
                    sourceSchemaVersion: expectation.version,
                    targetSchemaVersion: SmartCartPersistedState.currentSchemaVersion,
                    preservedStateURL: fixture.fileURL
                )
            )

            let retryStore = JSONSmartCartStateStore(fileURL: fixture.fileURL)
            let retried = try XCTUnwrap(retryStore.load(), "schema \(expectation.version) retry")
            try assertDurableFields(in: retried, match: expectation)
            XCTAssertNil(retryStore.lastLoadWarning)
            let rewrittenJSON = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: fixture.fileURL)) as? [String: Any]
            )
            XCTAssertEqual(
                rewrittenJSON["schemaVersion"] as? Int,
                SmartCartPersistedState.currentSchemaVersion
            )

            let relaunched = try XCTUnwrap(
                JSONSmartCartStateStore(fileURL: fixture.fileURL).load(),
                "schema \(expectation.version) relaunch"
            )
            try assertDurableFields(in: relaunched, match: expectation)
        }
    }

    @MainActor
    private func makeV5Fixture(
        zipCode: String,
        includeActiveSession: Bool = false,
        sessionGuideCompleted: Bool = false,
        includeResumableManifest: Bool = false
    ) throws -> (
        fileURL: URL,
        originalData: Data,
        legacy: LegacySmartCartPersistedStateV5
    ) {
        let seedStore = InMemorySmartCartStateStore()
        let seedModel = AppModel(stateStore: seedStore, seedDemoShoppingState: true)
        seedModel.zipCode = zipCode
        seedModel.persistNow()
        let state = try XCTUnwrap(seedStore.state)
        let legacyShoppingItems = state.shoppingItems.map { item -> ShoppingListItem in
            var item = item
            if sessionGuideCompleted { item.status = .savedToWishlist }
            return item
        }
        let shoppingSessions: [ShoppingSession]
        if includeActiveSession {
            shoppingSessions = [ShoppingSession(
                recipeID: state.activeRecipe.id,
                recipeTitle: state.activeRecipe.title,
                storeID: state.savedLists.first?.manifest.storeID ?? "walmart-90210-a",
                retailerID: ShoppingRetailer.walmart.rawValue,
                desiredServings: state.desiredServings,
                fulfillmentMode: state.fulfillmentMode,
                shoppingScope: .singleRecipe(state.activeRecipe.id),
                items: legacyShoppingItems
            )]
        } else {
            shoppingSessions = state.shoppingSessions
        }
        let savedLists: [SavedShoppingList]
        if includeResumableManifest {
            let manifest = ShoppingManifest(
                recipeID: state.activeRecipe.id,
                recipeTitle: state.activeRecipe.title,
                retailerID: ShoppingRetailer.walmart.rawValue,
                storeID: "walmart-5206",
                storeName: "Walmart Supercenter A",
                desiredServings: state.desiredServings,
                fulfillmentMode: state.fulfillmentMode,
                items: legacyShoppingItems.map { item in
                    ManifestLineItem(
                        ingredientID: item.ingredient.id,
                        ingredientName: item.ingredient.name,
                        requestedQuantity: item.requestedQuantity,
                        purchaseQuantity: item.purchaseQuantity,
                        product: item.product,
                        status: item.status
                    )
                },
                handoffProgress: .inProgress,
                shoppingScope: .singleRecipe(state.activeRecipe.id)
            )
            savedLists = [SavedShoppingList(manifest: manifest)]
        } else {
            savedLists = state.savedLists
        }
        let legacy = LegacySmartCartPersistedStateV5(
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
            shoppingItems: legacyShoppingItems,
            guidedIndex: state.guidedIndex,
            savedLists: savedLists,
            preferredDeliveryPartnerName: state.preferredDeliveryPartnerName,
            pantryInventory: state.pantryInventory,
            preferredProductIDsByIngredient: state.preferredProductIDsByIngredient,
            analyticsEvents: state.analyticsEvents,
            walmartWishlistReference: state.walmartWishlistReference,
            shoppingSessions: shoppingSessions
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let originalData = try encoder.encode(legacy)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartCart-ReleaseBlockerMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("state.json")
        try originalData.write(to: fileURL, options: [.atomic])
        return (fileURL, originalData, legacy)
    }

    private func clonedLegacyItems(
        _ items: [ShoppingListItem]
    ) -> [ShoppingListItem] {
        items.map { item in
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
    }

    private var fixedLegacyFixtureExpectations: [FixedLegacyFixtureExpectation] {
        [
            FixedLegacyFixtureExpectation(
                version: 0,
                recipeID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                recipeTitle: "V0 Lentil Soup",
                recipeSource: .text,
                ingredientID: UUID(uuidString: "00000000-0000-4000-8000-000000000010")!,
                ingredientName: "Green Lentils",
                ingredientRawText: "2 cups green lentils, rinsed",
                ingredientQuantity: 2,
                ingredientUnit: "cups",
                ingredientPreparation: "rinsed",
                ingredientPreferenceNote: "User corrected from red lentils",
                desiredServings: 5,
                storeStrategy: .oneStore,
                fulfillmentMode: .pickup,
                selectedStoreID: UUID(uuidString: "00000000-0000-4000-8000-000000000040")!,
                zipCode: "10000",
                pickupDay: "Tuesday",
                pickupTime: "9:00 AM - 10:00 AM",
                shoppingItemID: UUID(uuidString: "00000000-0000-4000-8000-000000000020")!,
                requestedQuantity: "2.5 cups for 5 servings",
                purchaseQuantity: 2,
                productID: UUID(uuidString: "00000000-0000-4000-8000-000000000030")!,
                productTitle: "V0 Dry Green Lentils",
                productStoreID: "walmart-v0-100",
                productPackageQuantity: 16,
                productPackageUnit: "oz",
                shoppingStatus: .added,
                guidedIndex: 1,
                savedListID: UUID(uuidString: "00000000-0000-4000-8000-000000000050")!,
                manifestID: UUID(uuidString: "00000000-0000-4000-8000-000000000060")!,
                manifestLineID: UUID(uuidString: "00000000-0000-4000-8000-000000000070")!,
                manifestStoreName: "V0 Neighborhood Market",
                manifestProgress: .inProgress
            ),
            FixedLegacyFixtureExpectation(
                version: 1,
                recipeID: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!,
                recipeTitle: "V1 Chickpea Curry",
                recipeSource: .photo,
                ingredientID: UUID(uuidString: "00000000-0000-4000-8000-000000000110")!,
                ingredientName: "Low Sodium Chickpeas",
                ingredientRawText: "1 1/2 cups low sodium chickpeas, drained",
                ingredientQuantity: 1.5,
                ingredientUnit: "cups",
                ingredientPreparation: "drained",
                ingredientPreferenceNote: "User chose low sodium",
                desiredServings: 6,
                storeStrategy: .multipleStops,
                fulfillmentMode: .delivery,
                selectedStoreID: UUID(uuidString: "00000000-0000-4000-8000-000000000140")!,
                zipCode: "20001",
                pickupDay: "Friday",
                pickupTime: "5:00 PM - 7:00 PM",
                shoppingItemID: UUID(uuidString: "00000000-0000-4000-8000-000000000120")!,
                requestedQuantity: "2.25 cups for 6 servings",
                purchaseQuantity: 2,
                productID: UUID(uuidString: "00000000-0000-4000-8000-000000000130")!,
                productTitle: "V1 Low Sodium Chickpeas",
                productStoreID: "walmart-v1-200",
                productPackageQuantity: 15,
                productPackageUnit: "oz",
                shoppingStatus: .added,
                guidedIndex: 1,
                savedListID: UUID(uuidString: "00000000-0000-4000-8000-000000000150")!,
                manifestID: UUID(uuidString: "00000000-0000-4000-8000-000000000160")!,
                manifestLineID: UUID(uuidString: "00000000-0000-4000-8000-000000000170")!,
                manifestStoreName: "V1 Supercenter",
                manifestProgress: .completed
            ),
            FixedLegacyFixtureExpectation(
                version: 2,
                recipeID: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
                recipeTitle: "V2 Brown Rice Bowl",
                recipeSource: .link,
                ingredientID: UUID(uuidString: "00000000-0000-4000-8000-000000000210")!,
                ingredientName: "Long Grain Brown Rice",
                ingredientRawText: "3 cups long grain brown rice",
                ingredientQuantity: 3,
                ingredientUnit: "cups",
                ingredientPreparation: "uncooked",
                ingredientPreferenceNote: "User corrected package variety",
                desiredServings: 8,
                storeStrategy: .oneStore,
                fulfillmentMode: .pickup,
                selectedStoreID: UUID(uuidString: "00000000-0000-4000-8000-000000000240")!,
                zipCode: "30002",
                pickupDay: "Saturday",
                pickupTime: "11:00 AM - 12:00 PM",
                shoppingItemID: UUID(uuidString: "00000000-0000-4000-8000-000000000220")!,
                requestedQuantity: "6 cups for 8 servings",
                purchaseQuantity: 1,
                productID: UUID(uuidString: "00000000-0000-4000-8000-000000000230")!,
                productTitle: "V2 Long Grain Brown Rice",
                productStoreID: "walmart-v2-300",
                productPackageQuantity: 32,
                productPackageUnit: "oz",
                shoppingStatus: .skipped,
                guidedIndex: 1,
                savedListID: UUID(uuidString: "00000000-0000-4000-8000-000000000250")!,
                manifestID: UUID(uuidString: "00000000-0000-4000-8000-000000000260")!,
                manifestLineID: UUID(uuidString: "00000000-0000-4000-8000-000000000270")!,
                manifestStoreName: "V2 Pickup Store",
                manifestProgress: .paused
            ),
            FixedLegacyFixtureExpectation(
                version: 3,
                recipeID: UUID(uuidString: "00000000-0000-4000-8000-000000000301")!,
                recipeTitle: "V3 Sheet Pan Tacos",
                recipeSource: .photo,
                ingredientID: UUID(uuidString: "00000000-0000-4000-8000-000000000310")!,
                ingredientName: "Black Beans",
                ingredientRawText: "2 (15 oz) cans black beans, drained",
                ingredientQuantity: 2,
                ingredientUnit: "cans",
                ingredientPreparation: "drained",
                ingredientPreferenceNote: "User confirmed two cans",
                desiredServings: 4,
                storeStrategy: .multipleStops,
                fulfillmentMode: .delivery,
                selectedStoreID: UUID(uuidString: "00000000-0000-4000-8000-000000000340")!,
                zipCode: "40003",
                pickupDay: "Sunday",
                pickupTime: "2:00 PM - 4:00 PM",
                shoppingItemID: UUID(uuidString: "00000000-0000-4000-8000-000000000320")!,
                requestedQuantity: "2 cans for 4 servings",
                purchaseQuantity: 2,
                productID: UUID(uuidString: "00000000-0000-4000-8000-000000000330")!,
                productTitle: "V3 No Salt Black Beans",
                productStoreID: "walmart-v3-400",
                productPackageQuantity: 15,
                productPackageUnit: "oz",
                shoppingStatus: .added,
                guidedIndex: 1,
                savedListID: UUID(uuidString: "00000000-0000-4000-8000-000000000350")!,
                manifestID: UUID(uuidString: "00000000-0000-4000-8000-000000000360")!,
                manifestLineID: UUID(uuidString: "00000000-0000-4000-8000-000000000370")!,
                manifestStoreName: "V3 Delivery Store",
                manifestProgress: .inProgress
            ),
            FixedLegacyFixtureExpectation(
                version: 4,
                recipeID: UUID(uuidString: "00000000-0000-4000-8000-000000000401")!,
                recipeTitle: "V4 Citrus Chicken",
                recipeSource: .pinterest,
                ingredientID: UUID(uuidString: "00000000-0000-4000-8000-000000000410")!,
                ingredientName: "Lemons",
                ingredientRawText: "2-3 lemons, juiced",
                ingredientQuantity: 3,
                ingredientUnit: "count",
                ingredientPreparation: "juiced",
                ingredientPreferenceNote: "User kept the full recipe range",
                desiredServings: 5,
                storeStrategy: .oneStore,
                fulfillmentMode: .pickup,
                selectedStoreID: UUID(uuidString: "00000000-0000-4000-8000-000000000440")!,
                zipCode: "50004",
                pickupDay: "Monday",
                pickupTime: "8:00 AM - 9:00 AM",
                shoppingItemID: UUID(uuidString: "00000000-0000-4000-8000-000000000420")!,
                requestedQuantity: "3 lemons for 5 servings",
                purchaseQuantity: 3,
                productID: UUID(uuidString: "00000000-0000-4000-8000-000000000430")!,
                productTitle: "V4 Fresh Lemons",
                productStoreID: "walmart-v4-500",
                productPackageQuantity: 1,
                productPackageUnit: "count",
                shoppingStatus: .savedToWishlist,
                guidedIndex: 1,
                savedListID: UUID(uuidString: "00000000-0000-4000-8000-000000000450")!,
                manifestID: UUID(uuidString: "00000000-0000-4000-8000-000000000460")!,
                manifestLineID: UUID(uuidString: "00000000-0000-4000-8000-000000000470")!,
                manifestStoreName: "V4 Wishlist Store",
                manifestProgress: .paused
            )
        ]
    }

    private func makeFixedLegacyFixture(
        _ expectation: FixedLegacyFixtureExpectation
    ) throws -> (fileURL: URL, originalData: Data) {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LegacyState/legacy-v\(expectation.version).json")
        let originalData = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: originalData) as? [String: Any]
        )
        XCTAssertEqual(root["schemaVersion"] as? Int, expectation.version)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartCart-FixedLegacy-v\(expectation.version)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("state.json")
        try originalData.write(to: fileURL, options: [.atomic])
        return (fileURL, originalData)
    }

    private func assertDurableFields(
        in state: SmartCartPersistedState,
        match expected: FixedLegacyFixtureExpectation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(state.schemaVersion, SmartCartPersistedState.currentSchemaVersion, file: file, line: line)
        XCTAssertEqual(state.recipes.count, 1, file: file, line: line)
        XCTAssertEqual(state.activeRecipe.id, expected.recipeID, file: file, line: line)
        XCTAssertEqual(state.recipes.first?.id, expected.recipeID, file: file, line: line)
        XCTAssertEqual(state.activeRecipe.title, expected.recipeTitle, file: file, line: line)
        XCTAssertEqual(state.activeRecipe.source, expected.recipeSource, file: file, line: line)
        XCTAssertEqual(state.activeRecipe.sourceDetail, "Fixed shipped-state schema v\(expected.version)", file: file, line: line)

        let ingredient = try XCTUnwrap(state.activeRecipe.ingredients.first, file: file, line: line)
        XCTAssertEqual(ingredient.id, expected.ingredientID, file: file, line: line)
        XCTAssertEqual(ingredient.name, expected.ingredientName, file: file, line: line)
        XCTAssertEqual(ingredient.rawText, expected.ingredientRawText, file: file, line: line)
        XCTAssertEqual(ingredient.quantity, expected.ingredientQuantity, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(ingredient.unit, expected.ingredientUnit, file: file, line: line)
        XCTAssertEqual(ingredient.preparation, expected.ingredientPreparation, file: file, line: line)
        XCTAssertEqual(ingredient.preferenceNote, expected.ingredientPreferenceNote, file: file, line: line)
        XCTAssertEqual(ingredient.includeInList, true, file: file, line: line)
        XCTAssertEqual(ingredient.pantryState, .needToBuy, file: file, line: line)

        XCTAssertEqual(state.desiredServings, expected.desiredServings, file: file, line: line)
        XCTAssertEqual(state.storeStrategy, expected.storeStrategy, file: file, line: line)
        XCTAssertEqual(state.fulfillmentMode, expected.fulfillmentMode, file: file, line: line)
        XCTAssertEqual(state.selectedStoreIDs, Set([expected.selectedStoreID]), file: file, line: line)
        XCTAssertEqual(state.zipCode, expected.zipCode, file: file, line: line)
        XCTAssertEqual(state.pickupDay, expected.pickupDay, file: file, line: line)
        XCTAssertEqual(state.pickupTime, expected.pickupTime, file: file, line: line)

        XCTAssertEqual(state.shoppingItems.count, 1, file: file, line: line)
        let shoppingItem = try XCTUnwrap(state.shoppingItems.first, file: file, line: line)
        XCTAssertEqual(shoppingItem.id, expected.shoppingItemID, file: file, line: line)
        XCTAssertEqual(shoppingItem.ingredient.id, expected.ingredientID, file: file, line: line)
        XCTAssertEqual(shoppingItem.requestedQuantity, expected.requestedQuantity, file: file, line: line)
        XCTAssertEqual(shoppingItem.purchaseQuantity, expected.purchaseQuantity, file: file, line: line)
        XCTAssertEqual(shoppingItem.storeID, expected.selectedStoreID, file: file, line: line)
        XCTAssertEqual(shoppingItem.status, expected.shoppingStatus, file: file, line: line)
        XCTAssertEqual(shoppingItem.product.id, expected.productID, file: file, line: line)
        XCTAssertEqual(shoppingItem.product.title, expected.productTitle, file: file, line: line)
        XCTAssertEqual(shoppingItem.product.storeID, expected.productStoreID, file: file, line: line)
        XCTAssertEqual(shoppingItem.product.packageQuantity, expected.productPackageQuantity, file: file, line: line)
        XCTAssertEqual(shoppingItem.product.packageUnit, expected.productPackageUnit, file: file, line: line)
        XCTAssertEqual(state.guidedIndex, expected.guidedIndex, file: file, line: line)

        XCTAssertEqual(state.savedLists.count, 1, file: file, line: line)
        let savedList = try XCTUnwrap(state.savedLists.first, file: file, line: line)
        XCTAssertEqual(savedList.id, expected.savedListID, file: file, line: line)
        XCTAssertEqual(savedList.manifest.id, expected.manifestID, file: file, line: line)
        XCTAssertEqual(savedList.manifest.recipeID, expected.recipeID, file: file, line: line)
        XCTAssertEqual(savedList.manifest.recipeTitle, expected.recipeTitle, file: file, line: line)
        XCTAssertEqual(savedList.manifest.retailerID, "walmart", file: file, line: line)
        XCTAssertEqual(savedList.manifest.storeID, expected.productStoreID, file: file, line: line)
        XCTAssertEqual(savedList.manifest.storeName, expected.manifestStoreName, file: file, line: line)
        XCTAssertEqual(savedList.manifest.desiredServings, expected.desiredServings, file: file, line: line)
        XCTAssertEqual(savedList.manifest.fulfillmentMode, expected.fulfillmentMode, file: file, line: line)
        XCTAssertEqual(savedList.manifest.handoffProgress, expected.manifestProgress, file: file, line: line)
        let manifestLine = try XCTUnwrap(savedList.manifest.items.first, file: file, line: line)
        XCTAssertEqual(manifestLine.id, expected.manifestLineID, file: file, line: line)
        XCTAssertEqual(manifestLine.ingredientID, expected.ingredientID, file: file, line: line)
        XCTAssertEqual(manifestLine.product.id, expected.productID, file: file, line: line)
        XCTAssertEqual(manifestLine.status, expected.shoppingStatus, file: file, line: line)

        let activeSessionID = try XCTUnwrap(
            state.activeShoppingSessionID,
            file: file,
            line: line
        )
        let recoveredSession = try XCTUnwrap(
            state.shoppingSessions.first { $0.id == activeSessionID },
            file: file,
            line: line
        )
        XCTAssertEqual(recoveredSession.manifestID, expected.manifestID, file: file, line: line)
        XCTAssertEqual(recoveredSession.items, state.shoppingItems, file: file, line: line)
        XCTAssertEqual(
            recoveredSession.reconciliationIdentity,
            savedList.manifest.logicalTripID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            state.shoppingScope,
            .singleRecipe(expected.recipeID),
            file: file,
            line: line
        )

        try assertSchemaSpecificFields(in: state, version: expected.version, file: file, line: line)
    }

    private func assertSchemaSpecificFields(
        in state: SmartCartPersistedState,
        version: Int,
        file: StaticString,
        line: UInt
    ) throws {
        if version == 0 {
            XCTAssertEqual(state.preferences.organicPolicy, .whenAvailable, file: file, line: line)
            XCTAssertEqual(state.preferences.budgetPriority, .balanced, file: file, line: line)
            XCTAssertFalse(state.featureFlags.advancedToolsEnabled, file: file, line: line)
            XCTAssertNil(state.preferredDeliveryPartnerName, file: file, line: line)
        } else {
            XCTAssertEqual(state.preferences.organicPolicy, .only, file: file, line: line)
            XCTAssertEqual(state.preferences.budgetPriority, .qualityFirst, file: file, line: line)
            XCTAssertEqual(state.preferences.dietaryRestrictions, [.glutenFree], file: file, line: line)
            XCTAssertEqual(state.preferences.storeBrandPreference, .prefer, file: file, line: line)
            XCTAssertEqual(state.preferences.preferredBrands, ["Fixed Legacy Brand v\(version)"], file: file, line: line)
            XCTAssertTrue(state.featureFlags.advancedToolsEnabled, file: file, line: line)
            XCTAssertEqual(state.preferredDeliveryPartnerName, "Legacy Partner v\(version)", file: file, line: line)
        }

        if version < 2 {
            XCTAssertTrue(state.pantryInventory.isEmpty, file: file, line: line)
            XCTAssertTrue(state.preferredProductIDsByIngredient.isEmpty, file: file, line: line)
            XCTAssertTrue(state.analyticsEvents.isEmpty, file: file, line: line)
        } else {
            let pantry = try XCTUnwrap(state.pantryInventory.first, file: file, line: line)
            XCTAssertEqual(pantry.id, fixedUUID(version: version, suffix: 80), file: file, line: line)
            XCTAssertEqual(pantry.name, "V\(version) Pantry Reserve", file: file, line: line)
            XCTAssertEqual(pantry.preferredRetailerProductID, "legacy-pantry-v\(version)", file: file, line: line)
            XCTAssertEqual(state.preferredProductIDsByIngredient["fixture ingredient v\(version)"], "legacy-product-v\(version)", file: file, line: line)
            let event = try XCTUnwrap(state.analyticsEvents.first, file: file, line: line)
            XCTAssertEqual(event.id, fixedUUID(version: version, suffix: 90), file: file, line: line)
            XCTAssertEqual(event.properties["fixture"], "v\(version)", file: file, line: line)
        }

        if version == 2 {
            let pantry = try XCTUnwrap(state.pantryInventory.first, file: file, line: line)
            XCTAssertEqual(pantry.quantity, 2, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(pantry.unit, "bags", file: file, line: line)
            XCTAssertEqual(pantry.packageCount, 2, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(pantry.remainingAmount, 2, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(pantry.remainingUnit, "bags", file: file, line: line)
        }

        if version >= 3 {
            let ingredient = try XCTUnwrap(state.activeRecipe.ingredients.first, file: file, line: line)
            XCTAssertEqual(ingredient.sectionName, "Fixture section v\(version)", file: file, line: line)
            XCTAssertEqual(ingredient.brandNote, "Fixture brand note v\(version)", file: file, line: line)
            let evidence = try XCTUnwrap(ingredient.sourceEvidence, file: file, line: line)
            XCTAssertEqual(evidence.extractionStrategy, .visionOCR, file: file, line: line)
            XCTAssertEqual(evidence.parserConfidence, 0.88, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(ingredient.pantryDecision, .useAvailable, file: file, line: line)
            let pantry = try XCTUnwrap(state.pantryInventory.first, file: file, line: line)
            XCTAssertEqual(pantry.packageSize, Optional(version == 3 ? 8.0 : 1.0), file: file, line: line)
            XCTAssertEqual(pantry.packageUnit, version == 3 ? "oz" : "count", file: file, line: line)
            XCTAssertEqual(pantry.gtin14, version == 3 ? "00000000000333" : "00000000000444", file: file, line: line)
        }

        if version == 3 {
            let pantry = try XCTUnwrap(state.pantryInventory.first, file: file, line: line)
            XCTAssertEqual(pantry.packageCount, 2, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(pantry.remainingAmount, 16, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(pantry.remainingUnit, "oz", file: file, line: line)
        }

        if version == 4 {
            let ingredient = try XCTUnwrap(state.activeRecipe.ingredients.first, file: file, line: line)
            XCTAssertEqual(ingredient.quantityLowerBound, 2, file: file, line: line)
            let pantry = try XCTUnwrap(state.pantryInventory.first, file: file, line: line)
            XCTAssertEqual(pantry.packageCount, 4, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(pantry.remainingAmount, 3, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(pantry.remainingUnit, "count", file: file, line: line)
            let wishlist = try XCTUnwrap(state.walmartWishlistReference, file: file, line: line)
            XCTAssertEqual(wishlist.id, fixedUUID(version: 4, suffix: 95), file: file, line: line)
            XCTAssertEqual(wishlist.displayName, "V4 Family Wishlist", file: file, line: line)
            XCTAssertEqual(wishlist.sharedURL.absoluteString, "https://www.walmart.com/lists/shared/WL/fixed-v4", file: file, line: line)
        } else {
            XCTAssertNil(state.walmartWishlistReference, file: file, line: line)
        }
    }

    private func fixedUUID(version: Int, suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-000000000%1d%02d", version, suffix))!
    }
}

private struct FixedLegacyFixtureExpectation {
    var version: Int
    var recipeID: UUID
    var recipeTitle: String
    var recipeSource: RecipeSource
    var ingredientID: UUID
    var ingredientName: String
    var ingredientRawText: String
    var ingredientQuantity: Double
    var ingredientUnit: String
    var ingredientPreparation: String
    var ingredientPreferenceNote: String
    var desiredServings: Int
    var storeStrategy: StoreStrategy
    var fulfillmentMode: FulfillmentMode
    var selectedStoreID: UUID
    var zipCode: String
    var pickupDay: String
    var pickupTime: String
    var shoppingItemID: UUID
    var requestedQuantity: String
    var purchaseQuantity: Int
    var productID: UUID
    var productTitle: String
    var productStoreID: String
    var productPackageQuantity: Double
    var productPackageUnit: String
    var shoppingStatus: GuidedItemStatus
    var guidedIndex: Int
    var savedListID: UUID
    var manifestID: UUID
    var manifestLineID: UUID
    var manifestStoreName: String
    var manifestProgress: ManifestHandoffProgress
}
