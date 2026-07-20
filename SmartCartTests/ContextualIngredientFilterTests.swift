import CryptoKit
import Foundation
import XCTest
@testable import SmartCart

final class ContextualIngredientFilterTests: XCTestCase {
    private typealias Filter = ContextualIngredientFilter

    private enum Split { case development, heldOut }

    private enum Category: String, CaseIterable {
        case ocrFixture
        case multiColumnGeometry
        case crossRowOrCard
        case decorativeProse
        case structuredURL
        case pinterest
        case flatPastedList
        case quantityless
        case ambiguousNounVerb
        case nutritionOrMetadata
        case nonRecipe
        case mixedIngredientInstruction
    }

    private enum Source {
        case cameraPhoto, photoLibrary, screenshot, multiPageScan
        case structuredURL, pinterest, pastedText, groceryList, unknown

        var filterKind: Filter.DocumentSource.Kind {
            switch self {
            case .cameraPhoto: .cameraPhoto
            case .photoLibrary: .photoLibrary
            case .screenshot: .screenshot
            case .multiPageScan: .multiPageScan
            case .structuredURL: .structuredURL
            case .pinterest: .pinterest
            case .pastedText: .pastedText
            case .groceryList: .groceryList
            case .unknown: .unknown
            }
        }

        var requiresGeometry: Bool {
            switch self {
            case .cameraPhoto, .photoLibrary, .screenshot, .multiPageScan: true
            case .structuredURL, .pinterest, .pastedText, .groceryList, .unknown: false
            }
        }
    }

    private struct SpatialAddress {
        var page: Int = 0
        var column: Int = 0
        var section: String = "main"
    }

    private struct Document {
        var id: String
        var split: Split
        var source: Source
        var categories: Set<Category>
        var rawLines: [String]
        var spatialAddresses: [SpatialAddress]?

        var lineIDs: [String] {
            rawLines.indices.map { String(format: "%@-l%02d", id, $0 + 1) }
        }

        var records: [Filter.LineRecord] {
            zip(lineIDs, rawLines).enumerated().map { index, pair in
                let (lineID, text) = pair
                guard source.requiresGeometry else {
                    return .init(id: lineID, originalText: text, ordinal: index)
                }
                let address = spatialAddresses?[safe: index] ?? SpatialAddress(section: "\(id)-main")
                let row = spatialAddresses?[..<(index + 1)].filter {
                    $0.page == address.page && $0.column == address.column
                }.count ?? (index + 1)
                let box = OCRNormalizedBoundingBox(
                    x: 0.06 + (Double(address.column) * 0.47),
                    y: max(0.05, 0.94 - (Double(row) * 0.075)),
                    width: 0.38,
                    height: 0.045
                )
                return .init(
                    id: lineID,
                    originalText: text,
                    ordinal: index,
                    evidence: .init(
                        pageIndex: address.page,
                        columnIndex: address.column,
                        sectionID: "\(id)-\(address.section)",
                        sectionName: address.section,
                        boundingBox: box,
                        sourceConfidence: 0.93,
                        sourceObservationIDs: ["\(lineID)-observation"]
                    )
                )
            }
        }
    }

    private struct Oracle {
        var accepted: Set<String>
        var pureInstructions: Set<String> = []
        var sanitizedText: [String: String] = [:]
    }

    private struct Metrics {
        var truePositive = 0
        var falsePositive = 0
        var falseNegative = 0
        var pureInstructionLeak = 0
        var pureInstructionTotal = 0
        var mixedSuffixLeak = 0
        var mixedSuffixTotal = 0
        var divergenceCount = 0
        var beneficialDivergence = 0
        var harmfulDivergence = 0
        var falsePositiveDetails: [String] = []
        var falseNegativeDetails: [String] = []
        var suffixFailureDetails: [String] = []

        var precision: Double { ratio(truePositive, truePositive + falsePositive) }
        var recall: Double { ratio(truePositive, truePositive + falseNegative) }
        var instructionLeakage: Double {
            ratio(pureInstructionLeak + mixedSuffixLeak, pureInstructionTotal + mixedSuffixTotal)
        }
        var ingredientOmission: Double { ratio(falseNegative, truePositive + falseNegative) }

