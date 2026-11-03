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

    @Test func selectionTranslationTargetsChineseCachesAndDoesNotRepeatForGeometry() async throws {
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

    @Test func pdfNotificationsDeferStateWritesAndIgnoreDismantledViews() async throws {
        let pdf = try #require(PDFDocument(data: PDFReadingFixture.data()))
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.document = pdf
        let coordinator = PDFCoordinator()
        var updates = 0, page = 0
        let parent = PDFReader(pdf: pdf, page: .init(get: { page }, set: { page = $0 }), coordinator: coordinator) { _ in updates += 1 }
        let observer = PDFReader.Observer(parent)
        observer.observe(view)
        observer.selectionChanged()
        #expect(updates == 0)
        for _ in 0..<20 { await Task.yield() }
        #expect(updates > 0)
        let count = updates
        observer.selectionChanged()
        observer.stop()
        for _ in 0..<20 { await Task.yield() }
        #expect(updates == count)
    }

    @Test func annotationUsesRetainedSelectionAfterSystemPresentation() throws {
        let pdf = try #require(PDFDocument(data: PDFReadingFixture.data()))
        let page = try #require(pdf.page(at: 0))
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.document = pdf
        let coordinator = PDFCoordinator(); coordinator.view = view
        let selection = try #require(pdf.findString("Reading", withOptions: []).first)
        view.setCurrentSelection(selection, animate: false)
        coordinator.retainSelection()
        view.clearSelection()
        #expect(coordinator.selectionText == "Reading")
        #expect(!coordinator.annotate(.highlight, color: .systemYellow).isEmpty)
        #expect(page.annotations.count > 0)
        #expect(coordinator.selectionText.isEmpty)
    }

    @Test func selectingAndTranslatingDoesNotAlterPDFRenderingOrViewport() async throws {
        let pdf = try #require(PDFDocument(data: PDFReadingFixture.data()))
        let page = try #require(pdf.page(at: 0))
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.document = pdf; view.autoScales = true; view.layoutDocumentView()
        let coordinator = PDFCoordinator(); coordinator.view = view
        let bounds = page.bounds(for: .mediaBox)
        let before = page.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox).pngData()
        let scale = view.scaleFactor, frame = view.frame
        let selection = try #require(pdf.findString("Reading", withOptions: []).first)
        view.setCurrentSelection(selection, animate: false)
        let session = PDFSelectionTranslation(debounce: .zero) { _, _ in "阅读" }
        session.select(PDFSelectedText(text: "Reading", page: 0, rect: view.convert(selection.bounds(for: page), from: page)), source: "en")
        while session.loading { await Task.yield() }
        #expect(session.text == "阅读")
        #expect(view.frame == frame && view.scaleFactor == scale)
        #expect(page.bounds(for: .mediaBox) == bounds)
        #expect(page.annotations.isEmpty)
        #expect(page.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox).pngData() == before)
        coordinator.clearSelection()
        #expect(view.currentSelection == nil)
    }
}
