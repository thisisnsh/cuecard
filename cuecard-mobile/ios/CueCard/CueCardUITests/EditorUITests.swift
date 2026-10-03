import XCTest

/// The welcome screen and the editor: what a user sees first and works in most.
final class EditorUITests: CueCardUITestCase {

    func testWelcomeLeadsToTheEditorWithTheSampleScript() {
        launch(hasSeenWelcome: false, script: "")

        XCTAssertTrue(app.staticTexts["Floating Teleprompter"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No account needed. Scripts stay on this device."].exists)

        app.buttons["Get Started"].tap()

        waitForEditor()
        // An empty script is started off with the sample, so it can be played.
        let play = app.buttons["Start Teleprompter"]
        XCTAssertTrue(play.waitUntilEnabled())
        XCTAssertFalse(app.buttons["Add Sample Text"].exists)
    }

    func testEmptyEditorOffersTheSampleScript() {
        launch(script: "")
        waitForEditor()

        let play = app.buttons["Start Teleprompter"]
        XCTAssertTrue(play.exists)
        XCTAssertFalse(play.isEnabled)

        app.buttons["Add Sample Text"].tap()

        XCTAssertTrue(play.waitUntilEnabled())
        XCTAssertTrue(app.buttons["Timer, 1:00"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Unsaved"].exists)
    }

    func testTypingAndAddingACue() {
        launch(script: "")
        waitForEditor()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Hello there ")

        let addCue = app.buttons["Add Cue"]
        XCTAssertTrue(addCue.waitForExistence(timeout: 5), "The cue bar didn't come up with the keyboard")
        addCue.tap()
        editor.typeText("smile")

        let text = editor.value as? String ?? ""
        XCTAssertTrue(text.contains("Hello there"), "Editor holds: \(text)")
        XCTAssertTrue(text.contains("[cue smile]"), "Editor holds: \(text)")

        app.buttons["Hide keyboard"].tap()
        XCTAssertTrue(app.buttons["Start Teleprompter"].waitUntilEnabled())
        XCTAssertTrue(app.buttons["Unsaved"].exists)
    }

    func testSwitchingBetweenTeleprompterAndCards() {
        launch()
        waitForEditor()

        app.buttons["Mode: Teleprompter"].tap()
        app.buttons["Cards"].firstMatch.tap()

        XCTAssertTrue(app.buttons["Mode: Cards"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Create New Card"].exists)
        XCTAssertTrue(app.buttons["Open Cards"].exists)
        XCTAssertFalse(app.buttons["Start Teleprompter"].exists)

        app.buttons["Mode: Cards"].tap()
        app.buttons["Teleprompter"].firstMatch.tap()

        XCTAssertTrue(app.buttons["Mode: Teleprompter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Teleprompter"].exists)
    }

    func testEachModeKeepsItsOwnScript() {
        launch(script: "")
        waitForEditor()
        app.buttons["Add Sample Text"].tap()
        XCTAssertTrue(app.buttons["Start Teleprompter"].waitUntilEnabled())

        // Cards starts empty: the teleprompter's script stays with the teleprompter.
        app.buttons["Mode: Teleprompter"].tap()
        app.buttons["Cards"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Add Sample Text"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Open Cards"].isEnabled)
    }

    func testSavingANoteAndDeletingIt() {
        let title = "UI Test \(UUID().uuidString.prefix(8))"
        launch(script: "A script saved by the UI tests.")
        waitForEditor()

        let unsaved = app.buttons["Unsaved"]
        XCTAssertTrue(unsaved.waitForExistence(timeout: 5))
        unsaved.tap()

        let alert = app.alerts["Save Note"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let titleField = alert.textFields.firstMatch
        titleField.tap()
        titleField.typeText(title)
        alert.buttons["Save"].tap()

        XCTAssertTrue(unsaved.waitForNonExistence(timeout: 5), "Still unsaved after saving")

        chooseFromMoreMenu("Open")
        XCTAssertTrue(app.navigationBars["Saved Notes"].waitForExistence(timeout: 5))

        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The saved note isn't listed")

        // Clean up after the test.
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "The note wasn't deleted")

        tapDone()
    }
}
