import Foundation
import UIKit
@preconcurrency import Vision

struct OCRFocusTextCandidate: Hashable, Sendable {
    var text: String
    var boundingBox: OCRNormalizedBoundingBox
    var confidence: Double
}

struct OCRFocusSuggestion: Hashable, Sendable {
    var region: OCRFocusRegion
    var confidence: Double
}

enum OCRFocusRegionSuggester {
    private static let confidentSuggestionThreshold = 0.70
    private static let headingPattern = #"(?i)^\s*(ingredients?|what you(?:'|’)ll need)\s*:?[\s]*$"#
    private static let quantityPattern = #"(?i)^\s*[-•*☐✓]?\s*(?:\d+(?:[\s./-]\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|one|two|three|four|five|six|seven|eight|nine|ten)\b"#
    private static let unitPattern = #"(?i)\b(cups?|tbsp|tablespoons?|tsp|teaspoons?|oz|ounces?|lbs?|pounds?|g|grams?|kg|ml|liters?|cloves?|cans?|packages?|pinch|bunch)\b"#
    private static let instructionPattern = #"(?i)\b(preheat|bake|cook|stir|whisk|mix until|directions?|instructions?|method|step\s+\d+)\b"#

    static func suggestRegions(in images: [UIImage]) async -> [OCRFocusRegion] {
        var suggestions: [OCRFocusRegion] = []
        suggestions.reserveCapacity(images.count)
        for image in images {
            if Task.isCancelled { return suggestions }
            do {
                let candidates = try await recognizeCandidates(in: image)
                suggestions.append(suggestion(from: candidates).region)
            } catch {
                suggestions.append(.fullImage)
            }
        }
        return suggestions
    }

    static func suggestion(from candidates: [OCRFocusTextCandidate]) -> OCRFocusSuggestion {
        let prepared = candidates.compactMap { candidate -> PreparedCandidate? in
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, candidate.boundingBox.isUsable else { return nil }
            let topLeftBox = OCRFocusRegion(
                x: candidate.boundingBox.x,
                y: 1 - candidate.boundingBox.y - candidate.boundingBox.height,
                width: candidate.boundingBox.width,
                height: candidate.boundingBox.height
            ).normalized(minimumDimension: 0.01)
            return PreparedCandidate(
                text: text,
                box: topLeftBox,
                confidence: min(1, max(0, candidate.confidence)),
                lineScore: lineScore(text)
            )
        }
        let ingredientRows = prepared.filter { $0.lineScore >= 1.55 }
        let headings = prepared.filter { matches($0.text, pattern: headingPattern) }
        guard ingredientRows.count >= 2 else {
            return OCRFocusSuggestion(region: .fullImage, confidence: 0)
        }

        let candidateClusters = ingredientRows.map { seed in
            ingredientRows.filter { row in
                horizontalAffinity(seed.box, row.box)
                    && abs(seed.box.y + seed.box.height / 2 - row.box.y - row.box.height / 2) < 0.46
            }
        }
        guard let rows = candidateClusters.max(by: { clusterScore($0) < clusterScore($1) }),
              rows.count >= 2 else {
            return OCRFocusSuggestion(region: .fullImage, confidence: 0)
        }

        var included = rows
        let rowBounds = union(rows.map(\.box))
        let nearbyHeadings = headings.filter { heading in
            heading.box.y + heading.box.height <= rowBounds.y + 0.08
                && rowBounds.y - (heading.box.y + heading.box.height) < 0.16
                && horizontalAffinity(heading.box, rowBounds)
        }
        included.append(contentsOf: nearbyHeadings)

        let bounds = padded(union(included.map(\.box)), horizontal: 0.035, vertical: 0.025)
        let centers = rows.map { $0.box.x + ($0.box.width / 2) }
        let alignmentSpread = (centers.max() ?? 1) - (centers.min() ?? 0)
        let averageConfidence = rows.map(\.confidence).reduce(0, +) / Double(rows.count)
        let headingBonus = nearbyHeadings.isEmpty ? 0 : 0.18
        let alignmentBonus = alignmentSpread < 0.12 ? 0.12 : (alignmentSpread < 0.22 ? 0.06 : 0)
        let rowBonus = min(0.36, Double(rows.count) * 0.08)
        let confidence = min(
            1,
            0.30 + rowBonus + headingBonus + alignmentBonus + (averageConfidence * 0.08)
        )

        guard confidence >= confidentSuggestionThreshold,
              bounds.width >= 0.14,
              bounds.height >= 0.12,
              bounds.width * bounds.height >= 0.025 else {
            return OCRFocusSuggestion(region: .fullImage, confidence: confidence)
        }
        return OCRFocusSuggestion(region: bounds.normalized(), confidence: confidence)
    }

