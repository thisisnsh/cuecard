import SwiftUI
import Compression
import UniformTypeIdentifiers

extension UTType {
    /// A TextBundle: a folder holding a Markdown file and the images it shows.
    static let textBundle = UTType(importedAs: "org.textbundle.package")
    /// A TextBundle zipped into one file, which is easier to send.
    static let textPack = UTType(importedAs: "org.textbundle.compressed")
}

/// Scripts with images, to and from TextBundle (textbundle.org): a folder with
/// the script as Markdown in `text.md` and its images in `assets/`, each shown
/// with `![](assets/name.jpg)`. Bear, Ulysses and other Markdown apps read and
/// write them. A TextPack is the folder zipped into a single file, which is
/// how a script with images is shared.
///
/// Cues, card separators and emphasis stay as the script writes them.
enum TextPack {
    /// The largest TextPack imported, in bytes. A script's images are kept at
    /// a size that leaves this far more than enough.
    static let maxFileSize = 100 * 1024 * 1024

    /// Whether `url` is a TextPack or a TextBundle, rather than a text file.
    static func isPackage(_ url: URL) -> Bool {
        ["textpack", "textbundle"].contains(url.pathExtension.lowercased())
    }

    // MARK: - Writing

    /// A script and its images as a TextPack, in a temporary folder of its
    /// own, named for the script.
    static func write(title: String?, content: String) throws -> URL {
        let name = ScriptFile.suggestedFileName(title: title, content: content)
        let bundle = "\(name).textbundle/"
        let info: [String: Any] = [
            "version": 2,
            "type": "net.daringfireball.markdown",
            "transient": false,
            "creatorIdentifier": Bundle.main.bundleIdentifier ?? "com.thisisnsh.cuecard.ios"
        ]

        // An image that's missing keeps its tag, so it's at least still marked.
        let markdown = NSMutableString(string: TeleprompterParser.normalizingTags(in: content))
        var assets: [String: Data] = [:]
        for match in TeleprompterParser.imageMatches(in: markdown as String).reversed() {
            guard let data = assets[match.name] ?? ScriptImages.data(named: match.name) else { continue }
            assets[match.name] = data
            markdown.replaceCharacters(in: match.range, with: "![](assets/\(match.name))")
        }

        var files: [ZipArchive.File] = [
            .init(path: bundle, data: nil),
            .init(path: bundle + "info.json", data: try JSONSerialization.data(withJSONObject: info, options: .sortedKeys)),
            .init(path: bundle + "text.md", data: Data((markdown as String).utf8))
        ]
        if !assets.isEmpty {
            files.append(.init(path: bundle + "assets/", data: nil))
            for name in assets.keys.sorted() {
                files.append(.init(path: bundle + "assets/" + name, data: assets[name]))
            }
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(name).textpack")
        try ZipArchive.data(for: files).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Reading

    /// Something in the package that couldn't be read as a script.
    struct Unreadable: Error {}

    /// The script in a TextPack or TextBundle picked with the document picker.
    /// Its images are kept in the store and placed with `[image …]` tags; one
    /// that can't be found or read is left as the Markdown wrote it.
    /// Throws `ScriptFile.FileTooLarge` rather than read a TextPack over
    /// `maxFileSize`.
    static func readScript(from url: URL) throws -> String {
        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let contents = try Contents(of: url)
        guard let textPath = contents.textPath, let data = contents.read(textPath) else { throw Unreadable() }
        let markdown = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)

        // Images are found from the folder the text is in.
        let root = textPath.split(separator: "/").dropLast().map { $0 + "/" }.joined()
        let script = NSMutableString(string: markdown)
        let matches = markdownImageRegex.matches(in: markdown, range: NSRange(location: 0, length: script.length))
        for match in matches.reversed() {
            let path = script.substring(with: match.range(at: 1))
            guard let relative = bundlePath(path),
                  let image = contents.read(root + relative),
                  let name = ScriptImages.add(image) else { continue }
            script.replaceCharacters(in: match.range, with: TeleprompterParser.imageTag(name: name))
        }
        return script as String
    }

    /// `![description](path "title")`, the path in group 1. A path with a
    /// space in it is written `<like this>`.
    private static let markdownImageRegex = try! NSRegularExpression(
        pattern: #"!\[[^\]\n]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"\n]*")?\s*\)"#
    )

    /// A path written in the Markdown, as one within the bundle. Nil for a
    /// link elsewhere, or a path that climbs out of the bundle.
    private static func bundlePath(_ path: String) -> String? {
        let path = path.removingPercentEncoding ?? path
        guard !path.contains(":"), !path.hasPrefix("/") else { return nil }
        let components = path.split(separator: "/").filter { $0 != "." }
        guard !components.isEmpty, !components.contains("..") else { return nil }
        return components.joined(separator: "/")
    }

    /// The files in a TextPack or TextBundle, by their paths within it.
    private struct Contents {
        let paths: [String]
        let read: (String) -> Data?

        init(of url: URL) throws {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let root = url.standardizedFileURL.path + "/"
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
                var paths: [String] = []
                while let file = enumerator?.nextObject() as? URL {
                    let path = file.standardizedFileURL.path
                    if path.hasPrefix(root) { paths.append(String(path.dropFirst(root.count))) }
                }
                self.paths = paths
                read = { path in
                    let file = url.appendingPathComponent(path)
                    guard (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 <= maxFileSize }) == true
                    else { return nil }
                    return try? Data(contentsOf: file)
                }
            } else {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxFileSize {
                    throw ScriptFile.FileTooLarge(size: size)
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let entries = Dictionary(try ZipArchive.entries(in: data).map { ($0.path, $0) },
                                         uniquingKeysWith: { first, _ in first })
                paths = Array(entries.keys)
                read = { path in entries[path].flatMap { try? ZipArchive.contents(of: $0, in: data) } }
            }
        }

        /// The script's Markdown: `text.md` or the like, at the top or in the
        /// one folder the bundle was zipped as.
        var textPath: String? {
            paths
                .filter { path in
                    let parts = path.split(separator: "/")
                    guard let file = parts.last, parts.count <= 2, !path.hasPrefix("__MACOSX/") else { return false }
                    let name = file.lowercased()
                    return ["text.md", "text.markdown", "text.txt", "text.text"].contains(name)
                }
                .min { $0.split(separator: "/").count < $1.split(separator: "/").count }
        }
    }
}

