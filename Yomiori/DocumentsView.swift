import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

struct DocumentsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \PDFDoc.createdAt, order: .reverse) private var docs: [PDFDoc]
    @State private var picking = false
    @State private var error: String?
    @State private var toDelete: PDFDoc?
    @State private var path: [PDFDoc] = []
    @State private var search = ""
    @AppStorage("documentLibraryOrder") private var order = LibraryOrder.newest
    @AppStorage("lastOpenedDocument") private var lastOpenedID = ""

    private var shown: [PDFDoc] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return order.sorted(docs.filter { query.isEmpty || $0.title.localizedStandardContains(query) },
                            title: { $0.title }, createdAt: { $0.createdAt })
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if docs.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Keep the whole page.")
                                .literary(.title1)
                            Text("Read the original. Select a word for its meaning.")
                                .font(.body).foregroundStyle(Theme.textSecondary)
                            SourceAction(symbol: "doc.badge.plus", title: "Import a PDF", detail: "Choose from Files.") { picking = true }
                                .padding(.top, 20)
                        }
                        .padding(.horizontal, 24).padding(.vertical, 28)
                        .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
                    }
                } else if shown.isEmpty {
                    LibrarySearchEmpty(search: $search)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 156), spacing: 22, alignment: .top)], alignment: .leading, spacing: 28) {
                            ForEach(shown) { doc in
                                NavigationLink(value: doc) {
                                    Group {
                                        if dynamicTypeSize.isAccessibilitySize {
                                            HStack(alignment: .top, spacing: 16) {
                                                Thumb(doc: doc).frame(width: 64, height: 88).accessibilityHidden(true)
                                                documentInfo(doc)
                                            }
                                        } else {
                                            VStack(alignment: .leading, spacing: 10) {
                                                Thumb(doc: doc).aspectRatio(0.72, contentMode: .fit).accessibilityHidden(true)
                                                documentInfo(doc)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressFeedbackStyle())
                                .contextMenu { Button("Delete", role: .destructive) { toDelete = doc } }
                                .accessibilityAction(named: Text("Delete")) { toDelete = doc }
                            }
                        }
                        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 32)
                        .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Documents").navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search document titles")
            .navigationDestination(for: PDFDoc.self) { doc in
                DocViewer(doc: doc).onAppear { lastOpenedID = doc.id.uuidString }
            }
            .onAppear { openJump() }
            .onChange(of: app.jumpDoc?.id) { _, _ in openJump() }
            .toolbar {
                if !docs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let document = docs.first(where: { $0.id.uuidString == lastOpenedID }) {
                                Button { path.append(document) } label: {
                                    Label("Continue reading", systemImage: "book")
                                    Text(document.title)
                                }
                                Divider()
                            }
                            Picker("Sort", selection: $order) {
                                ForEach(LibraryOrder.allCases, id: \.self) { value in Text(value.label).tag(value) }
                            }
                        } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("Document options")
                    }.sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { picking = true } label: { Image(systemName: "plus") }.accessibilityLabel("Import document")
                }.sharedBackgroundVisibility(.hidden)
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf]) { result in
                guard case .success(let url) = result else { return }
                do {
                    let name = try Files.importFile(url)
                    guard let pdf = PDFDocument(url: Files.url(name)) else { throw CocoaError(.fileReadCorruptFile) }
                    let doc = PDFDoc(title: url.deletingPathExtension().lastPathComponent, fileName: name)
                    doc.languageCode = Prefs.target.code
                    doc.pageCount = pdf.pageCount
                    ctx.insert(doc); path = [doc]
                } catch { self.error = url.lastPathComponent + "\n" + L10n.string("Couldn't open this PDF.") }
            }
            .alert("Couldn't import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Choose another file") { picking = true }; Button("Cancel", role: .cancel) {}
            } message: { Text(error ?? "") }
            .confirmationDialog(L10n.string("doc.deleteTitle") + "\n" + L10n.string("doc.deleteBody"),
                                isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let doc = toDelete {
                        try? FileManager.default.removeItem(at: Files.url(doc.fileName))
                        let id = doc.id.uuidString
                        try? ctx.delete(model: DictEntry.self, where: #Predicate { $0.sourceID == id })
                        if lastOpenedID == doc.id.uuidString { lastOpenedID = "" }
                        ctx.delete(doc)
                    }
                    toDelete = nil
                }
                Button("Cancel", role: .cancel) { toDelete = nil }
            }
        }
    }

    private func documentInfo(_ doc: PDFDoc) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(doc.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            Text(L10n.format("doc.page", Int64(doc.lastPage + 1), Int64(doc.pageCount)))
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openJump() {
        if let jump = app.jumpDoc, let doc = docs.first(where: { $0.id.uuidString == jump.id }) { path = [doc] }
    }
}

