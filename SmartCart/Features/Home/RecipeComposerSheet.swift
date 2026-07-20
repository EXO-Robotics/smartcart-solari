import CoreImage
import ImageIO
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
    @State private var linkText = ""
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
    @State private var lastVisionSourceDocument: RecipeSourceDocument?
    @State private var lastVisionRetryCount = 0
    @State private var lastVisionDuration: TimeInterval = 0
    @State private var lastVisionLayoutAmbiguityCount = 0
    @State private var lastVisionIgnoredInstructionCount = 0
    @State private var selectedImageSetID: UUID?
    @State private var recognizedImageSetID: UUID?
    @State private var recognitionTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case recipe
        case link
    }

    init(initialMethod: ImportMethod, initialText: String? = nil) {
        let visibleInitialMethod = initialMethod == .pinterest ? .recipeLink : initialMethod
        self.initialMethod = visibleInitialMethod
        _selectedMethod = State(initialValue: visibleInitialMethod)
        _linkText = State(
            initialValue: initialText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
        if visibleInitialMethod == .sample {
            _title = State(initialValue: "Lemon Herb Chicken Pasta")
        } else {
            _title = State(initialValue: "Imported Recipe")
            _recipeText = State(initialValue: "")
        }
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
            recipe.sourceDocument = lastVisionSourceDocument
            if let sourceDocument = lastVisionSourceDocument {
                let rawSourceText = sourceDocument.rawRecognizedText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                recipe.rawSourceText = rawSourceText.isEmpty
                    ? nil
                    : sourceDocument.rawRecognizedText
                let observationsByID = Dictionary(
                    sourceDocument.observations.map { ($0.observationID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                for index in recipe.ingredients.indices {
                    guard let observationIDs = recipe.ingredients[index]
                        .sourceEvidence?.sourceObservationIDs
                    else { continue }
                    let originalLines = observationIDs.compactMap {
                        observationsByID[$0]?.text
                    }
                    if !originalLines.isEmpty {
                        recipe.ingredients[index].sourceEvidence?.originalLine = originalLines
                            .joined(separator: "\n")
                    }
                }
            } else {
                recipe.rawSourceText = nil
            }
        } else if selectedMethod == .recipeText {
            let sourceText = recipeText.trimmingCharacters(in: .whitespacesAndNewlines)
            recipe.rawSourceText = sourceText.isEmpty ? nil : recipeText
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

    private func canImport(_ recipe: Recipe) -> Bool {
        switch selectedMethod {
        case .camera, .photoLibrary:
            !selectedImages.isEmpty
                && selectedImageSetID != nil
                && selectedImageSetID == recognizedImageSetID
                && !recipe.ingredients.isEmpty
        case .recipeLink, .pinterest:
            validURL != nil
        case .recipeText:
            !recipe.ingredients.isEmpty
        case .sample:
            appModel.recipes.indices.contains(selectedSampleIndex)
        }
    }

    private var validURL: URL? {
        RecipeLinkInput.validHTTPSURL(from: linkText)
    }

    var body: some View {
        let draft = draftRecipe
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    methodPicker
                    selectedMethodContent

                    if selectedMethod != .sample && selectedMethod != .recipeLink && selectedMethod != .pinterest {
                        editableRecipeFields(for: draft)
                        detectedIngredients(in: draft)
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
                    .disabled(!canImport(draft) || isProcessing)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isProcessing)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                beginRecognition(in: [image])
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) {
            guard !photoItems.isEmpty else { return }
            beginPhotoLoad(photoItems)
        }
        .onDisappear {
            recognitionTask?.cancel()
        }
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IMPORT FROM")
                .smartEyebrow(SmartCartTheme.mutedInk)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(visibleImportMethods) { method in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                switchImportMethod(to: method)
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

    private var visibleImportMethods: [ImportMethod] {
        [.camera, .photoLibrary, .recipeLink, .recipeText, .sample]
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
                        Text("Import from a recipe page")
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
                    .accessibilityIdentifier("recipe-import-link-field")

                if !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   validURL == nil {
                    Label("Enter a complete HTTPS recipe link", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.coral)
                }

                if let validURL,
                   RecipeLinkInput.source(for: validURL) == .pinterest {
                    Label("Pinterest recipe link detected", systemImage: "link.badge.plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SmartCartTheme.green)
                }

                InfoBanner(
                    symbol: "lock.shield.fill",
                    title: "No account sign-in",
                    message: "SmartCart reads public recipe metadata only. Some sites may block access; photo and text import remain available.",
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

    private func editableRecipeFields(for recipe: Recipe) -> some View {
        let report = currentImportReport(for: recipe)
        return VStack(alignment: .leading, spacing: 14) {
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
                    Text("\(recipe.ingredients.count) found")
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

            if !recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                importQualitySummary(report)
            }
        }
    }

    private func detectedIngredients(in recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeader(title: "Detected ingredients", subtitle: "You’ll confirm these on the next screen")

            ForEach(recipe.ingredients.prefix(6)) { ingredient in
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

            if recipe.ingredients.count > 6 {
                Text("+ \(recipe.ingredients.count - 6) more ingredients")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .padding(.leading, 4)
            }
        }
    }

    private func currentImportReport(for recipe: Recipe) -> RecipeImportReport {
        var report = RecipeParser.importReport(
            for: recipe,
            recognizedText: recipeText,
            sourcePageCount: max(1, selectedImages.count),
            retryCount: lastVisionRetryCount,
            duration: lastVisionDuration
        )
        report.layoutConfidence = lastVisionLayoutConfidence ?? 1
        report.layoutAmbiguityCount = lastVisionLayoutAmbiguityCount
        report.ignoredInstructionLineCount = lastVisionIgnoredInstructionCount
        report.sourceEvidenceCount = recipe.ingredients.filter { $0.sourceEvidence != nil }.count
        report.quantityAlternativeReviewCount = recipe.ingredients.filter {
            ($0.sourceEvidence?.alternateQuantityCandidates.count ?? 0) > 1
        }.count
        return report
    }

    private func importQualitySummary(_ report: RecipeImportReport) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: report.confidenceLabel == "High confidence"
                    ? "checkmark.seal.fill"
                    : "exclamationmark.triangle.fill")
                Text(report.confidenceLabel)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(report.highConfidenceCount) ready · \(report.reviewCount + report.unknownCount) review")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(report.confidenceLabel == "High confidence"
                ? SmartCartTheme.green
                : SmartCartTheme.coral)

            if report.requiredConfirmationCount > 0 {
                Text("Confirm \(report.requiredConfirmationCount) uncertain amount\(report.requiredConfirmationCount == 1 ? "" : "s") before matching products.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            } else if report.omittedCandidateLineCount > 0 {
                Text("SmartCart may have skipped \(report.omittedCandidateLineCount) ingredient-like line\(report.omittedCandidateLineCount == 1 ? "" : "s"). Compare the text with the recipe image.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            } else {
                Text("Every detected line remains editable, and you’ll confirm the ingredients before SmartCart shops.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }

            if report.retryCount > 0 {
                Label("SmartCart automatically tried an enhanced image pass.", systemImage: "wand.and.stars")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
        }
        .padding(12)
        .background(SmartCartTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SmartCartTheme.border, lineWidth: 1)
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
        case .recipeLink, .pinterest:
            validURL.map(RecipeLinkInput.source(for:)) ?? .link
        case .recipeText: .text
        case .sample: .sample
        }
    }

    private func switchImportMethod(to method: ImportMethod) {
        guard selectedMethod != method else { return }
        recognitionTask?.cancel()
        recognitionTask = nil
        selectedImages = []
        photoItems = []
        selectedImageSetID = nil
        recognizedImageSetID = nil
        isProcessing = false
        clearVisionResult()
        selectedMethod = method
        errorMessage = nil
        focusedField = nil
        if method == .camera || method == .photoLibrary {
            recipeText = ""
            title = "Imported Recipe"
        } else if method == .recipeText {
            recipeText = ""
            title = "Imported Recipe"
        }
    }

    private func beginRecognition(in images: [UIImage]) {
        recognitionTask?.cancel()
        let imageSetID = UUID()
        let boundedImages = images.map { RecipeImagePreprocessor.resizedForOCR($0) }
        selectedImages = boundedImages
        selectedImageSetID = imageSetID
        recognizedImageSetID = nil
        recipeText = ""
        title = "Imported Recipe"
        clearVisionResult()
        errorMessage = nil
        recognitionTask = Task {
            await recognizeRecipe(in: boundedImages, imageSetID: imageSetID)
        }
    }

    private func beginPhotoLoad(_ items: [PhotosPickerItem]) {
        recognitionTask?.cancel()
        let imageSetID = UUID()
        selectedImages = []
        selectedImageSetID = imageSetID
        recognizedImageSetID = nil
        recipeText = ""
        title = "Imported Recipe"
        clearVisionResult()
        errorMessage = nil
        recognitionTask = Task {
            await loadPhotos(items, imageSetID: imageSetID)
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem], imageSetID: UUID) async {
        isProcessing = true
        processingMessage = "Loading \(items.count) page\(items.count == 1 ? "" : "s")…"
        errorMessage = nil
        defer {
            if selectedImageSetID == imageSetID {
                isProcessing = false
            }
        }

        do {
            var images: [UIImage] = []
            for item in items {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = RecipeImagePreprocessor.downsampledImage(from: data)
                else {
                    throw RecipeVisionError.unreadableImage
                }
                try Task.checkCancellation()
                images.append(image)
            }
            guard !Task.isCancelled, selectedImageSetID == imageSetID else { return }
            selectedImages = images
            await recognizeRecipe(in: images, imageSetID: imageSetID)
        } catch {
            guard !Task.isCancelled, selectedImageSetID == imageSetID else { return }
            selectedImages = []
            recognizedImageSetID = nil
            errorMessage = error.localizedDescription
        }
    }

    private func recognizeRecipe(in images: [UIImage], imageSetID: UUID) async {
        isProcessing = true
        processingMessage = "Reading recipe text…"
        errorMessage = nil
        defer {
            if selectedImageSetID == imageSetID {
                isProcessing = false
            }
        }

        do {
            let customWords = [title] + appModel.pantryInventory.map(\.name)
            let result = try await RecipeVisionReader.recognizeText(
                in: images,
                contextualWords: customWords
            )
            guard !Task.isCancelled, selectedImageSetID == imageSetID else { return }
            processingMessage = "Normalizing ingredients…"
            recipeText = result.text
            if title == "Imported Recipe", let suggestedTitle = result.suggestedTitle {
                title = suggestedTitle
            }
            lastVisionOCRConfidence = Double(result.confidence)
            lastVisionLayoutConfidence = result.layoutConfidence
            lastVisionSourceLines = result.sourceLines
            lastVisionSourceDocument = result.sourceDocument
            lastVisionRetryCount = result.retryCount
            lastVisionDuration = result.duration
            lastVisionLayoutAmbiguityCount = result.layoutAmbiguityCount
            lastVisionIgnoredInstructionCount = result.ignoredInstructionLineCount
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
            recognizedImageSetID = imageSetID
            guard hasCredibleIngredients(recipe) else {
                errorMessage = "No ingredients were detected. Keep the photo and try a tighter crop, a clearer image, pasted text, or manual ingredient entry. SmartCart will never invent replacement groceries."
                return
            }
            processingMessage = "Opening Recipe Ready…"
            guard appModel.beginRecipe(addingSourceCrops(to: draftRecipe)) else {
                errorMessage = "The ingredient list is empty. Review the recognized text or try another image."
                return
            }
        } catch {
            guard !Task.isCancelled, selectedImageSetID == imageSetID else { return }
            recipeText = ""
            clearVisionResult()
            recognizedImageSetID = nil
            errorMessage = error.localizedDescription
        }
    }

    private func clearVisionResult() {
        lastVisionOCRConfidence = nil
        lastVisionLayoutConfidence = nil
        lastVisionSourceLines = []
        lastVisionSourceDocument = nil
        lastVisionRetryCount = 0
        lastVisionDuration = 0
        lastVisionLayoutAmbiguityCount = 0
        lastVisionIgnoredInstructionCount = 0
    }

    private func importRecipe() async {
        errorMessage = nil

        switch selectedMethod {
        case .sample:
            guard appModel.recipes.indices.contains(selectedSampleIndex) else { return }
            if !appModel.beginRecipe(appModel.recipes[selectedSampleIndex]) {
                errorMessage = "That sample has no ingredients. Choose another recipe."
            }

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
                    source: RecipeLinkInput.source(for: validURL)
                )
                guard hasCredibleIngredients(imported) else {
                    errorMessage = "No ingredient list was found on that page. Check the link, paste the recipe text, or import a screenshot."
                    return
                }
                if !appModel.beginRecipe(imported) {
                    errorMessage = "No ingredient list was found on that page. Check the link, paste the recipe text, or import a screenshot."
                }
            } catch {
                errorMessage = error.localizedDescription
            }

        case .camera, .photoLibrary, .recipeText:
            let parsedRecipe = draftRecipe
            guard hasCredibleIngredients(parsedRecipe) else {
                errorMessage = "No ingredients detected. Retry the image, edit or paste the ingredient text, or add ingredients manually before continuing."
                return
            }
            let recipe = selectedMethod == .camera || selectedMethod == .photoLibrary
                ? addingSourceCrops(to: parsedRecipe)
                : parsedRecipe
            if !appModel.beginRecipe(recipe) {
                errorMessage = "No ingredients detected. Review the text or try another import method."
            }
        }
    }

    private func hasCredibleIngredients(_ recipe: Recipe) -> Bool {
        // Reuse the parser's existing usable-state boundary. Any ingredient-level
        // blockers remain visible and actionable on Recipe Ready.
        !recipe.ingredients.isEmpty
    }
}

enum RecipeVisionReader {
    struct Result {
        var suggestedTitle: String?
        var text: String
        var sourceLines: [OCRSourceLine]
        var sourceDocument: RecipeSourceDocument
        var pageCount: Int
        var retryCount: Int
        var duration: TimeInterval
        var confidence: Float
        var layoutConfidence: Double
        var layoutAmbiguityCount: Int
        var ignoredInstructionLineCount: Int
    }

    private struct PageResult {
        var suggestedTitle: String?
        var text: String
        var sourceLines: [OCRSourceLine]
        var rawRecognizedText: String
        var reconstructedText: String
        var filteredIngredientLines: [String]
        var ignoredSourceLines: [String]
        var sourceObservations: [RecipeSourceObservation]
        var confidence: Float
        var layoutConfidence: Double
        var layoutAmbiguityCount: Int
        var ignoredInstructionLineCount: Int

        var qualityScore: Double {
            RecipeOCRPolicy.qualityScore(
                confidence: confidence,
                layoutConfidence: layoutConfidence,
                ambiguityCount: layoutAmbiguityCount,
                sourceLineCount: sourceLines.count
            )
        }
    }

    static func recognizeText(
        in images: [UIImage],
        contextualWords: [String] = []
    ) async throws -> Result {
        let startedAt = Date()
        var pages: [String] = []
        var rawPages: [String] = []
        var reconstructedPages: [String] = []
        var filteredIngredientLines: [String] = []
        var ignoredSourceLines: [String] = []
        var sourceObservations: [RecipeSourceObservation] = []
        var suggestedTitle: String?
        var sourceLines: [OCRSourceLine] = []
        var retryCount = 0
        var confidenceTotal: Float = 0
        var layoutConfidenceTotal = 0.0
        var layoutAmbiguityCount = 0
        var ignoredInstructionLineCount = 0
        let customWords = RecipeOCRPolicy.boundedCustomWords(contextualWords)

        for (pageIndex, image) in images.enumerated() {
            let normalizedImage = RecipeImagePreprocessor.normalizeOrientation(image)
            let page: PageResult
            do {
                let primary = try await recognizeText(
                    in: normalizedImage,
                    pageIndex: pageIndex,
                    level: .accurate,
                    minimumTextHeight: 0.008,
                    customWords: customWords
                )
                if RecipeOCRPolicy.shouldRunEnhancedPass(
                    confidence: primary.confidence,
                    layoutConfidence: primary.layoutConfidence,
                    ambiguityCount: primary.layoutAmbiguityCount,
                    sourceLineCount: primary.sourceLines.count
                ) {
                    retryCount += 1
                    do {
                        let enhanced = try await recognizeText(
                            in: RecipeImagePreprocessor.contrastEnhanced(normalizedImage),
                            pageIndex: pageIndex,
                            level: .accurate,
                            minimumTextHeight: 0.004,
                            customWords: customWords
                        )
                        page = enhanced.qualityScore > primary.qualityScore
                            ? enhanced
                            : primary
                    } catch {
                        // A usable primary pass is always safer than discarding
                        // the page because an optional enhancement failed.
                        page = primary
                    }
                } else {
                    page = primary
                }
            } catch {
                retryCount += 1
                let correctedImage = RecipeImagePreprocessor.contrastEnhanced(normalizedImage)
                page = try await recognizeText(
                    in: correctedImage,
                    pageIndex: pageIndex,
                    level: .accurate,
                    minimumTextHeight: 0.004,
                    customWords: customWords
                )
            }
            try Task.checkCancellation()
            if suggestedTitle == nil {
                suggestedTitle = page.suggestedTitle
            }
            pages.append(page.text)
            rawPages.append(page.rawRecognizedText)
            reconstructedPages.append(page.reconstructedText)
            filteredIngredientLines.append(contentsOf: page.filteredIngredientLines)
            ignoredSourceLines.append(contentsOf: page.ignoredSourceLines)
            sourceObservations.append(contentsOf: page.sourceObservations)
            sourceLines.append(contentsOf: page.sourceLines)
            confidenceTotal += page.confidence
            layoutConfidenceTotal += page.layoutConfidence
            layoutAmbiguityCount += page.layoutAmbiguityCount
            ignoredInstructionLineCount += page.ignoredInstructionLineCount
        }

        let combined = pages.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else { throw RecipeVisionError.noTextFound }
        return Result(
            suggestedTitle: suggestedTitle,
            text: combined,
            sourceLines: sourceLines,
            sourceDocument: RecipeSourceDocument(
                rawRecognizedText: rawPages.joined(separator: "\n"),
                reconstructedText: reconstructedPages.joined(separator: "\n"),
                filteredIngredientLines: filteredIngredientLines,
                ignoredSourceLines: ignoredSourceLines,
                observations: sourceObservations
            ),
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
    ) async throws -> PageResult {
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
                    observation -> (VNRecognizedTextObservation, VNRecognizedText, [OCRTextAlternative], [OCRTextAlternative])? in
                    let recognized = observation.topCandidates(3)
                    guard let candidate = recognized.first else { return nil }
                    let alternatives = recognized.dropFirst().compactMap { alternative -> OCRTextAlternative? in
                        let text = alternative.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty,
                              text.caseInsensitiveCompare(candidate.string) != .orderedSame
                        else { return nil }
                        return OCRTextAlternative(
                            text: text,
                            confidence: Double(alternative.confidence)
                        )
                    }
                    let reconstructionAlternatives: [OCRTextAlternative]
                    if RecipeOCRPolicy.shouldPreserveAlternatives(
                        in: candidate.string,
                        confidence: candidate.confidence
                    ) {
                        reconstructionAlternatives = alternatives
                    } else {
                        reconstructionAlternatives = []
                    }
                    return (observation, candidate, alternatives, reconstructionAlternatives)
                }
                let sourceObservations = sourceObservations(
                    from: candidates,
                    pageIndex: pageIndex
                )
                let layout = OCRLayoutReconstructor.reconstruct(
                    layoutObservations(from: candidates, pageIndex: pageIndex)
                )
                let text = layout.reconstructedText
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if text.isEmpty {
                    continuation.resume(throwing: RecipeVisionError.noTextFound)
                } else {
                    let confidence = candidates.reduce(Float.zero) { $0 + $1.1.confidence } / Float(max(1, candidates.count))
                    continuation.resume(
                        returning: PageResult(
                            suggestedTitle: layout.suggestedTitle,
                            text: text,
                            sourceLines: layout.ingredientSourceLines,
                            rawRecognizedText: sourceObservations.map(\.text).joined(separator: "\n"),
                            reconstructedText: text,
                            filteredIngredientLines: layout.ingredientLines,
                            ignoredSourceLines: layout.ignoredInstructionLines,
                            sourceObservations: sourceObservations,
                            confidence: confidence,
                            layoutConfidence: layout.layoutConfidence,
                            layoutAmbiguityCount: layout.ambiguities.count,
                            ignoredInstructionLineCount: layout.ignoredInstructionLines.count
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

    private static func layoutObservations(
        from candidates: [(VNRecognizedTextObservation, VNRecognizedText, [OCRTextAlternative], [OCRTextAlternative])],
        pageIndex: Int
    ) -> [OCRTextObservation] {
        candidates.enumerated().flatMap { observationIndex, entry in
            let (observation, candidate, _, alternatives) = entry
            let ranges = bulletDelimitedRanges(in: candidate.string)
            let baseID = "page-\(pageIndex)-vision-\(observationIndex)"

            guard ranges.count > 1 else {
                return [
                    OCRTextObservation(
                        observationID: baseID,
                        text: candidate.string,
                        boundingBox: normalizedBox(observation.boundingBox),
                        confidence: Double(candidate.confidence),
                        pageIndex: pageIndex,
                        bulletMarker: RecipeOCRPolicy.leadingBulletMarker(in: candidate.string),
                        alternateCandidates: alternatives
                    )
                ]
            }

            let alternateSegments = alternatives.map { alternative in
                (alternative, bulletDelimitedSegments(in: alternative.text))
            }
            return ranges.enumerated().map { fragmentIndex, range in
                let fragment = String(candidate.string[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let rectangle = try? candidate.boundingBox(for: range)
                let box = rectangle?.boundingBox ?? observation.boundingBox
                let fragmentAlternatives = alternateSegments.compactMap {
                    alternative, segments -> OCRTextAlternative? in
                    guard segments.indices.contains(fragmentIndex) else { return nil }
                    let text = segments[fragmentIndex]
                    guard text.caseInsensitiveCompare(fragment) != .orderedSame else { return nil }
                    return OCRTextAlternative(text: text, confidence: alternative.confidence)
                }
                return OCRTextObservation(
                    observationID: baseID,
                    text: fragment,
                    boundingBox: normalizedBox(box),
                    confidence: Double(candidate.confidence),
                    pageIndex: pageIndex,
                    bulletMarker: RecipeOCRPolicy.leadingBulletMarker(in: fragment),
                    alternateCandidates: fragmentAlternatives
                )
            }
        }
    }

    private static func sourceObservations(
        from candidates: [(VNRecognizedTextObservation, VNRecognizedText, [OCRTextAlternative], [OCRTextAlternative])],
        pageIndex: Int
    ) -> [RecipeSourceObservation] {
        candidates.enumerated().map { observationIndex, entry in
            let (observation, candidate, alternatives, _) = entry
            let box = normalizedBox(observation.boundingBox)
            return RecipeSourceObservation(
                observationID: "page-\(pageIndex)-vision-\(observationIndex)",
                text: candidate.string,
                pageIndex: pageIndex,
                boundingBox: NormalizedSourceRect(
                    x: box.x,
                    y: box.y,
                    width: box.width,
                    height: box.height
                ),
                confidence: Double(candidate.confidence),
                alternatives: alternatives.map {
                    RecipeSourceTextAlternative(
                        text: $0.text,
                        confidence: $0.confidence
                    )
                }
            )
        }
    }

    private static func normalizedBox(_ box: CGRect) -> OCRNormalizedBoundingBox {
        OCRNormalizedBoundingBox(
            x: box.origin.x,
            y: box.origin.y,
            width: box.width,
            height: box.height
        )
    }

    private static func bulletDelimitedRanges(in text: String) -> [Range<String.Index>] {
        let starts = text.indices.filter { ["•", "☐", "✓"].contains(text[$0]) }
        guard starts.count > 1 else { return [] }
        return starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1] : text.endIndex
            return start..<end
        }
    }

    private static func bulletDelimitedSegments(in text: String) -> [String] {
        bulletDelimitedRanges(in: text).map {
            String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines)
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

    static func leadingBulletMarker(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
              ["•", "-", "*", "☐", "✓"].contains(String(first))
        else { return nil }
        return String(first)
    }

    static func shouldRunEnhancedPass(
        confidence: Float,
        layoutConfidence: Double,
        ambiguityCount: Int,
        sourceLineCount: Int
    ) -> Bool {
        confidence < 0.78
            || layoutConfidence < 0.78
            || ambiguityCount > 0
            || sourceLineCount < 2
    }

    static func qualityScore(
        confidence: Float,
        layoutConfidence: Double,
        ambiguityCount: Int,
        sourceLineCount: Int
    ) -> Double {
        let lineCoverage = min(1, Double(max(0, sourceLineCount)) / 4)
        let ambiguityPenalty = min(0.24, Double(max(0, ambiguityCount)) * 0.06)
        return min(
            1,
            max(
                0,
                (Double(confidence) * 0.48)
                    + (layoutConfidence * 0.36)
                    + (lineCoverage * 0.16)
                    - ambiguityPenalty
            )
        )
    }
}

enum RecipeImagePreprocessor {
    private static let maximumOCRPixelDimension: CGFloat = 2_600
    private static let renderingContext = CIContext(options: [.cacheIntermediates: true])

    static func downsampledImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maximumOCRPixelDimension),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    static func resizedForOCR(_ image: UIImage) -> UIImage {
        let normalized = normalizeOrientation(image)
        let longestSide = max(normalized.size.width, normalized.size.height)
        guard longestSide > maximumOCRPixelDimension else { return normalized }
        let scale = maximumOCRPixelDimension / longestSide
        let size = CGSize(
            width: max(1, normalized.size.width * scale),
            height: max(1, normalized.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: size))
        }
    }

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
        guard let cgImage = renderingContext.createCGImage(output, from: output.extent) else { return normalized }
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
