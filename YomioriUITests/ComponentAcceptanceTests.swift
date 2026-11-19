import XCTest

@MainActor final class ComponentAcceptanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--component-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Component preview"].waitForExistence(timeout: 10))
    }

    func testReaderLookupAndNativeSelection() {
        app.buttons["Reader"].tap()
        let reader = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "今日は日本語を勉強します。")).firstMatch
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        app.switches["Furigana"].tap()
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        reader.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.1)).tap()
        XCTAssertTrue(app.staticTexts["preview.lookup"].waitForExistence(timeout: 5))
        reader.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.1)).press(forDuration: 1.2)
        let lookup = app.descendants(matching: .any).matching(identifier: "Look up meaning").firstMatch
        XCTAssertTrue(lookup.waitForExistence(timeout: 5), app.debugDescription)
        lookup.tap()
        XCTAssertFalse(app.staticTexts["preview.lookup"].label.isEmpty)
    }

    func testSettingsLicenseEntry() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let credits = app.buttons["Credits"]
        for _ in 0..<3 where !credits.isHittable { app.swipeUp() }
        XCTAssertTrue(credits.waitForExistence(timeout: 5))
        credits.tap()
        let licenses = app.buttons["Open source licenses"]
        XCTAssertTrue(licenses.waitForExistence(timeout: 5)); licenses.tap()
        XCTAssertTrue(app.navigationBars["Open source licenses"].waitForExistence(timeout: 5))
        let notices = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Yomiori — Open Source Licenses")).firstMatch
        XCTAssertTrue(notices.waitForExistence(timeout: 5))
        XCTAssertTrue(notices.label.contains("ZIPFoundation"))
        XCTAssertTrue(notices.label.contains("Litext"))
    }

    func testSystemShareCancelThenSaveToFiles() {
        app.navigationBars.buttons["Export"].tap()
        XCTAssertTrue(app.navigationBars["Anki"].waitForExistence(timeout: 5))
        let primary = app.buttons["export.primary"]
        primary.tap()
        let share = primary
        let ready = NSPredicate(format: "label == 'Share' AND enabled == true")
        expectation(for: ready, evaluatedWith: share)
        waitForExpectations(timeout: 10)
        share.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        close.tap()
        app.navigationBars.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["preview.exportedCount"].label, "Preview exported: 0")

        app.navigationBars.buttons["Export"].tap()
        primary.tap()
        expectation(for: ready, evaluatedWith: share)
        waitForExpectations(timeout: 10)
        share.tap()
        let saveToFiles = app.cells.matching(NSPredicate(format: "label == %@", "Save to Files")).firstMatch
        if !saveToFiles.isHittable { app.swipeUp() }
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 10), app.debugDescription)
        saveToFiles.tap()
        let save = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
        filename.tap()
        filename.press(forDuration: 1)
        if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
        let existing = filename.value as? String ?? "Yomiori-Anki"
        filename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        filename.typeText("Yomiori-Acceptance-\(UUID().uuidString.prefix(8))")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        save.tap()
        let replace = app.alerts.buttons["Replace"]
        if replace.waitForExistence(timeout: 2) { replace.tap() }
        let delivered = app.staticTexts["1 card exported"]
        XCTAssertTrue(delivered.waitForExistence(timeout: 15), app.debugDescription)
        app.navigationBars["Anki"].buttons["Done"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Preview exported: 1"), evaluatedWith: app.staticTexts["preview.exportedCount"])
        waitForExpectations(timeout: 5)
    }
}
