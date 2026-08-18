import Foundation
import XCTest
@testable import SmartCart

final class TripIntelligenceContractTests: XCTestCase {
    private var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "contracts/fixtures/v1")
    }

    private func fixture(_ relativePath: String) throws -> Data {
        try Data(contentsOf: fixtureRoot.appending(path: relativePath))
    }

    func testDecodesSharedChickenParmesanGoldenFixtures() throws {
        let decoder = JSONDecoder()
        let ingredient = try decoder.decode(
            IngredientInputDTO.self,
            from: fixture("chicken-parmesan/ingredient-input.json")
        )
        let identity = try decoder.decode(
            TripIntelligenceEnvelopeDTO<IngredientIdentityResolutionDTO>.self,
            from: fixture("chicken-parmesan/identity-output.json")
        )
        let mass = try decoder.decode(
            TripIntelligenceEnvelopeDTO<IngredientMassEstimateDTO>.self,
            from: fixture("chicken-parmesan/mass-output.json")
        )
        let nutrition = try decoder.decode(
            TripIntelligenceEnvelopeDTO<IngredientNutritionResolutionDTO>.self,
            from: fixture("chicken-parmesan/nutrition-output.json")
        )
        let recipe = try decoder.decode(
            TripIntelligenceEnvelopeDTO<RecipeNutritionEstimateDTO>.self,
            from: fixture("chicken-parmesan/recipe-nutrition-output.json")
        )

        XCTAssertEqual(ingredient.name, "Parmesan cheese")
        XCTAssertEqual(ingredient.preparation, "finely grated")
        XCTAssertEqual(identity.data.retailerQuery, "Parmesan cheese")
        XCTAssertEqual(mass.data.massGrams?.preferred, 90)
        XCTAssertEqual(nutrition.data.nutrition?.proteinGrams.preferred, 33.3)
        XCTAssertEqual(recipe.data.perServing?.energyKilocalories.preferred, 94.5)
        XCTAssertEqual(recipe.schemaVersion, TripIntelligenceSchema.version)
    }

    func testBlankQuantityEncodesExplicitNullInsteadOfInventedOne() throws {
        let ingredient = Ingredient(
            rawText: "Salt",
            name: "Salt",
            quantity: 0,
            unit: ""
        )
        let dto = try IngredientInputDTO(
            ingredient: ingredient,
            includedInRecipe: true,
            includeInTrip: true
        )

        XCTAssertNil(dto.quantity)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as? [String: Any]
        )
        XCTAssertTrue(object["quantity"] is NSNull)
    }

    func testSemanticQuantitySurvivesModelAdapter() throws {
        let ingredient = Ingredient(
            rawText: "Olive oil, as needed",
            name: "Olive oil",
            quantity: 0,
            semanticQuantity: "as needed",
            unit: ""
        )

        let dto = try IngredientInputDTO(
            ingredient: ingredient,
            includedInRecipe: true,
            includeInTrip: false
        )

        XCTAssertEqual(dto.quantity, .semantic("as needed"))
        XCTAssertFalse(dto.includeInTrip)
        XCTAssertTrue(dto.includedInRecipe)
    }

    func testSourceImageBytesNeverCrossTransportBoundary() throws {
        let sourceEvidence = IngredientSourceEvidence(
            rawText: "1 cup Parmesan cheese",
            pageIndex: 0,
            boundingBox: nil,
            extractionStrategy: .visionOCR,
            ocrConfidence: 0.9,
            layoutConfidence: 0.9,
            parserConfidence: 0.9,
            normalizationConfidence: 0.9,
            alternateQuantityCandidates: [],
            sourceCropJPEGData: Data("private-image".utf8)
        )
        let ingredient = Ingredient(
            rawText: sourceEvidence.rawText,
            name: "Parmesan cheese",
            quantity: 1,
            unit: "cup",
            sourceEvidence: sourceEvidence
        )

        let dto = try IngredientInputDTO(
            ingredient: ingredient,
            includedInRecipe: true,
            includeInTrip: true
        )
        let encoded = try JSONEncoder().encode(dto)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(text.contains("private-image"))
        XCTAssertFalse(text.contains("sourceCropJPEGData"))
    }
}
