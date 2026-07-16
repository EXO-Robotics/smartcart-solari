import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel

    private let importColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                promiseCard
                importSection
                journeySection
                sampleSection
                storeCard
                trustStrip
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(GatherTheme.canvas)
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
                        .foregroundStyle(GatherTheme.navy)
                    Circle()
                        .fill(GatherTheme.green)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(GatherTheme.canvas, lineWidth: 2))
                }
            }
            .accessibilityLabel("Open account")
        }
        .padding(.top, 8)
    }

    private var promiseCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Turn any recipe into a ready-to-shop grocery list.")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Capture. Confirm. Shop smarter.")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GatherTheme.yellow)
                }

                Spacer(minLength: 0)

                Image(systemName: "cart.fill.badge.plus")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            }

            HStack(spacing: 8) {
                promisePill("Photo or link", symbol: "camera.fill")
                promisePill("Smart match", symbol: "tag.fill")
                promisePill("Share or shop", symbol: "square.and.arrow.up.fill")
            }
        }
        .padding(20)
        .background {
            LinearGradient(
                colors: [GatherTheme.navy, Color(red: 0.02, green: 0.22, blue: 0.26)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .gatherShadow()
    }

    private func promisePill(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.10))
            .clipShape(Capsule())
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

    private var journeySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                title: "The SmartCart journey",
                subtitle: "You stay in control at every step"
            )

            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    JourneyStepCard(number: 1, symbol: "square.and.arrow.down.fill", title: "Import", subtitle: "From anywhere", isActive: true)
                    journeyArrow
                    JourneyStepCard(number: 2, symbol: "checklist", title: "Review", subtitle: "Confirm items")
                    journeyArrow
                    JourneyStepCard(number: 3, symbol: "storefront.fill", title: "Store", subtitle: "Choose location")
                    journeyArrow
                    JourneyStepCard(number: 4, symbol: "tag.fill", title: "Match", subtitle: "Find products")
                    journeyArrow
                    JourneyStepCard(number: 5, symbol: "cart.fill", title: "Shop", subtitle: "Open or share")
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 1, for: .scrollContent)
        }
    }

    private var journeyArrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption.bold())
            .foregroundStyle(GatherTheme.green)
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
                        .foregroundStyle(GatherTheme.green)
                        .textCase(.uppercase)
                    Text(appModel.primaryStore.name)
                        .font(.headline)
                        .foregroundStyle(GatherTheme.navy)
                    Text("\(appModel.primaryStore.distance, specifier: "%.1f") mi · \(appModel.fulfillmentMode.rawValue) · \(appModel.pickupTime)")
                        .font(.caption)
                        .foregroundStyle(GatherTheme.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if appModel.selectedStores.count > 1 {
                    Text("+\(appModel.selectedStores.count - 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 29, height: 29)
                        .background(GatherTheme.green)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(GatherTheme.secondaryInk.opacity(0.6))
                }
            }
            .gatherCard(padding: 14)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var trustStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(GatherTheme.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("Your checkout stays with the retailer")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GatherTheme.navy)
                Text("SmartCart never asks for Walmart credentials or payment.")
                    .font(.caption)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GatherTheme.herbLight.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
