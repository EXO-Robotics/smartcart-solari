import Foundation
import Observation

enum WeeklyMealsContentSource: String, Codable, Hashable, Sendable {
    case bundledFallback
    case cachedRemote
    case freshRemote
}

struct RemoteWeeklyMealsManifest: Codable, Hashable, Sendable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let currentCollectionID: String
    let currentCollectionURL: String
    let publishedAt: Date
    let minimumAppVersion: String
}

struct RemoteWeeklyMealCollectionDocument: Codable, Hashable, Sendable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let revision: Int
    let publishedAt: Date
    let collection: WeeklyMealCollection
    let recipes: [CuratedRecipeRecord]
}

struct CachedWeeklyMealsContent: Codable, Hashable, Sendable {
    let manifest: RemoteWeeklyMealsManifest
    let document: RemoteWeeklyMealCollectionDocument
    let validatedAt: Date
}

enum WeeklyMealsRemoteError: Error, Equatable, Sendable {
    case missingConfiguration
    case invalidConfiguration
    case insecureConfiguration
    case invalidResponse
    case unexpectedStatus(Int)
    case payloadTooLarge
    case invalidManifest
    case unsupportedAppVersion
    case unsafeCollectionURL
    case crossOriginRedirect
    case invalidCollection([WeeklyMealManifestIssue])
    case staleManifest
}

struct WeeklyMealsRemoteConfiguration: Hashable, Sendable {
    static let bundleKey = "SmartCartWeeklyMealsBaseURL"

    let baseURL: URL

    var manifestURL: URL {
        baseURL
            .appendingPathComponent("weekly-meals", isDirectory: true)
            .appendingPathComponent("manifest.json", isDirectory: false)
    }

    static func resolve(
        explicitURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> Result<Self, WeeklyMealsRemoteError> {
        if let explicitURL {
            return validate(explicitURL)
        }
        if let rawValue = environment["SMARTCART_WEEKLY_MEALS_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawValue.isEmpty {
            guard let url = URL(string: rawValue) else { return .failure(.invalidConfiguration) }
            return validate(url)
        }
        if let rawValue = bundleInfo[bundleKey] as? String {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, !value.contains("$("), let url = URL(string: value) {
                return validate(url)
            }
            if !value.isEmpty, !value.contains("$(") {
                return .failure(.invalidConfiguration)
            }
        }
        return .failure(.missingConfiguration)
    }

    private static func validate(_ url: URL) -> Result<Self, WeeklyMealsRemoteError> {
        guard url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else {
            return .failure(url.scheme?.lowercased() == "http" ? .insecureConfiguration : .invalidConfiguration)
        }
        return .success(Self(baseURL: url))
    }
}

struct WeeklyMealsHTTPResponse: Sendable {
    let data: Data
    let finalURL: URL
}

protocol WeeklyMealsHTTPClient: Sendable {
    func get(_ url: URL, maximumBytes: Int) async throws -> WeeklyMealsHTTPResponse
}

struct URLSessionWeeklyMealsHTTPClient: WeeklyMealsHTTPClient, @unchecked Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func get(_ url: URL, maximumBytes: Int) async throws -> WeeklyMealsHTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              let finalURL = httpResponse.url else {
            throw WeeklyMealsRemoteError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WeeklyMealsRemoteError.unexpectedStatus(httpResponse.statusCode)
        }
        if let expectedLength = httpResponse.value(forHTTPHeaderField: "Content-Length")
            .flatMap(Int.init), expectedLength > maximumBytes {
            throw WeeklyMealsRemoteError.payloadTooLarge
        }
        guard data.count <= maximumBytes else { throw WeeklyMealsRemoteError.payloadTooLarge }
        return WeeklyMealsHTTPResponse(data: data, finalURL: finalURL)
    }
}

protocol WeeklyMealsCacheStoring: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

struct FileWeeklyMealsCacheStore: WeeklyMealsCacheStoring, @unchecked Sendable {
    let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = baseURL
                .appendingPathComponent("WeeklyMeals", isDirectory: true)
                .appendingPathComponent("last-valid-v1.json", isDirectory: false)
        }
    }

    func load() throws -> Data? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let size = try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
        guard size?.intValue ?? 0 <= RemoteWeeklyMealsValidator.maximumCollectionBytes +
            RemoteWeeklyMealsValidator.maximumManifestBytes else {
            throw WeeklyMealsRemoteError.payloadTooLarge
        }
        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    func save(_ data: Data) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