        private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
            denominator == 0 ? 0 : Double(numerator) / Double(denominator)
        }
    }

    func testMixedInstructionSuffixKeepsLineIdentityAndEvidence() throws {
        let box = OCRNormalizedBoundingBox(x: 0.12, y: 0.68, width: 0.51, height: 0.06)
        let evidence = Filter.LineEvidence(
            pageIndex: 2,
            columnIndex: 1,
            sectionID: "ingredients-card",
            sectionName: "Ingredients",
            boundingBox: box,
            sourceConfidence: 0.91,
            sourceObservationIDs: ["vision-42"]
        )
        let original = "1 tsp flaky sea salt, EASY AS 1-2-3! Mash banana. Stir in peanut butter."
        let record = Filter.LineRecord(
            id: "evidence-l01",
            originalText: original,
            ordinal: 0,
            evidence: evidence
        )

        let result = Filter.filter(
            [
                .init(id: "evidence-heading", originalText: "Ingredients", ordinal: 0),
                record
            ],
            source: .init(kind: .screenshot, documentID: "evidence", detail: "unit fixture"),
            using: .contextual
        )
        let accepted = try XCTUnwrap(result.accepted.first)

        XCTAssertEqual(result.acceptedLineIDs, ["evidence-l01"])
        XCTAssertEqual(accepted.originalText, original)
        XCTAssertEqual(accepted.sanitizedText, "1 tsp flaky sea salt")
        XCTAssertEqual(accepted.removedSuffix, "EASY AS 1-2-3! Mash banana. Stir in peanut butter.")
        XCTAssertEqual(accepted.evidence, evidence)
        XCTAssertEqual(accepted.evidence.boundingBox, box)
        XCTAssertTrue(accepted.reviewReasons.contains(.instructionSuffixRemoved))
    }

    func testOCRSourceLineInitializerPreservesDiscreteProvenance() throws {
        let sourceLine = OCRSourceLine(
            text: "2 cups all-purpose flour",
            pageIndex: 1,
            boundingBox: .init(x: 0.08, y: 0.77, width: 0.36, height: 0.04),
            confidence: 0.87,
            alternateCandidates: [.init(text: "12 cups all-purpose flour", confidence: 0.43)],
            columnIndex: 0,
            sourceObservationIDs: ["ocr-a", "ocr-b"],
            continuationAttached: true,
            reconstructionConfidence: 0.82
        )
        let record = Filter.LineRecord(
            id: "ocr-evidence-l01",
            ordinal: 1,
            ocrSourceLine: sourceLine,
            sectionID: "page-1-ingredients",
            sectionName: "Ingredients"
        )

        let result = Filter.filter(
            [
                .init(id: "ocr-evidence-heading", originalText: "Ingredients", ordinal: 0),
                record
            ],
            source: .init(kind: .multiPageScan, documentID: "ocr-evidence"),
            using: .contextual
        )
        let accepted = try XCTUnwrap(result.accepted.first)

        XCTAssertEqual(accepted.lineID, "ocr-evidence-l01")
        XCTAssertEqual(accepted.originalText, sourceLine.text)
        XCTAssertEqual(accepted.evidence.pageIndex, 1)
        XCTAssertEqual(accepted.evidence.columnIndex, 0)
        XCTAssertEqual(accepted.evidence.sectionID, "page-1-ingredients")
        XCTAssertEqual(accepted.evidence.sectionName, "Ingredients")
        XCTAssertEqual(accepted.evidence.boundingBox, sourceLine.boundingBox)
        XCTAssertEqual(accepted.evidence.sourceConfidence, 0.82)
        XCTAssertEqual(accepted.evidence.sourceObservationIDs, ["ocr-a", "ocr-b"])
    }

    func testAllExistingOCRFixtureAssetsFlowThroughEvidenceAwareFilter() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/OCR", isDirectory: true)
        let expectedAssets: Set<String> = [
            "chocolate_chip_cookie_bars_exact.jpeg",
            "chocolate_chip_cookie_bars_vision_observations.json",
            "cross_region_banana_peanut_butter_observations.json",
            "two_column_chocolate_chip_expected.txt",
            "two_column_chocolate_chip_ignored_instructions.txt",
            "two_column_chocolate_chip_observations.json"
        ]
        let actualAssets = Set(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { !$0.hasPrefix(".") }
        )
        XCTAssertEqual(actualAssets, expectedAssets, "Update the labeled OCR corpus when fixture assets change")
        let exactJPEG = try Data(contentsOf: directory.appendingPathComponent("chocolate_chip_cookie_bars_exact.jpeg"))
        XCTAssertEqual(
            SHA256.hash(data: exactJPEG).map { String(format: "%02x", $0) }.joined(),
            "1833d4b0c53c0a78d67f5de764d30c5c03aee7e8ce868b84d53f2845c2b053d7"
        )

        let specifications: [(slug: String, file: String, expectedLineCount: Int)] = [
            ("two-column", "two_column_chocolate_chip_observations.json", 5),
            ("cross-region", "cross_region_banana_peanut_butter_observations.json", 1),
            ("cookie-bars", "chocolate_chip_cookie_bars_vision_observations.json", 5)
        ]
        for specification in specifications {
            let observations = try JSONDecoder().decode(
                [OCRTextObservation].self,
                from: Data(contentsOf: directory.appendingPathComponent(specification.file))
            )
            let reconstruction = OCRLayoutReconstructor().reconstruct(observations)
            XCTAssertEqual(reconstruction.ingredientSourceLines.count, specification.expectedLineCount)
            let records = reconstruction.ingredientSourceLines.enumerated().map { index, sourceLine in
                Filter.LineRecord(
                    id: String(format: "ocr-%@-l%02d", specification.slug, index + 1),
                    ordinal: index,
                    ocrSourceLine: sourceLine,
                    sectionID: "\(specification.slug)-ingredients",
                    sectionName: "Ingredients"
                )
            }
            let result = Filter.filter(
                records,
                source: .init(kind: .screenshot, documentID: "ocr-\(specification.slug)"),
                using: .contextual
            )
            XCTAssertEqual(result.acceptedLineIDs, records.map(\.id), specification.file)
            for (accepted, sourceLine) in zip(result.accepted, reconstruction.ingredientSourceLines) {
                XCTAssertEqual(accepted.originalText, sourceLine.text)
                XCTAssertEqual(accepted.evidence.pageIndex, sourceLine.pageIndex)
                XCTAssertEqual(accepted.evidence.columnIndex, sourceLine.columnIndex)
                XCTAssertEqual(accepted.evidence.sectionName, "Ingredients")
                XCTAssertEqual(accepted.evidence.boundingBox, sourceLine.boundingBox)
                XCTAssertEqual(accepted.evidence.sourceObservationIDs, sourceLine.sourceObservationIDs)
            }

            if specification.slug == "two-column" {
                let expectedText = String(
                    decoding: try Data(contentsOf: directory.appendingPathComponent("two_column_chocolate_chip_expected.txt")),
                    as: UTF8.self
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                let expectedIgnored = String(
                    decoding: try Data(contentsOf: directory.appendingPathComponent("two_column_chocolate_chip_ignored_instructions.txt")),
                    as: UTF8.self
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertEqual(reconstruction.reconstructedText, expectedText)
                XCTAssertEqual(reconstruction.ignoredInstructionLines.joined(separator: "\n"), expectedIgnored)
            }
        }
    }

    func testIndependentDevelopmentSpatialExpansionMetricsAndIntegrity() {
        let documents = Self.independentSpatialDevelopmentDocuments
        let oracleMap = Self.independentSpatialDevelopmentOracles
        let expectedIDs = (73...96).map { String(format: "d%03d", $0) }

        XCTAssertEqual(documents.count, 24)
        XCTAssertEqual(documents.map(\.id), expectedIDs)
        XCTAssertTrue(documents.allSatisfy { $0.split == .development })
        XCTAssertEqual(Set(documents.map(\.id)).count, documents.count)
        XCTAssertEqual(Set(oracleMap.keys), Set(expectedIDs))
        XCTAssertGreaterThanOrEqual(
            documents.filter { $0.categories.contains(.multiColumnGeometry) }.count,
            10
        )
        XCTAssertGreaterThanOrEqual(
            documents.filter { $0.categories.contains(.crossRowOrCard) }.count,
            10
        )
        XCTAssertGreaterThanOrEqual(
            documents.filter { $0.categories.contains(.ocrFixture) }.count,
            5
        )

        for document in documents {
            let oracle = oracleMap[document.id]!
            let records = document.records
            let lineIDs = Set(document.lineIDs)
            XCTAssertEqual(records.count, document.rawLines.count, document.id)
            XCTAssertTrue(oracle.accepted.isSubset(of: lineIDs), document.id)
            XCTAssertTrue(oracle.pureInstructions.isSubset(of: lineIDs), document.id)
            XCTAssertTrue(Set(oracle.sanitizedText.keys).isSubset(of: oracle.accepted), document.id)
            if document.source.requiresGeometry {
                XCTAssertEqual(document.spatialAddresses?.count, document.rawLines.count, document.id)
            }

            let result = Filter.filter(
                records,
                source: .init(
                    kind: document.source.filterKind,
                    documentID: document.id,
                    detail: "independent-spatial-development-corpus"
                ),
                using: .contextual
            )
            XCTAssertEqual(result.decisions.map(\.record), records, "Line records changed in \(document.id)")
            XCTAssertEqual(
                result.decisions.map(\.lineID),
                document.lineIDs,
                "Decision order changed in \(document.id)"
            )
            XCTAssertEqual(
                result.acceptedLineIDs,
                document.lineIDs.filter { oracle.accepted.contains($0) },
                "Accepted order changed in \(document.id)"
            )
        }

        let contextual = Self.evaluateIndependentSpatialDevelopment(using: .contextual)
        let legacy = Self.evaluateIndependentSpatialDevelopment(using: .legacy)
        let diagnostics = "TP=\(contextual.truePositive) FP=\(contextual.falsePositive) FN=\(contextual.falseNegative) P=\(contextual.precision) R=\(contextual.recall) omission=\(contextual.ingredientOmission) leakage=\(contextual.instructionLeakage)\nFP: \(contextual.falsePositiveDetails.joined(separator: " | "))\nFN: \(contextual.falseNegativeDetails.joined(separator: " | "))\nSuffix: \(contextual.suffixFailureDetails.joined(separator: " | "))"

        XCTAssertEqual(contextual.falsePositive, 0, diagnostics)
        XCTAssertEqual(contextual.falseNegative, 0, diagnostics)
        XCTAssertEqual(contextual.pureInstructionLeak, 0, diagnostics)
        XCTAssertEqual(contextual.mixedSuffixLeak, 0, diagnostics)
        XCTAssertGreaterThanOrEqual(contextual.precision, 0.90, diagnostics)
        XCTAssertGreaterThanOrEqual(contextual.recall, 0.90, diagnostics)
        XCTAssertLessThanOrEqual(contextual.instructionLeakage, 0.05, diagnostics)
        XCTAssertLessThanOrEqual(contextual.ingredientOmission, 0.10, diagnostics)
        XCTAssertGreaterThan(contextual.divergenceCount, 0)
        XCTAssertGreaterThan(contextual.beneficialDivergence, contextual.harmfulDivergence)
        XCTAssertGreaterThanOrEqual(contextual.recall, legacy.recall, diagnostics)
        XCTAssertLessThanOrEqual(contextual.instructionLeakage, legacy.instructionLeakage)
    }

    func testCorpusIntegrityAndMinimumCategoryGates() {
        let documents = Self.developmentDocuments + Self.heldOutDocuments
        let oracleMap = Self.oracles
        XCTAssertTrue((100...150).contains(documents.count), "Corpus must remain between 100 and 150 documents")
        XCTAssertEqual(documents.count, 120)
        XCTAssertEqual(Self.developmentDocuments.count, 72)
        XCTAssertEqual(Self.heldOutDocuments.count, 48)
        XCTAssertGreaterThanOrEqual(Self.heldOutDocuments.count, 40)
        XCTAssertTrue(Self.developmentDocuments.allSatisfy { $0.split == .development })
        XCTAssertTrue(Self.heldOutDocuments.allSatisfy { $0.split == .heldOut })
        XCTAssertTrue(
            Set(Self.developmentDocuments.map(\.id))
                .isDisjoint(with: Set(Self.heldOutDocuments.map(\.id)))
        )
        XCTAssertEqual(Set(documents.map(\.id)).count, documents.count)
        XCTAssertEqual(Set(oracleMap.keys), Set(documents.map(\.id)))

        for document in documents {
            let lineIDs = Set(document.lineIDs)
            let oracle = oracleMap[document.id]!
            XCTAssertEqual(lineIDs.count, document.rawLines.count, "Duplicate line IDs in \(document.id)")
            XCTAssertTrue(oracle.accepted.isSubset(of: lineIDs), "Unknown accepted ID in \(document.id)")
            XCTAssertTrue(oracle.pureInstructions.isSubset(of: lineIDs), "Unknown instruction ID in \(document.id)")
            XCTAssertTrue(Set(oracle.sanitizedText.keys).isSubset(of: oracle.accepted))
            XCTAssertTrue(oracle.accepted.isDisjoint(with: oracle.pureInstructions))
            if document.source.requiresGeometry {
                if let spatialAddresses = document.spatialAddresses {
                    XCTAssertEqual(spatialAddresses.count, document.rawLines.count)
                }
                XCTAssertEqual(document.records.count, document.records.filter {
                    $0.evidence.pageIndex != nil && $0.evidence.columnIndex != nil
                        && $0.evidence.boundingBox != nil && !$0.evidence.sourceObservationIDs.isEmpty
                }.count)
            }
        }

        let minimums: [Category: Int] = [
            .multiColumnGeometry: 10, .crossRowOrCard: 10, .decorativeProse: 10,
            .structuredURL: 10, .pinterest: 5, .flatPastedList: 10,
            .quantityless: 10, .ambiguousNounVerb: 10, .nutritionOrMetadata: 10,
            .nonRecipe: 10, .mixedIngredientInstruction: 10
        ]
        for (category, minimum) in minimums {
            XCTAssertGreaterThanOrEqual(
                documents.filter { $0.categories.contains(category) }.count,
                minimum,
                "Category gate regressed: \(category.rawValue)"
            )
        }
        XCTAssertGreaterThanOrEqual(documents.filter { $0.categories.contains(.ocrFixture) }.count, 3)
    }

    func testDevelopmentCorpusMetricsAndContextualLegacyDivergence() {
        let contextual = Self.evaluate(Self.developmentDocuments, using: .contextual)
        let legacy = Self.evaluate(Self.developmentDocuments, using: .legacy)

        let diagnostics = "TP=\(contextual.truePositive) FP=\(contextual.falsePositive) FN=\(contextual.falseNegative) P=\(contextual.precision) R=\(contextual.recall) omission=\(contextual.ingredientOmission) leakage=\(contextual.instructionLeakage)\nFP: \(contextual.falsePositiveDetails.joined(separator: " | "))\nFN: \(contextual.falseNegativeDetails.joined(separator: " | "))\nSuffix: \(contextual.suffixFailureDetails.joined(separator: " | "))"
        XCTAssertGreaterThanOrEqual(contextual.precision, 0.90, diagnostics)
        XCTAssertGreaterThanOrEqual(contextual.recall, 0.90, diagnostics)
        XCTAssertLessThanOrEqual(contextual.instructionLeakage, 0.05, diagnostics)
        XCTAssertLessThanOrEqual(contextual.ingredientOmission, 0.10, diagnostics)
        XCTAssertGreaterThan(contextual.divergenceCount, 0)
        XCTAssertGreaterThan(contextual.beneficialDivergence, contextual.harmfulDivergence)
        XCTAssertGreaterThanOrEqual(contextual.recall, legacy.recall, diagnostics)
        XCTAssertLessThanOrEqual(contextual.instructionLeakage, legacy.instructionLeakage)
    }

    func testDefaultFilterRemainsLegacyAuthoritative() {
        let records: [Filter.LineRecord] = [
            .init(id: "default-heading", originalText: "Ingredients", ordinal: 0),
            .init(id: "default-ambiguous", originalText: "Toast the bread", ordinal: 1),
            .init(id: "default-flour", originalText: "1 cup flour", ordinal: 2)
        ]
        let source = Filter.DocumentSource(kind: .pastedText, documentID: "default-posture")

        let implicit = Filter.filter(records, source: source)
        let legacy = Filter.filter(records, source: source, using: .legacy)
        let contextual = Filter.filter(records, source: source, using: .contextual)

        XCTAssertEqual(implicit, legacy)
        XCTAssertEqual(implicit.classifierVersion, .legacy)
        XCTAssertTrue(implicit.acceptedLineIDs.contains("default-ambiguous"))
        XCTAssertFalse(contextual.acceptedLineIDs.contains("default-ambiguous"))
    }

    #if DEBUG
    func testRecipeParserShadowMapsEverySourceKindExplicitly() {
        let pageZero = OCRSourceLine(
            text: "1 cup flour",
            pageIndex: 0,
            boundingBox: .init(x: 0.1, y: 0.7, width: 0.4, height: 0.05),
            confidence: 0.9,
            alternateCandidates: []
        )
        let pageOne = OCRSourceLine(
            text: "2 eggs",
            pageIndex: 1,
            boundingBox: .init(x: 0.1, y: 0.6, width: 0.4, height: 0.05),
            confidence: 0.9,
            alternateCandidates: []
        )
        let cases: [(RecipeSource, String, [OCRSourceLine], Filter.DocumentSource.Kind)] = [
            (.photo, "Captured with SmartCart", [pageZero], .cameraPhoto),
            (.photo, "Imported from Photos", [pageZero], .photoLibrary),
            (.photo, "Shared recipe image", [pageZero], .screenshot),
            (.photo, "Captured with SmartCart", [pageZero, pageOne], .multiPageScan),
            (.link, "example.com", [], .structuredURL),
            (.pinterest, "pinterest.com", [], .pinterest),
            (.text, "Pasted into SmartCart", [], .pastedText),
            (.sample, "SmartCart sample recipe", [], .groceryList)
        ]

        for (source, detail, sourceLines, expectedKind) in cases {
            let report = RecipeParser.contextualShadowReport(
                text: "1 cup flour\n2 eggs",
                source: source,
                sourceDetail: detail,
                sourceLines: sourceLines,
                authoritativeAcceptedLineOrdinals: []
            )
            XCTAssertEqual(report.source.kind, expectedKind, detail)
        }
    }

    func testRecipeParserShadowPreservesLinesAndConsumptivelyMapsOCREvidence() {
        let flour = OCRSourceLine(
            text: "1 cup flour",
            pageIndex: 0,
            boundingBox: .init(x: 0.08, y: 0.78, width: 0.34, height: 0.04),
            confidence: 0.96,
            alternateCandidates: [],
            sourceObservationIDs: ["ocr-flour"]
        )
        let correctedEggs = OCRSourceLine(
            text: "2 large br0wn eggs",
            pageIndex: 0,
            boundingBox: .init(x: 0.08, y: 0.70, width: 0.34, height: 0.04),
            confidence: 0.84,
            alternateCandidates: [],
            sourceObservationIDs: ["ocr-eggs"]
        )
        let salt = OCRSourceLine(
            text: "1 tsp salt",
            pageIndex: 0,
            boundingBox: .init(x: 0.08, y: 0.62, width: 0.34, height: 0.04),
            confidence: 0.93,
            alternateCandidates: [],
            sourceObservationIDs: ["ocr-salt"]
        )
        let text = "Ingredients\n\n1 cup fl0ur\n1 cup flour\n2 large brown eggs\n1 tsp salt\n1 tsp salt\nDirections"

        let report = RecipeParser.contextualShadowReport(
            text: text,
            source: .photo,
            sourceDetail: "Captured with SmartCart",
            sourceLines: [correctedEggs, flour, salt],
            authoritativeAcceptedLineOrdinals: []
        )
        let repeated = RecipeParser.contextualShadowReport(
            text: text,
            source: .photo,
            sourceDetail: "Captured with SmartCart",
            sourceLines: [correctedEggs, flour, salt],
            authoritativeAcceptedLineOrdinals: []
        )

        XCTAssertEqual(report.records.map(\.originalText), text.components(separatedBy: .newlines))
        XCTAssertEqual(report.records.map(\.ordinal), Array(report.records.indices))
        XCTAssertEqual(Set(report.records.map(\.id)).count, report.records.count)
        XCTAssertEqual(report.records.map(\.id), repeated.records.map(\.id))
        XCTAssertEqual(report.records[1].originalText, "")
        XCTAssertEqual(report.records[1].evidence, .none)

        // The later exact line reserves the only flour observation before fuzzy matching.
        XCTAssertEqual(report.records[2].evidence, .none)
        XCTAssertEqual(report.records[3].evidence.sourceObservationIDs, ["ocr-flour"])

        // Corrected parser text remains authoritative while OCR evidence stays attached.
        XCTAssertEqual(report.records[4].originalText, "2 large brown eggs")
        XCTAssertEqual(report.records[4].evidence.sourceObservationIDs, ["ocr-eggs"])
        XCTAssertEqual(report.records[4].evidence.boundingBox, correctedEggs.boundingBox)
        XCTAssertEqual(report.records[4].evidence.sectionID, "ocr-ingredient-stream")
        XCTAssertEqual(report.records[4].evidence.sectionName, "Ingredients")

        // Duplicate input cannot reuse a source observation after it is consumed.
        XCTAssertEqual(report.records[5].evidence.sourceObservationIDs, ["ocr-salt"])
        XCTAssertEqual(report.records[6].evidence, .none)
        XCTAssertEqual(report.records.map(\.ordinal), report.records.indices.map { $0 })
    }

    func testRecipeParserOutputStaysLegacyWhileShadowExposesDivergence() {
        let text = "Ingredients\nToast the bread\n1 cup flour\nDirections\nMix until smooth."

        let recipe = RecipeParser.parse(title: "Legacy authority", text: text)
        let report = RecipeParser.contextualShadowReport(
            text: text,
            authoritativeAcceptedLineOrdinals: [1, 2]
        )
        let authoritativeTexts = report.authoritativeAcceptedLineIDs.compactMap { lineID in
            report.records.first(where: { $0.id == lineID })?.originalText
        }

        XCTAssertEqual(recipe.ingredients.map(\.rawText), ["Toast the bread", "1 cup flour"])
        XCTAssertEqual(recipe.ingredients.map(\.rawText), authoritativeTexts)
        XCTAssertEqual(report.contextualResult.accepted.map(\.sanitizedText), ["1 cup flour"])
        XCTAssertEqual(report.divergence.divergences.map(\.originalText), ["Toast the bread"])
        XCTAssertEqual(report.divergence.comparedLineCount, text.components(separatedBy: .newlines).count)
    }
    #endif

    func testFrozenHeldOutCorpusDoesNotRegressAgainstLegacy() {
        let contextual = Self.evaluate(Self.heldOutDocuments, using: .contextual)
        let legacy = Self.evaluate(Self.heldOutDocuments, using: .legacy)

        XCTAssertGreaterThanOrEqual(contextual.precision, 0.88)
        XCTAssertGreaterThanOrEqual(contextual.recall, 0.88)
        XCTAssertLessThanOrEqual(contextual.instructionLeakage, 0.06)
        XCTAssertLessThanOrEqual(contextual.ingredientOmission, 0.12)
        XCTAssertGreaterThan(contextual.divergenceCount, 0)
        XCTAssertGreaterThanOrEqual(contextual.precision, legacy.precision)
        XCTAssertGreaterThanOrEqual(contextual.recall, legacy.recall)
        XCTAssertLessThanOrEqual(contextual.instructionLeakage, legacy.instructionLeakage)
    }
}

