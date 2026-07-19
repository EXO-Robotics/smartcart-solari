import Foundation

struct SmartCartPersistedState: Codable, Hashable {
    static let currentSchemaVersion = 6

    var schemaVersion: Int = currentSchemaVersion
    var recipes: [Recipe]
    var activeRecipe: Recipe
    var desiredServings: Int
    var preferences: ShoppingPreferences
    var featureFlags: AppFeatureFlags
    var storeStrategy: StoreStrategy
    var fulfillmentMode: FulfillmentMode
    var selectedStoreIDs: Set<UUID>
    var zipCode: String
    var pickupDay: String
    var pickupTime: String
    var shoppingItems: [ShoppingListItem]
    var guidedIndex: Int
    var savedLists: [SavedShoppingList]
    var preferredDeliveryPartnerName: String?
    var pantryInventory: [PantryInventoryItem]
    var preferredProductIDsByIngredient: [String: String]
    var analyticsEvents: [AnalyticsEvent]
    var walmartWishlistReference: WalmartWishlistReference? = nil
    var shoppingSessions: [ShoppingSession] = []
    var activeShoppingSessionID: UUID? = nil
    var shoppingScope: ShoppingScope? = nil
    var mealPrepDraft: MealPrepDraft? = nil
    var mealPrepPlan: MealPrepPlanSnapshot? = nil
}

struct LegacySmartCartPersistedStateV5: Codable, Hashable {
    var schemaVersion = 5
    var recipes: [Recipe]
    var activeRecipe: Recipe
    var desiredServings: Int
    var preferences: ShoppingPreferences
    var featureFlags: AppFeatureFlags
    var storeStrategy: StoreStrategy
    var fulfillmentMode: FulfillmentMode
    var selectedStoreIDs: Set<UUID>
    var zipCode: String
    var pickupDay: String
    var pickupTime: String
    var shoppingItems: [ShoppingListItem]
    var guidedIndex: Int
    var savedLists: [SavedShoppingList]
    var preferredDeliveryPartnerName: String?
    var pantryInventory: [PantryInventoryItem]
    var preferredProductIDsByIngredient: [String: String]
    var analyticsEvents: [AnalyticsEvent]
    var walmartWishlistReference: WalmartWishlistReference?
    var shoppingSessions: [ShoppingSession]
}

struct LegacySmartCartPersistedStateV4: Codable, Hashable {
    var schemaVersion = 4
    var recipes: [Recipe]
    var activeRecipe: Recipe
    var desiredServings: Int
    var preferences: ShoppingPreferences
    var featureFlags: AppFeatureFlags
    var storeStrategy: StoreStrategy
    var fulfillmentMode: FulfillmentMode
    var selectedStoreIDs: Set<UUID>
    var zipCode: String
    var pickupDay: String
    var pickupTime: String
    var shoppingItems: [ShoppingListItem]
    var guidedIndex: Int
    var savedLists: [SavedShoppingList]
    var preferredDeliveryPartnerName: String?
    var pantryInventory: [PantryInventoryItem]
    var preferredProductIDsByIngredient: [String: String]
    var analyticsEvents: [AnalyticsEvent]
    var walmartWishlistReference: WalmartWishlistReference?
}

struct LegacySmartCartPersistedStateV3: Codable, Hashable {
    var schemaVersion = 3
    var recipes: [Recipe]
    var activeRecipe: Recipe
    var desiredServings: Int
    var preferences: ShoppingPreferences
    var featureFlags: AppFeatureFlags
    var storeStrategy: StoreStrategy
    var fulfillmentMode: FulfillmentMode
    var selectedStoreIDs: Set<UUID>
    var zipCode: String
    var pickupDay: String
    var pickupTime: String
    var shoppingItems: [ShoppingListItem]
    var guidedIndex: Int
    var savedLists: [SavedShoppingList]
    var preferredDeliveryPartnerName: String?
    var pantryInventory: [PantryInventoryItem]
    var preferredProductIDsByIngredient: [String: String]
    var analyticsEvents: [AnalyticsEvent]
}

