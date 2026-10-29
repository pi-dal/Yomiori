import SwiftUI
import SwiftData
import AVFoundation
import CryptoKit

@MainActor @Observable
final class WordAtlasStore {
    static let shared = WordAtlasStore()
    private(set) var words: [AtlasWord] = []
    private(set) var levels: [String] = []
    private(set) var topics: [String] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var document: WordListDocument?
    init(document: WordListDocument? = nil) { if let document { install(document) } }
    private func install(_ document: WordListDocument) {
        self.document = document
        words = document.entries
        levels = Array(Set(words.map(\.cefr).filter { !$0.isEmpty })).sorted()
        topics = Array(Set(words.map(\.topic))).sorted()
        searchIndex = Dictionary(uniqueKeysWithValues: words.map { word in
            (word.id, ([word.w, word.id, word.topic, word.cefr] + word.senses.flatMap { [$0.en, $0.zh] })
                .joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
        })
    }
    private var searchIndex: [String: String] = [:]

    func load() async {
        guard words.isEmpty, !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        guard let url = Bundle.main.url(forResource: "word-atlas", withExtension: "json") else {
            error = L10n.string("The offline word list is missing from this installation.")
            return
        }
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try WordListDocument.decodeValidated(Data(contentsOf: url))
            }.value
            install(document)
        } catch {
            self.error = L10n.string("The offline word list could not be opened. Please try again.")
        }
    }

    func filtered(search: String, level: String, topic: String) -> [AtlasWord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return words.filter {
            (level.isEmpty || $0.cefr == level) && (topic.isEmpty || $0.topic == topic)
                && (query.isEmpty || searchIndex[$0.id, default: ""].contains(query))
        }
    }
}

@MainActor
enum IELTSCardWriter {
    static func savedIDs(_ cards: [Card], listID: String = "ielts") -> Set<String> {
        Set(cards.filter { $0.wordListID == listID }.map(\.wordListEntryID))
    }

    @discardableResult
    static func add(_ words: [AtlasWord], context: ModelContext, document: WordListDocument? = nil) throws -> Int {
        // Fetch again at insertion time: filtered rows or a confirmation may be stale.
        var saved = savedIDs(try context.fetch(FetchDescriptor<Card>()), listID: document?.id ?? "ielts")
        var inserted: [Card] = []
        for word in words where !saved.contains(word.id) {
            let card = Card(sentence: word.ex.first?.en ?? word.w, word: word.w)
            card.reading = word.reading
            card.meaning = word.meaning
            if document?.language == "ja" { card.definitionJa = word.senses.map(\.en).joined(separator: "\n") }
            else { card.definitionEnglish = word.senses.map(\.en).joined(separator: "\n") }
            card.translation = word.ex.first?.zh ?? ""
            card.languageCode = document?.language ?? "en"
            card.wordListID = document?.id ?? "ielts"
            card.wordListEntryID = word.id
            card.sourceID = ""
            card.sourceName = "\(document?.title ?? "IELTS"), \(document?.source.name ?? "Word Atlas")"
            card.audioRemoteURL = word.ex.isEmpty ? "" : word.exampleAudioURL?.absoluteString ?? ""
            context.insert(card)
            inserted.append(card)
            saved.insert(word.id)
        }
        do { try context.save() }
        catch {
            for card in inserted { context.delete(card) }
            throw error
        }
        return inserted.count
    }
}

