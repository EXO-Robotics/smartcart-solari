import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingDiscardSession: ShoppingSession?
    @State private var shoppingTripsExpanded = false
    @GestureState private var shoppingTripsDrag: CGFloat = 0

    private let collapsedShoppingTripsDrawerHeight: CGFloat = 92
    private let workspaceTransition: Namespace.ID?

    init(workspaceTransition: Namespace.ID? = nil) {
        self.workspaceTransition = workspaceTransition
    }

    var body: some View {
        GeometryReader { geometry in
            let drawerHeight = max(420, geometry.size.height - 88)
            let collapsedOffset = drawerHeight - collapsedShoppingTripsDrawerHeight
            let hasPausedTrips = !pausedShoppingSessions.isEmpty

            ZStack(alignment: .bottom) {
                SmartCartFoodBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        startShoppingSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(
                        .bottom,
                        hasPausedTrips ? collapsedShoppingTripsDrawerHeight + 24 : 36
                    )
                }
                .scrollIndicators(.hidden)

                if hasPausedTrips {
                    continueShoppingTripsDrawer(
                        height: drawerHeight,
                        collapsedOffset: collapsedOffset
                    )
                    .offset(y: shoppingTripsDrawerOffset(collapsedOffset: collapsedOffset))
                    .animation(
                        reduceMotion ? nil : SmartCartMotion.signature,
                        value: shoppingTripsExpanded
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: shoppingTripsExpanded)
        .onChange(of: pausedShoppingSessions.map(\.id)) { _, sessionIDs in
            if sessionIDs.isEmpty {
                shoppingTripsExpanded = false
                pendingDiscardSession = nil
            }
        }
        .confirmationDialog(
            "Clear this paused order?",
            isPresented: Binding(
                get: { pendingDiscardSession != nil },
                set: { isPresented in
                    if !isPresented { pendingDiscardSession = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDiscardSession {
                Button("Clear Order", role: .destructive) {
                    appModel.discardPendingShoppingSession(pendingDiscardSession.id)
                    self.pendingDiscardSession = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDiscardSession = nil
            }
        } message: {
            Text("This removes the paused shopping trip and its generated list. Completed order history is not affected.")
        }
    }

    private var header: some View {
        ZStack {
            SmartCartLogo()
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                moreImportMenu
            }
        }
        .padding(.top, 8)
    }

    private var startShoppingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start a Shopping Trip")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(homeInk)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            startShoppingPanel
        }
    }

    @ViewBuilder
    private var startShoppingPanel: some View {
        let panel = VStack(spacing: 14) {
            Image(systemName: "camera")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(homeInk)
                .frame(width: 72, height: 72)
                .background(homeIconBackground)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(homeBorder, lineWidth: 1)
                }
                .accessibilityHidden(true)

            Button {
                appModel.openImporter(.camera)
            } label: {
                Text("Take Photo")
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(HomePrimaryButtonStyle())
            .accessibilityIdentifier("home-import-camera")
            .accessibilityHint("Opens the camera recipe importer")

            Button {
                appModel.openImporter(.photoLibrary)
            } label: {
                Text("Choose Photo")
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(HomeSecondaryButtonStyle())
            .accessibilityIdentifier("home-import-photos")
            .accessibilityHint("Opens the photo recipe importer")

            Button(action: pasteRecipeFromClipboard) {
                HStack(spacing: 11) {
                    Image(systemName: "doc.on.clipboard")
                        .accessibilityHidden(true)
                    Text("Paste Recipe")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .accessibilityHidden(true)
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(homeInk)
                .frame(maxWidth: .infinity, minHeight: 82)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("home-paste-recipe")
            .accessibilityHint("Pastes recipe text or a copied recipe link")

            Divider()
                .overlay(homeBorder)

            mealPrepLaunchButton
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .background {
            HomeGlassSurface(radius: 30, darkness: 0.16)
        }

        if let workspaceTransition {
            panel.smartCartTransitionSource(
                id: SmartCartTransitionID.recipeWorkspace,
                in: workspaceTransition
            )
        } else {
            panel
        }
    }

    private var mealPrepLaunchButton: some View {
        Button {
            appModel.startMealPrepDraft()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SmartCartTheme.green)
                    .frame(width: 44, height: 44)
                    .background(homeIconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Meal Prep Mode")
                        .font(.headline)
                        .foregroundStyle(homeInk)
                    Text("Combine up to five saved recipes")
                        .font(.caption)
                        .foregroundStyle(homeSecondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(homeSecondaryInk)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-start-meal-prep")
        .accessibilityHint("Starts a separate workflow that combines up to five saved recipes")
    }

    private var moreImportMenu: some View {
        Menu {
            Button {
                appModel.openImporter(.recipeText)
            } label: {
                Label("Enter Manually", systemImage: "keyboard")
            }
            .accessibilityIdentifier("home-import-manual")

            Button {
                appModel.openImporter(.sample)
            } label: {
                Label("Try a Sample", systemImage: "takeoutbag.and.cup.and.straw.fill")
            }
            .accessibilityIdentifier("home-import-sample")
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.bold())
                .foregroundStyle(homeInk)
                .rotationEffect(.degrees(90))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("home-import-more")
        .accessibilityLabel("More options")
        .accessibilityHint("Shows manual entry and sample recipe options")
    }

    private var pausedShoppingSessions: [ShoppingSession] {
        appModel.pendingShoppingSessions.filter(\.isReusable)
    }

    private func continueShoppingTripsDrawer(
        height: CGFloat,
        collapsedOffset: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            continueShoppingTripsHandle(collapsedOffset: collapsedOffset)

            Divider()
                .overlay(SmartCartTheme.border)

            if shoppingTripsExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(pausedShoppingSessions) { session in
                            pausedShoppingTripRow(session)
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
        .background {
            ZStack(alignment: .top) {
                WoodGrainBackground()
                HomeGlassSurface(radius: 30, darkness: 0.28)
                    .frame(height: collapsedShoppingTripsDrawerHeight)
            }
        }
        .clipShape(HomePullUpShape())
        .overlay {
            HomePullUpShape()
                .stroke(SmartCartTheme.borderStrong.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 22, y: -8)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
    }

    private func continueShoppingTripsHandle(collapsedOffset: CGFloat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: shoppingTripsExpanded ? "chevron.compact.down" : "chevron.compact.up")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(SmartCartTheme.green)
                .frame(height: 35)
                .accessibilityHidden(true)

            HStack(spacing: 9) {
                Label("Continue Shopping", systemImage: "cart.badge.clock")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(homeInk)

                Spacer()

                Text(shoppingTripsExpanded ? "Swipe down to hide" : pausedOrdersCountText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(homeSecondaryInk)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .frame(height: collapsedShoppingTripsDrawerHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            shoppingTripsExpanded.toggle()
        }
        .gesture(shoppingTripsDragGesture(collapsedOffset: collapsedOffset))
        .accessibilityLabel("Continue Shopping drawer")
        .accessibilityValue(shoppingTripsExpanded ? "Expanded" : "Collapsed, \(pausedOrdersCountText)")
        .accessibilityHint(
            shoppingTripsExpanded
                ? "Swipe down or double tap to hide paused orders"
                : "Swipe up or double tap to show paused orders"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home-continue-shopping-drawer")
    }

    private var pausedOrdersCountText: String {
        let count = pausedShoppingSessions.count
        return "\(count) paused order\(count == 1 ? "" : "s")"
    }

    private func pausedShoppingTripRow(_ session: ShoppingSession) -> some View {
        HStack(spacing: 10) {
            Button {
                appModel.openShoppingSession(session.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cart.fill")
                        .font(.headline.bold())
                        .foregroundStyle(SmartCartTheme.green)
                        .frame(width: 42, height: 42)
                        .background(homeIconBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("RESUME SHOPPING")
                            .smartEyebrow(SmartCartTheme.green)
                        Text(session.recipeTitle)
                            .font(.headline)
                            .foregroundStyle(homeInk)
                            .multilineTextAlignment(.leading)
                        Text(pausedShoppingTripDetail(session))
                            .font(.caption)
                            .foregroundStyle(homeSecondaryInk)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(homeSecondaryInk)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-continue-shopping-\(session.id.uuidString)")

            Button(role: .destructive) {
                pendingDiscardSession = session
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(homeInk.opacity(0.82))
                    .frame(width: 36, height: 36)
                    .background(homeIconBackground)
                    .clipShape(Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-clear-paused-\(session.id.uuidString)")
            .accessibilityLabel("Clear paused order for \(session.recipeTitle)")
            .accessibilityHint("Removes this paused order after confirmation")
        }
        .padding(13)
        .background {
            HomeGlassSurface(radius: 18, darkness: 0.28)
        }
    }

    private func pausedShoppingTripDetail(_ session: ShoppingSession) -> String {
        let completed = session.items.filter(\.status.isCompleted).count
        let remaining = max(session.items.count - completed, 0)
        return "\(remaining) item\(remaining == 1 ? "" : "s") remaining"
    }

    private var homeInk: Color {
        colorScheme == .light ? SmartCartTheme.ink : .white
    }

    private var homeSecondaryInk: Color {
        colorScheme == .light ? SmartCartTheme.secondaryInk : .white.opacity(0.72)
    }

    private var homeIconBackground: Color {
        colorScheme == .light ? .white.opacity(0.48) : .black.opacity(0.24)
    }

    private var homeBorder: Color {
        colorScheme == .light ? .black.opacity(0.13) : .white.opacity(0.18)
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

    private func pasteRecipeFromClipboard() {
        // Pasteboard contents are read only after the shopper explicitly taps Paste Recipe.
        let pasteboard = UIPasteboard.general
        let copiedText = pasteboard.url?.absoluteString ?? pasteboard.string
        let normalizedText = copiedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = normalizedText?.isEmpty == false ? normalizedText : nil

        if let validatedURL = trimmedText.flatMap(RecipeLinkInput.validHTTPSURL(from:)) {
            appModel.openImporter(.recipeLink, initialText: validatedURL.absoluteString)
        } else {
            appModel.openImporter(.recipeText, initialText: trimmedText)
        }
    }
}

private typealias HomeGlassSurface = SmartCartSmokedGlassSurface

/// Raised center handle keeps the conditional Continue Shopping drawer
/// discoverable above the tab bar without adding another navigation control.
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

private struct HomePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.88))
            .background(configuration.isPressed ? Color.white.opacity(0.84) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: configuration.isPressed ? 5 : 11, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct HomeSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)

        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(colorScheme == .light ? SmartCartTheme.ink : .white)
            .background(
                colorScheme == .light
                    ? Color.white.opacity(configuration.isPressed ? 0.62 : 0.42)
                    : (configuration.isPressed ? Color.white.opacity(0.14) : Color.black.opacity(0.22))
            )
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    colorScheme == .light
                        ? Color.black.opacity(configuration.isPressed ? 0.20 : 0.13)
                        : Color.white.opacity(configuration.isPressed ? 0.34 : 0.22),
                    lineWidth: 1
                )
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