private extension ContextualIngredientFilterTests {
    private static func evaluate(
        _ documents: [Document],
        using version: Filter.ClassifierVersion
    ) -> Metrics {
        var metrics = Metrics()
        let oracleMap = oracles
        for document in documents {
            let oracle = oracleMap[document.id]!
            let source = Filter.DocumentSource(
                kind: document.source.filterKind,
                documentID: document.id,
                detail: "deterministic-labeled-corpus"
            )
            let result = Filter.filter(document.records, source: source, using: version)
            let predicted = Set(result.acceptedLineIDs)
            let falsePositives = predicted.subtracting(oracle.accepted)
            let falseNegatives = oracle.accepted.subtracting(predicted)
            metrics.truePositive += predicted.intersection(oracle.accepted).count
            metrics.falsePositive += falsePositives.count
            metrics.falseNegative += falseNegatives.count
            metrics.pureInstructionTotal += oracle.pureInstructions.count
            metrics.pureInstructionLeak += predicted.intersection(oracle.pureInstructions).count
            metrics.mixedSuffixTotal += oracle.sanitizedText.count

            let acceptedByID = Dictionary(uniqueKeysWithValues: result.accepted.map { ($0.lineID, $0) })
            let decisionsByID = Dictionary(uniqueKeysWithValues: result.decisions.map { ($0.lineID, $0) })
            for lineID in falsePositives.sorted() {
                let decision = decisionsByID[lineID]
                metrics.falsePositiveDetails.append(
                    "\(lineID)[\(document.source)] text=\(decision?.originalText ?? "?") reason=\(String(describing: decision?.acceptanceReason))"
                )
            }
            for lineID in falseNegatives.sorted() {
                let decision = decisionsByID[lineID]
                metrics.falseNegativeDetails.append(
                    "\(lineID)[\(document.source)] text=\(decision?.originalText ?? "?") ignored=\(decision?.ignoredReasons.map(\.rawValue).joined(separator: ",") ?? "missing")"
                )
            }
            for (lineID, expectedSanitized) in oracle.sanitizedText {
                if acceptedByID[lineID]?.sanitizedText != expectedSanitized
                    || acceptedByID[lineID]?.reviewReasons.contains(.instructionSuffixRemoved) != true {
                    metrics.mixedSuffixLeak += 1
                    metrics.suffixFailureDetails.append(
                        "\(lineID) expected=\(expectedSanitized) actual=\(acceptedByID[lineID]?.sanitizedText ?? "not accepted")"
                    )
                }
            }

            if version == .contextual {
                let shadow = Filter.developmentShadowReport(for: document.records, source: source)
                metrics.divergenceCount += shadow.divergences.count
                for divergence in shadow.divergences {
                    let legacyCorrect = (divergence.legacyDisposition == .accepted) == oracle.accepted.contains(divergence.lineID)
                    let contextualCorrect = (divergence.contextualDisposition == .accepted) == oracle.accepted.contains(divergence.lineID)
                    if contextualCorrect && !legacyCorrect { metrics.beneficialDivergence += 1 }
                    if legacyCorrect && !contextualCorrect { metrics.harmfulDivergence += 1 }
                }
            }
        }
        return metrics
    }

