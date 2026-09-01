import Foundation
import XCTest
@testable import SmartCart

final class SolariEvidenceContractTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_799_000_000)

    func testOneToThreeSupportedWaitingItemsBuildGeneralizedV2Request() throws {
        for count in 1...3 {
            let eligibility = SolariResearchRequestBuilder.evaluate(
                items: Array(demoItems().prefix(count)),
                configuration: configuration(),
                servingCount: 4,
                now: now,
                requestID: fixedUUID("10000000-0000-0000-0000-000000000001")
            )
            guard case .eligible(let plan) = eligibility else {
                return XCTFail("Expected \(count) items to be eligible")
            }
            XCTAssertEqual(plan.request.schemaVersion, "solari-shopping-research-request-v2")
            XCTAssertEqual(plan.request.demoID, "owned-demo-grocer-basket-v2")
            XCTAssertEqual(plan.request.retailerID, "smartcart-demo-grocer")
            XCTAssertEqual(plan.request.requirements.count, count)
            XCTAssertTrue(plan.request.requirements.allSatisfy { (1...3).contains($0.candidateProductIDs.count) })
            XCTAssertTrue(plan.sourceURLsByProductID.values.allSatisfy {
                $0.absoluteString.hasPrefix("https://exo-robotics.github.io/smartcart-solari/website/solari-demo/retailer/product/")
            })
        }
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
        let changedPlan = eligiblePlan(items: changed, now: now, requestID: first.request.requestID)
        XCTAssertNotEqual(first.fingerprint, changedPlan.fingerprint)
        XCTAssertFalse(SolariResearchRequestBuilder.matchesCurrentPlan(first, items: changed, servingCount: 4))
    }

    func testExplicitIneligibilityReasonsCoverBoundsAndUnsupportedCatalog() {
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
            unit: "count",
            products: [product(id: "unsupported")]
        )
        XCTAssertEqual(
            SolariResearchRequestBuilder.evaluate(
                items: [unsupported],
                configuration: configuration(),
                servingCount: 4
            ),
            .ineligible([.unsupportedProduct("Fresh basil")])
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

    func testConfigurationDerivesExactOwnedSourceAndRejectsCredentialsOrHTTP() {
        let configuration = configuration()
        XCTAssertEqual(
            configuration.sourceURL(for: "10414680")?.absoluteString,
            "https://exo-robotics.github.io/smartcart-solari/website/solari-demo/retailer/product/10414680.html"
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

    func testValidatorAcceptsGeneralizedEvidenceWithTypedProvenance() throws {
        let plan = eligiblePlan(items: [demoItems()[0]], now: now)
        let validated = try SolariEvidenceValidator(now: now).validate(result(for: plan), for: plan)
        XCTAssertEqual(validated.result.basket.observedSubtotal, Decimal(string: "9.47"))
        XCTAssertEqual(validated.result.provenance.accessBoundary, .appleAppAttest)
        XCTAssertEqual(validated.result.optimizer.method, .sandbox)
    }

    func testValidatorRejectsMismatchedDerivedSourceURL() throws {
        let plan = eligiblePlan(items: [demoItems()[0]], now: now)
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
            collectionMethod: observation.collectionMethod,
            freshness: observation.freshness
        )
        let mutated = replacing(original, observations: [invalid])
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(mutated, for: plan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidObservationReference)
        }
    }

    func testValidatorRejectsInvalidTrustBoundary() throws {
        let plan = eligiblePlan(items: [demoItems()[0]], now: now)
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
            optimizer: original.optimizer,
            provenance: original.provenance,
            trust: invalidTrust
        )
        XCTAssertThrowsError(try SolariEvidenceValidator(now: now).validate(mutated, for: plan)) {
            XCTAssertEqual($0 as? SolariEvidenceContractError, .invalidProvenance)
        }
    }

    func testMemoryCacheExpiresAndRefreshBypassesWithoutPersistence() {
        let plan = eligiblePlan(items: [demoItems()[0]], now: now)
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
        let payload = Data("{\"schemaVersion\":\"solari-shopping-research-request-v2\"}".utf8)
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
            items: [demoItems()[0]],
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
        let requirement = plan.request.requirements[0]
        let productID = requirement.candidateProductIDs[0]
        let observation = SolariRetailerObservation(
            schemaVersion: SolariRetailerEvidenceSchema.observationVersion,
            observationID: "obs-\(productID)",
            requirementID: requirement.id,
            retailerProductID: productID,
            sourceURL: plan.sourceURLsByProductID[productID]!,
            title: "Demo Chicken Breasts",
            packageDescription: "3 lb synthetic package",
            packageQuantity: 3,
            packageUnit: .pound,
            visiblePrice: Decimal(string: "9.47"),
            currency: "USD",
            observedAt: now.addingTimeInterval(-5),
            confidence: .high,
            ambiguityReasons: [],
            collectionMethod: .controlledDemo,
            freshness: SolariObservationFreshness(status: .fresh, ageSeconds: 5, maxAgeSeconds: 86_400)
        )
        let decision = SolariBasketDecision(
            schemaVersion: SolariRetailerEvidenceSchema.decisionVersion,
            requirementID: requirement.id,
            observationID: observation.observationID,
            packageCount: 1,
            requiredQuantity: requirement.requiredQuantity,
            coveredQuantity: 3,
            quantityUnit: .pound,
            surplusQuantity: 3 - requirement.requiredQuantity,
            lineTotal: Decimal(string: "9.47"),
            currency: "USD",
            proteinGramsPerDollar: nil,
            substitutionNote: nil,
            rationale: ["Smallest sufficient admitted package."],
            confidence: .high,
            ambiguityReasons: []
        )
        return SolariResearchResult(
            schemaVersion: SolariRetailerEvidenceSchema.resultVersion,
            requestID: plan.request.requestID,
            demoID: plan.request.demoID,
            retailerID: plan.request.retailerID,
            completedAt: now,
            executionMode: .live,
            status: .complete,
            observations: [observation],
            decisions: [decision],
            basket: SolariBasketSummary(
                completeness: .complete,
                observedSubtotal: Decimal(string: "9.47"),
                currency: "USD",
                pricedLineCount: 1,
                missingPriceLineCount: 0,
                unmatchedRequirementCount: 0
            ),
            optimizer: SolariOptimizerProvenance(
                method: .sandbox,
                algorithmVersion: "smallest-sufficient-package-v2",
                independentlyVerified: true
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
