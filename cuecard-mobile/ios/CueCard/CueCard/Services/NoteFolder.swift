import Foundation

/// A folder the user picked in Files where saved notes are also kept, one text
/// file each. It sits outside the app, so the notes stay if the app is deleted,
/// and edits made to the files outside the app come back in on the next sync.
///
/// The images the notes place are kept beside them, in a hidden folder of
/// CueCard's own, so they come back with the notes too.
///
/// Every note's file sits at the top of the folder. The library's folders
/// aren't folders on disk: how the notes are filed in them is kept in a
/// hidden file of CueCard's own, so it comes back with the notes too.
@MainActor
final class NoteFolder {
    /// What's needed to match a file to its note, kept in a hidden index in
    /// the folder so a reinstalled app can pick the notes back up.
    private struct Entry: Codable {
        /// The file's path in the folder: its name, or, for a file not yet
        /// moved out of a library folder that was a folder on disk, that
        /// folder's name and its name.
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
        /// Files over `ScriptFile.maxFileSize`, by name. They're left unread.
        var tooLarge: [String] = []
        /// Files of notes deleted in the app that couldn't be deleted yet, by name.
        var undeletable: [String] = []
        /// The library's folders once the folder's own list is taken in, or
        /// nil if the folder couldn't be looked at.
        var folders: [String]?
    }

    /// How the notes are filed in the library's folders. Every note the
    /// folder knows is listed, in its folder or with the unfiled ones, so a
    /// note moved out of a folder elsewhere moves out here too.
    private struct Library: Codable, Equatable {
        struct Folder: Codable, Equatable {
            var name: String
            var notes: [UUID]
        }

        var folders: [Folder]
        var unfiled: [UUID]

        /// The folder a note is filed in: nil for none, or `.some(nil)` for
        /// the top of the library.
        func folder(of id: UUID) -> String?? {
            if unfiled.contains(id) { return .some(nil) }
            return folders.first { $0.notes.contains(id) }.map { .some($0.name) }
        }
    }

    private let bookmarkKey = "cuecard_notes_folder_bookmark"
    private let pendingDeletionsKey = "cuecard_notes_folder_pending_deletions"
    /// Library folders from when they were folders on disk, whose files are
    /// still being moved out to the top.
    private let oldFoldersKey = "cuecard_notes_folder_known_folders"
    /// The library file's modification date when it was last in step, to
    /// tell when it's been changed outside the app.
    private let libraryModifiedKey = "cuecard_notes_folder_library_modified"
    /// The library's folders when the list was last in step, to tell a
    /// folder made or deleted in the app from one deleted or made elsewhere.
    private let syncedFoldersKey = "cuecard_notes_folder_synced_folders"
    private let indexName = ".cuecard.json"
    private let libraryName = ".cuecard-library.json"
    /// Only CueCard writes in here, and it deletes what no note places.
    private let imagesFolderName = ".cuecard-images"
    private let textExtensions: Set<String> = ["txt", "md"]
    private let fileManager = FileManager.default

    var isChosen: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// The folder's name, or nil if there's none or it can't be reached.
    var name: String? {
        resolve()?.lastPathComponent
    }

    /// Whether the folder is in iCloud Drive. False if it can't be reached.
    var isInICloud: Bool {
        guard let url = resolve() else { return false }
        // iCloud Drive's folders are all under Mobile Documents; the system
        // can't always say so for a folder outside the app's own containers.
        return url.path.contains("/Mobile Documents/") || fileManager.isUbiquitousItem(at: url)
    }

