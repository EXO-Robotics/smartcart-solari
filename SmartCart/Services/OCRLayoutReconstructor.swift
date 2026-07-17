import Foundation

/// A Vision-independent normalized rectangle. Coordinates use a bottom-left origin.
struct OCRNormalizedBoundingBox: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var minX: Double { x }
    var maxX: Double { x + width }
    var minY: Double { y }
    var maxY: Double { y + height }
    var midY: Double { y + (height / 2) }

    var isUsable: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
    }
}

/// One OCR text observation. Callers can map Vision observations into this value at the boundary.
struct OCRTextObservation: Codable, Equatable, Hashable, Sendable {
    var text: String
    var boundingBox: OCRNormalizedBoundingBox
    var confidence: Double
    var pageIndex: Int
    var bulletMarker: String?
    var alternateCandidates: [OCRTextAlternative]?

    init(
        text: String,
        boundingBox: OCRNormalizedBoundingBox,
        confidence: Double,
        pageIndex: Int = 0,
        bulletMarker: String? = nil,
        alternateCandidates: [OCRTextAlternative]? = nil
    ) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.pageIndex = pageIndex
        self.bulletMarker = bulletMarker
        self.alternateCandidates = alternateCandidates
    }
}

struct OCRTextAlternative: Codable, Equatable, Hashable, Sendable {
    var text: String
    var confidence: Double
}

/// One reconstructed ingredient line that still carries the exact page and
/// normalized geometry needed to make visual evidence reviewable.
struct OCRSourceLine: Codable, Equatable, Hashable, Sendable {
    var text: String
    var pageIndex: Int
    var boundingBox: OCRNormalizedBoundingBox
    var confidence: Double
    var alternateCandidates: [OCRTextAlternative]
}

enum OCRLayoutAmbiguity: String, Codable, Equatable, Hashable, Sendable {
    case invalidBoundingBoxes
    case lowObservationConfidence
    case uncertainColumnDetection
    case overlappingColumns
    case mixedPageLayouts
}

struct OCRPageLayout: Codable, Equatable, Sendable {
    var pageIndex: Int
    var columnCount: Int
    var confidence: Double
    var isAmbiguous: Bool
}

struct OCRLayoutReconstruction: Codable, Equatable, Sendable {
    var ingredientLines: [String]
    var ingredientSourceLines: [OCRSourceLine]
    var ignoredInstructionLines: [String]
    var pageLayouts: [OCRPageLayout]
    var layoutConfidence: Double
    var ambiguities: [OCRLayoutAmbiguity]

    var reconstructedText: String {
        ingredientLines.joined(separator: "\n")
    }

    var detectedColumnCount: Int {
        pageLayouts.map(\.columnCount).max() ?? 0
    }

    var isAmbiguous: Bool {
        !ambiguities.isEmpty
    }
}

/// Reconstructs reading order from OCR lines without importing Vision or platform UI frameworks.
struct OCRLayoutReconstructor {
    private let maximumColumnCount = 3
    private let columnStartGap = 0.14