struct Thumb: View {
    let doc: PDFDoc
    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                        .shadow(color: .black.opacity(0.08), radius: 9, x: 0, y: 5)
                } else if loaded {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text").font(.title2)
                        Text("Preview unavailable").font(.caption).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Theme.textSecondary).padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 3))
                } else {
                    ProgressView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: doc.fileName) {
            image = nil; loaded = false
            let url = Files.url(doc.fileName)
            let rendered = await Task.detached(priority: .utility) {
                autoreleasepool {
                    PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 480, height: 672), for: .cropBox)
                }
            }.value
            guard !Task.isCancelled else { return }
            image = rendered; loaded = true
        }
    }
}

struct DocViewer: View {
    @Bindable var doc: PDFDoc
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query private var notes: [DictEntry]
    @State private var pdf: PDFDocument?
    @State private var page = 0
    @State private var coordinator = PDFCoordinator()
    @State private var selection: PDFSelectedText?
    @State private var translation: PDFSelectionTranslation
    @State private var showingNotes = false
    @State private var presentedSelection: PDFSelectedText?
    @State private var pendingNote = false
    @State private var noteDraft: String?
    @State private var noteQuote = ""
    @State private var notePage = 0
    @State private var saveError: String?

    init(doc: PDFDoc) {
        self.doc = doc
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--pdf-preview") {
            _translation = State(initialValue: PDFSelectionTranslation { text, _ in "阅读（测试译文）：\(text)" })
        } else { _translation = State(initialValue: PDFSelectionTranslation()) }
        #else
        _translation = State(initialValue: PDFSelectionTranslation())
        #endif
        let id = doc.id.uuidString
        _notes = Query(filter: #Predicate<DictEntry> { $0.sourceID == id }, sort: \.sourcePos)
    }

