import XCTest
@testable import SmartCart

final class MealPrepAggregationTests: XCTestCase {
    func testSelectionLimitIsFive() throws {
        var draft = MealPrepDraft()
        for index in 0..<5 {
            try draft.addSelection(selection(recipe("Recipe \(index)", servings: 2, []), target: 2))
        }
        XCTAssertThrowsError(try draft.addSelection(selection(recipe("Six", servings: 2, []), target: 2))) {
            XCTAssertEqual($0 as? MealPrepAggregationError, .tooManySelections(maximum: 5))
        }
    }

    func testIndependentServingScalingAndTrustedUnitMerge() throws {
        let first = selection(recipe("A", servings: 4, [ingredient("Flour", 1, "cup")]), target: 8)
        let second = selection(recipe("B", servings: 2, [ingredient("Flour", 8, "fl oz")]), target: 1)
        let result = try aggregate([first, second])
        XCTAssertEqual(result.lines.count, 1)
        XCTAssertEqual(result.lines[0].quantity, 2.5, accuracy: 0.000_001)
        XCTAssertEqual(result.lines[0].unit.symbol, "cup")
        XCTAssertEqual(result.lines[0].mergeReviewState, .automaticallyMerged)
    }

    func testVolumeNeverMergesWithWeight() throws {
        let result = try aggregate([
            selection(recipe("A", servings: 1, [ingredient("Butter", 1, "cup")]), target: 1),
            selection(recipe("B", servings: 1, [ingredient("Butter", 8, "oz")]), target: 1)
        ])
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertTrue(result.lines.allSatisfy { $0.mergeReviewReasons.contains(.incompatibleUnit) })
    }

    func testMassMergesAcrossPoundsAndGramsThroughCanonicalQuantity() throws {
        let selected = [selection(
            recipe("Two-system dough", servings: 1, [
                ingredient("Flour", 1, "lb"),
                ingredient("Flour", 453.59237, "g")
            ]),
            target: 1
        )]

        let result = try aggregate(selected)

        XCTAssertEqual(result.lines.count, 1)
        XCTAssertEqual(result.lines[0].quantity, 2, accuracy: 0.000_001)
        XCTAssertEqual(result.lines[0].unit.symbol, "lb")
    }

    func testVolumeMergesAcrossCupsAndMillilitersThroughCanonicalQuantity() throws {
        let selected = [selection(
            recipe("Two-system sauce", servings: 1, [
                ingredient("Milk", 1, "cup"),
                ingredient("Milk", 236.5882365, "ml")
            ]),
            target: 1
        )]

        let result = try aggregate(selected)

        XCTAssertEqual(result.lines.count, 1)
        XCTAssertEqual(result.lines[0].quantity, 2, accuracy: 0.000_001)
        XCTAssertEqual(result.lines[0].unit.symbol, "cup")
    }

    func testOnionAndButterSubtypesRemainSeparate() throws {
        let ingredients = [
            ingredient("Red onions", 1, "count"), ingredient("Yellow onion", 1, "count"),
            ingredient("Salted butter", 4, "oz"), ingredient("Unsalted butter", 4, "oz")
        ]
        let result = try aggregate([selection(recipe("Dinner", servings: 1, ingredients), target: 1)])
        XCTAssertEqual(result.lines.count, 4)
        XCTAssertTrue(result.lines.allSatisfy { $0.mergeReviewState == .reviewRequired })
        XCTAssertEqual(Set(result.lines.compactMap(\.uncertainDuplicateGroup)).count, 2)
    }

    func testPreparationInsensitiveMergeButProductChangingPreparationDoesNot() throws {
        let chopped = ingredient("Carrots", 2, "count", preparation: "chopped")
        let diced = ingredient("Carrot", 1, "count", preparation: "finely diced")
        let cooked = ingredient("Rice", 1, "cup", preparation: "cooked")
        let uncooked = ingredient("Rice", 1, "cup", preparation: "uncooked")
        let melted = ingredient("Unsalted butter", 4, "oz", preparation: "melted")
        let softened = ingredient("Unsalted butter", 2, "oz", preparation: "softened")
        let freshTomatoes = ingredient("Tomatoes", 2, "count")
        let sunDriedTomatoes = ingredient("Tomatoes", 1, "cup", preparation: "sun-dried")
        let result = try aggregate([selection(recipe(
            "Prep",
            servings: 1,
            [chopped, diced, cooked, uncooked, melted, softened, freshTomatoes, sunDriedTomatoes]
        ), target: 1)])
        XCTAssertEqual(result.lines.first(where: { $0.canonicalName == "carrot" })?.quantity, 3)
        XCTAssertEqual(result.lines.first(where: { $0.canonicalName == "unsalted butter" })?.quantity, 6)
        XCTAssertEqual(result.lines.filter { $0.canonicalName == "rice" }.count, 2)
        XCTAssertTrue(result.lines.filter { $0.canonicalName == "rice" }.allSatisfy {
            $0.mergeReviewReasons.contains(.productChangingPreparation)
        })
        XCTAssertEqual(result.lines.filter { $0.canonicalName == "tomato" }.count, 2)
    }

