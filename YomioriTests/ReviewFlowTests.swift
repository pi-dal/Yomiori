import Foundation
import SwiftData
import Testing
@testable import Yomiori

@MainActor struct ReviewFlowTests {
    private var now: Date { Date(timeIntervalSince1970: 1_793_707_200) }

    @Test func repeatedMissesCannotKeepOneWordInPracticeForever() {
        let id = UUID()
        var flow = ReviewSessionQueue([(id, false)])
        for _ in 0..<10 where !flow.isEmpty { flow.record(correct: false) }
        #expect(flow.isEmpty && flow.recalled.isEmpty && flow.missed == [id])
    }

    @Test func missThenRecallCompletesTheCardWithOneLapse() throws {
        let store = try ModelContainer(for: Card.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        let card = Card(sentence: "s", word: "w"); card.reps = 3; card.interval = 12; card.due = now.addingTimeInterval(-60)
        context.insert(card); try context.save()
        var flow = ReviewSessionQueue([(card.id, false)])
        for attempt in [false, false, true] {
            let misses = flow.current?.misses ?? 0
            if let rating = ReviewSessionQueue.rating(correct: attempt, priorMisses: misses) {
                try DailyStudy.rate(card, rating: rating, context: context, now: now)
            }
            flow.record(correct: attempt)
        }
        #expect(flow.isEmpty && card.lapses == 1)
        #expect(StudyPlan(cards: [card], reviewLimit: 10, newLimit: 0, now: now).completed == 1)
        #expect(card.due > now)
    }

    @Test func meaningChoicesIncludeTheAnswerOnceAndStayInTheLanguage() {
        let card = Card(sentence: "s", word: "w"); card.meaning = "quiet"; card.languageCode = "ja"
        let others = ["Quiet ", "café", "to read", "every day", "to remember", "bright"].map { meaning -> Card in
            let other = Card(sentence: meaning, word: meaning); other.meaning = meaning; other.languageCode = "ja"; return other
        }
        let english = Card(sentence: "e", word: "e"); english.meaning = "english only"; english.languageCode = "en"
        let options = MeaningChoices.make(answer: card.meaning, card: card, among: [card, english] + others, meaning: \.meaning)
        #expect(options.count > 1 && Set(options).count == options.count)
        #expect(options.filter { MeaningChoices.normalized($0) == "quiet" } == ["quiet"])
        #expect(!options.contains("english only"))
        #expect(MeaningChoices.make(answer: card.meaning, card: card, among: [card, english], meaning: \.meaning).isEmpty)
        #expect(MeaningChoices.make(answer: " ", card: card, among: others, meaning: \.meaning).isEmpty)
    }

    @Test func sessionSummaryReturnsToTheMostFrequentExistingSource() {
        func card(_ kind: String, _ id: String, _ position: Double) -> Card {
            let c = Card(sentence: "s", word: "w"); c.sourceKind = kind; c.sourceID = id; c.sourcePos = position; return c
        }
        let cards = [card("pdf", "doc", 3), card("subtitle", "gone", 1), card("subtitle", "m", 12),
                     card("subtitle", "m", 40), card("pdf", "doc", 9), card("subtitle", "gone", 2), card("coach", "x", 0)]
        #expect(ReviewSource.mostFrequent(cards + [card("subtitle", "m", 50)], materials: ["m"], documents: ["doc"]) == .material(id: "m", position: 12))
        #expect(ReviewSource.mostFrequent(cards, materials: [], documents: []) == nil)
    }
}
