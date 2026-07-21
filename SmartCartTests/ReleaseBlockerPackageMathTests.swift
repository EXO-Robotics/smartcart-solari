import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import SmartCart

final class ReleaseBlockerPackageMathTests: XCTestCase {
    @MainActor
    func testMinimumInteractionGeometryRendersAtLeast44Points() {
        XCTAssertGreaterThanOrEqual(SmartCartTheme.minimumHitTargetDimension, 44)

        let host = UIHostingController(
            rootView: Button("Target probe") {}
                .smartCartMinimumHitTarget()
        )
        let renderedSize = host.sizeThatFits(
            in: CGSize(width: 320, height: 320)
        )

        XCTAssertGreaterThanOrEqual(renderedSize.width, 44)
        XCTAssertGreaterThanOrEqual(renderedSize.height, 44)
    }

    func testRequiredReversalAndScannerControlsRetainHitTargetModifier() throws {
        let mealPrepSource = try sourceText("SmartCart/Features/MealPrep/MealPrepViews.swift")
        let scannerSource = try sourceText("SmartCart/Features/Pantry/BarcodeScannerView.swift")

        XCTAssertTrue(mealPrepSource.contains("pantryChoice(\"Use Pantry\""))
        XCTAssertTrue(mealPrepSource.contains("pantryChoice(\"Buy Full\""))
        XCTAssertTrue(
            try sourceSection(
                mealPrepSource,
                from: "private func reviewAlternativesButton",
                through: "private func alternativeGroupName"
            ).contains(".smartCartMinimumHitTarget()")
        )
        XCTAssertTrue(
            try sourceSection(
                mealPrepSource,
                from: "private func pantryChoice",
                through: "private var sourceRecipes"
            ).contains(".smartCartMinimumHitTarget()")
        )
        XCTAssertTrue(
            try sourceSection(
                scannerSource,
                from: "private func amountButton",
                through: "private func barcodeProvenance"
            ).contains(".smartCartMinimumHitTarget()")
        )
    }

    func testCountRequestAgainstMassPackageIsUnresolvedWithoutInventingOnePackage() {
        let product = makeProduct(packageQuantity: 16, packageUnit: "oz")

        XCTAssertEqual(
            PackageMath.packageCount(
                product: product,
                requestedQuantity: 2,
                requestedUnit: "count"
            ),
            0
        )
        XCTAssertFalse(
            PackageMath.isPackageSufficient(
                product: product,
                requestedQuantity: 2,
                requestedUnit: "count"
            )
        )
    }

    func testSameDomainMassConversionStillRoundsUpCorrectly() {
        let product = makeProduct(packageQuantity: 16, packageUnit: "oz")

        XCTAssertEqual(
            PackageMath.packageCount(
                product: product,
                requestedQuantity: 1.5,
                requestedUnit: "lb"
            ),
            2
        )
        XCTAssertFalse(
            PackageMath.isPackageSufficient(
                product: product,
                requestedQuantity: 1.5,
                requestedUnit: "lb"
            )
        )
    }

    func testSameDomainVolumeConversionStillRoundsUpCorrectly() {
        let product = makeProduct(packageQuantity: 16, packageUnit: "fl oz")

        XCTAssertEqual(
            PackageMath.packageCount(
                product: product,
                requestedQuantity: 3,
                requestedUnit: "cups"
            ),
            2
        )
        XCTAssertFalse(
            PackageMath.isPackageSufficient(
                product: product,
                requestedQuantity: 3,
                requestedUnit: "cups"
            )
        )
    }

    func testNamedCountAliasIsTrustedOnlyForCountDestination() {
        let countProduct = makeProduct(packageQuantity: 8, packageUnit: "count")
        let massProduct = makeProduct(packageQuantity: 8, packageUnit: "oz")

        XCTAssertTrue(
            PackageMath.isPackageSufficient(
                product: countProduct,
                requestedQuantity: 2,
                requestedUnit: "cloves"
            )
        )
        XCTAssertEqual(
            PackageMath.packageCount(
                product: massProduct,
                requestedQuantity: 2,
                requestedUnit: "cloves"
            ),
            0
        )
        XCTAssertFalse(
            PackageMath.isPackageSufficient(
                product: massProduct,
                requestedQuantity: 2,
                requestedUnit: "cloves"
            )
        )
    }

