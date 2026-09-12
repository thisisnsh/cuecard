import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settingsService: SettingsService

    var body: some View {
        Group {
            if settingsService.hasSeenWelcome {
                HomeView()
            } else {
                WelcomeView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsService.shared)
}
