import SwiftUI

@main
struct CueCardWatchApp: App {
    @StateObject private var connector = WatchConnector.shared
    @StateObject private var store = DeckStore.shared

    init() {
        WatchConnector.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(connector)
                .environmentObject(store)
        }
    }
}
