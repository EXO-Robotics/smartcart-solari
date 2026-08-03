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
    var observationID: String?
    var text: String
    var boundingBox: OCRNormalizedBoundingBox
    var confidence: Double
    var pageIndex: Int
    var bulletMarker: String?
    var alternateCandidates: [OCRTextAlternative]?
    /// Stable order from the upstream OCR request before any geometric sorting.
    var originalOrder: Int?

    init(
        observationID: String? = nil,
        text: String,
        boundingBox: OCRNormalizedBoundingBox,
        confidence: Double,
        pageIndex: Int = 0,
        bulletMarker: String? = nil,
        alternateCandidates: [OCRTextAlternative]? = nil,
        originalOrder: Int? = nil
    ) {
        self.observationID = observationID
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.pageIndex = pageIndex
        self.bulletMarker = bulletMarker
        self.alternateCandidates = alternateCandidates
        self.originalOrder = originalOrder
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
    var columnIndex: Int
    var sourceObservationIDs: [String]
    var continuationAttached: Bool
    var reconstructionConfidence: Double

    init(
        text: String,
        pageIndex: Int,
        boundingBox: OCRNormalizedBoundingBox,
        confidence: Double,
        alternateCandidates: [OCRTextAlternative],
        columnIndex: Int = 0,
        sourceObservationIDs: [String] = [],
        continuationAttached: Bool = false,
        reconstructionConfidence: Double? = nil
    ) {
        self.text = text
        self.pageIndex = pageIndex
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.alternateCandidates = alternateCandidates
        self.columnIndex = columnIndex
        self.sourceObservationIDs = sourceObservationIDs
        self.continuationAttached = continuationAttached
        self.reconstructionConfidence = reconstructionConfidence ?? confidence
    }
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
    var suggestedTitle: String?
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
        let prepared = observations.enumerated().flatMap { index, observation -> [PreparedObservation] in
            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            guard observation.boundingBox.isUsable else {
                ambiguities.insert(.invalidBoundingBoxes)
                return []
            }
            return Self.prepareFragments(
                from: observation,
                text: text,
                fallbackID: "page-\(observation.pageIndex)-observation-\(index)"
            )
        }

        guard !prepared.isEmpty else {
            ambiguities.insert(.uncertainColumnDetection)
            return OCRLayoutReconstruction(
                suggestedTitle: nil,
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
        var suggestedTitle: String?
        var ignoredInstructionLines: [String] = []
        var pageLayouts: [OCRPageLayout] = []
        var weightedConfidence = 0.0
        var observationTotal = 0

        let pages = Dictionary(grouping: prepared, by: \.pageIndex)
        for pageIndex in pages.keys.sorted() {
            guard let pageObservations = pages[pageIndex] else { continue }
            let analysis = analyzePage(pageObservations)
            if suggestedTitle == nil {
                suggestedTitle = analysis.suggestedTitle
            }
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
            suggestedTitle: suggestedTitle,
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

    /// Vision can return two side-by-side bullet items as one wide observation.
    /// Split those fragments before column detection so a right-column wrap can
    /// never be attached to the left column merely because their baselines align.
    private static func prepareFragments(
        from observation: OCRTextObservation,
        text: String,
        fallbackID: String
    ) -> [PreparedObservation] {
        let observationID = observation.observationID ?? fallbackID
        let segments = embeddedBulletSegments(in: text)
        guard segments.count > 1 else {
            return [
                PreparedObservation(
                    text: text,
                    box: observation.boundingBox,
                    confidence: clamp(observation.confidence),
                    pageIndex: observation.pageIndex,
                    bulletMarker: cleanedBullet(observation.bulletMarker),
                    alternateCandidates: observation.alternateCandidates ?? [],
                    sourceObservationIDs: [observationID]
                )
            ]
        }

        let alternateSegments = (observation.alternateCandidates ?? []).map { alternative in
            (alternative, embeddedBulletSegments(in: alternative.text))
        }
        return segments.enumerated().map { segmentIndex, segment in
            let box = OCRNormalizedBoundingBox(
                x: observation.boundingBox.x + (observation.boundingBox.width * segment.startRatio),
                y: observation.boundingBox.y,
                width: observation.boundingBox.width * (segment.endRatio - segment.startRatio),
                height: observation.boundingBox.height
            )
            let alternatives = alternateSegments.compactMap { alternative, split -> OCRTextAlternative? in
                guard split.indices.contains(segmentIndex) else { return nil }
                let alternateText = split[segmentIndex].text
                guard alternateText.caseInsensitiveCompare(segment.text) != .orderedSame else { return nil }
                return OCRTextAlternative(text: alternateText, confidence: alternative.confidence)
            }
            return PreparedObservation(
                text: segment.text,
                box: box,
                confidence: clamp(observation.confidence),
                pageIndex: observation.pageIndex,
                bulletMarker: segment.marker,
                alternateCandidates: alternatives,
                sourceObservationIDs: [observationID]
            )
        }
    }

    private static func embeddedBulletSegments(in text: String) -> [BulletSegment] {
        guard let regex = try? NSRegularExpression(pattern: #"[•☐✓]"#) else { return [] }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard matches.count > 1, source.length > 0 else { return [] }

        return matches.enumerated().compactMap { index, match in
            let start = match.range.location
            let end = index + 1 < matches.count ? matches[index + 1].range.location : source.length
            guard end > start else { return nil }
            let raw = source.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            return BulletSegment(
                text: raw,
                marker: source.substring(with: match.range),
                startRatio: Double(start) / Double(source.length),
                endRatio: Double(end) / Double(source.length)
            )
        }
    }

    private static func extractSuggestedTitle(
        from observations: [PreparedObservation],
        above heading: PreparedObservation
    ) -> String? {
        let candidates = observations.filter { observation in
            observation.box.midY > heading.box.midY + 0.012
                && observation.bulletMarker == nil
                && !isIngredientHeading(observation.text)
                && !isInstructionHeading(observation.text)
                && !hasLeadingQuantity(observation.text)
        }
        guard let maximumHeight = candidates.map(\.box.height).max() else { return nil }
        let titleLines = candidates
            .filter { $0.box.height >= max(0.024, maximumHeight * 0.68) }
            .sorted(by: physicalReadingOrder)
            .prefix(3)
            .map(\.text)
        guard !titleLines.isEmpty else { return nil }
        let joined = collapseWhitespace(titleLines.joined(separator: " "))
        guard joined.count <= 90 else { return nil }
        return joined.lowercased().split(separator: " ").map { token in
            token.prefix(1).uppercased() + token.dropFirst()
        }.joined(separator: " ")
    }

    private func analyzePage(_ observations: [PreparedObservation]) -> PageAnalysis {
        let averageOCRConfidence = observations.map(\.confidence).reduce(0, +) / Double(observations.count)
        let ingredientHeading = observations
            .filter { Self.isIngredientHeading($0.text) }
            .max { $0.box.midY < $1.box.midY }
        let instructionBoundary = observations
            .filter {
                Self.isInstructionHeading($0.text)
                    && (ingredientHeading == nil || $0.box.midY < ingredientHeading!.box.midY)
            }
            .map(\.box.midY)
            .max()
        let suggestedTitle = ingredientHeading.flatMap { heading in
            Self.extractSuggestedTitle(from: observations, above: heading)
        }

        let globalIgnored: [PreparedObservation]
        let ingredientRegion: [PreparedObservation]
        if let heading = ingredientHeading {
            globalIgnored = instructionBoundary.map { boundary in
                observations.filter { $0.box.midY <= boundary + 0.004 }
            } ?? []
            ingredientRegion = observations.filter { observation in
                observation.box.midY < heading.box.midY - 0.004
                    && (instructionBoundary == nil || observation.box.midY > instructionBoundary! + 0.004)
                    && !Self.isIngredientHeading(observation.text)
                    && !Self.isInstructionHeading(observation.text)
            }
        } else if let boundary = instructionBoundary {
            globalIgnored = observations.filter { $0.box.midY <= boundary + 0.004 }
            ingredientRegion = observations.filter {
                $0.box.midY > boundary + 0.004
                    && !Self.isIngredientHeading($0.text)
            }
        } else {
            globalIgnored = []
            ingredientRegion = observations.filter {
                !Self.isIngredientHeading($0.text)
            }
        }

        guard !ingredientRegion.isEmpty else {
            return PageAnalysis(
                suggestedTitle: suggestedTitle,
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

        let hasIngredientEvidence = columns.contains { column in
            column.contains(where: Self.isIngredientStart)
        }

        for (columnIndex, column) in columns.enumerated() {
            let physicalLines = makePhysicalLines(from: column, columnIndex: columnIndex)
            let logicalLines = reconstructCandidateGroups(in: physicalLines)
            let columnHasIngredientEvidence = column.contains(where: Self.isIngredientStart)
            var reachedInstructions = false

            for (lineIndex, line) in logicalLines.enumerated() {
                let rendered = line.renderedText
                let nextLine = logicalLines.indices.contains(lineIndex + 1)
                    ? logicalLines[lineIndex + 1]
                    : nil
                let role = Self.groupRole(for: line, followedBy: nextLine)
                if reachedInstructions {
                    ignoredInstructionLines.append(rendered)
                } else if role == .ingredientHeading || role == .sectionHeading {
                    continue
                } else if role == .instructionOrProse {
                    reachedInstructions = true
                    ignoredInstructionLines.append(rendered)
                } else if role == .continuation || role == .noise {
                    // Keep unresolved source fragments out of the shopping stream.
                    // The raw observation remains available in source evidence.
                    ignoredInstructionLines.append(rendered)
                } else if ingredientHeading != nil,
                          hasIngredientEvidence,
                          !columnHasIngredientEvidence {
                    // A disconnected, unanchored component beneath an explicit
                    // Ingredients heading is commonly neighboring card copy or
                    // a title from another OCR region. Keep it out of ingredients.
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
            suggestedTitle: suggestedTitle,
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
        guard candidates.count >= 2 else {
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

        if bands.count <= 1 {
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

        // Sparse OCR regions still carry meaningful geometry. Dropping a
        // singleton band forces distant card regions into the nearest column,
        // which can then contaminate an otherwise valid ingredient line.
        var substantive = bands
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

    private func makePhysicalLines(
        from observations: [PreparedObservation],
        columnIndex: Int
    ) -> [PhysicalLine] {
        let sorted = observations.sorted {
            if abs($0.box.midY - $1.box.midY) > 0.006 {
                return $0.box.midY > $1.box.midY
            }
            return $0.box.minX < $1.box.minX
        }
        var rows: [[PreparedObservation]] = []

        for observation in sorted {
            if let index = rows.indices.reversed().first(where: {
                Self.belongsOnSameRow(observation, as: rows[$0])
                    && !Self.crossesIngredientStart(observation, row: rows[$0])
            }) {
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
            let joined = Self.normalizeOCRLine(primaryFragments.joined(separator: " "))
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
                    let variantText = Self.normalizeOCRLine(variant.joined(separator: " "))
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
                text: joined,
                bulletMarker: marker,
                pageIndex: fragments.first?.pageIndex ?? 0,
                columnIndex: columnIndex,
                sourceObservationIDs: Self.unique(fragments.flatMap(\.sourceObservationIDs)),
                minX: fragments.map { $0.box.minX }.min() ?? 0,
                minY: fragments.map { $0.box.minY }.min() ?? 0,
                maxX: fragments.map { $0.box.maxX }.max() ?? 0,
                maxY: fragments.map { $0.box.maxY }.max() ?? 0,
                averageHeight: fragments.map { $0.box.height }.reduce(0, +) / Double(fragments.count),
                confidence: fragments.map(\.confidence).reduce(0, +) / Double(fragments.count),
                reconstructionConfidence: fragments.map(\.confidence).reduce(0, +) / Double(fragments.count),
                alternateCandidates: Array(alternatives.prefix(4))
            )
        }
        .filter { !$0.text.isEmpty }
    }

    /// Builds and scores the two safe candidates for each adjacent pair: keep
    /// discrete lines or attach the second as a continuation. The merge wins
    /// only with strong geometry plus grammatical incompleteness. This makes
    /// cross-ingredient merges more expensive than an uncertain split.
    private func reconstructCandidateGroups(in lines: [PhysicalLine]) -> [LogicalLine] {
        var result: [LogicalLine] = []

        for line in lines {
            if let previous = result.last,
               Self.continuationScore(line, after: previous) >= 6 {
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
                result[result.count - 1].sourceObservationIDs = Self.unique(
                    previous.sourceObservationIDs + line.sourceObservationIDs
                )
                result[result.count - 1].continuationAttached = true
                result[result.count - 1].reconstructionConfidence = min(
                    previous.reconstructionConfidence,
                    line.reconstructionConfidence
                ) * 0.97
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
                        columnIndex: line.columnIndex,
                        sourceObservationIDs: line.sourceObservationIDs,
                        continuationAttached: false,
                        reconstructionConfidence: line.reconstructionConfidence,
                        minX: line.minX,
                        minY: line.minY,
                        maxX: line.maxX,
                        maxY: line.maxY,
                        averageHeight: line.averageHeight,
                        anchorMinX: line.minX,
                        anchorMaxX: line.maxX,
                        anchorMinY: line.minY,
                        confidence: line.confidence,
                        alternateCandidates: line.alternateCandidates
                    )
                )
            }
        }

        return result
    }

    private static func continuationScore(
        _ line: PhysicalLine,
        after previous: LogicalLine
    ) -> Int {
        guard line.bulletMarker == nil,
              !hasLeadingQuantity(line.text),
              line.columnIndex == previous.columnIndex,
              line.maxY <= previous.minY + max(0.008, previous.averageHeight * 0.30),
              previous.minY - line.maxY <= max(0.065, previous.averageHeight * 2.2),
              !isInstructionLine(line.text),
              !isInstructionLine(previous.text)
        else { return .min }

        let strictAnchor = isSafeContinuation(line, of: previous)
        let relaxedAnchor = isRelaxedContinuation(line, of: previous)
        guard strictAnchor || relaxedAnchor else { return .min }

        let previousIncomplete = appearsGrammaticallyIncomplete(previous.text)
        let fragment = looksLikeContinuationFragment(line.text)
        // A non-bulleted complete ingredient never absorbs a following row.
        guard previous.bulletMarker != nil || previousIncomplete else { return .min }

        var score = strictAnchor ? 3 : 2
        if previous.bulletMarker != nil { score += 2 }
        if previousIncomplete { score += 3 }
        if fragment { score += 3 }
        if line.text.first?.isLowercase == true { score += 1 }
        if line.text.split(whereSeparator: \Character.isWhitespace).count <= 4 { score += 1 }
        if independentlyLooksLikeIngredient(line.text) { score -= 6 }
        return score
    }

    private static func isRelaxedContinuation(
        _ line: PhysicalLine,
        of previous: LogicalLine
    ) -> Bool {
        let startDelta = abs(line.minX - previous.anchorMinX)
        let overlap = min(previous.anchorMaxX, line.maxX)
            - max(previous.anchorMinX, line.minX)
        return startDelta <= max(0.035, previous.averageHeight)
            && overlap >= max(0.01, min(line.maxX - line.minX, previous.anchorMaxX - previous.anchorMinX) * 0.20)
    }

    private static func appearsGrammaticallyIncomplete(_ text: String) -> Bool {
        let value = headingKey(text)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(",") { return true }
        return value.range(
            of: #"(?:\b(?:and|or|with)|\b(?:coarsely|finely|roughly|freshly|shredded|flaked|grated|chopped|minced|diced|sliced))$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func looksLikeContinuationFragment(_ text: String) -> Bool {
        let value = headingKey(text)
        return value.range(
            of: #"^(?:(?:or\s+)?(?:chopped|flaked|grated|shredded|diced|minced|sliced)|divided|optional|preferably|to taste|for (?:serving|garnish|topping))\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func independentlyLooksLikeIngredient(_ text: String) -> Bool {
        hasLeadingQuantity(text)
            || extractBullet(from: text, explicit: nil).marker != nil
    }

    private enum GroupRole {
        case ingredient
        case continuation
        case ingredientHeading
        case sectionHeading
        case instructionOrProse
        case noise
        case ambiguous
    }

    private static func groupRole(
        for line: LogicalLine,
        followedBy nextLine: LogicalLine?
    ) -> GroupRole {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .noise }
        if isIngredientHeading(text) { return .ingredientHeading }
        if isInstructionLine(text) { return .instructionOrProse }
        if looksLikeStructuralSectionHeading(text, followedBy: nextLine?.text) {
            return .sectionHeading
        }
        if looksLikeContinuationFragment(text) && !line.continuationAttached {
            return .continuation
        }
        if hasLeadingQuantity(text) || line.bulletMarker != nil { return .ingredient }
        if text.hasSuffix(".") && text.split(whereSeparator: \Character.isWhitespace).count > 6 {
            return .instructionOrProse
        }
        return .ambiguous
    }

    private static func looksLikeStructuralSectionHeading(
        _ text: String,
        followedBy nextText: String?
    ) -> Bool {
        guard let nextText,
              hasLeadingQuantity(nextText) || extractBullet(from: nextText, explicit: nil).marker != nil,
              !hasLeadingQuantity(text),
              text.split(whereSeparator: \Character.isWhitespace).count <= 8
        else { return false }
        let key = headingKey(text)
        guard key.hasPrefix("for the ") || key.hasPrefix("for ") else { return false }
        let words = text.split(whereSeparator: \Character.isWhitespace)
        let titleLikeCount = words.filter { $0.first?.isUppercase == true }.count
        return titleLikeCount >= max(2, words.count / 2)
    }

    private static func belongsOnSameRow(
        _ observation: PreparedObservation,
        as row: [PreparedObservation]
    ) -> Bool {
        let rowMidY = row.map { $0.box.midY }.reduce(0, +) / Double(row.count)
        let rowHeight = row.map { $0.box.height }.reduce(0, +) / Double(row.count)
        guard abs(observation.box.midY - rowMidY)
                <= max(0.012, min(rowHeight, observation.box.height) * 0.55)
        else { return false }

        let nearestHorizontalGap = row.map { fragment in
            horizontalGap(observation.box, fragment.box)
        }.min() ?? .infinity
        let maximumFragmentGap = min(
            0.055,
            max(0.020, min(rowHeight, observation.box.height) * 1.5)
        )
        return nearestHorizontalGap <= maximumFragmentGap
    }

    private static func crossesIngredientStart(
        _ observation: PreparedObservation,
        row: [PreparedObservation]
    ) -> Bool {
        let rowHasBullet = row.contains {
            $0.bulletMarker != nil || extractBullet(from: $0.text, explicit: nil).marker != nil
        }
        let observationHasBullet = observation.bulletMarker != nil
            || extractBullet(from: observation.text, explicit: nil).marker != nil
        // Encountering a bullet always starts a new item, including when OCR
        // happened to return a left-side unbulleted fragment first.
        if observationHasBullet { return true }

        guard rowHasBullet else { return false }
        let bulletStart = row
            .filter {
                $0.bulletMarker != nil
                    || extractBullet(from: $0.text, explicit: nil).marker != nil
            }
            .map { $0.box.minX }
            .min() ?? observation.box.minX
        return observation.box.minX < bulletStart - 0.004
            || observation.box.minX - bulletStart > 0.18
    }

    private static func horizontalGap(
        _ lhs: OCRNormalizedBoundingBox,
        _ rhs: OCRNormalizedBoundingBox
    ) -> Double {
        max(0, max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX))
    }

    private static func isSafeContinuation(
        _ line: PhysicalLine,
        of previous: LogicalLine
    ) -> Bool {
        let indent = line.minX - previous.anchorMinX
        let minimumIndent = max(0.018, previous.averageHeight * 0.45)
        let maximumIndent = min(0.12, max(0.08, previous.averageHeight * 3.0))
        let maximumAnchorDrop = max(0.08, previous.averageHeight * 3.0)
        guard indent >= minimumIndent,
              indent <= maximumIndent,
              previous.anchorMinY - line.maxY <= maximumAnchorDrop
        else { return false }

        let overlap = min(previous.anchorMaxX, line.maxX)
            - max(previous.anchorMinX, line.minX)
        if overlap > max(0.004, min(line.maxX - line.minX, previous.anchorMaxX - previous.anchorMinX) * 0.06) {
            return true
        }

        let gap = max(
            0,
            max(line.minX - previous.anchorMaxX, previous.anchorMinX - line.maxX)
        )
        return gap <= max(0.010, previous.averageHeight * 0.35)
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

    private static func normalizeOCRLine(_ text: String) -> String {
        var normalized = collapseWhitespace(text)
        normalized = normalized.replacingOccurrences(
            of: #"^(?:I|l)(?=\s+(?:large|medium|small|cups?|tbsp|tsp|tablespoons?|teaspoons?|oz|ounces?|lbs?|pounds?|grams?|kg|ml|cloves?|cans?|jars?|bags?|packages?)\b)"#,
            with: "1",
            options: [.regularExpression, .caseInsensitive]
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?i)^(\s*(?:\d+(?:[./]\d+)?|\d+\s+\d+/\d+|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚])\s+)(cups?|tbsp|tbsps|tablespoons?|tsp|tsps|teaspoons?|oz|ounces?|lbs?|pounds?|grams?|kg|kilograms?|ml|milliliters?|liters?|cloves?|cans?|jars?|bags?|bunches?|packages?|pinches?|slices?|sticks?)(?=[A-Za-z])"#,
            with: "$1$2 ",
            options: .regularExpression
        )
        normalized = repairMeasurementUnitTokenJoins(in: normalized)
        normalized = normalized.replacingOccurrences(
            of: #"(?i)\bsa[mn]i-sweet(?=\s+chocolate)"#,
            with: "semi-sweet",
            options: .regularExpression
        )
        return collapseWhitespace(normalized)
    }

    private static func hasLeadingQuantity(_ text: String) -> Bool {
        text.range(
            of: #"^\s*(?:[-•*☐✓]\s*)?(?:\d|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|one\b|two\b|three\b|four\b|five\b|six\b|seven\b|eight\b|nine\b|ten\b|half\b|quarter\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isIngredientStart(_ observation: PreparedObservation) -> Bool {
        observation.bulletMarker != nil
            || extractBullet(from: observation.text, explicit: nil).marker != nil
            || hasLeadingQuantity(observation.text)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
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

        let actions = [
            "preheat", "heat", "mix", "stir", "whisk", "combine", "add", "bake",
            "cook", "simmer", "boil", "roast", "grill", "fold", "beat", "place",
            "transfer", "spread", "pour", "arrange", "season", "chill", "refrigerate",
            "freeze", "serve", "let", "set", "line", "grease", "melt", "mash"
        ]

        // Imperative verbs are meaningful only at a sentence boundary. This
        // catches embedded card copy such as "EASY AS 1-2-3! Mash... Stir..."
        // without banning ingredient lines merely because they contain a verb.
        let clauses = normalized.components(
            separatedBy: CharacterSet(charactersIn: ".!?;:\n")
        )
        return clauses.contains { clause in
            var actionText = collapseWhitespace(clause)
            if let match = actionText.range(
                of: #"^\d{1,2}(?:[.)]|\s+-)?\s*"#,
                options: .regularExpression
            ) {
                actionText.removeSubrange(match)
            }
            if isInstructionHeading(actionText) { return true }
            return actions.contains { action in
                actionText == action || actionText.hasPrefix(action + " ")
            }
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
    var sourceObservationIDs: [String]

    var renderedText: String {
        guard let bulletMarker else { return text }
        return "\(bulletMarker) \(text)"
    }
}

private struct PhysicalLine {
    var text: String
    var bulletMarker: String?
    var pageIndex: Int
    var columnIndex: Int
    var sourceObservationIDs: [String]
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
    var averageHeight: Double
    var confidence: Double
    var reconstructionConfidence: Double
    var alternateCandidates: [OCRTextAlternative]
}

private struct LogicalLine {
    var text: String
    var bulletMarker: String?
    var pageIndex: Int
    var columnIndex: Int
    var sourceObservationIDs: [String]
    var continuationAttached: Bool
    var reconstructionConfidence: Double
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
    var averageHeight: Double
    var anchorMinX: Double
    var anchorMaxX: Double
    var anchorMinY: Double
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
            alternateCandidates: alternateCandidates,
            columnIndex: columnIndex,
            sourceObservationIDs: sourceObservationIDs,
            continuationAttached: continuationAttached,
            reconstructionConfidence: reconstructionConfidence
        )
    }
}

private struct BulletSegment {
    var text: String
    var marker: String
    var startRatio: Double
    var endRatio: Double
}

private struct ColumnDetection {
    var centers: [Double]
    var confidence: Double
    var ambiguities: Set<OCRLayoutAmbiguity>
}

private struct PageAnalysis {
    var suggestedTitle: String?
    var ingredientLines: [String]
    var ingredientSourceLines: [OCRSourceLine]
    var ignoredInstructionLines: [String]
    var columnCount: Int
    var confidence: Double
    var ambiguities: Set<OCRLayoutAmbiguity>
}
