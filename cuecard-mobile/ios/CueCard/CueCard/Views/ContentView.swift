import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settingsService: SettingsService

    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsService.shared)
}
