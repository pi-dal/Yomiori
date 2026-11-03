import XCTest

@MainActor final class PDFReadingAcceptanceTests: XCTestCase {
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLongTranslationSheetAndNote() {
        let app = XCUIApplication()
        app.launchArguments = ["--pdf-preview", "--pdf-preview-long", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let result = app.staticTexts["pdf.translation.result"]
        guard result.waitForExistence(timeout: 12) else { XCTFail(app.debugDescription); return }
        XCTAssertTrue(result.label.contains("Keep the page exactly"))
        capture(app, "pdf-long-selection")
        app.buttons["Translation actions"].tap()
        app.buttons["Add note"].tap()
        XCTAssertTrue(app.alerts["Note"].waitForExistence(timeout: 5))
        app.alerts["Note"].textFields.firstMatch.tap()
        app.alerts["Note"].textFields.firstMatch.typeText("Layout preserved")
        app.alerts["Note"].buttons["Save"].tap()
        app.buttons["Notes"].tap()
        XCTAssertTrue(app.staticTexts["Layout preserved"].waitForExistence(timeout: 5))
    }

    func testOriginalPDFAndAutomaticChineseSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["--pdf-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["PDF layout preview"].waitForExistence(timeout: 10))
        let pdf = app.descendants(matching: .any)["pdf.original"].firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 5))
        let frame = pdf.frame
        capture(app, "pdf-original")
        // The synthetic first page places “Reading” at x=40,y=210 of its 600×800 canvas.
        // Use the visible page's text element when PDFKit exposes it, otherwise its page coordinate.
        let reading = app.staticTexts.matching(NSPredicate(format: "label == %@", "Reading")).firstMatch
        if reading.exists { reading.tap() }
        else { pdf.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.27)).tap() }
        let result = app.staticTexts["pdf.translation.result"]
        guard result.waitForExistence(timeout: 8) else {
            XCTFail(app.debugDescription); return
        }
        XCTAssertTrue(result.label.contains("阅读"))
        XCTAssertEqual(pdf.frame, frame)
        capture(app, "pdf-selected-chinese")
        app.buttons["Close translation"].tap()
        XCTAssertFalse(result.exists)
        XCTAssertEqual(pdf.frame, frame)
        capture(app, "pdf-original-restored")
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 2"].waitForExistence(timeout: 5))
        capture(app, "pdf-second-page")
    }
}
