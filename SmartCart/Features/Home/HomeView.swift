import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pendingDiscardAction: HomeTripActionPresentation?
    @State private var shoppingTripsExpanded = false
    @State private var shoppingTripsDrag: CGFloat = 0

    private var collapsedShoppingTripsDrawerHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 148 : 92
    }
    private let workspaceTransition: Namespace.ID?

    init(workspaceTransition: Namespace.ID? = nil) {
        self.workspaceTransition = workspaceTransition
    }

    var body: some View {
        GeometryReader { geometry in
            let drawerHeight = max(420, geometry.size.height - 88)
            let collapsedOffset = drawerHeight - collapsedShoppingTripsDrawerHeight
            let hasTripActions = !tripActionPresentations.isEmpty

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
                        hasTripActions ? collapsedShoppingTripsDrawerHeight + 24 : 36
                    )
                }
                .scrollIndicators(.hidden)

                if hasTripActions {
                    continueShoppingTripsDrawer(
                        height: drawerHeight,
                        collapsedOffset: collapsedOffset
                    )
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(
                                height: drawerHeight - shoppingTripsDrawerOffset(
                                    collapsedOffset: collapsedOffset
                                )
                            )
                    }
                    .offset(y: shoppingTripsDrawerOffset(collapsedOffset: collapsedOffset))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: shoppingTripsExpanded)
        .onChange(of: tripActionPresentations.map(\.id)) { _, actionIDs in
            if actionIDs.isEmpty {
                shoppingTripsExpanded = false
                shoppingTripsDrag = 0
                pendingDiscardAction = nil
            }
        }
        .confirmationDialog(
            "Clear this paused order?",
            isPresented: Binding(
                get: { pendingDiscardAction != nil },
                set: { isPresented in
                    if !isPresented { pendingDiscardAction = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDiscardAction {
                Button("Clear Order", role: .destructive) {
                    appModel.discardPendingShoppingSession(pendingDiscardAction.id)
                    self.pendingDiscardAction = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDiscardAction = nil
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
            .accessibilityHint(
                RecipeLinkCapability.current.isAvailable
                    ? "Pastes recipe text or a copied recipe link"
                    : "Pastes recipe text"
            )

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

    private var tripActionPresentations: [HomeTripActionPresentation] {
        appModel.homeTripActionPresentations
    }

    private func continueShoppingTripsDrawer(
        height: CGFloat,
        collapsedOffset: CGFloat
    ) -> some View {
        let woodWrapDepth: CGFloat = shoppingTripsExpanded ? 26 : 0
        let joinOverlap: CGFloat = shoppingTripsExpanded ? 2 : 0

        return VStack(spacing: 0) {
            continueShoppingTripsHandle(collapsedOffset: collapsedOffset)

            if shoppingTripsExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(tripActionPresentations) { presentation in
                            homeTripActionRow(presentation)
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
                    .clipShape(SmartCartDrawerWoodWrapShape(depth: woodWrapDepth))
                    .padding(
                        .top,
                        collapsedShoppingTripsDrawerHeight - woodWrapDepth - joinOverlap
                    )
                SmartCartDrawerGlassSurface(
                    shape: HomePullUpShape(),
                    darkness: 0.28
                )
                    .frame(height: collapsedShoppingTripsDrawerHeight)
            }
        }
        .clipShape(HomePullUpShape())
        .overlay(alignment: .top) {
            HomePullUpShape()
                .stroke(SmartCartTheme.borderStrong.opacity(0.72), lineWidth: 1)
                .frame(height: collapsedShoppingTripsDrawerHeight)
                .mask(alignment: .top) {
                    Rectangle()
                        .frame(
                            height: collapsedShoppingTripsDrawerHeight - joinOverlap
                        )
                }
        }
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

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) {
                        shoppingTripsHandleTitle
                        shoppingTripsHandleSummary
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 9) {
                        shoppingTripsHandleTitle
                        Spacer()
                        shoppingTripsHandleSummary
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .frame(height: collapsedShoppingTripsDrawerHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            settleShoppingTripsDrawer(expanded: !shoppingTripsExpanded)
        }
        .gesture(shoppingTripsDragGesture(collapsedOffset: collapsedOffset))
        .accessibilityLabel("Shopping Trips drawer")
        .accessibilityValue(shoppingTripsExpanded ? "Expanded" : "Collapsed, \(shoppingTripsSummaryText)")
        .accessibilityHint(
            shoppingTripsExpanded
                ? "Swipe down or double tap to hide paused orders"
                : "Swipe up or double tap to show paused orders"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home-continue-shopping-drawer")
    }

    private var shoppingTripsHandleTitle: some View {
        Label(shoppingTripsTitle, systemImage: "cart.badge.clock")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(homeInk)
    }

    private var shoppingTripsHandleSummary: some View {
        Text(shoppingTripsExpanded ? "Swipe down to hide" : shoppingTripsSummaryText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(homeSecondaryInk)
    }

    private var shoppingTripsTitle: String {
        let actions = tripActionPresentations.map(\.action)
        guard actions.count == 1, let action = actions.first else {
            return "Shopping Trips · \(actions.count)"
        }
        switch action {
        case .resume: return "Resume Shopping"
        case .updatePantry: return "Update Pantry"
        }
    }

    private var shoppingTripsSummaryText: String {
        let actions = tripActionPresentations.map(\.action)
        let resumeCount = actions.filter {
            if case .resume = $0 { return true }
            return false
        }.count
        let pantryCount = actions.count - resumeCount

        if resumeCount > 0, pantryCount > 0 {
            return "\(resumeCount) paused · \(pantryCount) pantry update\(pantryCount == 1 ? "" : "s")"
        }
        if pantryCount > 0 {
            return "\(pantryCount) pantry update\(pantryCount == 1 ? "" : "s")"
        }
        return "\(resumeCount) paused order\(resumeCount == 1 ? "" : "s")"
    }

    private func homeTripActionRow(_ presentation: HomeTripActionPresentation) -> some View {
        HStack(spacing: 10) {
            Button {
                appModel.performHomeTripAction(presentation.action)
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
                        Text(homeTripActionEyebrow(presentation.action))
                            .smartEyebrow(SmartCartTheme.green)
                        Text(presentation.title)
                            .font(.headline)
                            .foregroundStyle(homeInk)
                            .multilineTextAlignment(.leading)
                        Text(presentation.detail)
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
            .accessibilityIdentifier("home-continue-shopping-\(presentation.id.uuidString)")

            if case .resume = presentation.action {
                Button(role: .destructive) {
                    pendingDiscardAction = presentation
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
                .accessibilityIdentifier("home-clear-paused-\(presentation.id.uuidString)")
                .accessibilityLabel("Clear paused order for \(presentation.title)")
                .accessibilityHint("Removes this paused order after confirmation")
            }
        }
        .padding(13)
        .background {
            HomeGlassSurface(radius: 18, darkness: 0.28)
        }
    }

    private func homeTripActionEyebrow(_ action: HomeTripAction) -> String {
        switch action {
        case .resume: return "RESUME SHOPPING"
        case .updatePantry: return "UPDATE PANTRY"
        }
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
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    shoppingTripsDrag = value.translation.height
                }
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.height
                let decisiveDistance = min(96, collapsedOffset * 0.22)
                let shouldExpand = shoppingTripsExpanded
                    ? projected <= decisiveDistance
                    : projected < -decisiveDistance
                settleShoppingTripsDrawer(expanded: shouldExpand)
            }
    }

    private func settleShoppingTripsDrawer(expanded: Bool) {
        withAnimation(reduceMotion ? nil : SmartCartMotion.signature) {
            shoppingTripsExpanded = expanded
            shoppingTripsDrag = 0
        }
    }

    private func pasteRecipeFromClipboard() {
        // Pasteboard contents are read only after the shopper explicitly taps Paste Recipe.
        let pasteboard = UIPasteboard.general
        let copiedText = pasteboard.url?.absoluteString ?? pasteboard.string
        let normalizedText = copiedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = normalizedText?.isEmpty == false ? normalizedText : nil

        if let validatedURL = trimmedText.flatMap(RecipeLinkInput.validHTTPSURL(from:)) {
            let capability = RecipeLinkCapability.current
            if capability.isAvailable {
                appModel.openImporter(.recipeLink, initialText: validatedURL.absoluteString)
            } else {
                appModel.showToast(capability.fallbackMessage)
            }
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
