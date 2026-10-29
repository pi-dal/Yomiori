import Foundation
import ZIPFoundation

struct ExportCard: Sendable {
    let id: UUID
    let sentence: String
    let word: String
    let meaning: String
    let audioFile: String?
    @MainActor init(_ card: Card) {
        id = card.id; sentence = card.sentence; word = card.word
        meaning = [card.reading, card.meaning, card.translation].filter { !$0.isEmpty }.joined(separator: "\n")
        audioFile = card.audioFile
    }
    init(id: UUID = UUID(), sentence: String, word: String, meaning: String, audioFile: String? = nil) {
        self.id = id; self.sentence = sentence; self.word = word; self.meaning = meaning; self.audioFile = audioFile
    }
}
struct AnkiArtifact: Sendable {
    let directory: URL
    let files: [URL]
    let cardIDs: Set<UUID>
}
enum AnkiExporter {
    /// All files exist on success; failed builds remove their partial artifacts.
    static func build(_ cards: [ExportCard], audioDirectory: URL, outputDirectory: URL, progress: Progress = Progress()) throws -> AnkiArtifact {
        let directory = outputDirectory.appending(path: "anki-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try Task.checkCancellation()
            guard !progress.isCancelled else { throw CancellationError() }
            let staging = directory.appending(path: "contents", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            func escape(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            var csv = "sentence,word,meaning,audio\n"
            var copied = Set<String>()
            for card in cards {
                try Task.checkCancellation()
                guard !progress.isCancelled else { throw CancellationError() }
                var audio = ""
                if let name = card.audioFile {
                    guard name == (name as NSString).lastPathComponent, name != ".", name != ".." else { throw CocoaError(.fileReadInvalidFileName) }
                    if copied.insert(name).inserted {
                        let destination = staging.appending(path: name)
                        try FileManager.default.copyItem(at: audioDirectory.appending(path: name), to: destination)
                    }
                    audio = "[sound:\(name)]"
                }
                csv += [card.sentence, card.word, card.meaning, audio].map(escape).joined(separator: ",") + "\n"
            }
            try csv.write(to: staging.appending(path: "cards.csv"), atomically: true, encoding: .utf8)
            let instructions = """
            Yomiori — CSV and audio export

            This ZIP contains cards.csv and the referenced audio files. It is not an Anki .apkg deck.
            Extract the ZIP. Import cards.csv with Anki's text import and map the sentence, word,
            meaning and audio columns to your note type. Copy the audio files into the collection's
            media folder using your Anki installation's supported workflow.

            Yomiori — CSV 与音频导出

            此 ZIP 包含 cards.csv 和对应音频，不是 Anki .apkg 牌组。
            解压后在 Anki 中导入 CSV，将 sentence、word、meaning、audio 列映射到笔记字段，
            并按照你使用的 Anki 版本支持的方式将音频放入 collection.media 媒体目录。
            """
            try instructions.write(to: staging.appending(path: "README.txt"), atomically: true, encoding: .utf8)
            let archive = directory.appending(path: "Yomiori-Anki.zip")
            try FileManager.default.zipItem(at: staging, to: archive, shouldKeepParent: false, compressionMethod: .deflate, progress: progress)
            try Task.checkCancellation()
            guard !progress.isCancelled else { throw CancellationError() }
            try FileManager.default.removeItem(at: staging)
            return AnkiArtifact(directory: directory, files: [archive], cardIDs: Set(cards.map(\.id)))
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
