import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Yomiori

@MainActor struct DailyStudyTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Card.self, DictEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "DailyStudyTests.\(UUID())")! }
    private var now: Date { Date(timeIntervalSince1970: 1_793_707_200) }

    @Test func reviewsPrecedeNewCardsAndRepeatedVisitsRespectDailyBudget() throws {
        let store = try container(), context = store.mainContext
        defer { withExtendedLifetime(store) {} }
        let fresh = Card(sentence: "new", word: "new")
        let old = Card(sentence: "old", word: "old"); old.reps = 2
        old.due = now.addingTimeInterval(-100); fresh.due = now.addingTimeInterval(-10)
        context.insert(fresh); context.insert(old); try context.save()
        let p = StudyPlan(cards: [fresh, old], reviewLimit: 2, newLimit: 1, now: now)
        #expect(p.queue.map(\.word) == ["old", "new"])
        try DailyStudy.rate(old, rating: .good, context: context, now: now)
        try DailyStudy.rate(fresh, rating: .good, context: context, now: now)
        let complete = StudyPlan(cards: [fresh, old], reviewLimit: 2, newLimit: 1, now: now)
        #expect(complete.completed == 2 && complete.remaining == 0 && complete.queue.isEmpty)
        let tomorrow = StudyPlan(cards: [fresh, old], reviewLimit: 2, newLimit: 1, now: now.addingTimeInterval(86400))
        #expect(tomorrow.completed == 0 && tomorrow.remaining == 2)
    }

    @Test func journeySnapshotConnectsRealActivityToTheDailyLoop() throws {
        let store = try ModelContainer(for: Card.self, DictEntry.self, ImmersionLog.self, ChatMsg.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(store) {} }
        let context = store.mainContext, d = defaults()
        d.set("ja", forKey: "targetLang")
        d.set(60, forKey: "dailyGoal")
        let card = Card(sentence: "今日は読む", word: "読む")
        card.due = now
        context.insert(card)
        let log = ImmersionLog(day: Calendar.current.startOfDay(for: now), seconds: 3600, kind: "reading")
        let entry = DictEntry(term: "読む", kind: "word", sourceKind: "subtitle")
        entry.createdAt = now
        let message = ChatMsg(role: "user", content: "読む")
        message.createdAt = now
        context.insert(log); context.insert(entry); context.insert(message)
        try context.save()

        let beforeReview = LearningJourneySnapshot.make(cards: [card], logs: [log], entries: [entry], messages: [message], defaults: d, now: now)
        #expect(!beforeReview.reviewDone)
        #expect(beforeReview.immersionDone && beforeReview.discoveryDone)
        // Immersion, a saved word and a Coach message: three of the four anchors.
        #expect(beforeReview.todayStepsDone == 3 && LearningJourneySnapshot.anchorCount == 4)
        #expect(beforeReview.totalWords == 1 && beforeReview.coachMessages == 1)

        try DailyStudy.rate(card, rating: .good, context: context, now: now)
        let afterReview = LearningJourneySnapshot.make(cards: [card], logs: [log], entries: [entry], messages: [message], defaults: d, now: now)
        #expect(afterReview.reviewDone && afterReview.todayStepsDone == 4)
        #expect(afterReview.activeDays == 1 && afterReview.activeDaysThisWeek == 1 && afterReview.totalCoachMessages == 1)
    }
    @Test func againWaitsTenMinutesAndDoesNotConsumeAnotherNewSlot() throws {
        let store = try container(), context = store.mainContext
        defer { withExtendedLifetime(store) {} }
        let card = Card(sentence: "hello", word: "hello"); context.insert(card); try context.save()
        try DailyStudy.rate(card, rating: .again, context: context, now: now)
        let p = StudyPlan(cards: [card], reviewLimit: 10, newLimit: 1, now: now)
        #expect(p.queue.isEmpty && p.completed == 0 && p.newSlots == 0)
        #expect(p.nextLearningDate == now.addingTimeInterval(600))
        let later = StudyPlan(cards: [card], reviewLimit: 10, newLimit: 1, now: now.addingTimeInterval(601))
        #expect(later.queue.map(\.id) == [card.id])
        try DailyStudy.rate(card, rating: .good, context: context, now: now.addingTimeInterval(601))
        #expect(StudyPlan(cards: [card], reviewLimit: 10, newLimit: 1, now: now.addingTimeInterval(602)).completed == 1)
    }

    @Test func freePracticeIgnoresDailyBudgetButKeepsLanguageAndPriority() {
        let d = defaults()
        d.set("ja", forKey: "targetLang")
        d.set(1, forKey: "reviewLimit")
        let due = Card(sentence: "due", word: "due")
        due.reps = 1; due.due = now.addingTimeInterval(-10)
        let fresh = Card(sentence: "fresh", word: "fresh")
        fresh.due = now
        let later = Card(sentence: "later", word: "later")
        later.reps = 2; later.interval = 5; later.due = now.addingTimeInterval(86_400)
        let otherLanguage = Card(sentence: "other", word: "other")
        otherLanguage.languageCode = "en"; otherLanguage.due = now

        let practice = FreePractice.cards([later, otherLanguage, fresh, due], defaults: d, now: now)
        #expect(practice.map(\.word) == ["due", "fresh", "later"])
        #expect(StudyPlan(cards: [later, otherLanguage, fresh, due], reviewLimit: 1, newLimit: 0, language: "ja", now: now).queue.count == 1)
        #expect(StudyCardStatus.key(fresh, now: now) == "review.new")
        #expect(StudyCardStatus.key(due, now: now) == "review.dueNow")
        #expect(StudyCardStatus.key(later, now: now) == "review.scheduled")
    }
    @Test func preparedNewWordsAreBoundedDeduplicatedAndLanguageAware() throws {
        let store = try container(), context = store.mainContext, d = defaults()
        defer { withExtendedLifetime(store) {} }
        d.set("en", forKey: "targetLang"); d.set(3, forKey: "study.newLimit")
        let url = try #require(Bundle.main.url(forResource: "word-atlas", withExtension: "json"))
        let document = try WordListDocument.decodeValidated(Data(contentsOf: url))
        try DailyStudy.prepare(context: context, documents: [document], defaults: d)
        try DailyStudy.prepare(context: context, documents: [document], defaults: d)
        let cards = try context.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 3)
        #expect(Set(cards.map { QuickDictionary.normalized($0.word) }).count == 3)
        #expect(cards.allSatisfy { $0.languageCode == "en" })
        #expect(cards.allSatisfy { WordLevel.rank($0.wordLevel) ?? -1 >= WordLevel.rank("B1")! })
        d.set("ja", forKey: "targetLang")
        try DailyStudy.prepare(context: context, documents: [document], defaults: d)
        #expect(try context.fetch(FetchDescriptor<Card>()).count == 3)
    }

    @Test func savedWordAutomaticallyCreatesOneCardAndCanBeDisabled() throws {
        let store = try container(), context = store.mainContext
        defer { withExtendedLifetime(store) {} }
        let hit = DictionaryHit(id: "1", term: "Hello", reading: "", meaning: "你好", context: "Hello there.", language: "en", source: "lookup")
        try QuickDictionary.save(hit, context: context)
        try QuickDictionary.save(hit, context: context)
        #expect(try context.fetch(FetchDescriptor<Card>()).count == 1)
        var second = hit; second.term = "Goodbye"
        try QuickDictionary.save(second, context: context, autoCard: false)
        #expect(try context.fetch(FetchDescriptor<DictEntry>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<Card>()).count == 1)
    }

    @Test func reminderScheduleOmitsCompletedDayAndHandlesPastTimeAndDST() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9)))
        let dates = StudyReminderSchedule.dates(now: start, hour: 20, minute: 30, skipToday: true, calendar: cal)
        #expect(dates.count == 29)
        #expect(dates.first?.day == 1 && dates.first?.month == 11 && dates.first?.hour == 20)
        let late = try #require(cal.date(byAdding: .hour, value: 13, to: start))
        let future = StudyReminderSchedule.dates(now: late, hour: 20, minute: 30, skipToday: false, calendar: cal)
        #expect(future.count == 29)
        #expect(future.allSatisfy { cal.date(from: $0)! > late })
    }

    @Test func dailyProgressSurvivesStoreReopen() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "study-store-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let schema = Schema([Card.self, DictEntry.self])
        let configuration = ModelConfiguration(schema: schema, url: url)
        var store: ModelContainer? = try ModelContainer(for: schema, configurations: configuration)
        if let context = store?.mainContext {
            let card = Card(sentence: "hello", word: "hello")
            context.insert(card)
            try DailyStudy.rate(card, rating: .good, context: context, now: now)
        }
        store = nil
        let reopened = try ModelContainer(for: schema, configurations: configuration)
        let cards = try reopened.mainContext.fetch(FetchDescriptor<Card>())
        let p = StudyPlan(cards: cards, reviewLimit: 1, newLimit: 1, now: now)
        #expect(p.completed == 1 && p.queue.isEmpty && p.introduced == 1)
    }

    @Test func notificationsScheduleCancelRejectDeniedAndRouteTap() async throws {
        let client = FakeStudyNotifications(), d = defaults()
        let reminders = StudyReminders(client: client, storage: d)
        await reminders.enable(defaults: d)
        #expect(d.bool(forKey: "study.reminders"))
        await reminders.refresh(defaults: d, completed: false, now: now)
        #expect(!client.pending.isEmpty && client.pending.count <= 30)
        #expect(client.pending.values.allSatisfy { $0.content.userInfo["destination"] as? String == "daily-study" })
        await reminders.refresh(defaults: d, completed: true, now: now)
        #expect(client.pending.count == 29)
        reminders.cancel(); #expect(client.pending.isEmpty)
        client.allowed = false
        await reminders.enable(defaults: d)
        #expect(!d.bool(forKey: "study.reminders") && reminders.failure != nil)
        await reminders.refresh(defaults: d, completed: false, now: now)
        #expect(client.pending.isEmpty)
        reminders.handleDestination("other"); #expect(!reminders.openStudy)
        reminders.handleDestination("daily-study"); #expect(reminders.openStudy)
    }

    @Test func minimumEnglishLevelKeepsNewWordsChallenging() {
        let easy = Card(sentence: "easy", word: "easy"); easy.languageCode = "en"; easy.wordLevel = "A1"; easy.createdAt = now.addingTimeInterval(-3); easy.due = now
        let target = Card(sentence: "target", word: "target"); target.languageCode = "en"; target.wordLevel = "B1"; target.createdAt = now.addingTimeInterval(-2); target.due = now
        let hard = Card(sentence: "hard", word: "hard"); hard.languageCode = "en"; hard.wordLevel = "C1"; hard.createdAt = now.addingTimeInterval(-1); hard.due = now
        let plan = StudyPlan(cards: [easy, target, hard], reviewLimit: 10, newLimit: 3, language: "en", minimumLevel: "B1", now: now)
        #expect(plan.minimumLevel == "B1")
        #expect(plan.queue.map(\.word) == ["target", "hard"])
    }

    @Test func englishGetsAUsefulDefaultMinimumLevel() {
        let d = defaults()
        d.set("en", forKey: "targetLang")
        #expect(DailyStudy.minimumLevel(d) == "B1")
        d.set("all", forKey: DailyStudy.minimumLevelKey)
        #expect(DailyStudy.minimumLevel(d) == nil)
        d.set("ja", forKey: "targetLang")
        #expect(DailyStudy.minimumLevel(d) == nil)
    }

    @Test func oldReviewBacklogPreventsNewWordFlood() {
        let old = (0..<8).map { i in let c = Card(sentence: "old", word: "\(i)"); c.reps = 1; c.due = now.addingTimeInterval(-1); return c }
        let p = StudyPlan(cards: old, reviewLimit: 5, newLimit: 5, now: now)
        #expect(p.queue.count == 5 && p.newSlots == 0)
    }
}
