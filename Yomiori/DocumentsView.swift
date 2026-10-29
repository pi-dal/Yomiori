import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

struct DocumentsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \PDFDoc.createdAt, order: .reverse) private var docs: [PDFDoc]
    @State private var picking = false
    @State private var error: String?
    @State private var toDelete: PDFDoc?
    @State private var path: [PDFDoc] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if docs.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No documents").font(Theme.Fonts.body.weight(.semibold))
                            Text("Import a PDF to start reading.")
                                .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                            Button { picking = true } label: {
                                Label("Import a PDF", systemImage: "plus")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16).frame(minHeight: 48)
                                    .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Choose a PDF from Files")
                        }.frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.top, 16).frame(maxWidth: .infinity)
                    }
                } else {
                    List {
                        Section("Recent Documents") {
                            ForEach(docs) { d in
                                NavigationLink(value: d) {
                                    HStack(spacing: 16) {
                                        Image(systemName: "doc.text").font(.system(size: 22)).frame(width: 24).accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(d.title).font(Theme.Fonts.body.weight(.semibold))
                                            Text(L10n.format("doc.page", Int64(d.lastPage + 1), Int64(d.pageCount)) + "  ·  Last read page \(d.lastPage + 1)")
                                                .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                                    }
                                    .frame(minHeight: 56, alignment: .leading)
                                }
                            }
                            .onDelete { offsets in for i in offsets { toDelete = docs[i] } }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background).font(Theme.Fonts.body).foregroundStyle(Theme.ink)
            .navigationTitle("Documents").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PDFDoc.self) { DocViewer(doc: $0) }
            .onAppear { if let j = app.jumpDoc, let d = docs.first(where: { $0.id.uuidString == j.id }) { path = [d] } }
            .onChange(of: app.jumpDoc?.id) { _, _ in if let j = app.jumpDoc, let d = docs.first(where: { $0.id.uuidString == j.id }) { path = [d] } }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { picking = true } label: { Label("Import document", systemImage: "plus") } } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf]) { r in
                guard case .success(let url) = r else { return }
                do {
                    let name = try Files.importFile(url)
                    guard let pdf = PDFDocument(url: Files.url(name)) else { throw CocoaError(.fileReadCorruptFile) }
                    let d = PDFDoc(title: url.deletingPathExtension().lastPathComponent, fileName: name)
                    d.languageCode = Prefs.target.code
                    d.pageCount = pdf.pageCount
                    ctx.insert(d); path = [d]
                } catch { self.error = url.lastPathComponent + "\n" + L10n.string("Couldn't open this PDF.") }
            }
            .alert("Couldn't import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Choose another file") { picking = true }; Button("Cancel", role: .cancel) {} } message: { Text(error ?? "") }
            .confirmationDialog(L10n.string("doc.deleteTitle") + "\n" + L10n.string("doc.deleteBody"), isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let d = toDelete {
                        try? FileManager.default.removeItem(at: Files.url(d.fileName))
                        let id = d.id.uuidString
                        try? ctx.delete(model: DictEntry.self, where: #Predicate { $0.sourceID == id })
                        ctx.delete(d)
                    }
                    toDelete = nil
                }
                Button("Cancel", role: .cancel) { toDelete = nil }
            }
        }
    }
}

struct Thumb: View {
    let doc: PDFDoc
    var body: some View {
        if let p = PDFDocument(url: Files.url(doc.fileName))?.page(at: 0) {
            Image(uiImage: p.thumbnail(of: CGSize(width: 80, height: 112), for: .mediaBox))
        } else { Theme.controlFill }
    }
}

