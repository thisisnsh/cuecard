import SwiftUI
import UniformTypeIdentifiers

/// Plain-text document used by the file exporter to write a script to disk.
struct ScriptDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let decoded = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = decoded
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Helpers for moving scripts between the editor and files on disk.
enum ScriptFile {
    /// Types the importer accepts. `.plainText` also covers Markdown and other
    /// plain-text formats, so .txt and .md files both come through here.
    static let importableContentTypes: [UTType] = [.plainText, .rtf]

    /// Read a picked file as text. Files coming from the document picker live
    /// outside the sandbox, so access has to be scoped for the duration of the read.
    static func readText(from url: URL) throws -> String {
        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
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

    /// File name suggested when exporting, preferring the saved note's title and
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