    func testUnitlessRecipeCountUsesCountPackages() {
        let product = makeProduct(packageQuantity: 2, packageUnit: "count")

        XCTAssertEqual(
            PackageMath.packageCount(
                product: product,
                requestedQuantity: 5,
                requestedUnit: ""
            ),
            3
        )
        XCTAssertFalse(
            PackageMath.isPackageSufficient(
                product: product,
                requestedQuantity: 5,
                requestedUnit: ""
            )
        )
    }

    func testVariableWeightProductRequiresExplicitPackageConfirmation() {
        let product = makeProduct(
            packageQuantity: 1.5,
            packageUnit: "lb",
            variableWeight: true
        )

        XCTAssertNil(
            PackageMath.resolvedPackageCount(
                product: product,
                requestedQuantity: 3,
                requestedUnit: "lb"
            )
        )
        XCTAssertFalse(
            PackageMath.isPackageSufficient(
                product: product,
                requestedQuantity: 3,
                requestedUnit: "lb"
            )
        )
    }

    func testVisibleReplacementPolicyKeepsOnlyResolvableCandidatesInOrder() {
        let firstSafe = makeProduct(packageQuantity: 16, packageUnit: "oz")
        var crossDomain = makeProduct(packageQuantity: 8, packageUnit: "count")
        crossDomain.retailerProductID = "cross-domain"
        var missingMetadata = makeProduct(packageQuantity: 16, packageUnit: "oz")
        missingMetadata.retailerProductID = "missing-metadata"
        missingMetadata.packageQuantity = nil
        var variableWeight = makeProduct(
            packageQuantity: 1.5,
            packageUnit: "lb",
            variableWeight: true
        )
        variableWeight.retailerProductID = "variable-weight"
        var secondSafe = makeProduct(packageQuantity: 8, packageUnit: "oz")
        secondSafe.retailerProductID = "second-safe"

        let visible = ReplacementOptionPolicy.resolvedCandidates(
            from: [firstSafe, crossDomain, missingMetadata, variableWeight, secondSafe]
        ) { product in
            PackageMath.resolvedPackageCount(
                product: product,
                requestedQuantity: 1,
                requestedUnit: "lb"
            )
        }

        XCTAssertEqual(
            visible.map(\.retailerProductID),
            [firstSafe.retailerProductID, secondSafe.retailerProductID]
        )
    }

    func testVisibleReplacementPolicyReturnsEmptyWhenEveryCandidateIsUnsafe() {
        let variableWeight = makeProduct(
            packageQuantity: 1.5,
            packageUnit: "lb",
            variableWeight: true
        )
        let crossDomain = makeProduct(packageQuantity: 8, packageUnit: "count")

        let visible = ReplacementOptionPolicy.resolvedCandidates(
            from: [variableWeight, crossDomain]
        ) { product in
            PackageMath.resolvedPackageCount(
                product: product,
                requestedQuantity: 1,
                requestedUnit: "lb"
            )
        }

        XCTAssertTrue(visible.isEmpty)
    }

