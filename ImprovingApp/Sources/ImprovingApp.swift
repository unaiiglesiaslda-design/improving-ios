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
                    switch newPhase {
                    case .active:
                        store.handleAppBecameActive()
                        store.publishWidgetSnapshot(triggerReload: true, forceReload: true)
                    case .inactive, .background:
                        store.publishWidgetSnapshot(triggerReload: true, forceReload: true)
                        store.flushPersistenceNow()
                    @unknown default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .improvingShortcutsSyncDidArrive)) { _ in
                    store.scanAutoSyncInboxIfNeeded(force: true)
                }
        }
    }
}