    func testAlternativesStaySeparateAndShareReviewGroup() throws {
        var parsley = ingredient("Parsley", 1, "bunch")
        parsley.alternativeGroup = "fresh herb choice"
        var cilantro = ingredient("Cilantro", 1, "bunch")
        cilantro.alternativeGroup = "fresh herb choice"
        let result = try aggregate([selection(recipe("Salsa", servings: 2, [parsley, cilantro]), target: 2)])
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertTrue(result.lines.allSatisfy { $0.mergeReviewState == .alternativeChoice })
        XCTAssertEqual(Set(result.lines.compactMap(\.uncertainDuplicateGroup)).count, 1)
    }

    @MainActor
    func testAlternativeChoicePurchasesOnlyTheExplicitSelection() throws {
        var parsley = ingredient("Parsley", 1, "bunch")
        parsley.alternativeGroup = "fresh herb choice"
        var cilantro = ingredient("Cilantro", 1, "bunch")
        cilantro.alternativeGroup = "fresh herb choice"
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Salsa", servings: 2, [parsley, cilantro]), target: 2)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())
        let parsleyLine = try XCTUnwrap(model.mealPrepPlan?.lines.first { $0.name == "Parsley" })

        model.selectMealPrepAlternative(parsleyLine.id)

        let lines = try XCTUnwrap(model.mealPrepPlan?.lines)
        XCTAssertEqual(lines.first { $0.name == "Parsley" }?.mergeReviewState, .selectedAlternative)
        XCTAssertEqual(lines.first { $0.name == "Parsley" }?.quantityToBuy, 1)
        XCTAssertEqual(lines.first { $0.name == "Cilantro" }?.mergeReviewState, .excludedAlternative)
        XCTAssertEqual(lines.first { $0.name == "Cilantro" }?.quantityToBuy, 0)
        XCTAssertEqual(model.mealPrepPlan?.unresolvedReviewCount, 0)
        XCTAssertEqual(model.mealPrepPlan?.pantryCoveredCount, 0)
    }

    @MainActor
    func testAlternativeSelectionCanBeReopenedChangedAndSurvivesJSONRelaunch() throws {
        var dairy = ingredient("Milk or cream", 1, "cup")
        dairy.alternativeGroup = "milk or cream"
        let store = try makeTemporaryJSONStore()
        let model = AppModel(stateStore: store)
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Sauce", servings: 2, [dairy]), target: 2)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())
        let milkID = try XCTUnwrap(model.mealPrepPlan?.lines.first { $0.name.lowercased() == "milk" }?.id)
        let creamID = try XCTUnwrap(model.mealPrepPlan?.lines.first { $0.name.lowercased() == "cream" }?.id)

        model.selectMealPrepAlternative(milkID)

        let selectedRelaunch = AppModel(stateStore: store)
        XCTAssertEqual(
            selectedRelaunch.mealPrepPlan?.lines.first { $0.id == milkID }?.mergeReviewState,
            .selectedAlternative
        )
        selectedRelaunch.reopenMealPrepAlternativeGroup(lineID: milkID)
        XCTAssertEqual(selectedRelaunch.mealPrepPlan?.unresolvedReviewCount, 2)
        XCTAssertTrue(selectedRelaunch.mealPrepPlan?.lines.allSatisfy {
            $0.mergeReviewState == .alternativeChoice && $0.mergeReviewReasons.contains(.alternative)
        } == true)

        let reopenedRelaunch = AppModel(stateStore: store)
        XCTAssertEqual(reopenedRelaunch.mealPrepPlan?.unresolvedReviewCount, 2)
        reopenedRelaunch.selectMealPrepAlternative(creamID)

        let changedRelaunch = AppModel(stateStore: store)
        XCTAssertEqual(
            changedRelaunch.mealPrepPlan?.lines.first { $0.id == creamID }?.mergeReviewState,
            .selectedAlternative
        )
        XCTAssertEqual(
            changedRelaunch.mealPrepPlan?.lines.first { $0.id == milkID }?.mergeReviewState,
            .excludedAlternative
        )
        XCTAssertEqual(changedRelaunch.mealPrepPlan?.unresolvedReviewCount, 0)
    }

    @MainActor
    func testExcludedAlternativeGroupCanBeReopenedAfterJSONRelaunch() throws {
        var dairy = ingredient("Milk or cream", 1, "cup")
        dairy.alternativeGroup = "milk or cream"
        let store = try makeTemporaryJSONStore()
        let model = AppModel(stateStore: store)
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Sauce", servings: 2, [dairy]), target: 2)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())
        let lineID = try XCTUnwrap(model.mealPrepPlan?.lines.first?.id)

        model.excludeMealPrepAlternativeGroup(lineID)
        XCTAssertTrue(model.mealPrepPlan?.lines.allSatisfy {
            $0.mergeReviewState == .excludedAlternative && !$0.participatesInCurrentTrip
        } == true)

        let excludedRelaunch = AppModel(stateStore: store)
        XCTAssertTrue(excludedRelaunch.mealPrepPlan?.lines.allSatisfy {
            $0.mergeReviewState == .excludedAlternative && !$0.participatesInCurrentTrip
        } == true)
        excludedRelaunch.reopenMealPrepAlternativeGroup(lineID: lineID)

        let reopenedRelaunch = AppModel(stateStore: store)
        XCTAssertEqual(reopenedRelaunch.mealPrepPlan?.unresolvedReviewCount, 2)
        XCTAssertTrue(reopenedRelaunch.mealPrepPlan?.lines.allSatisfy {
            $0.mergeReviewState == .alternativeChoice &&
                $0.mergeReviewReasons.contains(.alternative) &&
                $0.participatesInCurrentTrip
        } == true)
    }

