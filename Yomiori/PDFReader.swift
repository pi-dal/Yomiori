import SwiftUI
import PDFKit

@MainActor final class PDFCoordinator {
    weak var view: PDFView?
    private var retainedSelection: PDFSelection?
    private var activeSelection: PDFSelection? { view?.currentSelection ?? retainedSelection }
    var selectionText: String { activeSelection?.string ?? "" }
    var selectionPage: Int? {
        guard let view, let page = activeSelection?.pages.first, let document = view.document else { return nil }
        return document.index(for: page)
    }

    /// A system presentation may clear PDFKit's visible selection. Annotation still uses the saved range.
    func retainSelection() { retainedSelection = view?.currentSelection?.copy() as? PDFSelection }
    func clearSelection() { retainedSelection = nil; view?.clearSelection() }

    var isSelecting: Bool {
        func tracking(in view: UIView) -> Bool {
            if view.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true { return true }
            return view.subviews.contains(where: tracking)
        }
        return view.map { tracking(in: $0) } ?? false
    }

    @discardableResult
    func annotate(_ kind: PDFAnnotationSubtype, color: UIColor) -> [[Double]] {
        guard let selection = activeSelection else { return [] }
        var rects: [[Double]] = []
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                let annotation = PDFAnnotation(bounds: bounds, forType: kind, withProperties: nil)
                annotation.color = kind == .highlight ? color : .label
                rects.append([bounds.minX, bounds.minY, bounds.width, bounds.height])
                annotation.quadrilateralPoints = [CGPoint(x: 0, y: bounds.height), CGPoint(x: bounds.width, y: bounds.height),
                                                 CGPoint(x: 0, y: 0), CGPoint(x: bounds.width, y: 0)].map { NSValue(cgPoint: $0) }
                page.addAnnotation(annotation)
            }
        }
        clearSelection()
        return rects
    }
}

/// PDFKit paints the original page. Translation is presented separately, never as page content.
struct PDFReader: UIViewRepresentable {
    let pdf: PDFDocument
    @Binding var page: Int
    let coordinator: PDFCoordinator
    let onSelect: (PDFSelectedText?) -> Void

    func makeCoordinator() -> Observer { Observer(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = SelectionPDFView()
        view.backgroundColor = .secondarySystemBackground
        view.document = pdf
        view.displayBox = .cropBox
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.accessibilityIdentifier = "pdf.original"
        coordinator.view = view
        context.coordinator.observe(view)
        let initialPage = min(max(0, page), max(0, pdf.pageCount - 1))
        // PDFKit emits page-zero notifications while laying out a new view. Restore after
        // that layout, then begin publishing user page changes back to the saved position.
        DispatchQueue.main.async { [weak view, weak observer = context.coordinator] in
            guard let view, let observer else { return }
            view.layoutIfNeeded()
            view.layoutDocumentView()
            if let first = pdf.page(at: initialPage) { view.go(to: first) }
            observer.restoringPosition = false
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--pdf-preview-long") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak view] in
                guard let view, let selection = pdf.findString("Keep the page exactly as it was designed.", withOptions: []).first else { return }
                view.setCurrentSelection(selection, animate: false)
            }
        }
        #endif
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.restoringPosition,
           let destination = pdf.page(at: page), view.currentPage != destination {
            view.go(to: destination)
        }
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Observer) { coordinator.stop() }

    @MainActor final class Observer: NSObject, UIGestureRecognizerDelegate {
        var parent: PDFReader
        var restoringPosition = true
        private weak var view: PDFView?
        private weak var scrollView: UIScrollView?
        private var scrollObservation: NSKeyValueObservation?
        private var stopped = false
        private var selectionPending = false
        private var pagePending = false
        init(_ parent: PDFReader) { self.parent = parent }
        deinit { NotificationCenter.default.removeObserver(self) }

        func observe(_ view: PDFView) {
            self.view = view
            for name in [Notification.Name.PDFViewSelectionChanged, .PDFViewScaleChanged, .PDFViewVisiblePagesChanged] {
                NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: name, object: view)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            view.addGestureRecognizer(tap)
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, !self.stopped else { return }
                if let scroll = self.findScroll(in: view) {
                    self.scrollView = scroll
                    self.scrollObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                        Task { @MainActor in self?.selectionChanged() }
                    }
                }
            }
        }

        func stop() {
            stopped = true
            NotificationCenter.default.removeObserver(self)
            scrollObservation?.invalidate(); scrollObservation = nil
        }

        private func findScroll(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { self.findScroll(in: $0) }.first
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view else { return }
            let point = recognizer.location(in: view)
            guard let page = view.page(for: point, nearest: false) else { view.clearSelection(); return }
            let pagePoint = view.convert(point, to: page)
            // Preserve PDF links and annotations' native handling.
            if page.annotation(at: pagePoint) != nil { return }
            if let selection = page.selectionForWord(at: pagePoint),
               !((selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                view.setCurrentSelection(selection, animate: false)
                selectionChanged()
            } else { view.clearSelection() }
        }

        @objc func selectionChanged() {
            guard !stopped, !selectionPending else { return }
            selectionPending = true
            // PDFKit can notify synchronously inside updateUIView / go(to:).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.selectionPending = false
                guard !self.stopped else { return }
                self.publishSelection()
            }
        }

        private func publishSelection() {
            guard let view, let document = view.document, let selection = view.currentSelection,
                  let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  let selectedPage = selection.pages.first else { parent.onSelect(nil); return }
            let rect = view.convert(selection.bounds(for: selectedPage), from: selectedPage)
            guard rect.intersects(view.bounds), !rect.isEmpty else { parent.onSelect(nil); return }
            parent.onSelect(PDFSelectedText(text: text, page: document.index(for: selectedPage), rect: rect))
        }

        @objc private func pageChanged() {
            guard !stopped, !restoringPosition, !pagePending else { return }
            pagePending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pagePending = false
                guard !self.stopped, let view = self.view,
                      let page = view.currentPage, let document = view.document else { return }
                let index = document.index(for: page)
                if index != NSNotFound, index != self.parent.page { self.parent.page = index }
                self.publishSelection()
            }
        }
    }
}

/// Keep selection handles while preventing a second system menu from covering the translation.
private final class SelectionPDFView: PDFView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}
