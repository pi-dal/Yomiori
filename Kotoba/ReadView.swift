import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import CoreText

struct ReadView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Material.createdAt, order: .reverse) private var items: [Material]
    @Environment(AppState.self) private var app
    @State private var importer: ImportKind?
    @State private var linkMode: LinkSheet.Mode?
    @State private var showImport = false
    @State private var photo: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showSettings = false
    @State private var transcribing: (title: String, p: Double)?
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var path: [Material] = []
    @AppStorage("targetLang") private var importLanguage = "ja"

    enum ImportKind: Identifiable { case media, subtitle; var id: Self { self } }
    struct ModeBox: Identifiable { let mode: LinkSheet.Mode; var id: Int { mode == .link ? 0 : 1 } }

    private func openJump() {
        guard let j = app.jumpMaterial, let m = items.first(where: { $0.id.uuidString == j.id }) else { return }
        m.lastLine = Subtitles.index(at: j.time, in: m.lines) ?? 0
        path = [m]
    }

    private var importSheet: some View {
        NavigationStack {
            List {
                Picker("Language", selection: $importLanguage) {
                    Text("Japanese").tag("ja"); Text("English").tag("en")
                }
                .frame(minHeight: 56)
                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                .listRowSeparatorTint(Theme.separator)
                .listRowSeparator(.hidden, edges: .top)
                .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions[.trailing] }
                row("Video or audio", "") { showImport = false; importer = .media }
                row("Photos", "") { showImport = false; showPhotos = true }
                row("Subtitle file", "") { showImport = false; importer = .subtitle }
                row("Media link", "") { showImport = false; Task { try? await Task.sleep(for: .milliseconds(400)); linkMode = .link } }
                row("Podcast feed", "") { showImport = false; Task { try? await Task.sleep(for: .milliseconds(400)); linkMode = .podcast } }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 56)
            .listRowSeparatorTint(Theme.separator)
            .scrollContentBackground(.hidden).background(Theme.background)
            .foregroundStyle(Theme.ink)
            .navigationTitle("Import").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { showImport = false } } }
        }
        .presentationDetents([.medium, .large])
    }
    private func row(_ title: LocalizedStringKey, _ sub: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        .listRowSeparatorTint(Theme.separator)
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions[.trailing] }
    }

    private func ingestDownloaded(_ f: URL, title: String, kind: String, art: URL?) {
        importMedia(f, title: title, source: kind, art: art)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if items.isEmpty { empty } else { list }
            }
            .background(Theme.background)
        .font(Theme.Fonts.body)
            .navigationTitle("Read").navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Material.self) { ReaderView(material: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showImport = true } label: { Image(systemName: "plus") }.accessibilityLabel("Import")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showImport) { importSheet }
            .sheet(item: Binding(get: { linkMode.map { ModeBox(mode: $0) } }, set: { if $0 == nil { linkMode = nil } })) { b in
                LinkSheet(mode: b.mode) { f, title, kind, art in ingestDownloaded(f, title: title, kind: kind, art: art) }
            }
            .onChange(of: app.jumpMaterial?.id) { _, id in openJump() }
            .onAppear { openJump() }
            .fileImporter(isPresented: Binding(get: { importer != nil }, set: { if !$0 { importer = nil } }),
                          allowedContentTypes: importer == .subtitle ? [UTType(filenameExtension: "srt") ?? .plainText, UTType(filenameExtension: "vtt") ?? .plainText, .plainText] : [.movie, .audio, .mpeg4Movie, .mp3]) { r in
                guard case .success(let url) = r else { return }
                let kind = importer; importer = nil
                if kind == .subtitle { importSubtitle(url) } else { importMedia(url) }
            }
            .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .videos)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let m = try? await item.loadTransferable(type: VideoFile.self) { importMedia(m.url, title: L10n.string("Video")) }
                    photo = nil
                }
            }
            .overlay { if let t = transcribing { progressCard(t) } }
            .alert("Couldn't import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private var empty: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("No reading material").font(Theme.Fonts.body.weight(.semibold))
                Button { showImport = true } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "plus").font(.system(size: 24)).frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add Text").font(Theme.Fonts.body.weight(.semibold))
                            Text("Import or add a text to start reading.").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                }.buttonStyle(.plain)
            }
            .frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.top, 24).frame(maxWidth: .infinity)
        }
    }

    private var list: some View {
        let resumed = items.first(where: { $0.lastLine > 0 && !$0.lines.isEmpty })
        let recent = items.filter { $0.id != resumed?.id }
        return List {
            Section {
                Text("Continue where you left off or add a new text.")
                    .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 20, trailing: 24))
                    .listRowSeparator(.hidden)
            }
            if let m = resumed {
                Section("Continue reading") {
                    NavigationLink(value: m) { materialRow(m, resumed: true) }
                        .swipeActions { Button("Delete", role: .destructive) { delete(m) } }
                }
            }
            Section("Recent") {
                ForEach(recent) { m in
                    NavigationLink(value: m) { materialRow(m, resumed: false) }
                }
                .onDelete { offsets in for i in offsets { delete(recent[i]) } }
            }
            Section("Add Text") {
                Button { showImport = true } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "plus").font(.system(size: 24, weight: .regular)).frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Import or add a text").font(Theme.Fonts.body.weight(.semibold))
                            Text("Paste text, import a file, or choose from your library.").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    }
                    .frame(minHeight: 56, alignment: .leading)
                }
            }
        }
        .listStyle(.plain)
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
        .environment(\.defaultMinListRowHeight, 56)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
    }

    private func materialRow(_ material: Material, resumed: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: material.isAudio ? "waveform" : "doc.text")
                .font(.system(size: 20)).frame(width: 24, height: 24)
                .foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(material.title).font(Theme.Fonts.body.weight(.semibold))
                Text(Language.find(material.languageCode).displayName).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                Text(resumed
                     ? L10n.format("read.position", Int64(material.lastLine + 1), Int64(material.lines.count))
                     : (material.lines.isEmpty ? L10n.string("read.needsTranscription") : L10n.format("read.ready", Int64(material.lines.count))))
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func progressCard(_ t: (title: String, p: Double)) -> some View {
        VStack(spacing: 12) {
            Text(L10n.format("read.transcribing", Int64(t.p * 100))).font(Theme.Fonts.body.weight(.semibold))
            ProgressLine(value: t.p)
            Button("Cancel", role: .cancel) { task?.cancel(); transcribing = nil }
        }
        .padding(24).frame(maxWidth: 320)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func delete(_ m: Material) {
        if let f = m.mediaFile { try? FileManager.default.removeItem(at: Files.url(f)) }
        ctx.delete(m)
    }

    private func importSubtitle(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { error = L10n.string("Couldn't read this file."); return }
        let lines = Subtitles.parse(s)
        guard !lines.isEmpty else { error = L10n.string("read.noSubtitlesBody"); return }
        let m = Material(title: url.deletingPathExtension().lastPathComponent)
        m.languageCode = importLanguage
        m.lines = lines
        ctx.insert(m)
        Analytics.capture("material_added", ["kind": "subtitle"])
        path = [m]
    }

    private func importMedia(_ url: URL, title: String? = nil, source: String = "file", art: URL? = nil) {
        let name: String
        do { name = try Files.importFile(url) } catch { self.error = L10n.string("Couldn't read this file."); return }
        let m = Material(title: title ?? url.deletingPathExtension().lastPathComponent, mediaFile: name)
        m.languageCode = importLanguage
        m.sourceKind = source; m.artworkURL = art?.absoluteString
        Analytics.capture("material_added", ["kind": source])
        m.isAudio = ["mp3", "m4a", "aac", "wav", "aiff", "caf"].contains((name as NSString).pathExtension.lowercased())
        ctx.insert(m)
        let file = Files.url(name)
        transcribing = (m.title, 0)
        task = Task {
            do {
                let lines = try await Transcriber.run(url: file, locale: Language.find(m.languageCode).locale) { p in
                    Task { @MainActor in transcribing = (m.title, p) }
                }
                m.lines = lines
                transcribing = nil
                path = [m]
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                transcribing = nil
                m.needsTranscription = true
                if !Task.isCancelled { self.error = L10n.string("read.noSubtitlesBody") }
                path = [m]
            }
        }
    }
}

