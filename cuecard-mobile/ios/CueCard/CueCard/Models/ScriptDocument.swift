import SwiftUI
import UniformTypeIdentifiers

/// Helpers for moving scripts between the editor and files on disk.
enum ScriptFile {
    /// Types the importer accepts. `.plainText` also covers Markdown and other
    /// plain-text formats, so .txt and .md files both come through here.
    static let importableContentTypes: [UTType] = [.plainText, .rtf]

    /// The largest file read as a script, in bytes. Far more than any script
    /// runs to, and little enough to read into memory without trouble.
    static let maxFileSize = 10 * 1024 * 1024

    /// A file over `maxFileSize`, which is left unread.
    struct FileTooLarge: Error {
        let size: Int
    }

    /// Whether a file is over `maxFileSize`. False if its size can't be told.
    static func isTooLarge(_ url: URL) -> Bool {
        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return (fileSize(of: url) ?? 0) > maxFileSize
    }

    private static func fileSize(of url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    /// Read a picked file as text. Files coming from the document picker live
    /// outside the sandbox, so access has to be scoped for the duration of the read.
    /// Throws `FileTooLarge` rather than read a file over `maxFileSize`.
    static func readText(from url: URL) throws -> String {
        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let size = fileSize(of: url), size > maxFileSize {
            throw FileTooLarge(size: size)
        }

        if url.pathExtension.lowercased() == "rtf" {
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return attributed.string
        }

        let data = try Data(contentsOf: url)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        var encoding: String.Encoding = .utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }

    /// Title for an imported script, taken from the file name.
    static func title(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Imported Script" : name
    }

    /// File name suggested for a script, preferring the saved note's title and
    /// falling back to the script's first line.
    static func suggestedFileName(title: String?, content: String) -> String {
        let candidates = [
            title,
            content.split(separator: "\n").first.map(String.init)
        ]

        for candidate in candidates {
            let name = sanitized(candidate ?? "")
            if !name.isEmpty {
                return String(name.prefix(60))
            }
        }

        return "Speech"
    }

    private static func sanitized(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return name
            .components(separatedBy: illegal)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
