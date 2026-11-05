import SwiftUI
import SwiftData

struct DictionaryHit: Identifiable {
    var id: String
    var term: String
    var reading: String
    var meaning: String
    var context: String
    var language: String
    var source: String
}

@MainActor enum QuickDictionary {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func search(_ query: String, language: String, saved: [DictEntry], documents: [WordListDocument]) -> [DictionaryHit] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        var hits: [DictionaryHit] = [], seen = Set<String>()
        for entry in saved where entry.languageCode == language && entry.kind == "word" {
            guard [entry.term, entry.reading, entry.meaning].contains(where: { normalized($0).contains(needle) }) else { continue }
            let identity = normalized(entry.term)
            if seen.insert(identity).inserted {
                hits.append(.init(id: entry.id.uuidString, term: entry.term, reading: entry.reading, meaning: entry.meaning, context: entry.context, language: language, source: L10n.string("Saved words")))
            }
        }
        for document in documents where document.language == language {
            for word in document.entries {
                guard [word.w, word.reading, word.meaning].contains(where: { normalized($0).contains(needle) }) else { continue }
                if seen.insert(normalized(word.w)).inserted {
                    hits.append(.init(id: document.id + ":" + word.id, term: word.w, reading: word.reading, meaning: word.meaning, context: word.ex.first?.en ?? "", language: language, source: document.title))
                }
                if hits.count >= 60 { break }
            }
        }
        return Array(hits.sorted { left, right in
            let l = normalized(left.term) == needle, r = normalized(right.term) == needle
            return l != r ? l : left.term.localizedStandardCompare(right.term) == .orderedAscending
        }.prefix(40))
    }
    static func save(_ hit: DictionaryHit, context: ModelContext, autoCard: Bool = true) throws {
        try Operations.shared.checkpoint(Operations.shared.generation)
        let language = hit.language
        let existing = try context.fetch(FetchDescriptor<DictEntry>(predicate: #Predicate { $0.languageCode == language && $0.kind == "word" }))
        guard !existing.contains(where: { normalized($0.term) == normalized(hit.term) }) else { return }
        let entry = DictEntry(term: hit.term, kind: "word", sourceKind: "lookup")
        entry.languageCode = language; entry.reading = hit.reading; entry.meaning = hit.meaning
        entry.context = hit.context; entry.sourceName = hit.source
        context.insert(entry)
        var card: Card?
        do {
            if autoCard { card = try DailyStudy.addSaved(entry, context: context) }
            try context.save()
        } catch { if let card { context.delete(card) }; context.delete(entry); throw error }
    }
}

/// Shared by the dictionary, text Coach and live captions; only Save writes data.
struct QuickDictionaryView: View {
    var initialQuery = ""
    var sentence = ""
    var initialLanguage: String? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var saved: [DictEntry]
    @State private var query = ""
    @State private var language = "ja"
    @State private var library = WordListLibrary.shared
    @State private var result: DictionaryHit?
    @State private var busy = false
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    @State private var showingSettings = false
    @AppStorage("study.autoCards") private var autoCards = true
    private var hits: [DictionaryHit] { QuickDictionary.search(query, language: language, saved: saved, documents: library.documents) }
    private var otherHits: [DictionaryHit] { hits.filter { QuickDictionary.normalized($0.term) != result.map { QuickDictionary.normalized($0.term) } } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Word or phrase", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityIdentifier("lookup.query").submitLabel(.search).onSubmit { lookup() }
                    Picker("Language", selection: $language) { Text("Japanese").tag("ja"); Text("English").tag("en") }
                    Button { lookup() } label: {
                        HStack { Label("Look up meaning", systemImage: "magnifyingglass"); Spacer(); if busy { ProgressView() } }
                    }.buttonStyle(TextActionStyle()).disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("lookup.search")
                }.listRowBackground(Theme.surface)
                if !sentence.isEmpty {
                    Section {
                        TappableText(text: sentence, language: language, furigana: false) { word in query = word }
                    } header: { Text("Tap a word to look it up") }.listRowBackground(Theme.surface)
                }
                if let result { Section { hitRow(result) } header: { Text("Definition") }.listRowBackground(Theme.surface) }
                if let failure {
                    Section {
                        Text(failure).foregroundStyle(Theme.errorText)
                        Button("AI service settings") { showingSettings = true }.buttonStyle(TextActionStyle())
                    }.listRowBackground(Theme.surface)
                }
                if !otherHits.isEmpty {
                    Section { ForEach(otherHits) { hit in hitRow(hit) } } header: { Text("Saved words & word lists") }.listRowBackground(Theme.surface)
                } else if !query.isEmpty && !busy && result == nil {
                    Section { Text("No local match. Look up this word with your configured AI service.").foregroundStyle(Theme.textSecondary) }.listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.groupedBackground).foregroundStyle(Theme.ink).tint(Theme.accent)
            .navigationTitle("Look up a word").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { query = initialQuery; language = initialLanguage ?? Prefs.target.code; await library.load() }
            .onChange(of: query) { _, _ in cancel() }
            .onChange(of: language) { _, _ in cancel() }
            .onDisappear { task?.cancel() }
            .sheet(isPresented: $showingSettings) { NavigationStack { AISettingsView() } }
        }
    }
    private func hitRow(_ hit: DictionaryHit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: hit.term).literary(.title2, bold: true, .original).textSelection(.enabled)
            if !hit.reading.isEmpty { Text(verbatim: hit.reading).foregroundStyle(Theme.textSecondary) }
            Text(verbatim: hit.meaning).textSelection(.enabled)
            Text(verbatim: hit.source).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            let exists = saved.contains { $0.kind == "word" && $0.languageCode == hit.language && QuickDictionary.normalized($0.term) == QuickDictionary.normalized(hit.term) }
            Button(exists ? "In dictionary" : (autoCards ? "study.saveAndReview" : "Add to dictionary"), systemImage: exists ? "checkmark" : "plus") {
                do { try QuickDictionary.save(hit, context: context, autoCard: autoCards) } catch { failure = error.localizedDescription }
            }.buttonStyle(PaperActionStyle()).disabled(exists).accessibilityIdentifier("lookup.save.\(hit.term)")
        }.padding(.vertical, 8)
    }
    private func cancel() { task?.cancel(); task = nil; busy = false; result = nil; failure = nil }
    private func lookup() {
        cancel()
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines), language = language
        guard !word.isEmpty else { return }
        guard word.count <= 200 else { failure = L10n.string("Enter a word or a short phrase (up to 200 characters)."); return }
        if let exact = hits.first(where: { QuickDictionary.normalized($0.term) == QuickDictionary.normalized(word) }) { result = exact; return }
        busy = true
        let generation = Operations.shared.generation
        task = Task {
            defer { if !Task.isCancelled { busy = false } }
            do {
                let entry = try await Words.lookup(word, sentence: sentence.isEmpty ? word : sentence, languageCode: language)
                try Operations.shared.checkpoint(generation)
                result = .init(id: UUID().uuidString, term: word, reading: language == "ja" ? Words.reading(word) ?? "" : "", meaning: entry.meaning, context: sentence, language: language, source: L10n.string("AI definition"))
            } catch { if !Task.isCancelled, !(error is CancellationError) { failure = error.localizedDescription } }
        }
    }
}