    private static func evaluateIndependentSpatialDevelopment(
        using version: Filter.ClassifierVersion
    ) -> Metrics {
        var metrics = Metrics()
        let documents = independentSpatialDevelopmentDocuments
        let oracleMap = independentSpatialDevelopmentOracles
        for document in documents {
            let oracle = oracleMap[document.id]!
            let source = Filter.DocumentSource(
                kind: document.source.filterKind,
                documentID: document.id,
                detail: "independent-spatial-development-corpus"
            )
            let result = Filter.filter(document.records, source: source, using: version)
            let predicted = Set(result.acceptedLineIDs)
            let falsePositives = predicted.subtracting(oracle.accepted)
            let falseNegatives = oracle.accepted.subtracting(predicted)
            metrics.truePositive += predicted.intersection(oracle.accepted).count
            metrics.falsePositive += falsePositives.count
            metrics.falseNegative += falseNegatives.count
            metrics.pureInstructionTotal += oracle.pureInstructions.count
            metrics.pureInstructionLeak += predicted.intersection(oracle.pureInstructions).count
            metrics.mixedSuffixTotal += oracle.sanitizedText.count

            let acceptedByID = Dictionary(uniqueKeysWithValues: result.accepted.map { ($0.lineID, $0) })
            let decisionsByID = Dictionary(uniqueKeysWithValues: result.decisions.map { ($0.lineID, $0) })
            for lineID in falsePositives.sorted() {
                let decision = decisionsByID[lineID]
                metrics.falsePositiveDetails.append(
                    "\(lineID)[\(document.source)] text=\(decision?.originalText ?? "?") reason=\(String(describing: decision?.acceptanceReason))"
                )
            }
            for lineID in falseNegatives.sorted() {
                let decision = decisionsByID[lineID]
                metrics.falseNegativeDetails.append(
                    "\(lineID)[\(document.source)] text=\(decision?.originalText ?? "?") ignored=\(decision?.ignoredReasons.map(\.rawValue).joined(separator: ",") ?? "missing")"
                )
            }
            for (lineID, expectedSanitized) in oracle.sanitizedText {
                if acceptedByID[lineID]?.sanitizedText != expectedSanitized
                    || acceptedByID[lineID]?.reviewReasons.contains(.instructionSuffixRemoved) != true {
                    metrics.mixedSuffixLeak += 1
                    metrics.suffixFailureDetails.append(
                        "\(lineID) expected=\(expectedSanitized) actual=\(acceptedByID[lineID]?.sanitizedText ?? "not accepted")"
                    )
                }
            }

            if version == .contextual {
                let shadow = Filter.developmentShadowReport(for: document.records, source: source)
                metrics.divergenceCount += shadow.divergences.count
                for divergence in shadow.divergences {
                    let legacyCorrect = (divergence.legacyDisposition == .accepted)
                        == oracle.accepted.contains(divergence.lineID)
                    let contextualCorrect = (divergence.contextualDisposition == .accepted)
                        == oracle.accepted.contains(divergence.lineID)
                    if contextualCorrect && !legacyCorrect { metrics.beneficialDivergence += 1 }
                    if legacyCorrect && !contextualCorrect { metrics.harmfulDivergence += 1 }
                }
            }
        }
        return metrics
    }

    private static func d(
        _ id: String,
        _ split: Split,
        _ source: Source,
        _ categories: Set<Category>,
        _ lines: [String],
        spatial: [SpatialAddress]? = nil
    ) -> Document {
        Document(
            id: id,
            split: split,
            source: source,
            categories: categories,
            rawLines: lines,
            spatialAddresses: spatial
        )
    }

    private static func o(
        _ accepted: Set<String>,
        instructions: Set<String> = [],
        sanitized: [String: String] = [:]
    ) -> Oracle {
        Oracle(accepted: accepted, pureInstructions: instructions, sanitizedText: sanitized)
    }

    private static func spatial(
        _ columns: [Int],
        sections: [String]? = nil,
        pages: [Int]? = nil
    ) -> [SpatialAddress] {
        columns.indices.map { index in
            SpatialAddress(
                page: pages?[safe: index] ?? 0,
                column: columns[index],
                section: sections?[safe: index] ?? "main"
            )
        }
    }
}

private extension ContextualIngredientFilterTests {
    private static var developmentDocuments: [Document] {
        [
            d("d001", .development, .pastedText, [.decorativeProse], ["Sunday Cloud Cake", "This tender favorite tastes like a warm afternoon at Grandma’s.", "Ingredients", "2 cups all-purpose flour"]),
            d("d002", .development, .screenshot, [.decorativeProse], ["Silky Tomato Supper", "Cozy, bright, and made for rainy nights.", "1 cup heavy cream", "Whisk until the soup turns smooth."]),
            d("d003", .development, .cameraPhoto, [.decorativeProse], ["“The cookie everyone asks me to bring.”", "WHAT YOU NEED", "1 cup packed brown sugar", "½ cup unsalted butter"]),
            d("d004", .development, .pastedText, [.decorativeProse, .mixedIngredientInstruction], ["A no-fuss loaf for slow mornings.", "Ingredients", "2 cups all-purpose flour. Mix with the salt in a large bowl.", "Bake until deeply golden."]),
            d("d005", .development, .photoLibrary, [.decorativeProse], ["Bright berry magic in every spoonful.", "TOPPING", "½–¾ cup fresh raspberries", "for topping"]),
            d("d006", .development, .pastedText, [.decorativeProse], ["One-Pot Rice for Busy People", "The kind of dinner that practically makes itself.", "1½ cups long-grain white rice", "Serves 4"]),
            d("d007", .development, .screenshot, [.decorativeProse], ["A weeknight hug in a bowl.", "You will need", "¾ cup heavy cream", "2 tsp fresh thyme"]),
            d("d008", .development, .screenshot, [.decorativeProse, .nonRecipe], ["Cream your way to softer skin.", "Our brown sugar body polish is summer in a jar.", "Shop the collection today."]),
            d("d009", .development, .multiPageScan, [.decorativeProse], ["The soup that carried us through winter.", "Ingredients", "2 tbsp extra-virgin olive oil", "Directions", "Simmer for 20 minutes.", "1 cup cream"]),
            d("d010", .development, .pastedText, [.decorativeProse], ["Midnight Cocoa", "Easy as 1–2–3!", "Ingredients:", "1 cup Dutch-process cocoa powder"]),

            d("d011", .development, .structuredURL, [.structuredURL], ["Recipe: Tomato Soup", "Ingredients", "2 cans whole peeled tomatoes", "Cook time: 35 minutes"]),
            d("d012", .development, .structuredURL, [.structuredURL, .mixedIngredientInstruction], ["https://example.test/creamy-soup", "1 cup heavy cream. Stir into the soup over low heat.", "Serve immediately."]),
            d("d013", .development, .structuredURL, [.structuredURL], ["INGREDIENTS", "2–3 medium Yukon Gold potatoes", "1-½ tsp kosher salt", "Instructions", "Bake at 425°F until crisp."]),
            d("d014", .development, .structuredURL, [.structuredURL], ["Home › Recipes › Rice Pudding", "1 cup short-grain rice", "⅓ cup packed light brown sugar", "Calories: 280"]),
            d("d015", .development, .structuredURL, [.structuredURL], ["For the topping:", "2 tbsp chopped pistachios", "for topping", "Yield: 8 slices"]),
            d("d016", .development, .structuredURL, [.structuredURL], ["Ingredients", "1 (14-ounce) can fire-roasted, diced tomatoes", "2–4 cloves garlic, finely minced", "Author: Mina Chen"]),
            d("d017", .development, .structuredURL, [.structuredURL], ["Ingredientes / Ingredients", "½ cup crème fraîche / crema fresca", "2 cucharadas de aceite de oliva", "Fold gently until combined."]),
            d("d018", .development, .structuredURL, [.structuredURL], ["https://example.test/best-summer-pasta", "By Rowan Lee", "Total time: 45 minutes", "A glossy, garden-fresh dinner."]),
            d("d019", .development, .structuredURL, [.structuredURL, .mixedIngredientInstruction], ["Soup ingredients", "2 cups vegetable broth. Bring to a boil in a saucepan.", "Simmer uncovered for 10 minutes.", "Rating: 4.9"]),
            d("d020", .development, .structuredURL, [.structuredURL], ["1 cup bread flour", "¾ tsp instant yeast", "Directions", "Mix the dough for 8 minutes.", "2 tbsp olive oil"]),

            d("d021", .development, .pinterest, [.pinterest], ["PIN: Five-Minute Salsa", "Fresh, punchy, and party-ready 🌶️", "4 Roma tomatoes", "½ cup chopped cilantro"]),
            d("d022", .development, .pinterest, [.pinterest], ["Save this lemon loaf!", "1½ cups cake flour", "Zest of 2 lemons", "Tap for the full recipe"]),
            d("d023", .development, .pinterest, [.pinterest, .mixedIngredientInstruction], ["Chewy Brown Sugar Bars", "Ingredients", "½ cup packed brown sugar. Beat with the softened butter.", "Bake for 22–25 minutes."]),
            d("d024", .development, .pinterest, [.pinterest], ["12 dreamy blue kitchens", "Cream cabinets are trending again.", "Save these ideas for your remodel."]),
            d("d025", .development, .pinterest, [.pinterest], ["Coconut Rice Bowl", "1 cup jasmine rice, rinsed", "¾ cup full-fat coconut milk", "www.example.test/coconut-rice"]),

            d("d026", .development, .groceryList, [.flatPastedList], ["1 bag long-grain rice", "1 lb light brown sugar", "1 pint heavy cream"]),
            d("d027", .development, .pastedText, [.flatPastedList], ["2 cans chickpeas", "1 bunch flat-leaf parsley", "remember napkins"]),
            d("d028", .development, .groceryList, [.flatPastedList, .mixedIngredientInstruction], ["2 cups rolled oats. Stir with the cinnamon.", "½ cup chopped walnuts", "Bake until toasted."]),
            d("d029", .development, .pastedText, [.flatPastedList], ["2 cups flour, 1 cup sugar, 1 tsp kosher salt", "Bake at 350°F for 30 minutes."]),
            d("d030", .development, .groceryList, [.flatPastedList], ["2–3 lb bone-in, skin-on chicken thighs", "1 (12-oz) jar roasted red peppers, drained", "¾–1 cup low-sodium chicken stock"]),
            d("d031", .development, .pastedText, [.flatPastedList], ["• 250 g plain flour", "• 125 g salted butter", "• 1 tsp vanilla"]),
            d("d032", .development, .groceryList, [.flatPastedList], ["1 cup Greek yogurt", "2 tbsp toasted sesame seeds for topping", "for topping"]),
            d("d033", .development, .pastedText, [.flatPastedList], ["SAUCE", "1 can crushed tomatoes", "2 tbsp olive oil", "METHOD", "Simmer until thick."]),
            d("d034", .development, .groceryList, [.flatPastedList], ["2 lemons", "2 batteries", "3 paint brushes", "1 bunch scallions"]),
            d("d035", .development, .pastedText, [.flatPastedList], ["2 tomates / tomatoes", "1 taza de arroz / cup rice", "½ cucharadita de sal"]),

            d("d036", .development, .pastedText, [.quantityless], ["Ingredients", "all-purpose flour", "packed brown sugar", "heavy cream"]),
            d("d037", .development, .groceryList, [.quantityless], ["basmati rice", "canned tomatoes", "fresh basil", "call Mom"]),
            d("d038", .development, .pastedText, [.quantityless, .mixedIngredientInstruction], ["Ingredients", "dark chocolate", "Heavy cream. Whisk until glossy.", "Serve warm."]),
            d("d039", .development, .screenshot, [.quantityless], ["WHAT YOU NEED", "ripe bananas", "creamy peanut butter", "flaky sea salt"]),
            d("d040", .development, .cameraPhoto, [.quantityless], ["For the sauce:", "crushed tomatoes", "fresh oregano", "grated Parmesan"]),
            d("d041", .development, .photoLibrary, [.quantityless], ["INGREDIENTS", "brown rice", "coconut cream", "lime zest"]),
            d("d042", .development, .multiPageScan, [.quantityless], ["CAKE:", "cake flour", "unsalted butter", "FROSTING:", "cream cheese"]),
            d("d043", .development, .screenshot, [.quantityless], ["Ingredientes / Ingredients", "arroz jazmín / jasmine rice", "leche de coco / coconut milk", "sal marina / sea salt"]),
            d("d044", .development, .unknown, [.quantityless], ["Brown sugar skies over Rice County.", "Cream dreams and summer light.", "Read the full poem."]),
            d("d045", .development, .pastedText, [.quantityless], ["Directions", "Stir until smooth.", "brown sugar", "heavy cream"]),

            d("d046", .development, .groceryList, [.ambiguousNounVerb], ["1 cup heavy cream", "4 slices sourdough toast", "1 cup orange juice"]),
            d("d047", .development, .pastedText, [.ambiguousNounVerb, .mixedIngredientInstruction], ["Ingredients", "2 cups heavy cream. Whisk with the vanilla.", "Directions", "Serve over toast."]),
            d("d048", .development, .groceryList, [.ambiguousNounVerb], ["1 package dinner rolls", "4 slices provolone", "2 tbsp Italian spice blend"]),
            d("d049", .development, .pastedText, [.ambiguousNounVerb], ["½ cup unsalted butter", "Directions", "Cream the butter with the sugar.", "Roll the dough thin.", "Slice into squares."]),
            d("d050", .development, .pastedText, [.ambiguousNounVerb], ["1 cup cauliflower rice", "Instructions", "Rice the cauliflower in a processor.", "Season with salt."]),
            d("d051", .development, .pastedText, [.ambiguousNounVerb], ["Juice of 2 lemons", "1 tsp lemon zest", "Directions", "Juice the lemons into a bowl."]),
            d("d052", .development, .screenshot, [.ambiguousNounVerb], ["1 cup packed brown sugar", "½ cup browned butter", "Method", "Brown the butter slowly."]),
            d("d053", .development, .screenshot, [.ambiguousNounVerb, .nonRecipe], ["Roll paint onto the cream-colored wall.", "Slice the masking tape at each corner.", "Mix primer before use."]),
            d("d054", .development, .groceryList, [.ambiguousNounVerb], ["2 cream-filled brioche rolls", "6 slices smoked turkey", "Directions", "Serve the rolls warm."]),
            d("d055", .development, .groceryList, [.ambiguousNounVerb], ["1 cup breakfast-blend coffee", "2 slices whole-grain bread", "cream to taste"]),

            d("d056", .development, .screenshot, [.nutritionOrMetadata], ["Ingredients", "2 cups cooked chickpeas", "Calories: 310", "Protein 14 g"]),
            d("d057", .development, .pastedText, [.nutritionOrMetadata, .mixedIngredientInstruction], ["Serves 6", "Ingredients", "1 cup long-grain rice. Bring the stock to a boil.", "Serve after resting.", "Sodium: 220 mg"]),
            d("d058", .development, .cameraPhoto, [.nutritionOrMetadata], ["Nutrition Facts", "Serving size 1 cup", "Total carbohydrate 32 g", "Includes 8 g added sugars"]),
            d("d059", .development, .pastedText, [.nutritionOrMetadata], ["Prep time: 10 minutes", "Cook time: 25 minutes", "2 tbsp extra-virgin olive oil", "Yield: 4 bowls"]),
            d("d060", .development, .photoLibrary, [.nutritionOrMetadata], ["Nutrition Facts", "Ingredients: wheat flour, sugar, cocoa butter", "Contains wheat and milk", "Net wt 7 oz"]),
            d("d061", .development, .cameraPhoto, [.nutritionOrMetadata, .nonRecipe], ["Dietary Supplement", "Serving Size: 2 capsules", "Vitamin C 500 mg", "Other ingredients: cellulose, silica"]),
            d("d062", .development, .multiPageScan, [.nutritionOrMetadata], ["Makes 12 muffins", "Total time: 40 minutes", "Ingredients", "2 cups whole-wheat flour", "375°F"]),
            d("d063", .development, .screenshot, [.nutritionOrMetadata], ["1 cup cooked brown rice", "Per serving", "Sodium 85 mg", "Fiber 4 g"]),
            d("d064", .development, .pastedText, [.nutritionOrMetadata, .mixedIngredientInstruction], ["Ingredients", "½ cup unsalted butter", "1 cup brown sugar. Beat until pale and fluffy.", "Bake for 18 minutes.", "Calories per cookie: 190"]),
            d("d065", .development, .screenshot, [.nutritionOrMetadata], ["Serves 8 | Prep 15 min | Cook 45 min", "1 cup arborio rice", "4 cups low-sodium stock", "Directions", "½ cup heavy cream"]),

            d("d066", .development, .screenshot, [.nonRecipe], ["2 cups wood filler", "1 gallon cream paint", "Mix epoxy for two minutes."]),
            d("d067", .development, .photoLibrary, [.nonRecipe], ["Morning skincare routine", "1 tbsp vitamin C serum", "Mix serum with moisturizer in your palm."]),
            d("d068", .development, .screenshot, [.nonRecipe], ["Monday itinerary", "8:00 — 2 cups coffee with Dana", "9:30 — Rice County planning meeting"]),
            d("d069", .development, .cameraPhoto, [.nonRecipe], ["Trail workout", "3 sets of 12 walking lunges", "1 cup water between rounds", "Bring a towel and resistance band."]),
            d("d070", .development, .groceryList, [.nonRecipe, .mixedIngredientInstruction], ["Weekend grocery and prep note", "2 ripe avocados. Mash before serving.", "Pick up dry cleaning"]),
            d("d071", .development, .unknown, [.nonRecipe], ["Q3 commodity report", "Brown sugar futures rose 4%.", "Rice volume declined across the region."]),
            d("d072", .development, .screenshot, [.nonRecipe], ["Café Menu", "Cream Tea — $14", "Brown Sugar Latte — $6", "Jasmine Rice Bowl — $12"])
        ]
    }

