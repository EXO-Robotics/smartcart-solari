import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("smartcart.hasSeenJourneyIntro") private var hasSeenJourneyIntro = false
    @State private var showIntro = false
    @Namespace private var workspaceTransition

    var body: some View {
        @Bindable var appModel = appModel

        ZStack(alignment: .top) {
            SmartCartFoodBackground()
                .ignoresSafeArea()

            TabView(selection: $appModel.selectedTab) {
                NavigationStack(path: $appModel.homePath) {
                    HomeView(workspaceTransition: workspaceTransition)
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
            case .importer(let method, let initialText):
                RecipeComposerSheet(initialMethod: method, initialText: initialText)
            }
        }
        .onAppear {
            let environment = ProcessInfo.processInfo.environment
            if environment["SMARTCART_SKIP_INTRO"] != nil {
                hasSeenJourneyIntro = true
            }
            showIntro = (!hasSeenJourneyIntro && !appModel.hasExperiencedUserState) ||
                environment["SMARTCART_SHOW_INTRO"] != nil
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
        case .weeklyMealsCollection:
            WeeklyMealsCollectionView()
        case .weeklyMealDetail(let recipeID):
            WeeklyMealDetailView(recipeID: recipeID)
        case .mealPrepSelection:
            MealPrepSelectionView()
        case .mealPrepDashboard:
            MealPrepDashboardView()
        case .recipeReady:
            RecipeReadyView()
                .smartCartNavigationZoom(
                    sourceID: SmartCartTransitionID.recipeWorkspace,
                    in: workspaceTransition
                )
                .smartCartTransitionSource(
                    id: SmartCartTransitionID.shoppingWorkspace,
                    in: workspaceTransition
                )
        case .shoppingTrip:
            RetailerSafariHandoffView()
                .smartCartNavigationZoom(
                    sourceID: SmartCartTransitionID.shoppingWorkspace,
                    in: workspaceTransition
                )
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
                .smartCartNavigationZoom(
                    sourceID: SmartCartTransitionID.shoppingWorkspace,
                    in: workspaceTransition
                )
        case .shoppingReconciliation(let sessionID):
            ShoppingReconciliationView(sessionID: sessionID)
        }
    }
}

/// One-time trust-first orientation shown only before a shopper has created
/// meaningful app state. The environment override remains available for QA.
struct IntroJourneyView: View {
    let onFinish: () -> Void

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

            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(SmartCartTheme.green)
                        .padding(24)
                        .background(SmartCartTheme.herbLight)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(SmartCartTheme.borderStrong, lineWidth: 1)
                        }
                        .shadow(color: SmartCartTheme.mintGlow, radius: 20)
                        .accessibilityHidden(true)

                    VStack(spacing: 9) {
                        Text("SHOP WITH CONFIDENCE")
                            .smartEyebrow()
                        Text("Your recipe. Your choices.")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(SmartCartTheme.ink)
                            .multilineTextAlignment(.center)
                        Text("Import a recipe, review only what needs attention, then shop with your retailer.")
                            .font(.body)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        trustPoint(
                            symbol: "checklist",
                            title: "You review before shopping",
                            message: "Ingredient names, amounts, and matches stay editable."
                        )
                        Divider()
                        trustPoint(
                            symbol: "safari.fill",
                            title: "Checkout stays with the retailer",
                            message: "SmartCart never asks for retailer credentials or payment."
                        )
                    }
                    .smartCartCard()
                    .smartCartShadow()
                }
                .padding(.horizontal, 22)
                .padding(.top, 30)
                .padding(.bottom, 24)
            }

            Button(action: onFinish) {
                HStack {
                    Text("Get started")
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

    private func trustPoint(symbol: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.bold())
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