    func reconstruct(_ observations: [OCRTextObservation]) -> OCRLayoutReconstruction {
        var ambiguities = Set<OCRLayoutAmbiguity>()
        let prepared = observations.compactMap { observation -> PreparedObservation? in
            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            guard observation.boundingBox.isUsable else {
                ambiguities.insert(.invalidBoundingBoxes)
                return nil
            }
            return PreparedObservation(
                text: text,
                box: observation.boundingBox,
                confidence: Self.clamp(observation.confidence),
                pageIndex: observation.pageIndex,
                bulletMarker: Self.cleanedBullet(observation.bulletMarker),
                alternateCandidates: observation.alternateCandidates ?? []
            )
        }

        guard !prepared.isEmpty else {
            ambiguities.insert(.uncertainColumnDetection)
            return OCRLayoutReconstruction(
                ingredientLines: [],
                ingredientSourceLines: [],
                ignoredInstructionLines: [],
                pageLayouts: [],
                layoutConfidence: 0,
                ambiguities: ambiguities.sorted(by: Self.ambiguitySort)
            )
        }

        var ingredientLines: [String] = []
        var ingredientSourceLines: [OCRSourceLine] = []
        var ignoredInstructionLines: [String] = []
        var pageLayouts: [OCRPageLayout] = []
        var weightedConfidence = 0.0
        var observationTotal = 0

        let pages = Dictionary(grouping: prepared, by: \.pageIndex)
        for pageIndex in pages.keys.sorted() {
            guard let pageObservations = pages[pageIndex] else { continue }
            let analysis = analyzePage(pageObservations)
            ingredientLines.append(contentsOf: analysis.ingredientLines)
            ingredientSourceLines.append(contentsOf: analysis.ingredientSourceLines)
            ignoredInstructionLines.append(contentsOf: analysis.ignoredInstructionLines)
            pageLayouts.append(
                OCRPageLayout(
                    pageIndex: pageIndex,
                    columnCount: analysis.columnCount,
                    confidence: analysis.confidence,
                    isAmbiguous: !analysis.ambiguities.isEmpty
                )
            )
            ambiguities.formUnion(analysis.ambiguities)
            weightedConfidence += analysis.confidence * Double(pageObservations.count)
            observationTotal += pageObservations.count
        }

        if Set(pageLayouts.map(\.columnCount)).count > 1 {
            ambiguities.insert(.mixedPageLayouts)
        }

        return OCRLayoutReconstruction(
            ingredientLines: ingredientLines,
            ingredientSourceLines: ingredientSourceLines,
            ignoredInstructionLines: ignoredInstructionLines,
            pageLayouts: pageLayouts,
            layoutConfidence: Self.clamp(weightedConfidence / Double(max(1, observationTotal))),
            ambiguities: ambiguities.sorted(by: Self.ambiguitySort)
        )
    }

    static func reconstruct(_ observations: [OCRTextObservation]) -> OCRLayoutReconstruction {
        OCRLayoutReconstructor().reconstruct(observations)
    }

    private func analyzePage(_ observations: [PreparedObservation]) -> PageAnalysis {
        let averageOCRConfidence = observations.map(\.confidence).reduce(0, +) / Double(observations.count)
        let spanningInstructionBoundary = observations
            .filter { $0.box.width >= 0.58 && Self.isInstructionHeading($0.text) }
            .map { $0.box.midY }
            .max()

        let globalIgnored: [PreparedObservation]
        let ingredientRegion: [PreparedObservation]
        if let boundary = spanningInstructionBoundary {
            globalIgnored = observations.filter { $0.box.midY <= boundary + 0.004 }
            ingredientRegion = observations.filter {
                $0.box.midY > boundary + 0.004
                    && !(Self.isIngredientHeading($0.text) && $0.box.width >= 0.58)
            }
        } else {
            globalIgnored = []
            ingredientRegion = observations.filter {
                !(Self.isIngredientHeading($0.text) && $0.box.width >= 0.58)
            }
        }

        guard !ingredientRegion.isEmpty else {
            return PageAnalysis(
                ingredientLines: [],
                ingredientSourceLines: [],
                ignoredInstructionLines: globalIgnored
                    .sorted(by: Self.physicalReadingOrder)
                    .map(\.renderedText),
                columnCount: 1,
                confidence: Self.clamp(averageOCRConfidence * 0.72),
                ambiguities: [.uncertainColumnDetection]
            )
        }

        let detection = detectColumns(in: ingredientRegion)
        var ambiguities = detection.ambiguities
        if averageOCRConfidence < 0.55 {
            ambiguities.insert(.lowObservationConfidence)
        }

        var columns = Array(repeating: [PreparedObservation](), count: detection.centers.count)
        for observation in ingredientRegion {
            let nearest = detection.centers.indices.min { lhs, rhs in
                abs(observation.box.minX - detection.centers[lhs])
                    < abs(observation.box.minX - detection.centers[rhs])
            } ?? 0
            columns[nearest].append(observation)
        }

        var ingredientLines: [String] = []
        var ingredientSourceLines: [OCRSourceLine] = []
        var ignoredInstructionLines = globalIgnored
            .sorted(by: Self.physicalReadingOrder)
            .map(\.renderedText)

        for column in columns {
            let physicalLines = makePhysicalLines(from: column)
            let logicalLines = mergeBulletContinuations(in: physicalLines)
            var reachedInstructions = false

            for line in logicalLines {
                let rendered = line.renderedText
                if reachedInstructions {
                    ignoredInstructionLines.append(rendered)
                } else if Self.isIngredientHeading(line.text) {
                    continue
                } else if Self.isInstructionLine(line.text) {
                    reachedInstructions = true
                    ignoredInstructionLines.append(rendered)
                } else {
                    ingredientLines.append(rendered)
                    ingredientSourceLines.append(line.sourceLine)
                }
            }
        }

        let confidence = Self.clamp((detection.confidence * 0.72) + (averageOCRConfidence * 0.28))
        if confidence < 0.68 {
            ambiguities.insert(.uncertainColumnDetection)
        }

        return PageAnalysis(
            ingredientLines: ingredientLines,
            ingredientSourceLines: ingredientSourceLines,
            ignoredInstructionLines: ignoredInstructionLines,
            columnCount: columns.count,
            confidence: confidence,
            ambiguities: ambiguities
        )
    }