enum RemoteWeeklyMealsValidator {
    static let maximumManifestBytes = 64 * 1_024
    static let maximumCollectionBytes = 1_024 * 1_024
    static let approvedImageAssetNames: Set<String> = [
        "weekly-placeholder-chicken-taco-rice-bowls",
        "weekly-placeholder-creamy-buffalo-chicken-dip",
        "weekly-placeholder-honey-garlic-chicken-rice",
        "weekly-placeholder-korean-ground-beef-bowls",
        "weekly-placeholder-make-ahead-breakfast-burritos",
        "weekly-placeholder-one-pot-cheeseburger-pasta",
        "weekly-placeholder-protein-berry-smoothie",
        "weekly-placeholder-protein-overnight-oats"
    ]
    private static let supportedUnits: Set<String> = [
        "", "as needed", "can", "clove", "cup", "each", "g", "kg", "l", "lb",
        "ml", "oz", "package", "pinch", "tbsp", "to taste", "tsp"
    ]

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func validate(
        manifest: RemoteWeeklyMealsManifest,
        document: RemoteWeeklyMealCollectionDocument,
        currentAppVersion: String
    ) throws -> ResolvedWeeklyMealCollection {
        guard manifest.schemaVersion == RemoteWeeklyMealsManifest.supportedSchemaVersion,
              !manifest.currentCollectionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isSupportedVersion(currentAppVersion, minimum: manifest.minimumAppVersion) else {
            if !isSupportedVersion(currentAppVersion, minimum: manifest.minimumAppVersion) {
                throw WeeklyMealsRemoteError.unsupportedAppVersion
            }
            throw WeeklyMealsRemoteError.invalidManifest
        }
        guard document.schemaVersion == RemoteWeeklyMealCollectionDocument.supportedSchemaVersion,
              document.id == manifest.currentCollectionID,
              document.collection.id == document.id,
              document.revision > 0,
              document.publishedAt <= manifest.publishedAt,
              !document.collection.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WeeklyMealsRemoteError.invalidManifest
        }

        let recipesResource = WeeklyMealRecipesResource(
            contentSchemaVersion: WeeklyMealsManifest.supportedSchemaVersion,
            recipes: document.recipes
        )
        let validationManifest = WeeklyMealsManifest(
            contentSchemaVersion: WeeklyMealsManifest.supportedSchemaVersion,
            recipesResource: "inline",
            collectionResources: ["inline"],
            fallbackCollectionID: document.collection.id,
            pricingResource: "none"
        )
        var issues = WeeklyMealManifestValidator.issues(
            manifest: validationManifest,
            recipes: recipesResource,
            collections: [document.collection]
        )
        for recipe in document.recipes {
            let path = "recipes.\(recipe.id.rawValue)"
            if recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                recipe.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                recipe.metadata.accessibilityDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !isApprovedAssetName(recipe.metadata.imageAssetName) {
                issues.append(.init(code: .invalidRecipe, path: path, message: "Public recipe text or image reference is invalid."))
            }
            for ingredient in recipe.ingredients {
                if !supportedUnits.contains(ingredient.unit.lowercased()) ||
                    ingredient.quantity.map({ !isFinitePositive($0) }) == true {
                    issues.append(.init(code: .invalidRecipe, path: "\(path).ingredients.\(ingredient.id)", message: "Ingredient unit or quantity is unsupported."))
                }
            }
            if recipe.instructions.contains(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                issues.append(.init(code: .invalidRecipe, path: "\(path).instructions", message: "Instructions cannot be empty."))
            }
            if let nutrition = recipe.metadata.nutrition,
               !isFiniteNonnegative(nutrition.proteinGramsPerServing) {
                issues.append(.init(code: .invalidNutrition, path: "\(path).nutrition", message: "Nutrition must be finite and nonnegative."))
            }
        }
        guard issues.isEmpty else { throw WeeklyMealsRemoteError.invalidCollection(issues) }

