import Foundation

/// The decks the iPhone has put on the watch, kept on the watch so they can be
/// read with the iPhone out of reach.
@MainActor
final class DeckStore: ObservableObject {
    static let shared = DeckStore()

    @Published private(set) var decks: [WatchDeck] = []

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("decks.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([WatchDeck].self, from: data) {
            decks = decoded
        }
    }

    func deck(id: UUID) -> WatchDeck? {
        decks.first { $0.id == id }
    }

    /// Take the iPhone's set in place of the one here.
    func replace(with data: Data) {
        guard let decoded = try? JSONDecoder().decode([WatchDeck].self, from: data) else { return }
        decks = decoded

        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