/// Presented inside Dictionary's existing navigation container.
struct WordListsView: View {
    var search = ""
    @Query private var cards: [Card]
    @State private var library = WordListLibrary.shared
    @State private var importing = false
    @State private var selected: WordListDocument?
    var body: some View {
        List {
            Section {
                ForEach(library.documents.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || Language.find($0.language).displayName.localizedCaseInsensitiveContains(search) }) { document in
                    NavigationLink { IELTSWordListView(document: document) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: document.title).font(Theme.Fonts.body.weight(.semibold))
                            Text(Language.find(document.language).displayName).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                            Text(L10n.format("lists.count", Int64(document.entries.count))).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        }.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    }.wordListRows()
                }
            }
            if !search.isEmpty && !library.documents.contains(where: { $0.title.localizedCaseInsensitiveContains(search) || Language.find($0.language).displayName.localizedCaseInsensitiveContains(search) }) {
                Text("lists.noMatchingLists").wordListRows()
            }
            Section {
                if let example = Bundle.main.url(forResource: "word-list-example", withExtension: "json") {
                    ShareLink(item: example) { Label { Text(L10n.string("Example word list")) } icon: { Image(systemName: "square.and.arrow.up").font(.system(size: 20)).frame(width: 24, height: 24) } }
                }
            }.wordListRows()
            if let error = library.error {
                Section {
                    Text(L10n.string("Couldn't read this file.")).foregroundStyle(Theme.errorText)
                    DisclosureGroup(L10n.string("Details")) {
                        Text(verbatim: error).font(Theme.Fonts.meta).textSelection(.enabled)
                    }
                }.wordListRows()
            }
            if let builtin = library.documents.first(where: { $0.id == "ielts" }) {
                Section { WordListSourceView(source: builtin.source) }.wordListRows()
            }
        }
        .environment(\.defaultMinListRowHeight, 48).listStyle(.plain).listSectionSpacing(24).scrollContentBackground(.hidden).background(Theme.background).foregroundStyle(Theme.ink).font(Theme.Fonts.body)
        .frame(maxWidth: 720).frame(maxWidth: .infinity).background(Theme.background)
        .padding(.top, 24)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { importing = true } label: { Image(systemName: "plus").font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel("Import word list") } }
        .sheet(isPresented: $importing) { WordListImportView { document in selected = document } }
        .navigationDestination(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { if let selected { IELTSWordListView(document: selected) } }
        .task {
            await library.load()
            #if DEBUG
            // Expose the generated fixture through the native Files picker for manual import QA.
            if let example = Bundle.main.url(forResource: "word-list-example", withExtension: "json") {
                let destination = URL.documentsDirectory.appendingPathComponent("study-starter.json")
                if !FileManager.default.fileExists(atPath: destination.path) { try? FileManager.default.copyItem(at: example, to: destination) }
                if let data = try? Data(contentsOf: example), var fixture = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    fixture["unsupportedKey"] = true
                    if let invalid = try? JSONSerialization.data(withJSONObject: fixture) {
                        try? invalid.write(to: URL.documentsDirectory.appendingPathComponent("study-invalid.json"), options: .atomic)
                    }
                    fixture.removeValue(forKey: "unsupportedKey")
                    if var entries = fixture["entries"] as? [[String: Any]], !entries.isEmpty {
                        entries[0]["note"] = "A refreshed word-list note."
                        fixture["entries"] = entries
                        if let update = try? JSONSerialization.data(withJSONObject: fixture) {
                            try? update.write(to: URL.documentsDirectory.appendingPathComponent("study-update.json"), options: .atomic)
                        }
                    }
                }
            }
            #endif
        }
    }
}

