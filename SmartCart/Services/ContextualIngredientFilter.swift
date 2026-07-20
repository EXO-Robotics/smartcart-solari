import Foundation

/// Source-aware ingredient filtering that preserves each upstream line and its evidence.
///
/// The adapter deliberately does not rebuild reading order, merge lines, truncate the
/// document, or parse shopping quantities. OCR layout remains the authority for line
/// order and geometry; this type only decides whether each discrete source line belongs
/// in the ingredient stream.
struct ContextualIngredientFilter {
    enum ClassifierVersion: String, Codable, Equatable, Sendable {
        case legacy
        case contextual
    }

    struct DocumentSource: Codable, Equatable, Sendable {
        enum Kind: String, Codable, CaseIterable, Sendable {
            /// A live camera capture. Geometry and observation provenance are required.
            case cameraPhoto
            /// A still image chosen from the photo library. Geometry is required.
            case photoLibrary
            /// A screenshot of a recipe surface. Geometry is required.
            case screenshot
            /// A scan whose lines may span pages. Page and geometry evidence are required.
            case multiPageScan
            /// Lines supplied by a URL extractor's ingredient container.
            case structuredURL
            /// Lines supplied by a Pinterest ingredient container.
            case pinterest
            /// Unstructured text pasted by the person using the app.
            case pastedText
            /// A source explicitly declared to be a grocery/ingredient list.
            case groceryList
            /// A source whose structure is not known.
            case unknown

            var requiresStrictSpatialEvidence: Bool {
                switch self {
                case .cameraPhoto, .photoLibrary, .screenshot, .multiPageScan:
                    true
                case .structuredURL, .pinterest, .pastedText, .groceryList, .unknown:
                    false
                }
            }

            var suppliesDeclaredIngredientRows: Bool {
                switch self {
                case .structuredURL, .pinterest, .groceryList:
                    true
                case .cameraPhoto, .photoLibrary, .screenshot, .multiPageScan, .pastedText, .unknown:
                    false
                }
            }
        }

        var kind: Kind
        var documentID: String?
        var detail: String?

        init(kind: Kind, documentID: String? = nil, detail: String? = nil) {
            self.kind = kind
            self.documentID = documentID
            self.detail = detail
        }
    }

    /// Evidence copied verbatim from the upstream layout/source adapter.
    struct LineEvidence: Codable, Equatable, Sendable {
        var pageIndex: Int?
        var columnIndex: Int?
        var sectionID: String?
        var sectionName: String?
        var boundingBox: OCRNormalizedBoundingBox?
        var sourceConfidence: Double?
        var sourceObservationIDs: [String]

        init(
            pageIndex: Int? = nil,
            columnIndex: Int? = nil,
            sectionID: String? = nil,
            sectionName: String? = nil,
            boundingBox: OCRNormalizedBoundingBox? = nil,
            sourceConfidence: Double? = nil,
            sourceObservationIDs: [String] = []
        ) {
            self.pageIndex = pageIndex
            self.columnIndex = columnIndex
            self.sectionID = sectionID
            self.sectionName = sectionName
            self.boundingBox = boundingBox
            self.sourceConfidence = sourceConfidence
            self.sourceObservationIDs = sourceObservationIDs
        }

        static let none = LineEvidence()

        init(
            ocrSourceLine: OCRSourceLine,
            sectionID: String? = nil,
            sectionName: String? = nil
        ) {
            self.init(
                pageIndex: ocrSourceLine.pageIndex,
                columnIndex: ocrSourceLine.columnIndex,
                sectionID: sectionID,
                sectionName: sectionName,
                boundingBox: ocrSourceLine.boundingBox,
                sourceConfidence: ocrSourceLine.reconstructionConfidence,
                sourceObservationIDs: ocrSourceLine.sourceObservationIDs
            )
        }
    }

    /// One indivisible line. `id`, `originalText`, order, and evidence are never rewritten.
    struct LineRecord: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var originalText: String
        var ordinal: Int
        var evidence: LineEvidence

        init(
            id: String,
            originalText: String,
            ordinal: Int,
            evidence: LineEvidence = .none
        ) {
            self.id = id
            self.originalText = originalText
            self.ordinal = ordinal
            self.evidence = evidence
        }

