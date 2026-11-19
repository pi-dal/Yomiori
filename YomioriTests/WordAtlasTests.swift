import Foundation
import SwiftData
import Testing
@testable import Yomiori

struct WordAtlasTests {
    @Test @MainActor func savingALocalLookupDeduplicatesByLanguageAndRespectsAutoCard() throws {
        let container = try ModelContainer(for: DictEntry.self, Card.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let data = try Data(contentsOf: #require(Bundle.main.url(forResource: "word-atlas", withExtension: "json")))
        let document = try WordListDocument.decodeValidated(data)
        let word = try #require(document.entries.first)
        let hits = QuickDictionary.search("  " + word.w.uppercased() + "  ", language: "en", saved: [], documents: [document])
        let exact = try #require(hits.first)
        #expect(exact.term == word.w)
        try QuickDictionary.save(exact, context: context)
        try QuickDictionary.save(exact, context: context)
        var japanese = exact; japanese.language = "ja"
        try QuickDictionary.save(japanese, context: context, autoCard: false)
        let saved = try context.fetch(FetchDescriptor<DictEntry>())
        #expect(saved.map(\.languageCode).sorted() == ["en", "ja"])
        let cards = try context.fetch(FetchDescriptor<Card>())
        #expect(cards.map(\.word) == [word.w] && cards.first?.languageCode == "en")
        #expect(QuickDictionary.search(word.w, language: "en", saved: saved, documents: [document]).filter { QuickDictionary.normalized($0.term) == QuickDictionary.normalized(word.w) }.count == 1)
    }

    @Test @MainActor func bundledIELTSListIsCompleteAndSearchable() async throws {
        let store = WordAtlasStore()
        await store.load()
        #expect(store.error == nil)
        #expect(store.words.count == 7298)
        #expect(store.filtered(search: "MOTIVATE", level: "B2", topic: "education").contains { $0.w == "motivate" })
        #expect(store.filtered(search: "no-match-zzzzzzzz", level: "", topic: "").isEmpty)
    }
}
