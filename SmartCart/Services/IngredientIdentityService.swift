import Foundation

/// A bounded, conservative identity model for ingredient equivalence.
///
/// This service intentionally does not reason about quantity, package size, or
/// pantry coverage. Callers should use it only to decide whether two ingredient
/// names describe the same kind of food before applying quantity logic.
struct IngredientIdentity: Codable, Hashable, Sendable {
    var normalizedName: String
    var family: IngredientIdentityFamily?
    var subtype: IngredientIdentitySubtype?
    var form: IngredientIdentityForm?
    var criticalAttributes: Set<IngredientIdentityCriticalAttribute>
    var unclassifiedQualifiers: Set<String>

    var isStructured: Bool { family != nil }
}

enum IngredientIdentityFamily: String, Codable, CaseIterable, Sendable {
    case butter
    case milk
    case flour
    case sugar
    case cream
    case spinach
    case rice
}

enum IngredientIdentitySubtype: String, Codable, CaseIterable, Sendable {
    case dairy
    case peanut
    case almond
    case coconut
    case cashew
    case oat
    case soy
    case wheat
    case allPurpose
    case bread
    case white
    case brown
    case powdered
    case heavy
    case sour
    case grain
    case cauliflower
}

enum IngredientIdentityForm: String, Codable, CaseIterable, Sendable {
    case fresh
    case frozen
    case dried
    case canned
    case cooked
    case raw
}

enum IngredientIdentityCriticalAttribute: String, Codable, CaseIterable, Sendable {
    case salted
    case unsalted
}

/// `exact` is the only relationship that is safe to treat as automatic
/// ingredient equivalence. `compatible` and `substitute` are reserved for
/// positively curated rules and are never inferred from token overlap. Any
/// incomplete or unclassified relationship remains `unknown`.
enum IngredientRelationship: String, Codable, CaseIterable, Sendable {
    case exact
    case compatible
    case substitute
    case incompatible
    case unknown

    var isExact: Bool { self == .exact }
}

enum IngredientIdentityService {
    static func identity(
        for name: String,
        preparation: String = ""
    ) -> IngredientIdentity {
        let normalizedName = canonicalName(name)
        let nameTokens = Set(tokens(in: name))
        let semanticNameTokens = nameTokens.union(tokens(in: normalizedName))
        let preparationTokens = Set(tokens(in: preparation))
        let allTokens = semanticNameTokens.union(preparationTokens)

        let family = family(for: semanticNameTokens)
        let subtype = subtype(for: family, tokens: allTokens)
        let form = form(for: allTokens)
        let criticalAttributes = criticalAttributes(for: allTokens)
        let consumed = consumedTokens(
            family: family,
            subtype: subtype,
            form: form,
            criticalAttributes: criticalAttributes
        )

        return IngredientIdentity(
            normalizedName: normalizedName,
            family: family,
            subtype: subtype,
            form: form,
            criticalAttributes: criticalAttributes,
            unclassifiedQualifiers: nameTokens
                .union(preparationTokens)
                .subtracting(consumed)
                .subtracting(ignoredPreparationTokens)
        )
    }

    static func relationship(
        between lhsName: String,
        and rhsName: String,
        lhsPreparation: String = "",
        rhsPreparation: String = ""
    ) -> IngredientRelationship {
        relationship(
            between: identity(for: lhsName, preparation: lhsPreparation),
            and: identity(for: rhsName, preparation: rhsPreparation)
        )
    }