struct VideoFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { f in
            let dst = URL.temporaryDirectory.appending(path: UUID().uuidString + "-" + f.file.lastPathComponent)
            try FileManager.default.copyItem(at: f.file, to: dst)
            return VideoFile(url: dst)
        }
    }
}

// MARK: Reader (Focus layout)

struct ReaderView: View {
    @Bindable var material: Material
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var ctx
    @ScaledMetric(relativeTo: .title2) private var focusSize: CGFloat = 28
    @Query private var savedWords: [DictEntry]
    @State private var player = PlayerModel()
    @State private var showTranslation = false
    @State private var furigana = true
    @State private var wordSheet: WordTarget?
    @State private var translating = false
    @State private var banner: String?
    @State private var noteLine: SubLine?
    @State private var noteText = ""
    @State private var tapped: Set<String> = []
    @State private var showSubtitles = false
    @State private var subtitleError: String?
    @State private var stageOverflows = false

    struct WordTarget: Identifiable { let id = UUID(); let word: String; let sentence: String; var kind = "word"; var materialID = ""; var materialTitle = ""; var time = 0.0; var end = 0.0; var mediaFile: String?; var translation: String?; var languageCode = "ja" }

    init(material: Material) {
        _material = Bindable(material)
        let id = material.id.uuidString
        _savedWords = Query(filter: #Predicate<DictEntry> { $0.sourceID == id })
    }

    private var lines: [SubLine] { material.lines }
    private var current: Int? { Subtitles.index(at: player.time, in: lines) }
    private var index: Int { min(max(current ?? 0, 0), max(lines.count - 1, 0)) }
    private var savedTerms: Set<String> { Set(savedWords.filter { $0.kind != "highlight" }.map(\.term)) }
    private var hasMedia: Bool { material.mediaFile != nil }

    var body: some View {
        VStack(spacing: 0) {
            if let banner {
                HStack { Image(systemName: "wifi.slash"); Text(banner); Spacer(); Button("Try again") { translateAll() } }
                    .font(Theme.Fonts.meta).padding(.horizontal, 24).padding(.vertical, 12).background(Theme.highlight)
            }
            if lines.isEmpty { retry } else { focus }
        }
        .background(Theme.background)
        .font(Theme.Fonts.body)
        .navigationTitle(material.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if hasMedia { speedMenu }
                readingOptions
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { if hasMedia { controls } }
        .sheet(item: $wordSheet) { t in
            WordSheet(target: t).presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $showSubtitles, allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText, UTType(filenameExtension: "vtt") ?? .plainText, .plainText]) { result in
            guard case .success(let url) = result else {
                subtitleError = L10n.string("Couldn't read this file."); return
            }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                subtitleError = L10n.string("Couldn't read this file."); return
            }
            let imported = Subtitles.parse(text)
            guard !imported.isEmpty else { subtitleError = L10n.string("read.noSubtitlesBody"); return }
            material.lines = imported
            material.needsTranscription = false
            subtitleError = nil
        }
        .alert("Add note", isPresented: Binding(get: { noteLine != nil }, set: { if !$0 { noteLine = nil } })) {
            TextField("Write a note", text: $noteText)
            Button("Save") {
                if let l = noteLine, let i = lines.firstIndex(where: { $0.id == l.id }) { var ls = lines; ls[i].note = noteText; material.lines = ls }
                noteLine = nil
            }
            Button("Cancel", role: .cancel) { noteLine = nil }
        }
        .onAppear {
            if let f = material.mediaFile { player.load(Files.url(f)) }
            if material.lastLine > 0, material.lastLine < lines.count { player.seek(lines[material.lastLine].start) }
        }
        .onDisappear {
            if let c = current { material.lastLine = c }
            player.stop(); app.jumpMaterial = nil
        }
        .onChange(of: current) { _, c in if let c { material.lastLine = c } }
        .immersion(material.isAudio || material.sourceKind != "file" ? "listening" : "listening", active: player.playing)
    }

