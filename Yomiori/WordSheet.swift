import SwiftUI
import SwiftData

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
    @State private var lookupTask: Task<Void, Never>?
    @State private var miningTask: Task<Void, Never>?
    @State private var operationError: String?

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
            .onDisappear { lookupTask?.cancel(); miningTask?.cancel() }
            .alert("Couldn't save", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(operationError ?? "") }
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
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                toast = hasAudio ? L10n.string("read.savedAudio") : L10n.string("read.savedNoAudio")
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                operationError = error.localizedDescription
            }
        }
    }
    private func toggle() {
        do { try CardMining.toggle(target, meaning: entry?.meaning ?? "", context: ctx) }
        catch { operationError = error.localizedDescription }
    }
}