struct LegacySmartCartPersistedStateV2: Codable, Hashable {
    var schemaVersion = 2
    var recipes: [Recipe]
    var activeRecipe: Recipe
    var desiredServings: Int
    var preferences: ShoppingPreferences
    var featureFlags: AppFeatureFlags
    var storeStrategy: StoreStrategy
    var fulfillmentMode: FulfillmentMode
    var selectedStoreIDs: Set<UUID>
    var zipCode: String
    var pickupDay: String
    var pickupTime: String
    var shoppingItems: [ShoppingListItem]
    var guidedIndex: Int
    var savedLists: [SavedShoppingList]
    var preferredDeliveryPartnerName: String?
    var pantryInventory: [PantryInventoryItem]
    var preferredProductIDsByIngredient: [String: String]
    var analyticsEvents: [AnalyticsEvent]
}

struct LegacySmartCartPersistedStateV1: Codable, Hashable {
    var schemaVersion = 1
    var recipes: [Recipe]
    var activeRecipe: Recipe
    var desiredServings: Int
    var preferences: ShoppingPreferences
    var featureFlags: AppFeatureFlags
    var storeStrategy: StoreStrategy
    var fulfillmentMode: FulfillmentMode
    var selectedStoreIDs: Set<UUID>
    var zipCode: String
    var pickupDay: String
    var pickupTime: String
    var shoppingItems: [ShoppingListItem]
    var guidedIndex: Int
    var savedLists: [SavedShoppingList]
    var preferredDeliveryPartnerName: String?
}

struct LegacySmartCartPersistedStateV0: Codable, Hashable {
    var schemaVersion = 0
    var recipes: [Recipe]
    var activeRecipe: Recipe
    var desiredServings: Int
    var storeStrategy: StoreStrategy
    var fulfillmentMode: FulfillmentMode
    var selectedStoreIDs: Set<UUID>
    var zipCode: String
    var pickupDay: String
    var pickupTime: String
    var shoppingItems: [ShoppingListItem]
    var guidedIndex: Int
    var savedLists: [SavedShoppingList]
}

protocol SmartCartStateStoring {
    var lastLoadWarning: SmartCartStateStoreWarning? { get }

    func load() throws -> SmartCartPersistedState?
    func save(_ state: SmartCartPersistedState) throws
}

extension SmartCartStateStoring {
    var lastLoadWarning: SmartCartStateStoreWarning? { nil }
}

enum SmartCartStateStoreWarning: LocalizedError, Equatable {
    case migrationRewriteFailed(
        sourceSchemaVersion: Int,
        targetSchemaVersion: Int,
        preservedStateURL: URL?
    )

    var errorDescription: String? {
        switch self {
        case .migrationRewriteFailed(let source, let target, let preservedStateURL):
            if preservedStateURL != nil {
                return "SmartCart loaded your data, but could not finish updating storage from schema \(source) to \(target). Your previous data was preserved and the update can be retried."
            }
            return "SmartCart loaded your data, but could not finish updating storage from schema \(source) to \(target). The update can be retried after storage becomes available."
        }
    }
}

enum SmartCartStateStoreError: LocalizedError, Equatable {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "SmartCart state schema \(version) is newer than this app supports."
        }
    }
}

final class JSONSmartCartStateStore: SmartCartStateStoring {
    typealias AtomicWriter = (Data, URL) throws -> Void
    typealias DataReader = (URL) throws -> Data

    let fileURL: URL
    private(set) var lastLoadWarning: SmartCartStateStoreWarning?

    private let atomicWriter: AtomicWriter
    private let dataReader: DataReader

    init(
        fileURL: URL,
        dataReader: @escaping DataReader = { try Data(contentsOf: $0) },
        atomicWriter: @escaping AtomicWriter = { data, destination in
            try data.write(to: destination, options: [.atomic])
        }
    ) {
        self.fileURL = fileURL
        self.dataReader = dataReader
        self.atomicWriter = atomicWriter
    }

    convenience init() {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.init(
            fileURL: baseURL
                .appendingPathComponent("SmartCart", isDirectory: true)
                .appendingPathComponent("state.json")
        )
    }