        init(
            id: String,
            ordinal: Int,
            ocrSourceLine: OCRSourceLine,
            sectionID: String? = nil,
            sectionName: String? = nil
        ) {
            self.init(
                id: id,
                originalText: ocrSourceLine.text,
                ordinal: ordinal,
                evidence: LineEvidence(
                    ocrSourceLine: ocrSourceLine,
                    sectionID: sectionID,
                    sectionName: sectionName
                )
            )
        }
    }

    enum EvidenceRole: String, Codable, Equatable, Sendable {
        case emptyBoundary
        case ingredientHeading
        case sectionHeading
        case instructionHeading
        case documentBoundary
        case strongIngredientCandidate
        case weakIngredientCandidate
        case continuationFragment
        case instruction
        case metadata
        case prose
        case noise
    }

    enum DocumentRole: String, Codable, Equatable, Sendable {
        case neutral
        case declaredIngredientList
        case ingredientRegion
        case instructionRegion
    }

    enum Disposition: String, Codable, Equatable, Sendable {
        case accepted
        case ignored
    }

    enum AcceptanceReason: String, Codable, Equatable, Sendable {
        case strongIngredientInSection
        case strongIngredientCluster
        case strongIngredientIndependentShape
        case strongIngredientWithMissingSpatialEvidence
        case boundedQuantitylessRescue
        case declaredUpstreamIngredientEvidence
        case declaredStructuredIngredient
        case declaredGroceryListItem
        case legacyShape
    }

    enum IgnoredReason: String, Codable, Equatable, Sendable {
        case emptyLine
        case ingredientHeading
        case sectionHeading
        case instructionHeading
        case documentBoundary
        case instructionVerb
        case ambiguousInstructionVerb
        case embeddedInstructionSentence
        case recipeMetadata
        case nutritionMetadata
        case decorativeNoise
        case nonFoodContext
        case proseSentence
        case continuationFragment
        case bareUnitOrPackage
        case quantityWithoutIngredientName
        case weakWithoutBoundedStrongNeighbor
        case isolatedStrongCandidate
        case instructionRegion
        case missingPageEvidence
        case missingColumnEvidence
        case missingGeometryEvidence
        case missingObservationEvidence
        case legacyRejected
    }

    enum ReviewReason: String, Codable, Equatable, Sendable {
        case leadingBulletNormalized
        case instructionSuffixRemoved
        case quantitylessContextRescue
        case sourceDeclaredIngredient
        case missingObservationProvenance
        case missingSpatialProvenance
        case lowSourceConfidence
        case ambiguousQuantityShape
    }

    struct LineDecision: Codable, Equatable, Sendable {
        var record: LineRecord
        /// Trimmed/bullet-normalized text used for classification. It can be a reviewed
        /// ingredient prefix only after a proven boundary; `removedSuffix` and the exact
        /// `record.originalText` make that sanitation explicit rather than silent.
        var sanitizedText: String
        /// Exact source suffix removed after a proven instruction boundary. The leading
        /// separator is excluded; all suffix content and trailing punctuation are retained.
        var removedSuffix: String? = nil
        var disposition: Disposition
        var evidenceRole: EvidenceRole
        var documentRole: DocumentRole
        var confidence: Double
        var acceptanceReason: AcceptanceReason?
        var ignoredReasons: [IgnoredReason]
        var reviewReasons: [ReviewReason]

        var lineID: String { record.id }
        var originalText: String { record.originalText }
        var evidence: LineEvidence { record.evidence }
    }

    struct AcceptedLine: Codable, Equatable, Sendable {
        var record: LineRecord
        var sanitizedText: String
        var removedSuffix: String?
        var reason: AcceptanceReason
        var confidence: Double
        var reviewReasons: [ReviewReason]

        var lineID: String { record.id }
        var originalText: String { record.originalText }
        var evidence: LineEvidence { record.evidence }
    }

    struct IgnoredLine: Codable, Equatable, Sendable {
        var record: LineRecord
        var sanitizedText: String
        var reasons: [IgnoredReason]
        var confidence: Double

        var lineID: String { record.id }
        var originalText: String { record.originalText }
        var evidence: LineEvidence { record.evidence }
    }

    struct FilterResult: Codable, Equatable, Sendable {
        var classifierVersion: ClassifierVersion
        var decisions: [LineDecision]
        var accepted: [AcceptedLine]
        var ignored: [IgnoredLine]

        init(classifierVersion: ClassifierVersion, decisions: [LineDecision]) {
            self.classifierVersion = classifierVersion
            self.decisions = decisions
            self.accepted = decisions.compactMap { decision in
                guard decision.disposition == .accepted,
                      let reason = decision.acceptanceReason
                else { return nil }
                return AcceptedLine(
                    record: decision.record,
                    sanitizedText: decision.sanitizedText,
                    removedSuffix: decision.removedSuffix,
                    reason: reason,
                    confidence: decision.confidence,
                    reviewReasons: decision.reviewReasons
                )
            }
            self.ignored = decisions.compactMap { decision in
                guard decision.disposition == .ignored else { return nil }
                return IgnoredLine(
                    record: decision.record,
                    sanitizedText: decision.sanitizedText,
                    reasons: decision.ignoredReasons,
                    confidence: decision.confidence
                )
            }
        }

        var acceptedLineIDs: [String] { accepted.map(\.lineID) }
    }

    struct Divergence: Codable, Equatable, Sendable {
        var lineID: String
        var originalText: String
        var legacyDisposition: Disposition
        var contextualDisposition: Disposition
        var legacyReason: AcceptanceReason?
        var contextualReason: AcceptanceReason?
        var contextualIgnoredReasons: [IgnoredReason]
    }

    struct DivergenceReport: Codable, Equatable, Sendable {
        var comparedLineCount: Int
        var agreementCount: Int
        var divergences: [Divergence]

        var acceptedOnlyByLegacy: [Divergence] {
            divergences.filter {
                $0.legacyDisposition == .accepted && $0.contextualDisposition == .ignored
            }
        }

        var acceptedOnlyByContextual: [Divergence] {
            divergences.filter {
                $0.legacyDisposition == .ignored && $0.contextualDisposition == .accepted
            }
        }
    }

    /// Legacy remains authoritative by default. Contextual classification is available
    /// only through an explicit engineering call for development comparison.
    static func filter(
        _ lines: [LineRecord],
        source: DocumentSource,
        using version: ClassifierVersion = .legacy
    ) -> FilterResult {
        switch version {
        case .legacy:
            legacyFilter(lines, source: source)
        case .contextual:
            contextualFilter(lines, source: source)
        }
    }

    static func developmentShadowReport(
        for lines: [LineRecord],
        source: DocumentSource
    ) -> DivergenceReport {
        let legacy = legacyFilter(lines, source: source)
        let contextual = contextualFilter(lines, source: source)
        let legacyByID = Dictionary(uniqueKeysWithValues: legacy.decisions.map { ($0.lineID, $0) })
        let contextualByID = Dictionary(uniqueKeysWithValues: contextual.decisions.map { ($0.lineID, $0) })
        let divergences = lines.compactMap { line -> Divergence? in
            guard let old = legacyByID[line.id], let new = contextualByID[line.id],
                  old.disposition != new.disposition
            else { return nil }
            return Divergence(
                lineID: line.id,
                originalText: line.originalText,
                legacyDisposition: old.disposition,
                contextualDisposition: new.disposition,
                legacyReason: old.acceptanceReason,
                contextualReason: new.acceptanceReason,
                contextualIgnoredReasons: new.ignoredReasons
            )
        }
        return DivergenceReport(
            comparedLineCount: lines.count,
            agreementCount: lines.count - divergences.count,
            divergences: divergences
        )
    }
}

// MARK: - Contextual classifier

private extension ContextualIngredientFilter {
    struct FirstPass {
        var record: LineRecord
        var sanitizedText: String
        var removedSuffix: String? = nil
        var role: EvidenceRole
        var confidence: Double
        var ignoredReasons: [IgnoredReason]
        var reviewReasons: [ReviewReason]
    }

    struct ContextFrame {
        var role: DocumentRole
        var sectionKey: String?
    }

    struct ContextAddress: Hashable {
        var pageIndex: Int?
        var columnIndex: Int?
        var sectionKey: String?
    }

    static let maximumNeighborDistance = 2

    static func contextualFilter(
        _ lines: [LineRecord],
        source: DocumentSource
    ) -> FilterResult {
        let firstPass = lines.map { assess($0, source: source) }
        let frames = contextualFrames(for: firstPass, source: source)
        let decisions = firstPass.indices.map { index in
            contextualDecision(
                at: index,
                firstPass: firstPass,
                frames: frames,
                source: source
            )
        }
        return FilterResult(classifierVersion: .contextual, decisions: decisions)
    }