    static func relationship(
        between lhs: IngredientIdentity,
        and rhs: IngredientIdentity
    ) -> IngredientRelationship {
        guard !lhs.normalizedName.isEmpty, !rhs.normalizedName.isEmpty else {
            return .unknown
        }

        guard !hasAmbiguousStructure(lhs), !hasAmbiguousStructure(rhs) else {
            return .unknown
        }

        if isExplicitlyIncompatible(lhs, rhs) {
            return .incompatible
        }

        if lhs.family == nil, rhs.family == nil {
            return lhs.normalizedName == rhs.normalizedName
                && lhs.form == rhs.form
                && lhs.criticalAttributes == rhs.criticalAttributes
                && lhs.unclassifiedQualifiers == rhs.unclassifiedQualifiers
                ? .exact
                : .unknown
        }

        guard let lhsFamily = lhs.family,
              let rhsFamily = rhs.family,
              lhsFamily == rhsFamily else {
            return .unknown
        }

        if lhs.subtype == rhs.subtype,
           lhs.form == rhs.form,
           lhs.criticalAttributes == rhs.criticalAttributes,
           lhs.unclassifiedQualifiers == rhs.unclassifiedQualifiers {
            return .exact
        }

        // A shared curated family is useful evidence, but it is deliberately
        // insufficient for automatic equivalence. Unknown qualifiers, missing
        // specificity, or non-blocked variants remain unresolved.
        return .unknown
    }
}

private extension IngredientIdentityService {
    static let ignoredPreparationTokens: Set<String> = [
        "chop", "chopped", "dice", "diced", "finely", "grate", "grated",
        "melted", "mince", "minced", "roughly", "shred", "shredded",
        "slice", "sliced", "softened", "divided", "optional", "taste"
    ]

    static func canonicalName(_ raw: String) -> String {
        let normalized = normalized(raw)
        let aliases: [String: String] = [
            "all purpose flour": "all purpose flour",
            "allpurpose flour": "all purpose flour",
            "confectioner sugar": "powdered sugar",
            "confectioners sugar": "powdered sugar",
            "cow milk": "milk",
            "cows milk": "milk",
            "dairy milk": "milk",
            "granulated sugar": "white sugar",
            "heavy whipping cream": "heavy cream",
            "icing sugar": "powdered sugar",
            "riced cauliflower": "cauliflower rice",
            "whipping cream": "heavy cream"
        ]
        return aliases[normalized] ?? normalized
    }