    // MARK: Top bar

    private var speedMenu: some View {
        Menu {
            ForEach([0.75, 1, 1.25, 1.5] as [Float], id: \.self) { rate in
                Button("\(rate.formatted())×") { player.setRate(rate) }
            }
        } label: {
            Text("\(player.rate.formatted())×").font(Theme.Fonts.meta.monospacedDigit())
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Playback speed")
    }

    private var readingOptions: some View {
        Menu {
            Picker("Language", selection: $material.languageCode) {
                Text("Japanese").tag("ja"); Text("English").tag("en")
            }
            if material.languageCode == "ja" {
                Button { furigana.toggle() } label: {
                    Label(furigana ? L10n.string("read.furiganaHide") : L10n.string("read.furiganaShow"), systemImage: "textformat.size.ja")
                }
            }
            Toggle("Translation", isOn: Binding(get: { showTranslation }, set: {
                showTranslation = $0
                if $0 { translateAll() }
            }))
            if !lines.isEmpty {
                ShareLink(item: exportFile(), preview: SharePreview("\(material.title).srt")) {
                    Label("Export subtitles", systemImage: "square.and.arrow.up")
                }
                let line = lines[index]
                if hasMedia {
                    Button(L10n.string("read.play"), systemImage: "play") { player.seek(line.start, play: true) }
                }
                Button("Save word", systemImage: "star") { wordSheet = target(line.text, line, kind: "line") }
                if line.hl == nil {
                    Button("Highlight", systemImage: "highlighter") { highlight(line, HL.all[0]) }
                } else {
                    Button("Remove highlight", systemImage: "highlighter", role: .destructive) { highlight(line, nil) }
                }
                Button("Add note", systemImage: "note.text") { noteText = line.note ?? ""; noteLine = line }
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = line.text }
                Button("Ask Coach", systemImage: "bubble.left") { app.askCoach(L10n.format("Discuss this line: %@", line.text), context: material.title, languageCode: material.languageCode) }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Reading options")
    }

    private var retry: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("No subtitles found").font(Theme.Fonts.body.weight(.semibold))
                if let subtitleError { Text(subtitleError).foregroundStyle(Theme.errorText) }
                Button("Subtitle file") { showSubtitles = true }.buttonStyle(InkButtonStyle())
            }
            .frame(maxWidth: 640, alignment: .leading).padding(24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Focus stack

    private var focus: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    ReaderStudyLayout(stageHeight: geometry.size.height) {
                        VStack(alignment: .leading, spacing: 24) {
                            if index > 0 { neighbour(index - 1) }
                            currentLine(index)
                            if index + 1 < lines.count { neighbour(index + 1) }
                        }
                        .frame(maxWidth: 640, alignment: .leading)
                        .onGeometryChange(for: Bool.self) { group in
                            group.size.height > geometry.size.height
                        } action: { overflows in
                            stageOverflows = overflows
                            if overflows { revealCurrent(using: proxy) }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .defaultScrollAnchor(.top)
                .onChange(of: index) { _, _ in
                    if stageOverflows { revealCurrent(using: proxy) }
                }
            }
        }
    }

    private func revealCurrent(using proxy: ScrollViewProxy) {
        guard lines.indices.contains(index) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { proxy.scrollTo(lines[index].id, anchor: .top) }
    }

    private func go(_ i: Int) {
        guard lines.indices.contains(i) else { return }
        player.seek(lines[i].start)
    }

    private func neighbour(_ i: Int) -> some View {
        let l = lines[i]
        return Text(l.text).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            .contentShape(Rectangle())
            .onTapGesture { go(i) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { go(i) }
    }

    private func currentLine(_ i: Int) -> some View {
        let line = lines[i]
        let terms = savedTerms
        return VStack(alignment: .leading, spacing: 24) {
            TappableText(text: line.text, language: material.languageCode, furigana: furigana && material.languageCode == "ja",
                         pointSize: focusSize, lineSpacing: 10, highlighted: line.hl != nil,
                         washed: { terms.contains($0) || tapped.contains("\(line.id)|\($0)") }) { w in
                tapped.insert("\(line.id)|\(w)")
                wordSheet = target(w, line)
            }
            .foregroundStyle(Theme.ink)
            if showTranslation, let t = line.translation {
                Text(t).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
            } else if showTranslation && translating { ProgressView().accessibilityLabel("Translation") }
            if let n = line.note { Label(n, systemImage: "note.text").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isSelected)
        .accessibilityValue(L10n.format("read.position", Int64(i + 1), Int64(lines.count)))
        .id(line.id)
    }

    // MARK: Controls

    private var controls: some View {
        let progress = player.time / max(player.duration, 1)
        let accessibilityProgress = progress.isFinite ? min(max(progress, 0), 1) : 0
        return VStack(spacing: 16) {
            ProgressLine(value: progress, onSeek: { player.seek($0 * max(player.duration, 1)) })
                .accessibilityRepresentation {
                    Slider(value: Binding(
                        get: { accessibilityProgress },
                        set: { player.seek($0 * max(player.duration, 1)) }
                    ), in: 0...1) {
                        Text("Playback position")
                    }
                    .accessibilityValue(accessibilityProgress.formatted(.percent.precision(.fractionLength(0))))
                    .accessibilityAdjustableAction { d in player.seek(player.time + (d == .increment ? 10 : -10)) }
                }
            ZStack {
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 24)).foregroundStyle(Theme.background)
                        .frame(width: 56, height: 56).background(Theme.ink, in: Circle())
                }
                .accessibilityLabel(player.playing ? L10n.string("read.pause") : L10n.string("read.play"))
                Button { player.seek(player.time - 10) } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 20)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back 10 seconds").offset(x: -72)
                Button { player.seek(player.time + 10) } label: {
                    Image(systemName: "goforward.10").font(.system(size: 20)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Forward 10 seconds").offset(x: 72)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: 720, minHeight: 88)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    private func target(_ w: String, _ line: SubLine, kind: String = "word") -> WordTarget {
        WordTarget(word: w, sentence: line.text, kind: kind, materialID: material.id.uuidString, materialTitle: material.title, time: line.start, end: line.end, mediaFile: material.mediaFile, translation: line.translation, languageCode: material.languageCode)
    }

    private func highlight(_ line: SubLine, _ h: HL?) {
        var ls = material.lines
        guard let i = ls.firstIndex(where: { $0.id == line.id }) else { return }
        ls[i].hl = h?.id
        material.lines = ls
        let mid = material.id.uuidString, start = line.start
        let existing = (try? ctx.fetch(FetchDescriptor<DictEntry>(predicate: #Predicate { $0.sourceID == mid && $0.kind == "highlight" })))?.first { $0.sourcePos == start }
        if let h {
            if let e = existing { e.colorIdx = h.id } else {
                let e = DictEntry(term: line.text, kind: "highlight", sourceKind: "subtitle")
                e.colorIdx = h.id; e.context = line.text; e.sourceID = mid; e.sourceName = material.title; e.sourcePos = start
                ctx.insert(e)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else if let e = existing { ctx.delete(e) }
    }

    private func translateAll() {
        guard !lines.isEmpty, !translating else { return }
        banner = nil
        let pending = lines.enumerated().filter { $0.element.translation == nil }
        guard !pending.isEmpty else { return }
        translating = true
        Task {
            defer { translating = false }
            do {
                for chunk in stride(from: 0, to: pending.count, by: 25).map({ Array(pending[$0..<min($0 + 25, pending.count)]) }) {
                    let out = try await AI.translate(chunk.map { $0.element.text }, from: Language.find(material.languageCode), to: Prefs.native)
                    var ls = material.lines
                    for (k, item) in chunk.enumerated() where k < out.count && !out[k].isEmpty { ls[item.offset].translation = out[k] }
                    material.lines = ls
                }
            } catch { banner = L10n.string("read.translationUnavailable") }
        }
    }

    private func exportFile() -> URL {
        let u = URL.temporaryDirectory.appending(path: "\(material.title).srt")
        try? Subtitles.srt(lines).write(to: u, atomically: true, encoding: .utf8)
        return u
    }
}

/// 2pt ink progress line on a light track. Tap or drag to seek when `onSeek` is set.
struct ProgressLine: View {
    let value: Double
    var onSeek: ((Double) -> Void)?
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.track)
                Rectangle().fill(Theme.ink).frame(width: g.size.width * min(max(value, 0), 1))
            }
            .frame(height: 2).frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                onSeek?(min(max(v.location.x / max(g.size.width, 1), 0), 1))
            })
        }
        .frame(height: onSeek == nil ? 20 : 44)
    }
}

/// A single measured composition: short prose centers at 45% of the available
/// stage; long prose supplies its natural scroll extent, without duplicate views.
private struct ReaderStudyLayout: Layout {
    let stageHeight: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let height = subviews.first?.sizeThatFits(.init(width: min(width, 640), height: nil)).height ?? 0
        return CGSize(width: width, height: height > stageHeight ? height + 48 : stageHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let group = subviews.first else { return }
        let width = min(bounds.width, 640)
        let size = group.sizeThatFits(.init(width: width, height: nil))
        let top = size.height > stageHeight ? 24 : max(0, stageHeight * 0.45 - size.height / 2)
        group.place(at: CGPoint(x: bounds.midX, y: bounds.minY + top), anchor: .top,
                    proposal: .init(width: width, height: size.height))
    }
}

/// CoreText uses one frame for ruby drawing, native line breaking and token hit tests.
struct TappableText: UIViewRepresentable {
    let text: String, language: String, furigana: Bool
    var pointSize: CGFloat = 17
    var lineSpacing: CGFloat = 4
    var highlighted = false
    var washed: (String) -> Bool = { _ in false }
    let onTap: (String) -> Void
    @ScaledMetric(relativeTo: .caption) private var rubySize: CGFloat = 14
    @Environment(\.colorScheme) private var colorScheme

    init(text: String, language: String, furigana: Bool, pointSize: CGFloat = 17,
         lineSpacing: CGFloat = 4, highlighted: Bool = false,
         washed: @escaping (String) -> Bool = { _ in false }, onTap: @escaping (String) -> Void) {
        self.text = text; self.language = language; self.furigana = furigana
        self.pointSize = pointSize; self.lineSpacing = lineSpacing; self.highlighted = highlighted
        self.washed = washed; self.onTap = onTap
    }
    func makeUIView(context: Context) -> ReaderRubyTextView { ReaderRubyTextView() }
    func updateUIView(_ view: ReaderRubyTextView, context: Context) {
        view.onWord = onTap
        let tokens = Words.tokens(text, language: language)
        let selectedWords = tokens.filter { $0.1 && washed($0.0) }.map(\.0)
        let key = RenderKey(text: text, language: language, furigana: furigana,
                            pointSize: pointSize, rubySize: rubySize, lineSpacing: lineSpacing,
                            highlighted: highlighted, selectedWords: selectedWords, dark: colorScheme == .dark)
        guard view.renderedKey != key else { return }
        view.renderedKey = key
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let ink = UIColor(Theme.ink).resolvedColor(with: traits)
        let supporting = UIColor(Theme.textSecondary).resolvedColor(with: traits)
        view.selectionColor = UIColor(Theme.highlight).resolvedColor(with: traits)
        view.tintColor = ink
        var breakMode = CTLineBreakMode.byWordWrapping
        var spacing = lineSpacing
        let paragraph: CTParagraphStyle = withUnsafePointer(to: &breakMode) { modePointer in
            withUnsafePointer(to: &spacing) { spacingPointer in
                let settings = [
                    CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: modePointer),
                    CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: spacingPointer)
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        let systemFont = UIFont.systemFont(ofSize: pointSize, weight: .semibold)
        let descriptor = systemFont.fontDescriptor.addingAttributes([
            .cascadeList: [UIFontDescriptor(name: "HiraginoSans-W6", size: pointSize)]
        ])
        // Bridge the actual system font rather than re-resolving its private
        // PostScript name. Ruby inherits this sans-serif cascade at its 14pt ratio.
        let font = UIFont(descriptor: descriptor, size: pointSize) as CTFont
        let content = NSMutableAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink.cgColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
            NSAttributedString.Key(kCTLanguageAttributeName as String): language
        ])
        var offset = 0
        var wordRanges: [ReaderRubyTextView.WordRange] = []
        var highlights: [NSRange] = []
        for (token, isWord) in tokens {
            let range = NSRange(location: offset, length: (token as NSString).length)
            defer { offset += range.length }
            if highlighted || (isWord && selectedWords.contains(token)) {
                highlights.append(range)
                content.addAttribute(NSAttributedString.Key(kCTUnderlineStyleAttributeName as String),
                                     value: CTUnderlineStyle.single.rawValue, range: range)
            }
            guard isWord else { continue }
            wordRanges.append(.init(text: token, range: range))
            if furigana, let reading = Words.reading(token) {
                let ruby = CTRubyAnnotationCreateWithAttributes(.auto, .auto, .before, reading as CFString, [
                    kCTRubyAnnotationSizeFactorAttributeName: rubySize / pointSize,
                    kCTForegroundColorAttributeName: supporting.cgColor
                ] as CFDictionary)
                content.addAttribute(NSAttributedString.Key(kCTRubyAnnotationAttributeName as String), value: ruby, range: range)
            }
        }
        view.configure(content: content, words: wordRanges, highlights: highlights, language: language)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReaderRubyTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
    struct RenderKey: Equatable {
        let text: String, language: String
        let furigana: Bool
        let pointSize: CGFloat, rubySize: CGFloat, lineSpacing: CGFloat
        let highlighted: Bool
        let selectedWords: [String]
        let dark: Bool
    }
}

/// CoreText suggests native Japanese line breaks; ruby base ranges that fit
/// stay together. Drawing and selection share lines with original UTF-16 offsets.
final class ReaderRubyTextView: UIView, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
    struct WordRange { let text: String; let range: NSRange }
    struct TextFrame { let width: CGFloat; let height: CGFloat; let lines: [CTLine]; let origins: [CGPoint] }
    var renderedKey: TappableText.RenderKey?
    var onWord: ((String) -> Void)?
    var selectionColor = UIColor(Theme.highlight)
    private var content = NSAttributedString(string: "")
    private var framesetter: CTFramesetter?
    private var cachedFrame: TextFrame?
    private var words: [WordRange] = []
    private var highlights: [NSRange] = []
    private var selectedRange: NSRange? {
        didSet {
            accessibilityValue = selectedExcerpt
            accessibilityTraits = selectedRange == nil ? .staticText : [.staticText, .selected]
        }
    }
    // Keep the latest presented excerpt after visual selection is dismissed;
    // UIKit may reuse the same UIActions after either handle extends the range.
    private var menuExcerpt: String?
    private var selectionAnchor = NSRange(location: 0, length: 0)
    private lazy var editMenu = UIEditMenuInteraction(delegate: self)
    private weak var observedWindow: UIWindow?
    private lazy var outsideTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tappedOutside(_:)))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()
    private lazy var handleDrag: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(draggedHandle(_:)))
        gesture.delegate = self
        return gesture
    }()

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let select = UILongPressGestureRecognizer(target: self, action: #selector(selected(_:)))
        tap.require(toFail: select)
        tap.require(toFail: handleDrag)
        addGestureRecognizer(tap)
        addGestureRecognizer(select)
        addGestureRecognizer(handleDrag)
        addInteraction(editMenu)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(content: NSAttributedString, words: [WordRange], highlights: [NSRange], language: String) {
        if self.content.string != content.string { clearSelection() }
        self.content = content; self.words = words; self.highlights = highlights
        framesetter = CTFramesetterCreateWithAttributedString(content as CFAttributedString)
        cachedFrame = nil
        accessibilityLabel = content.string
        accessibilityLanguage = language
        // Read the authentic sentence once; each word also has a VoiceOver lookup action.
        var seen: Set<String> = []
        accessibilityCustomActions = words.filter { seen.insert($0.text).inserted }.map { word in
            UIAccessibilityCustomAction(name: word.text) { [weak self] _ in
                self?.onWord?(word.text)
                return true
            }
        }
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    private func textFrame(width: CGFloat) -> TextFrame? {
        guard width.isFinite, width > 0, let framesetter else { return nil }
        if let cachedFrame, cachedFrame.width == width { return cachedFrame }
        let typesetter = CTFramesetterGetTypesetter(framesetter)
        let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
        let rubyWords = words.filter { content.attribute(rubyKey, at: $0.range.location, effectiveRange: nil) != nil }
        var lines: [CTLine] = []
        var baselineDepths: [CGFloat] = []
        var height: CGFloat = 0
        var start = 0
        while start < content.length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            if count <= 0 {
                count = (content.string as NSString).rangeOfComposedCharacterSequence(at: start).length
            }
            var end = min(content.length, start + count)
            if let word = rubyWords.first(where: { $0.range.location < end && end < NSMaxRange($0.range) && $0.range.location > start }) {
                let wholeWord = CTTypesetterCreateLine(typesetter, CFRange(location: word.range.location, length: word.range.length))
                if CTLineGetTypographicBounds(wholeWord, nil, nil, nil) <= Double(width) {
                    end = word.range.location
                }
            }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: end - start))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            if ascent + descent <= 0 {
                let font = UIFont.systemFont(ofSize: renderedKey?.pointSize ?? 28, weight: .semibold)
                ascent = font.ascender; descent = -font.descender
            }
            if !lines.isEmpty { height += max(0, renderedKey?.lineSpacing ?? 0) }
            baselineDepths.append(height + ascent)
            height += ascent + descent + max(0, leading)
            lines.append(line)
            start = end
        }
        height = max(1, ceil(height) + 1)
        let origins = baselineDepths.map { CGPoint(x: 0, y: height - $0) }
        let result = TextFrame(width: width, height: height, lines: lines, origins: origins)
        cachedFrame = result
        return result
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: textFrame(width: size.width)?.height ?? 0)
    }
    override func layoutSubviews() { super.layoutSubviews(); setNeedsDisplay() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let layout = textFrame(width: bounds.width) else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: layout.height)
        context.scaleBy(x: 1, y: -1)
        let lines = layout.lines
        let origins = layout.origins
        context.setFillColor(selectionColor.cgColor)
        for (line, origin) in zip(lines, origins) {
            let lineRange = CTLineGetStringRange(line)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            for highlight in highlights + (selectedRange.map { [$0] } ?? []) {
                let range = NSIntersectionRange(highlight, NSRange(location: lineRange.location, length: lineRange.length))
                guard range.length > 0 else { continue }
                let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
                let end = CTLineGetOffsetForStringIndex(line, NSMaxRange(range), nil)
                context.fill(CGRect(x: origin.x + min(start, end), y: origin.y - descent,
                                    width: abs(end - start), height: ascent + descent))
            }
        }
        for (line, origin) in zip(lines, origins) {
            context.textPosition = origin
            CTLineDraw(line, context)
        }
        context.restoreGState()
        if let selectedRange {
            // UIKit coordinates for functional selection stems and drag endpoints.
            context.setStrokeColor(tintColor.cgColor)
            context.setFillColor(tintColor.cgColor)
            context.setLineWidth(2)
            for (index, leading) in [(selectedRange.location, true), (NSMaxRange(selectedRange), false)] {
                if let caret = caretRect(at: index, preferPreviousLine: !leading) {
                    context.move(to: CGPoint(x: caret.midX, y: caret.minY))
                    context.addLine(to: CGPoint(x: caret.midX, y: caret.maxY))
                    context.strokePath()
                    let y = leading ? caret.minY : caret.maxY
                    context.fillEllipse(in: CGRect(x: caret.midX - 4, y: y - 4, width: 8, height: 8))
                }
            }
        }
    }
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let layout = textFrame(width: bounds.width) else { return }
        let location = recognizer.location(in: self)
        if let selectedRange {
            if let index = characterIndex(at: location), NSLocationInRange(index, selectedRange) { showSelectionMenu() }
            else { clearSelection() }
            return
        }
        let point = CGPoint(x: location.x, y: layout.height - location.y)
        let lines = layout.lines
        let origins = layout.origins
        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            guard point.y >= origin.y - descent, point.y <= origin.y + ascent,
                  point.x >= origin.x, point.x <= origin.x + width else { continue }
            let index = CTLineGetStringIndexForPosition(line, CGPoint(x: point.x - origin.x, y: point.y - origin.y))
            if let word = words.first(where: { NSLocationInRange(index, $0.range) }) { onWord?(word.text) }
            return
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if observedWindow !== window {
            observedWindow?.removeGestureRecognizer(outsideTap)
            observedWindow = window
            window?.addGestureRecognizer(outsideTap)
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === outsideTap || otherGestureRecognizer === outsideTap
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === handleDrag else { return true }
        return nearestEndpoint(to: gestureRecognizer.location(in: self)) != nil
    }
    @objc private func tappedOutside(_ gesture: UITapGestureRecognizer) {
        if selectedRange != nil, !bounds.contains(gesture.location(in: self)) {
            // The native menu sits outside these text bounds. Let UIKit finish
            // dispatching its Copy/Lookup action before it manages dismissal.
            selectedRange = nil
            setNeedsDisplay()
        }
    }
    private func clearSelection() {
        selectedRange = nil
        editMenu.dismissMenu()
        setNeedsDisplay()
    }
    /// Closest native line and UTF-16 insertion position; clamps a drag beyond the
    /// line ends so a continuous gesture can select across whitespace and lines.
    private func characterIndex(at point: CGPoint) -> Int? {
        guard let layout = textFrame(width: bounds.width), content.length > 0 else { return nil }
        let lines = layout.lines
        guard !lines.isEmpty else { return nil }
        let origins = layout.origins
        let flipped = CGPoint(x: point.x, y: layout.height - point.y)
        let verticalBounds = lines.indices.map { row -> ClosedRange<CGFloat> in
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTLineGetTypographicBounds(lines[row], &ascent, &descent, nil)
            return (origins[row].y - descent)...(origins[row].y + ascent)
        }
        // Prefer the line containing the finger, including its ascender/ruby
        // region. Only snap across a gap using distance to the bounds.
        let row = lines.indices.first(where: { verticalBounds[$0].contains(flipped.y) })
            ?? lines.indices.min { first, second in
                func distance(to interval: ClosedRange<CGFloat>) -> CGFloat {
                    max(interval.lowerBound - flipped.y, flipped.y - interval.upperBound, 0)
                }
                return distance(to: verticalBounds[first]) < distance(to: verticalBounds[second])
            }!
        let line = lines[row], origin = origins[row]
        let lineRange = CTLineGetStringRange(line)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if flipped.x <= origin.x { return lineRange.location }
        if flipped.x >= origin.x + width { return min(content.length, lineRange.location + lineRange.length) }
        let index = CTLineGetStringIndexForPosition(line, CGPoint(x: flipped.x - origin.x, y: 0))
        return index == kCFNotFound ? nil : min(max(0, index), content.length)
    }
    private func caretRect(at index: Int, preferPreviousLine: Bool) -> CGRect? {
        guard let layout = textFrame(width: bounds.width) else { return nil }
        let lines = layout.lines
        let origins = layout.origins
        for (line, origin) in zip(lines, origins) {
            let range = CTLineGetStringRange(line)
            let end = range.location + range.length
            guard index >= range.location, index < end || (preferPreviousLine && index == end) || index == content.length && index == end else { continue }
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let x = origin.x + CTLineGetOffsetForStringIndex(line, index, nil)
            return CGRect(x: x, y: layout.height - origin.y - ascent, width: 2, height: ascent + descent)
        }
        return nil
    }
    private func nearestEndpoint(to point: CGPoint) -> Bool? {
        guard let range = selectedRange,
              let start = caretRect(at: range.location, preferPreviousLine: false),
              let end = caretRect(at: NSMaxRange(range), preferPreviousLine: true) else { return nil }
        let first = hypot(point.x - start.midX, point.y - start.minY)
        let last = hypot(point.x - end.midX, point.y - end.maxY)
        guard min(first, last) <= 28 else { return nil }
        return first <= last
    }
    private func updateSelection(to index: Int) {
        let lower = min(selectionAnchor.location, index)
        let upper = max(NSMaxRange(selectionAnchor), index)
        let proposed = NSRange(location: lower, length: upper - lower)
        guard proposed.length > 0 else { return }
        // Never cut a surrogate pair, combining mark or other composed character.
        selectedRange = (content.string as NSString).rangeOfComposedCharacterSequences(for: proposed)
        setNeedsDisplay()
    }
    @objc private func selected(_ gesture: UILongPressGestureRecognizer) {
        guard let index = characterIndex(at: gesture.location(in: self)) else { return }
        switch gesture.state {
        case .began:
            editMenu.dismissMenu()
            let position = min(index, max(0, content.length - 1))
            selectionAnchor = words.first(where: { NSLocationInRange(position, $0.range) })?.range
                ?? (content.string as NSString).rangeOfComposedCharacterSequence(at: position)
            selectedRange = selectionAnchor
            setNeedsDisplay()
        case .changed: updateSelection(to: index)
        case .ended: updateSelection(to: index); showSelectionMenu()
        case .cancelled: showSelectionMenu()
        default: break
        }
    }
    @objc private func draggedHandle(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard let range = selectedRange, let leading = nearestEndpoint(to: point) else { return }
            editMenu.dismissMenu()
            selectionAnchor = NSRange(location: leading ? NSMaxRange(range) : range.location, length: 0)
        case .changed:
            if let index = characterIndex(at: point) { updateSelection(to: index) }
        case .ended, .cancelled: showSelectionMenu()
        default: break
        }
    }
    private var selectedExcerpt: String? {
        guard let range = selectedRange, range.length > 0, NSMaxRange(range) <= content.length else { return nil }
        return (content.string as NSString).substring(with: range)
    }
    private var selectionMenuTargetRect: CGRect? {
        guard let range = selectedRange,
              let start = caretRect(at: range.location, preferPreviousLine: false),
              let end = caretRect(at: NSMaxRange(range), preferPreviousLine: true) else { return nil }
        // Exclude the complete selected line span and both endpoint hit regions
        // from native menu placement, including the ruby above the first line.
        return start.union(end).insetBy(dx: -28, dy: -28)
    }
    private func showSelectionMenu() {
        guard let excerpt = selectedExcerpt, let target = selectionMenuTargetRect else { return }
        menuExcerpt = excerpt
        let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: target.midX, y: target.minY))
        configuration.preferredArrowDirection = .down
        editMenu.presentEditMenu(with: configuration)
    }
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        selectionMenuTargetRect ?? CGRect(origin: configuration.sourcePoint, size: .zero)
    }
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard menuExcerpt != nil else { return nil }
        return UIMenu(children: [
            UIAction(title: L10n.string("Copy"), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                guard let excerpt = self?.menuExcerpt else { return }
                UIPasteboard.general.string = excerpt
            },
            UIAction(title: L10n.string("Look up meaning"), image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
                guard let self, let excerpt = self.menuExcerpt else { return }
                self.onWord?(excerpt)
            }
        ])
    }

}

