import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header
                recipeImportCard
                weeknightSection
                storePlanCard
                pantryPulseCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .background(GatherTheme.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GatherTheme.secondaryInk)
                Text("What sounds good?")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(GatherTheme.ink)
            }

            Spacer()

            Button {
                appModel.presentedSheet = .storePicker
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 43))
                        .foregroundStyle(GatherTheme.herb)
                    Circle()
                        .fill(GatherTheme.tomato)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(GatherTheme.canvas, lineWidth: 2))
                }
            }
            .accessibilityLabel("Profile and store settings")
        }
        .padding(.top, 8)
    }

    private var recipeImportCard: some View {
        Button {
            appModel.presentedSheet = .recipeComposer
        } label: {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.17))
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Turn a recipe into a cart")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Paste it, type it, or start from a photo")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.headline)
                    .padding(10)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .foregroundStyle(.white)
            .padding(20)
            .background {
                LinearGradient(
                    colors: [GatherTheme.herb, Color(red: 0.32, green: 0.52, blue: 0.31)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
            }
            .gatherShadow()
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var weeknightSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "This week’s table", actionTitle: "See all") {
                appModel.showToast("Your full meal plan is ready")
            }

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(appModel.recipes) { recipe in
                        Button {
                            appModel.addRecipeIngredientsToCart(recipe)
                        } label: {
                            RecipeCard(recipe: recipe)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("Add ingredients for \(recipe.title)")
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 12)
            }
            .contentMargins(.horizontal, -2, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }

    private var storePlanCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shopping route")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(GatherTheme.ink)
                    Text(appModel.storeStrategy == .smartSplit ? "Smart Split is saving you money" : "Everything is going to one store")
                        .font(.subheadline)
                        .foregroundStyle(GatherTheme.secondaryInk)
                }

                Spacer()

                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.title3.bold())
                    .foregroundStyle(GatherTheme.herb)
                    .frame(width: 44, height: 44)
                    .background(GatherTheme.herbLight)
                    .clipShape(Circle())
            }

            HStack(spacing: 10) {
                ForEach(appModel.selectedStores) { store in
                    StorePill(store: store)
                }

                Button {
                    appModel.presentedSheet = .storePicker
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(GatherTheme.herb)
                        .frame(width: 34, height: 34)
                        .background(GatherTheme.herb.opacity(0.10))
                        .clipShape(Circle())
                }
            }

            Divider()

            HStack {
                StatChip(
                    symbol: "tag.fill",
                    text: "\(appModel.estimatedSavings.formatted(.currency(code: "USD"))) saved"
                )
                StatChip(symbol: "car.fill", text: "\(appModel.selectedStores.count) stops", color: GatherTheme.tomato)
                Spacer()
                Button("Adjust") {
                    appModel.presentedSheet = .storePicker
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(GatherTheme.herb)
            }
        }
        .gatherCard()
    }

    private var pantryPulseCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "cabinet.fill")
                .font(.title2)
                .foregroundStyle(GatherTheme.tomato)
                .frame(width: 52, height: 52)
                .background(GatherTheme.peach.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Pantry pulse")
                    .font(.headline)
                    .foregroundStyle(GatherTheme.ink)
                Text("Gather skipped 3 basics you likely have.")
                    .font(.subheadline)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(Color.gray.opacity(0.6))
        }
        .gatherCard(padding: 16)
    }
}
