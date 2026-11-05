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

    @Test func oldReviewBacklogPreventsNewWordFlood() {
        let old = (0..<8).map { i in let c = Card(sentence: "old", word: "\(i)"); c.reps = 1; c.due = now.addingTimeInterval(-1); return c }
        let p = StudyPlan(cards: old, reviewLimit: 5, newLimit: 5, now: now)
        #expect(p.queue.count == 5 && p.newSlots == 0)
    }
}
