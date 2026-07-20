import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var clipboardContainsProbableWebURL = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if !appModel.hasCompletedShoppingTrip {
                    promiseCard
                }
                if !appModel.pendingShoppingSessions.isEmpty {
                    pendingShoppingSection
                }
                if appModel.hasCompletedShoppingTrip,
                   let recipe = appModel.mostRecentShoppedRecipe {
                    shopAgainCard(recipe)
                }
                importSection
                storeCard
                trustStrip
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .smartCartBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: refreshClipboardDetection)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshClipboardDetection()
            }
        }
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

    private var promiseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("RECIPE IN · RETAILER READY")
                    .smartEyebrow()
                Spacer()
                Image(systemName: "safari.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .frame(width: 42, height: 42)
                    .background(SmartCartTheme.herbLight)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(SmartCartTheme.borderStrong, lineWidth: 1)
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Any recipe, ready to shop.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(SmartCartTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Capture a recipe, confirm the ingredients, and open a product-matched shopping trip in Safari.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    promisePill("Photo or link", symbol: "camera.fill")
                    promisePill("Smart match", symbol: "tag.fill")
                    promisePill("Share or shop", symbol: "square.and.arrow.up.fill")
                }
                VStack(alignment: .leading, spacing: 8) {
                    promisePill("Photo or link", symbol: "camera.fill")
                    promisePill("Smart match", symbol: "tag.fill")
                    promisePill("Share or shop", symbol: "square.and.arrow.up.fill")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(SmartCartTheme.paper)
        .smartCartCardEdge(radius: 26)
        .smartCartShadow()
    }

    private func promisePill(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(SmartCartTheme.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(SmartCartTheme.herbLight.opacity(0.7))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(SmartCartTheme.border, lineWidth: 1)
            }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "Start with a recipe",
                subtitle: "Take a photo or choose one you already have"
            )

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
                    Text(method == .camera ? "Camera" : "Photos")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text(method == .camera ? "Snap a cookbook or card" : "Choose a saved recipe image")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .smartCartCard(padding: 16)
            .smartCartShadow()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier(method == .camera ? "home-import-camera" : "home-import-photos")
        .accessibilityHint(method == .camera ? "Opens the camera recipe importer" : "Opens the photo recipe importer")
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
                    Text(isGuideComplete ? "Finish \(session.recipeTitle)" : "Continue \(session.recipeTitle)")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("\(retailerName) · \(isGuideComplete ? "shopping results ready" : "\(session.items.count - completed) remaining")")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .foregroundStyle(SmartCartTheme.green)
            }
            .smartCartCard(padding: 16)
            .smartCartShadow()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier(isGuideComplete ? "home-pantry-update-pending" : "home-resume-shopping")
    }

    private var pendingShoppingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appModel.pendingShoppingSessions.count > 1 {
                SectionHeader(
                    title: "Shopping trips",
                    subtitle: "Resume a trip or finish its pantry update"
                )
            }
            ForEach(appModel.pendingShoppingSessions) { session in
                pendingShoppingCard(session)
            }
        }
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
