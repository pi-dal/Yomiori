#if DEBUG
import SwiftUI
import SwiftData

/// Opt-in, in-memory UI fixture. Never writes sample content to the learner's library.
struct ComponentPreview: View {
    @State private var tab = "Coach"
    @State private var lookup: String?
    @State private var export = false
    @State private var streaming = false
    @State private var furigana = true
    @State private var streamText = ""
    @Environment(\.modelContext) private var context
    @Query private var previewCards: [Card]
    private let reader = "今日は日本語を勉強します。新しい言葉を少しずつ覚えましょう。Hello 👩🏽‍💻 café。"
    private let answer = """
    ## A little practice, every day

    Read a short passage, then **say it in your own words**.

    今日は日本語を勉強します。
    （Today, I'll study Japanese.）

    | Word | Reading | Meaning |
    | --- | --- | --- |
    | 言葉 | ことば | Word |
    | 毎日 | まいにち | Every day |

    - Read for five minutes.
    - Save one useful phrase.
    - Try it in a conversation.

    > Small steps make a habit.

    ```text
    日本語 → Read → Practice
    ```
    """
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Preview", selection: $tab) {
                    Text("Coach").tag("Coach"); Text("Reader").tag("Reader")
                }.pickerStyle(.segmented).padding(24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if tab == "Coach" {
                            CoachMessageContent(text: streaming ? streamText : answer, isStreaming: streaming)
                            Button(streaming ? "Cancel" : "Stream preview") { streaming.toggle() }
                        } else {
                            Toggle("Furigana", isOn: $furigana)
                            TappableText(text: reader, language: "ja", furigana: furigana, pointSize: 28,
                                         lineSpacing: 8, washed: { $0 == "日本語" }) { lookup = $0 }
                            if let lookup { Text(verbatim: lookup).accessibilityIdentifier("preview.lookup") }
                            Text("Long press to select text. Tap a word to look it up.").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        }
                    }.frame(maxWidth: 640, alignment: .leading).padding(24).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Component preview").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Export") { export = true } }
            .safeAreaInset(edge: .bottom) {
                Text("Preview exported: \(previewCards.filter(\.exported).count)")
                    .font(.caption).accessibilityIdentifier("preview.exportedCount")
            }
            .sheet(isPresented: $export) { ExportSheet() }
            .background(Theme.background).foregroundStyle(Theme.ink).tint(Theme.ink)
            .task {
                guard (try? context.fetchCount(FetchDescriptor<Card>())) == 0 else { return }
                context.insert(Card(sentence: "日本語を勉強します。", word: "日本語"))
                try? context.save()
            }
            .task(id: streaming) {
                guard streaming else { return }
                streamText = ""
                do {
                    for character in answer {
                        try await Task.sleep(for: .milliseconds(12))
                        streamText.append(character)
                    }
                    streaming = false
                } catch { }
            }
        }
    }
}
#endif