    private func detectColumns(in observations: [PreparedObservation]) -> ColumnDetection {
        let candidates = observations.filter { $0.box.width <= 0.58 }
        guard candidates.count >= 4 else {
            return ColumnDetection(
                centers: [Self.median(observations.map { $0.box.minX })],
                confidence: candidates.count < 2 ? 0.62 : 0.82,
                ambiguities: candidates.count < 2 ? [.uncertainColumnDetection] : []
            )
        }

        let sorted = candidates.sorted { $0.box.minX < $1.box.minX }
        var bands: [[PreparedObservation]] = []
        for observation in sorted {
            guard let lastBand = bands.last else {
                bands.append([observation])
                continue
            }
            let center = Self.median(lastBand.map { $0.box.minX })
            if observation.box.minX - center >= columnStartGap,
               bands.count < maximumColumnCount {
                bands.append([observation])
            } else {
                bands[bands.count - 1].append(observation)
            }
        }

        let minimumBandSize = max(2, Int(floor(Double(candidates.count) * 0.18)))
        var substantive = bands.filter { $0.count >= minimumBandSize }
        if substantive.count <= 1 {
            let largestGap = zip(sorted, sorted.dropFirst())
                .map { $1.box.minX - $0.box.minX }
                .max() ?? 0
            let uncertain = largestGap >= columnStartGap * 0.72
            return ColumnDetection(
                centers: [Self.median(observations.map { $0.box.minX })],
                confidence: uncertain ? 0.64 : 0.90,
                ambiguities: uncertain ? [.uncertainColumnDetection] : []
            )
        }

        substantive.sort {
            Self.median($0.map { $0.box.minX }) < Self.median($1.map { $0.box.minX })
        }
        let centers = substantive.map { Self.median($0.map { $0.box.minX }) }
        let gaps = zip(centers, centers.dropFirst()).map { $1 - $0 }
        let minimumGap = gaps.min() ?? columnStartGap
        let balance = Double(substantive.map(\.count).min() ?? 1)
            / Double(substantive.map(\.count).max() ?? 1)
        let separation = Self.clamp((minimumGap - columnStartGap) / 0.22)
        var confidence = 0.70 + (0.20 * separation) + (0.10 * balance)
        var ambiguities = Set<OCRLayoutAmbiguity>()

        for index in 0..<(substantive.count - 1) {
            let leftTypicalMaxX = Self.median(substantive[index].map { $0.box.maxX })
            let rightTypicalMinX = Self.median(substantive[index + 1].map { $0.box.minX })
            if leftTypicalMaxX > rightTypicalMinX + 0.02 {
                ambiguities.insert(.overlappingColumns)
                confidence -= 0.16
            }
        }

        if minimumGap < columnStartGap + 0.025 || balance < 0.34 {
            ambiguities.insert(.uncertainColumnDetection)
        }

        return ColumnDetection(
            centers: centers,
            confidence: Self.clamp(confidence),
            ambiguities: ambiguities
        )
    }