    static func normalized(_ raw: String) -> String {
        raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
        .replacingOccurrences(of: "-", with: " ")
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty && $0 != "s" }
        .map(singularized)
        .joined(separator: " ")
    }

    static func tokens(in value: String) -> [String] {
        normalized(value).split(separator: " ").map(String.init)
    }

    static func singularized(_ token: String) -> String {
        let exceptions: [String: String] = [
            "berries": "berry",
            "cloves": "clove",
            "leaves": "leaf",
            "potatoes": "potato",
            "tomatoes": "tomato"
        ]
        if let exception = exceptions[token] { return exception }
        if token.hasSuffix("ies"), token.count > 4 {
            return String(token.dropLast(3)) + "y"
        }
        if token.hasSuffix("s"), !token.hasSuffix("ss"), token.count > 3 {
            return String(token.dropLast())
        }
        return token
    }

    static func family(for tokens: Set<String>) -> IngredientIdentityFamily? {
        if tokens.contains("butter") { return .butter }
        if tokens.contains("milk") { return .milk }
        if tokens.contains("flour") { return .flour }
        if tokens.contains("sugar") { return .sugar }
        if tokens.contains("cream") { return .cream }
        if tokens.contains("spinach") { return .spinach }
        if tokens.contains("rice") { return .rice }
        return nil
    }

    static func subtype(
        for family: IngredientIdentityFamily?,
        tokens: Set<String>
    ) -> IngredientIdentitySubtype? {
        switch family {
        case .butter:
            if tokens.contains("peanut") { return .peanut }
            if tokens.contains("almond") { return .almond }
            if tokens.contains("cashew") { return .cashew }
            if tokens.contains("dairy") || tokens.contains("cow") { return .dairy }
            return nil
        case .milk:
            if tokens.contains("coconut") { return .coconut }
            if tokens.contains("almond") { return .almond }
            if tokens.contains("cashew") { return .cashew }
            if tokens.contains("oat") { return .oat }
            if tokens.contains("soy") { return .soy }
            if tokens.contains("dairy") || tokens.contains("cow") { return .dairy }
            return nil
        case .flour:
            if tokens.contains("almond") { return .almond }
            if tokens.contains("coconut") { return .coconut }
            if tokens.contains("bread") { return .bread }
            if tokens.contains("all") && tokens.contains("purpose") { return .allPurpose }
            if tokens.contains("wheat") { return .wheat }
            return nil
        case .sugar:
            if tokens.contains("brown") { return .brown }
            if tokens.contains("powdered") { return .powdered }
            if tokens.contains("white") || tokens.contains("granulated") { return .white }
            return nil
        case .cream:
            if tokens.contains("sour") { return .sour }
            if tokens.contains("heavy") { return .heavy }
            if tokens.contains("coconut") { return .coconut }
            return nil
        case .rice:
            if tokens.contains("cauliflower") { return .cauliflower }
            if !tokens.intersection(["white", "brown", "jasmine", "basmati", "grain"]).isEmpty {
                return .grain
            }
            return nil
        case .spinach, nil:
            return nil
        }
    }

    static func form(for tokens: Set<String>) -> IngredientIdentityForm? {
        let matches = IngredientIdentityForm.allCases.filter { tokens.contains($0.rawValue) }
        return matches.count == 1 ? matches[0] : nil
    }

    static func criticalAttributes(
        for tokens: Set<String>
    ) -> Set<IngredientIdentityCriticalAttribute> {
        var result: Set<IngredientIdentityCriticalAttribute> = []
        if tokens.contains("salted") { result.insert(.salted) }
        if tokens.contains("unsalted") { result.insert(.unsalted) }
        return result
    }

    static func consumedTokens(
        family: IngredientIdentityFamily?,
        subtype: IngredientIdentitySubtype?,
        form: IngredientIdentityForm?,
        criticalAttributes: Set<IngredientIdentityCriticalAttribute>
    ) -> Set<String> {
        var result: Set<String> = []

        switch family {
        case .butter: result.insert("butter")
        case .milk: result.insert("milk")
        case .flour: result.insert("flour")
        case .sugar: result.insert("sugar")
        case .cream: result.insert("cream")
        case .spinach: result.insert("spinach")
        case .rice: result.insert("rice")
        case nil: break
        }

        switch subtype {
        case .dairy: result.formUnion(["dairy", "cow"])
        case .peanut: result.insert("peanut")
        case .almond: result.insert("almond")
        case .coconut: result.insert("coconut")
        case .cashew: result.insert("cashew")
        case .oat: result.insert("oat")
        case .soy: result.insert("soy")
        case .wheat: result.insert("wheat")
        case .allPurpose: result.formUnion(["all", "purpose", "allpurpose"])
        case .bread: result.insert("bread")
        case .white: result.formUnion(["white", "granulated"])
        case .brown: result.insert("brown")
        case .powdered: result.formUnion(["powdered", "confectioner", "confectioners", "icing"])
        case .heavy: result.formUnion(["heavy", "whipping"])
        case .sour: result.insert("sour")
        case .grain: break
        case .cauliflower: result.formUnion(["cauliflower", "riced"])
        case nil: break
        }

        if let form { result.insert(form.rawValue) }
        result.formUnion(criticalAttributes.map(\.rawValue))
        return result
    }

    static func isExplicitlyIncompatible(
        _ lhs: IngredientIdentity,
        _ rhs: IngredientIdentity
    ) -> Bool {
        guard lhs.family == rhs.family, let family = lhs.family else {
            return false
        }

        switch family {
        case .butter:
            if isNutButter(lhs.subtype) != isNutButter(rhs.subtype),
               isDairyOrUnspecified(lhs.subtype) || isDairyOrUnspecified(rhs.subtype) {
                return true
            }
            return hasCriticalAttributeConflict(lhs, rhs, .salted, .unsalted)
        case .milk:
            let lhsIsPlant = isPlantMilk(lhs.subtype)
            let rhsIsPlant = isPlantMilk(rhs.subtype)
            return lhsIsPlant != rhsIsPlant
                && (isDairyOrUnspecified(lhs.subtype) || isDairyOrUnspecified(rhs.subtype))
        case .flour:
            let lhsIsNutOrCoconut = [.almond, .coconut].contains(lhs.subtype)
            let rhsIsNutOrCoconut = [.almond, .coconut].contains(rhs.subtype)
            if lhsIsNutOrCoconut != rhsIsNutOrCoconut { return true }
            return (lhs.subtype == .bread && isPlainWheatFlour(rhs.subtype))
                || (rhs.subtype == .bread && isPlainWheatFlour(lhs.subtype))
        case .sugar:
            return (lhs.subtype == .brown && (rhs.subtype == .white || rhs.subtype == nil))
                || (rhs.subtype == .brown && (lhs.subtype == .white || lhs.subtype == nil))
        case .cream:
            if isSubtypePair(lhs, rhs, .heavy, .sour) { return true }
            return (lhs.subtype == .sour && rhs.subtype == nil)
                || (rhs.subtype == .sour && lhs.subtype == nil)
        case .spinach:
            return isFormPair(lhs, rhs, .fresh, .frozen)
        case .rice:
            return (lhs.subtype == .cauliflower && (rhs.subtype == .grain || rhs.subtype == nil))
                || (rhs.subtype == .cauliflower && (lhs.subtype == .grain || lhs.subtype == nil))
        }
    }

    static func hasAmbiguousStructure(_ identity: IngredientIdentity) -> Bool {
        guard identity.criticalAttributes.count <= 1 else { return true }
        let unresolvedForms = Set(IngredientIdentityForm.allCases.map(\.rawValue))
            .intersection(identity.unclassifiedQualifiers)
        return unresolvedForms.count > 1
    }

    static func isDairyOrUnspecified(_ subtype: IngredientIdentitySubtype?) -> Bool {
        subtype == nil || subtype == .dairy
    }

    static func isNutButter(_ subtype: IngredientIdentitySubtype?) -> Bool {
        subtype == .peanut || subtype == .almond || subtype == .cashew
    }

    static func isPlantMilk(_ subtype: IngredientIdentitySubtype?) -> Bool {
        subtype == .coconut || subtype == .almond || subtype == .cashew
            || subtype == .oat || subtype == .soy
    }

    static func isPlainWheatFlour(_ subtype: IngredientIdentitySubtype?) -> Bool {
        subtype == nil || subtype == .wheat || subtype == .allPurpose
    }

    static func isSubtypePair(
        _ lhs: IngredientIdentity,
        _ rhs: IngredientIdentity,
        _ first: IngredientIdentitySubtype,
        _ second: IngredientIdentitySubtype
    ) -> Bool {
        (lhs.subtype == first && rhs.subtype == second)
            || (lhs.subtype == second && rhs.subtype == first)
    }

    static func isFormPair(
        _ lhs: IngredientIdentity,
        _ rhs: IngredientIdentity,
        _ first: IngredientIdentityForm,
        _ second: IngredientIdentityForm
    ) -> Bool {
        (lhs.form == first && rhs.form == second)
            || (lhs.form == second && rhs.form == first)
    }

    static func hasCriticalAttributeConflict(
        _ lhs: IngredientIdentity,
        _ rhs: IngredientIdentity,
        _ first: IngredientIdentityCriticalAttribute,
        _ second: IngredientIdentityCriticalAttribute
    ) -> Bool {
        (lhs.criticalAttributes.contains(first) && rhs.criticalAttributes.contains(second))
            || (lhs.criticalAttributes.contains(second) && rhs.criticalAttributes.contains(first))
    }
}
