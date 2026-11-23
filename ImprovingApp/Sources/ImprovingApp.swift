import SwiftUI

@main
struct ImprovingApp: App {
    @StateObject private var store = ImprovingStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ImprovingRootView()
                .environmentObject(store)
                .onOpenURL { url in
                    store.handleIncomingURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        store.scanAutoSyncInboxIfNeeded()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .improvingShortcutsSyncDidArrive)) { _ in
                    store.scanAutoSyncInboxIfNeeded(force: true)
                }
        }
    }
}
