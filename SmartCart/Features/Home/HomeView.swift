import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel

    private let importColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                promiseCard
                if !appModel.pendingShoppingSessions.isEmpty {
                    pendingShoppingSection
                }
                importSection
                sampleSection
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

                Text("Capture a recipe, confirm the ingredients, and open a product-matched retailer guide in Safari.")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                promisePill("Photo or link", symbol: "camera.fill")
                promisePill("Smart match", symbol: "tag.fill")
                promisePill("Share or shop", symbol: "square.and.arrow.up.fill")
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
            .font(.system(size: 10, weight: .bold))
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
                title: "Import a recipe",
                subtitle: "Start from wherever you found dinner"
            )

            LazyVGrid(columns: importColumns, spacing: 10) {
                ForEach(ImportMethod.allCases) { method in
                    ImportActionTile(method: method) {
                        appModel.openImporter(method)
                    }
                }
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

    private var sampleSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "Perfect for testing",
                subtitle: "Walk through a complete product match"
            )

            if let recipe = appModel.recipes.first {
                RecipeHeroCard(recipe: recipe) {
                    appModel.beginRecipe(recipe)
                }
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
                    Text("\(appModel.retailerConfiguration.guideLabel) · Opens in Safari")
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
