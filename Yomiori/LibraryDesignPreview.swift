#if DEBUG
import SwiftUI
import SwiftData

/// Opt-in visual fixtures. The in-memory container never changes the learner's library.
struct LibraryDesignPreview: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @State private var seeded = false
    @State private var showSettings = false
    private let preferences: UserDefaults

    init() {
        let suite = "Yomiori.LibraryDesignPreview"
        preferences = UserDefaults(suiteName: suite)!
        preferences.removePersistentDomain(forName: suite)
    }

    /// A silent mono PCM WAV, so playback-driven reader states can be previewed without bundled audio.
    private static func silence(seconds: Int) -> Data {
        let rate: UInt32 = 8000, samples = UInt32(seconds) * rate
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples * 2).littleEndian)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(1).littleEndian); append(rate.littleEndian)
        append((rate * 2).littleEndian); append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        data.append(contentsOf: Array("data".utf8)); append((samples * 2).littleEndian)
        data.append(Data(count: Int(samples) * 2))
        return data
    }

    var body: some View {
        RootView()
            .defaultAppStorage(preferences)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task {
                guard !seeded else { return }
                seeded = true
                let arguments = ProcessInfo.processInfo.arguments
                if let flag = arguments.firstIndex(of: "--preview-tab"), flag + 1 < arguments.count {
                    app.tab = ["documents": .documents, "dictionary": .dictionary, "coach": .coach][arguments[flag + 1]] ?? .read
                }
                let reading = Material(title: "A quiet morning in Kyoto")
                reading.languageCode = "ja"
                reading.lines = [
                    SubLine(start: 0, end: 5, text: "京都の朝は、静かで美しい。"),
                    SubLine(start: 5, end: 10, text: "小さな喫茶店で、本を読みます。"),
                    SubLine(start: 10, end: 15, text: "今日は何を読もうか。")
                ]
                // Synthetic glosses for the bilingual reader; real translations come from the learner's AI service.
                for (index, gloss) in ["Mornings in Kyoto are quiet and beautiful.", "I read a book in a small café.", "What shall I read today?"].enumerated() {
                    reading.lines[index].translation = gloss
                    reading.lines[index].translationSource = "ja"
                    reading.lines[index].translationTarget = preferences.string(forKey: "nativeLang") ?? Language.deviceDefault
                }
                reading.lastLine = 1
                if arguments.contains("--preview-media") {
                    try? FileManager.default.createDirectory(at: Files.dir, withIntermediateDirectories: true)
                    try? Self.silence(seconds: 15).write(to: Files.url("design-preview.wav"))
                    reading.mediaFile = "design-preview.wav"
                }
                context.insert(reading)
                for title in ["At the little bookshop", "Everyday conversations"] {
                    let material = Material(title: title)
                    material.languageCode = "ja"; material.lines = reading.lines
                    context.insert(material)
                }
                for (term, kana, meaning) in [("木漏れ日", "こもれび", "Sunlight filtering through the trees"),
                                              ("喫茶店", "きっさてん", "A coffee shop; a café"),
                                              ("静か", "しずか", "Quiet; peaceful"),
                                              ("日常", "にちじょう", "Everyday life")] {
                    let entry = DictEntry(term: term, kind: "word", sourceKind: "subtitle")
                    entry.reading = kana; entry.meaning = meaning
                    entry.sourceName = reading.title; entry.sourceID = reading.id.uuidString
                    if term == "喫茶店" { entry.sourcePos = 5 }
                    context.insert(entry)
                }
                try? FileManager.default.createDirectory(at: Files.dir, withIntermediateDirectories: true)
                try? PDFReadingFixture.data().write(to: Files.url("design-preview.pdf"))
                let document = PDFDoc(title: "Language in context", fileName: "design-preview.pdf")
                document.pageCount = 2; document.languageCode = "en"
                if ProcessInfo.processInfo.arguments.contains("--library-invalid-position-preview") {
                    document.lastPage = 99
                }
                context.insert(document)
                if let flag = arguments.firstIndex(of: "--preview-open"), flag + 1 < arguments.count {
                    if arguments[flag + 1] == "reader" { app.jumpMaterial = (reading.id.uuidString, 5) }
                    if arguments[flag + 1] == "document" { app.jumpDoc = (document.id.uuidString, 0); app.tab = .documents }
                    if arguments[flag + 1] == "settings" { showSettings = true }
                }
                if ProcessInfo.processInfo.arguments.contains("--library-scale-preview") {
                    for index in 1...240 {
                        let material = Material(title: "Reading \(index)")
                        material.languageCode = "ja"; material.lines = reading.lines
                        material.createdAt = reading.createdAt.addingTimeInterval(-Double(index))
                        context.insert(material)
                        let extra = PDFDoc(title: "Document \(index)", fileName: "design-preview.pdf")
                        extra.pageCount = 2; extra.languageCode = "en"
                        extra.createdAt = document.createdAt.addingTimeInterval(-Double(index))
                        context.insert(extra)
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("--library-stress-preview") {
                    for (index, title) in ["Listening notes", "Everyday Japanese: a collection of conversations, observations and useful expressions", "Travel journal", "Weekend reading", "Preview unavailable"].enumerated() {
                        let fileName = "design-preview-\(index).pdf"
                        if index < 4 {
                            try? PDFReadingFixture.data(title: title, landscape: index == 0).write(to: Files.url(fileName))
                        } else {
                            try? FileManager.default.removeItem(at: Files.url(fileName))
                        }
                        let extra = PDFDoc(title: title, fileName: fileName)
                        extra.pageCount = 2; extra.languageCode = "ja"
                        extra.createdAt = document.createdAt.addingTimeInterval(-Double(index + 1))
                        context.insert(extra)
                    }
                }
            }
    }
}
#endif
