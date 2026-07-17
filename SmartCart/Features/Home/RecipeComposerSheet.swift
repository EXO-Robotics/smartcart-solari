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
        RecipeParser.parse(
            title: title,
            text: recipeText,
            source: source(for: selectedMethod),
            sourceDetail: sourceDetail
        )
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

    private var canImport: Bool {
        switch selectedMethod {
        case .camera, .photoLibrary:
            !selectedImages.isEmpty && !recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .recipeLink, .pinterest:
            validURL != nil
        case .recipeText:
            !recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .background(SmartCartTheme.canvas)
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
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.right")
                                }
                            }
                            HStack {
                                Text("Import")
                                Spacer()
                                if isProcessing {
                                    ProgressView()
                                        .tint(.white)
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
                .font(.caption2.weight(.heavy))
                .tracking(0.9)
                .foregroundStyle(SmartCartTheme.secondaryInk)

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
                            .foregroundStyle(index == selectedSampleIndex ? .white : SmartCartTheme.green)
                            .frame(width: 48, height: 48)
                            .background(index == selectedSampleIndex ? SmartCartTheme.green : SmartCartTheme.herbLight)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

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
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(SmartCartTheme.navy.opacity(0.86))
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selectedImages.count > 1 {
                        Label("\(selectedImages.count) pages", systemImage: "doc.on.doc.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(SmartCartTheme.navy.opacity(0.86))
                            .clipShape(Capsule())
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
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                TextField("Recipe name", text: $title)
                    .font(.headline)
                    .focused($focusedField, equals: .title)
                    .smartField()
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("INGREDIENT TEXT")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
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
            let result = try await RecipeVisionReader.recognizeText(in: images)
            processingMessage = "Normalizing ingredients…"
            recipeText = result.text
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
                sourceDetail: sourceDetail
            )
            appModel.lastImportReport = RecipeParser.importReport(
                for: recipe,
                recognizedText: result.text,
                sourcePageCount: result.pageCount,
                retryCount: result.retryCount,
                duration: result.duration
            )
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
            appModel.beginRecipe(draftRecipe)
        }
    }
}

private enum RecipeVisionReader {
    struct Result {
        var text: String
        var pageCount: Int
        var retryCount: Int
        var duration: TimeInterval
        var confidence: Float
    }

    static func recognizeText(in images: [UIImage]) async throws -> Result {
        let startedAt = Date()
        var pages: [String] = []
        var retryCount = 0
        var confidenceTotal: Float = 0

        for image in images {
            do {
                let page = try await recognizeText(in: image, level: .accurate, minimumTextHeight: 0.008)
                pages.append(page.text)
                confidenceTotal += page.confidence
            } catch {
                retryCount += 1
                let page = try await recognizeText(in: image, level: .fast, minimumTextHeight: 0.004)
                pages.append(page.text)
                confidenceTotal += page.confidence
            }
        }

        let combined = pages.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else { throw RecipeVisionError.noTextFound }
        return Result(
            text: combined,
            pageCount: images.count,
            retryCount: retryCount,
            duration: Date().timeIntervalSince(startedAt),
            confidence: confidenceTotal / Float(max(1, images.count))
        )
    }

    private static func recognizeText(
        in image: UIImage,
        level: VNRequestTextRecognitionLevel,
        minimumTextHeight: Float
    ) async throws -> (text: String, confidence: Float) {
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
                let candidates = observations.compactMap { $0.topCandidates(1).first }
                let lines = candidates.map(\.string)
                let text = lines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if text.isEmpty {
                    continuation.resume(throwing: RecipeVisionError.noTextFound)
                } else {
                    let confidence = candidates.reduce(Float.zero) { $0 + $1.confidence } / Float(max(1, candidates.count))
                    continuation.resume(returning: (text, confidence))
                }
            }
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = minimumTextHeight

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
