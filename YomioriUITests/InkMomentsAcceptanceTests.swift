import XCTest

/// The study loop's acknowledgement moments: graded choices, a word that sticks, the session's page of words
/// and the stroke beneath a studied word. Language-independent, so it also runs in Chinese and at accessibility sizes.
@MainActor final class InkMomentsAcceptanceTests: XCTestCase {
    private let meanings = ["毎日、少しずつ学びます。": "every day", "京都の朝は静かです。": "quiet",
                            "小さな喫茶店で本を読みます。": "café", "今日は何を読もうか。": "to read",
                            "新しい言葉を覚えます。": "to remember"]
    private var variant: String { ProcessInfo.processInfo.environment["INK_VARIANT"] ?? "en" }

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

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        if let directory = ProcessInfo.processInfo.environment["INK_SHOTS"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(variant)-\(name).png"))
        }
    }

    private func currentSentence(_ app: XCUIApplication) throws -> String {
        try XCTUnwrap(meanings.keys.first { app.staticTexts[$0].exists })
    }

    func testStudyLoopAcknowledgesEachAnswer() throws {
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
        sleep(1); capture(app, "recall-struck")
        next.tap()

        var capturedCorrect = false
        for step in 0..<14 {
            if app.buttons["review.finish"].waitForExistence(timeout: 1) { break }
            if app.buttons["review.gotIt"].exists { app.buttons["review.gotIt"].tap(); continue }
            XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5), "step \(step)")
            let sentence = try currentSentence(app)
            app.buttons.matching(NSPredicate(format: "label == %@", meanings[sentence]!)).firstMatch.tap()
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            if !capturedCorrect { sleep(1); capture(app, "recall-checked"); capturedCorrect = true }
            next.tap()
            // Let the outgoing card clear before reading the next one.
            _ = next.waitForNonExistence(timeout: 3)
            // 喫茶店 sits ten days out in the synthetic fixture; recalling it carries it past three weeks.
            if sentence == "小さな喫茶店で本を読みます。" { usleep(700_000); capture(app, "word-stuck") }
        }
        XCTAssertTrue(app.buttons["review.finish"].waitForExistence(timeout: 5))
        sleep(2)
        let page = app.otherElements.matching(NSPredicate(format: "label CONTAINS '喫茶店'")).firstMatch
        XCTAssertTrue(page.exists, "the session's words are one accessible page")
        capture(app, "session-page")
    }

    func testStudiedWordCarriesItsStrokeInTheWordSheet() throws {
        let app = launch()
        let featured = app.buttons["reading-featured"]
        XCTAssertTrue(featured.waitForExistence(timeout: 10))
        for _ in 0..<6 where !featured.isHittable { app.swipeUp() }
        featured.tap()
        let line = app.otherElements["reader-current-line"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        // 読み (a card word, 読む) begins at the eleventh character of 小さな喫茶店で、本を読みます。
        let size = 28.0
        line.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: size * 10.5, dy: line.frame.height > size * 3 ? size * 1.2 : line.frame.height * 0.6)).tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        // The studied word's note sits above its sentence; the large detent shows both.
        app.descendants(matching: .any)["read.studyNote"].firstMatch.swipeUp()
        sleep(2)
        capture(app, "word-sheet-stroke")
    }
}