struct IELTSWordListView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [Card]
    @State private var store: WordAtlasStore
    init(document: WordListDocument? = nil) { _store = State(initialValue: document.map { WordAtlasStore(document: $0) } ?? WordAtlasStore.shared) }
    private var listID: String { store.document?.id ?? "ielts" }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var search = ""
    @State private var level = ""
    @State private var topic = ""
    @State private var shown: [AtlasWord] = []
    @State private var pending: [AtlasWord] = []
    @State private var confirmBulk = false
    @State private var saveError: String?
    @State private var notice: String?
    private var saved: Set<String> { IELTSCardWriter.savedIDs(cards, listID: listID) }
    private var savedCount: Int { saved.intersection(Set(store.words.map(\.id))).count }
    private var newWords: [AtlasWord] { let ids = saved; return Array(shown.lazy.filter { !ids.contains($0.id) }.prefix(20)) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Language.find(store.document?.language ?? "en").displayName).font(Theme.Fonts.meta)
                    Text(L10n.format("lists.progress", Int64(savedCount), Int64(store.words.count))).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    ProgressView(value: Double(savedCount), total: Double(max(store.words.count, 1))).tint(Theme.ink)
                        .accessibilityLabel("Words in your Cards")
                        .accessibilityValue(L10n.format("lists.progress", Int64(savedCount), Int64(store.words.count)))
                }
                if let document = store.document { WordListSourceView(source: document.source) }
                DictionarySearchField(text: $search, prompt: "Search this list")
                    .padding(.vertical, 8)
                let filterLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                filterLayout {
                    Menu {
                        Picker("Level", selection: $level) {
                            Text("All levels").tag("")
                            ForEach(store.levels, id: \.self) { Text(WordListMetadata.level($0)).tag($0) }
                        }
                    } label: { Label { Text(level.isEmpty ? L10n.string("All levels") : WordListMetadata.level(level)) } icon: { Image(systemName: "line.3.horizontal.decrease").font(.system(size: 20)).frame(width: 24, height: 24) } }
                    .accessibilityLabel(L10n.string("Level"))
                    Menu {
                        Picker("Topic", selection: $topic) {
                            Text("All topics").tag("")
                            ForEach(store.topics, id: \.self) { Text(WordListMetadata.topic($0)).tag($0) }
                        }
                    } label: { Label { Text(topic.isEmpty ? L10n.string("All topics") : WordListMetadata.topic(topic)) } icon: { Image(systemName: "tag").font(.system(size: 20)).frame(width: 24, height: 24) } }
                    .accessibilityLabel(L10n.string("Topic"))
                }.font(Theme.Fonts.body).frame(minHeight: 44)
                if let notice { Text(notice).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.updatesFrequently) }
            }.wordListRows()
            if store.loading {
                Section { ProgressView("Loading…") }.wordListRows()
            } else if let error = store.error {
                Section {
                    Text(error)
                    Button("Try again") { Task { await store.load(); refresh() } }
                }.wordListRows()
            } else if shown.isEmpty {
                Section {
                    Text("No words match your search.").foregroundStyle(Theme.textSecondary)
                    if !search.isEmpty || !level.isEmpty || !topic.isEmpty { Button("Clear filters") { search = ""; level = ""; topic = "" } }
                }
                    .wordListRows()
            } else {
                Section {
                    ForEach(shown) { word in
                        IELTSWordRow(word: word, document: store.document, saved: saved.contains(word.id)) { add([word]) }
                            .wordListRows()
                    }
                } header: {
                    Text(L10n.format("lists.count", Int64(shown.count)))
                        .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        .textCase(nil)
                        .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24))
                }
            }
        }
        .environment(\.defaultMinListRowHeight, 48).listStyle(.plain).listSectionSpacing(24).scrollContentBackground(.hidden).background(Theme.background)
        .frame(maxWidth: 720).frame(maxWidth: .infinity).background(Theme.background)
        .foregroundStyle(Theme.ink).font(Theme.Fonts.body).tint(Theme.ink)
        .navigationTitle(store.document?.title ?? "IELTS").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(newWords.isEmpty ? L10n.string("No new words") : L10n.format("lists.batch", Int64(newWords.count))) {
                pending = newWords; confirmBulk = true
            }.buttonStyle(InkButtonStyle()).disabled(newWords.isEmpty)
                .frame(maxWidth: 672).padding(.horizontal, 24).padding(.vertical, 16)
                .frame(maxWidth: .infinity).background(Theme.background)
        }
        .task { await store.load(); refresh() }
        .onChange(of: store.words.count) { _, _ in refresh() }
        .onChange(of: search) { _, _ in refresh() }
        .onChange(of: level) { _, _ in refresh() }
        .onChange(of: topic) { _, _ in refresh() }
        .confirmationDialog(L10n.format("lists.batchTitle", Int64(pending.count)), isPresented: $confirmBulk, titleVisibility: .visible) {
            Button(L10n.format("lists.batch", Int64(pending.count))) { add(pending); pending = [] }
            Button("Cancel", role: .cancel) { pending = [] }
        }
        .alert("Could not save Cards", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private func refresh() { shown = store.filtered(search: search, level: level, topic: topic) }
    private func add(_ words: [AtlasWord]) {
        do {
            let count = try IELTSCardWriter.add(words, context: context, document: store.document)
            notice = L10n.format("lists.saved", Int64(count))
        } catch { saveError = L10n.string("Your words could not be saved. Please try again.") }
    }
}

