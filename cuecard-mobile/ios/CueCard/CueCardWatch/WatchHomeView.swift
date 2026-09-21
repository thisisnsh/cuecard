import SwiftUI

/// The watch app's first screen: what is open on the iPhone.
struct WatchHomeView: View {
    @EnvironmentObject var connector: WatchConnector
    @State private var path: [Route] = []

    enum Route: Hashable {
        case teleprompter
        case phoneDeck
    }

    private var isTeleprompterOpen: Bool { connector.phone?.teleprompter != nil }
    private var phoneDeckSession: UUID? { connector.phone?.cards?.session }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("iPhone") {
                    if let timer = connector.phone?.teleprompter {
                        NavigationLink(value: Route.teleprompter) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("Teleprompter", systemImage: timer.symbolName)
                                TimerText(state: timer)
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(timer.tint.color)
                            }
                        }
                    }
                    if let deck = connector.phone?.cards {
                        NavigationLink(value: Route.phoneDeck) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(deck.title, systemImage: "rectangle.stack.fill")
                                Text(cardProgress(index: deck.index, count: deck.cards.count))
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if connector.phone?.teleprompter == nil && connector.phone?.cards == nil {
                        Text("Open a script or cards in CueCard on your iPhone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("CueCard")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .teleprompter:
                    TeleprompterRemoteView()
                case .phoneDeck:
                    PhoneDeckView()
                }
            }
        }
        // A script opened on the iPhone comes straight up on the watch.
        .onChange(of: isTeleprompterOpen) { _, isOpen in
            if isOpen, path.last != .teleprompter {
                path = [.teleprompter]
            }
        }
        // So do cards.
        .onChange(of: phoneDeckSession) { _, session in
            if session != nil, path.last != .phoneDeck {
                path = [.phoneDeck]
            }
        }
    }
}
