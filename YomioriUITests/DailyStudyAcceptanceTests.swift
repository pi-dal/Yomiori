import XCTest

@MainActor final class DailyStudyAcceptanceTests: XCTestCase {
    private func reach(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 10) {
        for _ in 0..<swipes where !(element.exists && element.isHittable) { app.swipeUp() }
    }
    func testDailyStudyCompletesAndReopeningKeepsBudget() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--daily-study-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let start = app.buttons["study.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        // Synthetic preview cards: three due words, then two new words introduced in context.
        let meanings = ["毎日、少しずつ学びます。": "every day", "京都の朝は静かです。": "quiet",
                        "小さな喫茶店で本を読みます。": "café", "今日は何を読もうか。": "to read",
                        "新しい言葉を覚えます。": "to remember"]
        let dontKnow = app.buttons["review.dontKnow"]
        XCTAssertTrue(dontKnow.waitForExistence(timeout: 10))
        // Missing a word sends it back a few cards later instead of ending on a failure.
        let missedSentence = try XCTUnwrap(meanings.keys.first { app.staticTexts[$0].exists })
        dontKnow.tap()
        XCTAssertTrue(app.staticTexts["It comes back in a few cards."].waitForExistence(timeout: 5))
        app.buttons["review.next"].tap()
        var sawMissedAgain = false, sawIntro = false
        for step in 0..<12 {
            if app.staticTexts["Worth another look"].waitForExistence(timeout: 1) { break }
            let gotIt = app.buttons["review.gotIt"]
            if gotIt.exists {
                sawIntro = true; gotIt.tap(); continue
            }
            XCTAssertTrue(app.buttons["review.option"].firstMatch.waitForExistence(timeout: 5), "step \(step)")
            let sentence = try XCTUnwrap(meanings.keys.first { app.staticTexts[$0].exists })
            if sentence == missedSentence { sawMissedAgain = true }
            app.buttons.matching(NSPredicate(format: "label == %@", meanings[sentence]!)).firstMatch.tap()
            let next = app.buttons["review.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        XCTAssertTrue(sawMissedAgain && sawIntro)
        XCTAssertTrue(app.staticTexts["4 recalled · 2 new · 1 to revisit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You studied 5 cards. Your progress is saved."].exists)
        app.buttons["review.finish"].tap()
        XCTAssertTrue(app.staticTexts["Today’s goal is complete."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["5 cards completed today"].exists)
        // With nothing left to review, the same button opens Today and its next step.
        app.buttons["study.start"].tap()
        XCTAssertTrue(app.navigationBars["Today’s study"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["5 cards completed today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["study.review"].exists)
        XCTAssertTrue(app.buttons["journey.next"].exists)
    }
    func testFreePracticeRoundEndsWithSummaryAndKeepsSchedule() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--daily-study-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["journey.open"].waitForExistence(timeout: 10)); app.buttons["journey.open"].tap()
        let dailyQueue = app.staticTexts["3 reviews · 2 new words"]
        XCTAssertTrue(dailyQueue.waitForExistence(timeout: 5))
        let free = app.buttons["study.freePractice"]
        XCTAssertTrue(free.waitForExistence(timeout: 10)); reach(free, in: app); free.tap()
        let meanings = ["毎日、少しずつ学びます。": "every day", "京都の朝は静かです。": "quiet",
                        "小さな喫茶店で本を読みます。": "café", "今日は何を読もうか。": "to read",
                        "新しい言葉を覚えます。": "to remember"]
        for step in 0..<12 {
            if app.staticTexts["You practiced every available card. Your daily schedule is unchanged."].waitForExistence(timeout: 1) { break }
            if app.buttons["review.gotIt"].exists { app.buttons["review.gotIt"].tap(); continue }
            XCTAssertTrue(app.buttons["review.option"].firstMatch.waitForExistence(timeout: 5), "step \(step)")
            let sentence = try XCTUnwrap(meanings.keys.first { app.staticTexts[$0].exists })
            app.buttons.matching(NSPredicate(format: "label == %@", meanings[sentence]!)).firstMatch.tap()
            app.buttons["review.next"].tap()
        }
        XCTAssertTrue(app.staticTexts["5 recalled · 2 new · 0 to revisit"].exists)
        XCTAssertFalse(app.buttons["review.moreRound"].exists)
        app.buttons["review.finish"].tap()
        XCTAssertTrue(dailyQueue.waitForExistence(timeout: 5))
    }
    func testChineseAccessibleStudySettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--daily-study-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["study.start"].waitForExistence(timeout: 10)); app.buttons["study.start"].tap()
        XCTAssertTrue(app.navigationBars["复习"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["review.dontKnow"].waitForExistence(timeout: 10))
        app.navigationBars["复习"].buttons.firstMatch.tap()
        let path = app.buttons["journey.open"]
        XCTAssertTrue(path.waitForExistence(timeout: 10)); reach(path, in: app); path.tap()
        XCTAssertTrue(app.staticTexts["每天学一点。"].waitForExistence(timeout: 10))
        let settings = app.buttons["study.configure"]
        reach(settings, in: app, swipes: 30)
        settings.tap()
        XCTAssertTrue(app.navigationBars["每日学习与提醒"].waitForExistence(timeout: 5))
        let reminder = app.switches["study.reminderToggle"]
        for _ in 0..<8 {
            if reminder.exists && reminder.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(reminder.isHittable)
    }
}