enum PDFText {
    /// Splits a page's text into paragraphs: a line ending in sentence punctuation closes one.
    static func paragraphs(_ page: PDFPage) -> [String] {
        guard let raw = page.string else { return [] }
        var out: [String] = [], cur = ""
        let enders: Set<Character> = ["。", ".", "!", "?", "！", "？", "」", ":", "："]
        for line in raw.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { if !cur.isEmpty { out.append(cur); cur = "" }; continue }
            let cjk = t.unicodeScalars.contains { $0.value > 0x2E80 }
            cur += cur.isEmpty ? t : (cjk ? t : " " + t)
            if let l = t.last, enders.contains(l), cur.count > 40 { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

struct DocViewer: View {
    @Bindable var doc: PDFDoc
    @Environment(\.modelContext) private var ctx
    @Query private var notes: [DictEntry]
    @Environment(AppState.self) private var app
    @State private var mode = "Original"
    @State private var pdf: PDFDocument?
    @State private var page = 0
    @State private var coordinator = PDFCoordinator()
    @State private var translating = false
    @State private var translationError: String?
    @State private var pageTranslation: [String]?
    @State private var translationRequest = UUID()
    @State private var translationRetry = 0
    @AppStorage("nativeLang") private var nativeLanguage = Language.deviceDefault

    @State private var noteDraft: String?
    @State private var noteQuote = ""
    @State private var noText = false
    @State private var selected = false
    @State private var translateSel: String?

    init(doc: PDFDoc) {
        self.doc = doc
        let id = doc.id.uuidString
        _notes = Query(filter: #Predicate<DictEntry> { $0.sourceID == id }, sort: \.sourcePos)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextTabs(items: [("Original", L10n.string("doc.original")), ("Bilingual", L10n.string("doc.bilingual")), ("Notes", L10n.string("doc.notes"))], selection: $mode)
            if noText && mode != "Original" {
                VStack(spacing: 12) {
                    Text("No selectable text").font(Theme.Fonts.body.weight(.semibold))
                    Text("Scanned PDFs aren't supported.").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch mode {
                case "Original": original
                case "Bilingual": bilingual
                default: notesList
                }
            }
        }
        .background(Theme.background).font(Theme.Fonts.body).foregroundStyle(Theme.ink)
        .navigationTitle(doc.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Language", selection: $doc.languageCode) {
                        Text("Japanese").tag("ja"); Text("English").tag("en")
                    }
                } label: { Image(systemName: "character.bubble").frame(width: 44, height: 44) }
                    .accessibilityLabel("Language")
                ShareLink(item: Files.url(doc.fileName)) { Image(systemName: "square.and.arrow.up").font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel("Share")
            }
        }
        .immersion("reading", active: true)
        .onAppear {
            pdf = PDFDocument(url: Files.url(doc.fileName))
            page = doc.lastPage
            if let j = app.jumpDoc, j.id == doc.id.uuidString { page = j.page; app.jumpDoc = nil }
            if let p = pdf, !(0..<min(p.pageCount, 5)).contains(where: { !(p.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { noText = true }
        }
        .alert("Note", isPresented: Binding(get: { noteDraft != nil }, set: { if !$0 { noteDraft = nil } })) {
            TextField("Write a note", text: Binding(get: { noteDraft ?? "" }, set: { noteDraft = $0 }))
            Button("Save") { saveNote() }
            Button("Cancel", role: .cancel) { noteDraft = nil }
        } message: { Text(noteQuote.prefix(120)) }
        .sheet(item: Binding(get: { translateSel.map { Sel(text: $0) } }, set: { if $0 == nil { translateSel = nil } })) { s in
            SelectionTranslation(text: s.text, sourceLanguage: doc.languageCode).presentationDetents([.height(260), .medium])
        }
    }
    struct Sel: Identifiable { let text: String; var id: String { text } }

    private var original: some View {
        Group {
            if let pdf {
                PDFReader(pdf: pdf, page: $page, coordinator: coordinator, onSelect: { selected = $0 })
                    .onChange(of: page) { _, p in doc.lastPage = p }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Couldn't open this PDF.").font(Theme.Fonts.body.weight(.semibold))
                    Button("Try again") { pdf = PDFDocument(url: Files.url(doc.fileName)) }
                        .frame(minHeight: 48)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selected {
                HStack(spacing: 8) {
                    tool("highlighter", "Highlight") { annotate(.highlight) }
                    tool("underline", "Underline") { annotate(.underline) }
                    tool("note.text", "Add note") { noteQuote = coordinator.selectionText; noteDraft = "" }
                    tool("character.bubble", "Translate") { translateSel = coordinator.selectionText }
                }
                .frame(maxWidth: 720, minHeight: 56).padding(.horizontal, 24)
                .frame(maxWidth: .infinity).background(Theme.background)
                .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
            }
        }
    }
    private func tool(_ icon: String, _ label: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) { Image(systemName: icon).font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel(L10n.string(label))
    }

    private func annotate(_ kind: PDFAnnotationSubtype) {
        let quote = coordinator.selectionText, pg = coordinator.selectionPage ?? page
        let rects = coordinator.annotate(kind, color: HL.all[0].ui)
        if kind == .highlight, !quote.isEmpty {
            let e = DictEntry(term: quote, kind: "highlight", sourceKind: "pdf")
            e.colorIdx = 0; e.context = quote; e.sourceID = doc.id.uuidString; e.sourceName = doc.title; e.sourcePos = Double(pg); e.rects = rects
            ctx.insert(e)
        }
        if let pdf { pdf.write(to: Files.url(doc.fileName)) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func saveNote() {
        guard let t = noteDraft, !t.isEmpty else { noteDraft = nil; return }
        let e = DictEntry(term: noteQuote, kind: "note", sourceKind: "pdf")
        e.note = t; e.context = noteQuote; e.sourceID = doc.id.uuidString; e.sourceName = doc.title; e.sourcePos = Double(coordinator.selectionPage ?? page)
        ctx.insert(e)
        noteDraft = nil
    }

    // Bilingual
    private var bilingual: some View {
        let paras = pdf?.page(at: page).map(PDFText.paragraphs) ?? []
        let key = TranslationKey(source: doc.languageCode, target: nativeLanguage, texts: paras)
        let tr = pageTranslation
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if paras.isEmpty { Text("No text on this page").foregroundStyle(Theme.textSecondary) }
                    ForEach(Array(paras.enumerated()), id: \.offset) { i, p in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(p).font(Theme.Fonts.body).foregroundStyle(Theme.ink)
                            if let tr, i < tr.count, !tr[i].isEmpty {
                                Text(tr[i]).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                            } else if translating {
                                ProgressView(L10n.format("doc.translating", Int64(page + 1))).font(Theme.Fonts.meta)
                            }
                        }
                        .lineSpacing(6.5)
                        .padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                    }
                    if let translationError {
                        VStack(alignment: .leading) {
                            Label(translationError, systemImage: "exclamationmark.triangle").font(Theme.Fonts.meta).foregroundStyle(Theme.vermilion)
                            Button("Try again") { translationRetry += 1 }
                        }.padding(.top, 12)
                    }
                }.frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
            }
            pager
        }
        .task(id: "\(page):\(key.cacheID):\(translationRetry)") {
            await translatePage(texts: paras, source: doc.languageCode, target: nativeLanguage)
        }
    }

    private var pager: some View {
        HStack {
            Button { page = max(0, page - 1); doc.lastPage = page } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(page == 0).accessibilityLabel("Previous page")
            Spacer()
            Text(L10n.format("doc.page", Int64(page + 1), Int64(doc.pageCount))).font(Theme.Fonts.meta.monospacedDigit())
            Spacer()
            Button { page = min(doc.pageCount - 1, page + 1); doc.lastPage = page } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(page >= doc.pageCount - 1).accessibilityLabel("Next page")
        }.padding(.horizontal, 24).background(Theme.background)
    }

    private func translatePage(texts: [String], source: String, target: String) async {
        let request = UUID(); translationRequest = request
        pageTranslation = nil; translationError = nil; translating = true
        defer { if translationRequest == request { translating = false } }
        do {
            let output = try await TranslationService.page(doc, page: page, texts: texts, source: source, target: target, context: ctx)
            try Task.checkCancellation()
            guard translationRequest == request else { return }
            pageTranslation = output
        } catch {
            guard translationRequest == request, !Task.isCancelled, !(error is CancellationError) else { return }
            translationError = error.localizedDescription
        }
    }

    private var notesList: some View {
        List {
            if notes.isEmpty {
                EmptyState(symbol: "note.text", title: "No notes",
                           action: ("Open original", { mode = "Original" }))
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Theme.background)
                    .listRowSeparator(.hidden)
            }
            ForEach(notes) { n in
                Button { page = Int(n.sourcePos); mode = "Original" } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.format("doc.page", Int64(n.sourcePos + 1), Int64(doc.pageCount))).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        Text(n.term).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                        if !n.note.isEmpty { Text(n.note).font(Theme.Fonts.body).foregroundStyle(Theme.ink) }
                    }.padding(.vertical, 12).frame(maxWidth: 720, minHeight: 72, alignment: .leading).frame(maxWidth: .infinity)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                .listRowBackground(Theme.background)
            }
            .onDelete { for i in $0 { ctx.delete(notes[i]) } }
        }.listStyle(.plain).scrollContentBackground(.hidden)
    }
}

struct SelectionTranslation: View {
    let text: String
    let sourceLanguage: String
    @State private var out: String?
    @State private var failed = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(text).font(Theme.Fonts.body)
                Rectangle().fill(Theme.separator).frame(height: 0.5)
                if let out { Text(out).font(Theme.Fonts.body) }
                else if failed { Label("Translation unavailable", systemImage: "wifi.slash") }
                else { ProgressView() }
            }.padding(24)
        }
        .task {
            do { out = try await AI.translate([text], from: Language.find(sourceLanguage), to: Prefs.native).first } catch { failed = true }
        }
    }
}

