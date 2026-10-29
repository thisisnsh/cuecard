import Foundation

/// A folder the user picked in Files where saved notes are also kept, one text
/// file each. It sits outside the app, so the notes stay if the app is deleted,
/// and edits made to the files outside the app come back in on the next sync.
///
/// The images the notes place are kept beside them, in a hidden folder of
/// CueCard's own, so they come back with the notes too.
///
/// The library's folders are folders in here, one level deep, with the notes
/// filed in them inside. Folders and files moved between them outside the
/// app are moved in the library too.
@MainActor
final class NoteFolder {
    /// What's needed to match a file to its note, kept in a hidden index in
    /// the folder so a reinstalled app can pick the notes back up.
    private struct Entry: Codable {
        /// The file's path in the folder: its name, or a library folder's
        /// name and its name.
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
        /// The library's folders once the folders on disk are taken in, or
        /// nil if they couldn't be looked at.
        var folders: [String]?
    }

    private let bookmarkKey = "cuecard_notes_folder_bookmark"
    private let pendingDeletionsKey = "cuecard_notes_folder_pending_deletions"
    /// The library folders last seen on disk, to tell one deleted outside the
    /// app from one made in it that isn't on disk yet.
    private let knownFoldersKey = "cuecard_notes_folder_known_folders"
    private let indexName = ".cuecard.json"
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

