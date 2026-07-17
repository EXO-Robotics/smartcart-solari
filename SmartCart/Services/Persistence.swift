import Foundation

struct SmartCartPersistedState: Codable, Hashable {
    static let currentSchemaVersion = 2

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
    func load() throws -> SmartCartPersistedState?
    func save(_ state: SmartCartPersistedState) throws
}

enum SmartCartStateStoreError: LocalizedError {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "SmartCart state schema \(version) is newer than this app supports."
        }
    }
}

final class JSONSmartCartStateStore: SmartCartStateStoring {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let version = try JSONDecoder().decode(StateVersionProbe.self, from: data).schemaVersion ?? 0
            switch version {
            case SmartCartPersistedState.currentSchemaVersion:
                return try decoder().decode(SmartCartPersistedState.self, from: data)
            case 1:
                let legacy = try decoder().decode(LegacySmartCartPersistedStateV1.self, from: data)
                let migrated = migrate(legacy)
                try save(migrated)
                return migrated
            case 0:
                let legacy = try decoder().decode(LegacySmartCartPersistedStateV0.self, from: data)
                let migrated = migrate(legacy)
                try save(migrated)
                return migrated
            default:
                throw SmartCartStateStoreError.unsupportedSchema(version)
            }
        } catch {
            try? quarantineUnreadableState()
            return nil
        }
    }

    func save(_ state: SmartCartPersistedState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder().encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func migrate(
        _ legacy: LegacySmartCartPersistedStateV0
    ) -> SmartCartPersistedState {
        SmartCartPersistedState(
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
            savedLists: legacy.savedLists,
            preferredDeliveryPartnerName: nil,
            pantryInventory: [],
            preferredProductIDsByIngredient: [:],
            analyticsEvents: []
        )
    }

    private func migrate(
        _ legacy: LegacySmartCartPersistedStateV1
    ) -> SmartCartPersistedState {
        SmartCartPersistedState(
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
            savedLists: legacy.savedLists,
            preferredDeliveryPartnerName: legacy.preferredDeliveryPartnerName,
            pantryInventory: [],
            preferredProductIDsByIngredient: [:],
            analyticsEvents: []
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