    func load() throws -> SmartCartPersistedState? {
        lastLoadWarning = nil
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // Read errors are not evidence of corruption. Propagate them without
        // moving or replacing the source file; only successfully read bytes
        // that fail decoding may enter quarantine recovery.
        let data = try dataReader(fileURL)
        do {
            let version = try JSONDecoder().decode(StateVersionProbe.self, from: data).schemaVersion ?? 0
            switch version {
            case SmartCartPersistedState.currentSchemaVersion:
                return try decoder().decode(SmartCartPersistedState.self, from: data)
            case 5:
                let legacy = try decoder().decode(LegacySmartCartPersistedStateV5.self, from: data)
                return finishMigration(migrate(legacy), originalData: data, sourceSchemaVersion: version)
            case 4:
                let legacy = try decoder().decode(LegacySmartCartPersistedStateV4.self, from: data)
                return finishMigration(migrate(legacy), originalData: data, sourceSchemaVersion: version)
            case 3:
                let legacy = try decoder().decode(LegacySmartCartPersistedStateV3.self, from: data)
                return finishMigration(migrate(legacy), originalData: data, sourceSchemaVersion: version)
            case 2:
                let legacy = try decoder().decode(LegacySmartCartPersistedStateV2.self, from: data)
                return finishMigration(migrate(legacy), originalData: data, sourceSchemaVersion: version)
            case 1:
                let legacy = try decoder().decode(LegacySmartCartPersistedStateV1.self, from: data)
                return finishMigration(migrate(legacy), originalData: data, sourceSchemaVersion: version)
            case 0:
                let legacy = try decoder().decode(LegacySmartCartPersistedStateV0.self, from: data)
                return finishMigration(migrate(legacy), originalData: data, sourceSchemaVersion: version)
            default:
                throw SmartCartStateStoreError.unsupportedSchema(version)
            }
        } catch let error as SmartCartStateStoreError {
            // A newer app may have written this state. Keep the file intact so
            // an older build can never quarantine or overwrite valid data.
            throw error
        } catch {
            try? quarantineUnreadableState()
            return nil
        }
    }

    private func migrate(
        _ legacy: LegacySmartCartPersistedStateV5
    ) -> SmartCartPersistedState {
        let recoveredTrip = recoverLegacyTripState(
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            shoppingItems: legacy.shoppingItems,
            savedLists: legacy.savedLists,
            shoppingSessions: legacy.shoppingSessions
        )
        return SmartCartPersistedState(
            recipes: legacy.recipes,
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            preferences: legacy.preferences,
            featureFlags: legacy.featureFlags,
            storeStrategy: legacy.storeStrategy,
            fulfillmentMode: legacy.fulfillmentMode,
            selectedStoreIDs: legacy.selectedStoreIDs,
            zipCode: legacy.zipCode,
            pickupDay: legacy.pickupDay,
            pickupTime: legacy.pickupTime,
            shoppingItems: legacy.shoppingItems,
            guidedIndex: legacy.guidedIndex,
            savedLists: recoveredTrip.savedLists,
            preferredDeliveryPartnerName: legacy.preferredDeliveryPartnerName,
            pantryInventory: legacy.pantryInventory,
            preferredProductIDsByIngredient: legacy.preferredProductIDsByIngredient,
            analyticsEvents: legacy.analyticsEvents,
            walmartWishlistReference: legacy.walmartWishlistReference,
            shoppingSessions: recoveredTrip.shoppingSessions,
            activeShoppingSessionID: recoveredTrip.activeShoppingSessionID,
            shoppingScope: recoveredTrip.shoppingScope
        )
    }