    static func assess(_ record: LineRecord, source: DocumentSource) -> FirstPass {
        let originalTrimmed = record.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        var sanitized = normalizedBulletText(originalTrimmed)
        var reviewReasons: [ReviewReason] = []
        if sanitized != originalTrimmed {
            reviewReasons.append(.leadingBulletNormalized)
        }
        if let sourceConfidence = record.evidence.sourceConfidence, sourceConfidence < 0.72 {
            reviewReasons.append(.lowSourceConfidence)
        }
        if source.kind.requiresStrictSpatialEvidence,
           record.evidence.sourceObservationIDs.isEmpty {
            reviewReasons.append(.missingObservationProvenance)
        }
        if source.kind.requiresStrictSpatialEvidence,
           (record.evidence.pageIndex == nil
               || record.evidence.columnIndex == nil
               || record.evidence.boundingBox == nil) {
            reviewReasons.append(.missingSpatialProvenance)
        }

        guard !sanitized.isEmpty else {
            return FirstPass(
                record: record,
                sanitizedText: sanitized,
                role: .emptyBoundary,
                confidence: 1,
                ignoredReasons: [.emptyLine],
                reviewReasons: reviewReasons
            )
        }

        if isIngredientHeading(sanitized) {
            return ignoredAssessment(record, sanitized, .ingredientHeading, .ingredientHeading, reviewReasons)
        }
        if isInstructionHeading(sanitized) {
            return ignoredAssessment(record, sanitized, .instructionHeading, .instructionHeading, reviewReasons)
        }
        if isDocumentBoundaryHeading(sanitized) {
            return ignoredAssessment(record, sanitized, .documentBoundary, .documentBoundary, reviewReasons)
        }
        if isSectionHeading(sanitized) {
            return ignoredAssessment(record, sanitized, .sectionHeading, .sectionHeading, reviewReasons)
        }
        if isNonFoodContext(sanitized) {
            return ignoredAssessment(record, sanitized, .noise, .nonFoodContext, reviewReasons)
        }
        if looksLikeSourceTitle(sanitized, record: record, source: source) {
            return ignoredAssessment(record, sanitized, .noise, .decorativeNoise, reviewReasons)
        }
        var removedSuffix: String?
        if let split = embeddedInstructionSplit(in: sanitized) {
            if isReliableIngredientPrefix(split.prefix) {
                sanitized = split.prefix
                removedSuffix = split.removedSuffix
                reviewReasons.append(.instructionSuffixRemoved)
            } else {
                return ignoredAssessment(
                    record,
                    sanitized,
                    .instruction,
                    .embeddedInstructionSentence,
                    reviewReasons
                )
            }
        }
        if isDecorativeNoise(sanitized) {
            return ignoredAssessment(record, sanitized, .noise, .decorativeNoise, reviewReasons)
        }
        if isNutritionMetadata(sanitized) {
            return ignoredAssessment(record, sanitized, .metadata, .nutritionMetadata, reviewReasons)
        }
        if isRecipeMetadata(sanitized) {
            return ignoredAssessment(record, sanitized, .metadata, .recipeMetadata, reviewReasons)
        }
        if startsWithStrongInstruction(sanitized) {
            return ignoredAssessment(record, sanitized, .instruction, .instructionVerb, reviewReasons)
        }
        if startsWithAmbiguousInstruction(sanitized) {
            return ignoredAssessment(
                record,
                sanitized,
                .instruction,
                .ambiguousInstructionVerb,
                reviewReasons
            )
        }
        if looksLikeContinuationFragment(sanitized) {
            return ignoredAssessment(
                record,
                sanitized,
                .continuationFragment,
                .continuationFragment,
                reviewReasons
            )
        }

        let hasQuantity = hasLeadingQuantity(sanitized)
        let meaningfulNames = meaningfulNameTokens(in: sanitized)
        if hasQuantity && meaningfulNames.isEmpty {
            let reason: IgnoredReason = containsUnitOrPackage(sanitized)
                ? .bareUnitOrPackage
                : .quantityWithoutIngredientName
            return ignoredAssessment(record, sanitized, .noise, reason, reviewReasons)
        }
        if looksLikeProse(sanitized) {
            return ignoredAssessment(record, sanitized, .prose, .proseSentence, reviewReasons)
        }

        if hasQuantity || hasTrailingMeasuredQuantity(sanitized) {
            if usesAmbiguousQuantityShape(sanitized) {
                reviewReasons.append(.ambiguousQuantityShape)
            }
            return FirstPass(
                record: record,
                sanitizedText: sanitized,
                removedSuffix: removedSuffix,
                role: .strongIngredientCandidate,
                confidence: evidenceAdjustedConfidence(0.94, record: record),
                ignoredReasons: [],
                reviewReasons: reviewReasons
            )
        }

        if source.kind == .groceryList && isPlausibleConciseIngredient(sanitized, source: source) {
            reviewReasons.append(.sourceDeclaredIngredient)
            return FirstPass(
                record: record,
                sanitizedText: sanitized,
                removedSuffix: removedSuffix,
                role: .strongIngredientCandidate,
                confidence: evidenceAdjustedConfidence(0.91, record: record),
                ignoredReasons: [],
                reviewReasons: reviewReasons
            )
        }

        if isPlausibleConciseIngredient(sanitized, source: source) {
            return FirstPass(
                record: record,
                sanitizedText: sanitized,
                removedSuffix: removedSuffix,
                role: .weakIngredientCandidate,
                confidence: evidenceAdjustedConfidence(0.72, record: record),
                ignoredReasons: [],
                reviewReasons: reviewReasons
            )
        }

        return ignoredAssessment(record, sanitized, .prose, .proseSentence, reviewReasons)
    }

    static func ignoredAssessment(
        _ record: LineRecord,
        _ sanitizedText: String,
        _ role: EvidenceRole,
        _ reason: IgnoredReason,
        _ reviewReasons: [ReviewReason]
    ) -> FirstPass {
        FirstPass(
            record: record,
            sanitizedText: sanitizedText,
            role: role,
            confidence: evidenceAdjustedConfidence(0.98, record: record),
            ignoredReasons: [reason],
            reviewReasons: reviewReasons
        )
    }

    static func contextualFrames(
        for assessments: [FirstPass],
        source: DocumentSource
    ) -> [ContextFrame] {
        let baselineRole: DocumentRole = source.kind.suppliesDeclaredIngredientRows
            ? .declaredIngredientList
            : .neutral
        var states: [ContextAddress: ContextFrame] = [:]
        var frames: [ContextFrame] = []
        frames.reserveCapacity(assessments.count)

        for assessment in assessments {
            let address = contextAddress(for: assessment.record, source: source)
            var frame = states[address] ?? ContextFrame(role: baselineRole, sectionKey: nil)
            let hasIngredientEvidence = evidenceDeclaresIngredientRegion(
                assessment.record.evidence
            )
            let hasInstructionEvidence = evidenceDeclaresInstructionRegion(
                assessment.record.evidence
            )

            if hasIngredientEvidence {
                frame.role = .ingredientRegion
                frame.sectionKey = assessment.record.evidence.sectionID
                    ?? assessment.record.evidence.sectionName.map(headingKey)
            } else if hasInstructionEvidence {
                frame.role = .instructionRegion
                frame.sectionKey = nil
            }
            switch assessment.role {
            case .ingredientHeading:
                frame.role = .ingredientRegion
                frame.sectionKey = "ingredients"
            case .sectionHeading:
                // A generic label such as "Sauce" inside the method is method prose,
                // not permission to reopen ingredient rescue across that boundary.
                if frame.role != .instructionRegion {
                    frame.role = .ingredientRegion
                    frame.sectionKey = headingKey(assessment.sanitizedText)
                }
            case .instructionHeading, .documentBoundary:
                frame.role = .instructionRegion
                frame.sectionKey = nil
            case .instruction:
                // A method heading remains authoritative through its instruction
                // lines. A standalone imperative only closes the preceding rescue
                // segment, so a later independently measured row may still qualify.
                if frame.role != .instructionRegion {
                    frame.role = baselineRole
                    frame.sectionKey = nil
                }
            case .emptyBoundary, .metadata, .prose, .noise:
                // These are hard rescue boundaries. A later measured line can still
                // stand on its own, while a weak line must earn fresh local context.
                // Explicit upstream section evidence is reconsidered on every record.
                frame.role = baselineRole
                frame.sectionKey = nil
            case .strongIngredientCandidate, .weakIngredientCandidate,
                    .continuationFragment:
                break
            }
            states[address] = frame
            frames.append(frame)
        }
        return frames
    }

