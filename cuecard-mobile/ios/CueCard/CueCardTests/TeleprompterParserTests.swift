import Foundation
import Testing
@testable import CueCard

@Suite("Teleprompter parser")
struct TeleprompterParserTests {

    // MARK: - Finding cues

    @Test func findsCueAndItsText() {
        let text = "Hello [cue smile] world"
        let matches = TeleprompterParser.cueMatches(in: text)

        #expect(matches.count == 1)
        #expect(matches[0].content == "smile")
        #expect((text as NSString).substring(with: matches[0].range) == "[cue smile]")
    }

    @Test func readsTheOlderNoteSpelling() {
        let matches = TeleprompterParser.cueMatches(in: "[note pause]")
        #expect(matches.map(\.content) == ["pause"])
    }

    @Test func readsALegacyColorAndIgnoresIt() {
        let matches = TeleprompterParser.cueMatches(in: "[cue:green slow down]")
        #expect(matches.map(\.content) == ["slow down"])
    }

    @Test func emptyCueSitsJustInsideTheClosingBracket() {
        let text = "[cue]"
        let match = try! #require(TeleprompterParser.cueMatches(in: text).first)

        #expect(match.content == "")
        #expect(match.contentRange == NSRange(location: 4, length: 0))
    }

    @Test(arguments: [
        "[cue smi",          // not closed yet
        "[cue smile\nmore]", // cues don't span lines
        "[cuesmile]",        // no space after the keyword
        "[queue smile]",
        "plain text",
    ])
    func ignoresWhatIsNotACue(_ text: String) {
        #expect(TeleprompterParser.cueMatches(in: text).isEmpty)
    }

    @Test func findsEveryCueInOrder() {
        let matches = TeleprompterParser.cueMatches(in: "[cue one] a [note two] b [cue three]")
        #expect(matches.map(\.content) == ["one", "two", "three"])
    }

    @Test func caretInsideATagFindsIt() {
        let text = "Hi [cue smile] there"
        // "Hi " is 3 characters, so the tag runs 3..<14.
        #expect(TeleprompterParser.cueTag(containing: 8, in: text)?.content == "smile")
    }

    @Test(arguments: [3, 14, 0, 20])
    func caretAgainstOrOutsideABracketIsOutside(_ location: Int) {
        #expect(TeleprompterParser.cueTag(containing: location, in: "Hi [cue smile] there") == nil)
    }

    // MARK: - Tags

    @Test func buildsTrimmedCueTags() {
        #expect(TeleprompterParser.cueTag(text: "  smile  ") == "[cue smile]")
        #expect(TeleprompterParser.emptyCueTag == "[cue ]")
    }

    @Test func normalizesEveryTagToTheCurrentSpelling() {
        let text = "A [note pause] B [cue:red look up] C [SEPARATOR] D"
        #expect(TeleprompterParser.normalizingTags(in: text) == "A [cue pause] B [cue look up] C [separator] D")
    }

    @Test func normalizingCurrentSyntaxChangesNothing() {
        let text = "Hello [cue smile]\n[separator]\nNext"
        #expect(TeleprompterParser.normalizingTags(in: text) == text)
    }

    // MARK: - Segments

    @Test func splitsALineIntoTextAndCues() {
        let segments = TeleprompterParser.segments(in: "Hello [cue smile] world")
        #expect(describe(segments) == ["text:Hello", "cue:smile", "text:world"])
    }

    @Test func lineWithoutCuesIsOneTextSegment() {
        #expect(describe(TeleprompterParser.segments(in: "Just words")) == ["text:Just words"])
    }

    @Test func lineThatIsOnlyACueIsOneCueSegment() {
        #expect(describe(TeleprompterParser.segments(in: "[cue pause]")) == ["cue:pause"])
    }

    // MARK: - Parsing a script

    @Test func parsesWordsAndTagsCueWords() {
        let content = TeleprompterParser.parseNotes("Hello there [cue big smile]\n\nBye")

        #expect(content.words.map(\.text) == ["Hello", "there", "big", "smile", "Bye"])
        #expect(content.words.map(\.isCue) == [false, false, true, true, false])
        #expect(content.cues.map(\.content) == ["big smile"])
    }

    @Test func parsingNormalizesLineEndingsAndTrims() {
        let content = TeleprompterParser.parseNotes("  \r\nOne\r\nTwo\rThree\n  ")
        #expect(content.fullText == "One\nTwo\nThree")
    }

    @Test func parsingReadsCardSeparatorsAsLineBreaks() {
        let content = TeleprompterParser.parseNotes("One[separator]Two")
        #expect(content.fullText == "One\nTwo")
        #expect(content.words.map(\.text) == ["One", "Two"])
    }

    @Test func parsesAnEmptyScript() {
        let content = TeleprompterParser.parseNotes("   ")
        #expect(content.fullText.isEmpty)
        #expect(content.words.isEmpty)
        #expect(content.cues.isEmpty)
    }

    // MARK: - Time and position

    @Test(arguments: [
        (0, "00:00"), (5, "00:05"), (65, "01:05"), (600, "10:00"), (-5, "-00:05"), (-125, "-02:05"),
    ])
    func formatsTime(_ seconds: Int, _ expected: String) {
        #expect(TeleprompterParser.formatTime(seconds) == expected)
    }

    @Test func wordIndexFollowsElapsedTimeAndStopsAtTheLastWord() {
        #expect(TeleprompterParser.calculateCurrentWordIndex(elapsedTime: 0, totalWords: 10, wordsPerMinute: 120) == 0)
        #expect(TeleprompterParser.calculateCurrentWordIndex(elapsedTime: 2, totalWords: 10, wordsPerMinute: 120) == 4)
        #expect(TeleprompterParser.calculateCurrentWordIndex(elapsedTime: 60, totalWords: 10, wordsPerMinute: 120) == 9)
    }

    @Test func lineIndexFollowsElapsedTimeAndStopsAtTheLastLine() {
        #expect(TeleprompterParser.calculateCurrentLineIndex(elapsedTime: 30, totalLines: 100, linesPerMinute: 34) == 17)
        #expect(TeleprompterParser.calculateCurrentLineIndex(elapsedTime: 600, totalLines: 5, linesPerMinute: 34) == 4)
    }

    // MARK: - Sample scripts

    @Test @MainActor func sampleScriptsParse() {
        let teleprompter = TeleprompterParser.parseNotes(SettingsService.defaultNoteText)
        #expect(!teleprompter.words.isEmpty)
        #expect(teleprompter.cues.count == 6)

        let cards = CueCards.cards(in: SettingsService.defaultCardsText)
        #expect(cards.count == 7)
    }

    @Test @MainActor func sampleCardsFitOnTheLockScreen() {
        let limit = CueCards.characterLimit(onLockScreen: true)
        for card in CueCards.cards(in: SettingsService.defaultCardsText) {
            #expect(CueCards.measure(card: card, limit: limit).overflow == nil, "Too long: \(card)")
        }
    }

    private func describe(_ segments: [CueSegment]) -> [String] {
        segments.map {
            switch $0 {
            case .text(let text): return "text:\(text)"
            case .cue(let cue): return "cue:\(cue)"
            }
        }
    }
}
