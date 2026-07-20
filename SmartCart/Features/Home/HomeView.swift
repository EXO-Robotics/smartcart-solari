import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pendingDiscardSession: ShoppingSession?
    @State private var shoppingTripsExpanded = false
    @GestureState private var shoppingTripsDrag: CGFloat = 0

    private let collapsedShoppingTripsDrawerHeight: CGFloat = 92

    var body: some View {
        GeometryReader { geometry in
            let drawerHeight = max(420, geometry.size.height - 88)
            let collapsedOffset = drawerHeight - collapsedShoppingTripsDrawerHeight
            let hasPausedTrips = !pausedShoppingSessions.isEmpty

            ZStack(alignment: .bottom) {
                HomePhotoBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        shoppingTripStatusSection
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
                        .spring(response: 0.42, dampingFraction: 0.86),
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
        HStack {
            Image(systemName: "leaf.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SmartCartTheme.green)
                .shadow(color: SmartCartTheme.green.opacity(0.34), radius: 12)
                .frame(width: 44, height: 44, alignment: .leading)
                .accessibilityLabel("SmartCart")

            Spacer()

            moreImportMenu
        }
    }

    @ViewBuilder
    private var shoppingTripStatusSection: some View {
        if let pantryUpdateShoppingSession {
            pantryUpdateStatusCard(pantryUpdateShoppingSession)
        }
    }

    private var startShoppingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start a Shopping Trip")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            startShoppingPanel
        }
    }

    private var startShoppingPanel: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
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
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 82)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("home-paste-recipe")
            .accessibilityHint("Pastes recipe text or a copied recipe link")

            Divider()
                .overlay(Color.white.opacity(0.16))

            mealPrepLaunchButton
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .background {
            HomeGlassSurface(radius: 30, darkness: 0.16)
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
                    .background(Color.black.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Meal Prep Mode")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Combine up to five saved recipes")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.72))
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
                .foregroundStyle(.white)
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

    private var pantryUpdateShoppingSession: ShoppingSession? {
        appModel.pendingShoppingSessions.first(where: \.hasPendingPantryUpdateReminder)
    }

    private func pantryUpdateStatusCard(_ session: ShoppingSession) -> some View {
        Button {
            guard appModel.openShoppingSession(session.id) else { return }
            appModel.startShoppingReconciliation()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline.bold())
                    .foregroundStyle(SmartCartTheme.green)
                    .frame(width: 42, height: 42)
                    .background(Color.black.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Finish your last trip")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(pantryUpdateStatusDetail(session))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.74))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background {
                HomeGlassSurface(radius: 20, darkness: 0.40)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-finish-last-trip")
        .accessibilityLabel("Finish your last trip, \(pantryUpdateStatusDetail(session))")
    }

    private func pantryUpdateStatusDetail(_ session: ShoppingSession) -> String {
        let count = session.items.count
        return "Review \(count) trip item\(count == 1 ? "" : "s") and update pantry"
    }

    private func continueShoppingTripsDrawer(
        height: CGFloat,
        collapsedOffset: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            continueShoppingTripsHandle(collapsedOffset: collapsedOffset)

            Divider()
                .overlay(Color.white.opacity(0.16))

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
            HomePullUpGlassSurface()
        }
        .clipShape(HomePullUpShape())
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
                    .foregroundStyle(.white)

                Spacer()

                Text(shoppingTripsExpanded ? "Swipe down to hide" : pausedOrdersCountText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
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
                        .background(Color.black.opacity(0.24))
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("RESUME SHOPPING")
                            .smartEyebrow(SmartCartTheme.green)
                        Text(session.recipeTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Text(pausedShoppingTripDetail(session))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.70))
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.70))
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
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.10))
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

private struct HomePhotoBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                Image("SmartCartHomeBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                Color.black.opacity(colorScheme == .light ? 0.50 : 0.42)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.34),
                        Color.clear,
                        Color.black.opacity(0.24)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HomeGlassSurface: View {
    let radius: CGFloat
    let darkness: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(Color.black.opacity(darkness))
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.clear,
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
    }
}

private struct HomePullUpGlassSurface: View {
    var body: some View {
        let shape = HomePullUpShape()

        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(Color.black.opacity(0.34))
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.clear,
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
    }
}

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
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)

        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .background(
                configuration.isPressed
                    ? Color.white.opacity(0.14)
                    : Color.black.opacity(0.22)
            )
            .clipShape(shape)
            .overlay {
                shape.stroke(Color.white.opacity(configuration.isPressed ? 0.34 : 0.22), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