private struct IELTSWordRow: View {
    let word: AtlasWord
    let document: WordListDocument?
    let saved: Bool
    let add: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            NavigationLink { AtlasWordDetailView(word: word, document: document) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: word.w).font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    if !word.reading.isEmpty { Text(verbatim: word.reading).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                    Text(word.meaning.isEmpty ? word.senses.map(\.en).joined(separator: "; ") : word.meaning).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                }
            }
            Button(L10n.string(saved ? "In Cards" : "Add to Cards"), action: add)
                .font(Theme.Fonts.body.weight(.semibold)).frame(minHeight: 44).buttonStyle(.borderless).disabled(saved)
                .accessibilityLabel(Text(verbatim: word.w)).accessibilityValue(L10n.string(saved ? "In Cards" : "Add to Cards"))
        }.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}

struct AtlasWordDetailView: View {
    let word: AtlasWord
    var document: WordListDocument? = nil
    private var listID: String { document?.id ?? "ielts" }
    @Environment(\.modelContext) private var context
    @Query private var cards: [Card]
    @State private var audio = AtlasPronunciationPlayer()
    @State private var showPicture = false
    @State private var pictureAttempt = 0
    @State private var saveError = false
    private var saved: Bool { IELTSCardWriter.savedIDs(cards, listID: listID).contains(word.id) }

