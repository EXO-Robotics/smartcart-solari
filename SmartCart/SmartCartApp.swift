import SwiftUI

@main
struct SmartCartApp: App {
    @State private var appModel = AppModel()
    @State private var appearanceController = SmartCartAppearanceController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(appearanceController)
                .preferredColorScheme(appearanceController.appearance.colorScheme)
                .onAppear {
                    if let raw = ProcessInfo.processInfo.environment["SMARTCART_START_TAB"],
                       let tab = AppTab(rawValue: raw) {
                        appModel.selectedTab = tab
                    }
                }
        }
    }
}
