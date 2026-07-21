import XCTest
@testable import SmartCart

final class IngredientIdentityServiceTests: XCTestCase {
    func testRelationshipVocabularyIsBoundedAndConservative() {
        XCTAssertEqual(
            Set(IngredientRelationship.allCases),
            [.exact, .compatible, .substitute, .incompatible, .unknown]
        )
    }

    func testIdentitySeparatesFamilySubtypeFormAndCriticalAttributes() {
        let almondFlour = IngredientIdentityService.identity(for: "Organic almond flour")
        XCTAssertEqual(almondFlour.family, .flour)
        XCTAssertEqual(almondFlour.subtype, .almond)
        XCTAssertNil(almondFlour.form)
        XCTAssertEqual(almondFlour.criticalAttributes, [])
        XCTAssertEqual(almondFlour.unclassifiedQualifiers, ["organic"])

        let frozenSpinach = IngredientIdentityService.identity(for: "Spinach", preparation: "frozen, chopped")
        XCTAssertEqual(frozenSpinach.family, .spinach)
        XCTAssertEqual(frozenSpinach.form, .frozen)
        XCTAssertEqual(frozenSpinach.unclassifiedQualifiers, [])

        let saltedButter = IngredientIdentityService.identity(for: "Salted butter")
        XCTAssertEqual(saltedButter.family, .butter)
        XCTAssertNil(saltedButter.subtype)
        XCTAssertEqual(saltedButter.criticalAttributes, [.salted])
    }

    func testExactStructuredIdentityIgnoresCasePluralAndPreparationPlacement() {
        XCTAssertEqual(
            IngredientIdentityService.relationship(
                between: "FRESH SPINACH",
                and: "spinach",
                rhsPreparation: "fresh, chopped"
            ),
            .exact
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "Salted Butters", and: "salted butter"),
            .exact
        )
    }

    func testKnownAliasesCanResolveAsExact() {
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "riced cauliflower", and: "cauliflower rice"),
            .exact
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "heavy whipping cream", and: "heavy cream"),
            .exact
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "cow's milk", and: "dairy milk"),
            .exact
        )
    }

    func testDangerousPantryPairsAreExplicitlyIncompatibleInBothDirections() {
        let pairs: [(String, String)] = [
            ("peanut butter", "butter"),
            ("coconut milk", "dairy milk"),
            ("almond flour", "wheat flour"),
            ("flour", "bread flour"),
            ("wheat flour", "bread flour"),
            ("brown sugar", "white sugar"),
            ("salted butter", "unsalted butter"),
            ("heavy cream", "sour cream"),
            ("fresh spinach", "frozen spinach"),
            ("cauliflower rice", "rice")
        ]

        for (lhs, rhs) in pairs {
            XCTAssertEqual(
                IngredientIdentityService.relationship(between: lhs, and: rhs),
                .incompatible,
                "Expected \(lhs) and \(rhs) to be incompatible"
            )
            XCTAssertEqual(
                IngredientIdentityService.relationship(between: rhs, and: lhs),
                .incompatible,
                "Expected relationship to be symmetric for \(rhs) and \(lhs)"
            )
        }
    }

    func testBroadNamesAlsoProtectTheDocumentedFalsePositivePairs() {
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "milk", and: "coconut milk"),
            .incompatible
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "flour", and: "almond flour"),
            .incompatible
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "sugar", and: "brown sugar"),
            .incompatible
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "cream", and: "sour cream"),
            .incompatible
        )
    }

    func testIncompleteOrDifferentNonBlockedVariantIsUnknown() {
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "spinach", and: "fresh spinach"),
            .unknown
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "organic rice", and: "rice"),
            .unknown
        )

        let genericAndSpecificPairs: [(String, String)] = [
            ("flour", "wheat flour"),
            ("milk", "dairy milk"),
            ("butter", "dairy butter"),
            ("sugar", "white sugar"),
            ("rice", "white rice")
        ]
        for (generic, specific) in genericAndSpecificPairs {
            XCTAssertEqual(
                IngredientIdentityService.relationship(between: generic, and: specific),
                .unknown,
                "Generic \(generic) must not inherit the specificity of \(specific)"
            )
            XCTAssertEqual(
                IngredientIdentityService.relationship(between: specific, and: generic),
                .unknown,
                "Generic/specific review behavior must be symmetric"
            )
        }
    }

    func testPreparationSubtypeAndUnknownQualifiersCannotDisappear() {
        let cases: [(preparation: String, expected: IngredientRelationship)] = [
            ("coconut", .incompatible),
            ("evaporated", .unknown)
        ]

        for testCase in cases {
            XCTAssertEqual(
                IngredientIdentityService.relationship(
                    between: "milk",
                    and: "milk",
                    lhsPreparation: testCase.preparation
                ),
                testCase.expected
            )
            XCTAssertEqual(
                IngredientIdentityService.relationship(
                    between: "milk",
                    and: "milk",
                    rhsPreparation: testCase.preparation
                ),
                testCase.expected,
                "Preparation identity behavior must be symmetric"
            )
        }
    }

    func testGenericFamilyNamesDoNotAcquireUnsafeSpecificDefaults() {
        let genericNames = ["butter", "milk", "flour", "sugar", "rice"]

        for name in genericNames {
            XCTAssertNil(
                IngredientIdentityService.identity(for: name).subtype,
                "Generic \(name) must remain structurally unspecified"
            )
        }
    }

    func testContradictoryStructuredQualifiersDefaultToUnknown() {
        XCTAssertEqual(
            IngredientIdentityService.relationship(
                between: "fresh frozen spinach",
                and: "fresh frozen spinach"
            ),
            .unknown
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(
                between: "salted unsalted butter",
                and: "salted unsalted butter"
            ),
            .unknown
        )
    }

    func testUnrecognizedDifferentIngredientsDefaultToUnknown() {
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "oregano", and: "marjoram"),
            .unknown
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "", and: "oregano"),
            .unknown
        )
    }

    func testUnrecognizedIdenticalNamesCanStillBeExactWithoutSubsetInference() {
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "Oregano", and: "oregano"),
            .exact
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "oregano", and: "dried oregano"),
            .unknown
        )
        XCTAssertEqual(
            IngredientIdentityService.relationship(
                between: "paprika",
                and: "paprika",
                lhsPreparation: "smoked"
            ),
            .unknown
        )
    }

    func testTokenSubsetNeverCreatesExactIdentity() {
        let pairs: [(String, String)] = [
            ("butter", "European butter"),
            ("milk", "evaporated milk"),
            ("rice", "jasmine rice")
        ]

        for (lhs, rhs) in pairs {
            XCTAssertNotEqual(
                IngredientIdentityService.relationship(between: lhs, and: rhs),
                .exact,
                "Token subset must not imply exact identity for \(lhs) and \(rhs)"
            )
        }
    }

    func testQuantityWordsDoNotInfluenceTheIdentityRelationshipAPI() {
        // Quantity conversion intentionally has no entry point in this service.
        // Names with different unclassified quantity-like qualifiers cannot be
        // promoted to exact merely because their structured food family agrees.
        XCTAssertEqual(
            IngredientIdentityService.relationship(between: "8 ounce cream", and: "cream"),
            .unknown
        )
    }
}