    private static var independentSpatialDevelopmentDocuments: [Document] {
        [
            d(
                "d073", .development, .screenshot,
                [.multiColumnGeometry, .crossRowOrCard, .ocrFixture, .quantityless],
                ["Directions", "Roast until caramelized.", "Ingredients", "freekeh", "2 tbsp sorghum syrup"],
                spatial: spatial(
                    [0, 0, 1, 1, 1],
                    sections: ["left-method", "left-method", "right-recipe", "right-recipe", "right-recipe"]
                )
            ),
            d(
                "d074", .development, .screenshot,
                [.multiColumnGeometry, .crossRowOrCard, .ocrFixture, .quantityless],
                ["Ingredients", "Directions", "1 cup teff flour", "Bake until crisp.", "amaranth flakes"],
                spatial: spatial([0, 1, 0, 1, 0], sections: ["recipe", "recipe", "recipe", "recipe", "recipe"])
            ),
            d(
                "d075", .development, .multiPageScan,
                [.crossRowOrCard, .quantityless],
                ["Directions", "Simmer until glossy.", "Ingredients", "1 cup fonio", "baobab powder"],
                spatial: spatial(
                    [0, 0, 0, 0, 0],
                    sections: ["main", "main", "main", "main", "main"],
                    pages: [0, 0, 1, 1, 1]
                )
            ),
            d(
                "d076", .development, .multiPageScan,
                [.crossRowOrCard, .nutritionOrMetadata],
                ["Ingredients", "1 cup cassava flour", "Weekend field notes", "3 hours trail survey"],
                spatial: spatial(
                    [0, 0, 0, 0],
                    sections: ["recipe", "recipe", "notes-card", "notes-card"],
                    pages: [0, 0, 1, 1]
                )
            ),
            d(
                "d077", .development, .screenshot,
                [.crossRowOrCard],
                ["Ingredients", "1 cup millet", "Garden checklist", "mulch fabric"],
                spatial: spatial([0, 0, 0, 0], sections: ["recipe-card", "recipe-card", "garden-card", "garden-card"])
            ),
            d(
                "d078", .development, .screenshot,
                [.multiColumnGeometry, .crossRowOrCard, .ocrFixture, .quantityless],
                ["Ingredients", "sumac berries", "SAVE FOR LATER", "linen napkins", "2 tsp rose water"],
                spatial: spatial([0, 0, 1, 1, 0], sections: ["recipe-card", "recipe-card", "promo-card", "promo-card", "recipe-card"])
            ),
            d(
                "d079", .development, .pastedText,
                [.crossRowOrCard, .flatPastedList],
                ["Ingredients", "1 cup einkorn flour", "", "Weekend errands", "mail the parcel"]
            ),
            d(
                "d080", .development, .pastedText,
                [.flatPastedList, .quantityless],
                ["Ingredients", "1 cup black rice", "", "Ingredients", "urad dal"]
            ),
            d(
                "d081", .development, .photoLibrary,
                [.multiColumnGeometry, .crossRowOrCard, .nonRecipe],
                ["Ingredients", "2 cups semolina", "Equipment", "8-inch skillet", "wooden spoon"],
                spatial: spatial([0, 0, 1, 1, 1], sections: ["recipe-card", "recipe-card", "equipment-card", "equipment-card", "equipment-card"])
            ),
            d(
                "d082", .development, .screenshot,
                [.nutritionOrMetadata, .quantityless],
                ["Ingredients", "1 cup buckwheat groats", "Nutrition Facts", "Manganese 2 mg", "selenium flakes"],
                spatial: spatial([0, 0, 0, 0, 0], sections: ["recipe", "recipe", "recipe", "recipe", "recipe"])
            ),
            d(
                "d083", .development, .pastedText,
                [.mixedIngredientInstruction, .quantityless],
                ["Ingredients", "1 cup pearl couscous", "Cover and rest for 10 minutes.", "preserved lemon"]
            ),
            d(
                "d084", .development, .screenshot,
                [.multiColumnGeometry, .crossRowOrCard, .quantityless],
                ["Ingredients", "1 cup Job's tears", "Directions", "Remove the pan from heat.", "fresh epazote"],
                spatial: spatial([0, 0, 1, 1, 0], sections: ["recipe", "recipe", "recipe", "recipe", "recipe"])
            ),
            d(
                "d085", .development, .structuredURL,
                [.structuredURL, .crossRowOrCard],
                ["SAVE THIS RECIPE", "Ingredients", "1 cup adzuki beans", "Shop the pantry", "linen filters"]
            ),
            d(
                "d086", .development, .pinterest,
                [.pinterest, .crossRowOrCard],
                ["PIN IT", "Ingredients", "2 tbsp black garlic paste", "Sponsored", "Visit profile"]
            ),
            d(
                "d087", .development, .pastedText,
                [.quantityless],
                ["Ingredients", "makrut lime leaves", "asafoetida", "Directions", "Toast the spices briefly."]
            ),
            d(
                "d088", .development, .pastedText,
                [.flatPastedList],
                ["250 g red lentils", "30 ml tamarind concentrate", "2 tsp ajwain seeds"]
            ),
            d(
                "d089", .development, .screenshot,
                [.multiColumnGeometry, .crossRowOrCard, .ocrFixture, .nonRecipe],
                ["Shelf Assembly", "2 x 18-inch brackets", "4 screws", "1 cup wood stain"],
                spatial: spatial([0, 0, 0, 1], sections: ["assembly", "assembly", "assembly", "finishing"])
            ),
            d(
                "d090", .development, .photoLibrary,
                [.multiColumnGeometry, .crossRowOrCard, .nonRecipe],
                ["Buffer preparation", "2 g agarose", "50 ml electrophoresis buffer", "Heat until dissolved."],
                spatial: spatial([0, 0, 1, 1], sections: ["lab-title", "lab-title", "lab-steps", "lab-steps"])
            ),
            d(
                "d091", .development, .screenshot,
                [.ocrFixture, .mixedIngredientInstruction, .quantityless],
                ["INGREDIENTS", "I cup kaniwa", "2 t sp ground annatto. Stir into the broth.", "DIRECTIONS", "Bring to a simmer."],
                spatial: spatial([0, 0, 0, 0, 0], sections: ["recipe", "recipe", "recipe", "recipe", "recipe"])
            ),
            d(
                "d092", .development, .screenshot,
                [.multiColumnGeometry, .crossRowOrCard, .ocrFixture, .quantityless],
                ["Ingredients", "Directions", "l/2 cup tigernut flour", "Mix until smooth.", "1 t bsp date syrup"],
                spatial: spatial([0, 1, 0, 1, 0], sections: ["recipe", "recipe", "recipe", "recipe", "recipe"])
            ),
            d(
                "d093", .development, .screenshot,
                [.multiColumnGeometry, .crossRowOrCard, .ocrFixture],
                ["Ingredients", "1 tbsp yacon syrup", "RELATED IDEAS", "linen swatches", "mesquite powder"],
                spatial: spatial([0, 0, 1, 1, 1], sections: ["recipe-card", "recipe-card", "ideas-card", "ideas-card", "ideas-card"])
            ),
            d(
                "d094", .development, .screenshot,
                [.ocrFixture, .mixedIngredientInstruction],
                [
                    "Ingredients",
                    "3 tbsp black vinegar; Toss with the noodles.",
                    "1 tsp nigella seeds! Roast briefly in a dry pan.",
                    "2 cups sorghum flour, then mix until smooth."
                ],
                spatial: spatial([0, 0, 0, 0], sections: ["recipe", "recipe", "recipe", "recipe"])
            ),
            d(
                "d095", .development, .photoLibrary,
                [.multiColumnGeometry, .crossRowOrCard, .nonRecipe],
                ["Ingredients", "1 cup tepary beans", "CARE INSTRUCTIONS", "hand wash only", "soap flakes"],
                spatial: spatial([0, 0, 1, 1, 1], sections: ["recipe-card", "recipe-card", "care-card", "care-card", "care-card"])
            ),
            d(
                "d096", .development, .screenshot,
                [.multiColumnGeometry, .crossRowOrCard, .ocrFixture, .quantityless],
                ["METHOD", "Whisk the dressing.", "DRESSING", "2 tbsp ume plum vinegar", "shiso leaves"],
                spatial: spatial([0, 0, 1, 1, 1], sections: ["method-card", "method-card", "recipe-card", "recipe-card", "recipe-card"])
            )
        ]
    }