    static func contextAddress(
        for record: LineRecord,
        source: DocumentSource
    ) -> ContextAddress {
        let evidenceSection = record.evidence.sectionID
            ?? record.evidence.sectionName.map(headingKey)
        if source.kind.requiresStrictSpatialEvidence {
            return ContextAddress(
                pageIndex: record.evidence.pageIndex,
                columnIndex: record.evidence.columnIndex,
                sectionKey: evidenceSection
            )
        }
        return ContextAddress(
            pageIndex: record.evidence.pageIndex,
            columnIndex: record.evidence.columnIndex,
            sectionKey: evidenceSection
        )
    }

    static func evidenceDeclaresIngredientRegion(_ evidence: LineEvidence) -> Bool {
        if let sectionName = evidence.sectionName, isIngredientHeading(sectionName) {
            return true
        }
        if let sectionID = evidence.sectionID,
           folded(sectionID).contains("ingredient") {
            return true
        }
        return false
    }

    static func evidenceDeclaresInstructionRegion(_ evidence: LineEvidence) -> Bool {
        guard let sectionName = evidence.sectionName else { return false }
        return isInstructionHeading(sectionName) || isDocumentBoundaryHeading(sectionName)
    }

    static func contextualDecision(
        at index: Int,
        firstPass: [FirstPass],
        frames: [ContextFrame],
        source: DocumentSource
    ) -> LineDecision {
        let assessment = firstPass[index]
        let frame = frames[index]

        switch assessment.role {
        case .strongIngredientCandidate, .weakIngredientCandidate:
            break
        case .emptyBoundary, .ingredientHeading, .sectionHeading, .instructionHeading,
                .documentBoundary, .continuationFragment, .instruction, .metadata, .prose, .noise:
            return ignoredDecision(assessment, frame: frame)
        }

        if frame.role == .instructionRegion {
            return ignoredDecision(assessment, frame: frame, reasons: [.instructionRegion])
        }

        let missingEvidence = strictEvidenceFailures(for: assessment.record, source: source)
        if assessment.role == .weakIngredientCandidate && !missingEvidence.isEmpty {
            return ignoredDecision(assessment, frame: frame, reasons: missingEvidence)
        }

        if assessment.role == .strongIngredientCandidate {
            if source.kind.requiresStrictSpatialEvidence && !missingEvidence.isEmpty {
                return acceptedDecision(
                    assessment,
                    frame: frame,
                    reason: .strongIngredientWithMissingSpatialEvidence,
                    confidence: 0.78
                )
            }
            if frame.role == .ingredientRegion {
                return acceptedDecision(
                    assessment,
                    frame: frame,
                    reason: .strongIngredientInSection,
                    confidence: 0.97
                )
            }
            if source.kind == .groceryList,
               hasLeadingQuantity(assessment.sanitizedText)
                    || hasTrailingMeasuredQuantity(assessment.sanitizedText) {
                return acceptedDecision(
                    assessment,
                    frame: frame,
                    reason: .declaredGroceryListItem,
                    confidence: 0.96
                )
            }
            guard isCredibleIndependentStrong(assessment.sanitizedText) else {
                return ignoredDecision(assessment, frame: frame, reasons: [.isolatedStrongCandidate])
            }
            if source.kind == .groceryList {
                return acceptedDecision(
                    assessment,
                    frame: frame,
                    reason: .declaredGroceryListItem,
                    confidence: 0.96
                )
            }
            if source.kind == .structuredURL || source.kind == .pinterest {
                return acceptedDecision(
                    assessment,
                    frame: frame,
                    reason: .declaredStructuredIngredient,
                    confidence: 0.97
                )
            }
            return acceptedDecision(
                assessment,
                frame: frame,
                reason: .strongIngredientIndependentShape,
                confidence: 0.92
            )
        }

        if source.kind.requiresStrictSpatialEvidence,
           evidenceDeclaresIngredientRegion(assessment.record.evidence) {
            var reasons = assessment.reviewReasons
            appendUnique(.sourceDeclaredIngredient, to: &reasons)
            return acceptedDecision(
                assessment,
                frame: frame,
                reason: .declaredUpstreamIngredientEvidence,
                confidence: 0.86,
                reviewReasons: reasons
            )
        }
        if frame.role == .ingredientRegion {
            var reasons = assessment.reviewReasons
            appendUnique(.quantitylessContextRescue, to: &reasons)
            return acceptedDecision(
                assessment,
                frame: frame,
                reason: .boundedQuantitylessRescue,
                confidence: 0.84,
                reviewReasons: reasons
            )
        }
        if (source.kind == .structuredURL || source.kind == .pinterest)
            && containsKnownFood(assessment.sanitizedText) {
            var reasons = assessment.reviewReasons
            appendUnique(.sourceDeclaredIngredient, to: &reasons)
            return acceptedDecision(
                assessment,
                frame: frame,
                reason: .declaredStructuredIngredient,
                confidence: 0.88,
                reviewReasons: reasons
            )
        }
        if containsKnownFood(assessment.sanitizedText) && hasIndependentStrongNeighbor(
            at: index,
            firstPass: firstPass,
            frames: frames,
            source: source
        ) || (frame.role == .ingredientRegion && hasPlausibleWeakNeighbor(
            at: index,
            firstPass: firstPass,
            frames: frames,
            source: source
        )) {
            var reasons = assessment.reviewReasons
            appendUnique(.quantitylessContextRescue, to: &reasons)
            return acceptedDecision(
                assessment,
                frame: frame,
                reason: .boundedQuantitylessRescue,
                confidence: frame.role == .ingredientRegion ? 0.88 : 0.82,
                reviewReasons: reasons
            )
        }
        return ignoredDecision(
            assessment,
            frame: frame,
            reasons: [.weakWithoutBoundedStrongNeighbor]
        )
    }

    static func acceptedDecision(
        _ assessment: FirstPass,
        frame: ContextFrame,
        reason: AcceptanceReason,
        confidence: Double,
        reviewReasons: [ReviewReason]? = nil
    ) -> LineDecision {
        LineDecision(
            record: assessment.record,
            sanitizedText: assessment.sanitizedText,
            removedSuffix: assessment.removedSuffix,
            disposition: .accepted,
            evidenceRole: assessment.role,
            documentRole: frame.role,
            confidence: evidenceAdjustedConfidence(confidence, record: assessment.record),
            acceptanceReason: reason,
            ignoredReasons: [],
            reviewReasons: reviewReasons ?? assessment.reviewReasons
        )
    }

    static func ignoredDecision(
        _ assessment: FirstPass,
        frame: ContextFrame,
        reasons: [IgnoredReason]? = nil
    ) -> LineDecision {
        LineDecision(
            record: assessment.record,
            sanitizedText: assessment.sanitizedText,
            removedSuffix: assessment.removedSuffix,
            disposition: .ignored,
            evidenceRole: assessment.role,
            documentRole: frame.role,
            confidence: assessment.confidence,
            acceptanceReason: nil,
            ignoredReasons: reasons ?? assessment.ignoredReasons,
            reviewReasons: assessment.reviewReasons
        )
    }