        let recipesByID = Dictionary(uniqueKeysWithValues: document.recipes.map { ($0.id, $0) })
        let meals = try document.collection.entries
            .sorted { $0.displayOrder < $1.displayOrder }
            .map { entry -> ResolvedWeeklyMeal in
                guard let recipe = recipesByID[entry.recipeReference.recipeID] else {
                    throw WeeklyMealRepositoryError.missingRecipe(entry.recipeReference.recipeID)
                }
                return ResolvedWeeklyMeal(entry: entry, recipe: recipe)
            }
        return ResolvedWeeklyMealCollection(collection: document.collection, meals: meals)
    }

    static func collectionURL(
        from manifest: RemoteWeeklyMealsManifest,
        relativeTo configuration: WeeklyMealsRemoteConfiguration
    ) throws -> URL {
        let path = manifest.currentCollectionURL
        guard path.hasPrefix("/weekly-meals/collections/"),
              path.hasSuffix(".json"),
              !path.contains(".."),
              !path.contains("?"),
              !path.contains("#"),
              let origin = URL(string: "/", relativeTo: configuration.baseURL),
              let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            throw WeeklyMealsRemoteError.unsafeCollectionURL
        }
        return url
    }

    static func isSameOrigin(_ url: URL, as configuration: WeeklyMealsRemoteConfiguration) -> Bool {
        url.scheme?.lowercased() == configuration.baseURL.scheme?.lowercased() &&
            url.host?.lowercased() == configuration.baseURL.host?.lowercased() &&
            effectivePort(url) == effectivePort(configuration.baseURL)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : nil)
    }

    private static func isSafeAssetName(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private static func isApprovedAssetName(_ value: String) -> Bool {
        isSafeAssetName(value) && approvedImageAssetNames.contains(value)
    }

    private static func isFinitePositive(_ value: Decimal) -> Bool {
        isFiniteNonnegative(value) && value > 0
    }

    private static func isFiniteNonnegative(_ value: Decimal) -> Bool {
        NSDecimalNumber(decimal: value) != .notANumber && value >= 0
    }

    private static func isSupportedVersion(_ current: String, minimum: String) -> Bool {
        let currentParts = versionParts(current)
        let minimumParts = versionParts(minimum)
        guard currentParts != nil, minimumParts != nil else { return false }
        let count = max(currentParts!.count, minimumParts!.count)
        let lhs = currentParts! + Array(repeating: 0, count: count - currentParts!.count)
        let rhs = minimumParts! + Array(repeating: 0, count: count - minimumParts!.count)
        return lhs.lexicographicallyPrecedes(rhs) == false
    }

    private static func versionParts(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        let values = parts.compactMap { Int($0) }
        return values.count == parts.count ? values : nil
    }
}

private actor RemoteWeeklyMealsLoader {
    let configuration: WeeklyMealsRemoteConfiguration
    let client: any WeeklyMealsHTTPClient
    let cacheStore: any WeeklyMealsCacheStoring
    let currentAppVersion: String

    init(
        configuration: WeeklyMealsRemoteConfiguration,
        client: any WeeklyMealsHTTPClient,
        cacheStore: any WeeklyMealsCacheStoring,
        currentAppVersion: String
    ) {
        self.configuration = configuration
        self.client = client
        self.cacheStore = cacheStore
        self.currentAppVersion = currentAppVersion
    }

    func fetch(validatedAt: Date) async throws -> CachedWeeklyMealsContent {
        let manifestResponse = try await client.get(
            configuration.manifestURL,
            maximumBytes: RemoteWeeklyMealsValidator.maximumManifestBytes
        )
        guard RemoteWeeklyMealsValidator.isSameOrigin(manifestResponse.finalURL, as: configuration) else {
            throw WeeklyMealsRemoteError.crossOriginRedirect
        }
        let manifest = try RemoteWeeklyMealsValidator.decoder().decode(
            RemoteWeeklyMealsManifest.self,
            from: manifestResponse.data
        )
        let collectionURL = try RemoteWeeklyMealsValidator.collectionURL(
            from: manifest,
            relativeTo: configuration
        )
        let collectionResponse = try await client.get(
            collectionURL,
            maximumBytes: RemoteWeeklyMealsValidator.maximumCollectionBytes
        )
        guard RemoteWeeklyMealsValidator.isSameOrigin(collectionResponse.finalURL, as: configuration) else {
            throw WeeklyMealsRemoteError.crossOriginRedirect
        }
        let document = try RemoteWeeklyMealsValidator.decoder().decode(
            RemoteWeeklyMealCollectionDocument.self,
            from: collectionResponse.data
        )
        _ = try RemoteWeeklyMealsValidator.validate(
            manifest: manifest,
            document: document,
            currentAppVersion: currentAppVersion
        )
        return CachedWeeklyMealsContent(
            manifest: manifest,
            document: document,
            validatedAt: validatedAt
        )
    }

    func save(_ content: CachedWeeklyMealsContent) throws {
        try cacheStore.save(RemoteWeeklyMealsValidator.encoder().encode(content))
    }
}

