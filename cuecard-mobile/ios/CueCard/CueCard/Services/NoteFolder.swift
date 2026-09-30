import Foundation

/// A folder the user picked in Files where saved notes are also kept, one text
/// file each. It sits outside the app, so the notes stay if the app is deleted,
/// and edits made to the files outside the app come back in on the next sync.
@MainActor
final class NoteFolder {
    /// What's needed to match a file to its note, kept in a hidden index in
    /// the folder so a reinstalled app can pick the notes back up.
    private struct Entry: Codable {
        var file: String
        var title: String
        var mode: ScriptMode
        var createdAt: Date
        /// The note's `updatedAt` when the file was last in step with it.
        var noteUpdatedAt: Date
        /// The file's modification date then, to tell when it's been edited.
        var fileModifiedAt: Date?
    }

    /// What a sync found changed in the folder, for the app to take in.
    struct Changes {
        var updated: [SavedNote] = []
        var deleted: [UUID] = []
    }

    private let bookmarkKey = "cuecard_notes_folder_bookmark"
    private let indexName = ".cuecard.json"
    private let textExtensions: Set<String> = ["txt", "md"]
    private let fileManager = FileManager.default

    var isChosen: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// The folder's name, or nil if there's none or it can't be reached.
    var name: String? {
        resolve()?.lastPathComponent
    }

    /// Start keeping notes in `url`, a folder picked with the document picker.
    func choose(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData()
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    /// Stop using the folder. The files in it are left alone.
    func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Write a note to its file, renaming the file if the title changed.
    func write(_ note: SavedNote) {
        withFolder { folder in
            var index = readIndex(in: folder)
            write(note, into: &index, in: folder)
            writeIndex(index, in: folder)
        }
    }

    func remove(id: UUID) {
        withFolder { folder in
            var index = readIndex(in: folder)
            guard let entry = index.removeValue(forKey: id) else { return }
            try? fileManager.removeItem(at: folder.appendingPathComponent(entry.file))
            writeIndex(index, in: folder)
        }
    }

    /// Delete every file CueCard wrote. Anything else in the folder stays.
    func removeAll() {
        withFolder { folder in
            for entry in readIndex(in: folder).values {
                try? fileManager.removeItem(at: folder.appendingPathComponent(entry.file))
            }
            writeIndex([:], in: folder)
        }
    }

    /// Bring the folder and the app's notes in step: files edited, added,
    /// renamed or deleted outside the app come back as `Changes`, and notes the
    /// folder doesn't have yet are written to it. Whichever side changed last wins.
    func sync(_ notes: [SavedNote]) -> Changes {
        withFolder { folder in
            sync(notes, in: folder)
        } ?? Changes()
    }

    // MARK: - Syncing

    private func sync(_ notes: [SavedNote], in folder: URL) -> Changes {
        // If the folder can't be listed, nothing can be told about it, so
        // nothing is changed on either side.
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return Changes() }

        var changes = Changes()
        var index = readIndex(in: folder)
        let originalIndex = index
        let appNotes = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let files = Set(names.filter { !$0.hasPrefix(".") && textExtensions.contains(fileExtension($0)) })

        // Files in iCloud Drive that aren't downloaded show up as
        // ".Name.txt.icloud". They're still there, so they're asked for and
        // left as they are until they arrive.
        let pending = Set(names.compactMap { name -> String? in
            guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
            try? fileManager.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(name))
            return String(name.dropFirst().dropLast(".icloud".count))
        })

        var claimed = Set<String>()
        var missing: [UUID] = []

        for (id, entry) in originalIndex {
            if pending.contains(entry.file) {
                claimed.insert(entry.file)
                continue
            }
            guard files.contains(entry.file) else {
                missing.append(id)
                continue
            }
            claimed.insert(entry.file)

            let url = folder.appendingPathComponent(entry.file)
            let modified = modificationDate(of: url)
            let fileChanged = !sameDate(modified, entry.fileModifiedAt)
            let app = appNotes[id]

            if let app, !sameDate(app.updatedAt, entry.noteUpdatedAt), app.updatedAt > entry.noteUpdatedAt,
               !fileChanged || app.updatedAt >= (modified ?? .distantPast) {
                write(app, into: &index, in: folder)
            } else if fileChanged || app == nil {
                // Edited outside the app, or a note this install doesn't have
                // yet, as after the app is reinstalled.
                guard let content = readContent(of: url) else { continue }
                let note = SavedNote(id: id, title: entry.title, content: content, mode: entry.mode,
                                     createdAt: entry.createdAt,
                                     updatedAt: fileChanged ? (modified ?? Date()) : entry.noteUpdatedAt)
                if app != note { changes.updated.append(note) }
                index[id]?.noteUpdatedAt = note.updatedAt
                index[id]?.fileModifiedAt = modified
            }
        }

        var unknown = files.subtracting(claimed)