    /// Notes deleted in the app whose files couldn't be deleted from the
    /// folder yet. Kept outside the folder, which may not take changes, so
    /// the files aren't read back in as notes; each sync tries them again.
    private var pendingDeletions: Set<UUID> {
        get {
            let ids = UserDefaults.standard.stringArray(forKey: pendingDeletionsKey) ?? []
            return Set(ids.compactMap(UUID.init(uuidString:)))
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: pendingDeletionsKey)
            } else {
                UserDefaults.standard.set(newValue.map(\.uuidString), forKey: pendingDeletionsKey)
            }
        }
    }

    private var oldFolders: [String] {
        get { UserDefaults.standard.stringArray(forKey: oldFoldersKey) ?? [] }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: oldFoldersKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: oldFoldersKey)
            }
        }
    }

    private var libraryModifiedAt: Date? {
        get { UserDefaults.standard.object(forKey: libraryModifiedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: libraryModifiedKey) }
    }

    private var syncedFolders: [String]? {
        get { UserDefaults.standard.stringArray(forKey: syncedFoldersKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncedFoldersKey) }
    }

    /// Start keeping notes in `url`, a folder picked with the document picker.
    /// How its notes are filed, if CueCard kept them there before, is taken in.
    func choose(_ url: URL) throws {
        try saveBookmark(for: url)
        pendingDeletions = []
        oldFolders = []
        libraryModifiedAt = nil
        syncedFolders = nil
    }

    /// Stop using the folder. The files in it are left alone.
    func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        pendingDeletions = []
        oldFolders = []
        libraryModifiedAt = nil
        syncedFolders = nil
    }

    /// Write a note to its file, renaming the file if the title changed.
    func write(_ note: SavedNote) {
        withFolder { folder in
            var index = readIndex(in: folder)
            write(note, into: &index, in: folder)
            writeIndex(index, in: folder)
        }
    }

    /// Write down how the notes are filed in the library's folders, after
    /// one is moved or saved. If the list was changed outside the app since
    /// it was last in step, it's left for the next sync to take in first.
    func arrange(_ notes: [SavedNote], folders: [String]) {
        withFolder { folder in
            let stored = readLibrary(in: folder)
            if let stored, !sameDate(stored.modified, libraryModifiedAt) { return }
            let index = readIndex(in: folder)
            let appNotes = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let ids = Set(index.keys).union(appNotes.keys).subtracting(pendingDeletions)
            let library = makeLibrary(ids: ids, folders: folders) { id in
                if let note = appNotes[id] { return note.folder }
                return stored?.library.folder(of: id) ?? nil
            }
            if library != stored?.library { writeLibrary(library, in: folder) }
        }
    }

    /// Delete the files of notes deleted in the app. Any that can't be, as
    /// in a read-only folder or one out of reach, are tried again on each
    /// sync and kept from coming back in as notes meanwhile. Returns whether
    /// they're all gone.
    @discardableResult
    func remove(_ ids: Set<UUID>) -> Bool {
        guard isChosen else { return true }
        pendingDeletions.formUnion(ids)
        withFolder { folder in
            var index = readIndex(in: folder)
            let original = index
            deletePending(from: &index, in: folder)
            if !sameIndex(index, original) { writeIndex(index, in: folder) }
        }
        return pendingDeletions.isDisjoint(with: ids)
    }

    /// Delete every file CueCard wrote and stop using the folder. Anything
    /// else in it stays. If a file can't be deleted, or the folder can't be
    /// reached, the folder stays in use and false is returned.
    func release() -> Bool {
        let released = withFolder { folder -> Bool in
            let index = readIndex(in: folder)
            let kept = index.filter { !delete($0.value.file, in: folder) }
            pendingDeletions.formIntersection(kept.keys)
            writeIndex(kept, in: folder)
            let images = folder.appendingPathComponent(imagesFolderName, isDirectory: true)
            let imagesDeleted = !fileManager.fileExists(atPath: images.path)
                || (try? fileManager.removeItem(at: images)) != nil
            let library = folder.appendingPathComponent(libraryName)
            let libraryDeleted = !fileManager.fileExists(atPath: library.path)
                || (try? fileManager.removeItem(at: library)) != nil
            // Folders on disk from before go too, once nothing else is in them.
            for name in oldFolders {
                removeIfEmpty(name, in: folder)
            }
            return kept.isEmpty && imagesDeleted && libraryDeleted
        } ?? false
        if released { forget() }
        return released
    }

    /// Bring the folder and the app's notes in step: files edited, added,
    /// renamed, moved or deleted outside the app come back as `Changes`, and
    /// notes the folder doesn't have yet are written to it. Whichever side
    /// changed last wins. How the notes are filed in the library's `folders`
    /// is brought in step the same way.
    func sync(_ notes: [SavedNote], folders: [String]) -> Changes {
        withFolder { folder in
            sync(notes, folders: folders, in: folder)
        } ?? Changes()
    }

    // MARK: - Syncing

    private func sync(_ notes: [SavedNote], folders: [String], in folder: URL) -> Changes {
        // If the folder can't be listed, nothing can be told about it, so
        // nothing is changed on either side.
        guard (try? fileManager.contentsOfDirectory(atPath: folder.path)) != nil else { return Changes() }

        var changes = Changes()
        var index = readIndex(in: folder)
        let originalIndex = index
        // Files of deleted notes still there are left alone, not read back in.
        let undeletable = deletePending(from: &index, in: folder)
        changes.undeletable = undeletable.values.map(\.file).sorted()
        let appNotes = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The folders each file moved out of the old folders on disk was in.
        let movedFrom = moveOutOfOldFolders(index: &index, in: folder)
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        // Everything at the top of the folder, and in any old folder on disk
        // not emptied yet.
        let paths = names + oldFolders.flatMap { subfolder in
            ((try? fileManager.contentsOfDirectory(atPath: folder.appendingPathComponent(subfolder).path)) ?? [])
                .map { "\(subfolder)/\($0)" }
        }
        let files = Set(paths.filter {
            !fileName(of: $0).hasPrefix(".") && textExtensions.contains(fileExtension($0))
        })
        // Reading one of these fails, which leaves it and its note as they are.
        changes.tooLarge = files.filter { ScriptFile.isTooLarge(folder.appendingPathComponent($0)) }.sorted()

        // Files in iCloud Drive that aren't downloaded show up as
        // ".Name.txt.icloud". They're still there, so they're asked for and
        // left as they are until they arrive.
        let pending = Set(paths.compactMap { path -> String? in
            let name = fileName(of: path)
            guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
            try? fileManager.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(path))
            return self.path(String(name.dropFirst().dropLast(".icloud".count)), in: folderName(ofFile: path))
        })

        var claimed = Set<String>()
        var missing: [UUID] = []

        for (id, entry) in index {
            if pending.contains(entry.file) || undeletable[id] != nil {
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
                // Its library folder is settled below, with the others'.
                let note = SavedNote(id: id, title: entry.title, content: content, mode: entry.mode,
                                     folder: app?.folder, createdAt: entry.createdAt,
                                     updatedAt: fileChanged ? (modified ?? Date()) : entry.noteUpdatedAt)
                if app != note { changes.updated.append(note) }
                index[id]?.noteUpdatedAt = note.updatedAt
                index[id]?.fileModifiedAt = modified
            }
        }

        var unknown = files.subtracting(claimed)

        // Every file gone at once is more likely a folder that hasn't loaded
        // than one the user emptied, so notes are only let go of while the
        // folder still lists some file. A note's own file renamed counts, so
        // a folder of one note keeps it through a rename.
        if !missing.isEmpty, !files.isEmpty {
            for id in missing {
                guard let entry = index[id] else { continue }
                // A file renamed or moved outside the app still holds the same text.
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

        arrange(notes: appNotes, folders: folders, index: index, deleted: deleted,
                movedFrom: movedFrom, changes: &changes, in: folder)

        // Every note as it stands after the sync, for the images they place.
        let updated = Dictionary(changes.updated.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let contents = notes.filter { !deleted.contains($0.id) }.map { updated[$0.id]?.content ?? $0.content }
            + changes.updated.filter { appNotes[$0.id] == nil }.map(\.content)
        // A note file that couldn't be read yet may place images no note
        // here does, so none are deleted until every file has been.
        let readAll = pending.isEmpty && changes.tooLarge.isEmpty && (!files.isEmpty || originalIndex.isEmpty)
        syncImages(placedIn: contents, in: folder, deletingUnplaced: readAll)
        return changes
    }

    // MARK: - Library folders

    /// Bring how the notes are filed in step with the folder's own list.
    /// If the list was changed outside the app since it was last in step,
    /// as on another device or before the app was reinstalled, it wins;
    /// otherwise the app does. Notes changed folder are added to `changes`.
    private func arrange(notes appNotes: [UUID: SavedNote], folders: [String], index: [UUID: Entry],
                         deleted: Set<UUID>, movedFrom: [String: String], changes: inout Changes,
                         in folder: URL) {
        let stored = readLibrary(in: folder)
        let changedOutside = stored.map { !sameDate($0.modified, libraryModifiedAt) } ?? false
        let listed = stored?.library
        let ids = Set(index.keys).union(appNotes.keys).union(changes.updated.map(\.id))
            .subtracting(deleted).subtracting(pendingDeletions)

        /// The library folder a note was in when it was a folder on disk.
        func oldFolder(of id: UUID) -> String? {
            guard let file = index[id]?.file else { return nil }
            return movedFrom[file] ?? folderName(ofFile: file)
        }

        var names = folders
        if changedOutside, let listed {
            // The list's folders, but for those deleted here since it was
            // last in step, and those made here since.
            let synced = syncedFolders ?? []
            names = listed.folders.map(\.name).filter { !synced.containsFolder($0) || folders.containsFolder($0) }
            for name in folders where !synced.containsFolder(name) && !names.containsFolder(name) {
                names.append(name)
            }
        }
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            // Folders the list doesn't know yet: one a note here is in that
            // the list doesn't place, and one that was a folder on disk.
            let extra: String?
            if listed?.folder(of: id) != nil {
                extra = nil
            } else if let app = appNotes[id] {
                extra = changedOutside ? app.folder : nil
            } else {
                extra = oldFolder(of: id)
            }
            if let extra, !names.containsFolder(extra) { names.append(extra) }
        }

        func folderOf(_ id: UUID) -> String? {
            let name: String?
            if changedOutside, let placed = listed?.folder(of: id) {
                name = placed
            } else if let app = appNotes[id] {
                name = app.folder
            } else if let placed = listed?.folder(of: id) {
                name = placed
            } else {
                name = oldFolder(of: id)
            }
            // Named as the list names it; in none it's in no longer, at the top.
            return name.flatMap { name in names.first { $0.caseInsensitiveCompare(name) == .orderedSame } }
        }

        let library = makeLibrary(ids: ids, folders: names, folderOf: folderOf)
        for id in ids {
            let name = library.folder(of: id) ?? nil
            if let i = changes.updated.firstIndex(where: { $0.id == id }) {
                changes.updated[i].folder = name
            } else if var note = appNotes[id], note.folder != name {
                note.folder = name
                changes.updated.append(note)
            }
        }
        changes.folders = names

        if library != listed {
            writeLibrary(library, in: folder)
        } else if let stored {
            libraryModifiedAt = stored.modified
            syncedFolders = names
        }
    }

    /// The list of `folders` with each of `ids` filed in its folder, or with
    /// the unfiled ones. Sorted, so an unchanged list is written the same.
    private func makeLibrary(ids: Set<UUID>, folders: [String], folderOf: (UUID) -> String?) -> Library {
        var filed: [String: [UUID]] = [:]
        var unfiled: [UUID] = []
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            if let name = folderOf(id), let match = folders.first(where: {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }) {
                filed[match, default: []].append(id)
            } else {
                unfiled.append(id)
            }
        }
        return Library(folders: folders.map { Library.Folder(name: $0, notes: filed[$0] ?? []) },
                       unfiled: unfiled)
    }

    /// Library folders used to be folders on disk, with their notes' files
    /// in them. Each sync moves what's left in them out to the top, beside
    /// the others, and deletes each once it's empty. Returns the folder each
    /// moved file was in, by its new name.
    private func moveOutOfOldFolders(index: inout [UUID: Entry], in folder: URL) -> [String: String] {
        var old = oldFolders
        // A file still in one, as when the app was reinstalled since.
        for entry in index.values {
            if let name = folderName(ofFile: entry.file), !old.containsFolder(name) { old.append(name) }
        }
        guard !old.isEmpty else { return [:] }

        var movedFrom: [String: String] = [:]
        var remaining: [String] = []
        for name in old {
            let directory = folder.appendingPathComponent(name, isDirectory: true)
            guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
                // Still there but can't be listed: tried again next time.
                if fileManager.fileExists(atPath: directory.path) { remaining.append(name) }
                continue
            }
            for file in contents.sorted() where !file.hasPrefix(".") && textExtensions.contains(fileExtension(file)) {
                let current = path(file, in: name)
                let base = (file as NSString).deletingPathExtension
                let target = uniqueName(base: base, extension: (file as NSString).pathExtension,
                                        taken: takenNames(in: folder, index: index))
                guard (try? fileManager.moveItem(at: directory.appendingPathComponent(file),
                                                 to: folder.appendingPathComponent(target))) != nil else { continue }
                movedFrom[target] = name
                if let id = index.first(where: { $0.value.file == current })?.key {
                    index[id]?.file = target
                }
            }
            // Files in iCloud Drive that aren't downloaded keep it until they are.
            if !removeIfEmpty(name, in: folder) { remaining.append(name) }
        }
        oldFolders = remaining
        return movedFrom
    }

    /// Delete an old folder on disk if nothing but Finder's leftovers is in
    /// it. True once it's gone.
    @discardableResult
    private func removeIfEmpty(_ name: String, in folder: URL) -> Bool {
        let url = folder.appendingPathComponent(name, isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return !fileManager.fileExists(atPath: url.path)
        }
        guard contents.allSatisfy({ $0 == ".DS_Store" }) else { return false }
        return (try? fileManager.removeItem(at: url)) != nil
    }

    // MARK: - Images

    /// Bring in the images the notes place that this device doesn't have,
    /// as after the app is reinstalled, and delete the folder's copies of
    /// any no note places any more.
    private func syncImages(placedIn contents: [String], in folder: URL, deletingUnplaced: Bool) {
        let images = folder.appendingPathComponent(imagesFolderName, isDirectory: true)
        let names = Set(contents.flatMap { TeleprompterParser.imageNames(in: $0) })

        for name in names where !ScriptImages.contains(name) {
            let url = images.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url) {
                ScriptImages.add(data, named: name)
            } else {
                // Not downloaded from iCloud Drive yet; it's taken in once it is.
                try? fileManager.startDownloadingUbiquitousItem(at: url)
            }
        }

        guard deletingUnplaced, let files = try? fileManager.contentsOfDirectory(atPath: images.path) else { return }
        for file in files {
            // A file in iCloud Drive that isn't downloaded is ".name.icloud".
            let name = file.hasPrefix(".") && file.hasSuffix(".icloud")
                ? String(file.dropFirst().dropLast(".icloud".count)) : file
            if !names.contains(name) {
                try? fileManager.removeItem(at: images.appendingPathComponent(file))
            }
        }
    }

    /// Copy the images a note places into the folder, the ones not already there.
    private func writeImages(placedIn content: String, in folder: URL) {
        let names = TeleprompterParser.imageNames(in: content)
        guard !names.isEmpty else { return }
        let images = folder.appendingPathComponent(imagesFolderName, isDirectory: true)
        try? fileManager.createDirectory(at: images, withIntermediateDirectories: true)
        for name in names {
            let url = images.appendingPathComponent(name)
            guard !fileManager.fileExists(atPath: url.path),
                  !fileManager.fileExists(atPath: images.appendingPathComponent(".\(name).icloud").path),
                  let data = ScriptImages.data(named: name) else { continue }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Files

    /// Try again to delete the files of notes deleted in the app, dropping
    /// each from the index once it's gone. Returns the entries still waiting.
    @discardableResult
    private func deletePending(from index: inout [UUID: Entry], in folder: URL) -> [UUID: Entry] {
        var waiting: [UUID: Entry] = [:]
        for id in pendingDeletions {
            if let entry = index[id], !delete(entry.file, in: folder) {
                waiting[id] = entry
            } else {
                index.removeValue(forKey: id)
            }
        }
        pendingDeletions = Set(waiting.keys)
        return waiting
    }

    /// Delete a file, and its placeholder if it's in iCloud Drive and not
    /// downloaded. True once neither is there.
    private func delete(_ file: String, in folder: URL) -> Bool {
        [file, path(".\(fileName(of: file)).icloud", in: folderName(ofFile: file))].allSatisfy { name in
            let url = folder.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { return true }
            return (try? fileManager.removeItem(at: url)) != nil
        }
    }

    private func write(_ note: SavedNote, into index: inout [UUID: Entry], in folder: URL) {
        let existing = index[note.id]
        let titleBase = ScriptFile.suggestedFileName(title: note.title, content: note.content)
        var file = existing?.file
        if let current = file, existing?.title != note.title {
            // Renamed in the app, so the file follows, keeping its extension.
            var taken = takenNames(in: folder, index: index)
            if folderName(ofFile: current) == nil { taken.remove(current.lowercased()) }
            let target = uniqueName(base: titleBase, extension: fileExtension(current), taken: taken)
            if target != current,
               (try? fileManager.moveItem(at: folder.appendingPathComponent(current),
                                          to: folder.appendingPathComponent(target))) != nil {
                file = target
            }
        }
        let name = file ?? uniqueName(base: titleBase, extension: "txt", taken: takenNames(in: folder, index: index))
        let url = folder.appendingPathComponent(name)
        writeImages(placedIn: note.content, in: folder)
        guard (try? Data(note.content.utf8).write(to: url, options: .atomic)) != nil else { return }
        index[note.id] = Entry(file: name, title: note.title, mode: note.mode, createdAt: note.createdAt,
                               noteUpdatedAt: note.updatedAt, fileModifiedAt: modificationDate(of: url))
    }

    /// The names in use at the top of the folder, lowercased.
    private func takenNames(in folder: URL, index: [UUID: Entry]) -> Set<String> {
        let onDisk = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        let indexed = index.values.map(\.file).filter { folderName(ofFile: $0) == nil }
        return Set((onDisk + indexed).map { $0.lowercased() })
    }

    /// `base` as a file name, numbered if another file has it.
    private func uniqueName(base: String, extension ext: String, taken: Set<String>) -> String {
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

    /// The old folder on disk a file's path is in, or nil for the top.
    private func folderName(ofFile path: String) -> String? {
        let parts = path.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[0]) : nil
    }

    /// The file's own name, without its old folder.
    private func fileName(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private func path(_ name: String, in subfolder: String?) -> String {
        subfolder.map { "\($0)/\(name)" } ?? name
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
        // The index sits in the folder, where anything else with access can
        // rewrite it. An entry naming a path rather than a file in the folder
        // could have files elsewhere moved or deleted, so it's dropped. A
        // file in a library folder is the one path allowed.
        return index.filter { isNotePath($0.value.file) }
    }

    /// A file's name, or a visible folder's name and a file's name.
    private func isNotePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy(isPlainFileName) else { return false }
        return parts.count == 1 || (parts.count == 2 && !parts[0].hasPrefix("."))
    }

    private func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    private func writeIndex(_ index: [UUID: Entry], in folder: URL) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: folder.appendingPathComponent(indexName), options: .atomic)
    }

    /// The folder's list of how the notes are filed, and when it was last
    /// changed. Like the index, anything with access can rewrite it, but it
    /// only names folders and notes, so it's cleaned up and taken as it is.
    private func readLibrary(in folder: URL) -> (library: Library, modified: Date?)? {
        let url = folder.appendingPathComponent(libraryName)
        guard let data = try? Data(contentsOf: url),
              var library = try? JSONDecoder().decode(Library.self, from: data) else { return nil }
        var seen: [String] = []
        library.folders = library.folders.compactMap { entry in
            let name = ScriptFile.folderName(from: entry.name)
            guard !name.isEmpty, !seen.containsFolder(name) else { return nil }
            seen.append(name)
            return Library.Folder(name: name, notes: entry.notes)
        }
        return (library, modificationDate(of: url))
    }

    private func writeLibrary(_ library: Library, in folder: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = folder.appendingPathComponent(libraryName)
        guard let data = try? encoder.encode(library),
              (try? data.write(to: url, options: .atomic)) != nil else { return }
        libraryModifiedAt = modificationDate(of: url)
        syncedFolders = library.folders.map(\.name)
    }

    private func resolve() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale { try? saveBookmark(for: url) }
        return url
    }

    private func saveBookmark(for url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData()
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
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

extension Array where Element == String {
    /// Whether a folder of this name is in the list, whatever its case.
    func containsFolder(_ name: String) -> Bool {
        contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    mutating func removeFolder(_ name: String) {
        removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}
