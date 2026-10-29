import SwiftUI
import SwiftData
import PDFKit

struct DictionaryView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \DictEntry.createdAt, order: .reverse) private var all: [DictEntry]
    @State private var search = ""
    @State private var filter = "Words"
    @State private var sort = "Newest"
    @State private var selected: DictEntry?
    @Query private var cards: [Card]
    @AppStorage("reviewLimit") private var limit = 30
    @State private var reviewing = false
    @State private var showAllRecent = false
    private var dueCount: Int { ReviewView.due(cards, limit: limit).count }

    private var shown: [DictEntry] {
        var l = all
        switch filter {
        case "Words": break
        case "Lines": l = l.filter { $0.kind == "line" }
        case "Highlights": l = l.filter { $0.kind == "highlight" }
        default: break
        }
        if !search.isEmpty { l = l.filter { $0.term.localizedCaseInsensitiveContains(search) || $0.meaning.localizedCaseInsensitiveContains(search) || $0.reading.localizedCaseInsensitiveContains(search) } }
        if sort == "A to Z" { l.sort { ($0.reading.isEmpty ? $0.term : $0.reading).localizedCompare($1.reading.isEmpty ? $1.term : $1.reading) == .orderedAscending } }
        return l
    }

    private var shownCards: [Card] {
        cards.filter { search.isEmpty || $0.word.localizedCaseInsensitiveContains(search) || $0.sentence.localizedCaseInsensitiveContains(search) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var hasMixedCardLanguages: Bool { Set(shownCards.map(\.languageCode)).count > 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if filter != "Review" {
                    DictionarySearchField(text: $search, prompt: filter == "Cards" ? "Search cards" : "dictionary.search")
                        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
                }
                TextTabs(items: [("Words", "nav.words"), ("Cards", "nav.cards"), ("Lists", "nav.lists"), ("Review", "nav.review")], selection: $filter)
                if filter == "Lists" {
                    WordListsView(search: search)
                } else if filter == "Review" {
                    List { banner }.listStyle(.plain).scrollContentBackground(.hidden).padding(.top, 24)
                } else if filter == "Words" && all.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("dictionary.empty").font(Theme.Fonts.body.weight(.semibold))
                        Text("Save words while reading to build your dictionary.")
                            .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                        Button { app.tab = .read } label: {
                            Label("Open reading material", systemImage: "book")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).frame(minHeight: 48)
                                .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }.padding(.horizontal, 24).padding(.top, 24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if filter == "Words" && search.isEmpty && !showAllRecent {
                    recentWords
                } else {
                    List {
                        if (filter == "Cards" ? shownCards.isEmpty && !cards.isEmpty : shown.isEmpty) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(LocalizedStringKey(filter == "Cards" ? "dictionary.noMatchingCards" : "No words match your search.")).font(Theme.Fonts.body.weight(.semibold))
                                Button("Clear filters") { search = "" }
                                    .frame(minHeight: 44)
                            }.listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
                                .listRowBackground(Theme.background).listRowSeparator(.hidden)
                        }
                        if filter == "Cards" {
                            banner
                            if cards.isEmpty { Text("dictionary.cardsEmpty").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary).listRowBackground(Theme.background) }
                            ForEach(shownCards) { c in cardRow(c) }
                                .onDelete { i in
                                    let sorted = shownCards
                                    for k in i { ctx.delete(sorted[k]) }
                                }
                        } else {
                            ForEach(shown) { e in
                                Button { selected = e } label: { row(e) }
                                    .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
                                    .listRowBackground(Theme.background).listRowSeparator(.hidden)
                                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                            }.onDelete { i in for k in i { remove(shown[k]) } }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                    .padding(.top, 24)
                }
            }
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .background(Theme.background)
            .font(Theme.Fonts.body).foregroundStyle(Theme.ink)
            .navigationTitle("Dictionary").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { WordListsView() } label: { Image(systemName: "plus").font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel("Add word list")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { ImmersionView() } label: { Image(systemName: "chart.bar").font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel("nav.immersion")
                }
                if !all.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu { Picker("Sort", selection: $sort) { Text("dictionary.newest").tag("Newest"); Text("dictionary.alpha").tag("A to Z") } } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 20)).frame(width: 44, height: 44) }
                            .accessibilityLabel("Sort")
                    }
                }
            }
            .fullScreenCover(isPresented: $reviewing) { ReviewView() }
            .sheet(item: $selected) { EntryDetail(entry: $0).presentationDetents([.large]) }
        }
    }

    private var recentWords: some View {
        List {
            Section {
                HStack {
                    Text("Recent words").font(Theme.Fonts.body.weight(.semibold))
                    Spacer()
                    Button("See all") { showAllRecent = true }
                        .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 8, trailing: 24))
                .listRowSeparator(.hidden)
            }
            ForEach(Array(shown.prefix(8))) { e in
                Button { selected = e } label: { row(e) }
                    .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                    .listRowBackground(Theme.background).listRowSeparator(.hidden)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).padding(.top, 8)
    }
    private var banner: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    dueSummary
                    reviewButton
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        dueSummary.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 12)
                        reviewButton.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        dueSummary
                        reviewButton
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        .listRowBackground(Theme.background)
        .listRowSeparator(.hidden)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
    }

    private var dueSummary: some View {
        Text(dueCount == 0 ? L10n.string("review.noneDue") : L10n.format("review.due", Int64(dueCount)))
            .font(Theme.Fonts.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var reviewButton: some View {
        if dueCount > 0 {
            Button { reviewing = true } label: {
                Text("Start review").font(Theme.Fonts.body.weight(.semibold))
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
        }
    }
    private func cardRow(_ c: Card) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.sentence).font(Theme.Fonts.body.weight(.semibold))
            if c.word.trimmingCharacters(in: .whitespacesAndNewlines) != c.sentence.trimmingCharacters(in: .whitespacesAndNewlines) {
                Text(c.word).font(Theme.Fonts.body)
            }
            if !c.meaning.isEmpty { Text(c.meaning).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
            FlowLayout(lineSpacing: 8) {
                if c.audioFile != nil { Image(systemName: "speaker.wave.2").font(Theme.Fonts.meta).accessibilityLabel("Has audio") }
                if hasMixedCardLanguages { Text(Language.find(c.languageCode).displayName).font(Theme.Fonts.meta) }
            }.foregroundStyle(Theme.textSecondary)
            LabeledContent("Due", value: c.due.formatted(date: .abbreviated, time: .omitted))
                .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            if !c.sourceName.isEmpty {
                DisclosureGroup("Source") {
                    Text(cardSource(c)).foregroundStyle(Theme.textSecondary)
                }.font(Theme.Fonts.meta)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24)).listRowBackground(Theme.background).listRowSeparator(.hidden)
                                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
    }

    /// Older list cards stored an app-generated separator in their source snapshot.
    /// Material titles and other learner-authored source names stay verbatim.
    private func cardSource(_ card: Card) -> String {
        guard !card.wordListID.isEmpty,
              let separator = card.sourceName.range(of: " · ", options: .backwards) else { return card.sourceName }
        var source = card.sourceName
        source.replaceSubrange(separator, with: "\n")
        return source
    }

    private func remove(_ e: DictEntry) { if let c = e.modelContext { e.removeFromSource(c) } }

    private func row(_ e: DictEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if e.kind == "highlight" {
                Text(e.term).font(Theme.Fonts.body).foregroundStyle(Theme.ink).padding(.vertical, 4).background(Theme.highlight)
            } else {
                Text(e.term).font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.ink)
                if !e.reading.isEmpty { Text(e.reading).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                if !e.meaning.isEmpty { Text(e.meaning).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
            }
            if !e.note.isEmpty { Text(e.note).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
            FlowLayout(lineSpacing: 8) {
                Text(e.sourceName.isEmpty ? L10n.string("nav.coach") : e.sourceName)
                if e.sourceKind == "subtitle" { Text(Subtitles.stamp(e.sourcePos)) }
                if e.sourceKind == "pdf" { Text(L10n.format("Page %lld", Int64(e.sourcePos) + 1)) }
            }.font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct EntryDetail: View {
    @Bindable var entry: DictEntry
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var materials: [Material]
    @Query private var docs: [PDFDoc]
    @State private var confirm = false
    @State private var loading = false
    @State private var lookupTask: Task<Void, Never>?
    @State private var lookupError: String?

    private var sourceExists: Bool {
        switch entry.sourceKind {
        case "subtitle": materials.contains { $0.id.uuidString == entry.sourceID }
        case "pdf": docs.contains { $0.id.uuidString == entry.sourceID }
        default: false
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.term).font(Theme.Fonts.focus.weight(.semibold))
                            if !entry.reading.isEmpty { Text(entry.reading).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                        }
                    }
                    Section {
                        if entry.meaning.isEmpty {
                            Button(loading ? L10n.string("Loading…") : L10n.string("Look up meaning")) { lookup() }.disabled(loading)
                        } else { Text(entry.meaning) }
                        if let lookupError { Text(lookupError).foregroundStyle(Theme.errorText) }
                    } header: { Text("Meaning").font(Theme.Fonts.meta) }
                    if !entry.context.isEmpty && entry.context != entry.term {
                        Section {
                            Text(marked).font(Theme.Fonts.body)
                        } header: { Text("dictionary.context").font(Theme.Fonts.meta) }
                    }
                    Section {
                        TextField("common.note", text: $entry.note, axis: .vertical)
                    } header: { Text("Your note").font(Theme.Fonts.meta) }
                    Section {
                        DisclosureGroup("Source") {
                            if entry.sourceKind == "coach" || entry.sourceName.isEmpty { Text("nav.coach") }
                            else if sourceExists {
                                Button { dismiss(); app.goToSource(entry) } label: { Label("Go to source", systemImage: "arrow.up.right.square") }
                                Text(entry.sourceName).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                            } else { Text("dictionary.sourceMissing").foregroundStyle(Theme.textSecondary) }
                        }
                    }
                    Section { Button("dictionary.deleteWord", role: .destructive) { confirm = true }.foregroundStyle(Theme.errorText) }
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
                .listRowBackground(Theme.background)
                .listRowSeparator(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Ask Coach", systemImage: "bubble.left") { dismiss(); app.askCoach("Tell me more about \"\(entry.term)\" and give me an example.", context: entry.sourceName, languageCode: entry.languageCode) }
                    .buttonStyle(InkButtonStyle())
                    .frame(maxWidth: 672).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(maxWidth: .infinity).background(Theme.background)
            }
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .textCase(nil)
            .listStyle(.plain).scrollContentBackground(.hidden).background(Theme.background)
            .environment(\.defaultMinListRowHeight, 48)
            .listRowSpacing(0).listSectionSpacing(24)
            .font(Theme.Fonts.body).foregroundStyle(Theme.ink)
            .navigationTitle("Dictionary").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
            .confirmationDialog("dictionary.deleteTitle", isPresented: $confirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { entry.removeFromSource(ctx); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .task { if entry.meaning.isEmpty && entry.kind != "note" && entry.term.count < 30 { lookup() } }
        .onDisappear { lookupTask?.cancel() }
    }

    private var marked: AttributedString {
        var a = AttributedString("“" + entry.context + "”")
        var surface = entry.term
        if entry.languageCode == "en", !entry.term.isEmpty,
           let match = entry.context.range(of: entry.term, options: .caseInsensitive) {
            entry.context.enumerateSubstrings(in: entry.context.startIndex..<entry.context.endIndex, options: .byWords) { token, range, _, stop in
                if range.overlaps(match), let token { surface = token; stop = true }
            }
        }
        if !surface.isEmpty, let r = a.range(of: surface, options: .caseInsensitive) {
            a[r].backgroundColor = UIColor(Theme.highlight)
            a[r].underlineStyle = .single
            a[r].font = Theme.Fonts.body.weight(.semibold)
        }
        return a
    }

    private func lookup() {
        lookupTask?.cancel(); loading = true; lookupError = nil
        let generation = Operations.shared.generation
        lookupTask = Task {
            defer { if !Task.isCancelled { loading = false } }
            do {
                let result = try await Words.lookup(entry.term, sentence: entry.context, languageCode: entry.languageCode)
                try Operations.shared.checkpoint(generation)
                guard !entry.isDeleted, entry.modelContext != nil else { return }
                let old = entry.meaning
                entry.meaning = result.meaning
                do { try ctx.save() } catch { entry.meaning = old; throw error }
            } catch {
                if !Task.isCancelled, !(error is CancellationError) { lookupError = error.localizedDescription }
            }
        }
    }
}

enum PDFDocumentCache {
    static func open(_ d: PDFDoc) -> PDFDocument? { PDFDocument(url: Files.url(d.fileName)) }
}

extension DictEntry {
    /// Deletes the entry and removes the highlight it left on its source.
    func removeFromSource(_ ctx: ModelContext) {
        if kind == "highlight" {
            if sourceKind == "subtitle", let m = (try? ctx.fetch(FetchDescriptor<Material>()))?.first(where: { $0.id.uuidString == sourceID }) {
                var ls = m.lines
                if let i = ls.firstIndex(where: { abs($0.start - sourcePos) < 0.01 }) { ls[i].hl = nil; m.lines = ls }
            } else if sourceKind == "pdf", let d = (try? ctx.fetch(FetchDescriptor<PDFDoc>()))?.first(where: { $0.id.uuidString == sourceID }),
                      let pdf = PDFDocument(url: Files.url(d.fileName)), let page = pdf.page(at: Int(sourcePos)) {
                for a in page.annotations where a.type == "Highlight" && rects.contains(where: { $0.count >= 2 && abs($0[0] - a.bounds.minX) < 0.5 && abs($0[1] - a.bounds.minY) < 0.5 }) { page.removeAnnotation(a) }
                pdf.write(to: Files.url(d.fileName))
            }
        }
        ctx.delete(self)
    }
}

/// A search control in the content grid, independent of native navigation-bar sizing.
struct DictionarySearchField: View {
    @Binding var text: String
    var prompt: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 20))
                .foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.textSecondary))
                .font(Theme.Fonts.body).foregroundStyle(Theme.ink).padding(.vertical, 12)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel(Text(prompt))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 20)).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Clear filters")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8))
    }
}