    private static func recognizeCandidates(in image: UIImage) async throws -> [OCRFocusTextCandidate] {
        let normalized = RecipeImagePreprocessor.resizedForOCR(image)
        guard let cgImage = normalized.cgImage else { throw OCRFocusSuggestionError.unreadableImage }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let candidates = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap {
                    observation -> OCRFocusTextCandidate? in
                    guard let recognized = observation.topCandidates(1).first else { return nil }
                    return OCRFocusTextCandidate(
                        text: recognized.string,
                        boundingBox: OCRNormalizedBoundingBox(
                            x: observation.boundingBox.minX,
                            y: observation.boundingBox.minY,
                            width: observation.boundingBox.width,
                            height: observation.boundingBox.height
                        ),
                        confidence: Double(recognized.confidence)
                    )
                }
                continuation.resume(returning: candidates)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.008

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func lineScore(_ text: String) -> Double {
        if matches(text, pattern: instructionPattern) { return -1 }
        var score = 0.0
        if matches(text, pattern: quantityPattern) { score += 1.4 }
        if matches(text, pattern: unitPattern) { score += 0.8 }
        if text.trimmingCharacters(in: .whitespaces).first.map({ "-•*☐✓".contains($0) }) == true {
            score += 0.45
        }
        if text.count <= 72 { score += 0.25 }
        return score
    }

    private static func clusterScore(_ candidates: [PreparedCandidate]) -> Double {
        guard !candidates.isEmpty else { return 0 }
        let bounds = union(candidates.map(\.box))
        let density = Double(candidates.count) / max(0.08, bounds.height)
        return Double(candidates.count) * 2 + min(8, density * 0.08)
    }

    private static func horizontalAffinity(_ lhs: OCRFocusRegion, _ rhs: OCRFocusRegion) -> Bool {
        let overlap = max(0, min(lhs.x + lhs.width, rhs.x + rhs.width) - max(lhs.x, rhs.x))
        let overlapRatio = overlap / max(0.01, min(lhs.width, rhs.width))
        let centerDistance = abs(lhs.x + lhs.width / 2 - rhs.x - rhs.width / 2)
        return overlapRatio >= 0.22 || centerDistance < 0.18
    }

    private static func union(_ regions: [OCRFocusRegion]) -> OCRFocusRegion {
        guard let first = regions.first else { return .fullImage }
        let minX = regions.dropFirst().reduce(first.x) { min($0, $1.x) }
        let minY = regions.dropFirst().reduce(first.y) { min($0, $1.y) }
        let maxX = regions.dropFirst().reduce(first.x + first.width) { max($0, $1.x + $1.width) }
        let maxY = regions.dropFirst().reduce(first.y + first.height) { max($0, $1.y + $1.height) }
        return OCRFocusRegion(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func padded(
        _ region: OCRFocusRegion,
        horizontal: Double,
        vertical: Double
    ) -> OCRFocusRegion {
        let minX = max(0, region.x - horizontal)
        let minY = max(0, region.y - vertical)
        let maxX = min(1, region.x + region.width + horizontal)
        let maxY = min(1, region.y + region.height + vertical)
        return OCRFocusRegion(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

private struct PreparedCandidate {
    var text: String
    var box: OCRFocusRegion
    var confidence: Double
    var lineScore: Double
}

private enum OCRFocusSuggestionError: Error {
    case unreadableImage
}