    private func makePhysicalLines(from observations: [PreparedObservation]) -> [PhysicalLine] {
        let sorted = observations.sorted {
            if abs($0.box.midY - $1.box.midY) > 0.006 {
                return $0.box.midY > $1.box.midY
            }
            return $0.box.minX < $1.box.minX
        }
        var rows: [[PreparedObservation]] = []

        for observation in sorted {
            if let index = rows.indices.last,
               Self.belongsOnSameRow(observation, as: rows[index]) {
                rows[index].append(observation)
            } else {
                rows.append([observation])
            }
        }

        return rows.map { row in
            let fragments = row.sorted { $0.box.minX < $1.box.minX }
            var marker: String?
            let primaryFragments = fragments.compactMap { fragment -> String? in
                let split = Self.extractBullet(from: fragment.text, explicit: fragment.bulletMarker)
                if marker == nil { marker = split.marker }
                return split.text.isEmpty ? nil : split.text
            }
            let joined = Self.collapseWhitespace(primaryFragments.joined(separator: " "))
            var alternatives: [OCRTextAlternative] = []
            for (fragmentIndex, fragment) in fragments.enumerated() {
                for alternative in fragment.alternateCandidates.prefix(2) {
                    var variant = fragments.map {
                        Self.extractBullet(from: $0.text, explicit: $0.bulletMarker).text
                    }
                    variant[fragmentIndex] = Self.extractBullet(
                        from: alternative.text,
                        explicit: fragment.bulletMarker
                    ).text
                    let variantText = Self.repairMeasurementUnitTokenJoins(
                        in: Self.collapseWhitespace(variant.joined(separator: " "))
                    )
                    guard !variantText.isEmpty,
                          variantText.caseInsensitiveCompare(joined) != .orderedSame,
                          !alternatives.contains(where: { $0.text.caseInsensitiveCompare(variantText) == .orderedSame })
                    else { continue }
                    alternatives.append(
                        OCRTextAlternative(text: variantText, confidence: alternative.confidence)
                    )
                }
            }
            return PhysicalLine(
                text: Self.repairMeasurementUnitTokenJoins(in: joined),
                bulletMarker: marker,
                pageIndex: fragments.first?.pageIndex ?? 0,
                minX: fragments.map { $0.box.minX }.min() ?? 0,
                minY: fragments.map { $0.box.minY }.min() ?? 0,
                maxX: fragments.map { $0.box.maxX }.max() ?? 0,
                maxY: fragments.map { $0.box.maxY }.max() ?? 0,
                averageHeight: fragments.map { $0.box.height }.reduce(0, +) / Double(fragments.count),
                confidence: fragments.map(\.confidence).reduce(0, +) / Double(fragments.count),
                alternateCandidates: Array(alternatives.prefix(4))
            )
        }
        .filter { !$0.text.isEmpty }
    }

    private func mergeBulletContinuations(in lines: [PhysicalLine]) -> [LogicalLine] {
        var result: [LogicalLine] = []

        for line in lines {
            if let previous = result.last,
               previous.bulletMarker != nil,
               line.bulletMarker == nil,
               line.minX >= previous.minX + max(0.018, previous.averageHeight * 0.45),
               previous.minY - line.maxY <= max(0.065, previous.averageHeight * 2.2),
               !Self.isInstructionLine(line.text) {
                let mergedText = Self.collapseWhitespace(previous.text + " " + line.text)
                var alternatives = previous.alternateCandidates.map {
                    OCRTextAlternative(
                        text: Self.collapseWhitespace($0.text + " " + line.text),
                        confidence: min($0.confidence, line.confidence)
                    )
                }
                alternatives.append(contentsOf: line.alternateCandidates.map {
                    OCRTextAlternative(
                        text: Self.collapseWhitespace(previous.text + " " + $0.text),
                        confidence: min(previous.confidence, $0.confidence)
                    )
                })
                result[result.count - 1].text = mergedText
                result[result.count - 1].minX = min(previous.minX, line.minX)
                result[result.count - 1].minY = min(previous.minY, line.minY)
                result[result.count - 1].maxX = max(previous.maxX, line.maxX)
                result[result.count - 1].maxY = max(previous.maxY, line.maxY)
                result[result.count - 1].confidence = (previous.confidence + line.confidence) / 2
                result[result.count - 1].alternateCandidates = Array(
                    alternatives
                        .filter { $0.text.caseInsensitiveCompare(mergedText) != .orderedSame }
                        .prefix(6)
                )
            } else {
                result.append(
                    LogicalLine(
                        text: line.text,
                        bulletMarker: line.bulletMarker,
                        pageIndex: line.pageIndex,
                        minX: line.minX,
                        minY: line.minY,
                        maxX: line.maxX,
                        maxY: line.maxY,
                        averageHeight: line.averageHeight,
                        confidence: line.confidence,
                        alternateCandidates: line.alternateCandidates
                    )
                )
            }
        }

        return result
    }