    private func recoverLegacyTripState(
        activeRecipe: Recipe,
        desiredServings: Int,
        shoppingItems: [ShoppingListItem],
        savedLists: [SavedShoppingList],
        shoppingSessions: [ShoppingSession] = []
    ) -> (
        savedLists: [SavedShoppingList],
        shoppingSessions: [ShoppingSession],
        activeShoppingSessionID: UUID?,
        shoppingScope: ShoppingScope?
    ) {
        let scope: ShoppingScope? = shoppingItems.isEmpty
            ? nil
            : .singleRecipe(activeRecipe.id)
        var migratedSessions = shoppingSessions
        let matchingSessionIndices = migratedSessions.indices.filter { index in
            let session = migratedSessions[index]
            let sessionScope = session.shoppingScope ?? .singleRecipe(session.recipeID)
            return sessionScope == scope &&
                legacyShoppingItemsMatch(session.items, shoppingItems)
        }
        var activeSessionID = matchingSessionIndices
            .filter { !migratedSessions[$0].isCommitted }
            .max(by: {
                migratedSessions[$0].startedAt < migratedSessions[$1].startedAt
            })
            .map { migratedSessions[$0].id }
            ?? matchingSessionIndices.max(by: {
                migratedSessions[$0].startedAt < migratedSessions[$1].startedAt
            }).map { migratedSessions[$0].id }
        if activeSessionID == nil,
           let scope,
           let manifest = savedLists.map(\.manifest).first(where: { manifest in
               let manifestScope = manifest.shoppingScope ?? .singleRecipe(manifest.recipeID)
               return manifestScope == scope &&
                   manifest.handoffProgress != .notStarted &&
                   legacyManifest(manifest, matches: shoppingItems)
           }) {
            let recoveredSession = ShoppingSession(
                logicalTripID: manifest.logicalTripID ?? manifest.id,
                recipeID: activeRecipe.id,
                recipeTitle: manifest.recipeTitle,
                manifestID: manifest.id,
                storeID: manifest.storeID,
                retailerID: manifest.retailerID,
                desiredServings: desiredServings,
                fulfillmentMode: manifest.fulfillmentMode,
                shoppingScope: scope,
                startedAt: manifest.updatedAt,
                items: shoppingItems
            )
            migratedSessions.insert(recoveredSession, at: 0)
            activeSessionID = recoveredSession.id
        }
        var migratedLists = savedLists
        normalizeLegacyTripIdentities(
            sessions: &migratedSessions,
            savedLists: &migratedLists
        )
        return (
            savedLists: migratedLists,
            shoppingSessions: migratedSessions,
            activeShoppingSessionID: activeSessionID,
            shoppingScope: scope
        )
    }

