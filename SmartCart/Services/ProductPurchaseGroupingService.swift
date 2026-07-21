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
    let sourceContributions: [CombinedIngredientSource]

    init(
        lineID: UUID,
        sourceRecipeID: UUID? = nil,
        ingredientResolution: IngredientResolution,
        originalDisplayQuantity: String,
        canonicalRequiredQuantity: CanonicalQuantity? = nil,
        pantryDeduction: CanonicalQuantity? = nil,
        sourceContributions: [CombinedIngredientSource] = []
    ) {
        self.lineID = lineID
        self.sourceRecipeID = sourceRecipeID
        self.ingredientResolution = ingredientResolution
        self.originalDisplayQuantity = originalDisplayQuantity
        self.canonicalRequiredQuantity = canonicalRequiredQuantity
        self.pantryDeduction = pantryDeduction
        self.sourceContributions = sourceContributions
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
    var sourceContributions: [CombinedIngredientSource]?
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
    var packagePlan: ProductPackagePlan?
    /// All exact identifiers observed across the group. Optional so the
    /// Slice-1C storage shape remains decodable without migration synthesis.
    var exactProductIdentityEvidence: [ExactProductIdentity]? = nil

    var memberLineIDs: [UUID] { contributions.map(\.lineID) }
}

enum ProductPurchaseGroupingService {
    private struct Member {
        let candidate: ProductPurchaseCandidate
        let product: RetailerProductRecord
        let identity: ExactProductIdentity?
        let identities: Set<ExactProductIdentity>
    }

    /// Groups exact products that share a retailer product ID, canonical GTIN,
    /// or canonical exact-product URL. Search fallbacks and exact products
    /// without durable identity remain isolated. Unresolved and explicitly
    /// excluded demands do not become purchase groups.
    static func group(
        _ candidates: [ProductPurchaseCandidate]
    ) -> [ProductPurchaseGroup] {
        var groupedMembers: [[Member]] = []

        for candidate in candidates {
            let product: RetailerProductRecord
            let identity: ExactProductIdentity?
            let identities: Set<ExactProductIdentity>

            switch candidate.ingredientResolution.resolution {
            case .exactProduct(let exactProduct):
                product = exactProduct
                identity = exactProduct.exactProductIdentity
                identities = Set(ExactProductIdentity.all(for: exactProduct))
            case .searchFallback(let fallback):
                product = fallback
                identity = nil
                identities = []
            case .unresolved, .userExcluded:
                continue
            }

            let member = Member(
                candidate: candidate,
                product: product,
                identity: identity,
                identities: identities
            )
            guard !identities.isEmpty else {
                groupedMembers.append([member])
                continue
            }

            let matchingIndices = groupedMembers.indices.filter { groupIndex in
                groupedMembers[groupIndex].contains { !$0.identities.isDisjoint(with: identities) }
            }
            guard let firstMatchingIndex = matchingIndices.first else {
                groupedMembers.append([member])
                continue
            }
            groupedMembers[firstMatchingIndex].append(member)
            for mergeIndex in matchingIndices.dropFirst().reversed() {
                groupedMembers[firstMatchingIndex].append(contentsOf: groupedMembers.remove(at: mergeIndex))
            }
        }

        return groupedMembers.compactMap { members in
            guard let first = members.first else {
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
                    selectedProductIdentity: member.identity,
                    sourceContributions: member.candidate.sourceContributions
                )
            }
            let requiredQuantity = combinedRequiredQuantity(
                contributions.map(\.canonicalRequiredQuantity)
            )
            let packagePlan = packagePlan(
                members: members,
                requiredQuantity: requiredQuantity
            )
            let evidence = Array(Set(members.flatMap(\.identities))).sorted {
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.normalizedValue < $1.normalizedValue
            }
            return ProductPurchaseGroup(
                id: first.candidate.lineID,
                exactProductIdentity: first.identity,
                representativeProduct: first.product,
                contributions: contributions,
                packagePlan: packagePlan,
                exactProductIdentityEvidence: evidence.isEmpty ? nil : evidence
            )
        }
    }

    private static func packagePlan(
        members: [Member],
        requiredQuantity: CanonicalQuantity?
    ) -> ProductPackagePlan {
        guard let requiredQuantity else {
            return ProductPackagePlan(certainty: .unknown)
        }
        guard requiredQuantity.certainty == .exact,
              !members.isEmpty,
              members.allSatisfy({ !$0.product.variableWeight }),
              let firstSize = canonicalPackageSize(for: members[0].product),
              firstSize.certainty == .exact,
              firstSize.dimension == requiredQuantity.dimension,
              members.dropFirst().allSatisfy({ canonicalPackageSize(for: $0.product) == firstSize }),
              firstSize.value > 0
        else {
            return ProductPackagePlan(
                requiredQuantity: requiredQuantity,
                certainty: .unknown
            )
        }

        let rawCount = NSDecimalNumber(decimal: requiredQuantity.value / firstSize.value).doubleValue
        guard rawCount.isFinite,
              rawCount >= 0,
              rawCount <= Double(Int.max)
        else {
            return ProductPackagePlan(
                packageSize: firstSize,
                requiredQuantity: requiredQuantity,
                certainty: .unknown
            )
        }
        let count = max(1, Int(ceil(rawCount)))
        guard let acquired = CanonicalQuantity(
            value: firstSize.value * Decimal(count),
            dimension: firstSize.dimension,
            certainty: .exact
        ), let overage = CanonicalQuantity(
            value: acquired.value - requiredQuantity.value,
            dimension: acquired.dimension,
            certainty: .exact
        ) else {
            return ProductPackagePlan(
                packageSize: firstSize,
                requiredQuantity: requiredQuantity,
                certainty: .unknown
            )
        }
        return ProductPackagePlan(
            packageSize: firstSize,
            requiredQuantity: requiredQuantity,
            packageCount: count,
            acquiredQuantity: acquired,
            overage: overage,
            certainty: .exact
        )
    }

    private static func canonicalPackageSize(
        for product: RetailerProductRecord
    ) -> CanonicalQuantity? {
        guard let quantity = product.packageQuantity,
              quantity.isFinite,
              quantity > 0
        else { return nil }
        guard case .exact(let canonical) = QuantityEngine.canonicalize(
            value: Decimal(quantity),
            unit: product.packageUnit,
            certainty: .exact
        ) else { return nil }
        return canonical
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
