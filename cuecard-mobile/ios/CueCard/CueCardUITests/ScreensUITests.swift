import XCTest

/// Every sheet and full-screen view the editor opens comes up and closes.
final class ScreensUITests: CueCardUITestCase {

    // MARK: - Reading

    func testTeleprompterPlaysAndCloses() {
        launch()
        waitForEditor()

        app.buttons["Start Teleprompter"].tap()

        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "The teleprompter didn't open")
        play.tap()
        XCTAssertTrue(button(labelBeginningWith: "Pause").waitForExistence(timeout: 5), "It didn't start playing")

        closeTeleprompter()
        XCTAssertTrue(app.buttons["Start Teleprompter"].waitForExistence(timeout: 5))
    }

    func testReadingThroughADeckOfCards() {
        launch(mode: "cards", script: Self.cardsScript)
        waitForEditor()

        let open = app.buttons["Open Cards"]
        XCTAssertTrue(open.waitUntilEnabled())
        open.tap()

        XCTAssertTrue(app.navigationBars["Cards"].waitForExistence(timeout: 10), "The deck didn't open")
        XCTAssertTrue(app.staticTexts["First card"].exists)
        XCTAssertFalse(app.buttons["Previous Card"].isEnabled)

        app.buttons["Next Card"].tap()
        XCTAssertTrue(app.buttons["Previous Card"].waitUntilEnabled())

        app.buttons["Next Card"].tap()
        let finish = app.buttons["Finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        XCTAssertTrue(app.staticTexts["All cards done"].waitForExistence(timeout: 5))
        app.buttons["Start Over"].tap()
        XCTAssertTrue(app.buttons["Next Card"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Previous Card"].isEnabled)

        app.navigationBars["Cards"].buttons["Close"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
    }

    func testDeckOfOneCardFinishesStraightAway() {
        launch(mode: "cards", script: "Only card")
        waitForEditor()

        app.buttons["Open Cards"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 10))
        app.navigationBars["Cards"].buttons["Close"].tap()
    }

    // MARK: - Sheets

    func testTimerSheet() {
        launch()
        waitForEditor()

        app.buttons["Timer, 1:00"].tap()
        XCTAssertTrue(app.navigationBars["Teleprompter Timer"].waitForExistence(timeout: 5))
        tapDone()
    }

    func testCardsTimerSheet() {
        launch(mode: "cards", script: Self.cardsScript)
        waitForEditor()

        app.buttons["Timer, 1:00"].tap()
        XCTAssertTrue(app.navigationBars["Cards Timer"].waitForExistence(timeout: 5))
        tapDone()
    }

    func testTeleprompterSettings() {
        launch()
        waitForEditor()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Teleprompter Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scroll Speed"].exists)
        tapDone()
    }

    func testCardsSettings() {
        launch(mode: "cards", script: Self.cardsScript)
        waitForEditor()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Cards Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Show on Lock Screen"].exists)
        tapDone()
    }

    func testHelp() {
        launch()
        waitForEditor()

        app.buttons["Help"].tap()
        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 5))
        tapDone()
    }

    func testSavedNotes() {
        launch()
        waitForEditor()

        chooseFromMoreMenu("Open")
        XCTAssertTrue(app.navigationBars["Saved Notes"].waitForExistence(timeout: 5))
        tapDone()
    }

    func testNewNoteClearsTheEditor() {
        launch()
        waitForEditor()

        chooseFromMoreMenu("New")
        XCTAssertTrue(app.buttons["Add Sample Text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start Teleprompter"].isEnabled)
    }

    // MARK: - Helpers

    /// The close button fades with the other controls while the script plays.
    /// A tap on the script brings them back.
    private func closeTeleprompter() {
        let close = app.navigationBars.buttons["Close"]
        if !close.waitForExistence(timeout: 2) || !close.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(close.waitForExistence(timeout: 5), "No way to close the teleprompter")
        close.tap()
    }
}
