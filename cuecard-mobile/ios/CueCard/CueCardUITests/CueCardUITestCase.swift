import XCTest

/// Launches the app in a known state without touching its source.
///
/// Every value passed as `-key value` on launch lands in UserDefaults' argument
/// domain, which wins over what's saved for as long as the app runs. The app
/// reads its welcome flag, settings and scripts from UserDefaults at launch, so
/// each test starts from the same place whatever earlier runs left behind.
class CueCardUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// A short teleprompter script, enough to play.
    static let teleprompterScript = "Hello everyone.\n\n[cue smile]\n\nThanks for coming."

    /// Three cards.
    static let cardsScript = "First card\n[separator]\nSecond card [cue pause]\n[separator]\nThird card"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Start the app on the welcome screen or the editor, in `mode`, with
    /// `script` in that mode's editor and no saved note open.
    @discardableResult
    func launch(
        hasSeenWelcome: Bool = true,
        mode: String = "teleprompter",
        script: String = CueCardUITestCase.teleprompterScript
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let teleprompterScript = mode == "teleprompter" ? script : ""
        let cardsScript = mode == "cards" ? script : ""

        app.launchArguments += [
            "-cuecard_has_seen_welcome", hasSeenWelcome ? "YES" : "NO",
            "-cuecard_settings", Self.settingsArgument(mode: mode),
            "-cuecard_notes", Self.plistString(teleprompterScript),
            "-cuecard_cards_notes", Self.plistString(cardsScript),
            "-cuecard_current_note_id", Self.plistString(""),
            "-cuecard_cards_note_id", Self.plistString(""),
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        self.app = app

        if hasSeenWelcome {
            dismissWhatsNewIfShown()
        }
        return app
    }

    /// Default settings, apart from the mode, no start delay, and cards kept
    /// off the Lock Screen so a test never leaves a Live Activity behind.
    private static func settingsArgument(mode: String) -> String {
        let json = """
        {"scrollSpeed": 1, "timerMinutes": 1, "timerSeconds": 0, "themePreference": "System",
         "countdownSeconds": 0, "scriptMode": "\(mode)",
         "cards": {"editorFontSize": 16, "fontSize": 28, "cueColor": "pink",
                   "timerMinutes": 1, "timerSeconds": 0, "showOnLockScreen": false}}
        """
        // Old-style property list data: `<hex>`.
        return "<" + Data(json.utf8).map { String(format: "%02x", $0) }.joined() + ">"
    }

    /// A string as an old-style property list, so spaces, brackets and line
    /// breaks come through as written.
    private static func plistString(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// This version's new features float over the editor once, on the first
    /// launch after an update.
    private func dismissWhatsNewIfShown() {
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 3) {
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 3))
        }
    }

    // MARK: - Helpers

    /// The editor's toolbar has loaded.
    func waitForEditor(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10), "Editor didn't appear", file: file, line: line)
    }

    func button(labelBeginningWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func tapDone(file: StaticString = #filePath, line: UInt = #line) {
        let done = app.navigationBars.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "No Done button", file: file, line: line)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Sheet didn't close", file: file, line: line)
    }

    /// Open the ••• menu in the editor and choose `item`.
    func chooseFromMoreMenu(_ item: String, file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["More"].tap()
        let menuItem = app.buttons[item]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "No \(item) in the menu", file: file, line: line)
        menuItem.tap()
    }
}

extension XCUIElement {
    func waitUntilEnabled(timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