/// A script with images, shared as a TextPack, so its images go with it.
struct ScriptPackage: Transferable {
    let title: String?
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .textPack) { package in
            SentTransferredFile(try TextPack.write(title: package.title, content: package.content))
        }
    }
}

// MARK: - ZIP

/// Just enough of ZIP for TextPacks: writing files stored as they are — the
/// images in one are compressed already — and reading the files of an archive
/// stored or deflated, as other apps write them.
enum ZipArchive {
    struct File {
        /// `/` between folders, and at the end of a folder's own entry.
        let path: String
        /// Nil for a folder.
        let data: Data?
    }

    struct Entry {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let headerOffset: Int
    }

    struct Malformed: Error {}

    private static let localHeaderSignature: UInt32 = 0x0403_4b50
    private static let centralHeaderSignature: UInt32 = 0x0201_4b50
    private static let endSignature: UInt32 = 0x0605_4b50
    /// Names are UTF-8.
    private static let utf8Flag: UInt16 = 1 << 11
    /// The most any one file is unpacked to, so an archive can't claim more
    /// than the device has to give.
    private static let maxEntrySize = TextPack.maxFileSize

    // MARK: Writing

    static func data(for files: [File]) -> Data {
        var archive = Data()
        var directory = Data()
        let (time, date) = dosTimestamp(Date())

        for file in files {
            let name = Data(file.path.utf8)
            let contents = file.data ?? Data()
            let crc = crc32(contents)
            let offset = UInt32(archive.count)

            archive.append(le: localHeaderSignature)
            archive.append(le: UInt16(20)) // version needed
            archive.append(le: utf8Flag)
            archive.append(le: UInt16(0)) // stored
            archive.append(le: time)
            archive.append(le: date)
            archive.append(le: crc)
            archive.append(le: UInt32(contents.count))
            archive.append(le: UInt32(contents.count))
            archive.append(le: UInt16(name.count))
            archive.append(le: UInt16(0)) // extra
            archive.append(name)
            archive.append(contents)

            directory.append(le: centralHeaderSignature)
            directory.append(le: UInt16(20)) // version made by
            directory.append(le: UInt16(20)) // version needed
            directory.append(le: utf8Flag)
            directory.append(le: UInt16(0))
            directory.append(le: time)
            directory.append(le: date)
            directory.append(le: crc)
            directory.append(le: UInt32(contents.count))
            directory.append(le: UInt32(contents.count))
            directory.append(le: UInt16(name.count))
            directory.append(le: UInt16(0)) // extra
            directory.append(le: UInt16(0)) // comment
            directory.append(le: UInt16(0)) // disk
            directory.append(le: UInt16(0)) // internal attributes
            directory.append(le: UInt32(file.data == nil ? 0x10 : 0)) // external attributes: folder or not
            directory.append(le: offset)
            directory.append(name)
        }

        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(le: endSignature)
        archive.append(le: UInt16(0)) // this disk
        archive.append(le: UInt16(0)) // directory's disk
        archive.append(le: UInt16(files.count))
        archive.append(le: UInt16(files.count))
        archive.append(le: UInt32(directory.count))
        archive.append(le: directoryOffset)
        archive.append(le: UInt16(0)) // comment
        return archive
    }

    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                                   from: date)
        let time = (parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2
        let day = max((parts.year ?? 1980) - 1980, 0) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1)
        return (UInt16(truncatingIfNeeded: time), UInt16(truncatingIfNeeded: day))
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: Reading

    /// The files in an archive, read from its central directory. Folders and
    /// encrypted files are left out.
    static func entries(in data: Data) throws -> [Entry] {
        // The end record is the last thing in the file, before a comment of
        // up to 64 KB.
        let earliest = max(0, data.count - 22 - 0xFFFF)
        var end = data.count - 22
        while end >= earliest, data.uint32(at: end) != endSignature { end -= 1 }
        guard end >= earliest,
              let count = data.uint16(at: end + 10),
              let directoryOffset = data.uint32(at: end + 16) else { throw Malformed() }

        var entries: [Entry] = []
        var offset = Int(directoryOffset)
        for _ in 0..<count {
            guard data.uint32(at: offset) == centralHeaderSignature,
                  let flags = data.uint16(at: offset + 8),
                  let method = data.uint16(at: offset + 10),
                  let compressedSize = data.uint32(at: offset + 20),
                  let size = data.uint32(at: offset + 24),
                  let nameLength = data.uint16(at: offset + 28),
                  let extraLength = data.uint16(at: offset + 30),
                  let commentLength = data.uint16(at: offset + 32),
                  let headerOffset = data.uint32(at: offset + 42),
                  let name = data.slice(at: offset + 46, count: Int(nameLength)) else { throw Malformed() }
            let path = String(data: name, encoding: .utf8) ?? String(decoding: name, as: UTF8.self)
            if flags & 1 == 0, !path.hasSuffix("/") {
                entries.append(Entry(path: path, method: method, compressedSize: Int(compressedSize),
                                     size: Int(size), headerOffset: Int(headerOffset)))
            }
            offset += 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
        }
        return entries
    }

    /// One file's contents, unpacked.
    static func contents(of entry: Entry, in data: Data) throws -> Data {
        let header = entry.headerOffset
        guard data.uint32(at: header) == localHeaderSignature,
              let nameLength = data.uint16(at: header + 26),
              let extraLength = data.uint16(at: header + 28),
              entry.size <= maxEntrySize,
              let packed = data.slice(at: header + 30 + Int(nameLength) + Int(extraLength),
                                      count: entry.compressedSize) else { throw Malformed() }

        switch entry.method {
        case 0:
            return packed
        case 8:
            guard entry.size > 0 else { return Data() }
            guard !packed.isEmpty else { throw Malformed() }
            var unpacked = Data(count: entry.size)
            let written = unpacked.withUnsafeMutableBytes { destination in
                packed.withUnsafeBytes { source in
                    // COMPRESSION_ZLIB is raw deflate, as ZIP stores it.
                    compression_decode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, entry.size,
                        source.bindMemory(to: UInt8.self).baseAddress!, packed.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == entry.size else { throw Malformed() }
            return unpacked
        default:
            throw Malformed()
        }
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(le value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    func uint16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= count - 2 else { return nil }
        let start = startIndex + offset
        return UInt16(self[start]) | UInt16(self[start + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32? {
        guard let low = uint16(at: offset), let high = uint16(at: offset + 2) else { return nil }
        return UInt32(low) | UInt32(high) << 16
    }

    /// `count` bytes from `offset`, counted from the start, if they're all there.
    func slice(at offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0, offset <= self.count - count else { return nil }
        return subdata(in: (startIndex + offset)..<(startIndex + offset + count))
    }
}
