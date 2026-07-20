import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let primaryImportCardMinimumHeight: CGFloat = 154
    private let homeActionCardMinimumHeight: CGFloat = 104

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                startNewRecipeSection
                if !appModel.pendingShoppingSessions.isEmpty {
                    shoppingTripsSection
                }
                if appModel.hasCompletedShoppingTrip,
                   let recipe = appModel.mostRecentShoppedRecipe {
                    shopAgainCard(recipe)
                }
                storeCard
                trustStrip
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .smartCartBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            SmartCartLogo()

            Spacer()

            Button {
                appModel.selectedTab = .account
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(SmartCartTheme.navy)
                    Circle()
                        .fill(SmartCartTheme.green)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(SmartCartTheme.canvas, lineWidth: 2))
                }
            }
            .accessibilityLabel("Open account")
        }
        .padding(.top, 8)
    }

    private var startNewRecipeSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "Start New Recipe",
                subtitle: "Choose how to bring in the recipe you want to shop"
            )

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    primaryImportButton(.camera)
                    primaryImportButton(.photoLibrary)
                    pasteLinkButton
                    moreImportMenu
                }
            } else {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        primaryImportButton(.camera)
                        primaryImportButton(.photoLibrary)
                    }
                    GridRow {
                        pasteLinkButton
                        moreImportMenu
                    }
                }
            }

            mealPrepLaunchButton
        }
        .accessibilityIdentifier("home-start-new-recipe")
    }

    private func primaryImportButton(_ method: ImportMethod) -> some View {
        Button {
            appModel.openImporter(method)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: method.symbol)
                    .font(.title2.bold())
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .frame(width: 48, height: 48)
                    .background(method.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(method == .camera ? "Take Photo" : "Choose Photo")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text(method == .camera ? "Snap a cookbook or card" : "Choose a saved recipe image")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: dynamicTypeSize.isAccessibilitySize
                    ? nil
                    : primaryImportCardMinimumHeight,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .smartCartCard(padding: 16)
            .smartCartShadow()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier(method == .camera ? "home-import-camera" : "home-import-photos")
        .accessibilityHint(method == .camera ? "Opens the camera recipe importer" : "Opens the photo recipe importer")
    }

    private var mealPrepLaunchButton: some View {
        Button {
            appModel.startMealPrepDraft()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2.bold())
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .frame(width: 50, height: 50)
                    .background(SmartCartTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Meal Prep Mode")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Combine up to five saved recipes")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(SmartCartTheme.green)
            }
            .frame(minHeight: homeActionCardMinimumHeight)
            .smartCartCard(padding: 14)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("home-start-meal-prep")
        .accessibilityLabel("Meal Prep Mode")
        .accessibilityHint("Combine up to five saved recipes into one shopping trip")
    }

    private var pasteLinkButton: some View {
        Button {
            appModel.openImporter(.recipeLink)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "link")
                Text("Paste Link")
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("home-import-paste-link")
        .accessibilityHint("Opens the recipe link importer without reading the clipboard")
    }

    private var moreImportMenu: some View {
        Menu {
            Button {
                appModel.openImporter(.recipeText)
            } label: {
                Label("Paste Recipe Text", systemImage: "doc.on.clipboard.fill")
            }
            .accessibilityIdentifier("home-import-text")

            Button {
                appModel.selectedTab = .lists
            } label: {
                Label("Saved Recipes", systemImage: "book.fill")
            }
            .accessibilityIdentifier("home-open-saved-recipes")

            Button {
                appModel.openImporter(.sample)
            } label: {
                Label("Try a Sample", systemImage: "takeoutbag.and.cup.and.straw.fill")
            }
            .accessibilityIdentifier("home-import-sample")
        } label: {
            HStack {
                Label("More", systemImage: "ellipsis.circle.fill")
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("home-import-more")
        .accessibilityHint("Shows recipe text, saved recipe, and sample options")
    }

    private func shopAgainCard(_ recipe: Recipe) -> some View {
        Button {
            appModel.beginRecipe(recipe)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 15) {
                    shopAgainIdentity(recipe)
                    Spacer(minLength: 8)
                    Label("Shop Again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.onAccent)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(SmartCartTheme.green)
                        .clipShape(Capsule())
                }
                VStack(alignment: .leading, spacing: 14) {
                    shopAgainIdentity(recipe)
                    Label("Shop Again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(SmartCartTheme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .smartCartCard(padding: 16)
            .smartCartShadow()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("home-shop-again")
        .accessibilityLabel("Shop \(recipe.title) again")
        .accessibilityHint("Opens a fresh Recipe Ready review for this recipe")
    }

    private func shopAgainIdentity(_ recipe: Recipe) -> some View {
        HStack(spacing: 13) {
            Image(systemName: recipe.heroSymbol)
                .font(.title2.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 48, height: 48)
                .background(SmartCartTheme.herbLight)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("SHOP AGAIN")
                    .smartEyebrow()
                Text(recipe.title)
                    .font(.headline)
                    .foregroundStyle(SmartCartTheme.navy)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pendingShoppingCard(_ session: ShoppingSession) -> some View {
        let completed = session.items.filter { $0.status.isCompleted }.count
        let isGuideComplete = !session.items.isEmpty && completed == session.items.count
        let retailerName = session.items.first
            .flatMap { ShoppingRetailer(rawValue: $0.product.retailerID) }?
            .configuration.displayName ?? "Retailer"

        return Button {
            appModel.openShoppingSession(session.id)
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(SmartCartTheme.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isGuideComplete ? "PANTRY UPDATE PENDING" : "RESUME SHOPPING")
                        .smartEyebrow()
                    Text(isGuideComplete ? "Update pantry for \(session.recipeTitle)" : "Continue \(session.recipeTitle)")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("\(retailerName) · \(isGuideComplete ? "Shopping complete" : "\(session.items.count - completed) remaining")")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .foregroundStyle(SmartCartTheme.green)
            }
            .frame(minHeight: homeActionCardMinimumHeight)
            .smartCartCard(padding: 16)
            .shadow(color: SmartCartTheme.softShadow, radius: 12, y: 6)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier(
            "\(isGuideComplete ? "home-pantry-update-pending" : "home-resume-shopping")-\(session.id.uuidString)"
        )
    }

    private var shoppingTripsSection: some View {
        let sessions = appModel.pendingShoppingSessions

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Shopping Trips",
                subtitle: "Resume a trip or finish its pantry update"
            )

            if sessions.count == 1, let session = sessions.first {
                pendingShoppingCard(session)
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(sessions) { session in
                        pendingShoppingCard(session)
                    }
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(sessions) { session in
                            pendingShoppingCard(session)
                                .containerRelativeFrame(
                                    .horizontal,
                                    count: 10,
                                    span: 9,
                                    spacing: 10
                                )
                                .id(session.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 1, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .accessibilityIdentifier("home-shopping-trips")
    }

    private var storeCard: some View {
        Button {
            appModel.selectedTab = .store
        } label: {
            HStack(spacing: 14) {
                StoreMark(size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your preferred store")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SmartCartTheme.green)
                        .textCase(.uppercase)
                    Text(appModel.retailerConfiguration.displayName)
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Shopping Trip · Opens in Safari")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .foregroundStyle(SmartCartTheme.secondaryInk.opacity(0.6))
            }
            .smartCartCard(padding: 14)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var trustStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(SmartCartTheme.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("Your checkout stays with the retailer")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                Text("SmartCart never asks for retailer credentials or payment.")
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SmartCartTheme.herbLight.opacity(0.65))
        .smartCartCardEdge(radius: 20, elevated: false)
    }
}
