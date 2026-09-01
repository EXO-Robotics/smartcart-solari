import Foundation
import XCTest
@testable import SmartCart

final class SolariEvidenceContractTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_799_000_000)

    func testCompleteSupportedTripBuildsV3RequestWithoutWalmartIDs() throws {
        let plan = eligiblePlan(
            items: demoItems(),
            now: now,
            requestID: fixedUUID("10000000-0000-0000-0000-000000000001")
        )
        XCTAssertEqual(plan.request.schemaVersion, "solari-shopping-research-request-v3")
        XCTAssertEqual(plan.request.demoID, "owned-demo-grocer-basket-v3")
        XCTAssertEqual(plan.request.retailerID, "smartcart-demo-grocer")
        XCTAssertEqual(plan.request.storeReference, "smartcart-demo-grocer-owned-catalog-v2")
        XCTAssertEqual(plan.request.optimizationPolicy, .fixedV3)
        XCTAssertEqual(plan.request.requirements.count, 3)
        XCTAssertTrue(plan.request.requirements.allSatisfy { $0.candidateProductIDs.count == 2 })
        let encoded = try SolariRetailerResearchClient.encoder.encode(plan.request)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for walmartID in SolariResearchRequestBuilder.demoCandidateIDsByMatchedProductID.keys {
            XCTAssertFalse(text.contains(walmartID), "V3 request leaked Walmart ID \(walmartID)")
        }
        XCTAssertTrue(plan.request.requirements.flatMap(\.candidateProductIDs).allSatisfy { $0.hasPrefix("dg-") })
        XCTAssertTrue(plan.sourceURLsByProductID.values.allSatisfy {
            $0.absoluteString.hasPrefix("https://exo-robotics.github.io/smartcart-solari/website/solari-demo/retailer/product/")
        })
    }

    func testPlanFingerprintIsDeterministicAndBindsReviewedPlanNotTransportMetadata() throws {
        let items = demoItems()
        let first = eligiblePlan(
            items: items,
            now: now,
            requestID: fixedUUID("10000000-0000-0000-0000-000000000001")
        )
        let second = eligiblePlan(
            items: items.reversed(),
            now: now.addingTimeInterval(60),
            requestID: fixedUUID("10000000-0000-0000-0000-000000000002")
        )
        XCTAssertEqual(first.fingerprint, second.fingerprint)

        var changed = items
        changed[0].requestedAmount = 2
        XCTAssertEqual(
            SolariResearchRequestBuilder.evaluate(
                items: changed,
                configuration: configuration(),
                servingCount: 4,
                now: now,
                requestID: first.request.requestID
            ),
            .ineligible([.canonicalRequirementMismatch(
                name: "Boneless chicken breast",
                expected: "a chicken requirement of exactly 1.5 lb"
            )])
        )
        XCTAssertFalse(SolariResearchRequestBuilder.matchesCurrentPlan(first, items: changed, servingCount: 4))
    }

    func testExplicitIneligibilityReasonsCoverBoundsAndUnsupportedCatalog() {
        XCTAssertEqual(
            SolariResearchRequestBuilder.evaluate(
                items: Array(demoItems().prefix(2)),
                configuration: configuration(),
                servingCount: 4
            ),
            .ineligible([.requiresCompleteDemoTrip(2)])
        )
        var tooMany = demoItems()
        tooMany.append(demoItems()[0].withFreshIdentity())
        XCTAssertEqual(
            SolariResearchRequestBuilder.evaluate(
                items: tooMany,
                configuration: configuration(),
                servingCount: 4
            ),
            .ineligible([.tooManyWaitingItems(4)])
        )

        let unsupported = item(
            id: fixedUUID("20000000-0000-0000-0000-000000000099"),
            name: "Fresh basil",
            amount: 1,
            unit: "oz",
            products: [product(id: "unsupported")]
        )
        var unsupportedTrip = demoItems()
        unsupportedTrip[2] = unsupported
        XCTAssertEqual(
            SolariResearchRequestBuilder.evaluate(
                items: unsupportedTrip,
                configuration: configuration(),
                servingCount: 4
            ),
            .ineligible([.unsupportedProduct("Fresh basil")])
        )

        var mislabeled = demoItems()
        mislabeled[1] = item(
            id: fixedUUID("20000000-0000-0000-0000-000000000002"),
            name: "White rice",
            amount: 12,
            unit: "oz",
            products: [product(id: "10534084"), product(id: "623835750")]
        )
        XCTAssertEqual(
            SolariResearchRequestBuilder.evaluate(
                items: mislabeled,
                configuration: configuration(),
                servingCount: 4
            ),
            .ineligible([.canonicalRequirementMismatch(
                name: "White rice",
                expected: "a penne or pasta requirement of exactly 12 oz"
            )])
        )
    }

    func testEncodedRequestContainsOnlyCandidateIDsAndNoSourceOrCredentialMaterial() throws {
        let plan = eligiblePlan(items: demoItems(), now: now)
        let data = try SolariRetailerResearchClient.encoder.encode(plan.request)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8)).lowercased()
        XCTAssertTrue(text.contains("candidateproductids"))
        XCTAssertFalse(text.contains("sourceurl"))
        XCTAssertFalse(text.contains("cookie"))
        XCTAssertFalse(text.contains("credential"))
        XCTAssertFalse(text.contains("account"))
        XCTAssertFalse(text.contains("session"))
        XCTAssertFalse(text.contains("solari_api_key"))
    }

    func testRequestIDEncodesAsLowercaseForLetterBearingUUID() throws {
        let requestID = fixedUUID("ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF")
        let plan = eligiblePlan(items: demoItems(), now: now, requestID: requestID)
        let data = try SolariRetailerResearchClient.encoder.encode(plan.request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(
            object["requestID"] as? String,
            "abcdefab-cdef-4abc-8def-abcdefabcdef"
        )
        XCTAssertFalse(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("ABCDEF"))

        let decoded = try SolariRetailerResearchClient.decoder.decode(SolariResearchRequest.self, from: data)
        XCTAssertEqual(decoded.requestID, requestID)
    }

    func testConfigurationDerivesExactOwnedSourceAndRejectsCredentialsOrHTTP() {
        let configuration = configuration()
        XCTAssertEqual(
            configuration.sourceURL(for: "dg-chicken-rightsize-1lb")?.absoluteString,
            "https://exo-robotics.github.io/smartcart-solari/website/solari-demo/retailer/product/dg-chicken-rightsize-1lb.html"
        )
        XCTAssertNil(configuration.sourceURL(for: "unknown"))
        XCTAssertNil(SolariBackendConfiguration(
            backendRawValue: "https://user:secret@example.com",
            demoRetailerRawValue: "https://example.com/demo"
        ))
        XCTAssertNil(SolariBackendConfiguration(
            backendRawValue: "http://example.com",
            demoRetailerRawValue: "https://example.com/demo"
        ))
        XCTAssertNil(SolariBackendConfiguration(
            backendRawValue: "https://example.com",
            demoRetailerRawValue: "http://example.com/demo"
        ))
    }

    func testValidatorAcceptsNonGreedySandboxChoiceWithoutRecomputingGlobalArgmin() throws {
        let plan = eligiblePlan(items: demoItems(), now: now)
        let validated = try SolariEvidenceValidator(now: now).validate(result(for: plan), for: plan)
        XCTAssertEqual(validated.result.basket.observedSubtotal, Decimal(string: "13.32"))
        XCTAssertEqual(validated.result.comparison.premiumOverCheapest, Decimal(string: "0.53"))
        XCTAssertEqual(validated.result.comparison.surplusAvoidedOunces, 16)
        XCTAssertEqual(validated.result.provenance.accessBoundary, .appleAppAttest)
        XCTAssertEqual(validated.result.optimizer.method, .sandbox)
        XCTAssertEqual(validated.result.optimizer.authority, .sandbox)
        XCTAssertEqual(validated.result.optimizer.verification, .smartCartPolicyInvariants)
    }

    func testValidatorRejectsV3ComparisonMetricTampering() throws {
        let plan = eligiblePlan(items: demoItems(), now: now)
        let original = result(for: plan)
        let invalidComparison = SolariBasketComparison(
            cheapestAdequateSubtotal: original.comparison.cheapestAdequateSubtotal,
            selectedSubtotal: original.comparison.selectedSubtotal,
            premiumOverCheapest: Decimal(string: "0.54")!,
            cheapestAggregateSurplusOunces: original.comparison.cheapestAggregateSurplusOunces,
            selectedAggregateSurplusOunces: 14,
            surplusAvoidedOunces: original.comparison.surplusAvoidedOunces,
            maxPremiumOverCheapest: original.comparison.maxPremiumOverCheapest,
            currency: original.comparison.currency
        )

        XCTAssertThrowsError(
            try SolariEvidenceValidator(now: now).validate(
                replacing(original, comparison: invalidComparison),
                for: plan
            )
        ) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidComparison)
        }
    }

    func testValidatorRejectsSelectedDecisionSurplusTampering() throws {
        let plan = eligiblePlan(items: demoItems(), now: now)
        let original = result(for: plan)
        let decision = original.decisions[0]
        let invalidDecision = SolariBasketDecision(
            schemaVersion: decision.schemaVersion,
            requirementID: decision.requirementID,
            observationID: decision.observationID,
            packageCount: decision.packageCount,
            requiredQuantity: decision.requiredQuantity,
            coveredQuantity: decision.coveredQuantity,
            quantityUnit: decision.quantityUnit,
            surplusQuantity: decision.surplusQuantity,
            surplusOunces: decision.surplusOunces + 1,
            lineTotal: decision.lineTotal,
            currency: decision.currency,
            proteinGramsPerDollar: decision.proteinGramsPerDollar,
            substitutionNote: decision.substitutionNote,
            rationale: decision.rationale,
            confidence: decision.confidence,
            ambiguityReasons: decision.ambiguityReasons
        )
        var decisions = original.decisions
        decisions[0] = invalidDecision

        XCTAssertThrowsError(
            try SolariEvidenceValidator(now: now).validate(
                replacing(original, decisions: decisions),
                for: plan
            )
        ) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidPackageMath)
        }
    }

    func testValidatorBindsFreshnessAgeToObservedTimestampAndClaimedMaximum() throws {
        let plan = eligiblePlan(items: demoItems(), now: now)
        let original = result(for: plan)
        let observation = original.observations[0]

        var mismatchedAgeObservations = original.observations
        mismatchedAgeObservations[0] = replacing(
            observation,
            observedAt: now.addingTimeInterval(-120),
            freshness: .init(status: .fresh, ageSeconds: 5, maxAgeSeconds: 86_400)
        )
        XCTAssertThrowsError(
            try SolariEvidenceValidator(now: now).validate(
                replacing(original, observations: mismatchedAgeObservations),
                for: plan
            )
        ) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .staleObservation)
        }

        var overMaximumObservations = original.observations
        overMaximumObservations[0] = replacing(
            observation,
            observedAt: now.addingTimeInterval(-120),
            freshness: .init(status: .fresh, ageSeconds: 120, maxAgeSeconds: 60)
        )
        XCTAssertThrowsError(
            try SolariEvidenceValidator(now: now).validate(
                replacing(original, observations: overMaximumObservations),
                for: plan
            )
        ) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .staleObservation)
        }
    }

    func testValidatorAllowsSubstitutionNoteOnlyWhenItExactlyMatchesSelectedAmbiguity() throws {
        let plan = eligiblePlan(items: demoItems(), now: now)
        let original = result(for: plan)
        let ambiguity = "Package labeling may require confirmation."
        let selectedDecisionIndex = 0
        let selectedDecision = original.decisions[selectedDecisionIndex]
        let selectedObservationIndex = try XCTUnwrap(original.observations.firstIndex {
            $0.observationID == selectedDecision.observationID
        })
        let matchingObservation = replacing(
            original.observations[selectedObservationIndex],
            ambiguityReasons: [ambiguity]
        )
        var observations = original.observations
        observations[selectedObservationIndex] = matchingObservation

        var decisions = original.decisions
        decisions[selectedDecisionIndex] = replacing(
            decisions[selectedDecisionIndex],
            substitutionNote: ambiguity,
            ambiguityReasons: [ambiguity]
        )
        XCTAssertNoThrow(
            try SolariEvidenceValidator(now: now).validate(
                replacing(replacing(original, observations: observations), decisions: decisions),
                for: plan
            )
        )

        decisions[selectedDecisionIndex] = replacing(
            decisions[selectedDecisionIndex],
            substitutionNote: "A different unsupported note.",
            ambiguityReasons: [ambiguity]
        )
        XCTAssertThrowsError(
            try SolariEvidenceValidator(now: now).validate(
                replacing(replacing(original, observations: observations), decisions: decisions),
                for: plan
            )
        ) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidPackageMath)
        }
    }

    func testSelectedEvidenceHandoffUsesExactOwnedDemoSourcesAndNeverTransfersToConfiguredRetailer() throws {
        let plan = eligiblePlan(items: demoItems(), now: now)
        let validated = try SolariEvidenceValidator(now: now).validate(result(for: plan), for: plan)
        let handoff = SolariEvidenceHandoff(result: validated.result)

        XCTAssertEqual(handoff.retailerID, "smartcart-demo-grocer")
        XCTAssertFalse(handoff.transfersToConfiguredRetailer)
        XCTAssertEqual(Set(handoff.selectedSourceURLs), Set([
            configuration().sourceURL(for: "dg-chicken-rightsize-1lb")!,
            configuration().sourceURL(for: "dg-penne-value-16oz")!,
            configuration().sourceURL(for: "dg-parmesan-value-6oz")!
        ]))
        XCTAssertTrue(handoff.selectedSourceURLs.allSatisfy {
            $0.host == "exo-robotics.github.io" && $0.path.contains("/solari-demo/retailer/product/dg-")
        })
    }

    func testOriginalSmartCartContinuationRevalidatesAndNeverTransfersDemoSelections() throws {
        let items = demoItems()
        let plan = eligiblePlan(items: items, now: now)
        let research = try SolariEvidenceValidator(now: now).validate(result(for: plan), for: plan)
        let originalProductIDs = items.map(\.product.retailerProductID)
        let demoProductIDs = research.result.observations.map(\.retailerProductID)

        XCTAssertTrue(SolariOriginalSmartCartContinuation.permitsFinalization(
            plan: plan,
            research: research,
            items: items,
            servingCount: 4
        ))
        XCTAssertEqual(items.map(\.product.retailerProductID), originalProductIDs)
        XCTAssertTrue(Set(originalProductIDs).isDisjoint(with: Set(demoProductIDs)))
        XCTAssertTrue(plan.originalSmartCartSelections.allSatisfy {
            originalProductIDs.contains($0.retailerProductID) &&
                !SolariResearchRequestBuilder.supportedProductIDs.contains($0.retailerProductID)
        })

        var changed = items
        changed[0].requestedAmount = 2
        XCTAssertFalse(SolariOriginalSmartCartContinuation.permitsFinalization(
            plan: plan,
            research: research,
            items: changed,
            servingCount: 4
        ))
    }

    func testValidatorRejectsMismatchedDerivedSourceURL() throws {
        let plan = eligiblePlan(items: demoItems(), now: now)
        let original = result(for: plan)
        let observation = original.observations[0]
        let invalid = SolariRetailerObservation(
            schemaVersion: observation.schemaVersion,
            observationID: observation.observationID,
            requirementID: observation.requirementID,
            retailerProductID: observation.retailerProductID,
            sourceURL: URL(string: "https://evil.example/product")!,
            title: observation.title,
            packageDescription: observation.packageDescription,
            packageQuantity: observation.packageQuantity,
            packageUnit: observation.packageUnit,
            visiblePrice: observation.visiblePrice,
            currency: observation.currency,
            observedAt: observation.observedAt,
            confidence: observation.confidence,
            ambiguityReasons: observation.ambiguityReasons,
            proteinGramsPerPackage: observation.proteinGramsPerPackage,
            collectionMethod: observation.collectionMethod,
            location: observation.location,
            catalogEra: observation.catalogEra,
            syntheticPrice: observation.syntheticPrice,
            freshness: observation.freshness
        )
        var observations = original.observations
        observations[0] = invalid
        let mutated = replacing(original, observations: observations)
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(mutated, for: plan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidObservationReference)
        }
    }

    func testValidatorRejectsInvalidTrustBoundary() throws {
        let plan = eligiblePlan(items: demoItems(), now: now)
        let original = result(for: plan)
        let invalidTrust = SolariTrustBoundary(
            priceClaim: .observedNotGuaranteed,
            accountAccessed: true,
            cartModified: false,
            checkoutAutomated: false,
            userControlsHandoff: true,
            limitations: ["Visible test prices are not guaranteed."]
        )
        let mutated = SolariResearchResult(
            schemaVersion: original.schemaVersion,
            requestID: original.requestID,
            demoID: original.demoID,
            retailerID: original.retailerID,
            completedAt: original.completedAt,
            executionMode: original.executionMode,
            status: original.status,
            observations: original.observations,
            decisions: original.decisions,
            basket: original.basket,
            comparison: original.comparison,
            optimizer: original.optimizer,
            provenance: original.provenance,
            trust: invalidTrust
        )
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(mutated, for: plan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidProvenance)
        }
    }

    func testMemoryCacheExpiresAndRefreshBypassesWithoutPersistence() {
        let plan = eligiblePlan(items: demoItems(), now: now)
        let research = SolariValidatedResearch(result: result(for: plan), warnings: [])
        var cache = SolariValidatedResearchCache(timeToLive: 60)
        cache.insert(research, for: plan.fingerprint, now: now)
        XCTAssertNotNil(cache.value(for: plan.fingerprint, now: now.addingTimeInterval(59)))
        XCTAssertNil(cache.value(for: plan.fingerprint, now: now.addingTimeInterval(30), bypass: true))
        XCTAssertNil(cache.value(for: plan.fingerprint, now: now.addingTimeInterval(61)))
    }

    func testAppAttestAssertionHashBindsChallengeAndExactBodyBytes() {
        let challengeBase64URL = "q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s"
        let first = SolariAppAttestClient.assertionClientDataHash(
            challengeBase64URL: challengeBase64URL,
            exactResearchBody: Data("{\"a\":1}".utf8)
        )
        let second = SolariAppAttestClient.assertionClientDataHash(
            challengeBase64URL: challengeBase64URL,
            exactResearchBody: Data("{\"a\":1 }".utf8)
        )
        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(
            first.map { String(format: "%02x", $0) }.joined(),
            "60e66913e5f0c2a399818f3c18fc4853f726e32b7f4554038a04c3037e360d1f"
        )
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(
            SolariAppAttestClient.attestationClientDataHash(challenge: Data(repeating: 0xAB, count: 32)).count,
            32
        )
    }

    func testAppAttestKeyIdentifierRequiresCanonicalStandardPaddedBase64() {
        let standardPadded = Data(repeating: 0xFB, count: 32).base64EncodedString()
        XCTAssertTrue(standardPadded.contains("+"))
        XCTAssertTrue(standardPadded.hasSuffix("="))
        XCTAssertTrue(SolariAppAttestClient.isValidKeyID(standardPadded))
        XCTAssertFalse(SolariAppAttestClient.isValidKeyID(String(standardPadded.dropLast())))
        XCTAssertFalse(SolariAppAttestClient.isValidKeyID(
            standardPadded.replacingOccurrences(of: "+", with: "-")
        ))
    }

    func testResearchTransportUsesJSONEnvelopeWithExactPayloadAndNoAttestHeaders() throws {
        let payload = Data("{\"schemaVersion\":\"solari-shopping-research-request-v3\"}".utf8)
        let keyID = Data(repeating: 0xFB, count: 32).base64EncodedString()
        let assertion = Data([0x01, 0x02, 0x03, 0xFE])
        let challengeID = fixedUUID("30000000-0000-0000-0000-000000000001")
        let request = try SolariRetailerResearchClient.researchRequest(
            exactBody: payload,
            authorization: SolariAppAttestAuthorization(
                keyID: keyID,
                challengeID: challengeID,
                assertion: assertion
            ),
            endpoint: URL(string: "https://example.com/v1/solari/research")!
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-smartcart-app-attest-key-id"))
        XCTAssertNil(request.value(forHTTPHeaderField: "x-smartcart-app-attest-challenge-id"))
        XCTAssertNil(request.value(forHTTPHeaderField: "x-smartcart-app-attest-assertion"))

        let envelope = try SolariRetailerResearchClient.decoder.decode(
            SolariAppAttestResearchEnvelope.self,
            from: try XCTUnwrap(request.httpBody)
        )
        XCTAssertEqual(envelope.schemaVersion, "solari-app-attest-research-envelope-v1")
        XCTAssertEqual(envelope.challengeID, challengeID)
        XCTAssertEqual(envelope.keyID, keyID)
        XCTAssertEqual(Data(base64Encoded: envelope.assertionObject), assertion)
        XCTAssertEqual(Data(base64Encoded: envelope.payloadBase64), payload)
    }

    func testDebugRecordedReplayIsClearlyNonLiveAndDoesNotClaimSolariOrAppAttestRan() throws {
        let fixtureConfiguration = SolariBackendConfiguration(
            backendRawValue: "https://smartcart-solari-beta.example.com",
            demoRetailerRawValue: "https://exo-robotics.github.io/smartcart-solari/website/solari-demo",
            debugFixtureReplayEnabled: true
        )!
        let eligibility = SolariResearchRequestBuilder.evaluate(
            items: demoItems(),
            configuration: fixtureConfiguration,
            servingCount: 4,
            now: now
        )
        guard case .eligible(let plan) = eligibility else { return XCTFail("Fixture plan was ineligible") }
        XCTAssertEqual(plan.request.executionMode, .recordedFixture)

        let replay = try SolariDebugRecordedFixture.make(for: plan)
        XCTAssertEqual(replay.result.executionMode, .recordedFixture)
        XCTAssertEqual(replay.result.provenance.browser, .notRunFixture)
        XCTAssertEqual(replay.result.provenance.sandbox, .notRunFixture)
        XCTAssertEqual(replay.result.provenance.accessBoundary, .notUsedRecordedFixture)
        XCTAssertEqual(replay.result.trust.priceClaim, .recordedFixtureNotLive)
        XCTAssertEqual(replay.result.basket.observedSubtotal, Decimal(string: "13.32"))
        XCTAssertEqual(replay.result.comparison.cheapestAdequateSubtotal, Decimal(string: "12.79"))
        XCTAssertEqual(replay.result.comparison.premiumOverCheapest, Decimal(string: "0.53"))
        XCTAssertEqual(replay.result.comparison.selectedAggregateSurplusOunces, 15)
        XCTAssertEqual(replay.result.comparison.surplusAvoidedOunces, 16)
        XCTAssertEqual(replay.result.optimizer.authority, .notRunFixture)
        XCTAssertEqual(replay.result.optimizer.verification, .notRunFixture)
        XCTAssertTrue(replay.warnings.contains(where: { $0.contains("did not run") }))
    }

    private func eligiblePlan(
        items: [ShoppingListItem],
        now: Date,
        requestID: UUID = UUID()
    ) -> SolariResearchPlan {
        let eligibility = SolariResearchRequestBuilder.evaluate(
            items: items,
            configuration: configuration(),
            servingCount: 4,
            now: now,
            requestID: requestID
        )
        guard case .eligible(let plan) = eligibility else {
            fatalError("Test plan unexpectedly ineligible")
        }
        return plan
    }

    private func result(for plan: SolariResearchPlan) -> SolariResearchResult {
        var observations: [SolariRetailerObservation] = []
        var decisions: [SolariBasketDecision] = []
        var selectedSubtotal: Decimal = 0
        var cheapestSubtotal: Decimal = 0
        var selectedSurplusOunces = 0.0
        var cheapestSurplusOunces = 0.0

        for requirement in plan.request.requirements {
            let products = requirement.candidateProductIDs.map(testProduct)
            let candidateObservations = products.map { product in
                SolariRetailerObservation(
                    schemaVersion: SolariRetailerEvidenceSchema.observationVersion,
                    observationID: "obs-\(product.id)",
                    requirementID: requirement.id,
                    retailerProductID: product.id,
                    sourceURL: plan.sourceURLsByProductID[product.id]!,
                    title: product.title,
                    packageDescription: "\(product.quantity.formatted()) \(product.unit.rawValue) synthetic package",
                    packageQuantity: product.quantity,
                    packageUnit: product.unit,
                    visiblePrice: product.price,
                    currency: "USD",
                    observedAt: now.addingTimeInterval(-5),
                    confidence: .high,
                    ambiguityReasons: [],
                    proteinGramsPerPackage: nil,
                    collectionMethod: .controlledDemo,
                    location: .controlledDemo,
                    catalogEra: "current-v3",
                    syntheticPrice: true,
                    freshness: SolariObservationFreshness(status: .fresh, ageSeconds: 5, maxAgeSeconds: 86_400)
                )
            }
            observations.append(contentsOf: candidateObservations)

            let requiredOunces = requirement.requiredQuantity * unitScale(requirement.unit.evidenceUnit)
            let adequate = products.map { product -> (product: TestProduct, count: Int, total: Decimal, surplus: Double) in
                let packageOunces = product.quantity * unitScale(product.unit)
                let count = max(1, Int(ceil(requiredOunces / packageOunces)))
                return (product, count, product.price * Decimal(count), packageOunces * Double(count) - requiredOunces)
            }
            let cheapest = adequate.min {
                if $0.total != $1.total { return $0.total < $1.total }
                return $0.product.id < $1.product.id
            }!
            let selectedID = selectedProductID(for: requirement)
            let selected = adequate.first(where: { $0.product.id == selectedID })!
            let observation = candidateObservations.first(where: { $0.retailerProductID == selectedID })!
            let scale = unitScale(selected.product.unit)
            selectedSubtotal += selected.total
            cheapestSubtotal += cheapest.total
            selectedSurplusOunces += selected.surplus
            cheapestSurplusOunces += cheapest.surplus
            decisions.append(
                SolariBasketDecision(
                    schemaVersion: SolariRetailerEvidenceSchema.decisionVersion,
                    requirementID: requirement.id,
                    observationID: observation.observationID,
                    packageCount: selected.count,
                    requiredQuantity: requirement.requiredQuantity,
                    coveredQuantity: selected.product.quantity * Double(selected.count),
                    quantityUnit: selected.product.unit,
                    surplusQuantity: selected.surplus / scale,
                    surplusOunces: selected.surplus,
                    lineTotal: selected.total,
                    currency: "USD",
                    proteinGramsPerDollar: nil,
                    substitutionNote: nil,
                    rationale: ["Sandbox selected the low-surplus basket inside the shared premium cap."],
                    confidence: .high,
                    ambiguityReasons: []
                )
            )
        }
        return SolariResearchResult(
            schemaVersion: SolariRetailerEvidenceSchema.resultVersion,
            requestID: plan.request.requestID,
            demoID: plan.request.demoID,
            retailerID: plan.request.retailerID,
            completedAt: now,
            executionMode: .live,
            status: .complete,
            observations: observations,
            decisions: decisions,
            basket: SolariBasketSummary(
                completeness: .complete,
                observedSubtotal: selectedSubtotal,
                currency: "USD",
                pricedLineCount: decisions.count,
                missingPriceLineCount: 0,
                unmatchedRequirementCount: 0
            ),
            comparison: SolariBasketComparison(
                cheapestAdequateSubtotal: cheapestSubtotal,
                selectedSubtotal: selectedSubtotal,
                premiumOverCheapest: selectedSubtotal - cheapestSubtotal,
                cheapestAggregateSurplusOunces: cheapestSurplusOunces,
                selectedAggregateSurplusOunces: selectedSurplusOunces,
                surplusAvoidedOunces: cheapestSurplusOunces - selectedSurplusOunces,
                maxPremiumOverCheapest: Decimal(string: "0.75")!,
                currency: "USD"
            ),
            optimizer: SolariOptimizerProvenance(
                method: .sandbox,
                algorithmVersion: "surplus-within-price-cap-v1",
                objective: .minimizePackageSurplus,
                authority: .sandbox,
                verification: .smartCartPolicyInvariants,
                policyInvariantsVerified: true
            ),
            provenance: SolariExecutionProvenance(
                browser: .browser,
                sandbox: .sandbox,
                fixtureReplay: false,
                resourceCleanup: .init(browser: .enforcedBeforeResponse, sandbox: .enforcedBeforeResponse),
                accessBoundary: .appleAppAttest
            ),
            trust: SolariTrustBoundary(
                priceClaim: .observedNotGuaranteed,
                accountAccessed: false,
                cartModified: false,
                checkoutAutomated: false,
                userControlsHandoff: true,
                limitations: ["Visible synthetic prices are timestamped observations, not guarantees."]
            )
        )
    }

    private struct TestProduct {
        let id: String
        let title: String
        let quantity: Double
        let unit: SolariEvidenceUnit
        let price: Decimal
    }

    private func testProduct(_ id: String) -> TestProduct {
        switch id {
        case "dg-chicken-value-3lb": TestProduct(id: id, title: "Demo Grocer Value Chicken", quantity: 3, unit: .pound, price: 9.47)
        case "dg-chicken-rightsize-1lb": TestProduct(id: id, title: "Demo Grocer Right-Size Chicken", quantity: 1, unit: .pound, price: 5.00)
        case "dg-penne-value-16oz": TestProduct(id: id, title: "Demo Grocer Value Penne", quantity: 16, unit: .ounce, price: 1.24)
        case "dg-penne-rightsize-12oz": TestProduct(id: id, title: "Demo Grocer Right-Size Penne", quantity: 12, unit: .ounce, price: 1.65)
        case "dg-parmesan-value-6oz": TestProduct(id: id, title: "Demo Grocer Value Parmesan", quantity: 6, unit: .ounce, price: 2.08)
        case "dg-parmesan-rightsize-3oz": TestProduct(id: id, title: "Demo Grocer Right-Size Parmesan", quantity: 3, unit: .ounce, price: 2.42)
        default: fatalError("Unknown test Demo Grocer product \(id)")
        }
    }

    private func selectedProductID(for requirement: SolariShoppingRequirement) -> String {
        if requirement.candidateProductIDs.contains("dg-chicken-rightsize-1lb") { return "dg-chicken-rightsize-1lb" }
        if requirement.candidateProductIDs.contains("dg-penne-value-16oz") { return "dg-penne-value-16oz" }
        return "dg-parmesan-value-6oz"
    }

    private func unitScale(_ unit: SolariEvidenceUnit) -> Double {
        switch unit { case .ounce: 1; case .pound: 16; case .count: 1 }
    }

    private func replacing(
        _ observation: SolariRetailerObservation,
        observedAt: Date? = nil,
        ambiguityReasons: [String]? = nil,
        freshness: SolariObservationFreshness? = nil
    ) -> SolariRetailerObservation {
        SolariRetailerObservation(
            schemaVersion: observation.schemaVersion,
            observationID: observation.observationID,
            requirementID: observation.requirementID,
            retailerProductID: observation.retailerProductID,
            sourceURL: observation.sourceURL,
            title: observation.title,
            packageDescription: observation.packageDescription,
            packageQuantity: observation.packageQuantity,
            packageUnit: observation.packageUnit,
            visiblePrice: observation.visiblePrice,
            currency: observation.currency,
            observedAt: observedAt ?? observation.observedAt,
            confidence: observation.confidence,
            ambiguityReasons: ambiguityReasons ?? observation.ambiguityReasons,
            proteinGramsPerPackage: observation.proteinGramsPerPackage,
            collectionMethod: observation.collectionMethod,
            location: observation.location,
            catalogEra: observation.catalogEra,
            syntheticPrice: observation.syntheticPrice,
            freshness: freshness ?? observation.freshness
        )
    }

    private func replacing(
        _ decision: SolariBasketDecision,
        substitutionNote: String?,
        ambiguityReasons: [String]
    ) -> SolariBasketDecision {
        SolariBasketDecision(
            schemaVersion: decision.schemaVersion,
            requirementID: decision.requirementID,
            observationID: decision.observationID,
            packageCount: decision.packageCount,
            requiredQuantity: decision.requiredQuantity,
            coveredQuantity: decision.coveredQuantity,
            quantityUnit: decision.quantityUnit,
            surplusQuantity: decision.surplusQuantity,
            surplusOunces: decision.surplusOunces,
            lineTotal: decision.lineTotal,
            currency: decision.currency,
            proteinGramsPerDollar: decision.proteinGramsPerDollar,
            substitutionNote: substitutionNote,
            rationale: decision.rationale,
            confidence: decision.confidence,
            ambiguityReasons: ambiguityReasons
        )
    }

    private func replacing(
        _ result: SolariResearchResult,
        observations: [SolariRetailerObservation]
    ) -> SolariResearchResult {
        SolariResearchResult(
            schemaVersion: result.schemaVersion,
            requestID: result.requestID,
            demoID: result.demoID,
            retailerID: result.retailerID,
            completedAt: result.completedAt,
            executionMode: result.executionMode,
            status: result.status,
            observations: observations,
            decisions: result.decisions,
            basket: result.basket,
            comparison: result.comparison,
            optimizer: result.optimizer,
            provenance: result.provenance,
            trust: result.trust
        )
    }

    private func replacing(
        _ result: SolariResearchResult,
        comparison: SolariBasketComparison
    ) -> SolariResearchResult {
        SolariResearchResult(
            schemaVersion: result.schemaVersion,
            requestID: result.requestID,
            demoID: result.demoID,
            retailerID: result.retailerID,
            completedAt: result.completedAt,
            executionMode: result.executionMode,
            status: result.status,
            observations: result.observations,
            decisions: result.decisions,
            basket: result.basket,
            comparison: comparison,
            optimizer: result.optimizer,
            provenance: result.provenance,
            trust: result.trust
        )
    }

    private func replacing(
        _ result: SolariResearchResult,
        decisions: [SolariBasketDecision]
    ) -> SolariResearchResult {
        SolariResearchResult(
            schemaVersion: result.schemaVersion,
            requestID: result.requestID,
            demoID: result.demoID,
            retailerID: result.retailerID,
            completedAt: result.completedAt,
            executionMode: result.executionMode,
            status: result.status,
            observations: result.observations,
            decisions: decisions,
            basket: result.basket,
            comparison: result.comparison,
            optimizer: result.optimizer,
            provenance: result.provenance,
            trust: result.trust
        )
    }

    private func configuration() -> SolariBackendConfiguration {
        SolariBackendConfiguration(
            backendRawValue: "https://smartcart-solari-beta.example.com",
            demoRetailerRawValue: "https://exo-robotics.github.io/smartcart-solari/website/solari-demo"
        )!
    }

    private func demoItems() -> [ShoppingListItem] {
        [
            item(
                id: fixedUUID("20000000-0000-0000-0000-000000000001"),
                name: "Boneless chicken breast",
                amount: 1.5,
                unit: "lb",
                products: [product(id: "10414680")]
            ),
            item(
                id: fixedUUID("20000000-0000-0000-0000-000000000002"),
                name: "Penne pasta",
                amount: 12,
                unit: "oz",
                products: [product(id: "10534084"), product(id: "623835750")]
            ),
            item(
                id: fixedUUID("20000000-0000-0000-0000-000000000003"),
                name: "Parmesan",
                amount: 3,
                unit: "oz",
                products: [product(id: "10452414"), product(id: "10307238"), product(id: "47088917")]
            )
        ]
    }

    private func item(
        id: UUID,
        name: String,
        amount: Double,
        unit: String,
        products: [RetailerProductRecord]
    ) -> ShoppingListItem {
        ShoppingListItem(
            id: id,
            ingredient: Ingredient(
                id: UUID(uuidString: id.uuidString.replacingOccurrences(of: "20000000", with: "30000000"))!,
                name: name,
                quantity: amount,
                unit: unit
            ),
            requestedQuantity: "\(amount.formatted()) \(unit)",
            requestedAmount: amount,
            purchaseQuantity: 1,
            product: products[0],
            alternatives: Array(products.dropFirst()),
            storeID: fixedUUID("90000000-0000-0000-0000-000000000001"),
            matchScore: 1,
            matchingInputFingerprint: "reviewed-\(id.uuidString)"
        )
    }

    private func product(id: String) -> RetailerProductRecord {
        RetailerProductRecord(
            retailerID: ShoppingRetailer.walmart.rawValue,
            storeID: nil,
            retailerProductID: id,
            title: "Fixture \(id)",
            brand: "Fixture",
            exactURL: URL(string: "https://www.walmart.com/ip/\(id)")!,
            packageDescription: "3 lb",
            packageQuantity: 3,
            packageUnit: "lb",
            observedPrice: 1,
            unitPriceText: "$1",
            priceType: .exact,
            availability: .unknown,
            fulfillmentMethods: [],
            organicStatus: .unknown,
            dataSource: .demoSeed,
            observedAt: now,
            linkKind: .exactProduct,
            symbol: "basket",
            confidence: .high,
            matchKeywords: []
        )
    }

    private func fixedUUID(_ value: String) -> UUID { UUID(uuidString: value)! }
}

private extension ShoppingListItem {
    func withFreshIdentity() -> ShoppingListItem {
        ShoppingListItem(
            ingredient: Ingredient(name: ingredient.name, quantity: ingredient.quantity, unit: ingredient.unit),
            requestedQuantity: requestedQuantity,
            requestedAmount: requestedAmount,
            purchaseQuantity: purchaseQuantity,
            product: product,
            alternatives: alternatives,
            storeID: storeID,
            status: status,
            matchScore: matchScore
        )
    }
}