    var body: some View {
        Group {
            if let pdf {
                PDFReader(pdf: pdf, page: $page, coordinator: coordinator) { selected in
                    if let selected {
                        selection = selected
                        translation.select(selected, source: doc.languageCode)
                    } else if presentedSelection == nil {
                        selection = nil
                        translation.cancel()
                    }
                }
                .onChange(of: page) { _, value in doc.lastPage = value }
                .task(id: selection?.id) {
                    guard let selection else { return }
                    do {
                        try await Task.sleep(for: .milliseconds(550))
                        while coordinator.isSelecting { try await Task.sleep(for: .milliseconds(100)) }
                        try Task.checkCancellation()
                        coordinator.retainSelection()
                        presentedSelection = selection
                    } catch {}
                }
                .sheet(item: $presentedSelection, onDismiss: {
                    coordinator.clearSelection()
                    selection = nil
                    translation.cancel()
                    if pendingNote { pendingNote = false; noteDraft = "" }
                }) { selected in
                    PDFTranslationSheet(selection: selected, translation: translation,
                                        retry: { translation.select(selected, source: doc.languageCode, retry: true) },
                                        close: { presentedSelection = nil },
                                        highlight: { annotate(.highlight); presentedSelection = nil },
                                        underline: { annotate(.underline); presentedSelection = nil },
                                        note: {
                                            noteQuote = selected.text; notePage = selected.page
                                            pendingNote = true; presentedSelection = nil
                                        })
                        .presentationDetents([.height(260), .medium, .large])
                        .presentationDragIndicator(.visible)
                }
            } else {
                ContentUnavailableView {
                    Label("Couldn't open this PDF.", systemImage: "doc.questionmark")
                } actions: { Button("Try again") { load() } }
            }
        }
        .background(Theme.groupedBackground)
        .navigationTitle(doc.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingNotes = true } label: { Image(systemName: "note.text") }.accessibilityLabel("doc.notes")
                Menu {
                    Picker("Language", selection: $doc.languageCode) {
                        Text("Japanese").tag("ja"); Text("English").tag("en")
                    }
                    ShareLink(item: Files.url(doc.fileName)) { Label("Share", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Document options")
            }
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 16) {
                    Button { go(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(page <= 0).accessibilityLabel("Previous page")
                    Text(L10n.format("doc.page", Int64(page + 1), Int64(doc.pageCount)))
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    Button { go(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(page >= doc.pageCount - 1).accessibilityLabel("Next page")
                }
            }
        }
        .immersion("reading", active: true)
        .onAppear { load() }
        .onDisappear { translation.cancel() }
        .onChange(of: doc.languageCode) { _, source in translation.select(selection, source: source) }
        .onChange(of: app.jumpDoc?.page) { _, _ in
            guard let jump = app.jumpDoc, jump.id == doc.id.uuidString, let pdf else { return }
            coordinator.clearSelection()
            page = min(max(0, jump.page), max(0, pdf.pageCount - 1))
            app.jumpDoc = nil
        }
        .sheet(isPresented: $showingNotes) {
            NavigationStack {
                notesList
                    .navigationTitle("doc.notes").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingNotes = false } } }
            }
        }
        .alert("Note", isPresented: Binding(get: { noteDraft != nil }, set: { if !$0 { noteDraft = nil } })) {
            TextField("Write a note", text: Binding(get: { noteDraft ?? "" }, set: { noteDraft = $0 }))
            Button("Save") { saveNote() }
            Button("Cancel", role: .cancel) { noteDraft = nil }
        } message: { Text(noteQuote.prefix(120)) }
        .alert("Couldn't save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(saveError ?? "") }
    }

    private func load() {
        guard pdf == nil else { return }
        guard let loaded = PDFDocument(url: Files.url(doc.fileName)) else { return }
        let requested: Int
        if let jump = app.jumpDoc, jump.id == doc.id.uuidString {
            requested = jump.page; app.jumpDoc = nil
        } else { requested = doc.lastPage }
        page = min(max(0, requested), max(0, loaded.pageCount - 1))
        doc.pageCount = loaded.pageCount
        doc.lastPage = page
        pdf = loaded
    }

    private func go(_ offset: Int) {
        coordinator.clearSelection()
        page = min(max(0, page + offset), max(0, doc.pageCount - 1))
        doc.lastPage = page
    }

    private func annotate(_ kind: PDFAnnotationSubtype) {
        let quote = coordinator.selectionText, selectedPage = coordinator.selectionPage ?? page
        let rects = coordinator.annotate(kind, color: HL.all[0].ui)
        if kind == .highlight, !quote.isEmpty {
            let entry = DictEntry(term: quote, kind: "highlight", sourceKind: "pdf")
            entry.languageCode = doc.languageCode
            entry.colorIdx = 0; entry.context = quote; entry.sourceID = doc.id.uuidString
            entry.sourceName = doc.title; entry.sourcePos = Double(selectedPage); entry.rects = rects
            ctx.insert(entry)
        }
        if let pdf, !pdf.write(to: Files.url(doc.fileName)) { saveError = L10n.string("Couldn't save") }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func saveNote() {
        guard let text = noteDraft, !text.isEmpty else { noteDraft = nil; return }
        let entry = DictEntry(term: noteQuote, kind: "note", sourceKind: "pdf")
        entry.languageCode = doc.languageCode
        entry.note = text; entry.context = noteQuote; entry.sourceID = doc.id.uuidString
        entry.sourceName = doc.title; entry.sourcePos = Double(notePage)
        ctx.insert(entry); noteDraft = nil
    }

    private var notesList: some View {
        List {
            if notes.isEmpty { ContentUnavailableView("No notes", systemImage: "note.text").listRowSeparator(.hidden) }
            ForEach(notes) { note in
                Button {
                    coordinator.clearSelection(); page = Int(note.sourcePos); showingNotes = false
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.format("doc.page", Int64(note.sourcePos + 1), Int64(doc.pageCount)))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(note.term).foregroundStyle(Theme.ink)
                        if !note.note.isEmpty { Text(note.note).foregroundStyle(.secondary) }
                    }.padding(.vertical, 8)
                }
            }.onDelete { for index in $0 { ctx.delete(notes[index]) } }
        }.listStyle(.plain)
    }
}
