import XCTest

@MainActor final class DailyStudyAcceptanceTests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDailyStudyCompletesAndReopeningKeepsBudget() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--daily-study-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let start = app.buttons["study.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        capture(app, "daily-study-home-actions")
        start.tap()
        XCTAssertTrue(app.buttons["Show answer"].waitForExistence(timeout: 10))
        capture(app, "daily-study-starts-directly")
        for index in 1...5 {
            let answer = app.buttons["Show answer"]
            XCTAssertTrue(answer.waitForExistence(timeout: 5)); answer.tap()
            let good = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Good")).firstMatch
            XCTAssertTrue(good.waitForExistence(timeout: 5))
            if index == 1 { capture(app, "daily-study-rating-actions") }
            good.tap()
        }
        XCTAssertTrue(app.staticTexts["You studied 5 cards. Your progress is saved."].waitForExistence(timeout: 5))
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
        app.buttons["Done"].tap()
        app.buttons["study.start"].tap()
        XCTAssertTrue(app.staticTexts["5 cards completed today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["study.review"].exists)
    }
    func testChineseAccessibleStudySettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--library-design-preview", "--daily-study-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["study.start"].waitForExistence(timeout: 10)); app.buttons["study.start"].tap()
        XCTAssertTrue(app.navigationBars["复习"].waitForExistence(timeout: 10))
        app.navigationBars["复习"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["每天学一点。"].waitForExistence(timeout: 10))
        capture(app, "daily-study-chinese-accessible")
        let settings = app.buttons["study.configure"]
        if !settings.isHittable { app.swipeUp() }
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
