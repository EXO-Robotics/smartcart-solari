import XCTest
@testable import SmartCart

final class SolariEvidenceContractTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_278_400)

    func testBasketComparisonPresentationUsesScoresInsteadOfFalsePercentages() {
        let tradeoff = SolariBasketComparison(
            cheapestAdequateSubtotal: 24.20, selectedSubtotal: 24.83, premiumOverCheapest: 0.63,
            cheapestAggregateRelativeSurplus: 21.065711, selectedAggregateRelativeSurplus: 20.0799,
            relativeSurplusAvoided: 0.985811, maxPremiumOverCheapest: 0.75, currency: "USD"
        )
        let presentation = SolariBasketComparisonPresentation(tradeoff)
        XCTAssertTrue(presentation.headline.contains("Selected a lower-overage basket"))
        XCTAssertFalse(presentation.headline.contains("score"))
        XCTAssertTrue(presentation.detail.contains("package-overage score"))
        XCTAssertTrue(presentation.detail.contains("Review line items for exact leftover quantities"))
        XCTAssertFalse(presentation.headline.contains("%"))
        XCTAssertFalse(presentation.detail.contains("%"))

        let cheapest = SolariBasketComparison(
            cheapestAdequateSubtotal: 24.20, selectedSubtotal: 24.20, premiumOverCheapest: 0,
            cheapestAggregateRelativeSurplus: 21.065711, selectedAggregateRelativeSurplus: 21.065711,
            relativeSurplusAvoided: 0, maxPremiumOverCheapest: 0.75, currency: "USD"
        )
        XCTAssertEqual(
            SolariBasketComparisonPresentation(cheapest).headline,
            "Selected basket is the cheapest adequate option for this trip."
        )
    }

    func testOneOfEightWaitingLinesProducesPartialCoveragePlan() {
        let plan = eligiblePlan([item(1, "Chicken breast", 1.5, "lb", "10414680")] + (2...8).map(unsupported))
        XCTAssertEqual(plan.request.requirements.count, 1)
        XCTAssertEqual(plan.skippedLines.count, 7)
        XCTAssertEqual(plan.totalWaitingCount, 8)
        XCTAssertEqual(plan.originalSmartCartSelections.count, 8)
    }

    func testThreeOfEightWaitingLinesProducesPartialCoveragePlan() {
        let plan = eligiblePlan([
            item(1, "Chicken breast", 1.5, "lb", "10414680"),
            item(2, "Penne pasta", 12, "oz", "10534084"),
            item(3, "Parmesan", 3, "oz", "10452414")
        ] + (4...8).map(unsupported))
        XCTAssertEqual(plan.request.requirements.count, 3)
        XCTAssertEqual(plan.skippedLines.count, 5)
        XCTAssertEqual(plan.request.schemaVersion, "solari-shopping-research-request-v4")
        XCTAssertEqual(plan.request.optimizationPolicy, .fixedV4)
    }

    func testOverlappingCatalogCoverageSkipsLaterLineDeterministically() {
        let first = item(1, "Chicken breast", 1.5, "lb", "10414680")
        let second = item(2, "Chicken thighs", 2, "lb", "145781250")
        let forward = eligiblePlan([first, second])
        let reversed = eligiblePlan([second, first])

        XCTAssertEqual(forward.fingerprint, reversed.fingerprint)
        XCTAssertEqual(forward.request.requirements.map(\.id), [first.id])
        XCTAssertEqual(forward.skippedLines.map(\.id), [second.id])
        XCTAssertEqual(forward.skippedLines.map(\.reason), [.overlappingCatalogCoverage("Chicken thighs")])
    }

    func testDuplicateRequirementIdentityFailsGlobally() {
        let duplicate = item(1, "Chicken breast", 1.5, "lb", "10414680")
        XCTAssertEqual(evaluate([duplicate, duplicate]), .ineligible([.duplicateRequirement]))
    }

    func testValidatorRejectsMalformedDuplicateRequirementPlanWithoutTrapping() {
        let plan = eligiblePlan([item(1, "Chicken breast", 1.5, "lb", "10414680")])
        let original = validResult(plan)
        let malformedRequest = SolariResearchRequest(
            schemaVersion: plan.request.schemaVersion,
            requestID: plan.request.requestID,
            demoID: plan.request.demoID,
            submittedAt: plan.request.submittedAt,
            retailerID: plan.request.retailerID,
            executionMode: plan.request.executionMode,
            storeReference: plan.request.storeReference,
            optimizationPolicy: plan.request.optimizationPolicy,
            requirements: [plan.request.requirements[0], plan.request.requirements[0]]
        )
        let malformedPlan = SolariResearchPlan(
            configuration: plan.configuration,
            request: malformedRequest,
            fingerprint: plan.fingerprint,
            sourceURLsByProductID: plan.sourceURLsByProductID,
            originalSmartCartSelections: plan.originalSmartCartSelections,
            skippedLines: plan.skippedLines,
            totalWaitingCount: plan.totalWaitingCount,
            servingCount: plan.servingCount
        )
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(original, for: malformedPlan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidObservationReference)
        }
    }

    func testZeroCoverageReturnsActionableLineReasons() {
        let result = evaluate([unsupported(1), semantic(2, "Olive oil", "for frying", "", "10315102")])
        guard case .ineligible(let reasons) = result else { return XCTFail("Expected no coverage") }
        XCTAssertEqual(reasons.count, 2)
        XCTAssertTrue(reasons.allSatisfy { !$0.localizedDescription.contains("outage") })
    }

    func testMassUnitsCanonicalizeToGrams() {
        let cases: [(Double, String, Double)] = [(100, "g", 100), (1, "kg", 1_000), (1, "oz", 28.349_523_125), (1, "lb", 453.592_37)]
        for (index, value) in cases.enumerated() {
            let requirement = eligiblePlan([item(index + 1, "Chicken breast", value.0, value.1, "10414680")]).request.requirements[0]
            XCTAssertEqual(requirement.unit, .gram)
            XCTAssertEqual(requirement.requiredQuantity, value.2, accuracy: 0.000_001)
        }
    }

    func testVolumeUnitsCanonicalizeToMilliliters() {
        let cases: [(Double, String, Double)] = [
            (100, "ml", 100), (1, "l", 1_000), (1, "cup", 236.588_236_5),
            (1, "tbsp", 14.786_764_781_25), (1, "tsp", 4.928_921_593_75), (1, "fl oz", 29.573_529_562_5)
        ]
        for (index, value) in cases.enumerated() {
            let requirement = eligiblePlan([item(index + 1, "Olive oil", value.0, value.1, "10315102")]).request.requirements[0]
            XCTAssertEqual(requirement.unit, .milliliter)
            XCTAssertEqual(requirement.requiredQuantity, value.2, accuracy: 0.000_001)
        }
    }

    func testCountCanonicalizesWithoutInventingMass() {
        let requirement = eligiblePlan([item(1, "Lemon", 2, "count", "41752773")]).request.requirements[0]
        XCTAssertEqual(requirement.unit, .count)
        XCTAssertEqual(requirement.requiredQuantity, 2)
    }

    func testSemanticQuantitiesAreSkipped() {
        for (index, text) in ["for frying", "to taste", "as needed"].enumerated() {
            guard case .ineligible(let reasons) = evaluate([semantic(index + 1, "Olive oil", text, "", "10315102")]) else {
                return XCTFail("Expected semantic quantity to be skipped")
            }
            XCTAssertEqual(reasons, [.invalidQuantity("Olive oil")])
        }

        guard case .ineligible(let reasons) = evaluate([
            item(4, "Olive oil", 1, "tbsp", "10315102", quantity: "1 tbsp, to taste")
        ]) else {
            return XCTFail("Expected semantic qualifier to override a parsed numeric amount")
        }
        XCTAssertEqual(reasons, [.invalidQuantity("Olive oil")])
    }

    func testVolumeMassConversionIsRefused() {
        guard case .ineligible(let reasons) = evaluate([item(1, "Olive oil", 8, "oz", "10315102")]) else {
            return XCTFail("Expected incompatible dimensions")
        }
        XCTAssertEqual(reasons, [.incompatiblePackageDimension("Olive oil")])
    }

    func testValidatorAcceptsOneTwoAndNRequirementResults() throws {
        let items = [
            item(1, "Chicken breast", 1.5, "lb", "10414680"),
            item(2, "Penne pasta", 12, "oz", "10534084"),
            item(3, "Olive oil", 2, "tbsp", "10315102"),
            item(4, "Parmesan", 3, "oz", "10452414"),
            item(5, "Lemon", 2, "count", "41752773")
        ]
        for count in [1, 2, items.count] {
            let plan = eligiblePlan(Array(items.prefix(count)))
            XCTAssertEqual(try SolariEvidenceValidator(now: now).validate(validResult(plan), for: plan).result.decisions.count, count)
        }
    }

    func testSkippedLineMutationInvalidatesContinuation() throws {
        let items = [item(1, "Chicken breast", 1.5, "lb", "10414680"), unsupported(2)]
        let plan = eligiblePlan(items)
        let research = try SolariEvidenceValidator(now: now).validate(validResult(plan), for: plan)
        var mutated = items
        mutated[1].requestedAmount = 9
        mutated[1].requestedQuantity = "9 mystery"
        XCTAssertFalse(SolariOriginalSmartCartContinuation.permitsFinalization(plan: plan, research: research, items: mutated, servingCount: 4))
    }

    func testLargeUnsupportedTripIsDeterministicAndNeverSilentlyTruncated() {
        let items = [item(40, "Chicken breast", 1.5, "lb", "10414680")] + (1...30).map(unsupported)
        let first = eligiblePlan(items)
        let second = eligiblePlan(items.reversed())
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first.totalWaitingCount, 31)
        XCTAssertEqual(first.skippedLines.count, 30)
        XCTAssertEqual(first.originalSmartCartSelections.count, 31)
    }

    func testFullOriginalHandoffIsPreservedForPartialCoverage() throws {
        let items = [item(1, "Chicken breast", 1.5, "lb", "10414680"), unsupported(2)]
        let plan = eligiblePlan(items)
        let research = try SolariEvidenceValidator(now: now).validate(validResult(plan), for: plan)
        XCTAssertEqual(plan.originalSmartCartSelections.count, items.count)
        XCTAssertTrue(SolariOriginalSmartCartContinuation.permitsFinalization(plan: plan, research: research, items: items, servingCount: 4))
        XCTAssertTrue(items.allSatisfy { !$0.product.retailerProductID.hasPrefix("dg4-") })
    }

    func testValidatorRejectsRelativeSurplusTampering() {
        let plan = eligiblePlan([item(1, "Chicken breast", 1.5, "lb", "10414680")])
        let result = validResult(plan)
        let value = result.decisions[0]
        let tampered = SolariBasketDecision(
            schemaVersion: value.schemaVersion, requirementID: value.requirementID, observationID: value.observationID,
            retailerProductID: value.retailerProductID, packageCount: value.packageCount,
            requiredQuantity: value.requiredQuantity, coveredQuantity: value.coveredQuantity, quantityUnit: value.quantityUnit,
            surplusQuantity: value.surplusQuantity, relativeSurplus: value.relativeSurplus + 1,
            lineTotal: value.lineTotal, currency: value.currency, proteinGramsPerDollar: nil, substitutionNote: nil,
            rationale: value.rationale, confidence: value.confidence, ambiguityReasons: value.ambiguityReasons
        )
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(replacing(result, [tampered]), for: plan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidPackageMath)
        }
    }

    func testRefreshMintsTransportIdentityWithoutChangingPlanFingerprint() throws {
        let plan = eligiblePlan([item(1, "Chicken breast", 1.5, "lb", "10414680"), unsupported(2)])
        let refreshed = SolariResearchRequestBuilder.refreshedPlan(from: plan, now: now.addingTimeInterval(30))
        XCTAssertNotEqual(refreshed.request.requestID, plan.request.requestID)
        XCTAssertEqual(refreshed.fingerprint, plan.fingerprint)
        XCTAssertEqual(refreshed.request.requirements, plan.request.requirements)
        XCTAssertEqual(refreshed.originalSmartCartSelections, plan.originalSmartCartSelections)
        XCTAssertEqual(refreshed.skippedLines, plan.skippedLines)
        XCTAssertEqual(
            try SolariRetailerResearchClient.encoder.encode(refreshed.request),
            try SolariRetailerResearchClient.encoder.encode(refreshed.request),
            "A true retry must reuse the exact request body"
        )
    }

    func testEncodedRequestDoesNotLeakSourceCredentialOrOriginalRetailerIDs() throws {
        let plan = eligiblePlan([item(1, "Chicken breast", 1.5, "lb", "10414680")])
        let text = String(decoding: try SolariRetailerResearchClient.encoder.encode(plan.request), as: UTF8.self).lowercased()
        XCTAssertTrue(text.contains("candidateproductids"))
        for forbidden in ["10414680", "sourceurl", "cookie", "credential", "session", "solari_api_key"] {
            XCTAssertFalse(text.contains(forbidden))
        }
    }

    func testConfigurationDerivesOwnedV4SourceAndRejectsUnsafeURLs() {
        XCTAssertEqual(
            configuration().sourceURL(for: "dg4-chicken-value-3lb")?.absoluteString,
            "https://exo-robotics.github.io/smartcart-solari/website/solari-demo/retailer-v4/product/dg4-chicken-value-3lb.html"
        )
        XCTAssertNil(configuration().sourceURL(for: "unknown"))
        XCTAssertNil(SolariBackendConfiguration(backendRawValue: "https://user:secret@example.com", demoRetailerRawValue: "https://example.com"))
        XCTAssertNil(SolariBackendConfiguration(backendRawValue: "http://example.com", demoRetailerRawValue: "https://example.com"))
        XCTAssertNil(SolariBackendConfiguration(backendRawValue: "https://example.com", demoRetailerRawValue: "http://example.com"))
    }

    func testValidatorRejectsStaleEvidenceMismatchedSourceAndUnsafeTrust() {
        let plan = eligiblePlan([item(1, "Chicken breast", 1.5, "lb", "10414680")])
        let original = validResult(plan)
        var observations = original.observations
        observations[0] = replacing(observations[0], observedAt: now.addingTimeInterval(-120),
                                    sourceURL: observations[0].sourceURL,
                                    freshness: .init(status: .fresh, ageSeconds: 120, maxAgeSeconds: 60))
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(replacing(original, observations: observations), for: plan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .staleObservation)
        }

        observations = original.observations
        observations[0] = replacing(observations[0], observedAt: observations[0].observedAt,
                                    sourceURL: URL(string: "https://evil.example/product")!,
                                    freshness: observations[0].freshness)
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(replacing(original, observations: observations), for: plan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidObservationReference)
        }

        let unsafe = replacing(original, trust: .init(priceClaim: .observedNotGuaranteed, accountAccessed: true,
                                                       cartModified: false, checkoutAutomated: false,
                                                       userControlsHandoff: true, limitations: ["Not guaranteed."]))
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(unsafe, for: plan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidProvenance)
        }
    }

    func testMemoryCacheExpiresAndRefreshBypassesWithoutPersistence() {
        let plan = eligiblePlan([item(1, "Chicken breast", 1.5, "lb", "10414680")])
        let research = SolariValidatedResearch(result: validResult(plan), warnings: [], planFingerprint: plan.fingerprint)
        var cache = SolariValidatedResearchCache(timeToLive: 60)
        cache.insert(research, for: plan.fingerprint, now: now)
        XCTAssertNotNil(cache.value(for: plan.fingerprint, now: now.addingTimeInterval(59)))
        XCTAssertNil(cache.value(for: plan.fingerprint, now: now.addingTimeInterval(30), bypass: true))
        XCTAssertNil(cache.value(for: plan.fingerprint, now: now.addingTimeInterval(31)))
    }

    func testAppAttestBindsExactBodyAndRequiresCanonicalKeyID() throws {
        let challenge = "q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s"
        let first = SolariAppAttestClient.assertionClientDataHash(challengeBase64URL: challenge, exactResearchBody: Data("{\"a\":1}".utf8))
        let second = SolariAppAttestClient.assertionClientDataHash(challengeBase64URL: challenge, exactResearchBody: Data("{\"a\":1 }".utf8))
        XCTAssertEqual(first.count, 32)
        XCTAssertNotEqual(first, second)
        let keyID = Data(repeating: 0xFB, count: 32).base64EncodedString()
        XCTAssertTrue(SolariAppAttestClient.isValidKeyID(keyID))
        XCTAssertFalse(SolariAppAttestClient.isValidKeyID(String(keyID.dropLast())))

        let payload = Data("{\"schemaVersion\":\"solari-shopping-research-request-v4\"}".utf8)
        let request = try SolariRetailerResearchClient.researchRequest(
            exactBody: payload,
            authorization: .init(keyID: keyID, challengeID: fixedUUID(99, "50000000"), assertion: Data([1, 2, 3])),
            endpoint: URL(string: "https://example.com/v1/solari/research")!
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "x-smartcart-app-attest-key-id"))
        let envelope = try SolariRetailerResearchClient.decoder.decode(SolariAppAttestResearchEnvelope.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(Data(base64Encoded: envelope.payloadBase64), payload)
    }

    func testDebugRecordedReplayRemainsExplicitlyNonLive() throws {
        let fixtureConfiguration = SolariBackendConfiguration(
            backendRawValue: "https://smartcart.example.com",
            demoRetailerRawValue: "https://exo-robotics.github.io/smartcart-solari/website/solari-demo",
            debugFixtureReplayEnabled: true
        )!
        guard case .eligible(let plan) = SolariResearchRequestBuilder.evaluate(
            items: [item(1, "Chicken breast", 1.5, "lb", "10414680")],
            configuration: fixtureConfiguration, servingCount: 4, now: now
        ) else { return XCTFail("Expected fixture plan") }
        let replay = try SolariDebugRecordedFixture.make(for: plan)
        XCTAssertEqual(replay.result.executionMode, .recordedFixture)
        XCTAssertEqual(replay.result.provenance.browser, .notRunFixture)
        XCTAssertEqual(replay.result.provenance.sandbox, .notRunFixture)
        XCTAssertEqual(replay.result.provenance.accessBoundary, .notUsedRecordedFixture)
        XCTAssertEqual(replay.result.trust.priceClaim, .recordedFixtureNotLive)
        XCTAssertTrue(replay.warnings.contains { $0.contains("did not run") })
    }

    func testRequestIDEncodesLowercaseAndTransportUsesBoundedJSONEnvelope() throws {
        let requestID = UUID(uuidString: "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF")!
        guard case .eligible(let plan) = SolariResearchRequestBuilder.evaluate(
            items: [item(1, "Chicken breast", 1.5, "lb", "10414680")], configuration: configuration(),
            servingCount: 4, now: now, requestID: requestID
        ) else { return XCTFail("Expected plan") }
        let data = try SolariRetailerResearchClient.encoder.encode(plan.request)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("abcdefab-cdef-4abc-8def-abcdefabcdef"))

        let keyID = Data(repeating: 0xFB, count: 32).base64EncodedString()
        let request = try SolariRetailerResearchClient.researchRequest(
            exactBody: data, authorization: .init(keyID: keyID, challengeID: fixedUUID(88, "50000000"), assertion: Data([1])),
            endpoint: URL(string: "https://example.com/v1/solari/research")!
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 75)
        XCTAssertNil(request.value(forHTTPHeaderField: "x-smartcart-app-attest-assertion"))
        let session = SolariRetailerResearchClient.ephemeralSessionConfiguration()
        XCTAssertNil(session.httpCookieStorage)
        XCTAssertEqual(session.timeoutIntervalForResource, 90)
    }

    func testSelectedSourceHandoffUsesOnlyOwnedDemoSources() throws {
        let plan = eligiblePlan([item(1, "Chicken breast", 1.5, "lb", "10414680"), unsupported(2)])
        let validated = try SolariEvidenceValidator(now: now).validate(validResult(plan), for: plan)
        let handoff = SolariEvidenceHandoff(result: validated.result)
        XCTAssertEqual(handoff.retailerID, "smartcart-demo-grocer")
        XCTAssertFalse(handoff.transfersToConfiguredRetailer)
        XCTAssertTrue(handoff.selectedSourceURLs.allSatisfy {
            $0.host == "exo-robotics.github.io" && $0.path.contains("/retailer-v4/product/dg4-")
        })
    }

    func testValidatorAcceptsStaggeredFreshnessAndRejectsFutureEvidence() throws {
        let plan = eligiblePlan([
            item(1, "Chicken breast", 1.5, "lb", "10414680"),
            item(2, "Penne pasta", 12, "oz", "10534084")
        ])
        let original = validResult(plan)
        let staggered = original.observations.enumerated().map { index, observation in
            replacing(observation, observedAt: now.addingTimeInterval(-Double(index + 1)),
                      sourceURL: observation.sourceURL,
                      freshness: .init(status: .fresh, ageSeconds: index + 1, maxAgeSeconds: 86_400))
        }
        XCTAssertNoThrow(try SolariEvidenceValidator(now: now).validate(replacing(original, observations: staggered), for: plan))
        var future = staggered
        future[0] = replacing(future[0], observedAt: now.addingTimeInterval(10), sourceURL: future[0].sourceURL,
                              freshness: .init(status: .fresh, ageSeconds: 0, maxAgeSeconds: 86_400))
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(replacing(original, observations: future), for: plan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .staleObservation)
        }
    }

    func testSubstitutionNoteMustMatchSelectedObservationAmbiguity() throws {
        let plan = eligiblePlan([item(1, "Chicken breast", 1.5, "lb", "10414680")])
        let original = validResult(plan)
        let decision = original.decisions[0]
        let selectedIndex = original.observations.firstIndex { $0.observationID == decision.observationID }!
        let ambiguity = "Confirm the package label before handoff."
        var observations = original.observations
        observations[selectedIndex] = replacing(observations[selectedIndex], ambiguityReasons: [ambiguity])
        let validDecision = replacing(decision, substitutionNote: ambiguity, ambiguityReasons: [ambiguity])
        let withAmbiguity = replacing(replacing(original, observations: observations), [validDecision])
        XCTAssertNoThrow(try SolariEvidenceValidator(now: now).validate(withAmbiguity, for: plan))
        let invalidDecision = replacing(decision, substitutionNote: "Unsupported claim", ambiguityReasons: [ambiguity])
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(replacing(replacing(original, observations: observations), [invalidDecision]), for: plan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidPackageMath)
        }
    }

    private func evaluate<S: Sequence>(_ items: S) -> SolariResearchEligibility where S.Element == ShoppingListItem {
        SolariResearchRequestBuilder.evaluate(items: Array(items), configuration: configuration(), servingCount: 4, now: now)
    }

    private func eligiblePlan<S: Sequence>(_ items: S) -> SolariResearchPlan where S.Element == ShoppingListItem {
        guard case .eligible(let plan) = evaluate(items) else { fatalError("Expected eligible plan") }
        return plan
    }

    private func validResult(_ plan: SolariResearchPlan) -> SolariResearchResult {
        var observations: [SolariRetailerObservation] = [], decisions: [SolariBasketDecision] = []
        var subtotal: Decimal = 0, aggregate = 0.0
        for requirement in plan.request.requirements {
            let line = requirement.candidateProductIDs.map { id -> SolariRetailerObservation in
                let product = demoProduct(id)
                return .init(
                    schemaVersion: SolariRetailerEvidenceSchema.observationVersion,
                    observationID: "obs-\(requirement.id.uuidString.lowercased())-\(id)", requirementID: requirement.id,
                    retailerProductID: id, sourceURL: plan.sourceURLsByProductID[id]!, title: product.title,
                    packageDescription: product.title, packageQuantity: product.quantity, packageUnit: product.unit,
                    visiblePrice: product.price, currency: "USD", observedAt: now.addingTimeInterval(-5), confidence: .high,
                    ambiguityReasons: [], proteinGramsPerPackage: nil, collectionMethod: .controlledDemo,
                    location: .controlledDemo, catalogEra: "current-v4", syntheticPrice: true,
                    freshness: .init(status: .fresh, ageSeconds: 5, maxAgeSeconds: 86_400)
                )
            }
            observations += line
            let candidates = line.map { observation -> (SolariRetailerObservation, Int, Decimal, Double) in
                let count = max(1, Int(ceil(requirement.requiredQuantity / observation.packageQuantity!)))
                let total = observation.visiblePrice! * Decimal(count)
                let relative = (observation.packageQuantity! * Double(count) - requirement.requiredQuantity) / requirement.requiredQuantity
                return (observation, count, total, relative)
            }
            let selected = candidates.min { $0.2 == $1.2 ? $0.0.retailerProductID < $1.0.retailerProductID : $0.2 < $1.2 }!
            subtotal += selected.2; aggregate += selected.3
            decisions.append(.init(
                schemaVersion: SolariRetailerEvidenceSchema.decisionVersion, requirementID: requirement.id,
                observationID: selected.0.observationID, retailerProductID: selected.0.retailerProductID,
                packageCount: selected.1, requiredQuantity: requirement.requiredQuantity,
                coveredQuantity: selected.0.packageQuantity! * Double(selected.1), quantityUnit: selected.0.packageUnit!,
                surplusQuantity: selected.0.packageQuantity! * Double(selected.1) - requirement.requiredQuantity,
                relativeSurplus: selected.3, lineTotal: selected.2, currency: "USD", proteinGramsPerDollar: nil,
                substitutionNote: nil, rationale: ["Sandbox selected this package."], confidence: .high, ambiguityReasons: []
            ))
        }
        return .init(
            schemaVersion: SolariRetailerEvidenceSchema.resultVersion, requestID: plan.request.requestID,
            demoID: plan.request.demoID, retailerID: plan.request.retailerID, completedAt: now,
            executionMode: .live, status: .complete, observations: observations, decisions: decisions,
            basket: .init(completeness: .complete, observedSubtotal: subtotal, currency: "USD", pricedLineCount: decisions.count, missingPriceLineCount: 0, unmatchedRequirementCount: 0),
            comparison: .init(cheapestAdequateSubtotal: subtotal, selectedSubtotal: subtotal, premiumOverCheapest: 0,
                              cheapestAggregateRelativeSurplus: aggregate, selectedAggregateRelativeSurplus: aggregate,
                              relativeSurplusAvoided: 0, maxPremiumOverCheapest: 0.75, currency: "USD"),
            optimizer: .init(method: .sandbox, algorithmVersion: "relative-surplus-premium-dp-v1",
                             objective: .minimizeAggregateRelativeSurplus, authority: .sandbox,
                             verification: .smartCartPolicyInvariants, policyInvariantsVerified: true),
            provenance: .init(browser: .browser, sandbox: .sandbox, fixtureReplay: false,
                              resourceCleanup: .init(browser: .enforcedBeforeResponse, sandbox: .enforcedBeforeResponse), accessBoundary: .appleAppAttest),
            trust: .init(priceClaim: .observedNotGuaranteed, accountAccessed: false, cartModified: false,
                         checkoutAutomated: false, userControlsHandoff: true,
                         limitations: ["Synthetic observed prices are not guaranteed."])
        )
    }

    private struct DemoProduct { let title: String; let quantity: Double; let unit: SolariEvidenceUnit; let price: Decimal }
    private func demoProduct(_ id: String) -> DemoProduct {
        switch id {
        case "dg4-chicken-value-3lb": .init(title: "Chicken value", quantity: 1_360.777_11, unit: .gram, price: 8.13)
        case "dg4-chicken-organic-1-5lb": .init(title: "Chicken organic", quantity: 680.388_555, unit: .gram, price: 8.76)
        case "dg4-chicken-free-range-3lb": .init(title: "Chicken free range", quantity: 1_360.777_11, unit: .gram, price: 13.92)
        case "dg4-penne-value-16oz": .init(title: "Penne value", quantity: 453.592_37, unit: .gram, price: 1.24)
        case "dg4-penne-glutenfree-24oz": .init(title: "Penne gluten free", quantity: 680.388_555, unit: .gram, price: 11.98)
        case "dg4-olive-oil-value-17floz": .init(title: "Olive oil value", quantity: 502.750_002_562_5, unit: .milliliter, price: 6.12)
        case "dg4-olive-oil-organic-17floz": .init(title: "Olive oil organic", quantity: 502.750_002_562_5, unit: .milliliter, price: 7.36)
        case "dg4-olive-oil-smooth-16floz": .init(title: "Olive oil smooth", quantity: 473.176_473, unit: .milliliter, price: 6.75)
        case "dg4-parmesan-value-6oz": .init(title: "Parmesan value", quantity: 170.097_138_75, unit: .gram, price: 2.08)
        case "dg4-parmesan-frigo-5oz": .init(title: "Parmesan cup", quantity: 141.747_615_625, unit: .gram, price: 3.28)
        case "dg4-parmesan-kraft-6oz": .init(title: "Parmesan premium", quantity: 170.097_138_75, unit: .gram, price: 4.98)
        case "dg4-lemon-each-1ct": .init(title: "Lemon", quantity: 1, unit: .count, price: 0.64)
        default: fatalError("Missing test product \(id)")
        }
    }

    private func replacing(_ result: SolariResearchResult, _ decisions: [SolariBasketDecision]) -> SolariResearchResult {
        .init(schemaVersion: result.schemaVersion, requestID: result.requestID, demoID: result.demoID,
              retailerID: result.retailerID, completedAt: result.completedAt, executionMode: result.executionMode,
              status: result.status, observations: result.observations, decisions: decisions, basket: result.basket,
              comparison: result.comparison, optimizer: result.optimizer, provenance: result.provenance, trust: result.trust)
    }

    private func replacing(
        _ observation: SolariRetailerObservation,
        observedAt: Date,
        sourceURL: URL,
        freshness: SolariObservationFreshness
    ) -> SolariRetailerObservation {
        .init(schemaVersion: observation.schemaVersion, observationID: observation.observationID,
              requirementID: observation.requirementID, retailerProductID: observation.retailerProductID,
              sourceURL: sourceURL, title: observation.title, packageDescription: observation.packageDescription,
              packageQuantity: observation.packageQuantity, packageUnit: observation.packageUnit,
              visiblePrice: observation.visiblePrice, currency: observation.currency, observedAt: observedAt,
              confidence: observation.confidence, ambiguityReasons: observation.ambiguityReasons,
              proteinGramsPerPackage: observation.proteinGramsPerPackage, collectionMethod: observation.collectionMethod,
              location: observation.location, catalogEra: observation.catalogEra,
              syntheticPrice: observation.syntheticPrice, freshness: freshness)
    }

    private func replacing(
        _ observation: SolariRetailerObservation,
        ambiguityReasons: [String]
    ) -> SolariRetailerObservation {
        .init(schemaVersion: observation.schemaVersion, observationID: observation.observationID,
              requirementID: observation.requirementID, retailerProductID: observation.retailerProductID,
              sourceURL: observation.sourceURL, title: observation.title, packageDescription: observation.packageDescription,
              packageQuantity: observation.packageQuantity, packageUnit: observation.packageUnit,
              visiblePrice: observation.visiblePrice, currency: observation.currency, observedAt: observation.observedAt,
              confidence: observation.confidence, ambiguityReasons: ambiguityReasons,
              proteinGramsPerPackage: observation.proteinGramsPerPackage, collectionMethod: observation.collectionMethod,
              location: observation.location, catalogEra: observation.catalogEra,
              syntheticPrice: observation.syntheticPrice, freshness: observation.freshness)
    }

    private func replacing(
        _ decision: SolariBasketDecision,
        substitutionNote: String?,
        ambiguityReasons: [String]
    ) -> SolariBasketDecision {
        .init(schemaVersion: decision.schemaVersion, requirementID: decision.requirementID,
              observationID: decision.observationID, retailerProductID: decision.retailerProductID,
              packageCount: decision.packageCount, requiredQuantity: decision.requiredQuantity,
              coveredQuantity: decision.coveredQuantity, quantityUnit: decision.quantityUnit,
              surplusQuantity: decision.surplusQuantity, relativeSurplus: decision.relativeSurplus,
              lineTotal: decision.lineTotal, currency: decision.currency,
              proteinGramsPerDollar: decision.proteinGramsPerDollar, substitutionNote: substitutionNote,
              rationale: decision.rationale, confidence: decision.confidence, ambiguityReasons: ambiguityReasons)
    }

    private func replacing(_ result: SolariResearchResult, observations: [SolariRetailerObservation]) -> SolariResearchResult {
        .init(schemaVersion: result.schemaVersion, requestID: result.requestID, demoID: result.demoID,
              retailerID: result.retailerID, completedAt: result.completedAt, executionMode: result.executionMode,
              status: result.status, observations: observations, decisions: result.decisions, basket: result.basket,
              comparison: result.comparison, optimizer: result.optimizer, provenance: result.provenance, trust: result.trust)
    }

    private func replacing(_ result: SolariResearchResult, trust: SolariTrustBoundary) -> SolariResearchResult {
        .init(schemaVersion: result.schemaVersion, requestID: result.requestID, demoID: result.demoID,
              retailerID: result.retailerID, completedAt: result.completedAt, executionMode: result.executionMode,
              status: result.status, observations: result.observations, decisions: result.decisions, basket: result.basket,
              comparison: result.comparison, optimizer: result.optimizer, provenance: result.provenance, trust: trust)
    }

    private func configuration() -> SolariBackendConfiguration {
        SolariBackendConfiguration(backendRawValue: "https://smartcart.example.com",
                                   demoRetailerRawValue: "https://exo-robotics.github.io/smartcart-solari/website/solari-demo")!
    }

    private func item(_ index: Int, _ name: String, _ amount: Double?, _ unit: String, _ productID: String, quantity: String? = nil) -> ShoppingListItem {
        let id = fixedUUID(index, "20000000")
        return .init(
            id: id, ingredient: .init(id: fixedUUID(index, "30000000"), name: name, quantity: amount ?? 0, unit: unit),
            requestedQuantity: quantity ?? amount.map { "\($0) \(unit)" } ?? "", requestedAmount: amount,
            product: product(productID), alternatives: [], storeID: fixedUUID(1, "90000000"),
            matchScore: 1, matchingInputFingerprint: "reviewed-\(id.uuidString)"
        )
    }

    private func semantic(_ index: Int, _ name: String, _ quantity: String, _ unit: String, _ productID: String) -> ShoppingListItem {
        item(index, name, nil, unit, productID, quantity: quantity)
    }
    private func unsupported(_ index: Int) -> ShoppingListItem { item(index, "Unsupported item \(index)", 1, "count", "unsupported-\(index)") }

    private func product(_ id: String) -> RetailerProductRecord {
        .init(retailerID: ShoppingRetailer.walmart.rawValue, storeID: nil, retailerProductID: id,
              title: "Fixture \(id)", brand: "Fixture", exactURL: URL(string: "https://example.com/\(id)")!,
              packageDescription: "fixture", packageQuantity: 1, packageUnit: "count", observedPrice: 1,
              unitPriceText: "$1", priceType: .exact, availability: .unknown, fulfillmentMethods: [],
              organicStatus: .unknown, dataSource: .demoSeed, observedAt: now, linkKind: .exactProduct,
              symbol: "basket", confidence: .high, matchKeywords: [])
    }

    private func fixedUUID(_ index: Int, _ prefix: String) -> UUID {
        UUID(uuidString: String(format: "%@-0000-4000-8000-%012d", prefix, index))!
    }
}