    private static func belongsOnSameRow(
        _ observation: PreparedObservation,
        as row: [PreparedObservation]
    ) -> Bool {
        let rowMidY = row.map { $0.box.midY }.reduce(0, +) / Double(row.count)
        let rowHeight = row.map { $0.box.height }.reduce(0, +) / Double(row.count)
        return abs(observation.box.midY - rowMidY) <= max(0.012, min(rowHeight, observation.box.height) * 0.55)
    }

    private static func extractBullet(from text: String, explicit: String?) -> (marker: String?, text: String) {
        var remainder = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit {
            if remainder.hasPrefix(explicit) {
                remainder.removeFirst(explicit.count)
                remainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return (explicit, remainder)
        }

        for marker in ["•", "-", "*", "☐", "✓"] where remainder.hasPrefix(marker) {
            remainder.removeFirst(marker.count)
            return (marker, remainder.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (nil, remainder)
    }

    /// Repairs a split only when the fragments form a known unit directly after a quantity.
    /// It intentionally leaves all other OCR word splits untouched.
    private static func repairMeasurementUnitTokenJoins(in text: String) -> String {
        var tokens = text.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard tokens.count >= 3 else { return text }

        let units: Set<String> = [
            "cup", "cups", "tbsp", "tbsps", "tablespoon", "tablespoons",
            "tsp", "tsps", "teaspoon", "teaspoons", "oz", "ounce", "ounces",
            "lb", "lbs", "pound", "pounds", "g", "gram", "grams", "kg",
            "kilogram", "kilograms", "ml", "milliliter", "milliliters", "l",
            "liter", "liters", "clove", "cloves", "can", "cans", "jar", "jars",
            "bag", "bags", "bunch", "bunches", "package", "packages", "pkg",
            "pinch", "pinches", "slice", "slices", "stick", "sticks"
        ]

        var index = 1
        while index < tokens.count - 1 {
            guard hasQuantityPrefix(tokens, endingBefore: index) else {
                index += 1
                continue
            }

            var repaired = false
            for length in stride(from: min(3, tokens.count - index), through: 2, by: -1) {
                let range = index..<(index + length)
                let cores = range.map { unitCore(tokens[$0]) }
                let candidate = cores.joined().lowercased()
                let lastToken = tokens[index + length - 1]
                let trailing = trailingPunctuation(in: lastToken)
                guard units.contains(candidate),
                      cores.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isLetter) }),
                      range.dropLast().allSatisfy({ tokens[$0] == unitCore(tokens[$0]) }),
                      lastToken == cores.last! + trailing else { continue }

                let joined = cores.joined() + trailing
                tokens.replaceSubrange(range, with: [joined])
                repaired = true
                break
            }

            if !repaired { index += 1 }
        }

        return tokens.joined(separator: " ")
    }

    private static func hasQuantityPrefix(_ tokens: [String], endingBefore index: Int) -> Bool {
        guard index > 0, index <= 3 else { return false }
        let quantityTokens = tokens[..<index]
        return quantityTokens.allSatisfy { token in
            let core = unitCore(token).lowercased()
            if ["a", "an", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "half", "quarter"].contains(core) {
                return true
            }
            if core.contains("/") || core.contains("-") { return true }
            if core.rangeOfCharacter(from: .decimalDigits) != nil { return true }
            return core.rangeOfCharacter(from: CharacterSet(charactersIn: "¼½¾⅓⅔⅛⅜⅝⅞⅙⅚")) != nil
        }
    }

