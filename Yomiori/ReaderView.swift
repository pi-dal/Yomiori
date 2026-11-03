import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct ReaderView: View {
    @Bindable var material: Material
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var ctx
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var focusSize: CGFloat = 28
    @Query private var savedWords: [DictEntry]
    @State private var player = PlayerModel()
    @State private var translationMode = ReaderTranslation.off
    @State private var revealed = false
    @State private var shownIndex: Int?
    @State private var forward = true
    @State private var manualSteps = 0
    @State private var furigana = true
    @State private var wordSheet: WordTarget?
    @State private var translation = SubtitleTranslation()
    @AppStorage("nativeLang") private var nativeLanguage = Language.deviceDefault
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
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "--preview-translation"), flag + 1 < arguments.count,
           let mode = ReaderTranslation(rawValue: arguments[flag + 1]) { _translationMode = State(initialValue: mode) }
        #endif
    }

    private var lines: [SubLine] { material.lines }
    private var current: Int? { Subtitles.index(at: player.time, in: lines) }
    private var index: Int { min(max(current ?? 0, 0), max(lines.count - 1, 0)) }
    /// The line the focus stack shows; it follows `index` inside an animated transaction.
    private var displayIndex: Int { min(max(shownIndex ?? index, 0), max(lines.count - 1, 0)) }
    private var showTranslation: Bool { translationMode != .off }
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
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if hasMedia { speedMenu }
                readingOptions
            }
            if !hasMedia && !lines.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    HStack(spacing: 16) {
                        Button { go(index - 1) } label: { Image(systemName: "chevron.left") }
                            .disabled(index == 0).accessibilityLabel("Previous line")
                        Text(L10n.format("read.position", Int64(index + 1), Int64(lines.count)))
                            .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                            .contentTransition(.numericText(value: Double(index)))
                            .animation(reduceMotion ? nil : .snappy, value: index)
                        Button { go(index + 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(index == lines.count - 1).accessibilityLabel("Next line")
                    }
                }
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
            if app.jumpMaterial?.id == material.id.uuidString { app.jumpMaterial = nil }
            shownIndex = index
        }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--preview-reader-demo"), !lines.isEmpty else { return }
            if hasMedia { try? await Task.sleep(for: .seconds(1)); player.toggle(); return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                go(index + 1 < lines.count ? index + 1 : 0)
            }
        }
        #endif
        .onChange(of: index) { old, new in
            // Adjacent steps animate so reading order stays legible; jumps cut cleanly.
            forward = new >= old
            var transaction = Transaction(animation: abs(new - old) == 1 ? ReaderMotion.advance(reduceMotion: reduceMotion) : nil)
            transaction.disablesAnimations = abs(new - old) != 1
            withTransaction(transaction) { shownIndex = new; revealed = false }
        }
        .sensoryFeedback(.selection, trigger: manualSteps)
        .sensoryFeedback(trigger: revealed) { _, isRevealed in isRevealed ? .impact(weight: .light, intensity: 0.6) : nil }
        .onDisappear {
            if let c = current { material.lastLine = c }
            translation.cancel()
            player.stop(); app.jumpMaterial = nil
        }
        .onChange(of: app.jumpMaterial?.time) { _, _ in
            guard let jump = app.jumpMaterial, jump.id == material.id.uuidString,
                  let position = Subtitles.index(at: jump.time, in: lines) else { return }
            player.seek(lines[position].start)
            app.jumpMaterial = nil
        }
        .onChange(of: translation.error) { _, value in banner = value }
        .onChange(of: nativeLanguage) { _, _ in translation.cancel(); if showTranslation { translateAll() } }
        .onChange(of: material.languageCode) { _, _ in translation.cancel(); if showTranslation { translateAll() } }
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
                Button { withAnimation(ReaderMotion.veil(reduceMotion: reduceMotion)) { furigana.toggle() } } label: {
                    Label(furigana ? L10n.string("read.furiganaHide") : L10n.string("read.furiganaShow"), systemImage: "textformat.size.ja")
                }
            }
            Picker(selection: Binding(get: { translationMode }, set: { mode in
                let starting = translationMode == .off && mode != .off
                withAnimation(ReaderMotion.veil(reduceMotion: reduceMotion)) { translationMode = mode; revealed = false }
                if starting { translateAll() }
            })) {
                ForEach(ReaderTranslation.allCases) { mode in Text(mode.label).tag(mode) }
            } label: { Label("Translation", systemImage: "character.bubble") }
            .pickerStyle(.menu)
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
                Text(material.contentError ?? L10n.string("No subtitles found")).font(Theme.Fonts.body.weight(.semibold))
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
            let stageHeight = geometry.size.height
            ScrollViewReader { proxy in
                ScrollView {
                    ReaderStudyLayout(stageHeight: stageHeight) {
                        let shown = displayIndex
                        VStack(alignment: .leading, spacing: 24) {
                            // Each line keeps its identity as its role changes, so it moves with the reading flow.
                            ForEach(Array(max(0, shown - 1)...min(lines.count - 1, shown + 1)), id: \.self) { i in
                                if i == shown {
                                    currentLine(i).transition(ReaderMotion.focus(forward: forward, reduceMotion: reduceMotion))
                                } else {
                                    neighbour(i).transition(ReaderMotion.context(forward: forward, reduceMotion: reduceMotion))
                                }
                            }
                        }
                        .frame(maxWidth: 640, alignment: .leading)
                        .onGeometryChange(for: Bool.self) { group in
                            group.size.height > stageHeight
                        } action: { overflows in
                            stageOverflows = overflows
                            if overflows { revealCurrent(using: proxy) }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .defaultScrollAnchor(.top)
                .onChange(of: shownIndex) { _, _ in
                    if stageOverflows { revealCurrent(using: proxy) }
                }
            }
        }
    }

    private func revealCurrent(using proxy: ScrollViewProxy) {
        guard lines.indices.contains(displayIndex) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { proxy.scrollTo(lines[displayIndex].id, anchor: .top) }
    }

    private func go(_ i: Int) {
        guard lines.indices.contains(i) else { return }
        manualSteps += 1
        player.seek(lines[i].start)
    }

    private func neighbour(_ i: Int) -> some View {
        let l = lines[i]
        return Text(l.text).literary(.body, material.languageCode == "ja" ? .original : .interface).foregroundStyle(Theme.textSecondary)
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
            if hasMedia { SpokenStroke(player: player, start: line.start, end: line.end).padding(.top, -12) }
            if showTranslation, line.translationSource == material.languageCode, line.translationTarget == nativeLanguage, let t = line.translation {
                TranslationGloss(text: t, veiled: translationMode == .veiled && !revealed) {
                    guard translationMode == .veiled else { return }
                    withAnimation(ReaderMotion.veil(reduceMotion: reduceMotion)) { revealed.toggle() }
                }
                .transition(.opacity)
            } else if showTranslation && translation.running {
                Label { Text("read.translation.loading") } icon: { ProgressView() }
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            }
            if let n = line.note { Label(n, systemImage: "note.text").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isSelected)
        .accessibilityValue(L10n.format("read.position", Int64(i + 1), Int64(lines.count)))
        .accessibilityIdentifier("reader-current-line")
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
                    ZStack {
                        Image(systemName: "play.fill").offset(x: 1)
                            .opacity(player.playing ? 0 : 1)
                            .scaleEffect(player.playing ? 0.25 : 1)
                            .blur(radius: player.playing && !reduceMotion ? 4 : 0)
                        Image(systemName: "pause.fill")
                            .opacity(player.playing ? 1 : 0)
                            .scaleEffect(player.playing ? 1 : 0.25)
                            .blur(radius: player.playing || reduceMotion ? 0 : 4)
                    }
                    .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: player.playing)
                    .font(.system(.title2, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(width: 56, height: 56).background(Theme.accent, in: Circle())
                }
                .buttonStyle(PressFeedbackStyle())
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
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))
        .frame(maxWidth: 680, minHeight: 88)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private func target(_ w: String, _ line: SubLine, kind: String = "word") -> WordTarget {
        WordTarget(word: w, sentence: line.text, kind: kind, materialID: material.id.uuidString, materialTitle: material.title, time: line.start, end: line.end, mediaFile: material.mediaFile, translation: line.translationSource == material.languageCode && line.translationTarget == nativeLanguage ? line.translation : nil, languageCode: material.languageCode)
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
        guard !lines.isEmpty else { return }
        banner = nil
        translation.start(material, target: nativeLanguage, context: ctx)
    }

    private func exportFile() -> URL {
        let u = URL.temporaryDirectory.appending(path: "\(material.title).srt")
        try? Subtitles.srt(lines).write(to: u, atomically: true, encoding: .utf8)
        return u
    }
}
