import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import CueCard

@Suite("Script files")
struct ScriptFileTests {

    /// A folder of its own for each test, removed when the test ends.
    private final class TemporaryFolder {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("CueCardTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }

        func file(_ name: String, data: Data) throws -> URL {
            let file = url.appendingPathComponent(name)
            try data.write(to: file)
            return file
        }
    }

    // MARK: - Names

    @Test func titleComesFromTheFileName() {
        #expect(ScriptFile.title(for: URL(fileURLWithPath: "/tmp/My Talk.txt")) == "My Talk")
        #expect(ScriptFile.title(for: URL(fileURLWithPath: "/tmp/notes.v2.md")) == "notes.v2")
    }

    @Test func suggestedFileNamePrefersTheTitle() {
        #expect(ScriptFile.suggestedFileName(title: "Keynote", content: "First line") == "Keynote")
    }

    @Test func suggestedFileNameFallsBackToTheFirstLine() {
        #expect(ScriptFile.suggestedFileName(title: nil, content: "First line\nSecond") == "First line")
        #expect(ScriptFile.suggestedFileName(title: "   ", content: "First line") == "First line")
    }

    @Test func suggestedFileNameFallsBackToSpeech() {
        #expect(ScriptFile.suggestedFileName(title: nil, content: "") == "Speech")
        #expect(ScriptFile.suggestedFileName(title: "/:?", content: "") == "Speech")
    }

    @Test func suggestedFileNameDropsCharactersFilesCannotHave() {
        let name = ScriptFile.suggestedFileName(title: "Q3: Plan/Review?", content: "")
        #expect(!name.contains { "/\\:?%*|\"<>".contains($0) })
        #expect(name.hasPrefix("Q3"))
        #expect(name.hasSuffix("Review"))
    }

    @Test func suggestedFileNameIsAtMostSixtyCharacters() {
        let name = ScriptFile.suggestedFileName(title: String(repeating: "a", count: 200), content: "")
        #expect(name.count == 60)
    }

    // MARK: - Reading

    @Test func readsUTF8Text() throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("talk.txt", data: Data("Hello 👋 [cue smile]".utf8))
        #expect(try ScriptFile.readText(from: url) == "Hello 👋 [cue smile]")
    }

    @Test func readsMarkdown() throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("talk.md", data: Data("# Title\nBody".utf8))
        #expect(try ScriptFile.readText(from: url) == "# Title\nBody")
    }

    @Test func readsUTF16Text() throws {
        let folder = try TemporaryFolder()
        let data = try #require("Hello there".data(using: .utf16))
        let url = try folder.file("talk.txt", data: data)
        #expect(try ScriptFile.readText(from: url) == "Hello there")
    }

    @Test func readsRTFAsPlainText() throws {
        let folder = try TemporaryFolder()
        let attributed = NSAttributedString(string: "Hello from RTF",
                                            attributes: [.font: UIFont.boldSystemFont(ofSize: 14)])
        let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                       documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let url = try folder.file("talk.rtf", data: data)
        #expect(try ScriptFile.readText(from: url).trimmingCharacters(in: .whitespacesAndNewlines) == "Hello from RTF")
    }

    @Test func refusesFilesOverTheSizeLimit() throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("huge.txt", data: Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(ScriptFile.maxFileSize + 1))
        try handle.close()

        #expect(ScriptFile.isTooLarge(url))
        #expect(throws: ScriptFile.FileTooLarge.self) {
            try ScriptFile.readText(from: url)
        }
    }

    @Test func smallFileIsNotTooLarge() throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("small.txt", data: Data("Short".utf8))
        #expect(!ScriptFile.isTooLarge(url))
        #expect(ScriptFile.maxFileSize == 10 * 1024 * 1024)
    }

    @Test func importsPlainTextAndRTF() {
        #expect(ScriptFile.importableContentTypes.contains(.plainText))
        #expect(ScriptFile.importableContentTypes.contains(.rtf))
    }
}
