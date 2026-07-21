import Foundation

/// A bounded reason that one included ingredient did not reach a retailer
/// product or a labeled retailer-search fallback.
enum MatchingFailureReason: Codable, Hashable {
    case adapterUnavailable(retailerID: String)
    case noCandidates
    case requestCancelled
    case transientProviderFailure
    case invalidCandidateData
    case fallbackUnavailable
}

/// The exhaustive terminal result for one submitted ingredient demand.
///
/// A search fallback is intentionally distinct from an exact product. An
/// unresolved result is terminal for the matching attempt, but still requires
/// a later user decision before a Shopping Trip may begin.
enum ShoppingResolution: Codable, Hashable {
    case exactProduct(RetailerProductRecord)
    case searchFallback(RetailerProductRecord)
    case unresolved(MatchingFailureReason)
    case userExcluded

    var product: RetailerProductRecord? {
        switch self {
        case .exactProduct(let product), .searchFallback(let product):
            product
        case .unresolved, .userExcluded:
            nil
        }
    }

    var blocksNewShoppingTrip: Bool {
        if case .unresolved = self { return true }
        return false
    }
}

/// A demand-level result. This remains separate from later product grouping,
/// package planning, persistence, and Shopping Trip creation.
struct IngredientResolution: Identifiable, Codable, Hashable {
    var id: UUID { ingredient.id }

    let ingredient: Ingredient
    let resolution: ShoppingResolution
    let alternatives: [RetailerProductRecord]
    let matchScore: Double?
    let selectionReasons: [String]

    init(
        ingredient: Ingredient,
        resolution: ShoppingResolution,
        alternatives: [RetailerProductRecord] = [],
        matchScore: Double? = nil,
        selectionReasons: [String] = []
    ) {
        self.ingredient = ingredient
        self.resolution = resolution
        self.alternatives = alternatives
        self.matchScore = matchScore
        self.selectionReasons = selectionReasons
    }
}

/// Outcomes accepted from the retailer-matching boundary. Errors stay typed,
/// while an empty ranked result is normalized by `ShoppingResolutionService`.
enum IngredientMatchingOutcome: Hashable {
    case ranked([RankedRetailerProduct])
    case failed(MatchingFailureReason)
    case explicitlyExcluded
}

struct IngredientMatchingInput: Hashable {
    let ingredient: Ingredient
    let outcome: IngredientMatchingOutcome

    init(ingredient: Ingredient, outcome: IngredientMatchingOutcome) {
        self.ingredient = ingredient
        self.outcome = outcome
    }
}

enum ShoppingResolutionValidationIssue: Codable, Hashable {
    case missing(ingredientID: UUID)
    case duplicate(ingredientID: UUID, count: Int)
    case unexpected(ingredientID: UUID)
}

struct ShoppingResolutionValidation: Hashable {
    let issues: [ShoppingResolutionValidationIssue]
    let unresolvedIngredientIDs: [UUID]

    var hasExactlyOneResolutionPerIngredient: Bool { issues.isEmpty }

    var canStartShoppingTrip: Bool {
        hasExactlyOneResolutionPerIngredient && unresolvedIngredientIDs.isEmpty
    }
}

enum ShoppingResolutionService {
    /// Produces one terminal result for every input, in the same order.
    static func resolve(
        _ inputs: [IngredientMatchingInput]
    ) -> [IngredientResolution] {
        inputs.map(resolve)
    }

    static func resolve(
        _ input: IngredientMatchingInput
    ) -> IngredientResolution {
        switch input.outcome {
        case .explicitlyExcluded:
            return IngredientResolution(
                ingredient: input.ingredient,
                resolution: .userExcluded
            )

        case .failed(let reason):
            return IngredientResolution(
                ingredient: input.ingredient,
                resolution: .unresolved(reason)
            )

        case .ranked(let rankedProducts):
            guard !rankedProducts.isEmpty else {
                return IngredientResolution(
                    ingredient: input.ingredient,
                    resolution: .unresolved(.noCandidates)
                )
            }

            let valid: [(RankedRetailerProduct, ShoppingResolution)] = rankedProducts.compactMap { ranked in
                guard ranked.score.isFinite else { return nil }
                return resolution(for: ranked.product).map { (ranked, $0) }
            }
            guard let selected = valid.first else {
                return IngredientResolution(
                    ingredient: input.ingredient,
                    resolution: .unresolved(.invalidCandidateData),
                    matchScore: rankedProducts.first?.score,
                    selectionReasons: rankedProducts.first?.reasons ?? []
                )
            }

            return IngredientResolution(
                ingredient: input.ingredient,
                resolution: selected.1,
                alternatives: valid.dropFirst().map { $0.0.product },
                matchScore: selected.0.score,
                selectionReasons: selected.0.reasons
            )
        }
    }

    /// Validates a frozen demand list without performing grouping or mutating
    /// any runtime state.
    static func validate(
        includedIngredients: [Ingredient],
        resolutions: [IngredientResolution]
    ) -> ShoppingResolutionValidation {
        let expectedIDs = includedIngredients.map(\.id)
        let expectedIDSet = Set(expectedIDs)
        let resolutionCounts = Dictionary(grouping: resolutions, by: \.id)

        var issues: [ShoppingResolutionValidationIssue] = []
        for ingredientID in expectedIDs {
            let count = resolutionCounts[ingredientID]?.count ?? 0
            if count == 0 {
                issues.append(.missing(ingredientID: ingredientID))
            } else if count > 1 {
                issues.append(.duplicate(ingredientID: ingredientID, count: count))
            }
        }

        var seenUnexpectedIDs: Set<UUID> = []
        for resolution in resolutions
        where !expectedIDSet.contains(resolution.id)
            && seenUnexpectedIDs.insert(resolution.id).inserted {
            issues.append(.unexpected(ingredientID: resolution.id))
        }

        let unresolvedIngredientIDs = expectedIDs.filter { ingredientID in
            guard resolutionCounts[ingredientID]?.count == 1,
                  let resolution = resolutionCounts[ingredientID]?.first
            else {
                return false
            }
            return resolution.resolution.blocksNewShoppingTrip
        }

        return ShoppingResolutionValidation(
            issues: issues,
            unresolvedIngredientIDs: unresolvedIngredientIDs
        )
    }

    private static func resolution(
        for product: RetailerProductRecord
    ) -> ShoppingResolution? {
        guard isStructurallyValid(product) else { return nil }

        if product.dataSource == .searchFallback || product.linkKind == .searchResults {
            return .searchFallback(product)
        }
        guard product.linkKind == .exactProduct else { return nil }
        return .exactProduct(product)
    }

    private static func isStructurallyValid(
        _ product: RetailerProductRecord
    ) -> Bool {
        let retailerID = product.retailerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let productID = product.retailerProductID.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = product.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = product.exactURL.scheme?.lowercased()

        return !retailerID.isEmpty
            && !productID.isEmpty
            && !title.isEmpty
            && (scheme == "https" || scheme == "http")
            && product.exactURL.host != nil
    }
}
