import XCTest

@MainActor final class LiveCoachAcceptanceTests: XCTestCase {
    func testLocalLookupSaveAndVoiceConfigurationWithoutNetwork() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-targetLang", "en"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Dictionary"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Dictionary"].tap()
        app.buttons["dictionary.lookup"].tap()
        let query = app.textFields["lookup.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap(); query.typeText("abandon")
        app.buttons["lookup.search"].tap()
        let add = app.buttons["lookup.save.abandon"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), app.debugDescription)
        if add.isEnabled { add.tap() }
        XCTAssertFalse(add.isEnabled)
        capture(app, "lookup-saved")
        app.navigationBars.buttons["Done"].tap()
        app.tabBars.buttons["Coach"].tap()
        app.buttons["coach.live"].tap()
        XCTAssertTrue(app.navigationBars["Live Coach"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["live.start"].exists)
        XCTAssertTrue(app.staticTexts["Ready to talk"].exists)
        capture(app, "live-ready")
        app.buttons["Voice service settings"].tap()
        XCTAssertTrue(app.navigationBars["Voice service"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["live.endpoint"].exists || app.textViews["live.endpoint"].exists)
        XCTAssertTrue(app.switches["Allow web search in voice conversations"].exists)
        capture(app, "voice-settings")
    }
    func testWordListActionsAndExport() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Dictionary"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Dictionary"].tap()
        app.buttons["Lists"].tap()
        app.staticTexts["IELTS"].firstMatch.tap()
        let add = app.buttons.matching(NSPredicate(format: "value == %@", "Add to Cards")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        capture(app, "word-list-paper-actions")
        add.tap()
        capture(app, "word-list-saved-actions")
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Read"].tap()
        app.buttons["Settings"].tap()
        let export = app.buttons["Export to Anki"]
        for _ in 0..<4 { if export.isHittable { break }; app.swipeUp() }
        export.tap()
        XCTAssertTrue(app.navigationBars["Anki"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export.primary"].exists)
        capture(app, "export-ink-action")
    }

    func testChineseDarkVoiceEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons.element(boundBy: 3).tap()
        app.buttons["coach.live"].tap()
        XCTAssertTrue(app.navigationBars["实时语音教练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["live.start"].exists)
        XCTAssertTrue(app.staticTexts["准备开始"].exists)
        capture(app, "live-chinese-dark")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
