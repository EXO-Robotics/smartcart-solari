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
        let mealPrep = try decoder.decode(
            TripIntelligenceEnvelopeDTO<MealPrepNutritionEstimateDTO>.self,
            from: fixture("chicken-parmesan/meal-prep-nutrition-output.json")
        )

        XCTAssertEqual(ingredient.name, "Parmesan cheese")
        XCTAssertEqual(ingredient.preparation, "finely grated")
        XCTAssertEqual(identity.data.retailerQuery, "Parmesan cheese")
        XCTAssertEqual(mass.data.massGrams?.preferred, 90)
        XCTAssertEqual(nutrition.data.nutrition?.proteinGrams.preferred, 33.3)
        XCTAssertEqual(recipe.data.perServing?.energyKilocalories.preferred, 94.5)
        XCTAssertEqual(mealPrep.data.totalServings, 6)
        XCTAssertEqual(
            mealPrep.data.weightedAveragePerServing?.energyKilocalories.preferred,
            126
        )
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

    func testHandoffURLParserAcceptsOnlyExactClaimRoutesAndSealedToken() throws {
        let token = "v1." + String(repeating: "A", count: 37)
        XCTAssertEqual(
            SmartCartHandoffURLParser.parse(try XCTUnwrap(URL(string: "smartcart://claim#\(token)"))),
            .valid(token: token)
        )
        XCTAssertEqual(
            SmartCartHandoffURLParser.parse(
                try XCTUnwrap(
                    URL(string: "https://smartcart-barcode-api-omega.vercel.app/t#\(token)")
                )
            ),
            .valid(token: token)
        )
        XCTAssertEqual(
            SmartCartHandoffURLParser.parse(try XCTUnwrap(URL(string: "https://example.com/t#\(token)"))),
            .notSmartCartHandoff
        )
        XCTAssertEqual(
            SmartCartHandoffURLParser.parse(try XCTUnwrap(URL(string: "smartcart://claim/extra#\(token)"))),
            .invalid
        )
        XCTAssertEqual(
            SmartCartHandoffURLParser.parse(try XCTUnwrap(URL(string: "smartcart://claim/#\(token)"))),
            .invalid
        )
        XCTAssertEqual(
            SmartCartHandoffURLParser.parse(try XCTUnwrap(URL(string: "smartcart://claim?token=x#\(token)"))),
            .invalid
        )
        XCTAssertFalse(SmartCartHandoffURLParser.isValidToken("v1.not+base64url"))
        XCTAssertFalse(
            SmartCartHandoffURLParser.isValidToken(
                "v1." + String(repeating: "A", count: SmartCartHandoffURLParser.maximumTokenLength)
            )
        )
    }

    func testUniversalHandoffRejectsWrongHostPathQueryPortAndUserInfo() throws {
        let token = "v1." + String(repeating: "A", count: 37)
        let host = SmartCartHandoffURLParser.universalLinkHost
        let invalidURLs = [
            "https://\(host)/t/#\(token)",
            "https://\(host)/claim#\(token)",
            "https://\(host)/t?claim=1#\(token)",
            "https://\(host):443/t#\(token)",
            "https://user@\(host)/t#\(token)",
            "https://\(host)/t",
        ]
        for value in invalidURLs {
            XCTAssertEqual(
                SmartCartHandoffURLParser.parse(try XCTUnwrap(URL(string: value))),
                .invalid,
                value
            )
        }
        XCTAssertEqual(
            SmartCartHandoffURLParser.parse(
                try XCTUnwrap(URL(string: "http://\(host)/t#\(token)"))
            ),
            .notSmartCartHandoff
        )
        XCTAssertEqual(
            SmartCartHandoffURLParser.parse(
                try XCTUnwrap(URL(string: "https://evil.example/t#\(token)"))
            ),
            .notSmartCartHandoff
        )
    }

    func testHandoffClientPostsVersionedClaimEnvelopeWithStableRequestID() async throws {
        let requestID = UUID()
        let payload = makeHandoffPayload(
            recipes: [makeHandoffRecipe()],
            requestID: requestID
        )
        HandoffClaimURLProtocolStub.configure(responseData: try JSONEncoder().encode(payload))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HandoffClaimURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let token = "v1." + String(repeating: "A", count: 37)

        let result = try await SmartCartHandoffClient(
            baseURL: try XCTUnwrap(URL(string: "https://smartcart.example")),
            session: session
        ).claim(token: token, requestID: requestID)

        XCTAssertEqual(result, payload)
        let request = try XCTUnwrap(HandoffClaimURLProtocolStub.capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://smartcart.example/v1/handoffs/claim")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), requestID.uuidString)
        let body = try JSONDecoder().decode(
            TripIntelligenceRequestEnvelopeDTO<SmartCartHandoffClaimRequestDataDTO>.self,
            from: try XCTUnwrap(HandoffClaimURLProtocolStub.capturedBody)
        )
        XCTAssertEqual(body.schemaVersion, TripIntelligenceSchema.version)
        XCTAssertEqual(body.requestId, requestID)
        XCTAssertEqual(body.data.claimToken, token)
    }

    func testHandoffClientRejectsOversizedDeclaredResponseBeforeDecoding() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HandoffClaimURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        HandoffClaimURLProtocolStub.configure(
            responseData: Data("{}".utf8),
            responseHeaders: [
                "Content-Type": "application/json; charset=utf-8",
                "Content-Length": String(SmartCartHandoffClient.maximumResponseBytes + 1),
            ]
        )

        do {
            _ = try await SmartCartHandoffClient(
                baseURL: try XCTUnwrap(URL(string: "https://smartcart.example")),
                session: session
            ).claim(
                token: "v1." + String(repeating: "A", count: 37),
                requestID: UUID()
            )
            XCTFail("An oversized declared response must be rejected")
        } catch {
            XCTAssertEqual(error as? SmartCartHandoffClientError, .responseTooLarge)
        }
    }

    func testHandoffPayloadDecodesAndMapsBlankSemanticAndImageQuantitiesWithoutInventingOne() throws {
        let blankID = UUID()
        let semanticID = UUID()
        let numericID = UUID()
        let payload = makeHandoffPayload(recipes: [
            makeHandoffRecipe(
                sourceType: .imageTranscription,
                ingredients: [
                    makeIngredient(id: blankID, sourceText: "Salt", name: "Salt", quantity: nil),
                    makeIngredient(
                        id: semanticID,
                        sourceText: "Oil for frying",
                        name: "Oil",
                        quantity: .semantic("for frying")
                    ),
                    makeIngredient(
                        id: numericID,
                        sourceText: "1½ cups rice",
                        name: "Rice",
                        quantity: .numeric(value: 1.5, minimumValue: nil, unit: "cup")
                    )
                ],
                quantityReviewIDs: [numericID]
            )
        ])
        let decoded = try JSONDecoder().decode(
            SmartCartHandoffPayloadDTO.self,
            from: JSONEncoder().encode(payload)
        )
        let imported = try SmartCartHandoffSnapshotFactory.makeImport(from: decoded)
        let ingredients = try XCTUnwrap(imported.recipes.first).ingredients

        let blank = try XCTUnwrap(ingredients.first { $0.id == blankID })
        XCTAssertEqual(blank.quantity, 0)
        XCTAssertNil(blank.semanticQuantity)
        XCTAssertFalse(blank.quantityReviewRequired == true)

        let semantic = try XCTUnwrap(ingredients.first { $0.id == semanticID })
        XCTAssertEqual(semantic.quantity, 0)
        XCTAssertEqual(semantic.semanticQuantity, "for frying")
        XCTAssertFalse(semantic.quantityReviewRequired == true)

        let numeric = try XCTUnwrap(ingredients.first { $0.id == numericID })
        XCTAssertEqual(numeric.quantity, 1.5, accuracy: 0.000_001)
        XCTAssertTrue(numeric.quantityReviewRequired == true)
        XCTAssertEqual(numeric.sourceEvidence?.rawText, "1½ cups rice")
        XCTAssertEqual(numeric.sourceEvidence?.extractionStrategy, .visionOCR)
        XCTAssertEqual(numeric.sourceEvidence?.sourceObservationIDs, ["source-\(numericID.uuidString.lowercased())"])
        XCTAssertEqual(imported.recipes.first?.sourceDetail, "ChatGPT image transcription")
    }

    func testImageTranscriptionMustReviewEveryAndOnlyNumericQuantity() throws {
        let numericID = UUID()
        let missingReview = makeHandoffPayload(recipes: [
            makeHandoffRecipe(
                sourceType: .imageTranscription,
                ingredients: [
                    makeIngredient(
                        id: numericID,
                        sourceText: "2 cups flour",
                        name: "Flour",
                        quantity: .numeric(value: 2, minimumValue: nil, unit: "cup")
                    )
                ],
                quantityReviewIDs: []
            )
        ])

        XCTAssertThrowsError(try SmartCartHandoffSnapshotFactory.makeImport(from: missingReview)) {
            XCTAssertEqual(
                $0 as? SmartCartHandoffValidationError,
                .invalidQuantityReviewSet(recipeID: missingReview.data.recipes[0].analysis.data.recipeId)
            )
        }
    }

    func testHandoffRejectsMoreThanFiveRecipesAndDoesNotClampServings() throws {
        let sixRecipes = makeHandoffPayload(
            recipes: (0..<6).map { _ in makeHandoffRecipe(servings: 4) }
        )
        XCTAssertThrowsError(try SmartCartHandoffSnapshotFactory.makeImport(from: sixRecipes)) {
            XCTAssertEqual($0 as? SmartCartHandoffValidationError, .invalidRecipeCount)
        }

        let singleOverLimit = makeHandoffPayload(recipes: [makeHandoffRecipe(servings: 25)])
        XCTAssertThrowsError(try SmartCartHandoffSnapshotFactory.makeImport(from: singleOverLimit)) {
            XCTAssertEqual(
                $0 as? SmartCartHandoffValidationError,
                .invalidServings(recipeID: singleOverLimit.data.recipes[0].analysis.data.recipeId)
            )
        }

        let fractional = makeHandoffPayload(recipes: [makeHandoffRecipe(servings: 1.5)])
        XCTAssertThrowsError(try SmartCartHandoffSnapshotFactory.makeImport(from: fractional))
    }

    @MainActor
    func testSingleHandoffUsesDurableRecipeReadyBoundaryAndIsIdempotent() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, commerceDefaults: isolatedDefaults())
        let handoff = try SmartCartHandoffSnapshotFactory.makeImport(
            from: makeHandoffPayload(recipes: [makeHandoffRecipe(servings: 4)])
        )

        XCTAssertTrue(model.importSmartCartHandoff(handoff))
        XCTAssertTrue(model.importSmartCartHandoff(handoff))
        XCTAssertEqual(model.homePath, [.recipeReady])
        XCTAssertEqual(model.recipes.filter { $0.id == handoff.recipes[0].id }.count, 1)
        XCTAssertEqual(store.state?.activeRecipe.id, handoff.recipes[0].id)
    }

    @MainActor
    func testSingleHandoffReplayPreservesDurableCorrectionAndShoppingState() async throws {
        let store = InMemorySmartCartStateStore()
        let handoff = try SmartCartHandoffSnapshotFactory.makeImport(
            from: makeHandoffPayload(recipes: [makeHandoffRecipe(servings: 4)])
        )
        let firstModel = AppModel(stateStore: store, commerceDefaults: isolatedDefaults())
        XCTAssertTrue(firstModel.importSmartCartHandoff(handoff))

        var corrected = firstModel.activeRecipe.ingredients[0]
        corrected.name = "User-corrected brown rice"
        corrected.quantity = 2
        corrected.unit = "cups"
        XCTAssertTrue(firstModel.updateIngredient(id: corrected.id, with: corrected))
        firstModel.desiredServings = 7
        let session = ShoppingSession(
            recipeID: handoff.recipes[0].id,
            recipeTitle: firstModel.activeRecipe.title,
            storeID: "test-store",
            shoppingScope: .singleRecipe(handoff.recipes[0].id),
            items: []
        )
        firstModel.shoppingSessions = [session]
        firstModel.activeShoppingSessionID = session.id
        await firstModel.flushPendingPersistence()

        let restored = AppModel(stateStore: store, commerceDefaults: isolatedDefaults())
        XCTAssertTrue(restored.importSmartCartHandoff(handoff))
        XCTAssertEqual(restored.activeRecipe.ingredients[0].name, "User-corrected brown rice")
        XCTAssertEqual(restored.activeRecipe.ingredients[0].quantity, 2)
        XCTAssertEqual(restored.desiredServings, 7)
        XCTAssertEqual(restored.activeShoppingSessionID, session.id)
        XCTAssertEqual(restored.shoppingSessions, [session])
        XCTAssertEqual(restored.recipes.filter { $0.id == handoff.recipes[0].id }.count, 1)
        XCTAssertEqual(restored.homePath, [.recipeReady])
    }

    @MainActor
    func testMultiRecipeHandoffPersistsOneFreshMealPrepAndPreservesSemanticQuantity() throws {
        let semanticID = UUID()
        let first = makeHandoffRecipe(
            ingredients: [
                makeIngredient(
                    id: semanticID,
                    sourceText: "Oil as needed",
                    name: "Oil",
                    quantity: .semantic("as needed")
                )
            ]
        )
        let second = makeHandoffRecipe(servings: 6)
        let importPayload = try SmartCartHandoffSnapshotFactory.makeImport(
            from: makeHandoffPayload(recipes: [first, second])
        )
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, commerceDefaults: isolatedDefaults())

        XCTAssertTrue(model.importSmartCartHandoff(importPayload))
        XCTAssertTrue(model.importSmartCartHandoff(importPayload))
        XCTAssertEqual(model.homePath, [.mealPrepSelection, .recipeReady])
        XCTAssertEqual(model.mealPrepDraft?.id, importPayload.claimID)
        XCTAssertEqual(model.mealPrepDraft?.selections.count, 2)
        XCTAssertEqual(
            model.mealPrepDraft?.selections[0].recipeSnapshot.ingredients[0].semanticQuantity,
            "as needed"
        )
        XCTAssertTrue(model.ingredientsToBuy.contains { $0.semanticQuantity == "as needed" })

        let restored = AppModel(stateStore: store, commerceDefaults: isolatedDefaults())
        XCTAssertEqual(restored.mealPrepDraft?.id, importPayload.claimID)
        XCTAssertEqual(restored.mealPrepDraft?.selections.count, 2)
        XCTAssertEqual(
            restored.mealPrepDraft?.selections[0].recipeSnapshot.ingredients[0].semanticQuantity,
            "as needed"
        )
    }

    @MainActor
    func testMultiRecipeHandoffRejectsUnrelatedMealPrepWithoutReplacingIt() throws {
        let store = InMemorySmartCartStateStore()
        let model = AppModel(stateStore: store, commerceDefaults: isolatedDefaults())
        let first = try SmartCartHandoffSnapshotFactory.makeImport(
            from: makeHandoffPayload(recipes: [makeHandoffRecipe(), makeHandoffRecipe()])
        )
        XCTAssertTrue(model.importSmartCartHandoff(first))
        let originalDraft = try XCTUnwrap(model.mealPrepDraft)
        let originalPlan = try XCTUnwrap(model.mealPrepPlan)
        let originalRecipes = model.recipes

        let unrelated = try SmartCartHandoffSnapshotFactory.makeImport(
            from: makeHandoffPayload(recipes: [makeHandoffRecipe(), makeHandoffRecipe()])
        )
        XCTAssertFalse(model.importSmartCartHandoff(unrelated))
        XCTAssertEqual(model.mealPrepDraft, originalDraft)
        XCTAssertEqual(model.mealPrepPlan, originalPlan)
        XCTAssertEqual(model.recipes, originalRecipes)

        let startedSession = ShoppingSession(
            recipeID: originalDraft.selections[0].recipeSnapshot.id,
            recipeTitle: originalDraft.title,
            storeID: "test-store",
            shoppingScope: originalDraft.shoppingScope,
            mealPrepSnapshot: originalPlan,
            items: []
        )
        model.shoppingSessions = [startedSession]
        model.activeShoppingSessionID = startedSession.id

        let another = try SmartCartHandoffSnapshotFactory.makeImport(
            from: makeHandoffPayload(recipes: [makeHandoffRecipe(), makeHandoffRecipe()])
        )
        XCTAssertFalse(model.importSmartCartHandoff(another))
        XCTAssertEqual(model.mealPrepDraft, originalDraft)
        XCTAssertEqual(model.mealPrepPlan, originalPlan)
        XCTAssertEqual(model.shoppingSessions, [startedSession])
        XCTAssertEqual(model.activeShoppingSessionID, startedSession.id)
    }

    func testMealPrepSnapshotPreservesEvidenceMetadataWithoutDuplicatingJPEG() throws {
        let cropReference = IngredientSourceCropReference(
            sha256: String(repeating: "a", count: 64),
            byteCount: 1_024
        )
        let evidence = IngredientSourceEvidence(
            rawText: "1½ cups rice",
            pageIndex: 2,
            boundingBox: nil,
            extractionStrategy: .visionOCR,
            ocrConfidence: 0.88,
            layoutConfidence: 0.91,
            parserConfidence: 0.86,
            normalizationConfidence: 0.94,
            alternateQuantityCandidates: [1.5],
            alternateSourceTexts: ["1 1/2 cups rice"],
            sourceCropReference: cropReference,
            sourceCropJPEGData: Data("private-image".utf8),
            ocrColumnIndex: 1,
            sourceObservationIDs: ["observation-1"],
            continuationAttached: true,
            reconstructionConfidence: 0.84,
            originalLine: "1½ cups rice",
            removedSuffix: nil,
            reviewReasons: ["quantity_confirmation_required"]
        )
        let ingredient = Ingredient(
            rawText: evidence.rawText,
            name: "Rice",
            quantity: 1.5,
            unit: "cups",
            sourceEvidence: evidence,
            quantityReviewRequired: true
        )

        let frozen = FrozenMealPrepIngredient(ingredient: ingredient)
        XCTAssertEqual(frozen.sourceEvidence?.rawText, evidence.rawText)
        XCTAssertEqual(frozen.sourceEvidence?.pageIndex, 2)
        XCTAssertEqual(frozen.sourceEvidence?.sourceCropReference, cropReference)
        XCTAssertEqual(frozen.sourceEvidence?.sourceObservationIDs, ["observation-1"])
        XCTAssertEqual(frozen.sourceEvidence?.alternateSourceTexts, ["1 1/2 cups rice"])
        XCTAssertNil(frozen.sourceEvidence?.sourceCropJPEGData)
        let encoded = try JSONEncoder().encode(frozen)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("sourceCropJPEGData"))
    }

    @MainActor
    func testImageQuantitiesBlockSingleAndMealPrepUntilNativeConfirmation() throws {
        let firstNumericID = UUID()
        let first = makeHandoffRecipe(
            sourceType: .imageTranscription,
            ingredients: [
                makeIngredient(
                    id: firstNumericID,
                    sourceText: "1½ cups rice",
                    name: "Rice",
                    quantity: .numeric(value: 1.5, minimumValue: nil, unit: "cup")
                )
            ],
            quantityReviewIDs: [firstNumericID]
        )
        let single = try SmartCartHandoffSnapshotFactory.makeImport(
            from: makeHandoffPayload(recipes: [first])
        )
        let singleModel = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedDefaults()
        )
        XCTAssertTrue(singleModel.importSmartCartHandoff(single))
        XCTAssertEqual(singleModel.recipeReadyBlockingIssueCount, 1)
        XCTAssertFalse(singleModel.recipeReadyCanStartShopping)

        let secondNumericID = UUID()
        let second = makeHandoffRecipe(
            sourceType: .imageTranscription,
            ingredients: [
                makeIngredient(
                    id: secondNumericID,
                    sourceText: "2 cups beans",
                    name: "Beans",
                    quantity: .numeric(value: 2, minimumValue: nil, unit: "cup")
                )
            ],
            quantityReviewIDs: [secondNumericID]
        )
        let multi = try SmartCartHandoffSnapshotFactory.makeImport(
            from: makeHandoffPayload(recipes: [first, second])
        )
        let multiModel = AppModel(
            stateStore: InMemorySmartCartStateStore(),
            commerceDefaults: isolatedDefaults()
        )
        XCTAssertTrue(multiModel.importSmartCartHandoff(multi))
        XCTAssertEqual(multiModel.recipeReadyBlockingIssueCount, 2)
        XCTAssertFalse(multiModel.recipeReadyCanStartShopping)

        let blockedLineIDs = try XCTUnwrap(multiModel.mealPrepPlan).lines
            .filter { $0.mergeReviewReasons.contains(.uncertainQuantity) }
            .map(\.id)
        XCTAssertEqual(blockedLineIDs.count, 2)
        blockedLineIDs.forEach(multiModel.confirmMealPrepQuantity)
        XCTAssertEqual(multiModel.recipeReadyBlockingIssueCount, 0)
        XCTAssertTrue(multiModel.recipeReadyCanStartShopping)
        XCTAssertTrue(multiModel.ingredientsToBuy.allSatisfy { $0.quantityReviewRequired != true })
    }

    private func makeHandoffPayload(
        recipes: [SmartCartHandoffRecipeDTO],
        claimID: UUID = UUID(),
        requestID: UUID = UUID()
    ) -> SmartCartHandoffPayloadDTO {
        let now = Date()
        return SmartCartHandoffPayloadDTO(
            schemaVersion: TripIntelligenceSchema.version,
            resolverVersion: "smartcart-handoff-v1",
            requestId: requestID,
            data: SmartCartHandoffPayloadDataDTO(
                claimId: claimID,
                audience: "smartcart-ios",
                payloadDigest: String(repeating: "a", count: 64),
                issuedAt: internetDate(now.addingTimeInterval(-5)),
                expiresAt: internetDate(now.addingTimeInterval(300)),
                recipes: recipes
            )
        )
    }

    private func makeHandoffRecipe(
        sourceType: SmartCartHandoffSourceTypeDTO = .text,
        servings: Decimal = 4,
        ingredients: [IngredientInputDTO]? = nil,
        quantityReviewIDs: [UUID] = []
    ) -> SmartCartHandoffRecipeDTO {
        let recipeID = UUID()
        let resolvedIngredients = ingredients ?? [
            makeIngredient(
                sourceText: "1 cup rice",
                name: "Rice",
                quantity: .numeric(value: 1, minimumValue: nil, unit: "cup")
            )
        ]
        return SmartCartHandoffRecipeDTO(
            sourceType: sourceType,
            recipeText: resolvedIngredients.map(\.sourceText).joined(separator: "\n"),
            analysis: SmartCartRecipeAnalysisDTO(
                schemaVersion: TripIntelligenceSchema.version,
                resolverVersion: "recipe-text-v1",
                requestId: UUID(),
                data: SmartCartRecipeAnalysisDataDTO(
                    recipeId: recipeID,
                    title: "ChatGPT Recipe \(recipeID.uuidString.prefix(4))",
                    servings: servings,
                    ingredients: resolvedIngredients,
                    evidence: [],
                    issues: []
                )
            ),
            quantityReviewIngredientIds: quantityReviewIDs
        )
    }

    private func makeIngredient(
        id: UUID = UUID(),
        sourceText: String,
        name: String,
        quantity: IngredientQuantityInputDTO?
    ) -> IngredientInputDTO {
        IngredientInputDTO(
            ingredientId: id,
            sourceText: sourceText,
            name: name,
            preparation: "",
            quantity: quantity,
            includedInRecipe: true,
            includeInTrip: true,
            brandPreference: nil,
            evidence: [
                ResolutionEvidenceDTO(
                    evidenceId: "source-\(id.uuidString.lowercased())",
                    kind: .sourceText,
                    sourceName: "ChatGPT recipe text",
                    sourceVersion: nil,
                    sourceRecordId: nil,
                    description: "Original ingredient line."
                )
            ]
        )
    }

    private func internetDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "TripIntelligenceContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private final class HandoffClaimURLProtocolStub: URLProtocol {
    private static let lock = NSLock()
    private static var responseData = Data()
    private static var responseHeaders = ["Content-Type": "application/json; charset=utf-8"]
    private static var storedRequest: URLRequest?
    private static var storedBody: Data?

    static var capturedRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    static var capturedBody: Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedBody
    }

    static func configure(
        responseData: Data,
        responseHeaders: [String: String] = ["Content-Type": "application/json; charset=utf-8"]
    ) {
        lock.lock()
        self.responseData = responseData
        self.responseHeaders = responseHeaders
        storedRequest = nil
        storedBody = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let requestBody = request.httpBody ?? Self.readBody(from: request.httpBodyStream)
        Self.lock.lock()
        Self.storedRequest = request
        Self.storedBody = requestBody
        let data = Self.responseData
        let headers = Self.responseHeaders
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override func stopLoading() {}
}
