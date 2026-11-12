import XCTest

@MainActor final class DailyStudyAcceptanceTests: XCTestCase {
    private func reach(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 10) {
        for _ in 0..<swipes where !(element.exists && element.isHittable) { app.swipeUp() }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDailyStudyCompletesAndReopeningKeepsBudget() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--daily-study-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let start = app.buttons["study.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        capture(app, "daily-study-home-actions")
        start.tap()
        // Synthetic preview cards: three due words, then two new words introduced in context.
        let meanings = ["毎日、少しずつ学びます。": "every day", "京都の朝は静かです。": "quiet",
                        "小さな喫茶店で本を読みます。": "café", "今日は何を読もうか。": "to read",
                        "新しい言葉を覚えます。": "to remember"]
        let dontKnow = app.buttons["review.dontKnow"]
        XCTAssertTrue(dontKnow.waitForExistence(timeout: 10))
        capture(app, "daily-study-starts-with-recall")
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
                if !sawIntro { capture(app, "daily-study-new-word-in-context") }
                sawIntro = true; gotIt.tap(); continue
            }
            XCTAssertTrue(app.buttons["review.option"].firstMatch.waitForExistence(timeout: 5), "step \(step)")
            let sentence = try XCTUnwrap(meanings.keys.first { app.staticTexts[$0].exists })
            if sentence == missedSentence { sawMissedAgain = true }
            app.buttons.matching(NSPredicate(format: "label == %@", meanings[sentence]!)).firstMatch.tap()
            let next = app.buttons["review.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            if step == 0 { capture(app, "daily-study-recall-feedback") }
            next.tap()
        }
        XCTAssertTrue(sawMissedAgain && sawIntro)
        XCTAssertTrue(app.staticTexts["4 recalled · 2 new · 1 to revisit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You studied 5 cards. Your progress is saved."].exists)
        capture(app, "daily-study-session-summary")
        app.buttons["review.finish"].tap()
        XCTAssertTrue(app.staticTexts["Today’s goal is complete."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["5 cards completed today"].exists)
        capture(app, "daily-study-complete")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: landscape, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        capture(app, "daily-study-complete-landscape")
        XCUIDevice.shared.orientation = .portrait
        // With nothing left to review, the same button opens Today and its next step.
        app.buttons["study.start"].tap()
        XCTAssertTrue(app.navigationBars["Today’s study"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["5 cards completed today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["study.review"].exists)
        XCTAssertTrue(app.buttons["journey.next"].exists)
        capture(app, "today-after-review")
    }
    func testFreePracticeRoundEndsWithSummaryAndKeepsSchedule() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--daily-study-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["journey.open"].waitForExistence(timeout: 10)); app.buttons["journey.open"].tap()
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
            // Free practice never offers schedule adjustments.
            XCTAssertFalse(app.buttons["review.next"].staticTexts["Next review in 2 days"].exists)
            app.buttons["review.next"].tap()
        }
        XCTAssertTrue(app.staticTexts["5 recalled · 2 new · 0 to revisit"].exists)
        XCTAssertFalse(app.buttons["review.moreRound"].exists)
        capture(app, "free-practice-round-summary")
        app.buttons["review.finish"].tap()
        XCTAssertTrue(app.buttons["study.review"].waitForExistence(timeout: 5))
    }
    func testReaderMarksCardWordsFromOtherSources() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--daily-study-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let featured = app.buttons["reading-featured"]
        XCTAssertTrue(featured.waitForExistence(timeout: 10)); reach(featured, in: app); featured.tap()
        XCTAssertTrue(app.otherElements["reader-current-line"].waitForExistence(timeout: 10))
        capture(app, "reader-study-marks")
    }
    func testLearningJourneyExposesNextActionAndRoadmap() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--daily-study-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let path = app.buttons["journey.open"]
        XCTAssertTrue(path.waitForExistence(timeout: 10))
        path.tap()
        XCTAssertTrue(app.navigationBars["Today’s study"].waitForExistence(timeout: 10))
        // Cards are waiting, so review is the one primary action; Today no longer opens it by itself.
        XCTAssertTrue(app.buttons["study.review"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["review.dontKnow"].exists)
        XCTAssertTrue(app.staticTexts["1 of 4 anchors complete"].exists)
        capture(app, "today-top")
        let milestones = app.staticTexts["Milestones"]
        reach(milestones, in: app)
        XCTAssertTrue(app.staticTexts["Words that stuck"].exists)
        capture(app, "today-progress-milestones")
        let roadmap = app.staticTexts["The long route"]
        reach(roadmap, in: app)
        XCTAssertTrue(app.staticTexts["1 of 7 active days"].exists || app.staticTexts["0 of 7 active days"].exists)
        capture(app, "today-roadmap")
        app.buttons["Done"].tap()
        // Starting study from Read goes straight into review, without an intermediate screen.
        app.buttons["study.start"].tap()
        XCTAssertTrue(app.buttons["review.dontKnow"].waitForExistence(timeout: 10))
    }
    func testChineseAccessibleStudySettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--daily-study-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["study.start"].waitForExistence(timeout: 10)); app.buttons["study.start"].tap()
        XCTAssertTrue(app.navigationBars["复习"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["review.dontKnow"].waitForExistence(timeout: 10))
        capture(app, "review-recall-chinese-accessible")
        app.navigationBars["复习"].buttons.firstMatch.tap()
        let path = app.buttons["journey.open"]
        XCTAssertTrue(path.waitForExistence(timeout: 10)); reach(path, in: app); path.tap()
        XCTAssertTrue(app.staticTexts["每天学一点。"].waitForExistence(timeout: 10))
        capture(app, "daily-study-chinese-accessible")
        let settings = app.buttons["study.configure"]
        reach(settings, in: app, swipes: 30)
        settings.tap()
        XCTAssertTrue(app.navigationBars["每日学习与提醒"].waitForExistence(timeout: 5))
        capture(app, "daily-study-settings-chinese-accessible")
        let reminder = app.switches["study.reminderToggle"]
        for _ in 0..<8 {
            if reminder.exists && reminder.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(reminder.isHittable)
        capture(app, "daily-study-reminders-chinese-accessible")
    }
}