struct WordSheet: View {
    let target: ReaderView.WordTarget
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var saved: [DictEntry]
    @Query private var cards: [Card]
    @AppStorage("jaDefs") private var jaDefs = false
    @State private var entry: Words.Entry?
    @State private var failed = false
    @State private var toast: String?
    @State private var busy = false

    var isSaved: Bool { saved.contains { $0.term == target.word && $0.sourceID == target.materialID && $0.kind != "highlight" } }
    private var canMine: Bool { target.kind == "word" }
    private var mined: Bool { cards.contains { $0.word == target.word && $0.sentence == target.sentence } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(target.word).font(Theme.Fonts.focus.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        let sub = [Words.reading(target.word), entry.flatMap { $0.pos.isEmpty ? nil : $0.pos }].compactMap { $0 }.joined(separator: "\n")
                        if !sub.isEmpty { Text(sub).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                    }
                    if let entry {
                        Text(entry.meaning).font(Theme.Fonts.body)
                    } else if failed {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Translation unavailable", systemImage: "wifi.slash").foregroundStyle(Theme.textSecondary)
                            Button("Try again") { load() }.frame(minHeight: 44)
                        }
                    } else { ProgressView().accessibilityLabel("Translation") }
                    if canMine {
                        VStack(alignment: .leading, spacing: 8) {
                            observedSentence
                            if let translation = target.translation, !translation.isEmpty,
                               translation.trimmingCharacters(in: .whitespacesAndNewlines) != target.sentence.trimmingCharacters(in: .whitespacesAndNewlines) {
                                Text(translation).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if target.mediaFile != nil {
                            AudioRow(url: clipURLPreview, duration: min(target.end - target.time + 0.6, 30))
                        }
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 12) {
                    if canMine {
                        Button { mine() } label: {
                            HStack {
                                if busy { ProgressView().tint(Theme.background) }
                                Text(toast ?? (mined ? L10n.string("read.mined") : L10n.string("read.mine")))
                            }
                        }
                        .buttonStyle(InkButtonStyle()).disabled(busy || mined || entry == nil)
                        Button { toggle() } label: {
                            Text(isSaved ? L10n.string("read.saved") : L10n.string("read.saveWord"))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .accessibilityAddTraits(isSaved ? .isSelected : [])
                    } else {
                        Button { toggle() } label: {
                            Text(isSaved ? L10n.string("read.saved") : L10n.string("read.saveWord"))
                        }.buttonStyle(InkButtonStyle())
                        .accessibilityAddTraits(isSaved ? .isSelected : [])
                    }
                }
                .frame(maxWidth: 640).padding(.horizontal, 24).padding(.vertical, 16)
                .frame(maxWidth: .infinity).background(Theme.background)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.frame(minHeight: 44) }
            }
            .font(Theme.Fonts.body).foregroundStyle(Theme.ink)
            .background(Theme.background)
            .task { load(); await prepareClip() }
        }
    }

