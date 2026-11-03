import SwiftUI
import PDFKit
import Observation

/// Geometry is in the PDFView's coordinates. Text and page identify the request;
/// scrolling and zooming can move the anchor without repeating translation.
struct PDFSelectedText: Equatable, Identifiable {
    var id: String { "\(page):\(text)" }
    let text: String
    let page: Int
    let rect: CGRect
}

@MainActor @Observable
final class PDFSelectionTranslation {
    private(set) var text: String?
    private(set) var error: String?
    private(set) var loading = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var currentKey: TranslationKey?
    @ObservationIgnored private var cache: [TranslationKey: String] = [:]
    @ObservationIgnored private let translate: @MainActor (String, String) async throws -> String
    @ObservationIgnored private let debounce: Duration

    init(debounce: Duration = .milliseconds(350),
         translate: @escaping @MainActor (String, String) async throws -> String = { text, source in
             guard let output = try await AI.translate([text], from: Language.find(source), to: Language.find("zh")).first,
                   !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidResponse }
             return output
         }) {
        self.debounce = debounce
        self.translate = translate
    }

    func select(_ selection: PDFSelectedText?, source: String, retry: Bool = false) {
        guard let selection, !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cancel(); return
        }
        let key = TranslationKey(source: source, target: "zh", texts: [selection.text])
        guard retry || key != currentKey else { return }
        cancel()
        currentKey = key
        if let cached = cache[key] { text = cached; return }
        let id = UUID(); requestID = id
        let generation = Operations.shared.generation
        loading = true
        task = Task {
            defer { if requestID == id { loading = false; task = nil } }
            do {
                try await Task.sleep(for: debounce)
                let result = try await translate(selection.text, source)
                try Task.checkCancellation()
                try Operations.shared.checkpoint(generation)
                guard requestID == id else { return }
                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidResponse }
                cache[key] = result
                text = result
            } catch {
                guard requestID == id, !Task.isCancelled, !(error is CancellationError) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() {
        requestID = UUID(); task?.cancel(); task = nil
        currentKey = nil; text = nil; error = nil; loading = false
    }
}

/// System presentation keeps translation separate from the original PDF's rendering.
struct PDFTranslationSheet: View {
    let selection: PDFSelectedText
    let translation: PDFSelectionTranslation
    let retry: () -> Void
    let close: () -> Void
    let highlight: () -> Void
    let underline: () -> Void
    let note: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Chinese translation").font(.headline)
                Spacer()
                Menu {
                    Button("Copy original", systemImage: "doc.on.doc") { UIPasteboard.general.string = selection.text }
                    if let translated = translation.text {
                        Button("Copy translation", systemImage: "character.bubble") { UIPasteboard.general.string = translated }
                    }
                    Divider()
                    Button("Highlight", systemImage: "highlighter", action: highlight)
                    Button("Underline", systemImage: "underline", action: underline)
                    Button("Add note", systemImage: "note.text", action: note)
                } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel("Translation actions")
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close translation")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selection.text).font(.subheadline).foregroundStyle(.secondary)
                    result
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Theme.ink)
    }

    private var result: some View {
        Group {
            if let text = translation.text {
                Text(text).font(.title3).textSelection(.enabled).accessibilityIdentifier("pdf.translation.result")
            } else if let error = translation.error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try again", action: retry)
                }
            } else {
                ProgressView("Translating…").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
