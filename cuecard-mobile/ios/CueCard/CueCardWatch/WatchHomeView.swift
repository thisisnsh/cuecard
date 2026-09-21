import SwiftUI

/// The watch app's first screen: what is open on the iPhone.
struct WatchHomeView: View {
    @EnvironmentObject var connector: WatchConnector

    var body: some View {
        NavigationStack {
            List {
                Section("iPhone") {
                    Text("Open a script or cards in CueCard on your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("CueCard")
        }
    }
}
