import PDFKit
import SwiftData

@MainActor enum PDFMarks {
    /// Keep the original bytes until both the atomic file write and model save succeed.
    private static func commit(_ pdf: PDFDocument, at url: URL, context: ModelContext,
                               update: () -> Void) throws {
        try context.save()
        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let changed = pdf.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
        try changed.write(to: url, options: .atomic)
        update()
        do { try context.save() }
        catch {
            context.rollback()
            try original.write(to: url, options: .atomic)
            throw error
        }
    }

    static func add(_ kind: PDFAnnotationSubtype, coordinator: PDFCoordinator, pdf: PDFDocument,
                    doc: PDFDoc, context: ModelContext) throws {
        guard let page = coordinator.selectionPage else { return }
        let quote = coordinator.selectionText
        let entry = DictEntry(term: quote, kind: "highlight", sourceKind: "pdf")
        let annotations = coordinator.annotate(kind, color: HL.all[0].ui, id: entry.id)
        guard !annotations.isEmpty else { return }
        do {
            try commit(pdf, at: Files.url(doc.fileName), context: context) {
                guard kind == .highlight else { return }
                entry.languageCode = doc.languageCode
                entry.colorIdx = 0
                entry.context = quote
                entry.sourceID = doc.id.uuidString
                entry.sourceName = doc.title
                entry.sourcePos = Double(page)
                entry.rects = annotations.map { [$0.bounds.minX, $0.bounds.minY, $0.bounds.width, $0.bounds.height] }
                context.insert(entry)
            }
        } catch {
            for annotation in annotations { annotation.page?.removeAnnotation(annotation) }
            throw error
        }
    }

    static func remove(_ entry: DictEntry, from doc: PDFDoc, openDocument: PDFDocument?, context: ModelContext) throws {
        let url = Files.url(doc.fileName)
        guard let pdf = openDocument ?? PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        let name = PDFAnnotationKey(rawValue: "/NM")
        var matches: [(PDFPage, PDFAnnotation)] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            for mark in page.annotations where mark.type == "Highlight" {
                if mark.value(forAnnotationKey: name) as? String == entry.id.uuidString {
                    matches.append((page, mark))
                }
            }
        }
        // Older records identify a highlight by its rectangles on the recorded page.
        if matches.isEmpty, let index = Int(exactly: entry.sourcePos), let page = pdf.page(at: index) {
            var candidates = page.annotations.filter { $0.type == "Highlight" && $0.value(forAnnotationKey: name) == nil }
            for rect in entry.rects where rect.count == 4 {
                if let i = candidates.firstIndex(where: { mark in
                    let bounds = mark.bounds
                    return zip(rect, [bounds.minX, bounds.minY, bounds.width, bounds.height]).allSatisfy { abs($0 - $1) < 0.5 }
                }) { matches.append((page, candidates.remove(at: i))) }
            }
        }
        for (page, mark) in matches { page.removeAnnotation(mark) }
        do { try commit(pdf, at: url, context: context) { context.delete(entry) } }
        catch {
            for (page, mark) in matches { page.addAnnotation(mark) }
            throw error
        }
    }
}