    /// Schema-v5 could contain duplicate representations of one trip whose
    /// line UUIDs differed. Partition by durable semantics and commit timing:
    /// overlapping records share an identity; a later trip begun after the
    /// earlier pantry commit receives a new identity.
    private func normalizeLegacyTripIdentities(
        sessions: inout [ShoppingSession],
        savedLists: inout [SavedShoppingList]
    ) {
        for index in savedLists.indices where savedLists[index].manifest.logicalTripID == nil {
            savedLists[index].manifest.logicalTripID = savedLists[index].manifest.id
        }

        let orderedIndices = sessions.indices.sorted {
            sessions[$0].startedAt < sessions[$1].startedAt
        }
        var clusters: [[Int]] = []

        for index in orderedIndices {
            let matchingClusterIndex = clusters.indices.reversed().first { clusterIndex in
                guard let representative = clusters[clusterIndex].first,
                      legacySessionsMatchTripSemantics(
                        sessions[representative],
                        sessions[index]
                      ) else { return false }
                let clusterManifestIDs = Set(
                    clusters[clusterIndex].compactMap { sessions[$0].manifestID }
                )
                if let manifestID = sessions[index].manifestID,
                   !clusterManifestIDs.isEmpty,
                   !clusterManifestIDs.contains(manifestID) {
                    return false
                }
                let committedThrough = clusters[clusterIndex]
                    .compactMap { sessions[$0].reconciliation?.committedAt }
                    .max()
                guard let committedThrough else {
                    // Without a recorded commit boundary, multiple legacy
                    // representations cannot be proven to be repeat trips.
                    return true
                }
                return sessions[index].startedAt <= committedThrough
            }

            let manifestIdentity = sessions[index].manifestID.flatMap { manifestID in
                savedLists.first { $0.manifest.id == manifestID }?.manifest.logicalTripID
            }
            let hasSemanticPrior = clusters.contains { cluster in
                guard let representative = cluster.first else { return false }
                return legacySessionsMatchTripSemantics(
                    sessions[representative],
                    sessions[index]
                )
            }
            let semanticPriorIdentities = Set(
                clusters
                    .filter { cluster in
                        guard let representative = cluster.first else { return false }
                        return legacySessionsMatchTripSemantics(
                            sessions[representative],
                            sessions[index]
                        )
                    }
                    .compactMap { cluster in
                        cluster.first.flatMap { sessions[$0].reconciliationIdentity }
                    }
            )
            let currentIdentity = sessions[index].reconciliationIdentity
            let reusableCurrentIdentity = currentIdentity.flatMap {
                semanticPriorIdentities.contains($0) ? nil : $0
            }
            let identity = matchingClusterIndex.flatMap { clusterIndex in
                clusters[clusterIndex].first.flatMap {
                    sessions[$0].reconciliationIdentity
                }
            } ?? reusableCurrentIdentity
                ?? (hasSemanticPrior ? nil : manifestIdentity)
                ?? sessions[index].id
            sessions[index].logicalTripID = identity
            sessions[index].tripID = identity
            if sessions[index].reconciliation != nil {
                sessions[index].reconciliation?.logicalTripID = identity
            }
            if let matchingClusterIndex {
                clusters[matchingClusterIndex].append(index)
            } else {
                clusters.append([index])
            }
        }

        for cluster in clusters {
            let manifestIDs = Set(cluster.compactMap { sessions[$0].manifestID })
            guard manifestIDs.count == 1, let manifestID = manifestIDs.first else { continue }
            for index in cluster where sessions[index].manifestID == nil {
                sessions[index].manifestID = manifestID
            }
        }

        for listIndex in savedLists.indices {
            let manifestID = savedLists[listIndex].manifest.id
            if let latest = sessions
                .filter({ $0.manifestID == manifestID })
                .max(by: { $0.startedAt < $1.startedAt }),
               let identity = latest.reconciliationIdentity {
                savedLists[listIndex].manifest.logicalTripID = identity
            }
        }
    }

    private func legacySessionsMatchTripSemantics(
        _ lhs: ShoppingSession,
        _ rhs: ShoppingSession
    ) -> Bool {
        lhs.storeID == rhs.storeID &&
            (lhs.retailerID ?? lhs.items.first?.product.retailerID) ==
                (rhs.retailerID ?? rhs.items.first?.product.retailerID) &&
            (lhs.shoppingScope ?? .singleRecipe(lhs.recipeID)) ==
                (rhs.shoppingScope ?? .singleRecipe(rhs.recipeID)) &&
            legacyShoppingItemsMatch(lhs.items, rhs.items)
    }

    private func migrate(
        _ legacy: LegacySmartCartPersistedStateV4
    ) -> SmartCartPersistedState {
        let recoveredTrip = recoverLegacyTripState(
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            shoppingItems: legacy.shoppingItems,
            savedLists: legacy.savedLists
        )
        return SmartCartPersistedState(
            recipes: legacy.recipes,
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            preferences: legacy.preferences,
            featureFlags: legacy.featureFlags,
            storeStrategy: legacy.storeStrategy,
            fulfillmentMode: legacy.fulfillmentMode,
            selectedStoreIDs: legacy.selectedStoreIDs,
            zipCode: legacy.zipCode,
            pickupDay: legacy.pickupDay,
            pickupTime: legacy.pickupTime,
            shoppingItems: legacy.shoppingItems,
            guidedIndex: legacy.guidedIndex,
            savedLists: recoveredTrip.savedLists,
            preferredDeliveryPartnerName: legacy.preferredDeliveryPartnerName,
            pantryInventory: legacy.pantryInventory,
            preferredProductIDsByIngredient: legacy.preferredProductIDsByIngredient,
            analyticsEvents: legacy.analyticsEvents,
            walmartWishlistReference: legacy.walmartWishlistReference,
            shoppingSessions: recoveredTrip.shoppingSessions,
            activeShoppingSessionID: recoveredTrip.activeShoppingSessionID,
            shoppingScope: recoveredTrip.shoppingScope
        )
    }

