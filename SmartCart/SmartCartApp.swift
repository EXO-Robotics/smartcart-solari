import SwiftUI
import UIKit

@main
struct SmartCartApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel = AppModel()
    @State private var appearanceController = SmartCartAppearanceController()
    @State private var weeklyMealsStore = WeeklyMealsStore()
    @State private var handoffCoordinator = SmartCartHandoffCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(appearanceController)
                .environment(weeklyMealsStore)
                .preferredColorScheme(appearanceController.appearance.colorScheme)
                .onAppear {
                    if let raw = ProcessInfo.processInfo.environment["SMARTCART_START_TAB"],
                       let tab = AppTab.canonicalTab(forRawValue: raw) {
                        appModel.selectedTab = tab
                    }
                    if scenePhase == .active {
                        appModel.applicationDidBecomeActive()
                        Task { await weeklyMealsStore.refreshIfNeeded() }
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
                        Task { await weeklyMealsStore.refreshIfNeeded() }
                    @unknown default:
                        appModel.requestLifecyclePersistenceFlush()
                    }
                }
                .onOpenURL { url in
                    handoffCoordinator.handle(url, appModel: appModel)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    handoffCoordinator.handle(url, appModel: appModel)
                }
        }
    }
}

@MainActor
private final class SmartCartHandoffCoordinator {
    private struct Attempt {
        let token: String
        let requestID: UUID
    }

    private var attempt: Attempt?
    private var activeTask: Task<Void, Never>?

    func handle(_ url: URL, appModel: AppModel) {
        switch SmartCartHandoffURLParser.parse(url) {
        case .notSmartCartHandoff:
            return
        case .invalid:
            appModel.smartCartHandoffDidFail(
                "This SmartCart link is invalid. Ask ChatGPT to create a new one."
            )
        case .valid(let token):
            beginClaim(token: token, appModel: appModel)
        }
    }

    private func beginClaim(token: String, appModel: AppModel) {
        if activeTask != nil {
            guard attempt?.token != token else { return }
            appModel.smartCartHandoffDidFail("SmartCart is already opening another plan")
            return
        }

        let requestID: UUID
        if attempt?.token == token, let existingRequestID = attempt?.requestID {
            requestID = existingRequestID
        } else {
            requestID = UUID()
            attempt = Attempt(token: token, requestID: requestID)
        }

        guard case .success(let configuration) = BarcodeBackendConfiguration.resolve() else {
            appModel.smartCartHandoffDidFail("SmartCart’s plan service is not configured")
            return
        }
        let client = SmartCartHandoffClient(baseURL: configuration.baseURL)
        activeTask = Task { [weak self] in
            defer { self?.activeTask = nil }
            do {
                let payload = try await client.claim(token: token, requestID: requestID)
                try Task.checkCancellation()
                let handoff = try SmartCartHandoffSnapshotFactory.makeImport(from: payload)
                guard appModel.importSmartCartHandoff(handoff) else { return }
                self?.attempt = nil
            } catch is CancellationError {
                return
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? "SmartCart could not open this plan. Try the link again."
                appModel.smartCartHandoffDidFail(message)
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
