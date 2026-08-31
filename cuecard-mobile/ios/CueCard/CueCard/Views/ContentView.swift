import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var remoteConfig: RemoteConfigService

    var body: some View {
        Group {
            if remoteConfig.requiresUpdate {
                UpdateRequiredView()
            } else if authService.isAuthenticated {
                HomeView()
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService.shared)
        .environmentObject(SettingsService.shared)
        .environmentObject(RemoteConfigService.shared)
}
