import SwiftUI

@main
struct ImprovingApp: App {
    @StateObject private var store = ImprovingStore()

    var body: some Scene {
        WindowGroup {
            ImprovingRootView()
                .environmentObject(store)
        }
    }
}
