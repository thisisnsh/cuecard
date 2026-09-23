import Foundation

/// The decks the iPhone has put on the watch, kept on the watch so they can be
/// read with the iPhone out of reach.
@MainActor
final class DeckStore: ObservableObject {
    static let shared = DeckStore()

    @Published private(set) var decks: [WatchDeck] = []
    /// Where each deck was left, so it opens there again.
    @Published private var positions: [String: Int]

    private static let positionsKey = "deck_positions"

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("decks.json")
    }

    private init() {
        positions = UserDefaults.standard.dictionary(forKey: Self.positionsKey) as? [String: Int] ?? [:]
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([WatchDeck].self, from: data) {
            decks = decoded
        }
    }

    func deck(id: UUID) -> WatchDeck? {
        decks.first { $0.id == id }
    }

    func position(of id: UUID) -> Int {
        positions[id.uuidString] ?? 0
    }

    func setPosition(_ index: Int, of id: UUID) {
        guard positions[id.uuidString] != index else { return }
        positions[id.uuidString] = index
        UserDefaults.standard.set(positions, forKey: Self.positionsKey)
    }

    /// Take the iPhone's set in place of the one here.
    func replace(with data: Data) {
        guard let decoded = try? JSONDecoder().decode([WatchDeck].self, from: data) else { return }
        decks = decoded
        // A deck taken off the watch forgets where it was.
        let ids = Set(decoded.map(\.id.uuidString))
        positions = positions.filter { ids.contains($0.key) }
        UserDefaults.standard.set(positions, forKey: Self.positionsKey)

        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