    private static var independentSpatialDevelopmentOracles: [String: Oracle] {
        [
            "d073": o(["d073-l04", "d073-l05"], instructions: ["d073-l02"]),
            "d074": o(["d074-l03", "d074-l05"], instructions: ["d074-l04"]),
            "d075": o(["d075-l04", "d075-l05"], instructions: ["d075-l02"]),
            "d076": o(["d076-l02"]),
            "d077": o(["d077-l02"]),
            "d078": o(["d078-l02", "d078-l05"]),
            "d079": o(["d079-l02"]),
            "d080": o(["d080-l02", "d080-l05"]),
            "d081": o(["d081-l02"]),
            "d082": o(["d082-l02"]),
            "d083": o(["d083-l02"], instructions: ["d083-l03"]),
            "d084": o(["d084-l02", "d084-l05"], instructions: ["d084-l04"]),
            "d085": o(["d085-l03"]),
            "d086": o(["d086-l03"]),
            "d087": o(["d087-l02", "d087-l03"], instructions: ["d087-l05"]),
            "d088": o(["d088-l01", "d088-l02", "d088-l03"]),
            "d089": o([]),
            "d090": o([], instructions: ["d090-l04"]),
            "d091": o(
                ["d091-l02", "d091-l03"],
                instructions: ["d091-l05"],
                sanitized: ["d091-l03": "2 t sp ground annatto"]
            ),
            "d092": o(["d092-l03", "d092-l05"], instructions: ["d092-l04"]),
            "d093": o(["d093-l02"]),
            "d094": o(
                ["d094-l02", "d094-l03", "d094-l04"],
                sanitized: [
                    "d094-l02": "3 tbsp black vinegar",
                    "d094-l03": "1 tsp nigella seeds",
                    "d094-l04": "2 cups sorghum flour"
                ]
            ),
            "d095": o(["d095-l02"]),
            "d096": o(["d096-l04", "d096-l05"], instructions: ["d096-l02"])
        ]
    }

