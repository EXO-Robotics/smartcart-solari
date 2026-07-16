import SwiftUI

struct RecipeComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var title = "Lemon Herb Sheet Pan Chicken"
    @State private var recipeText = """
    4 chicken thighs
    1 lb baby potatoes
    2 lemons
    4 cloves garlic
    2 tbsp olive oil
    1 tsp dried oregano
    6 oz green beans
    """
    @State private var selectedInput = RecipeInputMode.paste
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case recipe
    }

    private enum RecipeInputMode: String, CaseIterable, Identifiable {
        case paste = "Paste"
        case type = "Type"
        case photo = "Photo"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .paste: "doc.on.clipboard"
            case .type: "keyboard"
            case .photo: "camera.fill"
            }
        }
    }

    private var parsedRecipe: Recipe {
        RecipeParser.parse(title: title, text: recipeText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    inputModePicker
                    recipeFields
                    detectedIngredients
                }
                .padding(20)
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(GatherTheme.canvas)
            .navigationTitle("New recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                addButton
            }
        }
        .presentationDetents([.large])
    }

    private var inputModePicker: some View {
        HStack(spacing: 10) {
            ForEach(RecipeInputMode.allCases) { mode in
                Button {
                    selectedInput = mode
                    if mode == .photo {
                        appModel.showToast("Photo scanning is ready for a camera integration")
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: mode.symbol)
                            .font(.headline)
                        Text(mode.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(selectedInput == mode ? .white : GatherTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(selectedInput == mode ? GatherTheme.herb : GatherTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(GatherTheme.border, lineWidth: selectedInput == mode ? 0 : 1)
                    }
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var recipeFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Recipe name")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GatherTheme.secondaryInk)
                    .textCase(.uppercase)
                TextField("Sunday pasta", text: $title)
                    .font(.title3.weight(.semibold))
                    .focused($focusedField, equals: .title)
                    .padding(15)
                    .background(GatherTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Ingredients")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GatherTheme.secondaryInk)
                        .textCase(.uppercase)
                    Spacer()
                    Text("\(parsedRecipe.ingredients.count) found")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GatherTheme.herb)
                }

                TextEditor(text: $recipeText)
                    .font(.body)
                    .focused($focusedField, equals: .recipe)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .padding(10)
                    .background(GatherTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(GatherTheme.border, lineWidth: 1)
                    }
            }
        }
    }

    private var detectedIngredients: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ready for your cart")

            ForEach(parsedRecipe.ingredients) { ingredient in
                HStack(spacing: 12) {
                    Image(systemName: ingredient.category.symbol)
                        .font(.subheadline.bold())
                        .foregroundStyle(GatherTheme.herb)
                        .frame(width: 38, height: 38)
                        .background(GatherTheme.herbLight)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GatherTheme.ink)
                        Text(ingredient.category.rawValue)
                            .font(.caption)
                            .foregroundStyle(GatherTheme.secondaryInk)
                    }

                    Spacer()

                    Text(ingredient.displayQuantity)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GatherTheme.secondaryInk)
                }
                .padding(13)
                .background(GatherTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var addButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                appModel.addRecipe(parsedRecipe)
                dismiss()
            } label: {
                HStack {
                    Text("Add to meal plan")
                    Spacer()
                    Text("\(parsedRecipe.ingredients.count) items")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.78)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(16)
            .background(.ultraThinMaterial)
        }
    }
}