    @MainActor
    func testKeepAllAlternativesCanBeReopenedAfterJSONRelaunch() throws {
        var dairy = ingredient("Milk or cream", 1, "cup")
        dairy.alternativeGroup = "milk or cream"
        let store = try makeTemporaryJSONStore()
        let model = AppModel(stateStore: store)
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Sauce", servings: 2, [dairy]), target: 2)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())
        let lineID = try XCTUnwrap(model.mealPrepPlan?.lines.first?.id)

        model.keepMealPrepAlternativeGroup(lineID)
        XCTAssertTrue(model.mealPrepPlan?.lines.allSatisfy {
            $0.mergeReviewState == .confirmedSeparate && $0.participatesInCurrentTrip
        } == true)

        let keptAllRelaunch = AppModel(stateStore: store)
        XCTAssertTrue(keptAllRelaunch.mealPrepPlan?.lines.allSatisfy {
            $0.mergeReviewState == .confirmedSeparate && $0.participatesInCurrentTrip
        } == true)
        keptAllRelaunch.reopenMealPrepAlternativeGroup(lineID: lineID)

        let reopenedRelaunch = AppModel(stateStore: store)
        XCTAssertEqual(reopenedRelaunch.mealPrepPlan?.unresolvedReviewCount, 2)
        XCTAssertTrue(reopenedRelaunch.mealPrepPlan?.lines.allSatisfy {
            $0.mergeReviewState == .alternativeChoice && $0.mergeReviewReasons.contains(.alternative)
        } == true)
    }

    func testRequiredMealPrepControlMetricIsAtLeastFortyFourPoints() {
        XCTAssertGreaterThanOrEqual(SmartCartTheme.minimumHitTargetDimension, 44)
    }

    @MainActor
    func testUncertainQuantityRequiresExplicitConfirmation() throws {
        var flour = ingredient("Flour", 2, "cup")
        flour.quantityReviewRequired = true
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Cake", servings: 4, [flour]), target: 4)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())
        let lineID = try XCTUnwrap(model.mealPrepPlan?.lines.first?.id)
        XCTAssertEqual(model.mealPrepPlan?.unresolvedReviewCount, 1)

        model.confirmMealPrepQuantity(lineID)

        XCTAssertEqual(model.mealPrepPlan?.lines.first?.mergeReviewState, .confirmedQuantity)
        XCTAssertEqual(model.mealPrepPlan?.unresolvedReviewCount, 0)
    }

    @MainActor
    func testMealPrepPlanSkipsRedundantReviewScreenAndOpensRecipeReady() {
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        let dinner = recipe("Dinner", servings: 2, [ingredient("Rice", 1, "cup")])
        model.mealPrepDraft = MealPrepDraft(selections: [selection(dinner, target: 2)])

        XCTAssertTrue(model.buildMealPrepPlan())

        XCTAssertEqual(model.homePath, [.mealPrepSelection, .recipeReady])
        XCTAssertEqual(model.recipeReadyBlockingIssueCount, 0)
    }