    private func migrate(
        _ legacy: LegacySmartCartPersistedStateV3
    ) -> SmartCartPersistedState {
        let recoveredTrip = recoverLegacyTripState(
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            shoppingItems: legacy.shoppingItems,
            savedLists: legacy.savedLists
        )
        return SmartCartPersistedState(
            recipes: legacy.recipes,
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            preferences: legacy.preferences,
            featureFlags: legacy.featureFlags,
            storeStrategy: legacy.storeStrategy,
            fulfillmentMode: legacy.fulfillmentMode,
            selectedStoreIDs: legacy.selectedStoreIDs,
            zipCode: legacy.zipCode,
            pickupDay: legacy.pickupDay,
            pickupTime: legacy.pickupTime,
            shoppingItems: legacy.shoppingItems,
            guidedIndex: legacy.guidedIndex,
            savedLists: recoveredTrip.savedLists,
            preferredDeliveryPartnerName: legacy.preferredDeliveryPartnerName,
            pantryInventory: legacy.pantryInventory,
            preferredProductIDsByIngredient: legacy.preferredProductIDsByIngredient,
            analyticsEvents: legacy.analyticsEvents,
            walmartWishlistReference: nil,
            shoppingSessions: recoveredTrip.shoppingSessions,
            activeShoppingSessionID: recoveredTrip.activeShoppingSessionID,
            shoppingScope: recoveredTrip.shoppingScope
        )
    }

    func save(_ state: SmartCartPersistedState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder().encode(state)
        try atomicWriter(data, fileURL)
        lastLoadWarning = nil
    }

    private func finishMigration(
        _ migrated: SmartCartPersistedState,
        originalData: Data,
        sourceSchemaVersion: Int
    ) -> SmartCartPersistedState {
        do {
            try save(migrated)
        } catch {
            let preservedStateURL = preserveLegacyState(
                originalData,
                sourceSchemaVersion: sourceSchemaVersion
            )
            lastLoadWarning = .migrationRewriteFailed(
                sourceSchemaVersion: sourceSchemaVersion,
                targetSchemaVersion: SmartCartPersistedState.currentSchemaVersion,
                preservedStateURL: preservedStateURL
            )
        }
        return migrated
    }

    private func legacyManifest(
        _ manifest: ShoppingManifest,
        matches shoppingItems: [ShoppingListItem]
    ) -> Bool {
        guard manifest.items.count == shoppingItems.count,
              shoppingItems.allSatisfy({ $0.product.retailerID == manifest.retailerID }) else {
            return false
        }

        let productStoreIDs = Set(shoppingItems.compactMap(\.product.storeID))
        if !productStoreIDs.isEmpty, productStoreIDs != Set([manifest.storeID]) {
            return false
        }

        let manifestSignatures = manifest.items.map {
            legacyItemSignature(
                ingredientName: $0.ingredientName,
                requestedQuantity: $0.requestedQuantity,
                purchaseQuantity: $0.purchaseQuantity,
                product: $0.product
            )
        }
        let shoppingSignatures = shoppingItems.map {
            legacyItemSignature(
                ingredientName: $0.ingredient.name,
                requestedQuantity: $0.requestedQuantity,
                purchaseQuantity: $0.purchaseQuantity,
                product: $0.product
            )
        }
        let manifestByIngredient = Dictionary(grouping: manifest.items, by: \.ingredientID)
            .mapValues { items in
                items.map {
                    legacyItemSignature(
                        ingredientName: $0.ingredientName,
                        requestedQuantity: $0.requestedQuantity,
                        purchaseQuantity: $0.purchaseQuantity,
                        product: $0.product
                    )
                }.sorted()
            }
        let shoppingByIngredient = Dictionary(grouping: shoppingItems, by: \.ingredient.id)
            .mapValues { items in
                items.map {
                    legacyItemSignature(
                        ingredientName: $0.ingredient.name,
                        requestedQuantity: $0.requestedQuantity,
                        purchaseQuantity: $0.purchaseQuantity,
                        product: $0.product
                    )
                }.sorted()
            }
        if Set(manifestByIngredient.keys) == Set(shoppingByIngredient.keys) {
            return manifestByIngredient == shoppingByIngredient
        }
        return manifestSignatures == shoppingSignatures ||
            manifestSignatures.sorted() == shoppingSignatures.sorted()
    }

