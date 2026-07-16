import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        ZStack(alignment: .top) {
            SmartCartTheme.canvas
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
                    ListsView()
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
            .toolbarBackground(SmartCartTheme.paper, for: .tabBar)
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
            StoreSelectionView()
        case .matching:
            ProductMatchingView()
        case .shoppingList:
            ShoppingListReviewView()
        case .guidedShopping:
            GuidedShoppingView()
        }
    }
}
