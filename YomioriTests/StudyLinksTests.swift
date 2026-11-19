import Foundation
import SwiftData
import Testing
@testable import Yomiori

@MainActor struct StudyLinksTests {
    private var now: Date { Date(timeIntervalSince1970: 1_793_707_200) }
    private func card(_ word: String, _ language: String = "ja", reps: Int = 0, interval: Double = 0) -> Card {
        let c = Card(sentence: word, word: word); c.languageCode = language; c.reps = reps; c.interval = interval; return c
    }

    @Test func japaneseCardWordsAreRecognisedInInflectedForms() {
        let yomu = card("読む"), oboeru = card("覚える"), shizuka = card("静か"), benkyou = card("勉強する")
        let lexicon = StudyLexicon(cards: [yomu, oboeru, shizuka, benkyou, card("読む", "en")], language: "ja")
        #expect(lexicon.card(for: "読む") === yomu)
        #expect(lexicon.card(for: "読も") === yomu && lexicon.card(for: "読みます") === yomu && lexicon.card(for: "読んだ") === yomu)
        #expect(lexicon.card(for: "覚えます") === oboeru && lexicon.card(for: "静か") === shizuka)
        #expect(lexicon.card(for: "勉強") === benkyou && lexicon.card(for: "勉強します") === benkyou)
        // A shared kanji is not enough: 読書 is a different word, and the bare stem 読 is not 読む.
        #expect(lexicon.card(for: "読書") == nil && lexicon.card(for: "読") == nil && lexicon.card(for: "静") == nil)
        #expect(StudyLexicon.occurrence(of: yomu, in: "今日は何を読もうか。")?.hasPrefix("読") == true)
    }

    @Test func englishCardWordsMatchTheirInflections() {
        let remember = card("remember", "en")
        let lexicon = StudyLexicon(cards: [remember], language: "en")
        #expect(lexicon.card(for: "Remember") === remember)
        #expect(lexicon.card(for: "remembered") === remember)
        #expect(lexicon.card(for: "member") == nil)
    }

    @Test func coachFocusesOnTodaysMissedThenNewWords() {
        let old = card("古い"); old.createdAt = now.addingTimeInterval(-9_000)
        let recent = card("新しい"); recent.createdAt = now.addingTimeInterval(-60)
        let missed = card("難しい"); missed.lapses = 2; missed.lastReviewedAt = now.addingTimeInterval(-30); missed.createdAt = now.addingTimeInterval(-90_000)
        let met = card("会う"); met.firstReviewedAt = now.addingTimeInterval(-40); met.lastReviewedAt = met.firstReviewedAt; met.createdAt = now.addingTimeInterval(-80_000)
        let english = card("hard", "en"); english.lapses = 3; english.lastReviewedAt = now
        let focus = CoachFocus.words([old, recent, missed, met, english, card("新しい")], language: "ja", now: now)
        #expect(focus.map(\.word) == ["難しい", "会う", "新しい", "古い"])
        #expect(CoachFocus.words([old, recent], language: "ja", now: now, limit: 1).map(\.word) == ["新しい"])
    }

    @Test func correctionBecomesOneCardInTheLearnersSentence() throws {
        let store = try ModelContainer(for: Card.self, ChatMsg.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext
        let message = ChatMsg(role: "user", content: "昨日、友達を公園に行きました"); message.languageCode = "ja"
        context.insert(message)
        let correction = Correction(category: "Particles", pattern: "に vs を", wrong: "友達を", right: "友達と", reason: "with a friend")
        let added = try #require(try CorrectionCards.add(correction, message: message, context: context, now: now))
        #expect(added.sentence == "昨日、友達と公園に行きました")
        #expect(added.word == "友達と" && added.sourceKind == "coach" && added.reps == 0 && added.due == now)
        #expect(added.meaning.contains("with a friend") && added.meaning.contains("友達を"))
        #expect(try CorrectionCards.add(correction, message: message, context: context) == nil)
        let cards = try context.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 1)
        #expect(StudyPlan(cards: cards, reviewLimit: 10, newLimit: 5, language: "ja", now: now).queue.count == 1)
    }

    @Test func missedDaysNeverResetProgressAndPhasesFollowActivity() throws {
        let d = UserDefaults(suiteName: "StudyLinksTests.\(UUID())")!
        let calendar = Calendar.current
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: now)! }
        // Activity on five separate days in the last week, with gaps, plus one old day.
        var logs: [ImmersionLog] = []
        for offset in [0, 2, 3, 5, 6, 20] { logs.append(ImmersionLog(day: calendar.startOfDay(for: day(offset)), seconds: 600, kind: "reading")) }
        let stuck = (0..<3).map { index -> Card in let c = card("語\(index)", reps: 6, interval: 30); c.lastCompletedAt = day(1); return c }
        let snapshot = LearningJourneySnapshot.make(cards: stuck, logs: logs, entries: [], messages: [], defaults: d, now: now)
        #expect(snapshot.activeDays == 7 && snapshot.activeDaysThisWeek == 6)
        #expect(snapshot.wordsStuck == 3 && snapshot.phase == .understanding)
        #expect(snapshot.tracks.first { $0.kind == .activeDays }?.reached == 7)
        let early = LearningJourneySnapshot.make(cards: [], logs: Array(logs.prefix(2)), entries: [], messages: [], defaults: d, now: now)
        #expect(early.activeDays == 2 && early.phase == .foundation)
    }
}