    private static func unitCore(_ token: String) -> String {
        token.trimmingCharacters(in: .punctuationCharacters)
    }

    private static func trailingPunctuation(in token: String) -> String {
        String(token.reversed().prefix { $0.isPunctuation }.reversed())
    }

    private static func isIngredientHeading(_ text: String) -> Bool {
        let normalized = headingKey(text)
        return ["ingredient", "ingredients", "what you need", "you will need"].contains(normalized)
    }

    private static func isInstructionHeading(_ text: String) -> Bool {
        let normalized = headingKey(text)
        return [
            "direction", "directions", "instruction", "instructions", "method",
            "preparation", "steps", "how to make", "make it"
        ].contains(normalized)
    }

    private static func isInstructionLine(_ text: String) -> Bool {
        let normalized = headingKey(text)
        if isInstructionHeading(normalized) { return true }

        var actionText = normalized
        if let match = actionText.range(of: #"^\d{1,2}[.)]\s*"#, options: .regularExpression) {
            actionText.removeSubrange(match)
        }
        let actions = [
            "preheat", "heat", "mix", "stir", "whisk", "combine", "add", "bake",
            "cook", "simmer", "boil", "roast", "grill", "fold", "beat", "place",
            "transfer", "spread", "pour", "arrange", "season", "chill", "refrigerate",
            "freeze", "serve", "let", "set", "line", "grease", "melt"
        ]
        return actions.contains { action in
            actionText == action || actionText.hasPrefix(action + " ")
        }
    }

    private static func headingKey(_ text: String) -> String {
        collapseWhitespace(
            text.lowercased().trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
            )
        )
    }

    private static func cleanedBullet(_ marker: String?) -> String? {
        guard let marker else { return nil }
        let cleaned = marker.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func ambiguitySort(_ lhs: OCRLayoutAmbiguity, _ rhs: OCRLayoutAmbiguity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private static func physicalReadingOrder(_ lhs: PreparedObservation, _ rhs: PreparedObservation) -> Bool {
        if abs(lhs.box.midY - rhs.box.midY) > 0.006 {
            return lhs.box.midY > rhs.box.midY
        }
        return lhs.box.minX < rhs.box.minX
    }
}

private struct PreparedObservation {
    var text: String
    var box: OCRNormalizedBoundingBox
    var confidence: Double
    var pageIndex: Int
    var bulletMarker: String?
    var alternateCandidates: [OCRTextAlternative]

    var renderedText: String {
        guard let bulletMarker else { return text }
        return "\(bulletMarker) \(text)"
    }
}

private struct PhysicalLine {
    var text: String
    var bulletMarker: String?
    var pageIndex: Int
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
    var averageHeight: Double
    var confidence: Double
    var alternateCandidates: [OCRTextAlternative]
}

private struct LogicalLine {
    var text: String
    var bulletMarker: String?
    var pageIndex: Int
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
    var averageHeight: Double
    var confidence: Double
    var alternateCandidates: [OCRTextAlternative]

    var renderedText: String {
        guard let bulletMarker else { return text }
        return "\(bulletMarker) \(text)"
    }

    var sourceLine: OCRSourceLine {
        OCRSourceLine(
            text: renderedText,
            pageIndex: pageIndex,
            boundingBox: OCRNormalizedBoundingBox(
                x: minX,
                y: minY,
                width: max(0, maxX - minX),
                height: max(0, maxY - minY)
            ),
            confidence: confidence,
            alternateCandidates: alternateCandidates
        )
    }
}

private struct ColumnDetection {
    var centers: [Double]
    var confidence: Double
    var ambiguities: Set<OCRLayoutAmbiguity>
}

private struct PageAnalysis {
    var ingredientLines: [String]
    var ingredientSourceLines: [OCRSourceLine]
    var ignoredInstructionLines: [String]
    var columnCount: Int
    var confidence: Double
    var ambiguities: Set<OCRLayoutAmbiguity>
}