@MainActor final class PDFCoordinator {
    weak var view: PDFView?
    var selectionText: String { view?.currentSelection?.string ?? "" }
    var selectionPage: Int? {
        guard let v = view, let p = v.currentSelection?.pages.first, let d = v.document else { return nil }
        return d.index(for: p)
    }
    @discardableResult
    func annotate(_ kind: PDFAnnotationSubtype, color: UIColor) -> [[Double]] {
        guard let sel = view?.currentSelection else { return [] }
        var rects: [[Double]] = []
        for line in sel.selectionsByLine() {
            for page in line.pages {
                let b = line.bounds(for: page)
                let a = PDFAnnotation(bounds: b, forType: kind, withProperties: nil)
                a.color = kind == .highlight ? color : UIColor(Theme.ink)
                rects.append([b.minX, b.minY, b.width, b.height])
                a.quadrilateralPoints = [CGPoint(x: 0, y: b.height), CGPoint(x: b.width, y: b.height), CGPoint(x: 0, y: 0), CGPoint(x: b.width, y: 0)].map { NSValue(cgPoint: $0) }
                page.addAnnotation(a)
            }
        }
        view?.clearSelection()
        return rects
    }
}

struct PDFReader: UIViewRepresentable {
    let pdf: PDFDocument
    @Binding var page: Int
    let coordinator: PDFCoordinator
    let onSelect: (Bool) -> Void

    func makeCoordinator() -> Obs { Obs(self) }
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.backgroundColor = UIColor(Theme.background)
        v.document = pdf; v.autoScales = true; v.displayMode = .singlePageContinuous
        coordinator.view = v
        if let p = pdf.page(at: page) { v.go(to: p) }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Obs.selChanged), name: .PDFViewSelectionChanged, object: v)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Obs.pageChanged), name: .PDFViewPageChanged, object: v)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        context.coordinator.parent = self
        if let p = pdf.page(at: page), v.currentPage != p, pdf.index(for: v.currentPage ?? p) != page { v.go(to: p) }
    }
    @MainActor final class Obs: NSObject {
        var parent: PDFReader
        init(_ p: PDFReader) { parent = p }
        @objc func selChanged(_ n: Notification) {
            let v = n.object as? PDFView
            parent.onSelect(!(v?.currentSelection?.string ?? "").isEmpty)
        }
        @objc func pageChanged(_ n: Notification) {
            guard let v = n.object as? PDFView, let p = v.currentPage, let d = v.document else { return }
            let i = d.index(for: p)
            if i != parent.page { parent.page = i }
        }
    }
}
