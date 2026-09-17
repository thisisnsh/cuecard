import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settingsService: SettingsService
    @ObservedObject private var whatsNew = WhatsNewService.shared

    var body: some View {
        Group {
            if settingsService.hasSeenWelcome {
                HomeView()
            } else {
                WelcomeView()
            }
        }
        .whatsNewCover(isPresented: $whatsNew.isPresented, release: whatsNew.release, version: whatsNew.version)
        .task {
            // Let the first screen settle before floating anything over it.
            try? await Task.sleep(nanoseconds: 500_000_000)
            whatsNew.presentIfUnseen(hasSeenWelcome: settingsService.hasSeenWelcome)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsService.shared)
}
