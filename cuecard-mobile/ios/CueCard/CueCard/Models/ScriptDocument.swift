import SwiftUI
import UniformTypeIdentifiers

/// Helpers for moving scripts between the editor and files on disk.
enum ScriptFile {
    /// Types the importer accepts. `.plainText` also covers Markdown and other
    /// plain-text formats, so .txt and .md files both come through here, and a
    /// script with images comes as a TextPack or TextBundle. Those are also
    /// asked for by extension, in case another app on the device has named
    /// them differently.
    static let importableContentTypes: [UTType] = [.plainText, .rtf, .textPack, .textBundle]
        + ["textpack", "textbundle"].compactMap { UTType(filenameExtension: $0) }

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
    ///
    /// A TextPack or TextBundle is read as the script it holds, its images
    /// kept in the store.
    static func readText(from url: URL) throws -> String {
        if TextPack.isPackage(url) {
            return try TextPack.readScript(from: url)
        }

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
            return markdown(from: attributed)
        }

        let data = try Data(contentsOf: url)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        var encoding: String.Encoding = .utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }

    /// Rich text as the script would be written: bold and italic kept as
    /// `*bold*` and `_italic_`, everything else dropped.
    static func markdown(from attributed: NSAttributedString) -> String {
        var pieces: [(text: String, style: EmphasisStyle)] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            var style = EmphasisStyle()
            if let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits {
                if traits.contains(.traitBold) { style.insert(.bold) }
                if traits.contains(.traitItalic) { style.insert(.italic) }
            }

            let text = attributed.attributedSubstring(from: range).string
            // A change of color or size alone doesn't split a stretch of one style.
            if let last = pieces.last, last.style == style {
                pieces[pieces.count - 1].text += text
            } else {
                pieces.append((text, style))
            }
        }

        return pieces.map { piece in
            guard !piece.style.isEmpty else { return piece.text }
            let open = (piece.style.contains(.bold) ? EmphasisStyle.bold.marker : "")
                + (piece.style.contains(.italic) ? EmphasisStyle.italic.marker : "")
            let close = String(open.reversed())
            // Markers go around the words of each line, not the space around them.
            return piece.text.components(separatedBy: "\n").map { line in
                let words = line.trimmingCharacters(in: .whitespaces)
                guard !words.isEmpty, let start = line.range(of: words) else { return line }
                return line.replacingCharacters(in: start, with: open + words + close)
            }.joined(separator: "\n")
        }.joined()
    }

    /// Title for an imported script, taken from the file name.
    static func title(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? String(localized: "Imported Script") : name
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

        return String(localized: "Speech")
    }

    private static func sanitized(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return name
            .components(separatedBy: illegal)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
