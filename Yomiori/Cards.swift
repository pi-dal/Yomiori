import SwiftUI
import SwiftData

/// A mined sentence, reviewed on a schedule.
@Model final class Card {
    var id = UUID()
    var sentence: String
    var word: String
    var reading: String = ""
    var meaning: String = ""
    var definitionJa: String = ""
    var translation: String = ""
    var languageCode: String = "ja"
    var wordListID: String = ""
    var wordListEntryID: String = ""
    var audioRemoteURL: String = ""
    var definitionEnglish: String = ""
    var audioFile: String?
    var sourceID: String = ""
    var sourceName: String = ""
    var sourcePos: Double = 0
    var createdAt = Date()
    var due = Date()
    var interval: Double = 0      // days
    var ease: Double = 2.5
    var reps = 0
    var lapses = 0
    var exported = false
    init(sentence: String, word: String) { self.sentence = sentence; self.word = word }
}

enum Rating: Int, CaseIterable { case again, hard, good, easy
    var label: String { L10n.string(["review.again", "review.hard", "review.good", "review.easy"][rawValue]) }
}

enum Scheduler {
    /// The next interval in days for a rating (0 means "again in 10 minutes").
    static let maximumInterval: Double = 36_500 // One hundred years.
    private static func boundedInterval(_ value: Double) -> Double {
        guard value.isFinite, value >= 0 else { return 0 }
        return min(value, maximumInterval)
    }
    private static func boundedEase(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 1.3), 10) : 2.5
    }
    static func next(_ c: Card, _ r: Rating) -> Double {
        let interval = boundedInterval(c.interval), ease = boundedEase(c.ease)
        let days: Double
        switch r {
        case .again: days = 0
        case .hard: days = interval == 0 ? 1 : max(1, (interval * 1.2).rounded())
        case .good: days = interval == 0 ? 2 : max(interval + 1, (interval * ease).rounded())
        case .easy: days = interval == 0 ? 4 : max(interval + 2, (interval * ease * 1.3).rounded())
        }
        return boundedInterval(days)
    }
    static func hint(_ days: Double) -> String {
        if days == 0 { return L10n.format("review.nextMinutes", Int64(10)) }
        let d = Int(boundedInterval(days))
        return L10n.format("review.nextDays", Int64(d))
    }
    static func apply(_ c: Card, _ r: Rating) {
        let days = next(c, r)
        c.ease = boundedEase(c.ease)
        switch r {
        case .again: c.lapses += 1; c.ease = max(1.3, c.ease - 0.2)
        case .hard: c.ease = max(1.3, c.ease - 0.15)
        case .good: break
        case .easy: c.ease += 0.15
        }
        c.ease = boundedEase(c.ease)
        c.reps += 1
        c.interval = days
        let now = Date()
        c.due = days == 0 ? now.addingTimeInterval(600)
            : Calendar.current.date(byAdding: .day, value: Int(days), to: Calendar.current.startOfDay(for: now))
                ?? now.addingTimeInterval(days * 86_400)
    }
}
