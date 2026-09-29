import Foundation
import SwiftData

/// A saved note as it's kept on disk.
@Model
final class StoredNote {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var mode: String = ScriptMode.teleprompter.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(_ note: SavedNote) {
        id = note.id
        update(from: note)
        createdAt = note.createdAt
    }

    func update(from note: SavedNote) {
        title = note.title
        content = note.content
        mode = note.mode.rawValue
        updatedAt = note.updatedAt
    }

    var savedNote: SavedNote {
        SavedNote(id: id, title: title, content: content,
                  mode: ScriptMode(rawValue: mode) ?? .teleprompter,
                  createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// Saved notes, kept with SwiftData on this device only. Only what the user
/// saves lands here; the script being written stays in UserDefaults until then.
@MainActor
final class NoteStore {
    private let container: ModelContainer?

    init() {
        container = try? ModelContainer(for: StoredNote.self,
                                        configurations: ModelConfiguration("Notes", cloudKitDatabase: .none))
    }

    private var context: ModelContext? { container?.mainContext }

    func fetchAll() -> [SavedNote] {
        guard let context,
              let stored = try? context.fetch(FetchDescriptor<StoredNote>()) else { return [] }
        return stored.map(\.savedNote)
    }

    /// Write notes in, adding them or replacing what's saved under their IDs.
    @discardableResult
    func save(_ notes: [SavedNote]) -> Bool {
        guard let context else { return false }
        for note in notes {
            let id = note.id
            let existing = (try? context.fetch(FetchDescriptor<StoredNote>(
                predicate: #Predicate { $0.id == id }))) ?? []
            if let stored = existing.first {
                stored.update(from: note)
            } else {
                context.insert(StoredNote(note))
            }
        }
        do {
            try context.save()
            return true
        } catch {
            return false
        }
    }

    func delete(id: UUID) {
        guard let context else { return }
        try? context.delete(model: StoredNote.self, where: #Predicate { $0.id == id })
        try? context.save()
    }

    func deleteAll() {
        guard let context else { return }
        try? context.delete(model: StoredNote.self)
        try? context.save()
    }
}