        // Every file gone at once is more likely a folder that hasn't loaded
        // than one the user emptied, so notes are only let go of while some
        // of their files are still there.
        if !missing.isEmpty, !claimed.isEmpty {
            for id in missing {
                guard let entry = index[id] else { continue }
                // A file renamed outside the app still holds the same text.
                let content = appNotes[id]?.content
                if let content, let renamed = unknown.sorted().first(where: {
                    readContent(of: folder.appendingPathComponent($0)) == content
                }) {
                    unknown.remove(renamed)
                    guard var note = appNotes[id] else { continue }
                    let url = folder.appendingPathComponent(renamed)
                    note.title = ScriptFile.title(for: url)
                    changes.updated.append(note)
                    index[id] = Entry(file: renamed, title: note.title, mode: entry.mode,
                                      createdAt: entry.createdAt, noteUpdatedAt: note.updatedAt,
                                      fileModifiedAt: modificationDate(of: url))
                } else {
                    index.removeValue(forKey: id)
                    if appNotes[id] != nil { changes.deleted.append(id) }
                }
            }
        }

        // Files added outside the app become new notes.
        for file in unknown.sorted() {
            let url = folder.appendingPathComponent(file)
            guard let content = readContent(of: url) else { continue }
            let modified = modificationDate(of: url) ?? Date()
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? modified
            let mode: ScriptMode = CueCards.separatorRanges(in: content).isEmpty ? .teleprompter : .cards
            let note = SavedNote(title: ScriptFile.title(for: url), content: content, mode: mode,
                                 createdAt: created, updatedAt: modified)
            changes.updated.append(note)
            index[note.id] = Entry(file: file, title: note.title, mode: mode, createdAt: created,
                                   noteUpdatedAt: modified, fileModifiedAt: modificationDate(of: url))
        }

        // Notes the folder doesn't have yet, as when it's first chosen.
        let deleted = Set(changes.deleted)
        for note in notes where index[note.id] == nil && !deleted.contains(note.id) {
            write(note, into: &index, in: folder)
        }

        if !sameIndex(index, originalIndex) {
            writeIndex(index, in: folder)
        }
        return changes
    }

    // MARK: - Files

    private func write(_ note: SavedNote, into index: inout [UUID: Entry], in folder: URL) {
        let existing = index[note.id]
        var file = existing?.file
        if let current = file, existing?.title != note.title {
            // Renamed in the app, so the file follows, keeping its extension.
            let taken = takenNames(in: folder, index: index).subtracting([current])
            let renamed = uniqueName(for: note, extension: fileExtension(current), taken: taken)
            if renamed != current,
               (try? fileManager.moveItem(at: folder.appendingPathComponent(current),
                                          to: folder.appendingPathComponent(renamed))) != nil {
                file = renamed
            }
        }
        let name = file ?? uniqueName(for: note, extension: "txt", taken: takenNames(in: folder, index: index))
        let url = folder.appendingPathComponent(name)
        guard (try? Data(note.content.utf8).write(to: url, options: .atomic)) != nil else { return }
        index[note.id] = Entry(file: name, title: note.title, mode: note.mode, createdAt: note.createdAt,
                               noteUpdatedAt: note.updatedAt, fileModifiedAt: modificationDate(of: url))
    }

    private func takenNames(in folder: URL, index: [UUID: Entry]) -> Set<String> {
        let onDisk = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(onDisk.map { $0.lowercased() } + index.values.map { $0.file.lowercased() })
    }

    /// The note's title as a file name, numbered if another file has it.
    private func uniqueName(for note: SavedNote, extension ext: String, taken: Set<String>) -> String {
        let base = ScriptFile.suggestedFileName(title: note.title, content: note.content)
        var name = "\(base).\(ext)"
        var number = 2
        while taken.contains(name.lowercased()) {
            name = "\(base) \(number).\(ext)"
            number += 1
        }
        return name
    }

    private func readContent(of url: URL) -> String? {
        guard let text = try? ScriptFile.readText(from: url) else { return nil }
        return TeleprompterParser.normalizingTags(in: text)
    }

    private func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func fileExtension(_ name: String) -> String {
        (name as NSString).pathExtension.lowercased()
    }

    /// Dates read back from the index can be off in the last fraction.
    private func sameDate(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < 0.001
    }

    private func sameIndex(_ a: [UUID: Entry], _ b: [UUID: Entry]) -> Bool {
        guard a.count == b.count else { return false }
        return a.allSatisfy { id, entry in
            guard let other = b[id] else { return false }
            return entry.file == other.file && entry.title == other.title && entry.mode == other.mode
                && sameDate(entry.noteUpdatedAt, other.noteUpdatedAt)
                && sameDate(entry.fileModifiedAt, other.fileModifiedAt)
        }
    }

    // MARK: - Index and access

    private func readIndex(in folder: URL) -> [UUID: Entry] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(indexName)),
              let index = try? JSONDecoder().decode([UUID: Entry].self, from: data) else { return [:] }
        return index
    }

    private func writeIndex(_ index: [UUID: Entry], in folder: URL) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: folder.appendingPathComponent(indexName), options: .atomic)
    }

    private func resolve() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale { try? choose(url) }
        return url
    }

    /// Run `body` with the folder open, if there is one and it can be reached.
    @discardableResult
    private func withFolder<T>(_ body: (URL) -> T) -> T? {
        guard let url = resolve() else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return body(url)
    }
}