    @MainActor
    func testUnresolvedMealPrepPlanOpensRecipeReadyWithShoppingBlocked() throws {
        var flour = ingredient("Flour", 2, "cup")
        flour.quantityReviewRequired = true
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Cake", servings: 4, [flour]), target: 4)
        ])

        XCTAssertTrue(model.buildMealPrepPlan())

        XCTAssertEqual(model.homePath, [.mealPrepSelection, .recipeReady])
        XCTAssertEqual(model.recipeReadyBlockingIssueCount, 1)
        XCTAssertFalse(model.recipeReadyCanStartShopping)
    }

    func testPantryFullPartialAndInsufficientConversions() throws {
        let flour = ingredient("Flour", 2, "cup")
        let scope = ShoppingScope.mealPrep(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let selected = [selection(recipe("Bake", servings: 1, [flour]), target: 1)]

        let full = try MealPrepAggregationService.aggregate(
            selections: selected,
            scope: scope,
            pantryInventory: [PantryInventoryItem(name: "Flour", remainingAmount: 16, remainingUnit: "fl oz")]
        )
        XCTAssertNil(full.lines[0].buyFullOverride)
        XCTAssertEqual(full.lines[0].quantityToBuy, 2, accuracy: 0.000_001)
        XCTAssertFalse(full.lines[0].pantryDeductions.isEmpty)
        var fullAfterUsePantry = full.lines
        fullAfterUsePantry[0].buyFullOverride = false
        MealPrepAggregationService.recomputePantry(
            [PantryInventoryItem(name: "Flour", remainingAmount: 16, remainingUnit: "fl oz")],
            for: &fullAfterUsePantry
        )
        XCTAssertEqual(fullAfterUsePantry[0].quantityToBuy, 0, accuracy: 0.000_001)

        let partial = try MealPrepAggregationService.aggregate(
            selections: selected,
            scope: scope,
            pantryInventory: [PantryInventoryItem(name: "Flour", remainingAmount: 1, remainingUnit: "cup")]
        )
        XCTAssertNil(partial.lines[0].buyFullOverride)
        XCTAssertEqual(partial.lines[0].quantityToBuy, 2, accuracy: 0.000_001)
        var partialAfterUsePantry = partial.lines
        partialAfterUsePantry[0].buyFullOverride = false
        MealPrepAggregationService.recomputePantry(
            [PantryInventoryItem(name: "Flour", remainingAmount: 1, remainingUnit: "cup")],
            for: &partialAfterUsePantry
        )
        XCTAssertEqual(partialAfterUsePantry[0].quantityToBuy, 1, accuracy: 0.000_001)

        let unsafe = try MealPrepAggregationService.aggregate(
            selections: selected,
            scope: scope,
            pantryInventory: [PantryInventoryItem(name: "Flour", remainingAmount: 16, remainingUnit: "oz")]
        )
        XCTAssertEqual(unsafe.lines[0].quantityToBuy, 2, accuracy: 0.000_001)
        XCTAssertTrue(unsafe.lines[0].pantryDeductions.isEmpty)
    }

    func testPurchasedProductMarketingNameRequiresReviewForGenericRecipeIngredient() throws {
        let selected = [selection(
            recipe("Dinner", servings: 1, [ingredient("Chicken breasts", 1, "lb")]),
            target: 1
        )]
        let inventory = PantryInventoryItem(
            name: "Free Range Fresh Boneless Chicken Breast",
            brand: "Perdue Harvestland",
            packageCount: 1,
            packageSize: 3.4,
            packageUnit: "lb",
            remainingAmount: 3.4,
            remainingUnit: "lb"
        )

        let result = try MealPrepAggregationService.aggregate(
            selections: selected,
            scope: .mealPrep(UUID()),
            pantryInventory: [inventory]
        )

        XCTAssertNil(result.lines[0].buyFullOverride)
        XCTAssertEqual(result.lines[0].quantityToBuy, 1, accuracy: 0.000_001)
        XCTAssertTrue(result.lines[0].pantryDeductions.isEmpty)
        var usePantryLines = result.lines
        usePantryLines[0].buyFullOverride = false
        MealPrepAggregationService.recomputePantry([inventory], for: &usePantryLines)
        XCTAssertEqual(usePantryLines[0].quantityToBuy, 1, accuracy: 0.000_001)
    }

    func testDangerousPantryIdentityPairsNeverProduceMeasuredCoverage() {
        let pairs: [(String, String)] = [
            ("butter", "peanut butter"),
            ("milk", "coconut milk"),
            ("cream", "sour cream"),
            ("flour", "bread flour"),
            ("flour", "almond flour"),
            ("sugar", "brown sugar"),
            ("rice", "cauliflower rice"),
            ("salted butter", "unsalted butter")
        ]

        for (ingredientName, pantryName) in pairs {
            let suggestion = PantryMatchingService.bestSuggestion(
                for: Ingredient(name: ingredientName, quantity: 1, unit: "cup"),
                inventory: [
                    PantryInventoryItem(
                        name: pantryName,
                        remainingAmount: 10,
                        remainingUnit: "cup"
                    )
                ]
            )

            XCTAssertNil(suggestion, "\(pantryName) must be suppressed for \(ingredientName)")
        }
    }

    func testUnknownPantryIdentityCanOnlyProduceReviewOnlyCoverage() throws {
        let ingredient = Ingredient(name: "Organic chicken breast", quantity: 1, unit: "lb")
        let pantry = PantryInventoryItem(
            name: "Chicken breast",
            remainingAmount: 2,
            remainingUnit: "lb"
        )

        let suggestion = try XCTUnwrap(
            PantryMatchingService.bestSuggestion(for: ingredient, inventory: [pantry])
        )

        XCTAssertEqual(suggestion.coverage, .possible)
        var reviewedIngredient = ingredient
        reviewedIngredient.pantrySuggestion = suggestion
        reviewedIngredient.pantryDecision = .useAvailable
        XCTAssertEqual(
            PantryMatchingService.quantityToBuy(
                for: reviewedIngredient,
                requiredQuantity: ingredient.quantity
            ),
            ingredient.quantity
        )
    }

    @MainActor
    func testMealPrepPantrySuggestionCanBeOverriddenAndRestored() throws {
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.pantryInventory = [
            PantryInventoryItem(name: "Flour", remainingAmount: 1, remainingUnit: "cup")
        ]
        let bake = recipe("Bake", servings: 1, [ingredient("Flour", 2, "cup")])
        model.mealPrepDraft = MealPrepDraft(selections: [selection(bake, target: 1)])
        XCTAssertTrue(model.buildMealPrepPlan())
        let lineID = try XCTUnwrap(model.mealPrepPlan?.lines.first?.id)
        XCTAssertNil(model.mealPrepPlan?.lines.first?.buyFullOverride)
        XCTAssertEqual(model.mealPrepPlan?.lines.first?.quantityToBuy, 2)
        XCTAssertTrue(model.mealPrepPlan?.lines.first?.hasPantryChoice == true)

        model.setMealPrepPantryOverride(lineID: lineID, buyFull: false)
        XCTAssertEqual(model.mealPrepPlan?.lines.first?.quantityToBuy, 1)
        XCTAssertFalse(model.mealPrepPlan?.lines.first?.pantryDeductions.isEmpty == true)

        model.setMealPrepPantryOverride(lineID: lineID, buyFull: true)
        XCTAssertEqual(model.mealPrepPlan?.lines.first?.quantityToBuy, 2)
        XCTAssertTrue(model.mealPrepPlan?.lines.first?.isBuyingFullQuantity == true)
        XCTAssertTrue(model.mealPrepPlan?.lines.first?.hasPantryChoice == true)
    }

    func testFrozenSnapshotSurvivesSourceRecipeDeletion() throws {
        var recipes = [recipe("Soup", servings: 4, [ingredient("Carrot", 2, "count")])]
        let frozenSelection = selection(recipes[0], target: 8)
        recipes.removeAll()
        let result = try aggregate([frozenSelection])
        XCTAssertTrue(recipes.isEmpty)
        XCTAssertEqual(result.lines[0].name, "Carrot")
        XCTAssertEqual(result.lines[0].quantity, 4, accuracy: 0.000_001)
    }

    func testShoppingScopeFingerprintInputIsDeterministic() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        XCTAssertEqual(
            ShoppingScope.mealPrep(id).fingerprintInput,
            "shopping-scope:v1:mealPrepBeta:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )
        XCTAssertEqual(ShoppingScope.mealPrep(id).fingerprintInput, ShoppingScope.mealPrep(id).fingerprintInput)
    }

    @MainActor
    func testMealPrepDraftAndReviewedPlanSurviveRelaunch() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store)
        let recipes = [
            recipe("Soup", servings: 4, [ingredient("Carrot", 2, "count")]),
            recipe("Rice", servings: 2, [ingredient("Rice", 1, "cup")])
        ]
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipes[0], target: 6),
            selection(recipes[1], target: 4)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())

        let restored = AppModel(stateStore: store)
        XCTAssertEqual(restored.mealPrepDraft?.selections.map(\.targetServings), [6, 4])
        XCTAssertEqual(restored.currentMealPrepPlan?.recipeCount, 2)
        XCTAssertEqual(restored.shoppingScope, restored.mealPrepDraft?.shoppingScope)
    }

    @MainActor
    func testDeletedSourceRecipeDoesNotCorruptPersistedMealPrepPlan() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store)
        let source = recipe("Freezer Soup", servings: 4, [ingredient("Carrot", 2, "count")])
        model.recipes = [source]
        model.mealPrepDraft = MealPrepDraft(selections: [selection(source, target: 8)])
        XCTAssertTrue(model.buildMealPrepPlan())
        model.recipes.removeAll()
        model.persistNow()

        let restored = AppModel(stateStore: store)
        XCTAssertTrue(restored.recipes.isEmpty)
        XCTAssertEqual(restored.currentMealPrepPlan?.selections.first?.recipeSnapshot.title, "Freezer Soup")
        XCTAssertEqual(restored.currentMealPrepPlan?.lines.first?.quantity, 4)
    }

    @MainActor
    func testMealPrepSessionFingerprintChangesWithServingsAndRecipeRemoval() throws {
        let defaults = UserDefaults(suiteName: "MealPrepAggregationTests.\(UUID().uuidString)")!
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: defaults,
            seedDemoShoppingState: true
        )
        let reusableItems = model.shoppingItems
        let first = recipe("Tacos", servings: 4, [ingredient("Yellow onion", 2, "count")])
        let second = recipe("Rice", servings: 2, [ingredient("Rice", 1, "cup")])
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(first, target: 4),
            selection(second, target: 2)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())
        model.shoppingItems = reusableItems
        model.completeRetailerSetup()
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let original = try XCTUnwrap(model.shoppingSessions.first)

        model.updateMealPrepServings(selectionID: try XCTUnwrap(model.mealPrepDraft?.selections.first).id, delta: 2)
        XCTAssertTrue(model.buildMealPrepPlan())
        model.shoppingItems = reusableItems
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let servingsChanged = try XCTUnwrap(model.shoppingSessions.first)
        XCTAssertNotEqual(servingsChanged.id, original.id)
        XCTAssertNotEqual(servingsChanged.stateFingerprint, original.stateFingerprint)

        model.mealPrepDraft?.selections.removeLast()
        XCTAssertTrue(model.buildMealPrepPlan())
        model.shoppingItems = reusableItems
        XCTAssertTrue(model.startOrResumeRetailerShoppingSession())
        let recipeRemoved = try XCTUnwrap(model.shoppingSessions.first)
        XCTAssertNotEqual(recipeRemoved.id, servingsChanged.id)
        XCTAssertNotEqual(recipeRemoved.stateFingerprint, servingsChanged.stateFingerprint)
    }

    @MainActor
    func testSchemaV5MigratesActiveSingleRecipeScopeToV6() throws {
        let seedStore = InMemorySmartCartStateStore()
        let seedModel = AppModel(stateStore: seedStore, seedDemoShoppingState: true)
        seedModel.persistNow()
        let state = try XCTUnwrap(seedStore.state)
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
            shoppingItems: state.shoppingItems,
            guidedIndex: state.guidedIndex,
            savedLists: state.savedLists,
            preferredDeliveryPartnerName: state.preferredDeliveryPartnerName,
            pantryInventory: state.pantryInventory,
            preferredProductIDsByIngredient: state.preferredProductIDsByIngredient,
            analyticsEvents: state.analyticsEvents,
            walmartWishlistReference: state.walmartWishlistReference,
            shoppingSessions: state.shoppingSessions
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(to: file, options: .atomic)

        let migrated = try XCTUnwrap(JSONSmartCartStateStore(fileURL: file).load())
        XCTAssertEqual(migrated.schemaVersion, SmartCartPersistedState.currentSchemaVersion)
        XCTAssertEqual(migrated.shoppingScope, ShoppingScope.singleRecipe(state.activeRecipe.id))
        XCTAssertEqual(migrated.shoppingItems, state.shoppingItems)
    }

    @MainActor
    func testMealPrepAtomicWriteFailureRollsBackScopePlanAndItemsTogether() throws {
        let store = ReleaseBlockerFailingStateStore()
        let model = AppModel(stateStore: store, seedDemoShoppingState: true)
        model.persistNow()
        let originalScope = model.shoppingScope
        let originalItems = model.shoppingItems
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Dinner", servings: 2, [ingredient("Rice", 1, "cup")]), target: 4)
        ])
        let originalDraft = model.mealPrepDraft
        store.failNextSave = true

        XCTAssertFalse(model.buildMealPrepPlan())

        XCTAssertEqual(model.shoppingScope, originalScope)
        XCTAssertEqual(model.mealPrepDraft, originalDraft)
        XCTAssertNil(model.mealPrepPlan)
        XCTAssertEqual(model.shoppingItems, originalItems)
        XCTAssertEqual(store.state?.shoppingScope, originalScope)
        XCTAssertEqual(store.state?.shoppingItems, originalItems)
    }

    @MainActor
    func testFreshMealPrepDraftWriteFailureLeavesPriorStateUntouched() {
        let store = ReleaseBlockerFailingStateStore()
        let model = AppModel(stateStore: store, seedDemoShoppingState: true)
        model.persistNow()
        let originalScope = model.shoppingScope
        let originalItems = model.shoppingItems
        store.failNextSave = true

        model.startMealPrepDraft()

        XCTAssertNil(model.mealPrepDraft)
        XCTAssertNil(model.mealPrepPlan)
        XCTAssertEqual(model.shoppingScope, originalScope)
        XCTAssertEqual(model.shoppingItems, originalItems)
        XCTAssertEqual(store.state?.shoppingScope, originalScope)
        XCTAssertEqual(store.state?.shoppingItems, originalItems)
    }

    @MainActor
    func testDeferredAlternativeIsExcludedReopensAfterJSONRelaunchAndCanBeSelected() async throws {
        var dairy = ingredient("Milk or cream", 1, "cup")
        dairy.alternativeGroup = "milk or cream"
        let store = try makeTemporaryJSONStore()
        let model = AppModel(stateStore: store)
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Sauce", servings: 2, [dairy]), target: 2)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())
        let lineID = try XCTUnwrap(model.mealPrepPlan?.lines.first?.id)

        model.deferMealPrepAlternativeGroup(lineID)

        XCTAssertEqual(model.mealPrepPlan?.unresolvedReviewCount, 0)
        XCTAssertEqual(model.mealPrepPlan?.lines.count, 2)
        XCTAssertTrue(model.mealPrepPlan?.lines.allSatisfy {
            $0.mergeReviewState == .deferredAlternative &&
                $0.quantityToBuy == 0 &&
                !$0.participatesInCurrentTrip
        } == true)
        XCTAssertTrue(model.ingredientsToBuy.isEmpty)
        model.openMealPrepDashboard()
        XCTAssertEqual(model.homePath.last, .recipeReady)

        let restored = AppModel(stateStore: store)
        XCTAssertTrue(restored.mealPrepPlan?.lines.allSatisfy {
            $0.mergeReviewState == .deferredAlternative && !$0.participatesInCurrentTrip
        } == true)
        restored.reopenMealPrepAlternativeGroup(lineID: lineID)
        XCTAssertEqual(restored.mealPrepPlan?.unresolvedReviewCount, 2)
        XCTAssertTrue(restored.mealPrepPlan?.lines.allSatisfy {
            $0.mergeReviewState == .alternativeChoice &&
                $0.mergeReviewReasons.contains(.alternative)
        } == true)
        restored.selectMealPrepAlternative(lineID)
        XCTAssertEqual(restored.mealPrepPlan?.unresolvedReviewCount, 0)
        await restored.startMatching()
        XCTAssertEqual(restored.shoppingItems.count, 1)
    }

    @MainActor
    func testDeferredAlternativeNeverEntersMatchedManifest() async throws {
        var dairy = ingredient("Milk or cream", 1, "cup")
        dairy.alternativeGroup = "milk or cream"
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Sauce", servings: 2, [dairy]), target: 2)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())
        let lineID = try XCTUnwrap(model.mealPrepPlan?.lines.first?.id)
        model.deferMealPrepAlternativeGroup(lineID)

        await model.startMatching()
        model.saveCurrentList()

        XCTAssertTrue(model.shoppingItems.isEmpty)
        XCTAssertTrue(model.savedLists.first?.manifest.items.isEmpty == true)
    }

    @MainActor
    func testBuyFullOverrideReallocatesSharedPantryAndSurvivesInventoryChanges() throws {
        var firstFlour = ingredient("Flour", 1, "cup")
        firstFlour.quantityReviewRequired = true
        let secondFlour = ingredient("Flour", 1, "cup")
        let stock = PantryInventoryItem(name: "Flour", remainingAmount: 1, remainingUnit: "cup")
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store)
        model.pantryInventory = [stock]
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Bake", servings: 1, [firstFlour, secondFlour]), target: 1)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())
        let firstID = try XCTUnwrap(model.mealPrepPlan?.lines.first {
            $0.sources.first?.ingredient.id == firstFlour.id
        }?.id)
        let secondID = try XCTUnwrap(model.mealPrepPlan?.lines.first {
            $0.sources.first?.ingredient.id == secondFlour.id
        }?.id)
        model.confirmMealPrepQuantity(firstID)
        model.confirmMealPrepLineSeparate(secondID)
        model.setMealPrepPantryOverride(lineID: firstID, buyFull: false)
        model.setMealPrepPantryOverride(lineID: secondID, buyFull: false)
        let initiallyCoveredID = try XCTUnwrap(model.mealPrepPlan?.lines.first {
            !$0.pantryDeductions.isEmpty
        }?.id)
        let otherID = initiallyCoveredID == firstID ? secondID : firstID

        model.setMealPrepPantryOverride(lineID: initiallyCoveredID, buyFull: true)

        XCTAssertTrue(model.mealPrepPlan?.lines.first { $0.id == initiallyCoveredID }?.isBuyingFullQuantity == true)
        XCTAssertFalse(model.mealPrepPlan?.lines.first { $0.id == initiallyCoveredID }?.pantryDeductions.isEmpty == true)
        XCTAssertEqual(model.mealPrepPlan?.lines.first { $0.id == initiallyCoveredID }?.quantityToBuy, 1)
        XCTAssertEqual(model.mealPrepPlan?.lines.first { $0.id == otherID }?.quantityToBuy, 0)

        var depleted = stock
        depleted.remainingAmount = 0
        model.updatePantryItem(depleted)
        XCTAssertTrue(model.mealPrepPlan?.lines.first { $0.id == initiallyCoveredID }?.isBuyingFullQuantity == true)
        XCTAssertFalse(model.mealPrepPlan?.lines.first { $0.id == initiallyCoveredID }?.hasPantryChoice == true)
        XCTAssertEqual(model.mealPrepPlan?.lines.first { $0.id == otherID }?.quantityToBuy, 1)

        var restoredStock = stock
        restoredStock.remainingAmount = 1
        model.updatePantryItem(restoredStock)
        XCTAssertTrue(model.mealPrepPlan?.lines.first { $0.id == initiallyCoveredID }?.isBuyingFullQuantity == true)
        XCTAssertEqual(model.mealPrepPlan?.lines.first { $0.id == otherID }?.quantityToBuy, 0)

        let restored = AppModel(stateStore: store)
        XCTAssertTrue(restored.mealPrepPlan?.lines.first { $0.id == initiallyCoveredID }?.isBuyingFullQuantity == true)
        XCTAssertTrue(restored.mealPrepPlan?.lines.first { $0.id == initiallyCoveredID }?.hasPantryChoice == true)
        XCTAssertEqual(restored.mealPrepPlan?.lines.first { $0.id == otherID }?.quantityToBuy, 0)

        restored.setMealPrepPantryOverride(lineID: initiallyCoveredID, buyFull: false)
        XCTAssertFalse(
            restored.mealPrepPlan?.lines.first { $0.id == initiallyCoveredID }?.pantryDeductions.isEmpty == true
        )
    }

    @MainActor
    func testParsedOrAlternativeCanBeResolvedAndPlanCanProceed() throws {
        var dairy = ingredient("Milk or cream", 1, "cup")
        dairy.alternativeGroup = "milk or cream"
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Sauce", servings: 2, [dairy]), target: 2)
        ])

        XCTAssertTrue(model.buildMealPrepPlan())
        XCTAssertEqual(Set(model.mealPrepPlan?.lines.map(\.name) ?? []), ["Milk", "cream"])
        let milkID = try XCTUnwrap(model.mealPrepPlan?.lines.first { $0.name.lowercased() == "milk" }?.id)
        model.selectMealPrepAlternative(milkID)

        XCTAssertEqual(model.mealPrepPlan?.unresolvedReviewCount, 0)
        XCTAssertEqual(
            model.mealPrepPlan?.lines.first { $0.name.lowercased() == "milk" }?.mergeReviewState,
            .selectedAlternative
        )
        model.openMealPrepDashboard()
        XCTAssertEqual(model.homePath.last, .recipeReady)
    }

    @MainActor
    func testPantryRecomputesAfterQuantityAlternativeAndInventoryChanges() throws {
        var flour = ingredient("Flour", 2, "cup")
        flour.quantityReviewRequired = true
        var dairy = ingredient("Milk or cream", 1, "cup")
        dairy.alternativeGroup = "milk or cream"
        let flourStock = PantryInventoryItem(name: "Flour", remainingAmount: 1, remainingUnit: "cup")
        let milkStock = PantryInventoryItem(name: "Milk", remainingAmount: 1, remainingUnit: "cup")
        let model = AppModel(stateStore: InMemorySmartCartStateStore())
        model.pantryInventory = [flourStock, milkStock]
        model.mealPrepDraft = MealPrepDraft(selections: [
            selection(recipe("Bake", servings: 1, [flour, dairy]), target: 1)
        ])
        XCTAssertTrue(model.buildMealPrepPlan())

        let flourID = try XCTUnwrap(model.mealPrepPlan?.lines.first { $0.canonicalName == "flour" }?.id)
        XCTAssertEqual(model.mealPrepPlan?.lines.first { $0.id == flourID }?.quantityToBuy, 2)
        model.confirmMealPrepQuantity(flourID)
        XCTAssertNil(model.mealPrepPlan?.lines.first { $0.id == flourID }?.buyFullOverride)
        XCTAssertEqual(model.mealPrepPlan?.lines.first { $0.id == flourID }?.quantityToBuy, 2)
        model.setMealPrepPantryOverride(lineID: flourID, buyFull: false)
        XCTAssertEqual(model.mealPrepPlan?.lines.first { $0.id == flourID }?.quantityToBuy, 1)

        let milkID = try XCTUnwrap(model.mealPrepPlan?.lines.first { $0.name.lowercased() == "milk" }?.id)
        model.selectMealPrepAlternative(milkID)
        XCTAssertNil(model.mealPrepPlan?.lines.first { $0.id == milkID }?.buyFullOverride)
        XCTAssertEqual(model.mealPrepPlan?.lines.first { $0.id == milkID }?.quantityToBuy, 1)
        model.setMealPrepPantryOverride(lineID: milkID, buyFull: false)
        XCTAssertEqual(model.mealPrepPlan?.lines.first { $0.id == milkID }?.quantityToBuy, 0)

        var reducedFlour = flourStock
        reducedFlour.remainingAmount = 0.5
        model.updatePantryItem(reducedFlour)
        XCTAssertEqual(model.mealPrepPlan?.lines.first { $0.id == flourID }?.quantityToBuy, 1.5)
    }

    @MainActor
    func testReviewedMealPrepPlanRestoresWithoutLosingDecisions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartCart-ReviewedPlan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = JSONSmartCartStateStore(fileURL: directory.appendingPathComponent("state.json"))
        var dairy = ingredient("Milk or cream", 1, "cup")
        dairy.alternativeGroup = "milk or cream"
        let source = recipe("Sauce", servings: 2, [dairy])
        let model = AppModel(stateStore: store)
        model.mealPrepDraft = MealPrepDraft(selections: [selection(source, target: 6)])
        XCTAssertTrue(model.buildMealPrepPlan())
        let selectedID = try XCTUnwrap(model.mealPrepPlan?.lines.first { $0.name.lowercased() == "cream" }?.id)
        model.selectMealPrepAlternative(selectedID)
        let reviewedPlan = try XCTUnwrap(model.mealPrepPlan)

        let restored = AppModel(stateStore: store)
        restored.startMealPrepDraft()

        XCTAssertEqual(restored.mealPrepDraft?.selections.first?.targetServings, 6)
        XCTAssertEqual(restored.mealPrepPlan?.id, reviewedPlan.id)
        XCTAssertEqual(restored.mealPrepPlan?.title, reviewedPlan.title)
        XCTAssertEqual(restored.mealPrepPlan?.selections, reviewedPlan.selections)
        XCTAssertEqual(restored.mealPrepPlan?.lines, reviewedPlan.lines)
        XCTAssertEqual(
            restored.mealPrepPlan?.lines.first { $0.id == selectedID }?.mergeReviewState,
            .selectedAlternative
        )
        XCTAssertEqual(restored.homePath, [.mealPrepSelection, .recipeReady])
    }

    private func aggregate(_ selections: [MealPrepSelection]) throws -> MealPrepAggregationResult {
        try MealPrepAggregationService.aggregate(
            selections: selections,
            scope: .mealPrep(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        )
    }

    private func makeTemporaryJSONStore() throws -> JSONSmartCartStateStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartCart-MealPrepAlternatives-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return JSONSmartCartStateStore(fileURL: directory.appendingPathComponent("state.json"))
    }

    private func selection(_ recipe: Recipe, target: Double) -> MealPrepSelection {
        MealPrepSelection(recipe: recipe, targetServings: target)
    }

    private func ingredient(
        _ name: String,
        _ quantity: Double,
        _ unit: String,
        preparation: String = ""
    ) -> Ingredient {
        Ingredient(name: name, quantity: quantity, unit: unit, preparation: preparation)
    }

    private func recipe(_ title: String, servings: Int, _ ingredients: [Ingredient]) -> Recipe {
        Recipe(
            title: title,
            source: .text,
            sourceDetail: "Test",
            heroSymbol: "fork.knife",
            servings: servings,
            prepMinutes: 0,
            cookMinutes: 0,
            ingredients: ingredients
        )
    }
}

private final class ReleaseBlockerFailingStateStore: SmartCartStateStoring {
    enum Failure: Error { case requested }

    var state: SmartCartPersistedState?
    var failNextSave = false

    func load() throws -> SmartCartPersistedState? { state }

    func save(_ state: SmartCartPersistedState) throws {
        if failNextSave {
            failNextSave = false
            throw Failure.requested
        }
        self.state = state
    }
}