    func testEveryReconciliationReplacementRouteProducesConfirmedFeedback() throws {
        let itemID = UUID()
        let directProduct = makeProduct(packageQuantity: 16, packageUnit: "oz")
        let directRoute = ReplacementCompletionPolicy.route(
            for: directProduct,
            resolvedPackageCount: 2
        )
        guard case .direct(let directFacts) = directRoute else {
            return XCTFail("Resolvable product must complete directly")
        }
        let directFeedback = ReplacementFeedbackFactory.matchedProduct(
            originalItemID: itemID,
            product: directProduct,
            facts: directFacts,
            preferNextTime: true
        )
        XCTAssertEqual(directFeedback.replacementAmount, 2)
        XCTAssertEqual(directFeedback.packageQuantity, 16)

        var manualProduct = makeProduct(packageQuantity: 8, packageUnit: "count")
        manualProduct.packageQuantity = nil
        manualProduct.packageUnit = nil
        XCTAssertEqual(
            ReplacementCompletionPolicy.route(
                for: manualProduct,
                resolvedPackageCount: nil
            ),
            .packageConfirmation
        )
        let manualFacts = try XCTUnwrap(
            ReplacementPurchaseFacts.confirmedPackages(3, product: manualProduct)
        )
        let manualFeedback = ReplacementFeedbackFactory.matchedProduct(
            originalItemID: itemID,
            product: manualProduct,
            facts: manualFacts,
            preferNextTime: false
        )
        XCTAssertEqual(manualFeedback.replacementAmount, 3)
        XCTAssertNil(manualFeedback.packageQuantity)
        XCTAssertNil(manualFeedback.packageUnit)

        let variableProduct = makeProduct(
            packageQuantity: 1.5,
            packageUnit: "lb",
            variableWeight: true
        )
        XCTAssertEqual(
            ReplacementCompletionPolicy.route(
                for: variableProduct,
                resolvedPackageCount: nil
            ),
            .variableWeightConfirmation
        )
        let exactFacts = try XCTUnwrap(
            ReplacementPurchaseFacts.exactVariableWeight(
                packageCount: 2,
                actualTotalWeight: 3.2,
                unit: "lb"
            )
        )
        let exactFeedback = ReplacementFeedbackFactory.matchedProduct(
            originalItemID: itemID,
            product: variableProduct,
            facts: exactFacts,
            preferNextTime: false
        )
        XCTAssertEqual(exactFeedback.replacementAmount, 2)
        XCTAssertEqual(
            try XCTUnwrap(exactFeedback.packageQuantity),
            1.6,
            accuracy: 0.000_001
        )

        let unknownFacts = try XCTUnwrap(
            ReplacementPurchaseFacts.packagesWithUnknownMass(packageCount: 2)
        )
        let unknownFeedback = ReplacementFeedbackFactory.matchedProduct(
            originalItemID: itemID,
            product: variableProduct,
            facts: unknownFacts,
            preferNextTime: false
        )
        XCTAssertEqual(unknownFeedback.replacementAmount, 2)
        XCTAssertNil(unknownFeedback.packageQuantity)
        XCTAssertNil(unknownFeedback.packageUnit)

        let scannedFeedback = try XCTUnwrap(
            ReplacementFeedbackFactory.scannedProduct(
                originalItemID: itemID,
                name: "Scanned replacement",
                brand: "Receipt brand",
                retailerProductID: "scanned-product",
                gtin14: "00012345678905",
                packageCount: 4,
                preferNextTime: true
            )
        )
        XCTAssertEqual(scannedFeedback.replacementAmount, 4)
        XCTAssertEqual(scannedFeedback.replacementGTIN14, "00012345678905")
    }

    func testConfirmedVariableWeightUsesActualTotalNotNominalMidpoint() throws {
        let facts = try XCTUnwrap(
            ReplacementPurchaseFacts.exactVariableWeight(
                packageCount: 2,
                actualTotalWeight: 3.2,
                unit: "lb"
            )
        )
        let perPackageQuantity = try XCTUnwrap(facts.packageQuantity)

        XCTAssertEqual(facts.packageCount, 2)
        XCTAssertEqual(perPackageQuantity, 1.6, accuracy: 0.000_001)
        XCTAssertEqual(facts.packageUnit, "lb")
        XCTAssertEqual(
            facts.packageCount * perPackageQuantity,
            3.2,
            accuracy: 0.000_001
        )
    }

    func testUnknownVariableWeightOmitsMassMetadata() throws {
        let facts = try XCTUnwrap(
            ReplacementPurchaseFacts.packagesWithUnknownMass(packageCount: 2)
        )

        XCTAssertEqual(facts.packageCount, 2)
        XCTAssertNil(facts.packageQuantity)
        XCTAssertNil(facts.packageUnit)
    }

