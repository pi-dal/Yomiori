import Foundation
import SwiftData
import Testing
@testable import Yomiori

@MainActor struct WordProgressionTests {
    private func word(_ id: String, _ level: String, senses: Int = 1, collocations: Int = 2) -> AtlasWord {
        var word = AtlasWord(id: id, term: id, senses: (0..<senses).map { _ in .init(partOfSpeech: "n.", definition: "d", translation: "t") },
                             examples: [], level: level, topic: "t")
        word.collocations = (0..<collocations).map { "c\($0)" }
        return word
    }

    private func reviewed(_ level: String, lapses: Int = 0, ease: Double = 2.5) -> Card {
        let card = Card(sentence: "s", word: UUID().uuidString)
        card.languageCode = "en"; card.wordLevel = level; card.reps = 3; card.lapses = lapses; card.ease = ease
        return card
    }

    @Test func difficultyRisesAcrossAndWithinLevels() {
        let words = [word("rare", "B1", senses: 1, collocations: 2), word("common", "B1", senses: 3, collocations: 4),
                     word("middle", "B1", senses: 2, collocations: 3), word("next", "B2", senses: 3, collocations: 4),
                     word("unlevelled", "N3")]
        let d = WordProgression.difficulties(words)
        #expect(d["unlevelled"] == nil)
        #expect(d["common"]! < d["middle"]! && d["middle"]! < d["rare"]!)
        #expect(d["rare"]! < 3 && d["next"]! >= 3)
        #expect(d.values.allSatisfy { $0 >= 2 && $0 < 4 })
    }

    @Test func abilityStartsAtTheFloorAndFollowsRecall() {
        let start = WordProgression.ability(cards: [], language: "en", floor: 2)
        #expect(abs(start - WordProgression.targetGap - 2) < 0.01)
        let steady = WordProgression.ability(cards: (0..<5).map { _ in reviewed("B1") }, language: "en", floor: 2)
        let easy = WordProgression.ability(cards: (0..<5).map { _ in reviewed("B1", ease: 2.65) }, language: "en", floor: 2)
        let struggling = WordProgression.ability(cards: (0..<5).map { _ in reviewed("B1", lapses: 1, ease: 2.3) }, language: "en", floor: 2)
        #expect(steady > start && easy > steady && struggling < start)
        // One day of five recalled words moves the target gradually, by well under one level.
        #expect(steady - start < 0.5 && easy - start < 0.75)
        // Other languages and unreviewed cards are not evidence.
        let unrelated = reviewed("C1"); unrelated.languageCode = "ja"
        let unseen = reviewed("C1"); unseen.reps = 0
        #expect(WordProgression.ability(cards: [unrelated, unseen], language: "en", floor: 2) == start)
    }

    @Test func nextWordsAscendFromTheTargetAndFallBackBelowIt() {
        let difficulty = ["a": 2.1, "b": 2.4, "c": 2.6, "d": 2.8, "e": 3.3]
        let words = ["e", "a", "d", "b", "c"].map { word($0, "B1") }
        #expect(WordProgression.next(words, count: 3, difficulties: difficulty, target: 2.5).map(\.id) == ["c", "d", "e"])
        // Only two words remain above the target: the hardest one below it fills the gap, still easiest first.
        #expect(WordProgression.next(words, count: 3, difficulties: difficulty, target: 2.7).map(\.id) == ["c", "d", "e"])
        #expect(WordProgression.next(words, count: 0, difficulties: difficulty, target: 2).isEmpty)
        // Lists without levels keep their own order.
        #expect(WordProgression.next(words, count: 2, difficulties: [:], target: 2).map(\.id) == ["e", "a"])
    }

    @Test func bundledListProgressesGraduallyAsWordsAreRecalled() throws {
        let store = try ModelContainer(for: Card.self, DictEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = store.mainContext
        defer { withExtendedLifetime(store) {} }
        let d = UserDefaults(suiteName: "WordProgressionTests.\(UUID())")!
        d.set("en", forKey: "targetLang"); d.set(5, forKey: "study.newLimit")
        let url = try #require(Bundle.main.url(forResource: "word-atlas", withExtension: "json"))
        let document = try WordListDocument.decodeValidated(Data(contentsOf: url))
        let difficulty = WordProgression.difficulties(document.entries)
        var day = Date(timeIntervalSince1970: 1_793_707_200)
        var averages: [Double] = []
        for _ in 0..<8 {
            try DailyStudy.prepare(context: context, documents: [document], defaults: d, now: day)
            let fresh = try context.fetch(FetchDescriptor<Card>()).filter { $0.reps == 0 }
                .sorted { $0.createdAt < $1.createdAt }
            #expect(fresh.count == 5)
            let values = fresh.map { difficulty[$0.wordListEntryID]! }
            #expect(values == values.sorted())
            #expect(values.allSatisfy { $0 >= 2 })
            averages.append(values.reduce(0, +) / Double(values.count))
            // The learner does the day's reviews and recalls every word.
            let due = try context.fetch(FetchDescriptor<Card>()).filter { $0.reps > 0 && $0.due <= day }
            for card in due + fresh { try DailyStudy.rate(card, rating: .good, context: context, now: day) }
            day = day.addingTimeInterval(86_400)
        }
        #expect(averages.first! < 2.15)
        #expect(zip(averages, averages.dropFirst()).allSatisfy { $1 >= $0 && $1 - $0 < 0.4 })
        #expect(averages.last! > 2.6)
    }
}
