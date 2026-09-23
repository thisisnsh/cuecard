import SwiftUI

/// The watch app's first screen: what is open on the iPhone, and the decks
/// kept on the watch.
struct WatchHomeView: View {
    @EnvironmentObject var connector: WatchConnector
    @EnvironmentObject var store: DeckStore
    @State private var path: [Route] = []
    @State private var showingHelp = false

    enum Route: Hashable {
        case teleprompter
        case phoneDeck
        case savedDeck(UUID)
    }

    private var isTeleprompterOpen: Bool { connector.phone?.teleprompter != nil }
    private var phoneDeckSession: UUID? { connector.phone?.cards?.session }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if isTeleprompterOpen || phoneDeckSession != nil || store.decks.isEmpty {
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

                Section {
                    ForEach(store.decks) { deck in
                        NavigationLink(value: Route.savedDeck(deck.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deck.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(store.position(of: deck.id) > 0
                                     ? cardProgress(index: store.position(of: deck.id), count: deck.cards.count)
                                     : (deck.cards.count == 1 ? "1 card" : "\(deck.cards.count) cards"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("On Watch")
                } footer: {
                    if store.decks.isEmpty {
                        Text("Choose notes to keep on your watch in CueCard's Settings on your iPhone.")
                    }
                }
            }
            .navigationTitle("CueCard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingHelp = true } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Reading on Apple Watch")
                }
            }
            .sheet(isPresented: $showingHelp) {
                NavigationStack {
                    List {
                        Section("Reading Cards") {
                            Text("Swipe to turn a card. Turn the Digital Crown to scroll longer cards.")
                            Text("Decks saved on your watch work even without your iPhone.")
                        }
                        Section("During a Talk") {
                            Text(WatchTips.returnToClock)
                        }
                    }
                    .font(.footnote)
                    .navigationTitle("Reading Tips")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingHelp = false }
                        }
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .teleprompter:
                    TeleprompterRemoteView()
                case .phoneDeck:
                    PhoneDeckView()
                case .savedDeck(let id):
                    SavedDeckView(deckID: id)
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
            guard session != nil, path.last != .phoneDeck else { return }
            // Opened from here, the deck is already up.
            if case .savedDeck(let id)? = path.last, id == connector.phone?.cards?.deckID { return }
            path = [.phoneDeck]
        }
    }
}
