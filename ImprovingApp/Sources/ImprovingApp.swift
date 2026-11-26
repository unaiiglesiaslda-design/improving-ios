import SwiftUI
import BackgroundTasks
import UIKit

@main
struct ImprovingApp: App {
    @StateObject private var store = ImprovingStore()
    @Environment(\.scenePhase) private var scenePhase

    private static let bgRefreshId = "com.improving.health.ios.refresh"

    init() {
        LocalNotificationManager.shared.registerDelegate()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgRefreshId, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.scheduleBackgroundRefresh()
            let work = Task {
                await ShortcutsHealthSyncImporter.processPendingInboxInBackground()
                refreshTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = {
                work.cancel()
                refreshTask.setTaskCompleted(success: false)
            }
        }
    }

    private static func scheduleBackgroundRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: Self.bgRefreshId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

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
                        // Rely on contentChanged diff rather than burning WidgetKit daily reload quota!
                        store.publishWidgetSnapshot(triggerReload: true, forceReload: false)
                    case .background:
                        Self.scheduleBackgroundRefresh()
                        let bgId = UIApplication.shared.beginBackgroundTask(withName: "ImprovingFlush")
                        store.flushPersistenceNow()
                        if bgId != .invalid {
                            UIApplication.shared.endBackgroundTask(bgId)
                        }
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .improvingShortcutsSyncDidArrive)) { _ in
                    store.scanAutoSyncInboxIfNeeded(force: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .improvingDeepLinkRequested)) { notif in
                    if let route = notif.userInfo?["route"] as? String {
                        store.handleDeepLinkRoute(route)
                    }
                }
        }
    }
}
