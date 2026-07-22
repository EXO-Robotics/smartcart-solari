import SwiftUI
import UIKit

@main
struct SmartCartApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
                    if scenePhase == .active {
                        appModel.applicationDidBecomeActive()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .inactive:
                        appModel.applicationWillResignActive()
                        appModel.requestLifecyclePersistenceFlush()
                    case .background:
                        appModel.applicationWillResignActive()
                        let lease = SmartCartBackgroundTaskLease()
                        lease.begin()
                        appModel.requestLifecyclePersistenceFlush { _ in
                            lease.end()
                        }
                    case .active:
                        appModel.applicationDidBecomeActive()
                    @unknown default:
                        appModel.requestLifecyclePersistenceFlush()
                    }
                }
        }
    }
}

@MainActor
private final class SmartCartBackgroundTaskLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(
            withName: "SmartCart state persistence"
        ) { [weak self] in
            Task { @MainActor [weak self] in self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        let completedIdentifier = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(completedIdentifier)
    }
}
