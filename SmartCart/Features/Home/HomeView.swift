import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var clipboardContainsProbableWebURL = false
    @State private var pastedIngredients = ""
    @State private var pendingDiscardSession: ShoppingSession?
    @State private var shoppingTripsExpanded =
        ProcessInfo.processInfo.environment["SMARTCART_HOME_TRIPS_DRAWER"] == "shopping-trips"
    @GestureState private var shoppingTripsDrag: CGFloat = 0
    @FocusState private var pasteIngredientsFocused: Bool

    private let homeActionCardContentMinHeight: CGFloat = 116
    private let collapsedShoppingTripsDrawerHeight: CGFloat = 92

    var body: some View {
        GeometryReader { geometry in
            let drawerHeight = max(420, geometry.size.height - 88)
            let collapsedOffset = drawerHeight - collapsedShoppingTripsDrawerHeight

            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        startShoppingSection
                        if appModel.hasCompletedShoppingTrip,
                           let recipe = appModel.mostRecentShoppedRecipe {
                            shopAgainCard(recipe)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, collapsedShoppingTripsDrawerHeight + 34)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    pasteIngredientsFocused = false
                }

                continueShoppingTripsDrawer(
                    height: drawerHeight,
                    collapsedOffset: collapsedOffset
                )
                .offset(y: shoppingTripsDrawerOffset(collapsedOffset: collapsedOffset))
                .animation(
                    .spring(response: 0.42, dampingFraction: 0.86),
                    value: shoppingTripsExpanded
                )
            }
        }
        .scrollIndicators(.hidden)
        .smartCartBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: shoppingTripsExpanded)
        .onAppear(perform: refreshClipboardDetection)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshClipboardDetection()
            }
        }
        .confirmationDialog(
            "Discard this paused trip?",
            isPresented: Binding(
                get: { pendingDiscardSession != nil },
                set: { isPresented in
                    if !isPresented { pendingDiscardSession = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDiscardSession {
                Button("Discard Trip", role: .destructive) {
                    appModel.discardPendingShoppingSession(pendingDiscardSession.id)
                    self.pendingDiscardSession = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDiscardSession = nil
            }
        } message: {
            Text("This removes the unfinished trip and its generated list. Completed shopping history is never deleted here.")
        }
    }

    private var header: some View {
        SmartCartLogo()
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    private var startShoppingSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Start a Shopping Trip")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.ink)
                .frame(maxWidth: .infinity, alignment: .center)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    primaryImportButton(.camera)
                    primaryImportButton(.photoLibrary)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    primaryImportButton(.camera)
                    primaryImportButton(.photoLibrary)
                }
            }

            pasteIngredientsCard

            if clipboardContainsProbableWebURL {
                pasteCopiedLinkButton
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    pasteLinkButton
                    moreImportMenu
                }
                VStack(spacing: 10) {
                    pasteLinkButton
                    moreImportMenu
                }
            }

            mealPrepLaunchButton
        }
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
                minHeight: homeActionCardContentMinHeight,
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
            .frame(maxWidth: .infinity, minHeight: homeActionCardContentMinHeight, alignment: .leading)
            .smartCartCard(padding: 16)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("home-start-meal-prep")
        .accessibilityLabel("Meal Prep Mode")
        .accessibilityHint("Combine up to five saved recipes into one shopping trip")
    }

    private var pasteIngredientsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "doc.on.clipboard")
                    .font(.title2.bold())
                    .foregroundStyle(SmartCartTheme.onAccent)
                    .frame(width: 50, height: 50)
                    .background(SmartCartTheme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                ZStack(alignment: .leading) {
                    if pastedIngredients.isEmpty {
                        Text("Paste Ingredients Here")
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }

                    TextEditor(text: $pastedIngredients)
                        .font(.body)
                        .foregroundStyle(SmartCartTheme.navy)
                        .scrollContentBackground(.hidden)
                        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62)
                        .focused($pasteIngredientsFocused)
                }

                Spacer(minLength: 4)

                Button {
                    appModel.openImporter(.recipeText, initialText: pastedIngredients)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(SmartCartTheme.green)
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, -36)
                .accessibilityIdentifier("home-paste-ingredients-continue")
                .accessibilityLabel("Continue with pasted ingredients")
                .accessibilityHint("Opens the recipe text importer with these ingredients")
            }
            .frame(maxWidth: .infinity, minHeight: homeActionCardContentMinHeight, alignment: .leading)
        }
        .smartCartCard(padding: 16)
        .accessibilityIdentifier("home-paste-ingredients")
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

    private var pasteCopiedLinkButton: some View {
        Button(action: pasteLinkFromClipboard) {
            HStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paste Copied Link")
                    Text("A web link is ready")
                        .font(.caption2.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("home-paste-copied-link")
        .accessibilityHint("Reads the copied web link and opens the recipe link importer")
    }

    private var moreImportMenu: some View {
        Menu {
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
        .accessibilityHint("Shows saved recipe and sample options")
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

    private func refreshClipboardDetection() {
        let probableWebURL: PartialKeyPath<UIPasteboard.DetectedValues> = \.probableWebURL
        UIPasteboard.general.detectPatterns(for: [probableWebURL]) { result in
            let containsWebURL = (try? result.get())?.contains(probableWebURL) == true
            DispatchQueue.main.async {
                clipboardContainsProbableWebURL = containsWebURL
            }
        }
    }

    private func pasteLinkFromClipboard() {
        // Reading pasteboard contents is intentionally confined to this explicit tap.
        let pasteboard = UIPasteboard.general
        let copiedText = pasteboard.url?.absoluteString ?? pasteboard.string
        let validatedText = copiedText.flatMap(RecipeLinkInput.validHTTPSURL(from:))?.absoluteString
        appModel.openImporter(.recipeLink, initialText: validatedText)
    }

    private func continueShoppingTripsDrawer(height: CGFloat, collapsedOffset: CGFloat) -> some View {
        VStack(spacing: 0) {
            continueShoppingTripsHandle(collapsedOffset: collapsedOffset)

            Divider()
                .overlay(SmartCartTheme.border)

            if shoppingTripsExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        if appModel.pendingShoppingSessions.isEmpty {
                            InfoBanner(
                                symbol: "cart.badge.clock",
                                title: "No paused trips",
                                message: "Start a shopping trip and SmartCart will keep it here if you pause before finishing.",
                                color: SmartCartTheme.green
                            )
                        } else {
                            ForEach(appModel.pendingShoppingSessions) { session in
                                continueShoppingTripRow(session)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
                .transition(.opacity)
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(SmartCartTheme.scannerSurface)
        .clipShape(HomePullUpShape())
        .overlay {
            HomePullUpShape()
                .stroke(SmartCartTheme.borderStrong.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: -8)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
    }

    private func continueShoppingTripsHandle(collapsedOffset: CGFloat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: shoppingTripsExpanded ? "chevron.compact.down" : "chevron.compact.up")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(SmartCartTheme.green)
                .frame(height: 35)

            HStack(spacing: 9) {
                Label("Continue Shopping Trips", systemImage: "cart.badge.clock")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.ink)

                Spacer()

                Text(shoppingTripsExpanded ? "Swipe down to hide" : "Swipe up to continue")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .frame(height: collapsedShoppingTripsDrawerHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            pasteIngredientsFocused = false
            shoppingTripsExpanded.toggle()
        }
        .gesture(shoppingTripsDragGesture(collapsedOffset: collapsedOffset))
        .accessibilityLabel("Continue Shopping Trips drawer")
        .accessibilityValue(shoppingTripsExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(shoppingTripsExpanded ? "Swipe down to hide paused shopping trips" : "Swipe up to show paused shopping trips")
        .accessibilityAddTraits(.isButton)
    }

    private func continueShoppingTripRow(_ session: ShoppingSession) -> some View {
        HStack(spacing: 12) {
            Button {
                appModel.openShoppingSession(session.id)
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: session.isGuideComplete ? "checkmark.circle.fill" : "cart.fill")
                        .font(.title3.bold())
                        .foregroundStyle(SmartCartTheme.green)
                        .frame(width: 42, height: 42)
                        .background(SmartCartTheme.herbLight)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.isGuideComplete ? "PANTRY UPDATE PENDING" : "RESUME SHOPPING")
                            .smartEyebrow()
                        Text(session.recipeTitle)
                            .font(.headline)
                            .foregroundStyle(SmartCartTheme.navy)
                            .multilineTextAlignment(.leading)
                        Text(continueShoppingTripDetail(session))
                            .font(.caption)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(SmartCartTheme.green)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("home-continue-shopping-\(session.id.uuidString)")

            Button(role: .destructive) {
                if session.isGuideComplete {
                    appModel.archivePantryUpdateReminder(sessionID: session.id)
                } else {
                    pendingDiscardSession = session
                }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .frame(width: 36, height: 36)
                    .background(SmartCartTheme.paper.opacity(0.64))
                    .clipShape(Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                session.isGuideComplete
                    ? "Archive pantry update reminder for \(session.recipeTitle)"
                    : "Discard \(session.recipeTitle)"
            )
            .accessibilityHint(
                session.isGuideComplete
                    ? "Hides this reminder while retaining the completed shopping trip in history"
                    : "Removes this paused shopping trip from SmartCart"
            )
        }
        .smartCartCard(padding: 13)
    }

    private func continueShoppingTripDetail(_ session: ShoppingSession) -> String {
        let completed = session.items.filter(\.status.isCompleted).count
        if session.isGuideComplete {
            return "Shopping results ready"
        }
        let remaining = session.items.count - completed
        return "\(remaining) item\(remaining == 1 ? "" : "s") remaining"
    }

    private func shoppingTripsDrawerOffset(collapsedOffset: CGFloat) -> CGFloat {
        let restingOffset = shoppingTripsExpanded ? 0 : collapsedOffset
        return min(max(restingOffset + shoppingTripsDrag, 0), collapsedOffset)
    }

    private func shoppingTripsDragGesture(collapsedOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($shoppingTripsDrag) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.height
                let decisiveDistance = min(96, collapsedOffset * 0.22)

                if shoppingTripsExpanded {
                    if projected > decisiveDistance {
                        shoppingTripsExpanded = false
                    }
                } else if projected < -decisiveDistance {
                    shoppingTripsExpanded = true
                }
            }
    }
}

/// A bottom drawer shape shared only by Home's retained shopping-trip surface.
/// The raised center handle makes the vertical swipe affordance visible above
/// the tab bar without introducing a second navigation control.
private struct HomePullUpShape: Shape {
    func path(in rect: CGRect) -> Path {
        let top: CGFloat = 34
        let cornerRadius: CGFloat = 26
        let handleRadius: CGFloat = 36
        let centerX = rect.midX

        var path = Path()
        path.move(to: CGPoint(x: cornerRadius, y: top))
        path.addLine(to: CGPoint(x: centerX - handleRadius, y: top))
        path.addCurve(
            to: CGPoint(x: centerX, y: 0),
            control1: CGPoint(x: centerX - 23, y: top),
            control2: CGPoint(x: centerX - 28, y: 0)
        )
        path.addCurve(
            to: CGPoint(x: centerX + handleRadius, y: top),
            control1: CGPoint(x: centerX + 28, y: 0),
            control2: CGPoint(x: centerX + 23, y: top)
        )
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: top + cornerRadius),
            control: CGPoint(x: rect.maxX, y: top)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY - cornerRadius),
            control: CGPoint(x: 0, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: 0, y: top + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: cornerRadius, y: top),
            control: CGPoint(x: 0, y: top)
        )
        path.closeSubpath()
        return path
    }
}
