import XCTest

/// The study loop's acknowledgement moments: graded choices, a word that sticks, the session's page of words
/// and the stroke beneath a studied word. Language-independent, so it also runs in Chinese and at accessibility sizes.
@MainActor final class InkMomentsAcceptanceTests: XCTestCase {
    private let meanings = ["毎日、少しずつ学びます。": "every day", "京都の朝は静かです。": "quiet",
                            "小さな喫茶店で本を読みます。": "café", "今日は何を読もうか。": "to read",
                            "新しい言葉を覚えます。": "to remember"]

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        let env = ProcessInfo.processInfo.environment
        let language = env["INK_LANGUAGE"] ?? "en"
        app.launchArguments = ["--library-design-preview", "--daily-study-preview",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if let size = env["INK_SIZE"] { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        return app
    }

    private func currentSentence(_ app: XCUIApplication) throws -> String {
        try XCTUnwrap(meanings.keys.first { app.staticTexts[$0].exists })
    }

    func testWrongChoiceAndCorrectAnswerRemainAccessibleUntilNext() throws {
        let app = launch()
        let start = app.buttons["study.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10)); start.tap()
        XCTAssertTrue(app.buttons["review.dontKnow"].waitForExistence(timeout: 10))

        // A wrong choice stays on the page, struck through, beside the checked answer.
        let missed = try currentSentence(app)
        let options = app.buttons.matching(identifier: "review.option")
        let wrong = try XCTUnwrap((0..<options.count).map { options.element(boundBy: $0) }.first { $0.label != meanings[missed]! })
        let wrongLabel = wrong.label
        wrong.tap()
        let next = app.buttons["review.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(options.count, 4, "graded choices remain in place")
        let struck = app.buttons.matching(NSPredicate(format: "identifier == 'review.option' AND label == %@", wrongLabel)).firstMatch
        let answer = app.buttons.matching(NSPredicate(format: "identifier == 'review.option' AND label == %@", meanings[missed]!)).firstMatch
        XCTAssertFalse((struck.value as? String ?? "").isEmpty)
        XCTAssertFalse((answer.value as? String ?? "").isEmpty)
        XCTAssertNotEqual(struck.value as? String, answer.value as? String)
    }
}