@MainActor
@Observable
final class WeeklyMealsStore {
    private(set) var collection: ResolvedWeeklyMealCollection?
    private(set) var displayModels: [WeeklyMealDisplayModel] = []
    private(set) var source: WeeklyMealsContentSource = .bundledFallback
    private(set) var isCurrentCollection = false
    private(set) var isRefreshing = false
    private(set) var lastRefreshError: WeeklyMealsRemoteError?

    @ObservationIgnored private let loader: RemoteWeeklyMealsLoader?
    @ObservationIgnored private let clock: any WeeklyMealsClock
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let currentAppVersion: String
    @ObservationIgnored private let refreshInterval: TimeInterval
    @ObservationIgnored private var cachedContent: CachedWeeklyMealsContent?

    init(
        bundle: Bundle = .main,
        configuration: WeeklyMealsRemoteConfiguration? = try? WeeklyMealsRemoteConfiguration.resolve().get(),
        cacheStore: any WeeklyMealsCacheStoring = FileWeeklyMealsCacheStore(),
        client: any WeeklyMealsHTTPClient = URLSessionWeeklyMealsHTTPClient(),
        clock: any WeeklyMealsClock = SystemWeeklyMealsClock(),
        calendar: Calendar = .autoupdatingCurrent,
        currentAppVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
        refreshInterval: TimeInterval = 6 * 60 * 60
    ) {
        self.clock = clock
        self.calendar = calendar
        self.currentAppVersion = currentAppVersion
        self.refreshInterval = refreshInterval
        loader = configuration.map {
            RemoteWeeklyMealsLoader(
                configuration: $0,
                client: client,
                cacheStore: cacheStore,
                currentAppVersion: currentAppVersion
            )
        }

        let bundled = try? BundledWeeklyMealRepository(bundle: bundle).activeCollection(
            on: clock.now,
            calendar: calendar
        )
        setCollection(bundled, source: .bundledFallback)

        let cacheURLIsSafe: (RemoteWeeklyMealsManifest) -> Bool = { manifest in
            guard let configuration else { return true }
            return (try? RemoteWeeklyMealsValidator.collectionURL(
                from: manifest,
                relativeTo: configuration
            )) != nil
        }
        if let data = try? cacheStore.load(),
           let cached = try? RemoteWeeklyMealsValidator.decoder().decode(CachedWeeklyMealsContent.self, from: data),
           cacheURLIsSafe(cached.manifest),
           let resolved = try? RemoteWeeklyMealsValidator.validate(
               manifest: cached.manifest,
               document: cached.document,
               currentAppVersion: currentAppVersion
           ) {
            cachedContent = cached
            setCollection(resolved, source: .cachedRemote)
        }
    }

    func meal(id: CuratedRecipeID) -> ResolvedWeeklyMeal? {
        collection?.meals.first { $0.recipe.id == id }
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard let loader, !isRefreshing else { return }
        let now = clock.now
        if !force,
           let lastValidatedAt = cachedContent?.validatedAt,
           now.timeIntervalSince(lastValidatedAt) < refreshInterval {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let candidate = try await loader.fetch(validatedAt: now)
            if let cachedContent {
                guard candidate.manifest.publishedAt >= cachedContent.manifest.publishedAt else {
                    throw WeeklyMealsRemoteError.staleManifest
                }
                if candidate.document.id == cachedContent.document.id {
                    guard candidate.document.revision >= cachedContent.document.revision else {
                        throw WeeklyMealsRemoteError.staleManifest
                    }
                    if candidate.document.revision == cachedContent.document.revision,
                       candidate.document != cachedContent.document {
                        throw WeeklyMealsRemoteError.staleManifest
                    }
                }
            }
            let resolved = try RemoteWeeklyMealsValidator.validate(
                manifest: candidate.manifest,
                document: candidate.document,
                currentAppVersion: currentAppVersion
            )
            try await loader.save(candidate)
            cachedContent = candidate
            setCollection(resolved, source: .freshRemote)
            lastRefreshError = nil
        } catch let error as WeeklyMealsRemoteError {
            lastRefreshError = error
        } catch {
            lastRefreshError = .invalidResponse
        }
    }

    private func setCollection(
        _ collection: ResolvedWeeklyMealCollection?,
        source: WeeklyMealsContentSource
    ) {
        self.collection = collection
        displayModels = collection.map { WeeklyMealDisplayModelFactory.makeModels(from: $0) } ?? []
        isCurrentCollection = collection?.collection.contains(clock.now, calendar: calendar) ?? false
        self.source = source
    }
}
