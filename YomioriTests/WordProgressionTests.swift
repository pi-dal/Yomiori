import Foundation
import SwiftData
import Testing
@testable import Yomiori

@MainActor struct WordProgressionTests {
    @Test func bundledListIntroducesHarderWordsAfterSustainedRecall() throws {
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
            #expect(fresh.count == 5)
            let values = fresh.map { difficulty[$0.wordListEntryID]! }
            averages.append(values.reduce(0, +) / Double(values.count))
            // The learner does the day's reviews and recalls every word.
            let due = try context.fetch(FetchDescriptor<Card>()).filter { $0.reps > 0 && $0.due <= day }
            for card in due + fresh { try DailyStudy.rate(card, rating: .good, context: context, now: day) }
            day = day.addingTimeInterval(86_400)
        }
        #expect(averages.last! > averages.first!)
    }
}