    private var usageTexts: [String] {
        [word.tip, word.note ?? ""].reduce(into: []) { texts, value in
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty && !texts.contains(text) { texts.append(text) }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: word.w).font(Theme.Fonts.focus.weight(.semibold))
                    if !word.reading.isEmpty { Text(verbatim: word.reading).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                    if !word.uk.isEmpty { Text(L10n.format("UK %@", word.uk)).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                    if !word.us.isEmpty { Text(L10n.format("US %@", word.us)).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                }
                if let pronunciationURL = word.pronunciationURL {
                Button {
                    if audio.playing { audio.stop() } else { audio.play(pronunciationURL) }
                } label: {
                    Label { Text(L10n.string(audio.playing ? "Stop pronunciation" : "Play pronunciation")) } icon: { Image(systemName: audio.playing ? "stop.fill" : "speaker.wave.2").font(.system(size: 20)).frame(width: 24, height: 24) }
                }.disabled(audio.loading)
                }
                if audio.loading { ProgressView("Loading…") }
                if audio.error != nil {
                    Text(L10n.string("Couldn't load audio")).font(Theme.Fonts.meta).foregroundStyle(Theme.errorText)
                }
            }.wordListRows()
            Section("Meanings") {
                ForEach(Array(word.senses.enumerated()), id: \.offset) { _, sense in
                    VStack(alignment: .leading, spacing: 8) {
                        if !sense.pos.isEmpty { Text(WordListMetadata.partOfSpeech(sense.pos)).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                        if !sense.zh.isEmpty { Text(verbatim: sense.zh) }
                        if !sense.en.isEmpty && sense.en.trimmingCharacters(in: .whitespacesAndNewlines) != sense.zh.trimmingCharacters(in: .whitespacesAndNewlines) {
                            Text(verbatim: sense.en).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }.wordListRows()
            if !word.ex.isEmpty {
                Section("Examples") {
                    ForEach(Array(word.ex.enumerated()), id: \.offset) { _, example in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(markedExample(example.en))
                            if !example.zh.isEmpty && example.zh.trimmingCharacters(in: .whitespacesAndNewlines) != example.en.trimmingCharacters(in: .whitespacesAndNewlines) {
                                Text(verbatim: example.zh).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }.wordListRows()
            }
            wordSection("Collocations", values: word.col)
            wordSection("Word family", values: word.fam)
            wordSection("Synonyms", values: word.syn)
            wordSection("Antonyms", values: word.ant)
            if !usageTexts.isEmpty {
                Section("Usage") {
                    ForEach(usageTexts, id: \.self) { Text(verbatim: $0) }
                }.wordListRows()
            }
            if let pictureURL = word.pictureURL {
            Section("Picture") {
                if showPicture {
                    AsyncImage(url: pictureURL) { phase in
                        switch phase {
                        case .empty: ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 120)
                        case .success(let image): image.resizable().scaledToFit().accessibilityLabel(L10n.format("Illustration of %@", word.w))
                        case .failure:
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Couldn't load picture").foregroundStyle(Theme.textSecondary)
                                Button("Try again") { pictureAttempt += 1 }
                            }
                        @unknown default: Text("Couldn't load picture")
                        }
                    }.id(pictureAttempt)
                } else { Button("Load picture") { showPicture = true } }
            }.wordListRows()
            }
            Section {
                DisclosureGroup(L10n.string("Details")) {
                    LabeledContent(L10n.string("Language"), value: Language.find(document?.language ?? "en").displayName)
                    if !word.cefr.isEmpty { LabeledContent(L10n.string("Level"), value: WordListMetadata.level(word.cefr)) }
                    if !word.topic.isEmpty { LabeledContent(L10n.string("Topic"), value: WordListMetadata.topic(word.topic)) }
                }
                if let document { WordListSourceView(source: document.source) }
            }.wordListRows()
        }
        .environment(\.defaultMinListRowHeight, 48).listStyle(.plain).listSectionSpacing(24).scrollContentBackground(.hidden).background(Theme.background)
        .frame(maxWidth: 720).frame(maxWidth: .infinity).background(Theme.background)
        .foregroundStyle(Theme.ink).font(Theme.Fonts.body).tint(Theme.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(L10n.string(saved ? "In Cards" : "Add to Cards")) {
                do { try IELTSCardWriter.add([word], context: context, document: document) }
                catch { saveError = true }
            }.buttonStyle(InkButtonStyle()).disabled(saved)
                .frame(maxWidth: 672).padding(.horizontal, 24).padding(.vertical, 16)
                .frame(maxWidth: .infinity).background(Theme.background)
                .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .onDisappear { audio.stop() }
        .alert("Could not save Cards", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: { Text("Your word could not be saved. Please try again.") }
    }

    private func markedExample(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        var surface = word.w
        if (document?.language ?? "en") == "en", !word.w.isEmpty,
           let match = text.range(of: word.w, options: .caseInsensitive) {
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { token, range, _, stop in
                if range.overlaps(match), let token { surface = token; stop = true }
            }
        }
        if !surface.isEmpty, let range = result.range(of: surface, options: .caseInsensitive) {
            result[range].backgroundColor = UIColor(Theme.highlight)
            result[range].foregroundColor = UIColor(Theme.ink)
            result[range].underlineStyle = .single
        }
        return result
    }

    @ViewBuilder private func wordSection(_ title: String, values: [String]) -> some View {
        if !values.isEmpty {
            Section { Text(values.joined(separator: "\n")) } header: { Text(L10n.string(title)).font(Theme.Fonts.meta) }
                .wordListRows()
        }
    }
}

@MainActor @Observable
final class AtlasPronunciationPlayer {
    private(set) var loading = false
    private(set) var playing = false
    private(set) var error: String?
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var localURL: URL?

    nonisolated static func cacheFilename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension
        let safeExtension = !ext.isEmpty && ext.count <= 8 && ext.allSatisfy { $0.isASCII && $0.isLetter || $0.isNumber } ? ext : "audio"
        return "\(digest).\(safeExtension)"
    }

    func play(_ inputURL: URL) {
        let url = URL(string: inputURL.absoluteString.replacingOccurrences(of: "https://0xlei.tech/words/atlas/", with: "https://raw.githubusercontent.com/designfuchen/word-atlas/main/public/atlas/")) ?? inputURL
        stop()
        error = nil
        loading = true
        request = Task {
            do {
                let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("WordAtlasAudio")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let file = dir.appendingPathComponent(Self.cacheFilename(for: url))
                if !FileManager.default.fileExists(atPath: file.path) {
                    let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
                    try Task.checkCancellation()
                    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), !data.isEmpty else { throw URLError(.badServerResponse) }
                    try data.write(to: file, options: .atomic)
                }
                localURL = file
                let asset = AVURLAsset(url: file)
                guard try await asset.load(.isPlayable) else {
                    try? FileManager.default.removeItem(at: file)
                    throw URLError(.cannotDecodeContentData)
                }
                try Task.checkCancellation()
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                let item = AVPlayerItem(asset: asset)
                player = AVPlayer(playerItem: item)
                observer = makeEndObserver(item)

                loading = false
                playing = true
                player?.play()
            } catch {
                guard !Task.isCancelled else { return }
                stop()
                self.error = L10n.string("Couldn't load audio")
            }
        }
    }

    private func makeEndObserver(_ item: AVPlayerItem) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    func stop() {
        request?.cancel()
        request = nil
        player?.pause()
        player = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        localURL = nil
        playing = false
        loading = false
    }
}

struct WordListSourceView: View {
    let source: WordListSource
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: source.name).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            NavigationLink {
                WordListSourceDetailView(source: source)
            } label: {
                Text(L10n.string("Source and license"))
            }
            if source.contentType == "ai-generated" {
                Text(L10n.string("AI-generated content")).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            }
        }.font(Theme.Fonts.body)
    }
}

private struct WordListSourceDetailView: View {
    let source: WordListSource
    var body: some View {
        List {
            Section {
                Text(verbatim: source.name).font(Theme.Fonts.body.weight(.semibold))
                Text(verbatim: source.attribution)
                Text(L10n.string(source.modified ? "Source content was modified." : "Source content is unchanged."))
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                Link(L10n.string("View source"), destination: source.url)
                Link(L10n.string("View license"), destination: source.licenseURL)
                Text(verbatim: source.license).font(Theme.Fonts.meta)
                if source.name == "Word Atlas" { NavigationLink(L10n.string("Credits")) { WordListCreditsView() } }
            }.wordListRows()
        }
        .environment(\.defaultMinListRowHeight, 48).listStyle(.plain).listSectionSpacing(24).scrollContentBackground(.hidden).background(Theme.background)
        .font(Theme.Fonts.body).foregroundStyle(Theme.ink).tint(Theme.ink)
        .navigationTitle(L10n.string("Source and license")).navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func wordListRows() -> some View {
        self
            .font(Theme.Fonts.body)
            .listRowBackground(
                Theme.background.overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 24)
                }
            )
            .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
            .listRowSeparator(.hidden)
    }
}