    static func hasIndependentStrongNeighbor(
        at index: Int,
        firstPass: [FirstPass],
        frames: [ContextFrame],
        source: DocumentSource
    ) -> Bool {
        guard strictEvidenceFailures(
            for: firstPass[index].record,
            source: source,
            requireObservationIDs: true
        ).isEmpty else { return false }
        let lower = max(0, index - maximumNeighborDistance)
        let upper = min(firstPass.count - 1, index + maximumNeighborDistance)
        guard lower <= upper else { return false }

        for neighborIndex in lower...upper where neighborIndex != index {
            guard firstPass[neighborIndex].role == .strongIngredientCandidate,
                  frames[neighborIndex].role != .instructionRegion,
                  strictEvidenceFailures(
                      for: firstPass[neighborIndex].record,
                      source: source,
                      requireObservationIDs: true
                  ).isEmpty,
                  !hasHardBoundary(
                      between: index,
                      and: neighborIndex,
                      firstPass: firstPass
                  ),
                  sharesContext(
                      firstPass[index].record,
                      firstPass[neighborIndex].record,
                      lhsFrame: frames[index],
                      rhsFrame: frames[neighborIndex],
                      source: source
                  )
            else { continue }
            return true
        }
        return false
    }

    static func hasPlausibleWeakNeighbor(
        at index: Int,
        firstPass: [FirstPass],
        frames: [ContextFrame],
        source: DocumentSource
    ) -> Bool {
        guard strictEvidenceFailures(
            for: firstPass[index].record,
            source: source,
            requireObservationIDs: true
        ).isEmpty else { return false }
        let lower = max(0, index - maximumNeighborDistance)
        let upper = min(firstPass.count - 1, index + maximumNeighborDistance)
        guard lower <= upper else { return false }

        for neighborIndex in lower...upper where neighborIndex != index {
            guard firstPass[neighborIndex].role == .weakIngredientCandidate,
                  frames[neighborIndex].role != .instructionRegion,
                  strictEvidenceFailures(
                      for: firstPass[neighborIndex].record,
                      source: source,
                      requireObservationIDs: true
                  ).isEmpty,
                  !hasHardBoundary(between: index, and: neighborIndex, firstPass: firstPass),
                  sharesContext(
                      firstPass[index].record,
                      firstPass[neighborIndex].record,
                      lhsFrame: frames[index],
                      rhsFrame: frames[neighborIndex],
                      source: source
                  )
            else { continue }
            return true
        }
        return false
    }

    static func hasHardBoundary(
        between lhs: Int,
        and rhs: Int,
        firstPass: [FirstPass]
    ) -> Bool {
        let lower = min(lhs, rhs) + 1
        let upper = max(lhs, rhs)
        guard lower < upper else { return false }
        return firstPass[lower..<upper].contains { assessment in
            switch assessment.role {
            case .emptyBoundary, .ingredientHeading, .sectionHeading, .instructionHeading,
                    .documentBoundary, .instruction, .metadata:
                true
            case .strongIngredientCandidate, .weakIngredientCandidate, .continuationFragment:
                false
            case .prose, .noise:
                true
            }
        }
    }

    static func sharesContext(
        _ lhs: LineRecord,
        _ rhs: LineRecord,
        lhsFrame: ContextFrame,
        rhsFrame: ContextFrame,
        source: DocumentSource
    ) -> Bool {
        if let lhsPage = lhs.evidence.pageIndex, let rhsPage = rhs.evidence.pageIndex,
           lhsPage != rhsPage {
            return false
        }
        if let lhsColumn = lhs.evidence.columnIndex, let rhsColumn = rhs.evidence.columnIndex,
           lhsColumn != rhsColumn {
            return false
        }

        let lhsEvidenceSection = lhs.evidence.sectionID
        let rhsEvidenceSection = rhs.evidence.sectionID
        if lhsEvidenceSection != nil || rhsEvidenceSection != nil {
            guard lhsEvidenceSection == rhsEvidenceSection else { return false }
        } else if lhsFrame.sectionKey != rhsFrame.sectionKey {
            return false
        }

        guard source.kind.requiresStrictSpatialEvidence else { return true }
        guard let lhsBox = lhs.evidence.boundingBox,
              let rhsBox = rhs.evidence.boundingBox
        else { return false }
        let verticalDistance = abs(lhsBox.midY - rhsBox.midY)
        let localLineHeight = max(lhsBox.height, rhsBox.height)
        let maximumVerticalDistance = max(0.08, (localLineHeight * 3.2) + 0.025)
        return verticalDistance <= maximumVerticalDistance
    }

    static func strictEvidenceFailures(
        for record: LineRecord,
        source: DocumentSource,
        requireObservationIDs: Bool = false
    ) -> [IgnoredReason] {
        guard source.kind.requiresStrictSpatialEvidence else { return [] }
        var reasons: [IgnoredReason] = []
        if record.evidence.pageIndex == nil { reasons.append(.missingPageEvidence) }
        if record.evidence.columnIndex == nil { reasons.append(.missingColumnEvidence) }
        if record.evidence.boundingBox == nil { reasons.append(.missingGeometryEvidence) }
        if requireObservationIDs && record.evidence.sourceObservationIDs.isEmpty {
            reasons.append(.missingObservationEvidence)
        }
        return reasons
    }
}

// MARK: - Legacy comparison classifier