    func testUnknownVariableWeightCannotReduceExactPantryQuantity() throws {
        let pantryItem = PantryInventoryItem(
            name: "Chicken breast",
            quantity: 2,
            unit: "package",
            packageCount: 2,
            packageSize: nil,
            packageUnit: nil,
            hasUnknownPackageMass: true
        )
        var ingredient = Ingredient(
            name: "Chicken breast",
            quantity: 3,
            unit: "lb",
            category: .meat
        )
        ingredient.pantrySuggestion = try XCTUnwrap(
            PantryMatchingService.bestSuggestion(
                for: ingredient,
                requiredQuantity: 3,
                inventory: [pantryItem]
            )
        )
        ingredient.pantryDecision = .useAvailable

        XCTAssertEqual(ingredient.pantrySuggestion?.coverage, .possible)
        XCTAssertEqual(
            PantryMatchingService.quantityToBuy(for: ingredient, requiredQuantity: 3),
            3,
            accuracy: 0.000_001
        )
    }

    func testNominalVariableWeightCannotUseConfirmedPackageMapping() {
        let variableWeight = makeProduct(
            packageQuantity: 1.5,
            packageUnit: "lb",
            variableWeight: true
        )

        XCTAssertNil(
            ReplacementPurchaseFacts.confirmedPackages(1, product: variableWeight)
        )
    }

    @MainActor
    func testExactVariableWeightCommitsActualMassAndSurvivesJSONRelaunch() throws {
        let store = try makeTemporaryJSONStore()
        let model = AppModel(stateStore: store, seedDemoShoppingState: true)
        let item = try XCTUnwrap(model.shoppingItems.first)
        let sessionID = try XCTUnwrap(model.ensureCurrentShoppingSession())
        var replacement = makeProduct(
            packageQuantity: 1.5,
            packageUnit: "lb",
            variableWeight: true
        )
        replacement.retailerProductID = "actual-weight-replacement"
        let facts = try XCTUnwrap(
            ReplacementPurchaseFacts.exactVariableWeight(
                packageCount: 2,
                actualTotalWeight: 3.2,
                unit: "lb"
            )
        )
        let feedback = ReplacementFeedbackFactory.matchedProduct(
            originalItemID: item.id,
            product: replacement,
            facts: facts,
            preferNextTime: false
        )

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: [feedback]
        )

