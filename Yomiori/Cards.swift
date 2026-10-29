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
    static func next(_ c: Card, _ r: Rating) -> Double {
        switch r {
        case .again: return 0
        case .hard: return c.interval == 0 ? 1 : max(1, (c.interval * 1.2).rounded())
        case .good: return c.interval == 0 ? 2 : max(c.interval + 1, (c.interval * c.ease).rounded())
        case .easy: return c.interval == 0 ? 4 : max(c.interval + 2, (c.interval * c.ease * 1.3).rounded())
        }
    }
    static func hint(_ days: Double) -> String {
        if days == 0 { return L10n.format("review.nextMinutes", Int64(10)) }
        let d = Int(days)
        return L10n.format("review.nextDays", Int64(d))
    }
    static func apply(_ c: Card, _ r: Rating) {
        let days = next(c, r)
        switch r {
        case .again: c.lapses += 1; c.ease = max(1.3, c.ease - 0.2)
        case .hard: c.ease = max(1.3, c.ease - 0.15)
        case .good: break
        case .easy: c.ease += 0.15
        }
        c.reps += 1
        c.interval = days
        c.due = days == 0 ? Date().addingTimeInterval(600) : Calendar.current.date(byAdding: .day, value: Int(days), to: Calendar.current.startOfDay(for: Date()))!
    }
}