private extension ContextualIngredientFilter {
    static func legacyFilter(
        _ lines: [LineRecord],
        source: DocumentSource
    ) -> FilterResult {
        var insideIngredientSection = false
        var insideInstructionSection = false
        var decisions: [LineDecision] = []
        decisions.reserveCapacity(lines.count)

        for line in lines {
            let sanitized = normalizedBulletText(
                line.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let role: DocumentRole
            if isIngredientHeading(sanitized) {
                insideIngredientSection = true
                insideInstructionSection = false
                role = .ingredientRegion
                decisions.append(legacyIgnored(line, sanitized, .ingredientHeading, role, .ingredientHeading))
                continue
            }
            if isSectionHeading(sanitized) {
                insideIngredientSection = true
                insideInstructionSection = false
                role = .ingredientRegion
                decisions.append(legacyIgnored(line, sanitized, .sectionHeading, role, .sectionHeading))
                continue
            }
            if isInstructionHeading(sanitized) || isDocumentBoundaryHeading(sanitized) {
                insideInstructionSection = true
                role = .instructionRegion
                let evidenceRole: EvidenceRole = isInstructionHeading(sanitized)
                    ? .instructionHeading
                    : .documentBoundary
                let reason: IgnoredReason = isInstructionHeading(sanitized)
                    ? .instructionHeading
                    : .documentBoundary
                decisions.append(legacyIgnored(line, sanitized, evidenceRole, role, reason))
                continue
            }

            role = insideInstructionSection
                ? .instructionRegion
                : (insideIngredientSection ? .ingredientRegion : .neutral)
            guard !sanitized.isEmpty, !insideInstructionSection else {
                decisions.append(
                    legacyIgnored(
                        line,
                        sanitized,
                        sanitized.isEmpty ? .emptyBoundary : .instruction,
                        role,
                        sanitized.isEmpty ? .emptyLine : .instructionRegion
                    )
                )
                continue
            }
            guard !legacyInstruction(sanitized), !legacyMetadata(sanitized) else {
                decisions.append(legacyIgnored(line, sanitized, .instruction, role, .legacyRejected))
                continue
            }

            let contextAllowsQuantityless = insideIngredientSection
                || source.kind.suppliesDeclaredIngredientRows
                || (source.kind.requiresStrictSpatialEvidence && !line.evidence.sourceObservationIDs.isEmpty)
            if legacyLooksLikeIngredient(sanitized, contextAllowsQuantityless: contextAllowsQuantityless) {
                decisions.append(
                    LineDecision(
                        record: line,
                        sanitizedText: sanitized,
                        disposition: .accepted,
                        evidenceRole: hasLeadingQuantity(sanitized)
                            ? .strongIngredientCandidate
                            : .weakIngredientCandidate,
                        documentRole: role,
                        confidence: evidenceAdjustedConfidence(0.68, record: line),
                        acceptanceReason: .legacyShape,
                        ignoredReasons: [],
                        reviewReasons: []
                    )
                )
            } else {
                decisions.append(legacyIgnored(line, sanitized, .prose, role, .legacyRejected))
            }
        }
        return FilterResult(classifierVersion: .legacy, decisions: decisions)
    }

    static func legacyIgnored(
        _ record: LineRecord,
        _ sanitizedText: String,
        _ evidenceRole: EvidenceRole,
        _ documentRole: DocumentRole,
        _ reason: IgnoredReason
    ) -> LineDecision {
        LineDecision(
            record: record,
            sanitizedText: sanitizedText,
            disposition: .ignored,
            evidenceRole: evidenceRole,
            documentRole: documentRole,
            confidence: 0.65,
            acceptanceReason: nil,
            ignoredReasons: [reason],
            reviewReasons: []
        )
    }

    static func legacyLooksLikeIngredient(
        _ line: String,
        contextAllowsQuantityless: Bool
    ) -> Bool {
        if matches(
            line,
            #"^\s*(?:about\s+|approximately\s+|~\s*)?(?:\d|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|a\b|an\b|one\b|two\b|three\b|four\b|five\b|six\b|seven\b|eight\b|nine\b|ten\b|half\b|quarter\b)"#
        ) {
            return true
        }
        if containsUnitOrPackage(line) || containsKnownFood(line) { return true }
        guard contextAllowsQuantityless else { return false }
        let wordCount = wordTokens(line).count
        return (1...14).contains(wordCount) && !line.hasSuffix(".")
    }

    static func legacyInstruction(_ line: String) -> Bool {
        matches(
            headingKey(line),
            #"^(?:preheat|heat|mix|stir|whisk|combine|add|bake|cook|simmer|boil|roast|grill|fold|beat|place|transfer|spread|pour|arrange|season|chill|refrigerate|freeze|serve|let|set|line|grease|melt|bring)\b"#
        )
    }

    static func legacyMetadata(_ line: String) -> Bool {
        let key = headingKey(line)
        return matches(
            key,
            #"^(?:prep|preparation|cook|bake|total)\s+time\b|^(?:serves|servings|yield|makes|calories)\b|^\d+\s*°\s*[fc]\b"#
        )
    }
}

// MARK: - Lexical and shape signals

private extension ContextualIngredientFilter {
    static let strongVerbPattern = "add|arrange|bake|beat|boil|bring|broil|chop|combine|cook|cool|cover|cut|discard|drain|fold|freeze|fry|grease|grill|heat|knead|line|marinate|mash|melt|microwave|mix|peel|place|pour|preheat|refrigerate|remove|reserve|rinse|roast|saute|sauté|serve|simmer|soak|spread|sprinkle|stir|toss|transfer|uncover|whisk"

    static let foodWords: Set<String> = [
        "almond", "almonds", "apple", "apples", "arroz", "avena", "avocado",
        "banana", "bananas",
        "basil", "beans", "beef", "berries", "berry", "bread", "breadcrumbs",
        "broth", "butter", "cacao", "carne", "carrot", "carrots", "cayenne",
        "celery", "cheese", "chicken", "chili", "chives", "chocolate", "cilantro",
        "cinnamon", "cocoa", "coconut", "corn", "cream", "cucumber", "cumin",
        "dill", "egg", "eggs", "espinaca", "farine", "fish", "flour", "frijoles",
        "garlic", "ginger", "harina", "honey", "huevo", "huevos", "huile", "juice",
        "kale", "lait", "leche", "lemon", "lentils", "lettuce", "levadura", "lime",
        "limon", "mantequilla", "mayonnaise", "milk", "mint", "mushroom", "mushrooms",
        "mustard", "noodles", "nutmeg", "oats", "oeuf", "oeufs", "oil", "onion",
        "onions", "orange", "oregano", "paprika", "parmesan", "parsley", "pasta", "peas", "pecans",
        "pepper", "pimienta", "pollo", "pork", "potato", "potatoes", "powder", "queso",
        "quinoa", "rice", "rosemary", "sal", "salmon", "salt", "scallions", "sesame",
        "shrimp", "spinach", "stock", "strawberries", "strawberry", "sucre", "sugar",
        "syrup", "thyme", "tomate", "tomates", "tomato", "tomatoes", "tortillas",
        "tuna", "turmeric", "vainilla", "vanilla", "vinegar", "walnuts", "water", "yeast",
        "yogur", "yogurt", "zanahoria", "zest", "azucar", "eau", "beurre", "sel", "poivre"
    ]

    static let unitAndPackageWords: Set<String> = [
        "bag", "bags", "bottle", "bottles", "box", "boxes", "bunch", "bunches",
        "can", "cans", "clove", "cloves", "container", "containers", "cup", "cups",
        "dash", "dashes", "dozen", "drop", "drops", "g", "gallon", "gallons", "gram",
        "grams", "jar", "jars", "kg", "kilogram", "kilograms", "l", "lb", "lbs", "link",
        "links", "liter", "liters", "litre", "litres", "ml", "ounce", "ounces", "oz",
        "package", "packages", "packet", "packets", "piece", "pieces", "pinch", "pinches",
        "pint", "pints", "pound", "pounds", "quart", "quarts", "slice", "slices", "tbsp",
        "tablespoon", "tablespoons", "taza", "tazas", "teaspoon", "teaspoons", "tsp",
        "cucharada", "cucharadas", "cucharadita", "cucharaditas"
    ]

    static let nonNameWords: Set<String> = unitAndPackageWords.union([
        "a", "about", "an", "and", "approximately", "as", "at", "brown", "chopped",
        "cold", "diced", "divided", "finely", "for", "fresh", "freshly", "frozen", "half",
        "large", "medium", "melted", "minced", "more", "of", "one", "optional", "or",
        "packed", "peeled", "quarter", "ripe", "room", "sifted", "small", "softened",
        "taste", "temperature", "the", "to", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "warm", "whole"
    ])

