import SwiftUI

@main
struct GrocrygetterApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.light)
        }
    }
}
