import Foundation
import Testing
@testable import Yomiori

struct LibraryOrderTests {
    @Test func naturalTitlesAndNewestTieBreakKeepLibraryOrderPredictable() {
        struct Item {
            let id: Int
            let title: String
            let date: Date
        }
        let items = [
            Item(id: 1, title: "Chapter 10", date: Date(timeIntervalSince1970: 4)),
            Item(id: 2, title: "Chapter 2", date: Date(timeIntervalSince1970: 1)),
            Item(id: 3, title: "Chapter 2", date: Date(timeIntervalSince1970: 3))
        ]
        #expect(LibraryOrder.title.sorted(items, title: { $0.title }, createdAt: { $0.date }).map(\.id) == [3, 2, 1])
        #expect(LibraryOrder.newest.sorted(items, title: { $0.title }, createdAt: { $0.date }).map(\.id) == [1, 3, 2])
    }
}
