#if DEBUG
import SwiftUI
import PDFKit
import SwiftData

/// A labeled synthetic PDF used only by opt-in tests, with no learner-library writes.
struct PDFReadingPreview: View {
    @State private var doc: PDFDoc?
    @Environment(\.modelContext) private var context
    var body: some View {
        NavigationStack {
            if let doc { DocViewer(doc: doc) } else { ProgressView() }
        }
        .task {
            guard doc == nil else { return }
            do {
                try FileManager.default.createDirectory(at: Files.dir, withIntermediateDirectories: true)
                let fileName = "pdf-layout-preview.pdf"
                try PDFReadingFixture.data().write(to: Files.url(fileName))
                let record = PDFDoc(title: "PDF layout preview", fileName: fileName)
                record.languageCode = "en"; record.pageCount = 2
                context.insert(record); doc = record
            } catch { assertionFailure(error.localizedDescription) }
        }
    }
}

@MainActor enum PDFReadingFixture {
    static func data(title: String = "Language in context", landscape: Bool = false) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: landscape ? 900 : 600, height: 800)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            for number in 1...2 {
                renderer.beginPage()
                UIColor.white.setFill(); renderer.cgContext.fill(bounds)
                draw("SYNTHETIC PDF · LAYOUT VERIFICATION", at: CGPoint(x: 40, y: 32), size: 10, color: .darkGray)
                draw(title, at: CGPoint(x: 40, y: 78), size: 30, weight: .bold)
                draw("Original type, columns and artwork", at: CGPoint(x: 40, y: 124), size: 14, color: .darkGray)
                UIColor.systemBlue.setFill(); renderer.cgContext.fill(CGRect(x: 40, y: 166, width: 520, height: 3))
                draw("Reading", at: CGPoint(x: 40, y: 210), size: 22, weight: .semibold)
                draw("Reading a little every day helps us notice\nnew words in their original context.\n\nKeep the page exactly as it was designed.\nSelect a word to see its Chinese meaning.", at: CGPoint(x: 40, y: 258), size: 14)
                draw("Listening", at: CGPoint(x: 320, y: 210), size: 22, weight: .semibold)
                draw("A familiar voice makes new phrases easier\nto remember. Listen, read and return to\nthe passage whenever you need it.", at: CGPoint(x: 320, y: 258), size: 14)
                UIColor(red: 0.91, green: 0.94, blue: 0.98, alpha: 1).setFill()
                renderer.cgContext.fill(CGRect(x: 40, y: 420, width: 520, height: 180))
                UIColor.systemBlue.setFill()
                renderer.cgContext.fillEllipse(in: CGRect(x: 80, y: 458, width: 100, height: 100))
                draw("A figure stays in place.", at: CGPoint(x: 220, y: 472), size: 20, weight: .medium)
                draw("Translation never redraws this page.", at: CGPoint(x: 220, y: 510), size: 14)
                draw("Page \(number) · Synthetic test content", at: CGPoint(x: 40, y: 750), size: 11, color: .darkGray)
            }
        }
    }

    private static func draw(_ text: String, at point: CGPoint, size: CGFloat,
                             weight: UIFont.Weight = .regular, color: UIColor = .black) {
        (text as NSString).draw(at: point, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
}
#endif
