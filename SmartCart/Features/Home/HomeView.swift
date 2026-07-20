import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            HomePhotoBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    shoppingTripStatusSection
                    startShoppingSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
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
        if let resumableShoppingSession, let pantryUpdateShoppingSession {
            VStack(alignment: .leading, spacing: 10) {
                Text("Shopping Trips")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        shoppingTripStatusCard(resumableShoppingSession, kind: .resume)
                        shoppingTripStatusCard(pantryUpdateShoppingSession, kind: .pantryUpdate)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            shoppingTripStatusCard(resumableShoppingSession, kind: .resume)
                                .frame(width: 294)
                            shoppingTripStatusCard(pantryUpdateShoppingSession, kind: .pantryUpdate)
                                .frame(width: 294)
                        }
                    }
                }
            }
            .accessibilityIdentifier("home-shopping-trips-strip")
        } else if let resumableShoppingSession {
            shoppingTripStatusCard(resumableShoppingSession, kind: .resume)
        } else if let pantryUpdateShoppingSession {
            shoppingTripStatusCard(pantryUpdateShoppingSession, kind: .pantryUpdate)
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

    private var resumableShoppingSession: ShoppingSession? {
        appModel.pendingShoppingSessions.first(where: \.isReusable)
    }

    private var pantryUpdateShoppingSession: ShoppingSession? {
        appModel.pendingShoppingSessions.first(where: \.hasPendingPantryUpdateReminder)
    }

    private func shoppingTripStatusCard(
        _ session: ShoppingSession,
        kind: HomeShoppingTripStatusKind
    ) -> some View {
        Button {
            openShoppingTripStatus(session, kind: kind)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.headline.bold())
                    .foregroundStyle(SmartCartTheme.green)
                    .frame(width: 42, height: 42)
                    .background(Color.black.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(shoppingTripStatusDetail(session, kind: kind))
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
        .accessibilityIdentifier(kind.accessibilityIdentifier)
        .accessibilityLabel("\(kind.title), \(shoppingTripStatusDetail(session, kind: kind))")
    }

    private func shoppingTripStatusDetail(
        _ session: ShoppingSession,
        kind: HomeShoppingTripStatusKind
    ) -> String {
        switch kind {
        case .resume:
            let completed = session.items.filter(\.status.isCompleted).count
            return "\(completed) of \(session.items.count) items · \(session.recipeTitle)"
        case .pantryUpdate:
            let count = session.items.count
            return "Review \(count) trip item\(count == 1 ? "" : "s") and update pantry"
        }
    }

    private func openShoppingTripStatus(
        _ session: ShoppingSession,
        kind: HomeShoppingTripStatusKind
    ) {
        guard appModel.openShoppingSession(session.id) else { return }
        if kind == .pantryUpdate {
            appModel.startShoppingReconciliation()
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

private enum HomeShoppingTripStatusKind: Equatable {
    case resume
    case pantryUpdate

    var title: String {
        switch self {
        case .resume: "Resume Shopping"
        case .pantryUpdate: "Finish your last trip"
        }
    }

    var symbol: String {
        switch self {
        case .resume: "cart.fill"
        case .pantryUpdate: "checkmark.circle.fill"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .resume: "home-resume-shopping"
        case .pantryUpdate: "home-finish-last-trip"
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
