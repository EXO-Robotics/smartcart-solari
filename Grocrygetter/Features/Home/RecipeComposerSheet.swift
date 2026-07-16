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
    @State private var photoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
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
            selectedImage != nil && !recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                            color: GatherTheme.coral
                        )
                    }
                }
                .padding(18)
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(GatherTheme.canvas)
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
                selectedImage = image
                Task { await recognizeRecipe(in: image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task { await loadPhoto(photoItem) }
        }
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IMPORT FROM")
                .font(.caption2.weight(.heavy))
                .tracking(0.9)
                .foregroundStyle(GatherTheme.secondaryInk)

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
                buttonTitle: selectedImage == nil ? "Open camera" : "Retake photo",
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
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(selectedImage == nil ? "Choose recipe photo" : "Choose a different photo", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
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
                            .foregroundStyle(GatherTheme.navy)
                        Text("SmartCart looks for standard recipe ingredients embedded in the page.")
                            .font(.caption)
                            .foregroundStyle(GatherTheme.secondaryInk)
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
                    color: GatherTheme.green
                )
            }
            .gatherCard()

        case .recipeText:
            InfoBanner(
                symbol: "doc.on.clipboard.fill",
                title: "Paste and go",
                message: "One ingredient per line works best. You can correct names, quantities, and pantry status next.",
                color: GatherTheme.green
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
                            .foregroundStyle(index == selectedSampleIndex ? .white : GatherTheme.green)
                            .frame(width: 48, height: 48)
                            .background(index == selectedSampleIndex ? GatherTheme.green : GatherTheme.herbLight)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.title)
                                .font(.headline)
                                .foregroundStyle(GatherTheme.navy)
                            Text("\(recipe.ingredients.count) ingredients · \(recipe.servings) servings · \(recipe.totalMinutes)m")
                                .font(.caption)
                                .foregroundStyle(GatherTheme.secondaryInk)
                        }

                        Spacer()

                        Image(systemName: index == selectedSampleIndex ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(index == selectedSampleIndex ? GatherTheme.green : GatherTheme.border)
                    }
                    .gatherCard(padding: 13)
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
                    .foregroundStyle(GatherTheme.navy)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(GatherTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }

            Button(action: action) {
                Label(buttonTitle, systemImage: symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .gatherCard()
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if let selectedImage {
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
                            .background(GatherTheme.navy.opacity(0.86))
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }
                .clipped()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(GatherTheme.green)
                Text("Recipe image preview")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GatherTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(GatherTheme.herbLight.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }

    private var editableRecipeFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("RECIPE NAME")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(GatherTheme.secondaryInk)
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
                        .foregroundStyle(GatherTheme.secondaryInk)
                    Spacer()
                    Text("\(draftRecipe.ingredients.count) found")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GatherTheme.green)
                }

                TextEditor(text: $recipeText)
                    .font(.body)
                    .focused($focusedField, equals: .recipe)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 170)
                    .padding(10)
                    .background(GatherTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(GatherTheme.border, lineWidth: 1)
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
                        .foregroundStyle(GatherTheme.green)
                        .frame(width: 37, height: 37)
                        .background(GatherTheme.herbLight)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GatherTheme.navy)
                            .lineLimit(1)
                        Text(ingredient.category.rawValue)
                            .font(.caption2)
                            .foregroundStyle(GatherTheme.secondaryInk)
                    }

                    Spacer()

                    Text(ingredient.displayQuantity)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GatherTheme.secondaryInk)
                }
                .padding(12)
                .background(GatherTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(GatherTheme.border, lineWidth: 1)
                }
            }

            if draftRecipe.ingredients.count > 6 {
                Text("+ \(draftRecipe.ingredients.count - 6) more ingredients")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GatherTheme.green)
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

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isProcessing = true
        processingMessage = "Loading image…"
        errorMessage = nil
        defer { isProcessing = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                throw RecipeVisionError.unreadableImage
            }
            selectedImage = image
            await recognizeRecipe(in: image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recognizeRecipe(in image: UIImage) async {
        isProcessing = true
        processingMessage = "Reading recipe text…"
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let recognized = try await RecipeVisionReader.recognizeText(in: image)
            processingMessage = "Normalizing ingredients…"
            recipeText = recognized
            if let firstLine = recognized
                .components(separatedBy: .newlines)
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty && $0.range(of: #"\d"#, options: .regularExpression) == nil }) {
                title = String(firstLine.prefix(60))
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
            appModel.beginRecipe(draftRecipe)
        }
    }
}

private enum RecipeVisionReader {
    static func recognizeText(in image: UIImage) async throws -> String {
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
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if text.isEmpty {
                    continuation.resume(throwing: RecipeVisionError.noTextFound)
                } else {
                    continuation.resume(returning: text)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

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
