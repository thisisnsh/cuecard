import Foundation

/// One saved state of a note. Written once and never changed: every save of a
/// note adds a new version, and restoring an old one adds a copy of it on top.
struct NoteVersion: Codable, Identifiable, Equatable {
    /// 1 for the first save, counting up from there.
    let number: Int
    let content: String
    let createdAt: Date
    /// The version this one brought back, if it came from a restore.
    let restoredFrom: Int?

    var id: Int { number }
}

/// Every version of every saved note, one file each, kept in the app's own
/// storage on this device. The notes folder only ever gets the newest.
@MainActor
final class NoteVersions {
    private let fileManager = FileManager.default
    private let root: URL?

    init() {
        root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NoteVersions", isDirectory: true)
    }

    /// A note's versions, oldest first.
    func versions(of id: UUID) -> [NoteVersion] {
        numbers(of: id).compactMap { read(number: $0, of: id) }
    }

    /// How many versions each note has, for notes that have any.
    func counts() -> [UUID: Int] {
        guard let root, let folders = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [:] }
        var counts: [UUID: Int] = [:]
        for folder in folders {
            guard let id = UUID(uuidString: folder) else { continue }
            let count = numbers(of: id).count
            if count > 0 { counts[id] = count }
        }
        return counts
    }

    /// Keep `note`'s text as its newest version, unless it already is.
    /// `previous` is the note as it was saved before, so a note saved before
    /// versions existed starts its history with what it held then.
    /// Returns how many versions the note has now.
    @discardableResult
    func record(_ note: SavedNote, previous: SavedNote? = nil, restoredFrom: Int? = nil) -> Int {
        var numbers = numbers(of: note.id)
        if numbers.isEmpty, let previous, previous.content != note.content {
            if write(NoteVersion(number: 1, content: previous.content, createdAt: previous.updatedAt,
                                 restoredFrom: nil), of: note.id) {
                numbers = [1]
            }
        }
        if let last = numbers.last, read(number: last, of: note.id)?.content == note.content {
            return numbers.count
        }
        let version = NoteVersion(number: (numbers.last ?? 0) + 1, content: note.content,
                                  createdAt: note.updatedAt, restoredFrom: restoredFrom)
        return write(version, of: note.id) ? numbers.count + 1 : numbers.count
    }

    func remove(id: UUID) {
        guard let folder = folder(of: id) else { return }
        try? fileManager.removeItem(at: folder)
    }

    func removeAll() {
        guard let root else { return }
        try? fileManager.removeItem(at: root)
    }

    /// Bytes taken by every version file.
    func totalSize() -> Int64 {
        guard let root,
              let files = fileManager.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: - Files

    private func folder(of id: UUID) -> URL? {
        root?.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func file(number: Int, of id: UUID) -> URL? {
        folder(of: id)?.appendingPathComponent("\(number).json")
    }

    /// The version numbers a note has on disk, in order.
    private func numbers(of id: UUID) -> [Int] {
        guard let folder = folder(of: id),
              let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.compactMap { name in
            name.hasSuffix(".json") ? Int(name.dropLast(".json".count)) : nil
        }.sorted()
    }

    private func read(number: Int, of id: UUID) -> NoteVersion? {
        guard let url = file(number: number, of: id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NoteVersion.self, from: data)
    }

    /// Write a new version's file. An existing file is never written over.
    private func write(_ version: NoteVersion, of id: UUID) -> Bool {
        guard let folder = folder(of: id), let url = file(number: version.number, of: id),
              let data = try? JSONEncoder().encode(version) else { return false }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .withoutOverwriting)
            return true
        } catch {
            return false
        }
    }
}