    // Frozen evaluation-only cases. Production classifier changes must never be
    // shaped from their individual texts, IDs, or per-case failures.
    private static var heldOutDocuments: [Document] {
        [
            d("h001", .heldOut, .pastedText, [.flatPastedList], ["INGREDIENTS", "2 cups all-purpose flour", "1½ cups rolled oats", "1 tsp kosher salt", "¾ cup unsalted butter, melted", "2 large eggs", "1 cup packed brown sugar", "DIRECTIONS"]),
            d("h002", .heldOut, .pastedText, [.mixedIngredientInstruction], ["Lemon Chicken", "Ingredients", "For the sauce:", "2 tbsp extra-virgin olive oil", "1 cup chicken stock", "½ tsp black pepper", "Method", "Simmer until reduced by half."]),
            d("h003", .heldOut, .pastedText, [.quantityless], ["Ingredients", "chicken thighs", "kosher salt", "black pepper", "olive oil", "garlic cloves", "lemon zest", "Instructions"]),
            d("h004", .heldOut, .pastedText, [.flatPastedList, .quantityless, .ambiguousNounVerb], ["milk", "eggs", "brown sugar", "jasmine rice", "heavy cream", "paper towels"]),
            d("h005", .heldOut, .pastedText, [.ambiguousNounVerb, .quantityless], ["Ingredients", "Cream", "Orange juice", "Dinner rolls", "Directions", "Toast the almonds.", "Cream the butter.", "Roll the dough."]),
            d("h006", .heldOut, .pastedText, [.decorativeProse, .nonRecipe], ["Sunday at Nana’s Table", "This silky rice dish tastes like a warm hug.", "Five reasons your family will ask for seconds", "Save this story for later", "Subscribe for weekly comfort", "Comments are open."]),
            d("h007", .heldOut, .pastedText, [.nutritionOrMetadata, .nonRecipe], ["Nutrition Facts", "Serving size 1 bowl", "Calories 420", "Total fat 9 g", "Sodium 610 mg", "350°F", "Prep time: 15 minutes"]),
            d("h008", .heldOut, .screenshot, [.multiColumnGeometry, .mixedIngredientInstruction, .ocrFixture], ["Ingredients", "1 tsp flaky sea salt, EASY AS 1-2-3! Mash banana. Stir in peanut butter.", "2 tbsp peanut butter", "Directions", "Bake until golden."], spatial: spatial([0, 0, 1, 0, 1])),
            d("h009", .heldOut, .structuredURL, [.structuredURL, .quantityless], ["https://recipes.example.com/lemony-orzo?utm_source=newsletter", "Lemony Orzo", "Ingredients", "orzo", "vegetable stock", "lemon zest", "Method", "Bring the stock to a boil."]),
            d("h010", .heldOut, .pinterest, [.pinterest, .decorativeProse, .nonRecipe], ["https://www.pinterest.com/pin/closet-ideas/", "10 pantry organization hacks", "Clear bins", "Label everything", "Save this Pin", "Shop the look."]),
            d("h011", .heldOut, .pinterest, [.pinterest, .ambiguousNounVerb], ["https://www.pinterest.com/pin/one-pan-chicken/", "One-Pan Creamy Chicken", "Ingredients", "1 lb chicken thighs", "2 cups jasmine rice", "1 cup heavy cream", "Tap to see the full recipe", "Directions"]),
            d("h012", .heldOut, .structuredURL, [.structuredURL], ["Ingredients", "1 cup rolled oats", "https://cdn.example.com/oats.jpg", "2 tbsp brown sugar", "https://example.com/privacy", "Method", "Whisk until smooth."]),
            d("h013", .heldOut, .structuredURL, [.structuredURL, .nutritionOrMetadata], ["https://food.example.com/apple-crisp/amp", "Skillet Apple Crisp", "4.9 from 228 votes", "Ingredients", "½ cup rolled oats", "1–2 tbsp brown sugar", "Jump to recipe", "Bake until bubbling."]),
            d("h014", .heldOut, .pinterest, [.pinterest, .crossRowOrCard, .decorativeProse], ["Ingredients", "1 cup brown sugar", "1 cup jasmine rice", "YOU MAY ALSO LIKE", "Creamy Tuscan Chicken", "Save Pin", "2.3k shares", "Directions"]),
            d("h015", .heldOut, .structuredURL, [.structuredURL, .nonRecipe], ["https://example.com/1-cup-rice", "https://search.example.com/?q=brown+sugar", "pinterest://pin/half-cup-cream", "www.example.com/ingredients", "mailto:recipes@example.com"]),
            d("h016", .heldOut, .pinterest, [.pinterest, .flatPastedList, .quantityless, .ambiguousNounVerb], ["• brown sugar", "• basmati rice", "• heavy cream", "• Tap to save", "https://pinterest.com/pin/2468"]),

            d("h017", .heldOut, .screenshot, [.ocrFixture, .multiColumnGeometry, .mixedIngredientInstruction], ["INGREDIENTS", "1 cup flour", "2 large eggs", "½ cup sugar", "1 tsp vanilla", "INSTRUCTIONS", "Mix until smooth.", "Bake for 20 minutes."], spatial: spatial([0, 0, 1, 0, 1, 0, 0, 1])),
            d("h018", .heldOut, .multiPageScan, [.ocrFixture, .multiColumnGeometry, .crossRowOrCard, .mixedIngredientInstruction], ["INGREDIENTS", "1 cup oats", "2 tbsp honey", "DIRECTIONS", "Stir until combined.", "1 cup yogurt", "1 cup berries", "Serve cold."], spatial: spatial([0, 0, 0, 0, 0, 1, 1, 1], sections: ["main", "left", "left", "left", "left", "right", "right", "right"])),
            d("h019", .heldOut, .cameraPhoto, [.ocrFixture, .multiColumnGeometry, .crossRowOrCard, .decorativeProse], ["Ingredients", "• 1 tsp flaky sea salt", "Sourdough Discard & Vanilla", "for topping", "EASY AS 1-2-3!", "Mash banana.", "Stir in peanut butter."], spatial: spatial([0, 0, 1, 0, 1, 1, 1], sections: ["main", "salt", "side", "salt", "side", "side", "side"])),
            d("h020", .heldOut, .screenshot, [.multiColumnGeometry, .crossRowOrCard], ["Tomato Soup", "Ingredients", "2 cans tomatoes", "1 cup heavy cream", "Garlic Knots", "1 cup all-purpose flour", "Bake at 425°F.", "Directions"], spatial: spatial([0, 0, 0, 0, 1, 1, 1, 1], sections: ["tomato", "tomato", "tomato", "tomato", "garlic", "garlic", "garlic", "garlic"])),
            d("h021", .heldOut, .screenshot, [.multiColumnGeometry, .mixedIngredientInstruction], ["Ingredients", "1 cup flour. Preheat oven to 350°F.", "2 eggs! Whisk until foamy.", "½ cup brown sugar; stir into the batter.", "Bake for 20 minutes."], spatial: spatial([0, 0, 1, 0, 1])),
            d("h022", .heldOut, .screenshot, [.multiColumnGeometry, .crossRowOrCard, .decorativeProse, .ambiguousNounVerb], ["Ingredients", "2 tbsp olive oil", "Salt & Straw", "Rice Paper Stories", "Cream of the Crop", "1 tsp thyme", "Instructions", "Heat oil until shimmering."], spatial: spatial([0, 0, 1, 1, 1, 0, 0, 0], sections: ["main", "main", "side", "side", "side", "main", "main", "main"])),
            d("h023", .heldOut, .screenshot, [.multiColumnGeometry, .crossRowOrCard, .decorativeProse, .ambiguousNounVerb], ["Ingredients", "• 1 cup brown sugar", "Award-winning comfort in every bite", "• 2 cups cooked rice", "Made for busy weeknights", "• ½ cup heavy cream", "Swipe for more", "Directions"], spatial: spatial([0, 0, 1, 0, 1, 0, 1, 0], sections: ["main", "main", "side", "main", "side", "main", "side", "main"])),
            d("h024", .heldOut, .cameraPhoto, [.ocrFixture, .multiColumnGeometry, .crossRowOrCard, .decorativeProse], ["• 2 cloves garlic", "© 2026 Table & Thyme", "• 1 cup broth", "Photography by Ana Ruiz", "for topping", "• parsley for topping"], spatial: spatial([0, 1, 0, 1, 1, 0], sections: ["main", "footer", "main", "footer", "footer", "main"])),

            d("h025", .heldOut, .pastedText, [.quantityless, .ambiguousNounVerb], ["Ingredients", "Brown sugar", "Jasmine rice", "Heavy cream", "Unsalted butter", "Directions", "Melt the butter over low heat."]),
            d("h026", .heldOut, .pastedText, [.decorativeProse, .nonRecipe, .ambiguousNounVerb, .crossRowOrCard], ["Brown sugar is the secret to a sweeter life.", "Rice feeds more people than stories do.", "Cream rises, and so can you.", "Save this kitchen essay", "Read next."]),
            d("h027", .heldOut, .pastedText, [.ambiguousNounVerb, .quantityless], ["Ingredients", "cream cheese", "toast points", "juice of one lemon", "dinner rolls", "Cream the butter.", "Toast the bread.", "Juice the lemon."]),
            d("h028", .heldOut, .pastedText, [.flatPastedList, .quantityless, .mixedIngredientInstruction], ["chicken thighs", "red onion", "ground cumin", "lime", "Marinate for 30 minutes.", "Grill until cooked through."]),
            d("h029", .heldOut, .pastedText, [.flatPastedList], ["for topping", ", for topping", "• for topping", "Flaky sea salt for topping", "1 tsp flaky sea salt, for topping."]),
            d("h030", .heldOut, .pastedText, [.quantityless, .mixedIngredientInstruction], ["Ingredients", "For topping:", "½ cup whipped cream", "For serving", "Fresh berries", "Method", "Top with berries before serving."]),
            d("h031", .heldOut, .pastedText, [.mixedIngredientInstruction, .crossRowOrCard], ["Notes:", "Use ripe bananas for best results.", "Ingredients:", "3 ripe bananas", "Pinch of salt", "Storage:", "Keep chilled.", "Directions:"]),
            d("h032", .heldOut, .pastedText, [.quantityless, .decorativeProse], ["Ingredients", "Sea salt.", "Black pepper.", "Extra-virgin olive oil.", "The best salt makes all the difference.", "Directions", "Season to taste."]),
            d("h033", .heldOut, .pastedText, [.flatPastedList], ["Ingredients", "2–3 Honeycrisp apples, peeled", "1 cup extra-virgin olive oil", "1 cup tomatoes, fire-roasted", "1½ cups semi-sweet chocolate chips", "Directions", "Roast until tender."]),
            d("h034", .heldOut, .pastedText, [.nutritionOrMetadata], ["Ingredients", "2 1/2 cups long-grain rice", "1 (14-ounce) can fire-roasted tomatoes", "salt-and-pepper blend", "Step 1: Heat the oil.", "2–3 minutes", "Serve immediately."]),
            d("h035", .heldOut, .pastedText, [.quantityless, .ambiguousNounVerb], ["Ingredients / Ingrédients", "½ tasse de crème / ½ cup cream", "2 cucharadas de aceite de oliva", "1 limón / 1 lemon", "Méthode", "Mélanger jusqu’à consistance lisse."]),
            d("h036", .heldOut, .screenshot, [.multiColumnGeometry, .quantityless], ["What you need", "✓ 200 g crème fraîche", "• 1 jalapeño, thinly sliced", "☐ 2 tbsp piñones", "— 1 cup açaí purée", "How to make", "Blend until smooth."], spatial: spatial([0, 0, 1, 0, 1, 0, 0])),
            d("h037", .heldOut, .pastedText, [.decorativeProse, .nonRecipe, .crossRowOrCard], ["Crème de la crème", "A story of café mornings", "Piñata Party Rice", "Save résumé", "1,000 readers loved this."]),
            d("h038", .heldOut, .pastedText, [.nutritionOrMetadata, .mixedIngredientInstruction], ["Ingredients", "1–2 lb bone-in chicken thighs", "2–3 sprigs thyme", "350–375°F", "20–25 minutes", "Directions", "Roast until the juices run clear."]),
            d("h039", .heldOut, .screenshot, [.mixedIngredientInstruction], ["Ingredients", "1 cucumber, seeded and diced", "2 cups rice, cooked and cooled", "1 cup cream, divided", "1 tsp salt; stir into sauce.", "Directions", "Combine the remaining ingredients."]),
            d("h040", .heldOut, .pastedText, [.quantityless, .ambiguousNounVerb], ["Ingredientes", "arroz integral", "crema espesa", "azúcar morena", "Calentar el arroz a fuego lento.", "Servir caliente."]),
            d("h041", .heldOut, .pastedText, [.nonRecipe, .nutritionOrMetadata, .crossRowOrCard], ["Grocery delivery", "Order subtotal $42.18", "2 items", "SKU 018293", "Add to cart", "Out of stock", "Arrives Tuesday."]),
            d("h042", .heldOut, .pastedText, [.mixedIngredientInstruction, .quantityless], ["Whiskey Sour", "Ingredients", "2 oz bourbon", "1 oz lemon juice", "¾ oz simple syrup", "Ice", "Shake with ice.", "Strain into a glass."]),
            d("h043", .heldOut, .cameraPhoto, [.nutritionOrMetadata, .nonRecipe, .crossRowOrCard], ["Nutrition Facts", "Serving Size 1 cup", "Calories 220", "Total Fat 8 g", "Sodium 450 mg", "Total Carbohydrate 31 g", "Protein 6 g", "Ingredients: milk, rice, sugar."]),
            d("h044", .heldOut, .structuredURL, [.structuredURL, .nonRecipe, .mixedIngredientInstruction], ["Creamy Rice in One Pot", "Serves 4", "Prep time: 10 minutes", "Heat oil in a saucepan.", "Stir in rice.", "Add cream and simmer.", "Serve immediately."]),
            d("h045", .heldOut, .pastedText, [.decorativeProse, .nutritionOrMetadata, .nonRecipe], ["5 reasons to love rice", "10 minute meals", "2 comments", "4.8 stars", "1 share", "2026 edition"]),
            d("h046", .heldOut, .groceryList, [.flatPastedList, .ambiguousNounVerb], ["Grocery list", "brown sugar", "rice", "heavy cream", "dish soap", "paper towels", "2 lemons", "Directions to store: turn left."]),
            d("h047", .heldOut, .pastedText, [.flatPastedList, .quantityless], ["Ingredients", "brown sugar", "jasmine rice", "", "cream", "Directions", "Stir cream into rice."]),
            d("h048", .heldOut, .pastedText, [.ambiguousNounVerb, .mixedIngredientInstruction], ["Ingredients", "• 1½ cups brown sugar", "• jasmine rice", "• heavy cream, for topping", "Method", "Brown the butter in a skillet.", "Rice the cauliflower, then stir in cream.", "for topping."])
        ]
    }
}

