import Foundation
import SwiftData

@MainActor enum CardMining {
    /// Prepare optional enrichments before creating models. Only a current task can commit.
    static func mine(_ target: ReaderView.WordTarget, entry: Words.Entry, japaneseDefinition: Bool, context: ModelContext) async throws -> Bool {
        let generation = Operations.shared.generation
        try Operations.shared.checkpoint(generation)
        var audioName: String?
        var committed = false
        defer {
            if !committed, let audioName { try? FileManager.default.removeItem(at: Files.url(audioName)) }
        }
        if let media = target.mediaFile {
            try FileManager.default.createDirectory(at: Files.dir, withIntermediateDirectories: true)
            let name = "card-\(UUID().uuidString).m4a"
            audioName = name
            let success = await Clip.export(media: Files.url(media), start: target.time, end: target.end, to: Files.url(name))
            try Operations.shared.checkpoint(generation)
            if !success { try? FileManager.default.removeItem(at: Files.url(name)); audioName = nil }
        }
        let definition = japaneseDefinition && target.languageCode == "ja" ? await Words.definitionJa(target.word, sentence: target.sentence) : ""
        try Operations.shared.checkpoint(generation)
        // Re-check at commit; another sheet may have mined the same target meanwhile.
        let word = target.word, sentence = target.sentence, source = target.materialID
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.word == word && $0.sentence == sentence && $0.sourceID == source })
        descriptor.fetchLimit = 1
        if try !context.fetch(descriptor).isEmpty { return false }
        let card = Card(sentence: sentence, word: word)
        card.reading = Words.reading(word) ?? ""; card.meaning = entry.meaning; card.translation = target.translation ?? ""
        card.languageCode = target.languageCode; card.definitionJa = definition; card.audioFile = audioName
        card.sourceID = source; card.sourceName = target.materialTitle; card.sourcePos = target.time
        context.insert(card)
        var saved: DictEntry?
        do {
            let existing = try context.fetch(FetchDescriptor<DictEntry>(predicate: #Predicate { $0.term == word && $0.sourceID == source && $0.kind != "highlight" }))
            if existing.isEmpty {
                let value = makeEntry(target, meaning: entry.meaning); context.insert(value); saved = value
            }
            try context.save(); committed = true
            return audioName != nil
        } catch {
            context.delete(card); if let saved { context.delete(saved) }
            throw error
        }
    }
    static func toggle(_ target: ReaderView.WordTarget, meaning: String, context: ModelContext) throws {
        try Operations.shared.checkpoint(Operations.shared.generation)
        let word = target.word, source = target.materialID
        let existing = try context.fetch(FetchDescriptor<DictEntry>(predicate: #Predicate { $0.term == word && $0.sourceID == source && $0.kind != "highlight" }))
        if let entry = existing.first {
            context.delete(entry)
            do { try context.save() } catch { context.rollback(); throw error }
        } else {
            let entry = makeEntry(target, meaning: meaning); context.insert(entry)
            do { try context.save() } catch { context.delete(entry); throw error }
        }
    }
    private static func makeEntry(_ target: ReaderView.WordTarget, meaning: String) -> DictEntry {
        let entry = DictEntry(term: target.word, kind: target.kind, sourceKind: "subtitle")
        entry.reading = Words.reading(target.word) ?? ""; entry.meaning = meaning; entry.context = target.sentence
        entry.languageCode = target.languageCode; entry.sourceID = target.materialID
        entry.sourceName = target.materialTitle; entry.sourcePos = target.time
        return entry
    }
}