        let restored = AppModel(stateStore: store)
        let pantry = try XCTUnwrap(
            restored.pantryInventory.first(where: { $0.name == replacement.name })
        )
        XCTAssertEqual(pantry.packageCount, 2)
        XCTAssertEqual(try XCTUnwrap(pantry.packageSize), 1.6, accuracy: 0.000_001)
        XCTAssertEqual(pantry.packageUnit, "lb")
        XCTAssertEqual(try XCTUnwrap(pantry.remainingAmount), 3.2, accuracy: 0.000_001)
        XCTAssertEqual(pantry.remainingUnit, "lb")
        XCTAssertFalse(pantry.hasUnknownPackageMass == true)
    }

    @MainActor
    func testUnknownVariableWeightCommitsPackageOnlyAndStaysConservativeAfterJSONRelaunch() throws {
        let store = try makeTemporaryJSONStore()
        let model = AppModel(stateStore: store, seedDemoShoppingState: true)
        let item = try XCTUnwrap(model.shoppingItems.first)
        let sessionID = try XCTUnwrap(model.ensureCurrentShoppingSession())
        var replacement = makeProduct(
            packageQuantity: 1.5,
            packageUnit: "lb",
            variableWeight: true
        )
        replacement.retailerProductID = "unknown-weight-replacement"
        let facts = try XCTUnwrap(
            ReplacementPurchaseFacts.packagesWithUnknownMass(packageCount: 2)
        )
        let feedback = ReplacementFeedbackFactory.matchedProduct(
            originalItemID: item.id,
            product: replacement,
            facts: facts,
            preferNextTime: false
        )

        try model.commitShoppingReconciliation(
            sessionID: sessionID,
            outcome: .boughtFew,
            purchasedItemIDs: [item.id],
            substitutions: [feedback]
        )

        let restored = AppModel(stateStore: store)
        let pantry = try XCTUnwrap(
            restored.pantryInventory.first(where: { $0.name == replacement.name })
        )
        XCTAssertEqual(pantry.packageCount, 2)
        XCTAssertNil(pantry.packageSize)
        XCTAssertNil(pantry.packageUnit)
        XCTAssertEqual(pantry.remainingAmount, 2)
        XCTAssertEqual(pantry.remainingUnit, "package")
        XCTAssertTrue(pantry.hasUnknownPackageMass == true)

        var ingredient = Ingredient(
            name: replacement.name,
            quantity: 3,
            unit: "lb",
            category: .meat
        )
        ingredient.pantrySuggestion = try XCTUnwrap(
            PantryMatchingService.bestSuggestion(
                for: ingredient,
                requiredQuantity: 3,
                inventory: restored.pantryInventory
            )
        )
        ingredient.pantryDecision = .useAvailable
        XCTAssertEqual(ingredient.pantrySuggestion?.coverage, .possible)
        XCTAssertEqual(
            PantryMatchingService.quantityToBuy(for: ingredient, requiredQuantity: 3),
            3,
            accuracy: 0.000_001
        )
    }

    @MainActor
    func testReleaseCandidateEncodingAndClaimsRemainNutritionFree() throws {
        let model = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            seedDemoShoppingState: true
        )
        let recipe = model.activeRecipe
        let draft = MealPrepDraft(
            selections: [
                MealPrepSelection(
                    recipe: recipe,
                    targetServings: Double(recipe.servings)
                )
            ]
        )
        let plan = MealPrepPlanSnapshot(draft: draft, lines: [])
        let encodedRecipe = try JSONEncoder().encode(recipe)
        let encodedPlan = try JSONEncoder().encode(plan)
        let encodedText = String(decoding: encodedRecipe + encodedPlan, as: UTF8.self)
            .lowercased()
        XCTAssertFalse(encodedText.contains("nutrition"))

        for path in [
            "SmartCart/Models/Models.swift",
            "SmartCart/Models/MealPrepModels.swift",
            "SmartCart/Services/Persistence.swift",
            "CHANGELOG.md",
            "Docs/ROADMAP_STATUS.md",
            "Docs/SCHEMA_MIGRATION.md"
        ] {
            XCTAssertFalse(
                try sourceText(path).localizedCaseInsensitiveContains("nutrition"),
                "Nutrition-only persistence or release claim reappeared in \(path)"
            )
        }
    }

    private func makeProduct(
        packageQuantity: Double,
        packageUnit: String,
        variableWeight: Bool = false
    ) -> RetailerProductRecord {
        RetailerProductRecord(
            retailerID: "test-retailer",
            storeID: "test-store",
            retailerProductID: "test-product-\(packageUnit)",
            title: "Test Product",
            brand: "Test Brand",
            exactURL: URL(string: "https://example.com/product")!,
            packageDescription: "\(packageQuantity) \(packageUnit)",
            packageQuantity: packageQuantity,
            packageUnit: packageUnit,
            unitPriceText: "Price unavailable",
            priceType: .unavailable,
            availability: .unknown,
            fulfillmentMethods: [],
            organicStatus: .unknown,
            dataSource: .searchFallback,
            observedAt: Date(timeIntervalSince1970: 0),
            symbol: "cart",
            variableWeight: variableWeight
        )
    }

    private func makeTemporaryJSONStore() throws -> JSONSmartCartStateStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartCart-PackageTruthTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return JSONSmartCartStateStore(fileURL: directory.appendingPathComponent("state.json"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func sourceSection(
        _ source: String,
        from startMarker: String,
        through endMarker: String
    ) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }
}