private extension ContextualIngredientFilterTests {
    // Ground truth is deliberately separate from the raw-document declarations.
    // Never derive accepted IDs from inline flags, classifier output, or text shape.
    private static var oracles: [String: Oracle] {
        [
            "d001": o(["d001-l04"]),
            "d002": o(["d002-l03"], instructions: ["d002-l04"]),
            "d003": o(["d003-l03", "d003-l04"]),
            "d004": o(["d004-l03"], instructions: ["d004-l04"], sanitized: ["d004-l03": "2 cups all-purpose flour"]),
            "d005": o(["d005-l03"]),
            "d006": o(["d006-l03"]),
            "d007": o(["d007-l03", "d007-l04"]),
            "d008": o([]),
            "d009": o(["d009-l03"], instructions: ["d009-l05"]),
            "d010": o(["d010-l04"]),
            "d011": o(["d011-l03"]),
            "d012": o(["d012-l02"], instructions: ["d012-l03"], sanitized: ["d012-l02": "1 cup heavy cream"]),
            "d013": o(["d013-l02", "d013-l03"], instructions: ["d013-l05"]),
            "d014": o(["d014-l02", "d014-l03"]),
            "d015": o(["d015-l02"]),
            "d016": o(["d016-l02", "d016-l03"]),
            "d017": o(["d017-l02", "d017-l03"], instructions: ["d017-l04"]),
            "d018": o([]),
            "d019": o(["d019-l02"], instructions: ["d019-l03"], sanitized: ["d019-l02": "2 cups vegetable broth"]),
            "d020": o(["d020-l01", "d020-l02"], instructions: ["d020-l04"]),
            "d021": o(["d021-l03", "d021-l04"]),
            "d022": o(["d022-l02", "d022-l03"]),
            "d023": o(["d023-l03"], instructions: ["d023-l04"], sanitized: ["d023-l03": "½ cup packed brown sugar"]),
            "d024": o([]),
            "d025": o(["d025-l02", "d025-l03"]),
            "d026": o(["d026-l01", "d026-l02", "d026-l03"]),
            "d027": o(["d027-l01", "d027-l02"]),
            "d028": o(["d028-l01", "d028-l02"], instructions: ["d028-l03"], sanitized: ["d028-l01": "2 cups rolled oats"]),
            "d029": o(["d029-l01"], instructions: ["d029-l02"]),
            "d030": o(["d030-l01", "d030-l02", "d030-l03"]),
            "d031": o(["d031-l01", "d031-l02", "d031-l03"]),
            "d032": o(["d032-l01", "d032-l02"]),
            "d033": o(["d033-l02", "d033-l03"], instructions: ["d033-l05"]),
            "d034": o(["d034-l01", "d034-l04"]),
            "d035": o(["d035-l01", "d035-l02", "d035-l03"]),
            "d036": o(["d036-l02", "d036-l03", "d036-l04"]),
            "d037": o(["d037-l01", "d037-l02", "d037-l03"]),
            "d038": o(["d038-l02", "d038-l03"], instructions: ["d038-l04"], sanitized: ["d038-l03": "Heavy cream"]),
            "d039": o(["d039-l02", "d039-l03", "d039-l04"]),
            "d040": o(["d040-l02", "d040-l03", "d040-l04"]),
            "d041": o(["d041-l02", "d041-l03", "d041-l04"]),
            "d042": o(["d042-l02", "d042-l03", "d042-l05"]),
            "d043": o(["d043-l02", "d043-l03", "d043-l04"]),
            "d044": o([]),
            "d045": o([], instructions: ["d045-l02"]),
            "d046": o(["d046-l01", "d046-l02", "d046-l03"]),
            "d047": o(["d047-l02"], instructions: ["d047-l04"], sanitized: ["d047-l02": "2 cups heavy cream"]),
            "d048": o(["d048-l01", "d048-l02", "d048-l03"]),
            "d049": o(["d049-l01"], instructions: ["d049-l03", "d049-l04", "d049-l05"]),
            "d050": o(["d050-l01"], instructions: ["d050-l03", "d050-l04"]),
            "d051": o(["d051-l01", "d051-l02"], instructions: ["d051-l04"]),
            "d052": o(["d052-l01", "d052-l02"], instructions: ["d052-l04"]),
            "d053": o([], instructions: ["d053-l01", "d053-l02", "d053-l03"]),
            "d054": o(["d054-l01", "d054-l02"], instructions: ["d054-l04"]),
            "d055": o(["d055-l01", "d055-l02", "d055-l03"]),
            "d056": o(["d056-l02"]),
            "d057": o(["d057-l03"], instructions: ["d057-l04"], sanitized: ["d057-l03": "1 cup long-grain rice"]),
            "d058": o([]),
            "d059": o(["d059-l03"]),
            "d060": o([]),
            "d061": o([]),
            "d062": o(["d062-l04"]),
            "d063": o(["d063-l01"]),
            "d064": o(["d064-l02", "d064-l03"], instructions: ["d064-l04"], sanitized: ["d064-l03": "1 cup brown sugar"]),
            "d065": o(["d065-l02", "d065-l03"]),
            "d066": o([], instructions: ["d066-l03"]),
            "d067": o([], instructions: ["d067-l03"]),
            "d068": o([]),
            "d069": o([], instructions: ["d069-l04"]),
            "d070": o(["d070-l02"], sanitized: ["d070-l02": "2 ripe avocados"]),
            "d071": o([]),
            "d072": o([]),

            "h001": o(["h001-l02", "h001-l03", "h001-l04", "h001-l05", "h001-l06", "h001-l07"]),
            "h002": o(["h002-l04", "h002-l05", "h002-l06"], instructions: ["h002-l08"]),
            "h003": o(["h003-l02", "h003-l03", "h003-l04", "h003-l05", "h003-l06", "h003-l07"]),
            "h004": o(["h004-l01", "h004-l02", "h004-l03", "h004-l04", "h004-l05"]),
            "h005": o(["h005-l02", "h005-l03", "h005-l04"], instructions: ["h005-l06", "h005-l07", "h005-l08"]),
            "h006": o([]),
            "h007": o([]),
            "h008": o(["h008-l02", "h008-l03"], instructions: ["h008-l05"], sanitized: ["h008-l02": "1 tsp flaky sea salt"]),
            "h009": o(["h009-l04", "h009-l05", "h009-l06"], instructions: ["h009-l08"]),
            "h010": o([]),
            "h011": o(["h011-l04", "h011-l05", "h011-l06"]),
            "h012": o(["h012-l02", "h012-l04"], instructions: ["h012-l07"]),
            "h013": o(["h013-l05", "h013-l06"], instructions: ["h013-l08"]),
            "h014": o(["h014-l02", "h014-l03"]),
            "h015": o([]),
            "h016": o(["h016-l01", "h016-l02", "h016-l03"]),
            "h017": o(["h017-l02", "h017-l03", "h017-l04", "h017-l05"], instructions: ["h017-l07", "h017-l08"]),
            "h018": o(["h018-l02", "h018-l03", "h018-l06", "h018-l07"], instructions: ["h018-l05", "h018-l08"]),
            "h019": o(["h019-l02"], instructions: ["h019-l06", "h019-l07"]),
            "h020": o(["h020-l03", "h020-l04"], instructions: ["h020-l07"]),
            "h021": o(["h021-l02", "h021-l03", "h021-l04"], instructions: ["h021-l05"], sanitized: ["h021-l02": "1 cup flour", "h021-l03": "2 eggs", "h021-l04": "½ cup brown sugar"]),
            "h022": o(["h022-l02", "h022-l06"], instructions: ["h022-l08"]),
            "h023": o(["h023-l02", "h023-l04", "h023-l06"]),
            "h024": o(["h024-l01", "h024-l03", "h024-l06"]),
            "h025": o(["h025-l02", "h025-l03", "h025-l04", "h025-l05"], instructions: ["h025-l07"]),
            "h026": o([]),
            "h027": o(["h027-l02", "h027-l03", "h027-l04", "h027-l05"], instructions: ["h027-l06", "h027-l07", "h027-l08"]),
            "h028": o(["h028-l01", "h028-l02", "h028-l03", "h028-l04"], instructions: ["h028-l05", "h028-l06"]),
            "h029": o(["h029-l04", "h029-l05"]),
            "h030": o(["h030-l03", "h030-l05"], instructions: ["h030-l07"]),
            "h031": o(["h031-l04", "h031-l05"], instructions: ["h031-l02", "h031-l07"]),
            "h032": o(["h032-l02", "h032-l03", "h032-l04"], instructions: ["h032-l07"]),
            "h033": o(["h033-l02", "h033-l03", "h033-l04", "h033-l05"], instructions: ["h033-l07"]),
            "h034": o(["h034-l02", "h034-l03", "h034-l04"], instructions: ["h034-l05", "h034-l07"]),
            "h035": o(["h035-l02", "h035-l03", "h035-l04"], instructions: ["h035-l06"]),
            "h036": o(["h036-l02", "h036-l03", "h036-l04", "h036-l05"], instructions: ["h036-l07"]),
            "h037": o([]),
            "h038": o(["h038-l02", "h038-l03"], instructions: ["h038-l07"]),
            "h039": o(["h039-l02", "h039-l03", "h039-l04", "h039-l05"], instructions: ["h039-l07"], sanitized: ["h039-l05": "1 tsp salt"]),
            "h040": o(["h040-l02", "h040-l03", "h040-l04"], instructions: ["h040-l05", "h040-l06"]),
            "h041": o([]),
            "h042": o(["h042-l03", "h042-l04", "h042-l05", "h042-l06"], instructions: ["h042-l07", "h042-l08"]),
            "h043": o([]),
            "h044": o([], instructions: ["h044-l04", "h044-l05", "h044-l06", "h044-l07"]),
            "h045": o([]),
            "h046": o(["h046-l02", "h046-l03", "h046-l04", "h046-l07"]),
            "h047": o(["h047-l02", "h047-l03", "h047-l05"], instructions: ["h047-l07"]),
            "h048": o(["h048-l02", "h048-l03", "h048-l04"], instructions: ["h048-l06", "h048-l07"])
        ]
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
