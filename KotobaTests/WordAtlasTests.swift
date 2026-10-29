import Foundation
import SwiftData
import Testing
@testable import Kotoba

struct WordAtlasTests {
    @Test @MainActor func corpusAndFilters() async throws {
        let store = WordAtlasStore()
        await store.load()
        #expect(store.error == nil)
        #expect(store.words.count == 7298)
        #expect(Set(store.words.map(\.id)).count == 7298)
        #expect(store.levels == ["A1", "A2", "B1", "B2", "C1", "C2"])
        #expect(store.topics.count == 19)
        #expect(store.filtered(search: "", level: "B2", topic: "education").count == 110)
        #expect(store.filtered(search: "MOTIVATE", level: "B2", topic: "education").contains { $0.w == "motivate" })
        #expect(store.filtered(search: "no-match-zzzzzzzz", level: "", topic: "").isEmpty)
    }

    @Test @MainActor func insertionDeduplicatesAndPreservesJapanese() async throws {
        let store = WordAtlasStore()
        await store.load()
        let first = try #require(store.words.first)
        let container = try ModelContainer(for: Card.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let japanese = Card(sentence: "日本語の文", word: "日本語")
        japanese.interval = 7
        context.insert(japanese)
        try context.save()
        #expect(try IELTSCardWriter.add([first, first], context: context) == 1)
        #expect(try IELTSCardWriter.add([first], context: context) == 0)
        let cards = try context.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 2)
        let english = try #require(cards.first { $0.wordListEntryID == first.id })
        #expect(english.languageCode == "en")
        #expect(english.wordListID == "ielts")
        #expect(!english.definitionEnglish.isEmpty)
        #expect(english.definitionJa.isEmpty)
        #expect(japanese.languageCode == "ja")
        #expect(japanese.interval == 7)
        #expect(japanese.wordListID.isEmpty)
    }
}
