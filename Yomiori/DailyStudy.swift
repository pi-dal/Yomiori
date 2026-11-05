import Foundation
import SwiftData
import SwiftUI

private struct StudyDefaultsKey: EnvironmentKey {
    static let defaultValue = UserDefaults.standard
}
extension EnvironmentValues {
    var studyDefaults: UserDefaults {
        get { self[StudyDefaultsKey.self] }
        set { self[StudyDefaultsKey.self] = newValue }
    }
}

/// A day's budget counts distinct completed cards, not taps or visits to the review screen.
struct StudyPlan {
    let queue: [Card]
    let completed: Int
    let introduced: Int
    let remaining: Int
    let newSlots: Int
    let nextLearningDate: Date?

    init(cards: [Card], reviewLimit: Int, newLimit: Int, language: String? = nil, now: Date = Date(), calendar: Calendar = .current) {
        let today: (Date?) -> Bool = { $0.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        completed = cards.filter { today($0.lastCompletedAt) }.count
        introduced = cards.filter { today($0.firstReviewedAt) }.count
        remaining = max(0, min(max(reviewLimit, 0), 100) - completed)
        let old = cards.filter { $0.reps > 0 && $0.due <= now && !today($0.lastCompletedAt) }
            .sorted { $0.due == $1.due ? $0.id.uuidString < $1.id.uuidString : $0.due < $1.due }
        newSlots = min(max(0, min(max(newLimit, 0), 20) - introduced), max(0, remaining - old.count))
        let fresh = cards.filter { $0.reps == 0 && $0.due <= now && (language == nil || $0.languageCode == language) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        queue = Array(old.prefix(remaining)) + Array(fresh.prefix(newSlots))
        nextLearningDate = remaining > 0 ? cards.filter {
            $0.reps > 0 && $0.interval == 0 && $0.due > now && !today($0.lastCompletedAt)
        }.map(\.due).min() : nil
    }
}

@MainActor enum DailyStudy {
    static func reviewLimit(_ defaults: UserDefaults) -> Int {
        defaults.object(forKey: "reviewLimit") == nil ? 30 : defaults.integer(forKey: "reviewLimit")
    }
    static func newLimit(_ defaults: UserDefaults) -> Int {
        defaults.object(forKey: "study.newLimit") == nil ? 5 : defaults.integer(forKey: "study.newLimit")
    }
    static func plan(_ cards: [Card], defaults: UserDefaults, now: Date = Date()) -> StudyPlan {
        StudyPlan(cards: cards, reviewLimit: reviewLimit(defaults), newLimit: newLimit(defaults), language: defaults.string(forKey: "targetLang") ?? "ja", now: now)
    }

    /// Local definitions only. Saving never silently starts an AI request or downloads audio.
    @discardableResult static func addSaved(_ entry: DictEntry, context: ModelContext) throws -> Card? {
        guard entry.kind == "word", !entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let language = entry.languageCode, term = QuickDictionary.normalized(entry.term)
        let existing = try context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.languageCode == language }))
        guard !existing.contains(where: { QuickDictionary.normalized($0.word) == term }) else { return nil }
        let card = Card(sentence: entry.context.isEmpty ? entry.term : entry.context, word: entry.term)
        card.languageCode = language; card.reading = entry.reading; card.meaning = entry.meaning
        card.sourceID = entry.sourceID; card.sourceName = entry.sourceName; card.sourcePos = entry.sourcePos
        card.sourceKind = entry.sourceKind
        context.insert(card)
        return card
    }

    /// Prepare only enough new material for today's budget. Repeated starts cannot grow the queue.
    static func prepare(context: ModelContext, documents: [WordListDocument], defaults: UserDefaults, now: Date = Date()) throws {
        let cards = try context.fetch(FetchDescriptor<Card>())
        let plan = plan(cards, defaults: defaults, now: now)
        var slots = max(0, plan.newSlots - plan.queue.filter { $0.reps == 0 }.count)
        guard slots > 0 else { return }
        let language = defaults.string(forKey: "targetLang") ?? "ja"
        let entries = try context.fetch(FetchDescriptor<DictEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        var inserted: [Card] = []
        do {
            for entry in entries where slots > 0 && entry.languageCode == language && defaults.object(forKey: "study.autoCards") as? Bool != false {
                if let card = try addSaved(entry, context: context) { inserted.append(card); slots -= 1 }
            }
            let source = defaults.string(forKey: "study.source") ?? "automatic"
            let document = source == "saved" ? nil : documents.first { $0.id == source && $0.language == language }
                ?? (source == "automatic" ? documents.first { $0.language == language } : nil)
            if slots > 0, let document {
                let existing = try context.fetch(FetchDescriptor<Card>())
                let ids = IELTSCardWriter.savedIDs(existing, listID: document.id)
                var terms = Set(existing.filter { $0.languageCode == language }.map { QuickDictionary.normalized($0.word) })
                let words = document.entries.filter { word in
                    !ids.contains(word.id) && terms.insert(QuickDictionary.normalized(word.w)).inserted
                }.prefix(slots)
                // This writer saves atomically; it also commits the saved-word cards above.
                try IELTSCardWriter.add(Array(words), context: context, document: document)
            } else { try context.save() }
        } catch {
            inserted.forEach { context.delete($0) }
            throw error
        }
    }

    static func rate(_ card: Card, rating: Rating, context: ModelContext, now: Date = Date()) throws {
        let previous = (card.ease, card.reps, card.lapses, card.interval, card.due,
                        card.firstReviewedAt, card.lastReviewedAt, card.lastCompletedAt)
        Scheduler.apply(card, rating, now: now)
        if previous.1 == 0 { card.firstReviewedAt = now }
        card.lastReviewedAt = now
        if rating != .again { card.lastCompletedAt = now }
        do { try context.save() }
        catch {
            (card.ease, card.reps, card.lapses, card.interval, card.due,
             card.firstReviewedAt, card.lastReviewedAt, card.lastCompletedAt) = previous
            throw error
        }
    }
}
