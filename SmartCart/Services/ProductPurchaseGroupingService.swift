import Foundation

/// One demand-level resolution waiting to be represented as a purchase group.
/// Matching, persistence, pantry mutation, and package planning remain outside
/// this value type.
struct ProductPurchaseCandidate: Hashable, Codable {
    let lineID: UUID
    let sourceRecipeID: UUID?
    let ingredientResolution: IngredientResolution
    let originalDisplayQuantity: String
    let canonicalRequiredQuantity: CanonicalQuantity?
    let pantryDeduction: CanonicalQuantity?

    init(
        lineID: UUID,
        sourceRecipeID: UUID? = nil,
        ingredientResolution: IngredientResolution,
        originalDisplayQuantity: String,
        canonicalRequiredQuantity: CanonicalQuantity? = nil,
        pantryDeduction: CanonicalQuantity? = nil
    ) {
        self.lineID = lineID
        self.sourceRecipeID = sourceRecipeID
        self.ingredientResolution = ingredientResolution
        self.originalDisplayQuantity = originalDisplayQuantity
        self.canonicalRequiredQuantity = canonicalRequiredQuantity
        self.pantryDeduction = pantryDeduction
    }
}

/// Ingredient-level provenance retained under a consolidated exact product.
struct ProductPurchaseContribution: Hashable, Codable {
    let lineID: UUID
    let sourceRecipeID: UUID?
    let sourceIngredientID: UUID
    let originalDisplayQuantity: String
    let canonicalRequiredQuantity: CanonicalQuantity?
    let pantryDeduction: CanonicalQuantity?
    let selectedProductIdentity: ExactProductIdentity?
}

/// Package-plan storage shape only. Slice 1C deliberately performs no package
/// arithmetic and never invents a package count.
struct ProductPackagePlan: Hashable, Codable {
    var packageSize: CanonicalQuantity?
    var requiredQuantity: CanonicalQuantity?
    var packageCount: Int?
    var acquiredQuantity: CanonicalQuantity?
    var overage: CanonicalQuantity?
    var certainty: QuantityCertainty

    init(
        packageSize: CanonicalQuantity? = nil,
        requiredQuantity: CanonicalQuantity? = nil,
        packageCount: Int? = nil,
        acquiredQuantity: CanonicalQuantity? = nil,
        overage: CanonicalQuantity? = nil,
        certainty: QuantityCertainty = .unknown
    ) {
        self.packageSize = packageSize
        self.requiredQuantity = requiredQuantity
        self.packageCount = packageCount
        self.acquiredQuantity = acquiredQuantity
        self.overage = overage
        self.certainty = certainty
    }

    private enum CodingKeys: String, CodingKey {
        case packageSize
        case requiredQuantity
        case packageCount
        case acquiredQuantity
        case overage
        case certainty
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        packageSize = try values.decodeIfPresent(CanonicalQuantity.self, forKey: .packageSize)
        requiredQuantity = try values.decodeIfPresent(CanonicalQuantity.self, forKey: .requiredQuantity)
        packageCount = try values.decodeIfPresent(Int.self, forKey: .packageCount)
        acquiredQuantity = try values.decodeIfPresent(CanonicalQuantity.self, forKey: .acquiredQuantity)
        overage = try values.decodeIfPresent(CanonicalQuantity.self, forKey: .overage)
        certainty = try values.decodeIfPresent(QuantityCertainty.self, forKey: .certainty) ?? .unknown
    }
}

struct ProductPurchaseGroup: Identifiable, Hashable, Codable {
    let id: UUID
    let exactProductIdentity: ExactProductIdentity?
    let representativeProduct: RetailerProductRecord
    let contributions: [ProductPurchaseContribution]
    let packagePlan: ProductPackagePlan?

    var memberLineIDs: [UUID] { contributions.map(\.lineID) }
}

enum ProductPurchaseGroupingService {
    /// Groups only equal preferred exact identities. Search fallbacks and exact
    /// products without a durable identity remain isolated. Unresolved and
    /// explicitly excluded demands do not become purchase groups.
    static func group(
        _ candidates: [ProductPurchaseCandidate]
    ) -> [ProductPurchaseGroup] {
        enum GroupKey: Hashable {
            case exact(ExactProductIdentity)
            case isolated(Int)
        }

        struct Member {
            let candidate: ProductPurchaseCandidate
            let product: RetailerProductRecord
            let identity: ExactProductIdentity?
        }

        var orderedKeys: [GroupKey] = []
        var membersByKey: [GroupKey: [Member]] = [:]

        for (offset, candidate) in candidates.enumerated() {
            let product: RetailerProductRecord
            let identity: ExactProductIdentity?
            let key: GroupKey

            switch candidate.ingredientResolution.resolution {
            case .exactProduct(let exactProduct):
                product = exactProduct
                identity = exactProduct.exactProductIdentity
                key = identity.map(GroupKey.exact) ?? .isolated(offset)
            case .searchFallback(let fallback):
                product = fallback
                identity = nil
                key = .isolated(offset)
            case .unresolved, .userExcluded:
                continue
            }

            if membersByKey[key] == nil {
                orderedKeys.append(key)
            }
            membersByKey[key, default: []].append(
                Member(candidate: candidate, product: product, identity: identity)
            )
        }

        return orderedKeys.compactMap { key in
            guard let members = membersByKey[key], let first = members.first else {
                return nil
            }
            let contributions = members.map { member in
                ProductPurchaseContribution(
                    lineID: member.candidate.lineID,
                    sourceRecipeID: member.candidate.sourceRecipeID,
                    sourceIngredientID: member.candidate.ingredientResolution.ingredient.id,
                    originalDisplayQuantity: member.candidate.originalDisplayQuantity,
                    canonicalRequiredQuantity: member.candidate.canonicalRequiredQuantity,
                    pantryDeduction: member.candidate.pantryDeduction,
                    selectedProductIdentity: member.identity
                )
            }
            let requiredQuantity = combinedRequiredQuantity(
                contributions.map(\.canonicalRequiredQuantity)
            )
            let packagePlan = ProductPackagePlan(
                requiredQuantity: requiredQuantity,
                certainty: requiredQuantity?.certainty ?? .unknown
            )
            return ProductPurchaseGroup(
                id: first.candidate.lineID,
                exactProductIdentity: first.identity,
                representativeProduct: first.product,
                contributions: contributions,
                packagePlan: packagePlan
            )
        }
    }

    private static func combinedRequiredQuantity(
        _ quantities: [CanonicalQuantity?]
    ) -> CanonicalQuantity? {
        guard !quantities.isEmpty else { return nil }
        let known = quantities.compactMap { $0 }
        guard known.count == quantities.count,
              let first = known.first,
              [.mass, .volume, .count].contains(first.dimension),
              known.allSatisfy({ $0.dimension == first.dimension })
        else {
            return nil
        }

        let value = known.reduce(Decimal.zero) { $0 + $1.value }
        let certainty = known.reduce(QuantityCertainty.exact) {
            combinedCertainty($0, $1.certainty)
        }
        return CanonicalQuantity(
            value: value,
            dimension: first.dimension,
            certainty: certainty
        )
    }

    private static func combinedCertainty(
        _ lhs: QuantityCertainty,
        _ rhs: QuantityCertainty
    ) -> QuantityCertainty {
        if lhs == .unknown || rhs == .unknown { return .unknown }
        if lhs == .estimated || rhs == .estimated { return .estimated }
        return .exact
    }
}
