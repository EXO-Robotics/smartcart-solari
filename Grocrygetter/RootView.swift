import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        ZStack(alignment: .top) {
            GatherTheme.canvas
                .ignoresSafeArea()

            TabView(selection: $appModel.selectedTab) {
                NavigationStack {
                    HomeView()
                }
                .tag(AppTab.plan)
                .tabItem {
                    Label(AppTab.plan.title, systemImage: AppTab.plan.symbol)
                }

                NavigationStack {
                    CartView()
                }
                .tag(AppTab.cart)
                .tabItem {
                    Label(AppTab.cart.title, systemImage: AppTab.cart.symbol)
                }
                .badge(appModel.activeCartItemCount)

                NavigationStack {
                    OrdersView()
                }
                .tag(AppTab.orders)
                .tabItem {
                    Label(AppTab.orders.title, systemImage: AppTab.orders.symbol)
                }
            }
            .tint(GatherTheme.herb)
            .toolbarBackground(GatherTheme.paper, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            if let message = appModel.toastMessage {
                ToastView(message: message)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: appModel.toastMessage)
        .sheet(item: $appModel.presentedSheet) { destination in
            switch destination {
            case .recipeComposer:
                RecipeComposerSheet()
            case .pickupScheduler:
                PickupSchedulerSheet()
            case .storePicker:
                StorePickerSheet()
            }
        }
    }
}

struct StorePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose the stores you’re happy to visit. Smart Split will compare your selected options.")
                        .font(.subheadline)
                        .foregroundStyle(GatherTheme.secondaryInk)
                        .padding(.bottom, 4)

                    ForEach(appModel.stores) { store in
                        Button {
                            appModel.toggleStore(store)
                        } label: {
                            HStack(spacing: 14) {
                                StoreMark(store: store, size: 52)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(store.name)
                                        .font(.headline)
                                        .foregroundStyle(GatherTheme.ink)
                                    Text("\(store.distance, specifier: "%.1f") mi • \(store.nextPickup)")
                                        .font(.caption)
                                        .foregroundStyle(GatherTheme.secondaryInk)
                                }

                                Spacer()

                                Image(systemName: appModel.selectedStoreIDs.contains(store.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(appModel.selectedStoreIDs.contains(store.id) ? GatherTheme.herb : Color.gray.opacity(0.45))
                            }
                            .gatherCard(padding: 14)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(20)
            }
            .background(GatherTheme.canvas)
            .navigationTitle("Your stores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