    private func legacyItemSignature(
        ingredientName: String,
        requestedQuantity: String,
        purchaseQuantity: Int,
        product: RetailerProductRecord
    ) -> String {
        let productIdentity = product.retailerProductID.isEmpty
            ? product.exactURL.absoluteString
            : product.retailerProductID
        return [
            normalizedLegacyIdentity(ingredientName),
            normalizedLegacyIdentity(requestedQuantity),
            String(purchaseQuantity),
            normalizedLegacyIdentity(product.retailerID),
            normalizedLegacyIdentity(productIdentity),
            product.packageQuantity.map { String($0.bitPattern) } ?? "",
            normalizedLegacyIdentity(product.packageUnit ?? "")
        ].joined(separator: "|")
    }

    private func legacyShoppingItemsMatch(
        _ lhs: [ShoppingListItem],
        _ rhs: [ShoppingListItem]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let lhsByID = Dictionary(grouping: lhs, by: \.id).mapValues {
            $0.map {
                legacyItemSignature(
                    ingredientName: $0.ingredient.name,
                    requestedQuantity: $0.requestedQuantity,
                    purchaseQuantity: $0.purchaseQuantity,
                    product: $0.product
                )
            }.sorted()
        }
        let rhsByID = Dictionary(grouping: rhs, by: \.id).mapValues {
            $0.map {
                legacyItemSignature(
                    ingredientName: $0.ingredient.name,
                    requestedQuantity: $0.requestedQuantity,
                    purchaseQuantity: $0.purchaseQuantity,
                    product: $0.product
                )
            }.sorted()
        }
        if Set(lhsByID.keys) == Set(rhsByID.keys) {
            return lhsByID == rhsByID
        }
        let lhsSignatures = lhsByID.values.flatMap { $0 }.sorted()
        let rhsSignatures = rhsByID.values.flatMap { $0 }.sorted()
        return lhsSignatures == rhsSignatures
    }

