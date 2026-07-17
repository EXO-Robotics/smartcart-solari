import CoreImage
import PhotosUI
import SwiftUI
import UIKit
@preconcurrency import Vision

struct RecipeComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    let initialMethod: ImportMethod

    @State private var selectedMethod: ImportMethod
    @State private var title = "Lemon Herb Chicken Pasta"
    @State private var recipeText = """
    1 lb chicken breasts
    8 oz penne pasta
    2 tbsp olive oil
    1 lemon, zested and juiced
    2 cloves garlic, minced
    1/2 cup heavy cream
    1/2 cup parmesan cheese
    1 bunch fresh parsley
    """
    @State private var linkText = "https://"
    @State private var selectedSampleIndex = 0
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var showCamera = false
    @State private var isProcessing = false
    @State private var processingMessage = ""
    @State private var errorMessage: String?
    @State private var lastVisionOCRConfidence: Double?
    @State private var lastVisionLayoutConfidence: Double?
    @State private var lastVisionSourceLines: [OCRSourceLine] = []
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case recipe
        case link
    }

    init(initialMethod: ImportMethod) {
        self.initialMethod = initialMethod
        _selectedMethod = State(initialValue: initialMethod)
    }

    private var draftRecipe: Recipe {
        var recipe = RecipeParser.parse(
            title: title,
            text: recipeText,
            source: source(for: selectedMethod),
            sourceDetail: sourceDetail,
            sourceLines: selectedMethod == .camera || selectedMethod == .photoLibrary
                ? lastVisionSourceLines
                : []
        )
        if selectedMethod == .camera || selectedMethod == .photoLibrary {
            for index in recipe.ingredients.indices {
                if recipe.ingredients[index].sourceEvidence?.ocrConfidence == nil {
                    recipe.ingredients[index].sourceEvidence?.ocrConfidence = lastVisionOCRConfidence
                }
                recipe.ingredients[index].sourceEvidence?.layoutConfidence = lastVisionLayoutConfidence
            }
        }
        return recipe
    }

    private var sourceDetail: String {
        switch selectedMethod {
        case .camera: "Captured with SmartCart"
        case .photoLibrary: "Imported from Photos"
        case .recipeLink, .pinterest: linkText
        case .recipeText: "Pasted into SmartCart"
        case .sample: "SmartCart sample recipe"
        }
    }

    private func addingSourceCrops(to sourceRecipe: Recipe) -> Recipe {
        var recipe = sourceRecipe
        let normalizedImages: [CGImage?] = selectedImages.map {
            RecipeImagePreprocessor.normalizeOrientation($0).cgImage
        }
        for index in recipe.ingredients.indices {
            guard let evidence = recipe.ingredients[index].sourceEvidence else { continue }
            recipe.ingredients[index].sourceEvidence?.sourceCropJPEGData = sourceCropData(
                for: evidence,
                normalizedImages: normalizedImages
            )
        }
        return recipe
    }

    private func sourceCropData(
        for evidence: IngredientSourceEvidence,
        normalizedImages: [CGImage?]
    ) -> Data? {
        guard let pageIndex = evidence.pageIndex,
              normalizedImages.indices.contains(pageIndex),
              let cgImage = normalizedImages[pageIndex],
              let box = evidence.boundingBox
        else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let horizontalPadding = max(5, width * 0.02)
        let verticalPadding = max(5, height * 0.012)
        let sourceRect = CGRect(
            x: CGFloat(box.x) * width - horizontalPadding,
            y: (1 - CGFloat(box.y + box.height)) * height - verticalPadding,
            width: CGFloat(box.width) * width + (horizontalPadding * 2),
            height: CGFloat(box.height) * height + (verticalPadding * 2)
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard sourceRect.width > 1,
              sourceRect.height > 1,
              let crop = cgImage.cropping(to: sourceRect.integral)
        else { return nil }
        return UIImage(cgImage: crop).jpegData(compressionQuality: 0.76)
    }

    private var canImport: Bool {
        switch selectedMethod {
        case .camera, .photoLibrary:
            !selectedImages.isEmpty && !draftRecipe.ingredients.isEmpty
        case .recipeLink, .pinterest:
            validURL != nil
        case .recipeText:
            !draftRecipe.ingredients.isEmpty
        case .sample:
            appModel.recipes.indices.contains(selectedSampleIndex)
        }
    }

    private var validURL: URL? {
        guard let url = URL(string: linkText), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    methodPicker
                    selectedMethodContent

                    if selectedMethod != .sample && selectedMethod != .recipeLink && selectedMethod != .pinterest {
                        editableRecipeFields
                        detectedIngredients
                    }

                    if let errorMessage {
                        InfoBanner(
                            symbol: "exclamationmark.triangle.fill",
                            title: "Import needs attention",
                            message: errorMessage,
                            color: SmartCartTheme.coral
                        )
                    }
                }
                .padding(18)
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .smartCartBackground()
            .navigationTitle("Import recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    Button {
                        Task { await importRecipe() }
                    } label: {
                        ViewThatFits {
                            HStack {
                                Text(importButtonTitle)
                                Spacer()
                                if isProcessing {
                                    ProgressView()
                                        .tint(SmartCartTheme.onAccent)
                                } else {
                                    Image(systemName: "arrow.right")
                                }
                            }
                            HStack {
                                Text("Import")
                                Spacer()
                                if isProcessing {
                                    ProgressView()
                                        .tint(SmartCartTheme.onAccent)
                                } else {
                                    Image(systemName: "arrow.right")
                                }
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canImport || isProcessing)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isProcessing)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                selectedImages = [image]
                Task { await recognizeRecipe(in: [image]) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) {
            guard !photoItems.isEmpty else { return }
            Task { await loadPhotos(photoItems) }
        }
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IMPORT FROM")
                .smartEyebrow(SmartCartTheme.mutedInk)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ImportMethod.allCases) { method in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedMethod = method
                                errorMessage = nil
                                focusedField = nil
                            }
                        } label: {
                            Label(method.shortTitle, systemImage: method.symbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selectedMethod == method ? .white : method.tint)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(selectedMethod == method ? method.tint : method.tint.opacity(0.09))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var selectedMethodContent: some View {
        switch selectedMethod {
        case .camera:
            mediaImportCard(
                title: "Snap any recipe",
                message: UIImagePickerController.isSourceTypeAvailable(.camera)
                    ? "Keep the ingredient list flat, bright, and fully in frame."
                    : "The Simulator has no camera. Use Upload Photo to test image recognition.",
                buttonTitle: selectedImages.isEmpty ? "Open camera" : "Retake photo",
                symbol: "camera.fill"
            ) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                } else {
                    errorMessage = "Camera capture is unavailable in the iOS Simulator. Upload a saved recipe image instead."
                }
            }

        case .photoLibrary:
            VStack(alignment: .leading, spacing: 12) {
                mediaPreview
                PhotosPicker(selection: $photoItems, maxSelectionCount: 8, matching: .images) {
                    Label(selectedImages.isEmpty ? "Choose recipe photos" : "Choose different photos", systemImage: "photo.stack.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                Text("Select up to 8 pages. SmartCart combines them in selection order.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

        case .recipeLink, .pinterest:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: selectedMethod.symbol)
                        .font(.title2.bold())
                        .foregroundStyle(selectedMethod.tint)
                        .frame(width: 48, height: 48)
                        .background(selectedMethod.tint.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedMethod == .pinterest ? "Import a recipe pin" : "Import from a recipe page")
                            .font(.headline)
                            .foregroundStyle(SmartCartTheme.navy)
                        Text("SmartCart looks for standard recipe ingredients embedded in the page.")
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }
                }

                TextField("https://example.com/recipe", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .link)
                    .smartField()

                InfoBanner(
                    symbol: "lock.shield.fill",
                    title: "No account sign-in",
                    message: "SmartCart reads public recipe metadata only. Pinterest may block some pages; photo and text import remain available.",
                    color: SmartCartTheme.green
                )
            }
            .smartCartCard()

        case .recipeText:
            InfoBanner(
                symbol: "doc.on.clipboard.fill",
                title: "Paste and go",
                message: "One ingredient per line works best. You can correct names, quantities, and pantry status next.",
                color: SmartCartTheme.green
            )

        case .sample:
            samplePicker
        }
    }

    private var samplePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Choose a sample", subtitle: "Perfect for testing every step")

            ForEach(Array(appModel.recipes.enumerated()), id: \.element.id) { index, recipe in
                Button {
                    selectedSampleIndex = index
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: recipe.heroSymbol)
                            .font(.title3.bold())
                            .foregroundStyle(index == selectedSampleIndex ? SmartCartTheme.onAccent : SmartCartTheme.green)
                            .frame(width: 48, height: 48)
                            .background(index == selectedSampleIndex ? AnyShapeStyle(SmartCartTheme.green) : AnyShapeStyle(SmartCartTheme.herbLight))
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .shadow(color: index == selectedSampleIndex ? SmartCartTheme.mintGlow : .clear, radius: 10)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.title)
                                .font(.headline)
                                .foregroundStyle(SmartCartTheme.navy)
                            Text("\(recipe.ingredients.count) ingredients · \(recipe.servings) servings · \(recipe.totalMinutes)m")
                                .font(.caption)
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                        }

                        Spacer()

                        Image(systemName: index == selectedSampleIndex ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(index == selectedSampleIndex ? SmartCartTheme.green : SmartCartTheme.border)
                    }
                    .smartCartCard(padding: 13)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private func mediaImportCard(
        title: String,
        message: String,
        buttonTitle: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 15) {
            mediaPreview

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }

            Button(action: action) {
                Label(buttonTitle, systemImage: symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .smartCartCard()
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if let selectedImage = selectedImages.first {
            Image(uiImage: selectedImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if isProcessing {
                        Label(processingMessage, systemImage: "text.viewfinder")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SmartCartTheme.ink)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(SmartCartTheme.canvas.opacity(0.86))
                            .clipShape(Capsule())
                            .overlay { Capsule().stroke(SmartCartTheme.border, lineWidth: 1) }
                            .padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selectedImages.count > 1 {
                        Label("\(selectedImages.count) pages", systemImage: "doc.on.doc.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SmartCartTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(SmartCartTheme.canvas.opacity(0.86))
                            .clipShape(Capsule())
                            .overlay { Capsule().stroke(SmartCartTheme.border, lineWidth: 1) }
                            .padding(10)
                    }
                }
                .clipped()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(SmartCartTheme.green)
                Text("Recipe image preview")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(SmartCartTheme.herbLight.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }

    private var editableRecipeFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("RECIPE NAME")
                    .smartEyebrow(SmartCartTheme.mutedInk)
                TextField("Recipe name", text: $title)
                    .font(.headline)
                    .focused($focusedField, equals: .title)
                    .smartField()
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("INGREDIENT TEXT")
                        .smartEyebrow(SmartCartTheme.mutedInk)
                    Spacer()
                    Text("\(draftRecipe.ingredients.count) found")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.green)
                }

                TextEditor(text: $recipeText)
                    .font(.body)
                    .focused($focusedField, equals: .recipe)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 170)
                    .padding(10)
                    .background(SmartCartTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(SmartCartTheme.border, lineWidth: 1)
                    }
            }
        }
    }

    private var detectedIngredients: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeader(title: "Detected ingredients", subtitle: "You’ll confirm these on the next screen")

            ForEach(draftRecipe.ingredients.prefix(6)) { ingredient in
                HStack(spacing: 11) {
                    Image(systemName: ingredient.category.symbol)
                        .font(.subheadline.bold())
                        .foregroundStyle(SmartCartTheme.green)
                        .frame(width: 37, height: 37)
                        .background(SmartCartTheme.herbLight)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SmartCartTheme.navy)
                            .lineLimit(1)
                        Text(ingredient.category.rawValue)
                            .font(.caption2)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }

                    Spacer()

                    Text(ingredient.displayQuantity)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                .padding(12)
                .background(SmartCartTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(SmartCartTheme.border, lineWidth: 1)
                }
            }

            if draftRecipe.ingredients.count > 6 {
                Text("+ \(draftRecipe.ingredients.count - 6) more ingredients")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .padding(.leading, 4)
            }
        }
    }

    private var importButtonTitle: String {
        if isProcessing { return processingMessage }
        return switch selectedMethod {
        case .recipeLink, .pinterest: "Import recipe"
        case .sample: "Use this sample"
        default: "Review ingredients"
        }
    }

    private func source(for method: ImportMethod) -> RecipeSource {
        switch method {
        case .camera, .photoLibrary: .photo
        case .recipeLink: .link
        case .pinterest: .pinterest
        case .recipeText: .text
        case .sample: .sample
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isProcessing = true
        processingMessage = "Loading \(items.count) page\(items.count == 1 ? "" : "s")…"
        errorMessage = nil
        defer { isProcessing = false }

        do {
            var images: [UIImage] = []
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else {
                    throw RecipeVisionError.unreadableImage
                }
                images.append(image)
            }
            selectedImages = images
            await recognizeRecipe(in: images)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recognizeRecipe(in images: [UIImage]) async {
        isProcessing = true
        processingMessage = "Reading recipe text…"
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let customWords = [title] + appModel.pantryInventory.map(\.name)
            let result = try await RecipeVisionReader.recognizeText(
                in: images,
                contextualWords: customWords
            )
            processingMessage = "Normalizing ingredients…"
            recipeText = result.text
            lastVisionOCRConfidence = Double(result.confidence)
            lastVisionLayoutConfidence = result.layoutConfidence
            lastVisionSourceLines = result.sourceLines
            if let firstLine = result.text
                .components(separatedBy: .newlines)
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty && $0.range(of: #"\d"#, options: .regularExpression) == nil }) {
                title = String(firstLine.prefix(60))
            }
            let recipe = RecipeParser.parse(
                title: title,
                text: result.text,
                source: source(for: selectedMethod),
                sourceDetail: sourceDetail,
                sourceLines: result.sourceLines
            )
            appModel.lastImportReport = RecipeParser.importReport(
                for: recipe,
                recognizedText: result.text,
                sourcePageCount: result.pageCount,
                retryCount: result.retryCount,
                duration: result.duration
            )
            appModel.lastImportReport?.layoutConfidence = result.layoutConfidence
            appModel.lastImportReport?.layoutAmbiguityCount = result.layoutAmbiguityCount
            appModel.lastImportReport?.ignoredInstructionLineCount = result.ignoredInstructionLineCount
            appModel.lastImportReport?.sourceEvidenceCount = recipe.ingredients.filter {
                $0.sourceEvidence?.pageIndex != nil && $0.sourceEvidence?.boundingBox != nil
            }.count
            appModel.lastImportReport?.quantityAlternativeReviewCount = recipe.ingredients.filter {
                !($0.sourceEvidence?.alternateQuantityCandidates.isEmpty ?? true)
            }.count
            if recipe.ingredients.isEmpty {
                errorMessage = "No ingredients were detected. Keep the photo and try a tighter crop, a clearer image, pasted text, or manual ingredient entry. SmartCart will never invent replacement groceries."
            }
            try? await Task.sleep(for: .milliseconds(220))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importRecipe() async {
        errorMessage = nil

        switch selectedMethod {
        case .sample:
            guard appModel.recipes.indices.contains(selectedSampleIndex) else { return }
            appModel.beginRecipe(appModel.recipes[selectedSampleIndex])

        case .recipeLink, .pinterest:
            guard let validURL else {
                errorMessage = RecipeImportError.invalidURL.localizedDescription
                return
            }
            isProcessing = true
            processingMessage = "Reading recipe page…"
            defer { isProcessing = false }
            do {
                let imported = try await RecipeLinkImporter.importRecipe(
                    from: validURL,
                    source: selectedMethod == .pinterest ? .pinterest : .link
                )
                appModel.beginRecipe(imported)
            } catch {
                errorMessage = error.localizedDescription
            }

        case .camera, .photoLibrary, .recipeText:
            let parsedRecipe = draftRecipe
            guard !parsedRecipe.ingredients.isEmpty else {
                errorMessage = "No ingredients detected. Retry the image, edit or paste the ingredient text, or add ingredients manually before continuing."
                return
            }
            let recipe = selectedMethod == .camera || selectedMethod == .photoLibrary
                ? addingSourceCrops(to: parsedRecipe)
                : parsedRecipe
            appModel.beginRecipe(recipe)
        }
    }
}

private enum RecipeVisionReader {
    struct Result {
        var text: String
        var sourceLines: [OCRSourceLine]
        var pageCount: Int
        var retryCount: Int
        var duration: TimeInterval
        var confidence: Float
        var layoutConfidence: Double
        var layoutAmbiguityCount: Int
        var ignoredInstructionLineCount: Int
    }

    static func recognizeText(
        in images: [UIImage],
        contextualWords: [String] = []
    ) async throws -> Result {
        let startedAt = Date()
        var pages: [String] = []
        var sourceLines: [OCRSourceLine] = []
        var retryCount = 0
        var confidenceTotal: Float = 0
        var layoutConfidenceTotal = 0.0
        var layoutAmbiguityCount = 0
        var ignoredInstructionLineCount = 0
        let customWords = RecipeOCRPolicy.boundedCustomWords(contextualWords)

        for (pageIndex, image) in images.enumerated() {
            let normalizedImage = RecipeImagePreprocessor.normalizeOrientation(image)
            do {
                let page = try await recognizeText(
                    in: normalizedImage,
                    pageIndex: pageIndex,
                    level: .accurate,
                    minimumTextHeight: 0.008,
                    customWords: customWords
                )
                pages.append(page.text)
                sourceLines.append(contentsOf: page.sourceLines)
                confidenceTotal += page.confidence
                layoutConfidenceTotal += page.layoutConfidence
                layoutAmbiguityCount += page.layoutAmbiguityCount
                ignoredInstructionLineCount += page.ignoredInstructionLineCount
            } catch {
                retryCount += 1
                let correctedImage = RecipeImagePreprocessor.contrastEnhanced(normalizedImage)
                let page = try await recognizeText(
                    in: correctedImage,
                    pageIndex: pageIndex,
                    level: .accurate,
                    minimumTextHeight: 0.004,
                    customWords: customWords
                )
                pages.append(page.text)
                sourceLines.append(contentsOf: page.sourceLines)
                confidenceTotal += page.confidence
                layoutConfidenceTotal += page.layoutConfidence
                layoutAmbiguityCount += page.layoutAmbiguityCount
                ignoredInstructionLineCount += page.ignoredInstructionLineCount
            }
        }

        let combined = pages.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else { throw RecipeVisionError.noTextFound }
        return Result(
            text: combined,
            sourceLines: sourceLines,
            pageCount: images.count,
            retryCount: retryCount,
            duration: Date().timeIntervalSince(startedAt),
            confidence: confidenceTotal / Float(max(1, images.count)),
            layoutConfidence: layoutConfidenceTotal / Double(max(1, images.count)),
            layoutAmbiguityCount: layoutAmbiguityCount,
            ignoredInstructionLineCount: ignoredInstructionLineCount
        )
    }

    private static func recognizeText(
        in image: UIImage,
        pageIndex: Int,
        level: VNRequestTextRecognitionLevel,
        minimumTextHeight: Float,
        customWords: [String]
    ) async throws -> (text: String, sourceLines: [OCRSourceLine], confidence: Float, layoutConfidence: Double, layoutAmbiguityCount: Int, ignoredInstructionLineCount: Int) {
        guard let cgImage = image.cgImage else {
            throw RecipeVisionError.unreadableImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let candidates = observations.compactMap {
                    observation -> (VNRecognizedTextObservation, VNRecognizedText, [OCRTextAlternative])? in
                    let recognized = observation.topCandidates(3)
                    guard let candidate = recognized.first else { return nil }
                    let alternatives: [OCRTextAlternative]
                    if RecipeOCRPolicy.shouldPreserveAlternatives(
                        in: candidate.string,
                        confidence: candidate.confidence
                    ) {
                        alternatives = recognized.dropFirst().compactMap { alternative in
                            let text = alternative.string.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty,
                                  text.caseInsensitiveCompare(candidate.string) != .orderedSame
                            else { return nil }
                            return OCRTextAlternative(
                                text: text,
                                confidence: Double(alternative.confidence)
                            )
                        }
                    } else {
                        alternatives = []
                    }
                    return (observation, candidate, alternatives)
                }
                let layout = OCRLayoutReconstructor.reconstruct(
                    candidates.map { observation, candidate, alternatives in
                        OCRTextObservation(
                            text: candidate.string,
                            boundingBox: OCRNormalizedBoundingBox(
                                x: observation.boundingBox.origin.x,
                                y: observation.boundingBox.origin.y,
                                width: observation.boundingBox.width,
                                height: observation.boundingBox.height
                            ),
                            confidence: Double(candidate.confidence),
                            pageIndex: pageIndex,
                            alternateCandidates: alternatives
                        )
                    }
                )
                let text = layout.reconstructedText
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if text.isEmpty {
                    continuation.resume(throwing: RecipeVisionError.noTextFound)
                } else {
                    let confidence = candidates.reduce(Float.zero) { $0 + $1.1.confidence } / Float(max(1, candidates.count))
                    continuation.resume(
                        returning: (
                            text,
                            layout.ingredientSourceLines,
                            confidence,
                            layout.layoutConfidence,
                            layout.ambiguities.count,
                            layout.ignoredInstructionLines.count
                        )
                    )
                }
            }
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = minimumTextHeight
            request.customWords = customWords

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum RecipeOCRPolicy {
    static let maximumCustomWordCount = 96

    private static let standardWords = [
        "tablespoon", "teaspoon", "tbsp", "tsp", "ounces", "ounce", "oz",
        "pounds", "pound", "lbs", "grams", "kilograms", "milliliters",
        "cups", "cloves", "pinch", "bunch", "package", "all-purpose",
        "mascarpone", "gochujang", "za'atar", "clearjel", "gruyère",
        "worcestershire", "parmesan", "mozzarella", "cilantro", "shallot",
        "scallion", "cornstarch", "buttermilk", "confectioners", "semi-sweet",
        "softened", "melted", "minced", "chopped", "divided", "drained",
        "rinsed", "packed", "sifted", "optional", "to taste"
    ]

    static func boundedCustomWords(_ contextualWords: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let contextual = contextualWords.flatMap { value in
            [value] + value.split(whereSeparator: \Character.isWhitespace).map(String.init)
        }
        for value in standardWords + contextual {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = cleaned.lowercased()
            guard (2...40).contains(cleaned.count), seen.insert(key).inserted else { continue }
            result.append(cleaned)
            if result.count == maximumCustomWordCount { break }
        }
        return result
    }

    static func shouldPreserveAlternatives(in text: String, confidence: Float) -> Bool {
        if confidence < 0.78 { return true }
        if text.range(of: #"[¼½¾⅓⅔⅛⅜⅝⅞⅙⅚]|\d\s*/\s*\d"#, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: #"^\s*[-•*☐✓]?\s*\d"#, options: .regularExpression) != nil {
            return true
        }
        return text.range(
            of: #"(?i)\b(cups?|tbsp|tablespoons?|tsp|teaspoons?|oz|ounces?|lbs?|pounds?|g|grams?|kg|ml|liters?|cloves?|cans?|packages?)\b"#,
            options: .regularExpression
        ) != nil
    }
}

enum RecipeImagePreprocessor {
    static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func contrastEnhanced(_ image: UIImage) -> UIImage {
        let normalized = normalizeOrientation(image)
        guard let input = CIImage(image: normalized) else { return normalized }
        let output = input.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.28,
                kCIInputBrightnessKey: 0.02
            ]
        )
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return normalized }
        return UIImage(cgImage: cgImage, scale: normalized.scale, orientation: .up)
    }
}

private enum RecipeVisionError: LocalizedError {
    case unreadableImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "SmartCart could not open that image."
        case .noTextFound:
            "No readable recipe text was found. Try a brighter, flatter image or paste the ingredient text."
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
