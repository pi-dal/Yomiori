import SwiftUI
import SwiftData
import PDFKit

struct DictionaryView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Environment(\.studyDefaults) private var defaults
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \DictEntry.createdAt, order: .reverse) private var all: [DictEntry]
    @State private var search = ""
    @State private var deleteError: String?
    @State private var showingLookup = false
    @State private var filter = "Words"
    @State private var sort = "Newest"
    @State private var selected: DictEntry?
    @Query private var cards: [Card]
    @AppStorage("reviewLimit") private var limit = 30
    @AppStorage("study.newLimit") private var newLimit = 5
    @State private var reviewing = false
    @State private var showAllRecent = false
    private var dueCount: Int { DailyStudy.plan(cards, defaults: defaults).queue.count }

    private var shown: [DictEntry] {
        var l = all
        switch filter {
        case "Words": break
        case "Lines": l = l.filter { $0.kind == "line" }
        case "Highlights": l = l.filter { $0.kind == "highlight" }
        default: break
        }
        if !search.isEmpty { l = l.filter { $0.term.localizedCaseInsensitiveContains(search) || $0.meaning.localizedCaseInsensitiveContains(search) || $0.reading.localizedCaseInsensitiveContains(search) || $0.note.localizedCaseInsensitiveContains(search) } }
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
                DictionarySearchField(text: $search, prompt: filter == "Cards" ? "Search cards" : "dictionary.search")
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 8)
                if filter == "Words" {
                    Button {
                        showingLookup = true
                    } label: {
                        Label(search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Look up a word" : "Look up this word", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.padding(.horizontal, 24).accessibilityIdentifier("dictionary.lookup")
                }
                // Review lives in Today; the Cards banner is its in-place shortcut.
                TextTabs(items: [("Words", "nav.words"), ("Cards", "nav.cards"), ("Lists", "nav.lists")], selection: $filter)
                if filter == "Lists" {
                    WordListsView(search: search)
                } else if filter == "Words" && all.isEmpty {
                    EmptyState(symbol: "character.book.closed", title: "dictionary.empty",
                               message: "Save words while reading to build your dictionary.",
                               action: ("Open reading material", { app.tab = .read }))
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
                                    .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                                    .listRowBackground(Theme.background).listRowSeparator(.visible, edges: .bottom)
                                    .listRowSeparator(.hidden, edges: .top)
                                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                            }.onDelete { i in for entry in i.map({ shown[$0] }) { remove(entry) } }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .background(Theme.background)
            .font(Theme.Fonts.body).foregroundStyle(Theme.ink)
            .navigationTitle("Dictionary").navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Lists bring their own import action; Words offer only ordering, as Read does.
                if filter == "Words" && !all.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort", selection: $sort) {
                                Text("dictionary.newest").tag("Newest")
                                Text("dictionary.alpha").tag("A to Z")
                            }
                        } label: { Image(systemName: "arrow.up.arrow.down") }
                            .accessibilityLabel("Dictionary options")
                    }.sharedBackgroundVisibility(.hidden)
                }
            }
            .fullScreenCover(isPresented: $reviewing) { ReviewView() }
            .sheet(isPresented: $showingLookup) { QuickDictionaryView(initialQuery: search) }
            .alert("Couldn't save", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) { Button("OK") {} } message: { Text(deleteError ?? "") }
            .sheet(item: $selected) { EntryDetail(entry: $0).presentationDetents([.large]) }
        }
    }

    private var recentWords: some View {
        List {
            ForEach(Array(shown.prefix(8))) { e in
                Button { selected = e } label: { row(e) }
                    .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                    .listRowBackground(Theme.background).listRowSeparator(.visible, edges: .bottom)
                    .listRowSeparator(.hidden, edges: .top)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
            if shown.count > 8 {
                Button("See all") { showAllRecent = true }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 8, trailing: 24))
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
                Label("Start review", systemImage: "play.fill")
            }.buttonStyle(CompactActionStyle())
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

    private func remove(_ entry: DictEntry) {
        do { try entry.removeFromSource(ctx) }
        catch { deleteError = error.localizedDescription }
    }

    private func row(_ e: DictEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if e.kind == "highlight" {
                Text(e.term).font(Theme.Fonts.body).foregroundStyle(Theme.ink).padding(.vertical, 4).background(Theme.highlight)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(e.term).literary(.title2, bold: true, .original).foregroundStyle(Theme.ink)
                        if !e.reading.isEmpty { Text(e.reading).font(.caption).foregroundStyle(Theme.textSecondary) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.term).literary(.title2, bold: true, .original).foregroundStyle(Theme.ink)
                        if !e.reading.isEmpty { Text(e.reading).font(.caption).foregroundStyle(Theme.textSecondary) }
                    }
                }
                if !e.meaning.isEmpty { Text(e.meaning).font(.subheadline).foregroundStyle(Theme.ink) }
            }
            if !e.note.isEmpty { Text(e.note).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
            HStack(spacing: 8) {
                Text(e.sourceName.isEmpty ? L10n.string("nav.coach") : e.sourceName).lineLimit(1)
                if e.sourceKind == "subtitle" && e.sourcePos > 0 { Text(Subtitles.stamp(e.sourcePos)).monospacedDigit() }
                if e.sourceKind == "pdf" { Text(L10n.format("Page %lld", Int64(e.sourcePos) + 1)) }
            }.font(.caption2).foregroundStyle(Theme.textSecondary)
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
                            Text(entry.term).literary(.title1, bold: true, .original)
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
                            if entry.sourceKind == "lookup" { Text(verbatim: entry.sourceName) }
                            else if entry.sourceKind == "coach" || entry.sourceName.isEmpty { Text("nav.coach") }
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
                Button("Delete", role: .destructive) { do { try entry.removeFromSource(ctx); dismiss() } catch { lookupError = error.localizedDescription } }
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

extension DictEntry {
    @MainActor func removeFromSource(_ ctx: ModelContext, openDocument: PDFDocument? = nil) throws {
        if kind == "highlight", let id = UUID(uuidString: sourceID) {
            if sourceKind == "pdf", let doc = try ctx.fetch(FetchDescriptor<PDFDoc>(predicate: #Predicate { $0.id == id })).first {
                try PDFMarks.remove(self, from: doc, openDocument: openDocument, context: ctx)
                return
            }
            if sourceKind == "subtitle", let material = try ctx.fetch(FetchDescriptor<Material>(predicate: #Predicate { $0.id == id })).first {
                var lines = try material.readLines()
                if let index = lines.firstIndex(where: { abs($0.start - sourcePos) < 0.01 }) {
                    lines[index].hl = nil
                    try material.writeLines(lines)
                }
            }
        }
        ctx.delete(self)
        do { try ctx.save() } catch { ctx.rollback(); throw error }
    }
}

/// A search control in the content grid, independent of native navigation-bar sizing.
struct DictionarySearchField: View {
    @Binding var text: String
    var prompt: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.subheadline)
                .foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.textSecondary))
                .font(.subheadline).foregroundStyle(Theme.ink).padding(.vertical, 10)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel(Text(prompt))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.subheadline).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Clear filters")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 10))
    }
}
