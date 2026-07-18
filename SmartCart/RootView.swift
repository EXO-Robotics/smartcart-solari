import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("smartcart.hasSeenJourneyIntro") private var hasSeenJourneyIntro = false
    @State private var showIntro = false

    var body: some View {
        @Bindable var appModel = appModel

        ZStack(alignment: .top) {
            WoodGrainBackground()
                .ignoresSafeArea()

            TabView(selection: $appModel.selectedTab) {
                NavigationStack(path: $appModel.homePath) {
                    HomeView()
                        .navigationDestination(for: SmartRoute.self) { route in
                            destination(for: route)
                        }
                }
                .tag(AppTab.home)
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.symbol)
                }

                NavigationStack {
                    RecipesView()
                }
                .tag(AppTab.lists)
                .tabItem {
                    Label(AppTab.lists.title, systemImage: AppTab.lists.symbol)
                }

                NavigationStack {
                    PantryDashboardView()
                }
                .tag(AppTab.pantry)
                .tabItem {
                    Label(AppTab.pantry.title, systemImage: AppTab.pantry.symbol)
                }

                NavigationStack {
                    StoreDashboardView()
                }
                .tag(AppTab.store)
                .tabItem {
                    Label(AppTab.store.title, systemImage: AppTab.store.symbol)
                }

                NavigationStack {
                    AccountView()
                }
                .tag(AppTab.account)
                .tabItem {
                    Label(AppTab.account.title, systemImage: AppTab.account.symbol)
                }
            }
            .tint(SmartCartTheme.green)
            .toolbarBackground(SmartCartTheme.canvasRaise, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            if let message = appModel.toastMessage {
                ToastView(message: message)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: appModel.toastMessage)
        .sheet(item: $appModel.presentedSheet) { destination in
            switch destination {
            case .importer(let method):
                RecipeComposerSheet(initialMethod: method)
            }
        }
        .onAppear {
            let environment = ProcessInfo.processInfo.environment
            if environment["SMARTCART_SKIP_INTRO"] != nil {
                hasSeenJourneyIntro = true
            }
            showIntro = !hasSeenJourneyIntro || environment["SMARTCART_SHOW_INTRO"] != nil
        }
        .fullScreenCover(isPresented: $showIntro) {
            IntroJourneyView {
                hasSeenJourneyIntro = true
                showIntro = false
            }
        }
    }

    @ViewBuilder
    private func destination(for route: SmartRoute) -> some View {
        switch route {
        case .ingredientReview:
            IngredientReviewView()
        case .servingAdjustment:
            ServingAdjustmentView()
        case .pantryCheck:
            PantryCheckView()
        case .preferences:
            ShoppingPreferencesView()
        case .storeSelection:
            RetailerSelectionView()
        case .matching:
            ProductMatchingView()
        case .shoppingList:
            ShoppingListReviewView()
        case .guidedShopping:
            RetailerSafariHandoffView()
        case .shoppingReconciliation(let sessionID):
            ShoppingReconciliationView(sessionID: sessionID)
        }
    }
}

/// One-time onboarding walk-through of the SmartCart journey, shown on
/// first launch instead of living on the Home screen.
struct IntroJourneyView: View {
    let onFinish: () -> Void

    @State private var step = 0

    private struct JourneyStep {
        let symbol: String
        let title: String
        let message: String
    }

    private let steps: [JourneyStep] = [
        .init(symbol: "square.and.arrow.down.fill", title: "Import from anywhere", message: "Snap a cookbook photo, paste a link or text, or start from a sample recipe."),
        .init(symbol: "checklist", title: "Review every ingredient", message: "Confirm names and quantities before anything is matched to a product."),
        .init(symbol: "slider.horizontal.3", title: "Set your rules", message: "Dietary filters, organic, budget, and brand preferences shape every match."),
        .init(symbol: "storefront.fill", title: "Choose a retailer", message: "Pick Walmart or Target for a retailer-specific shopping guide."),
        .init(symbol: "tag.fill", title: "Match real products", message: "SmartCart resolves exact retailer items, or clearly labeled searches."),
        .init(symbol: "safari.fill", title: "Finish with the retailer", message: "Open exact products in Safari, then use the retailer for lists, cart actions, fulfillment, payment, and checkout.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SmartCartLogo(compact: true)
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            TabView(selection: $step) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 22) {
                        Text("THE SMARTCART JOURNEY · \(index + 1)/\(steps.count)")
                            .smartEyebrow()

                        Image(systemName: item.symbol)
                            .font(.system(size: 46, weight: .bold))
                            .foregroundStyle(SmartCartTheme.green)
                            .frame(width: 118, height: 118)
                            .background(SmartCartTheme.herbLight)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .stroke(SmartCartTheme.borderStrong, lineWidth: 1)
                            }
                            .shadow(color: SmartCartTheme.mintGlow, radius: 24)

                        VStack(spacing: 9) {
                            Text(item.title)
                                .font(.system(size: 27, weight: .bold, design: .rounded))
                                .foregroundStyle(SmartCartTheme.ink)
                                .multilineTextAlignment(.center)
                            Text(item.message)
                                .font(.subheadline)
                                .foregroundStyle(SmartCartTheme.secondaryInk)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 34)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 7) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? SmartCartTheme.green : SmartCartTheme.border)
                        .frame(width: index == step ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: step)
            .padding(.bottom, 20)

            Button {
                if step < steps.count - 1 {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                        step += 1
                    }
                } else {
                    onFinish()
                }
            } label: {
                HStack {
                    Text(step < steps.count - 1 ? "Next" : "Get started")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 22)
            .padding(.bottom, 26)
        }
        .smartCartBackground()
        .interactiveDismissDisabled()
    }
}
