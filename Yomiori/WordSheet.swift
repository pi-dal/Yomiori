import SwiftUI
import SwiftData

struct WordSheet: View {
    let target: ReaderView.WordTarget
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var saved: [DictEntry]
    @Query private var cards: [Card]
    @AppStorage("jaDefs") private var jaDefs = false
    @AppStorage("study.autoCards") private var autoCards = true
    @State private var entry: Words.Entry?
    @State private var failed = false
    @State private var toast: String?
    @State private var busy = false
    @State private var lookupTask: Task<Void, Never>?
    @State private var miningTask: Task<Void, Never>?
    @State private var operationError: String?

    var isSaved: Bool { saved.contains { $0.term == target.word && $0.sourceID == target.materialID && $0.kind != "highlight" } }
    private var canMine: Bool { target.kind == "word" }
    @Query private var minedCards: [Card]
    private var mined: Bool { !minedCards.isEmpty }

    init(target: ReaderView.WordTarget) {
        self.target = target
        _minedCards = Query(filter: CardMining.predicate(word: target.word, sentence: target.sentence, source: target.materialID))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(target.word).literary(.title1, bold: true, .original)
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
                    } else { MeaningPlaceholder() }
                    if let card = studiedCard { studyNote(card) }
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
                                Text(toast ?? (mined ? L10n.string("read.mined") : L10n.string(autoCards ? "study.saveAndReview" : "read.mine")))
                            }
                        }
                        .buttonStyle(InkButtonStyle()).disabled(busy || mined || entry == nil)
                        if !autoCards {
                            Button { toggle() } label: {
                                Text(isSaved ? L10n.string("read.saved") : L10n.string("read.saveWord"))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .accessibilityAddTraits(isSaved ? .isSelected : [])
                        }
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
            .onDisappear {
                lookupTask?.cancel(); miningTask?.cancel()
                if let clipURLPreview { try? FileManager.default.removeItem(at: clipURLPreview) }
                clipURLPreview = nil
            }
            .alert("Couldn't save", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(operationError ?? "") }
        }
    }

    /// The word already has a card, possibly from another source: meeting it again is part of learning it.
    private var studiedCard: Card? {
        guard target.kind == "word" else { return nil }
        return StudyLexicon(cards: cards, language: target.languageCode).card(for: target.word)
    }

    private func studyNote(_ card: Card) -> some View {
        let known = StudyLexicon.stage(card) == .known
        let elsewhere = card.sentence.trimmingCharacters(in: .whitespacesAndNewlines) != target.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            Label(known ? "read.studyKnown" : "read.studyLearning", systemImage: known ? "checkmark.seal" : "leaf")
                .font(Theme.Fonts.meta.weight(.semibold)).foregroundStyle(Theme.accent)
            if elsewhere {
                Text("read.metBefore").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                Text(card.sentence).literary(.body, .original)
                if !card.sourceName.isEmpty { Text(verbatim: card.sourceName).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
            }
            if card.reps > 0 {
                Text(L10n.format("read.nextReview", card.due.formatted(.dateTime.month().day())))
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 2) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("read.studyNote")
    }

    /// The sentence the word was met in. Once the word has a card, the reader's study stroke is drawn beneath it;
    /// saving draws it left to right, so the learner sees the mark they will meet again while reading.
    private var observedSentence: some View {
        let stage = studiedCard.map(StudyLexicon.stage)
        return markedSentence
            .font(Theme.Fonts.body)
            .textRenderer(BrushStrokeRenderer(progress: stage == nil ? 0 : 1, known: stage == .known, reduceMotion: reduceMotion))
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .timingCurve(0.16, 1, 0.3, 1, duration: 0.6).delay(0.1), value: stage == nil)
    }

    private var markedSentence: Text {
        let sentence = target.sentence
        guard !target.word.isEmpty, let range = sentence.range(of: target.word) else { return Text(verbatim: sentence) }
        var word = AttributedString(String(sentence[range]))
        word.backgroundColor = Theme.highlight
        return Text("\(Text(verbatim: String(sentence[..<range.lowerBound])))\(Text(word).customAttribute(StudyWordAttribute()))\(Text(verbatim: String(sentence[range.upperBound...])))")
    }
    @State private var clipURLPreview: URL?
    private func prepareClip() async {
        guard let f = target.mediaFile, canMine, target.time.isFinite, target.end.isFinite,
              target.time >= 0, target.end >= target.time, target.end <= Subtitles.maximumTime else { return }
        guard (try? FileManager.default.createDirectory(at: Files.temporaryDirectory, withIntermediateDirectories: true)) != nil else { return }
        let dest = Files.temporaryDirectory.appending(path: "clip-preview-\(UUID().uuidString).m4a")
        if await Clip.export(media: Files.url(f), start: target.time, end: target.end, to: dest), !Task.isCancelled {
            clipURLPreview = dest
        } else { try? FileManager.default.removeItem(at: dest) }
    }
    private func load() {
        lookupTask?.cancel(); failed = false
        lookupTask = Task {
            do {
                let value = try await Words.lookup(target.word, sentence: target.sentence, languageCode: target.languageCode)
                try Task.checkCancellation(); entry = value
            } catch { if !Task.isCancelled, !(error is CancellationError) { failed = true } }
        }
    }
    private func mine() {
        guard !busy, !mined, let entry else { return }
        busy = true
        miningTask = Task {
            defer { busy = false }
            do {
                let hasAudio = try await CardMining.mine(target, entry: entry, japaneseDefinition: jaDefs, context: ctx)
                try Task.checkCancellation()
                Haptic.kept()
                let message = hasAudio ? L10n.string("read.savedAudio") : L10n.string("read.savedNoAudio")
                toast = message
                AccessibilityNotification.Announcement(message).post()
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                operationError = error.localizedDescription
            }
        }
    }
    private func toggle() {
        let saving = !isSaved
        do {
            try CardMining.toggle(target, meaning: entry?.meaning ?? "", context: ctx, autoCard: autoCards)
            if saving { Haptic.kept() }
        }
        catch { operationError = error.localizedDescription }
    }
}
