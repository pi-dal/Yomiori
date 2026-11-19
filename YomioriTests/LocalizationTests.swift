import Foundation
import Testing
@testable import Yomiori

struct LocalizationTests {
    private func text(_ key: String, language: String, _ arguments: CVarArg...) throws -> String {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        return String(format: bundle.localizedString(forKey: key, value: nil, table: nil),
                      locale: Locale(identifier: language), arguments: arguments)
    }

    @Test func reviewCountsUseEnglishPluralsAndChineseUnits() throws {
        #expect(try text("review.due", language: "en", Int64(1)) == "1 card due")
        #expect(try text("review.due", language: "en", Int64(2)) == "2 cards due")
        #expect(try text("review.due", language: "zh-Hans", Int64(2)) == "2 张待复习")
    }

    @Test func progressAndAccessibilityFormatsKeepArgumentTypes() throws {
        #expect(try text("review.a11yProgress", language: "zh-Hans", Int64(1), Int64(3)) == "已完成 1 / 3 个词")
        #expect(try text("review.a11yRating", language: "zh-Hans", "良好", "2 天") == "良好，2 天后复习")
    }
}
