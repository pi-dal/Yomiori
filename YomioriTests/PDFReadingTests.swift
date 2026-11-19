import Foundation
import PDFKit
import UIKit
import Testing
@testable import Yomiori

@MainActor private final class PDFTranslationGate {
    private var continuation: CheckedContinuation<String, Never>?
    var waiting: Bool { continuation != nil }
    func wait() async -> String { await withCheckedContinuation { continuation = $0 } }
    func resume(_ value: String) { continuation?.resume(returning: value); continuation = nil }
}

@MainActor struct PDFReadingTests {
    private func selected(_ text: String, rect: CGRect = CGRect(x: 10, y: 20, width: 40, height: 20)) -> PDFSelectedText {
        PDFSelectedText(text: text, page: 0, rect: rect)
    }

    @Test func reselectingTextReusesTranslationOnlyForTheSameLanguage() async throws {
        var requests: [(String, String)] = []
        let session = PDFSelectionTranslation(debounce: .zero) { text, source in
            requests.append((text, source)); return "中文：\(text)"
        }
        session.select(selected("Reading"), source: "en")
        while session.loading { await Task.yield() }
        #expect(session.text == "中文：Reading")
        session.select(selected("Reading", rect: CGRect(x: 50, y: 80, width: 60, height: 20)), source: "en")
        #expect(requests.count == 1)
        session.select(nil, source: "en")
        #expect(session.text == nil)
        session.select(selected("Reading"), source: "en")
        #expect(session.text == "中文：Reading")
        #expect(requests.count == 1)
        session.select(selected("Reading"), source: "ja")
        while session.loading { await Task.yield() }
        #expect(requests.count == 2)
        #expect(requests.last?.1 == "ja")
    }

    @Test func lateSelectionResponseCannotReplaceNewSelection() async throws {
        let gate = PDFTranslationGate()
        let session = PDFSelectionTranslation(debounce: .zero) { text, _ in
            if text == "old" { return await gate.wait() }
            return "新译文"
        }
        session.select(selected("old"), source: "en")
        while !gate.waiting { await Task.yield() }
        session.select(selected("new"), source: "en")
        while session.loading { await Task.yield() }
        #expect(session.text == "新译文")
        gate.resume("旧译文")
        for _ in 0..<20 { await Task.yield() }
        #expect(session.text == "新译文")
        session.cancel()
        #expect(session.text == nil && !session.loading)
    }

    @Test func selectionFailureCanRetry() async throws {
        var attempts = 0
        let session = PDFSelectionTranslation(debounce: .zero) { _, _ in
            attempts += 1
            if attempts == 1 { throw AIError.offline }
            return "阅读"
        }
        session.select(selected("Reading"), source: "en")
        while session.loading { await Task.yield() }
        #expect(session.error != nil)
        session.select(selected("Reading"), source: "en", retry: true)
        while session.loading { await Task.yield() }
        #expect(session.error == nil && session.text == "阅读")
    }

}