    private func normalizedLegacyIdentity(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func preserveLegacyState(
        _ originalData: Data,
        sourceSchemaVersion: Int
    ) -> URL? {
        if let currentData = try? Data(contentsOf: fileURL), currentData == originalData {
            return fileURL
        }

        do {
            try originalData.write(to: fileURL, options: [.atomic])
            return fileURL
        } catch {
            let recoveryURL = fileURL
                .deletingPathExtension()
                .appendingPathExtension("migration-recovery-v\(sourceSchemaVersion).json")
            do {
                try originalData.write(to: recoveryURL, options: [.atomic])
                return recoveryURL
            } catch {
                return nil
            }
        }
    }

    private func migrate(
        _ legacy: LegacySmartCartPersistedStateV2
    ) -> SmartCartPersistedState {
        let normalizedPantry = legacy.pantryInventory.map { item -> PantryInventoryItem in
            var item = item
            if item.name.range(of: #"^Scanned item \d{1,8}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                item.name = "Unknown Product"
                item.brand = ""
                item.requiresUserNaming = true
            }
            return item
        }
        let recoveredTrip = recoverLegacyTripState(
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            shoppingItems: legacy.shoppingItems,
            savedLists: legacy.savedLists
        )
        return SmartCartPersistedState(
            recipes: legacy.recipes,
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            preferences: legacy.preferences,
            featureFlags: legacy.featureFlags,
            storeStrategy: legacy.storeStrategy,
            fulfillmentMode: legacy.fulfillmentMode,
            selectedStoreIDs: legacy.selectedStoreIDs,
            zipCode: legacy.zipCode,
            pickupDay: legacy.pickupDay,
            pickupTime: legacy.pickupTime,
            shoppingItems: legacy.shoppingItems,
            guidedIndex: legacy.guidedIndex,
            savedLists: recoveredTrip.savedLists,
            preferredDeliveryPartnerName: legacy.preferredDeliveryPartnerName,
            pantryInventory: normalizedPantry,
            preferredProductIDsByIngredient: legacy.preferredProductIDsByIngredient,
            analyticsEvents: legacy.analyticsEvents,
            walmartWishlistReference: nil,
            shoppingSessions: recoveredTrip.shoppingSessions,
            activeShoppingSessionID: recoveredTrip.activeShoppingSessionID,
            shoppingScope: recoveredTrip.shoppingScope
        )
    }

    private func migrate(
        _ legacy: LegacySmartCartPersistedStateV0
    ) -> SmartCartPersistedState {
        let recoveredTrip = recoverLegacyTripState(
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            shoppingItems: legacy.shoppingItems,
            savedLists: legacy.savedLists
        )
        return SmartCartPersistedState(
            recipes: legacy.recipes,
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            preferences: ShoppingPreferences(),
            featureFlags: AppFeatureFlags(),
            storeStrategy: legacy.storeStrategy,
            fulfillmentMode: legacy.fulfillmentMode,
            selectedStoreIDs: legacy.selectedStoreIDs,
            zipCode: legacy.zipCode,
            pickupDay: legacy.pickupDay,
            pickupTime: legacy.pickupTime,
            shoppingItems: legacy.shoppingItems,
            guidedIndex: legacy.guidedIndex,
            savedLists: recoveredTrip.savedLists,
            preferredDeliveryPartnerName: nil,
            pantryInventory: [],
            preferredProductIDsByIngredient: [:],
            analyticsEvents: [],
            walmartWishlistReference: nil,
            shoppingSessions: recoveredTrip.shoppingSessions,
            activeShoppingSessionID: recoveredTrip.activeShoppingSessionID,
            shoppingScope: recoveredTrip.shoppingScope
        )
    }

    private func migrate(
        _ legacy: LegacySmartCartPersistedStateV1
    ) -> SmartCartPersistedState {
        let recoveredTrip = recoverLegacyTripState(
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            shoppingItems: legacy.shoppingItems,
            savedLists: legacy.savedLists
        )
        return SmartCartPersistedState(
            recipes: legacy.recipes,
            activeRecipe: legacy.activeRecipe,
            desiredServings: legacy.desiredServings,
            preferences: legacy.preferences,
            featureFlags: legacy.featureFlags,
            storeStrategy: legacy.storeStrategy,
            fulfillmentMode: legacy.fulfillmentMode,
            selectedStoreIDs: legacy.selectedStoreIDs,
            zipCode: legacy.zipCode,
            pickupDay: legacy.pickupDay,
            pickupTime: legacy.pickupTime,
            shoppingItems: legacy.shoppingItems,
            guidedIndex: legacy.guidedIndex,
            savedLists: recoveredTrip.savedLists,
            preferredDeliveryPartnerName: legacy.preferredDeliveryPartnerName,
            pantryInventory: [],
            preferredProductIDsByIngredient: [:],
            analyticsEvents: [],
            walmartWishlistReference: nil,
            shoppingSessions: recoveredTrip.shoppingSessions,
            activeShoppingSessionID: recoveredTrip.activeShoppingSessionID,
            shoppingScope: recoveredTrip.shoppingScope
        )
    }

    private func quarantineUnreadableState() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let backupURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct StateVersionProbe: Decodable {
    var schemaVersion: Int?
}

final class InMemorySmartCartStateStore: SmartCartStateStoring {
    var state: SmartCartPersistedState?

    init(state: SmartCartPersistedState? = nil) {
        self.state = state
    }

    func load() throws -> SmartCartPersistedState? {
        state
    }

    func save(_ state: SmartCartPersistedState) throws {
        self.state = state
    }
}
