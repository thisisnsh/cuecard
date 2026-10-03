import Foundation
import Testing
@testable import CueCard

@Suite("Cue cards")
struct CueCardsTests {

    // MARK: - Splitting a deck

    @Test func splitsADeckIntoTrimmedCards() {
        let script = "  One  \n[separator]\nTwo\n[separator]\n\n  Three\n"
        #expect(CueCards.cards(in: script) == ["One", "Two", "Three"])
    }

    @Test func leavesBlankCardsOutOfTheDeck() {
        #expect(CueCards.cards(in: "One\n[separator]\n   \n[separator]\nTwo") == ["One", "Two"])
    }

    @Test func separatorIsCaseInsensitive() {
        #expect(CueCards.cards(in: "One[SEPARATOR]Two[Separator]Three") == ["One", "Two", "Three"])
    }

    @Test func scriptWithoutSeparatorsIsOneCard() {
        #expect(CueCards.cards(in: "Just one card") == ["Just one card"])
        #expect(CueCards.cards(in: "").isEmpty)
    }

    @Test func handlesWindowsLineEndings() {
        #expect(CueCards.cards(in: "One\r\n[separator]\r\nTwo") == ["One", "Two"])
    }

    @Test func findsSeparatorAndCardRanges() {
        let text = "A[separator]B"
        #expect(CueCards.separatorRanges(in: text) == [NSRange(location: 1, length: 11)])
        #expect(CueCards.cardRanges(in: text) == [NSRange(location: 0, length: 1), NSRange(location: 12, length: 1)])
    }

    // MARK: - The editor's view of a deck

    @Test func editableCardsKeepBlankOnes() {
        #expect(CueCards.editableCards(in: "One\n[separator]\n\n[separator]\nTwo") == ["One", "", "Two"])
    }

    @Test func writesADeckWithASeparatorBetweenCards() {
        #expect(CueCards.script(for: ["One", "Two"]) == "One\n[separator]\nTwo")
    }

    @Test func singleBlankCardIsNoScript() {
        #expect(CueCards.script(for: [""]) == "")
        #expect(CueCards.script(for: ["  \n"]) == "")
    }

    @Test(arguments: [
        ["One"],
        ["One", "Two"],
        ["One", "", "Three"],
        ["Line one\nLine two", "Hi [cue smile]"],
    ])
    func deckSurvivesARoundTripThroughTheEditor(_ cards: [String]) {
        #expect(CueCards.editableCards(in: CueCards.script(for: cards)) == cards)
    }

    // MARK: - Separators

    @Test func teleprompterReadsSeparatorsAsLineBreaks() {
        #expect(CueCards.removingSeparators(from: "A[separator]B[SEPARATOR]C") == "A\nB\nC")
    }

    @Test func normalizesSeparatorsToLowercase() {
        #expect(CueCards.normalizingSeparators(in: "A[Separator]B") == "A[separator]B")
    }

    // MARK: - Measuring a card

    @Test func characterLimitDependsOnTheLockScreen() {
        #expect(CueCards.characterLimit(onLockScreen: true) == 120)
        #expect(CueCards.characterLimit(onLockScreen: false) == 280)
    }

    @Test func cueTextCountsButTagSyntaxDoesNot() {
        let measure = CueCards.measure(card: "Hello [cue smile]", limit: 100)
        #expect(measure.length == "Hello smile".count)
        #expect(measure.overflow == nil)
    }

    @Test func blankSpaceAtEitherEndIsNotCounted() {
        #expect(CueCards.measure(card: "  ab  ", limit: 100).length == 2)
        #expect(CueCards.measure(card: "\n\nab\n", limit: 100).length == 2)
    }

    @Test func marksEverythingPastTheLimit() {
        let measure = CueCards.measure(card: "abcdef", limit: 4)
        #expect(measure.length == 6)
        #expect(measure.overflow == NSRange(location: 4, length: 2))
    }

    @Test func cardExactlyAtTheLimitDoesNotOverflow() {
        #expect(CueCards.measure(card: "abcd", limit: 4).overflow == nil)
    }

    @Test func emojiCountAsOneCharacterEach() {
        let measure = CueCards.measure(card: "👋🏽🎉", limit: 2)
        #expect(measure.length == 2)
        #expect(measure.overflow == nil)
    }

    // MARK: - Runs

    @Test func splitsACardIntoTextAndCueRuns() {
        let runs = CueCards.runs(for: "Hello [cue smile] world")
        #expect(runs == [
            CueCardRun(text: "Hello ", isCue: false),
            CueCardRun(text: "smile", isCue: true),
            CueCardRun(text: " world", isCue: false),
        ])
    }

    @Test func keepsLineBreaksInRuns() {
        #expect(CueCards.runs(for: "A\nB") == [CueCardRun(text: "A\nB", isCue: false)])
    }

    @Test func leavesEmptyCuesOutOfRuns() {
        #expect(CueCards.runs(for: "Hi [cue]") == [CueCardRun(text: "Hi", isCue: false)])
    }

    @Test func cutsRunsAtTheMaximumLength() {
        #expect(CueCards.runs(for: "Hello world", maxLength: 5) == [CueCardRun(text: "Hello", isCue: false)])
        let runs = CueCards.runs(for: "Hi [cue smile]", maxLength: 5)
        #expect(runs.map(\.text).joined().count == 5)
    }

    // MARK: - Modes

    @Test func modeRawValuesStayStable() {
        // Persisted with the settings: changing these resets users' choice.
        #expect(ScriptMode.teleprompter.rawValue == "teleprompter")
        #expect(ScriptMode.cards.rawValue == "cards")
        #expect(ScriptMode.allCases.map(\.displayName) == ["Teleprompter", "Cards"])
    }
}
