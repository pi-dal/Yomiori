import Foundation
import SwiftData
import Testing
@testable import Yomiori

@MainActor struct ReviewFlowTests {
    private var now: Date { Date(timeIntervalSince1970: 1_793_707_200) }
    private let ids = (0..<6).map { _ in UUID() }

    @Test func newWordsAreMetInContextThenRecalledAfterOtherCards() {
        var flow = ReviewSessionQueue([(ids[0], true), (ids[1], false), (ids[2], false), (ids[3], false)])
        #expect(flow.step == .intro && flow.current?.id == ids[0])
        flow.finishIntro()
        #expect(flow.items.map(\.id) == [ids[1], ids[2], ids[3], ids[0]])
        #expect(flow.step == .recall && flow.finished == 0)
        for _ in 0..<3 { flow.record(correct: true) }
        #expect(flow.current?.id == ids[0] && flow.step == .recall)
        flow.record(correct: true)
        #expect(flow.isEmpty && flow.finished == 4 && flow.total == 4)
        #expect(flow.recalled.count == 4 && flow.newWords == [ids[0]] && flow.missed.isEmpty)
    }

    @Test func missedWordReturnsAfterAGapAndRetriesAreBounded() {
        var flow = ReviewSessionQueue([(ids[0], false), (ids[1], false), (ids[2], false), (ids[3], false), (ids[4], false)])
        #expect(flow.record(correct: false) == .returnsLater)
        #expect(flow.items.map(\.id) == [ids[1], ids[2], ids[3], ids[0], ids[4]])
        #expect(flow.finished == 0 && flow.missed == [ids[0]])

        var alone = ReviewSessionQueue([(ids[5], false)])
        for _ in 1..<ReviewSessionQueue.maximumMisses {
            #expect(alone.record(correct: false) == .returnsLater)
            #expect(alone.current?.id == ids[5])
        }
        #expect(alone.record(correct: false) == .finished)
        #expect(alone.isEmpty && alone.finished == 1 && alone.recalled.isEmpty && alone.missed == [ids[5]])
    }

    @Test func duplicateCardsAppearOnceAndIntroCannotBeSkippedByRecording() {
        var flow = ReviewSessionQueue([(ids[0], true), (ids[0], true)])
        #expect(flow.total == 1)
        #expect(flow.record(correct: true) == .finished)
        #expect(flow.current?.needsIntro == true && flow.finished == 0)
    }

    @Test func recallOutcomeMapsToOneScheduleChangePerState() {
        #expect(ReviewSessionQueue.rating(correct: true, priorMisses: 0) == .good)
        #expect(ReviewSessionQueue.rating(correct: true, priorMisses: 0, adjustment: .easy) == .easy)
        #expect(ReviewSessionQueue.rating(correct: true, priorMisses: 0, adjustment: .hard) == .hard)
        #expect(ReviewSessionQueue.rating(correct: false, priorMisses: 0) == .again)
        #expect(ReviewSessionQueue.rating(correct: false, priorMisses: 1) == nil)
        // Adjustments only apply to a clean first recall.
        #expect(ReviewSessionQueue.rating(correct: true, priorMisses: 1, adjustment: .easy) == .good)
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
        #expect(flow.isEmpty && card.lapses == 1 && card.reps == 5)
        #expect(StudyPlan(cards: [card], reviewLimit: 10, newLimit: 0, now: now).completed == 1)
        #expect(card.due > now.addingTimeInterval(86_400))
    }

    @Test func meaningChoicesIncludeTheAnswerOnceAndStayInTheLanguage() {
        let card = Card(sentence: "s", word: "w"); card.meaning = "quiet"; card.languageCode = "ja"
        let others = ["Quiet ", "café", "to read", "every day", "to remember", "bright"].map { meaning -> Card in
            let other = Card(sentence: meaning, word: meaning); other.meaning = meaning; other.languageCode = "ja"; return other
        }
        let english = Card(sentence: "e", word: "e"); english.meaning = "english only"; english.languageCode = "en"
        for _ in 0..<20 {
            let options = MeaningChoices.make(answer: card.meaning, card: card, among: [card, english] + others, meaning: \.meaning)
            #expect(options.count == 4)
            #expect(options.filter { MeaningChoices.normalized($0) == "quiet" } == ["quiet"])
            #expect(Set(options).count == 4 && !options.contains("english only"))
        }
        #expect(MeaningChoices.make(answer: card.meaning, card: card, among: [card, english], meaning: \.meaning).isEmpty)
        #expect(MeaningChoices.make(answer: " ", card: card, among: others, meaning: \.meaning).isEmpty)
    }

    @Test func meaningChoicesPreferTheSameListAndLevel() {
        let card = Card(sentence: "s", word: "w"); card.meaning = "calm"; card.wordListID = "list"; card.wordLevel = "B1"
        let close = ["mild", "kind", "warm"].map { meaning -> Card in
            let other = Card(sentence: meaning, word: meaning); other.meaning = meaning
            other.wordListID = "list"; other.wordLevel = "B1"; return other
        }
        let far = (0..<20).map { index -> Card in
            let other = Card(sentence: "\(index)", word: "\(index)")
            other.meaning = "a considerably longer unrelated explanation \(index)"; return other
        }
        // With two options the window holds the two best candidates, so the distractor must be a close one.
        for _ in 0..<20 {
            let options = MeaningChoices.make(answer: "calm", card: card, among: far + close, meaning: \.meaning, count: 2)
            #expect(options.count == 2 && options.contains("calm"))
            #expect(options.allSatisfy { $0 == "calm" || ["mild", "kind", "warm"].contains($0) })
        }
    }

    @Test func sessionSummaryReturnsToTheMostFrequentExistingSource() {
        func card(_ kind: String, _ id: String, _ position: Double) -> Card {
            let c = Card(sentence: "s", word: "w"); c.sourceKind = kind; c.sourceID = id; c.sourcePos = position; return c
        }
        let cards = [card("pdf", "doc", 3), card("subtitle", "gone", 1), card("subtitle", "m", 12),
                     card("subtitle", "m", 40), card("pdf", "doc", 9), card("subtitle", "gone", 2), card("coach", "x", 0)]
        #expect(ReviewSource.mostFrequent(cards, materials: ["m"], documents: ["doc"]) == .document(id: "doc", page: 3))
        #expect(ReviewSource.mostFrequent(cards + [card("subtitle", "m", 50)], materials: ["m"], documents: ["doc"]) == .material(id: "m", position: 12))
        #expect(ReviewSource.mostFrequent(cards, materials: [], documents: []) == nil)
    }
}
