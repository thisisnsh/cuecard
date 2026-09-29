import Foundation
import CoreData
import SwiftData

/// A saved note as it's kept on disk and in iCloud. CloudKit needs every
/// property to have a default, and can't hold a unique constraint, so the same
/// note can arrive twice; `NoteStore` keeps the newest copy.
@Model
final class StoredNote {
    var id: UUID = UUID()
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

/// Saved notes, kept with SwiftData and synced through the user's iCloud.
/// Only what the user saves lands here; the script being written stays in
/// UserDefaults until then.
@MainActor
final class NoteStore {
    static let cloudKitContainer = "iCloud.com.thisisnsh.cuecard.ios"

    private let container: ModelContainer?
    private var remoteChangeObserver: NSObjectProtocol?

    /// Called when notes saved on another device have come in.
    var onRemoteChange: (() -> Void)?

    init() {
        let synced = ModelConfiguration("Notes", cloudKitDatabase: .private(Self.cloudKitContainer))
        let local = ModelConfiguration("Notes", cloudKitDatabase: .none)
        // Without iCloud the notes are still kept, just on this device.
        container = (try? ModelContainer(for: StoredNote.self, configurations: synced))
            ?? (try? ModelContainer(for: StoredNote.self, configurations: local))

        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onRemoteChange?() }
        }
    }

    var isAvailable: Bool { container != nil }

    /// A fresh context each time, so what's read is what's in the store now,
    /// including anything iCloud has just brought in.
    private func makeContext() -> ModelContext? {
        guard let container else { return nil }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    /// Every saved note, with any copies of the same one folded into the newest.
    func fetchAll() -> [SavedNote] {
        guard let context = makeContext(),
              let stored = try? context.fetch(FetchDescriptor<StoredNote>()) else { return [] }

        var newest: [UUID: StoredNote] = [:]
        var copies: [StoredNote] = []
        for note in stored {
            if let kept = newest[note.id] {
                if note.updatedAt > kept.updatedAt {
                    copies.append(kept)
                    newest[note.id] = note
                } else {
                    copies.append(note)
                }
            } else {
                newest[note.id] = note
            }
        }
        if !copies.isEmpty {
            copies.forEach(context.delete)
            try? context.save()
        }
        return newest.values.map(\.savedNote)
    }

    /// Write notes in, adding them or replacing what's saved under their IDs.
    @discardableResult
    func save(_ notes: [SavedNote]) -> Bool {
        guard let context = makeContext() else { return false }
        for note in notes {
            let id = note.id
            let existing = (try? context.fetch(FetchDescriptor<StoredNote>(
                predicate: #Predicate { $0.id == id }))) ?? []
            if existing.isEmpty {
                context.insert(StoredNote(note))
            } else {
                existing.forEach { $0.update(from: note) }
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
        guard let context = makeContext() else { return }
        try? context.delete(model: StoredNote.self, where: #Predicate { $0.id == id })
        try? context.save()
    }

    func deleteAll() {
        guard let context = makeContext() else { return }
        try? context.delete(model: StoredNote.self)
        try? context.save()
    }
}