#Preview("Word lists and attribution") {
    NavigationStack { WordListsView() }
        .modelContainer(for: Card.self, inMemory: true)
}

/// Translate only standard metadata; custom learning data remains unchanged.
enum WordListMetadata {
    static func level(_ value: String) -> String {
        ["A1", "A2", "B1", "B2", "C1", "C2"].contains(value) ? L10n.string(value) : value
    }

    static func topic(_ value: String) -> String {
        let standard = [
            "arts": "Arts", "city": "City", "daily": "Daily life", "economy": "Economy",
            "education": "Education", "emotion": "Emotion", "environment": "Environment",
            "government": "Government", "health": "Health", "history": "History", "media": "Media",
            "nature": "Nature", "science": "Science", "society": "Society", "sport": "Sport",
            "technology": "Technology", "thinking": "Thinking", "travel": "Travel", "work": "Work"
        ]
        guard let key = standard[value] else { return value }
        return L10n.string(key)
    }

    static func partOfSpeech(_ value: String) -> String {
        let standard = [
            "adj.": "Adjective", "adv.": "Adverb", "conj.": "Conjunction", "det.": "Determiner",
            "int.": "Interjection", "n.": "Noun", "num.": "Numeral", "phr.": "Phrase",
            "prep.": "Preposition", "pron.": "Pronoun", "v.": "Verb",
            "adjective": "Adjective", "adverb": "Adverb", "conjunction": "Conjunction",
            "determiner": "Determiner", "interjection": "Interjection", "noun": "Noun",
            "numeral": "Numeral", "phrase": "Phrase", "preposition": "Preposition",
            "pronoun": "Pronoun", "verb": "Verb"
        ]
        guard let key = standard[value.lowercased()] else { return value }
        return L10n.string(key)
    }
}