    private var observedSentence: Text {
        var sentence = AttributedString(target.sentence)
        if let range = sentence.range(of: target.word) {
            sentence[range].backgroundColor = Theme.highlight
            sentence[range].underlineStyle = .single
        }
        return Text(sentence).font(Theme.Fonts.body)
    }
    @State private var clipURLPreview: URL?
    private func prepareClip() async {
        guard let f = target.mediaFile, canMine else { return }
        let dest = FileManager.default.temporaryDirectory.appending(path: "clip-preview-\(target.materialID.prefix(6))-\(Int(target.time * 10)).m4a")
        if await Clip.export(media: Files.url(f), start: target.time, end: target.end, to: dest) { clipURLPreview = dest }
    }
    private func load() {
        failed = false
        Task {
            do { entry = try await Words.lookup(target.word, sentence: target.sentence, languageCode: target.languageCode) } catch { failed = true }
        }
    }
    private func mine() {
        guard !busy, !mined, entry != nil else { return }
        busy = true
        let c = Card(sentence: target.sentence, word: target.word)
        c.reading = Words.reading(target.word) ?? ""; c.meaning = entry?.meaning ?? ""; c.translation = target.translation ?? ""
        c.languageCode = target.languageCode
        c.sourceID = target.materialID; c.sourceName = target.materialTitle; c.sourcePos = target.time
        Task {
            var hasAudio = false
            if let f = target.mediaFile {
                let name = "card-\(UUID().uuidString.prefix(8)).m4a"
                if await Clip.export(media: Files.url(f), start: target.time, end: target.end, to: Files.url(name)) { c.audioFile = name; hasAudio = true }
            }
            if jaDefs && target.languageCode == "ja" { c.definitionJa = await Words.definitionJa(target.word, sentence: target.sentence) }
            ctx.insert(c)
            if !saved.contains(where: { $0.term == target.word && $0.sourceID == target.materialID && $0.kind != "highlight" }) { toggle(silent: true) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Analytics.capture("card_mined")
            toast = hasAudio ? L10n.string("read.savedAudio") : L10n.string("read.savedNoAudio")
            busy = false
            try? await Task.sleep(for: .seconds(1)); dismiss()
        }
    }
    private func toggle(silent: Bool = false) {
        if let s = saved.first(where: { $0.term == target.word && $0.sourceID == target.materialID && $0.kind != "highlight" }) { if !silent { ctx.delete(s) }; return }
        let e = DictEntry(term: target.word, kind: target.kind, sourceKind: "subtitle")
        e.reading = Words.reading(target.word) ?? ""; e.meaning = entry?.meaning ?? ""; e.context = target.sentence
        e.languageCode = target.languageCode
        e.sourceID = target.materialID; e.sourceName = target.materialTitle; e.sourcePos = target.time
        ctx.insert(e)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct SettingsView: View {
    @AppStorage("targetLang") private var target = "ja"
    @AppStorage("nativeLang") private var native = Language.deviceDefault
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    @State private var showFeedback = false
    @State private var usage = Analytics.enabled
    @AppStorage("jaDefs") private var jaDefs = false
    @AppStorage("enDefs") private var enDefs = true
    @AppStorage("reviewLimit") private var reviewLimit = 30
    @State private var exporting = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { LanguagesSettingsView() } label: {
                        Text("Languages").frame(minHeight: 44, alignment: .leading)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                Section {
                    Toggle("Japanese definitions", isOn: $jaDefs)
                    Toggle("English definitions", isOn: $enDefs)
                    Stepper(value: $reviewLimit, in: 10...100, step: 10) { preferenceValue("Daily review limit") { Text(reviewLimit, format: .number).foregroundStyle(Theme.textSecondary) } }
                    NavigationLink { StagePicker() } label: { preferenceValue("Learning stage") { Text(CoachStage.current.label).foregroundStyle(Theme.textSecondary) } }
                    NavigationLink("nav.immersion") { ImmersionView() }
                    Button("Export to Anki") { exporting = true }
                } header: { Text("Learning").font(Theme.Fonts.meta.weight(.semibold)) }
                .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                Section {
                    Toggle("Anonymous usage data", isOn: $usage)
                    Button("Send feedback") { showFeedback = true }
                    DisclosureGroup("Usage data details") { Text("Records screens and actions, not reading or chat content.").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                Section {
                    Button("Clear all data", role: .destructive) { confirm = true }.foregroundStyle(Theme.errorText)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                #if DEBUG
                Section("Developer tools") { Button("Load sample content") { DebugSeed.run(ctx); dismiss() }; Button("Run Coach test") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NotificationCenter.default.post(name: Notification.Name("coachtest"), object: nil) } } }
                #endif
                Section { NavigationLink("Credits") { WordListCreditsView() } }
                    .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                Section { MadeWithAirBuild(.compact) }
            }
            .listStyle(.plain).listSectionSpacing(24).scrollContentBackground(.hidden).background(Theme.background).tint(Theme.ink).font(Theme.Fonts.body)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .environment(\.defaultMinListRowHeight, 56)
            .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .sheet(isPresented: $exporting) { ExportSheet().presentationDetents([.medium, .large]) }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .onChange(of: usage) { _, v in Analytics.enabled = v }
            .sheet(isPresented: $showFeedback) { FeedbackView() }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
            .confirmationDialog("Imported content, saved words, cards, notes, and chat history will be deleted. This can't be undone.", isPresented: $confirm, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    try? ctx.delete(model: Material.self); try? ctx.delete(model: DictEntry.self); try? ctx.delete(model: PDFDoc.self)
                    try? ctx.delete(model: ChatMsg.self); try? ctx.delete(model: Mistake.self)
                    try? ctx.delete(model: Card.self); try? ctx.delete(model: ImmersionLog.self)
                    try? WordListLibrary.shared.clearImported()
                    try? FileManager.default.removeItem(at: Files.dir)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    private func preferenceValue<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(title)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            value()
        }
    }
}
