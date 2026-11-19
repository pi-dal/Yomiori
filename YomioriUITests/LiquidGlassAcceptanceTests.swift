import XCTest

/// Reader position, source navigation and library recovery through the app.
@MainActor final class LiquidGlassAcceptanceTests: XCTestCase {
    func testTranslationRevealAndResetOnNextLine() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--preview-translation", "veiled",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet morning in Kyoto"].waitForExistence(timeout: 10))
        app.staticTexts["A quiet morning in Kyoto"].tap()
        let translation = app.buttons["reader-translation"]
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        XCTAssertEqual(translation.label, "Translation hidden")
        translation.tap()
        XCTAssertEqual(translation.label, "I read a book in a small café.")
        app.buttons["Next line"].tap()
        XCTAssertTrue(app.staticTexts["Line 3 of 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        XCTAssertEqual(translation.label, "Translation hidden")
        translation.tap()
        XCTAssertEqual(translation.label, "What shall I read today?")
        translation.tap()
        XCTAssertEqual(translation.label, "Translation hidden")
    }

    func testDocumentTitlesSortAlphabetically() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--library-stress-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Documents"].tap()
        app.buttons["Document options"].tap()
        app.buttons["Title"].tap()
        let alphabeticFirst = app.staticTexts["Everyday Japanese: a collection of conversations, observations and useful expressions"]
        XCTAssertTrue(alphabeticFirst.waitForExistence(timeout: 5))
        let second = app.staticTexts["Language in context"].frame
        XCTAssertTrue(alphabeticFirst.frame.minY < second.minY ||
                      (abs(alphabeticFirst.frame.minY - second.minY) < 2 && alphabeticFirst.frame.minX < second.minX))
    }

    func testReadingAndPDFPositionsResume() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet morning in Kyoto"].waitForExistence(timeout: 10))
        app.staticTexts["A quiet morning in Kyoto"].tap()
        XCTAssertTrue(app.staticTexts["Line 2 of 3"].waitForExistence(timeout: 5))
        app.buttons["Next line"].tap()
        XCTAssertTrue(app.staticTexts["Line 3 of 3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next line"].isEnabled)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["reading-featured"].tap()
        XCTAssertTrue(app.staticTexts["Line 3 of 3"].waitForExistence(timeout: 5))
        app.buttons["Previous line"].tap()
        XCTAssertTrue(app.staticTexts["Line 2 of 3"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Documents"].tap()
        app.staticTexts["Language in context"].tap()
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 2"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Document options"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Continue reading")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next page"].isEnabled)
    }

    func testReturningToAnotherPositionInSameSource() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet morning in Kyoto"].waitForExistence(timeout: 10))
        for (term, position) in [("静か", "Line 1 of 3"), ("喫茶店", "Line 2 of 3")] {
            app.tabBars.buttons["Dictionary"].tap()
            app.staticTexts[term].tap()
            let source = app.buttons["Source"]
            if !source.isHittable { app.swipeUp() }
            source.tap()
            let jump = app.buttons["Go to source"]
            if !jump.isHittable { app.swipeUp() }
            jump.tap()
            XCTAssertTrue(app.staticTexts[position].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    func testPDFClampsOldPositionAndRemovesDeletedResume() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--library-invalid-position-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Documents"].tap()
        app.staticTexts["Language in context"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next page"].isEnabled)
        app.navigationBars.buttons.firstMatch.tap()
        let title = app.staticTexts["Language in context"]
        title.press(forDuration: 1)
        app.buttons["Delete"].tap()
        let confirmation = app.sheets.buttons["Delete"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.staticTexts["Keep the whole page."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Document options"].exists)
    }

    func testDeletingFilteredAndLastReadingMaterial() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet morning in Kyoto"].waitForExistence(timeout: 10))
        let search = app.searchFields["Search reading titles"]
        if !search.isHittable { app.swipeDown() }
        search.tap(); search.typeText("bookshop")
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "At the little bookshop")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No matching titles"].waitForExistence(timeout: 5))
        app.buttons["Clear search"].tap()
        app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["A quiet morning in Kyoto"].exists)
        XCTAssertFalse(app.staticTexts["At the little bookshop"].exists)
        app.buttons["reading-featured"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Everyday conversations"].waitForExistence(timeout: 5))
        app.buttons["reading-featured"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Your next read starts here."].waitForExistence(timeout: 5))
    }

    func testChineseAccessibleSearchRecovery() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons.element(boundBy: 1).tap()
        let search = app.searchFields["搜索文档标题"]
        if !search.isHittable { app.swipeDown() }
        search.tap(); search.typeText("missing-title")
        XCTAssertTrue(app.staticTexts["没有匹配的标题"].waitForExistence(timeout: 5))
        let clear = app.buttons["清除搜索"]
        if !clear.isHittable { app.swipeUp() }
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        XCTAssertTrue(app.staticTexts["Language in context"].waitForExistence(timeout: 5))
    }
}