    private var knownFolders: [String] {
        get { UserDefaults.standard.stringArray(forKey: knownFoldersKey) ?? [] }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: knownFoldersKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: knownFoldersKey)
            }
        }
    }

    /// Start keeping notes in `url`, a folder picked with the document picker.
    func choose(_ url: URL) throws {
        try saveBookmark(for: url)
        pendingDeletions = []
        knownFolders = []
    }

    /// Stop using the folder. The files in it are left alone.
    func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        pendingDeletions = []
        knownFolders = []
    }

    /// Write a note to its file, renaming the file if the title changed.
    func write(_ note: SavedNote) {
        withFolder { folder in
            var index = readIndex(in: folder)
            write(note, into: &index, in: folder)
            writeIndex(index, in: folder)
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
            // Library folders CueCard made go too, once nothing else is in them.
            for name in knownFolders {
                removeIfEmpty(name, in: folder)
            }
            return kept.isEmpty && imagesDeleted
        } ?? false
        if released { forget() }
        return released
    }

    /// Bring the folder and the app's notes in step: files edited, added,
    /// renamed, moved or deleted outside the app come back as `Changes`, and
    /// notes the folder doesn't have yet are written to it. Whichever side
    /// changed last wins. The library's `folders` are brought in step the same way.
    func sync(_ notes: [SavedNote], folders: [String]) -> Changes {
        withFolder { folder in
            sync(notes, folders: folders, in: folder)
        } ?? Changes()
    }

    // MARK: - Syncing

    private func sync(_ notes: [SavedNote], folders: [String], in folder: URL) -> Changes {
        // If the folder can't be listed, nothing can be told about it, so
        // nothing is changed on either side.
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return Changes() }

        var changes = Changes()
        var index = readIndex(in: folder)
        let originalIndex = index
        // Files of deleted notes still there are left alone, not read back in.
        let undeletable = deletePending(from: &index, in: folder)
        changes.undeletable = undeletable.values.map(\.file).sorted()
        let appNotes = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Everything at the top of the folder and in the library folders in it.
        let paths = names + subfolders(in: folder, names: names).flatMap { subfolder in
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
                let note = SavedNote(id: id, title: entry.title, content: content, mode: entry.mode,
                                     folder: folderName(ofFile: entry.file), createdAt: entry.createdAt,
                                     updatedAt: fileChanged ? (modified ?? Date()) : entry.noteUpdatedAt)
                if app != note { changes.updated.append(note) }
                index[id]?.noteUpdatedAt = note.updatedAt
                index[id]?.fileModifiedAt = modified
            } else if let app, !sameFolder(app.folder, folderName(ofFile: entry.file)) {
                // Moved to another library folder while this one couldn't be
                // reached. A file moved outside the app is found by its text
                // below instead, as its old path is gone.
                write(app, into: &index, in: folder)
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
                    note.folder = folderName(ofFile: renamed)
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
                                 folder: folderName(ofFile: file), createdAt: created, updatedAt: modified)
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

        // Last, so folders the notes were just moved out of can go.
        changes.folders = syncFolders(folders, in: folder, listsAnything: !names.isEmpty)

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

    /// Bring the library's folders and the folders on disk in step, and
    /// return the library's. A folder made on either side is made on the
    /// other, and one deleted on either side is deleted on the other — on
    /// disk only once nothing is left in it.
    private func syncFolders(_ folders: [String], in folder: URL, listsAnything: Bool) -> [String]? {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return nil }
        let onDisk = subfolders(in: folder, names: names)
        var library = folders
        var known = knownFolders

        // Made outside the app, or there before the folder was chosen.
        for name in onDisk where !known.containsFolder(name) {
            if !library.containsFolder(name) { library.append(name) }
            known.append(name)
        }
        for name in known where !onDisk.containsFolder(name) {
            // Gone from disk. As with files, a folder that lists nothing at
            // all is more likely one that hasn't loaded than one emptied.
            guard listsAnything else { continue }
            library.removeFolder(name)
            known.removeFolder(name)
        }
        for name in known where !library.containsFolder(name) {
            // Deleted in the app.
            if removeIfEmpty(name, in: folder) { known.removeFolder(name) }
        }
        for name in library where !known.containsFolder(name) {
            // Made in the app while the folder couldn't be reached.
            let url = folder.appendingPathComponent(name, isDirectory: true)
            if (try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)) != nil {
                known.append(name)
            }
        }

        knownFolders = known
        return library
    }

    /// The folders at the top of the folder that hold library folders' notes:
    /// not hidden, and not a TextBundle or other package.
    private func subfolders(in folder: URL, names: [String]) -> [String] {
        names.filter { name in
            guard !name.hasPrefix("."), !["textbundle", "textpack"].contains(fileExtension(name)) else { return false }
            let values = try? folder.appendingPathComponent(name)
                .resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return values?.isDirectory == true && values?.isPackage != true
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Delete a library folder from disk if nothing but Finder's leftovers
    /// is in it. True once it's gone.
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
        let subfolder = note.folder
        if let subfolder {
            try? fileManager.createDirectory(at: folder.appendingPathComponent(subfolder, isDirectory: true),
                                             withIntermediateDirectories: true)
        }
        let titleBase = ScriptFile.suggestedFileName(title: note.title, content: note.content)
        var file = existing?.file
        if let current = file {
            let isMoved = !sameFolder(folderName(ofFile: current), subfolder)
            let isRenamed = existing?.title != note.title
            if isMoved || isRenamed {
                // Renamed or moved in the app, so the file follows, keeping its
                // extension, and its name if it only moved.
                let currentName = fileName(of: current)
                var taken = takenNames(in: folder, subfolder: subfolder, index: index)
                if !isMoved { taken.remove(currentName.lowercased()) }
                let base = isRenamed ? titleBase : (currentName as NSString).deletingPathExtension
                let target = path(uniqueName(base: base, extension: fileExtension(current), taken: taken),
                                  in: subfolder)
                if target != current,
                   (try? fileManager.moveItem(at: folder.appendingPathComponent(current),
                                              to: folder.appendingPathComponent(target))) != nil {
                    file = target
                }
            }
        }
        let name = file ?? path(uniqueName(base: titleBase, extension: "txt",
                                           taken: takenNames(in: folder, subfolder: subfolder, index: index)),
                                in: subfolder)
        let url = folder.appendingPathComponent(name)
        writeImages(placedIn: note.content, in: folder)
        guard (try? Data(note.content.utf8).write(to: url, options: .atomic)) != nil else { return }
        index[note.id] = Entry(file: name, title: note.title, mode: note.mode, createdAt: note.createdAt,
                               noteUpdatedAt: note.updatedAt, fileModifiedAt: modificationDate(of: url))
    }

    /// The names in use in a library folder, or at the top, lowercased.
    private func takenNames(in folder: URL, subfolder: String?, index: [UUID: Entry]) -> Set<String> {
        let directory = subfolder.map { folder.appendingPathComponent($0, isDirectory: true) } ?? folder
        let onDisk = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let indexed = index.values.filter { sameFolder(folderName(ofFile: $0.file), subfolder) }
            .map { fileName(of: $0.file) }
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

    /// The library folder a file's path is in, or nil for the top.
    private func folderName(ofFile path: String) -> String? {
        let parts = path.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[0]) : nil
    }

    /// The file's own name, without its library folder.
    private func fileName(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private func path(_ name: String, in subfolder: String?) -> String {
        subfolder.map { "\($0)/\(name)" } ?? name
    }

    /// Folder names are matched as the disk matches them, whatever their case.
    private func sameFolder(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.caseInsensitiveCompare(b) == .orderedSame
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