    static func normalizedBulletText(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*[-•*☐✓▪◦]\s*"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func headingKey(_ text: String) -> String {
        folded(text)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    static func folded(_ text: String) -> String {
        text.lowercased().folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func isIngredientHeading(_ line: String) -> Bool {
        let key = headingKey(line)
        if [
            "ingredient", "ingredients", "what you need", "you will need",
            "ingredientes", "ingredienti", "ingredientes ingredients", "ingredients ingredientes"
        ].contains(key) {
            return true
        }
        let words = key.split(separator: " ")
        return words.count <= 3
            && key.hasSuffix(" ingredients")
            && !key.hasPrefix("other ")
    }

    static func isInstructionHeading(_ line: String) -> Bool {
        let key = headingKey(line)
        return [
            "directions", "instructions", "method", "steps", "preparation", "how to make",
            "direcciones", "instrucciones", "metodo"
        ].contains(key)
            || key.hasPrefix("directions ")
            || key.hasPrefix("instructions ")
    }

    static func isDocumentBoundaryHeading(_ line: String) -> Bool {
        let key = headingKey(line)
        return [
            "notes", "recipe notes", "tips", "storage", "nutrition", "nutrition facts",
            "serving suggestions", "about this recipe", "equipment", "tools",
            "care instructions", "notas", "conservacion"
        ].contains(key)
    }

    static func isSectionHeading(_ line: String) -> Bool {
        let key = headingKey(line)
        let exact = [
            "cake", "dough", "dressing", "filling", "frosting", "garnish", "marinade",
            "sauce", "syrup", "topping", "dry ingredients", "wet ingredients"
        ]
        if exact.contains(key) { return true }
        if key == "for topping" || key == "for the topping" { return false }
        return matches(
            key,
            #"^for (?:the )?(?:cake|dough|dressing|filling|frosting|garnish|marinade|sauce|syrup)$"#
        )
    }

    static func isDecorativeNoise(_ line: String) -> Bool {
        let value = folded(line)
        return matches(value, #"(?:https?://|www\.|\b[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\b)"#)
            || matches(value, #"^@[a-z0-9_.]+$"#)
            || matches(value, #"^(?:save|pin it|print|share|subscribe|sign up|advertisement|sponsored|tap|click|shop|visit profile|related ideas|read the full|get the full|view recipe)\b"#)
            || matches(value, #"^(?:author:|by\s+|pin:|recipe:|rating:|review:)"#)
            || value.contains("›")
            || matches(value, #"(?:©|copyright|all rights reserved)"#)
            || matches(value, #"^\d(?:\.\d)?\s*(?:/\s*5\s*)?(?:stars?|ratings?|reviews?)\b"#)
            || matches(value, #"\beasy as\s+\d+(?:\s*[-–—]\s*\d+)+\b"#)
    }

    static func isNutritionMetadata(_ line: String) -> Bool {
        let value = folded(line)
        return matches(
            value,
            #"^(?:calories?|protein|carbohydrates?|carbs?|fat|saturated fat|fiber|fibre|sodium|cholesterol|sugars?)\s*:?[ \t]*\d+(?:[.,]\d+)?\s*(?:kcal|g|mg|%)?\b"#
        ) || matches(value, #"^\d+(?:[.,]\d+)?\s*(?:kcal|mg|g)\s+per serving\b"#)
    }

    static func isRecipeMetadata(_ line: String) -> Bool {
        let value = folded(line)
        return matches(
            value,
            #"^(?:prep|preparation|cook|cooking|bake|total|active|rest)\s*(?:time)?\s*:?\s*\d"#
        ) || matches(value, #"^(?:serves|servings|yield|makes)\s*:?\s*\d"#)
            || matches(value, #"^\d+(?:\s*[-–—]\s*\d+)?\s*(?:seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?)\b"#)
            || matches(value, #"^\d+\s*°\s*[fc]\b"#)
            || matches(value, #"^\d+\s+(?:ways|reasons|tips|steps|things)\b"#)
            || matches(value, #"^(?:day|week)\s+\d+\b"#)
            || matches(value, #"^per\s+(?:day|week|serving)\b"#)
            || matches(value, #"^\d+(?:[.,]\d+)?\s*(?:g|mg|kcal)\s*$"#)
            || matches(value, #"^\d{1,2}:\d{2}\b"#)
            || matches(value, #"^\d+\s+(?:sets?|reps?|rounds?)\b"#)
    }

    static func isNonFoodContext(_ line: String) -> Bool {
        let value = folded(line)
        return matches(
            value,
            #"\b(?:agarose|batter(?:y|ies)|bolts?|brackets?|cabinets?|capsules?|cellulose|centrifuge|dietary supplement|electrophoresis|epoxy|laboratory|lunges|moisturizer|nails?|paint\s*brush(?:es)?|paint|primer|reagents?|screws?|serum|silica|skincare|solvents?|varnish|washers?|wood filler|wood stain|workout|itinerary|appointment|county|meeting)\b"#
        ) || matches(value, #"\bbetween\s+(?:rounds?|sets?|reps?)\b"#)
            || matches(value, #"\b(?:electrophoresis|laboratory)\s+buffer\b|^buffer\s+preparation\b"#)
            || matches(value, #"\b\d+\s+(?:sets?|reps?|rounds?)\s+(?:of\s+)?\d+\b"#)
    }

    static func looksLikeSourceTitle(
        _ line: String,
        record: LineRecord,
        source: DocumentSource
    ) -> Bool {
        let quantityIsTitleCompound = matches(
            folded(line),
            #"^(?:one|two|three|four|five|six|seven|eight|nine|ten)-[[:alpha:]]"#
        )
        guard (!hasLeadingQuantity(line) || quantityIsTitleCompound),
              !evidenceDeclaresIngredientRegion(record.evidence)
        else { return false }

        let value = folded(line)
        if matches(value, #"^(?:author:|by\s+|pin:|recipe:|rating:|review:)"#)
            || value.contains("›") {
            return true
        }

        guard source.kind != .groceryList,
              record.ordinal == 0
        else { return false }
        let words = line.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard (2...9).contains(words.count) else { return false }

        let insignificant = Set(["a", "an", "and", "for", "in", "of", "the", "to", "with"])
        let significantWords = words.filter { !insignificant.contains(folded($0)) }
        let minimumSignificantWords = source.kind == .structuredURL || source.kind == .pinterest
            ? 2
            : 3
        guard significantWords.count >= minimumSignificantWords else { return false }
        return significantWords.allSatisfy { word in
            word.unicodeScalars.first.map { CharacterSet.uppercaseLetters.contains($0) } == true
        }
    }

    struct EmbeddedInstructionSplit {
        var prefix: String
        var removedSuffix: String
    }

    static func embeddedInstructionSplit(in line: String) -> EmbeddedInstructionSplit? {
        let pattern = #"[,.!?;:]\s*(?:(?:and\s+)?then\s+)?(?:(?:step\s+)?\d{1,2}\s*[:.)-]?\s*)?(?:"#
            + strongVerbPattern
            + #")\b"#
        guard let range = line.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }

        var prefixEnd = range.lowerBound
        let textBeforeInstruction = line[..<range.lowerBound]
        if let banner = textBeforeInstruction.range(
            of: #",\s*easy\s+as\s+\d+(?:\s*[-–—]\s*\d+)+\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            prefixEnd = banner.lowerBound
        }

        let prefix = line[..<prefixEnd]
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?"))
        let boundaryCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",.;:!?"))
        let suffixSlice = line[prefixEnd...]
        let suffixStart = suffixSlice.firstIndex { character in
            character.unicodeScalars.contains { !boundaryCharacters.contains($0) }
        } ?? line.endIndex
        let removedSuffix = String(line[suffixStart...])
        guard !removedSuffix.isEmpty else { return nil }
        return EmbeddedInstructionSplit(prefix: prefix, removedSuffix: removedSuffix)
    }

    static func isReliableIngredientPrefix(_ prefix: String) -> Bool {
        guard !prefix.isEmpty,
              !meaningfulNameTokens(in: prefix).isEmpty,
              !looksLikeProse(prefix),
              !startsWithStrongInstruction(prefix),
              !startsWithAmbiguousInstruction(prefix)
        else { return false }
        return hasLeadingQuantity(prefix)
            || hasTrailingMeasuredQuantity(prefix)
            || containsKnownFood(prefix)
    }

    static func startsWithStrongInstruction(_ line: String) -> Bool {
        matches(
            folded(line),
            #"^(?:(?:step\s+)?\d{1,2}\s*[:.)-]?\s*)?(?:"#
                + strongVerbPattern
                + #")\b(?:\s|$)"#
        )
    }

    static func startsWithAmbiguousInstruction(_ line: String) -> Bool {
        let value = folded(line)
        let prefix = #"^(?:(?:step\s+)?\d{1,2}\s*[:.)-]?\s*)?"#
        return matches(value, prefix + #"brown\s+(?:the|until|for)\b"#)
            || matches(value, prefix + #"blend\s+(?:the|with|together|until)\b"#)
            || matches(value, prefix + #"slice\s+(?:the|into|through)\b"#)
            || matches(value, prefix + #"cream\s+(?:the|together|until)\b"#)
            || matches(value, prefix + #"top\s+(?:the|with)\b"#)
            || matches(value, prefix + #"toast\s+(?:the|until|for)\b"#)
            || matches(value, prefix + #"juice\s+the\b"#)
            || matches(value, prefix + #"oil\s+the\b"#)
            || matches(value, prefix + #"salt\s+the\b"#)
            || matches(value, prefix + #"pepper\s+the\b"#)
            || matches(value, prefix + #"season\s+(?:the|with)\b"#)
            || matches(value, prefix + #"chill\s+(?:for|until|the)\b"#)
            || matches(value, prefix + #"roll\s+(?:the|into|until)\b"#)
    }

    static func looksLikeContinuationFragment(_ line: String) -> Bool {
        let value = folded(line)
        if matches(value, #"^\([^)]*\)\s*$"#) { return true }
        if matches(value, #"^(?:plus more|divided|at room temperature|for serving|for garnish|for (?:the )?topping)\b"#) {
            return true
        }
        let tokens = meaningfulNameTokens(in: line)
        return tokens.isEmpty
            && !hasLeadingQuantity(line)
            && matches(value, #"^(?:finely|freshly|roughly|thinly|coarsely)\b"#)
    }

    static func looksLikeProse(_ line: String) -> Bool {
        let value = folded(line)
        let wordCount = wordTokens(line).count
        if wordCount > 18 { return true }
        if matches(value, #"[!?]"#) { return true }
        if matches(value, #"[.!?]\s+[[:alpha:]]"#) { return true }
        if line.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(".") && wordCount > 6 {
            return true
        }
        return matches(
            value,
            #"\b(?:we|you|your|our|this|that|these|those)\b"#
        ) || matches(
            value,
            #"\b(?:until|then|in every|perfect for|delicious|favorite|enjoy|recipe of the day)\b"#
        )
    }

    static func hasLeadingQuantity(_ line: String) -> Bool {
        matches(
            folded(line),
            #"^(?:about\s+|approximately\s+|approx\.?\s+|~\s*)?(?:(?:\d+(?:[.,]\d+)?(?:\s+\d+/\d+)?|\d+/\d+|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚])(?:\s*[-–—]\s*(?:\d+(?:[.,]\d+)?|\d+/\d+|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]))?|(?:one|two|three|four|five|six|seven|eight|nine|ten|half|quarter)\b)"#
        )
    }

    static func usesAmbiguousQuantityShape(_ line: String) -> Bool {
        matches(folded(line), #"^[il1]/\d\b"#)
            || matches(folded(line), #"^\d+[.,]\d+\b"#)
    }

    static func hasTrailingMeasuredQuantity(_ line: String) -> Bool {
        matches(
            folded(line),
            #"\b\d+(?:[.,]\d+)?\s*(?:cups?|tbsp|tablespoons?|tsp|teaspoons?|oz|ounces?|lbs?|pounds?|g|grams?|kg|ml|liters?|litres?)\s*$"#
        ) && !meaningfulNameTokens(in: line).isEmpty
    }

    static func containsUnitOrPackage(_ line: String) -> Bool {
        !Set(wordTokens(line)).isDisjoint(with: unitAndPackageWords)
    }

    static func containsKnownFood(_ line: String) -> Bool {
        !Set(wordTokens(line)).isDisjoint(with: foodWords)
    }

    static func isCredibleIndependentStrong(_ line: String) -> Bool {
        containsUnitOrPackage(line) || containsKnownFood(line) || looksLikeCompoundMeasuredList(line)
    }

    static func looksLikeCompoundMeasuredList(_ line: String) -> Bool {
        guard matches(line, #"[,;+]\s*(?:\d|[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚])"#) else { return false }
        let numbers = wordTokens(line).filter { token in
            token.range(of: #"^\d"#, options: .regularExpression) != nil
        }
        return numbers.count >= 2 && containsUnitOrPackage(line)
    }

    static func isPlausibleConciseIngredient(_ line: String, source: DocumentSource) -> Bool {
        let words = wordTokens(line)
        guard (1...8).contains(words.count), !looksLikeProse(line) else { return false }
        return !meaningfulNameTokens(in: line).isEmpty
    }

    static func meaningfulNameTokens(in line: String) -> [String] {
        wordTokens(line).filter { token in
            guard token.rangeOfCharacter(from: .letters) != nil else { return false }
            return !nonNameWords.contains(token)
                && !matches(token, #"^(?:approx|needed|optional|hydration|percent)$"#)
        }
    }

    static func wordTokens(_ line: String) -> [String] {
        let value = folded(line)
        guard let expression = try? NSRegularExpression(
            pattern: #"[[:alpha:]]+(?:[-'][[:alpha:]]+)*|\d+(?:[.,/]\d+)?"#
        ) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            return String(value[swiftRange])
        }
    }

    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func evidenceAdjustedConfidence(_ base: Double, record: LineRecord) -> Double {
        guard let sourceConfidence = record.evidence.sourceConfidence else {
            return clamp(base)
        }
        return clamp((base * 0.72) + (clamp(sourceConfidence) * 0.28))
    }

    static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    static func appendUnique(_ reason: ReviewReason, to reasons: inout [ReviewReason]) {
        if !reasons.contains(reason) { reasons.append(reason) }
    }
}
