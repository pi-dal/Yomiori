import XCTest

/// Exercises the system navigation and safe areas used by the redesigned app shell.
@MainActor final class LiquidGlassAcceptanceTests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
        capture(app, "reader-translation-revealed")
        app.buttons["Next line"].tap()
        XCTAssertTrue(app.staticTexts["Line 3 of 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(translation.waitForExistence(timeout: 5))
        XCTAssertEqual(translation.label, "Translation hidden")
        translation.tap()
        XCTAssertEqual(translation.label, "What shall I read today?")
        translation.tap()
        XCTAssertEqual(translation.label, "Translation hidden")
        capture(app, "reader-translation-hidden-on-last-line")
    }

    func testPopulatedLibraryDesign() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet morning in Kyoto"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["小さな喫茶店で、本を読みます。"].exists)
        capture(app, "library-read-populated")
        app.staticTexts["A quiet morning in Kyoto"].tap()
        XCTAssertTrue(app.navigationBars["A quiet morning in Kyoto"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.staticTexts["Language in context"].waitForExistence(timeout: 5))
        capture(app, "library-documents-populated")
        app.staticTexts["Language in context"].tap()
        XCTAssertTrue(app.navigationBars["Language in context"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Dictionary"].tap()
        XCTAssertTrue(app.staticTexts["木漏れ日"].waitForExistence(timeout: 5))
        capture(app, "library-dictionary-populated")
    }

    func testMainDestinationsAndImport() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Read"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Read"].isSelected)
        capture(app, "phone-read-light")

        app.buttons["Import"].tap()
        XCTAssertTrue(app.navigationBars["Import"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Video or audio"].exists)
        capture(app, "phone-import-light")
        app.buttons["Cancel"].tap()

        for title in ["Documents", "Dictionary", "Coach"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.tabBars.buttons[title].isSelected)
            capture(app, "phone-\(title.lowercased())-light")
        }
        let send = app.buttons["Send"]
        XCTAssertFalse(send.isEnabled)
        app.buttons["Talk about my day"].tap()
        let message = app.textFields["Message Coach"]
        XCTAssertEqual(message.value as? String, "Help me talk about my day.")
        message.typeText(" Hello")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled)
        capture(app, "phone-coach-keyboard")
        app.terminate()
    }

    func testDarkDestinationsAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Read"].waitForExistence(timeout: 10))
        capture(app, "phone-read-dark")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture(app, "phone-settings-dark")
        app.buttons["Done"].tap()
        for title in ["Documents", "Dictionary", "Coach"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            capture(app, "phone-\(title.lowercased())-dark")
        }
    }

    func testLibrarySearchSortAndResume() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--library-stress-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet morning in Kyoto"].waitForExistence(timeout: 10))
        let readingSearch = app.searchFields["Search reading titles"]
        if !readingSearch.isHittable { app.swipeDown() }
        readingSearch.tap()
        readingSearch.typeText("bookshop")
        XCTAssertTrue(app.staticTexts["At the little bookshop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["A quiet morning in Kyoto"].exists)
        capture(app, "reading-search-results")
        app.staticTexts["At the little bookshop"].tap()
        XCTAssertTrue(app.navigationBars["At the little bookshop"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch.tap()
        XCTAssertTrue(app.buttons["Sort reading material"].waitForExistence(timeout: 5))
        app.buttons["Sort reading material"].tap()
        app.buttons["Title"].tap()
        capture(app, "reading-sorted-titles")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "At the little bookshop", "Start reading")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["At the little bookshop"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Documents"].tap()
        let documentSearch = app.searchFields["Search document titles"]
        if !documentSearch.isHittable { app.swipeDown() }
        documentSearch.tap()
        documentSearch.typeText("not-a-real-title")
        XCTAssertTrue(app.staticTexts["No matching titles"].waitForExistence(timeout: 5))
        capture(app, "document-search-empty")
        app.buttons["Clear search"].tap()
        documentSearch.tap()
        documentSearch.typeText("travel")
        XCTAssertTrue(app.staticTexts["Travel journal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Language in context"].exists)
        capture(app, "document-search-results")
        app.staticTexts["Travel journal"].tap()
        XCTAssertTrue(app.navigationBars["Travel journal"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch.tap()
        app.buttons["Document options"].tap()
        app.buttons["Title"].tap()
        let alphabeticFirst = app.staticTexts["Everyday Japanese: a collection of conversations, observations and useful expressions"]
        XCTAssertTrue(alphabeticFirst.waitForExistence(timeout: 5))
        let second = app.staticTexts["Language in context"].frame
        XCTAssertTrue(alphabeticFirst.frame.minY < second.minY ||
                      (abs(alphabeticFirst.frame.minY - second.minY) < 2 && alphabeticFirst.frame.minX < second.minX))
        capture(app, "documents-sorted-titles")
        app.buttons["Document options"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Continue reading")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Travel journal"].waitForExistence(timeout: 5))
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
        capture(app, "text-reader-last-line")
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
        capture(app, "pdf-resumed-page-two")
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
        capture(app, "reading-after-source-jumps")
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
        capture(app, "documents-after-last-delete")
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
        capture(app, "reading-library-after-last-delete")
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
        capture(app, "chinese-accessible-search-recovery")
        clear.tap()
        XCTAssertTrue(app.staticTexts["Language in context"].waitForExistence(timeout: 5))
    }

    func testLargeLibrarySearch() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--library-scale-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet morning in Kyoto"].waitForExistence(timeout: 10))
        let readingSearch = app.searchFields["Search reading titles"]
        if !readingSearch.isHittable { app.swipeDown() }
        readingSearch.tap()
        readingSearch.typeText("Reading 240")
        XCTAssertTrue(app.staticTexts["Reading 240"].waitForExistence(timeout: 5))
        capture(app, "large-library-reading-search")
        app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch.tap()
        app.tabBars.buttons["Documents"].tap()
        let search = app.searchFields["Search document titles"]
        if !search.isHittable { app.swipeDown() }
        search.tap()
        search.typeText("Document 240")
        XCTAssertTrue(app.staticTexts["Document 240"].waitForExistence(timeout: 5))
        capture(app, "large-library-document-search")
        app.staticTexts["Document 240"].tap()
        XCTAssertTrue(app.navigationBars["Document 240"].waitForExistence(timeout: 5))
    }

    func testDocumentGridEdgeCases() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--library-stress-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.staticTexts["Listening notes"].waitForExistence(timeout: 5))
        capture(app, "library-documents-grid")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Preview unavailable"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "library-documents-grid-scrolled")
        app.terminate()

        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.staticTexts["Language in context"].waitForExistence(timeout: 5))
        capture(app, "library-documents-grid-accessibility")
    }

    func testChinesePopulatedLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.staticTexts["A quiet morning in Kyoto"].waitForExistence(timeout: 10))
        capture(app, "library-read-chinese")
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["Language in context"].waitForExistence(timeout: 5))
        capture(app, "library-documents-chinese")
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["木漏れ日"].waitForExistence(timeout: 5))
        capture(app, "library-dictionary-chinese")
        app.tabBars.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(app.buttons["聊聊今天"].waitForExistence(timeout: 5))
        capture(app, "phone-coach-chinese")
    }

    func testChineseAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        capture(app, "phone-read-chinese-accessibility")
        let tabs = app.tabBars.buttons
        XCTAssertEqual(tabs.count, 4)
        tabs.element(boundBy: 1).tap()
        capture(app, "phone-documents-chinese-accessibility")
        tabs.element(boundBy: 2).tap()
        capture(app, "phone-dictionary-chinese-accessibility")
        tabs.element(boundBy: 3).tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        capture(app, "phone-coach-chinese-accessibility")
        app.swipeUp()
        XCTAssertTrue(app.buttons["用收藏的词来练习"].waitForExistence(timeout: 5))
        app.buttons["用收藏的词来练习"].tap()
        XCTAssertTrue(app.buttons["发送"].isEnabled)
        capture(app, "phone-coach-chinese-accessibility-input")
    }
}
