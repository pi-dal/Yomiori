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
        #expect(try text("review.due", language: "en", Int64(0)) == "0 cards due")
        #expect(try text("review.due", language: "en", Int64(1)) == "1 card due")
        #expect(try text("review.due", language: "en", Int64(2)) == "2 cards due")
        #expect(try text("review.completed", language: "en", Int64(1)) == "1 card reviewed")
        #expect(try text("review.completed", language: "zh-Hans", Int64(1)) == "已复习 1 张卡片")
        #expect(try text("review.nextDays", language: "zh-Hans", Int64(2)) == "2 天")
        #expect(try text("lists.count", language: "en", Int64(1)) == "1 word")
    }

    @Test func progressAndAccessibilityFormatsKeepArgumentTypes() throws {
        #expect(try text("read.transcribing", language: "en", Int64(42)) == "Generating subtitles… 42%")
        #expect(try text("link.downloading", language: "zh-Hans", Int64(42)) == "正在下载… 42%")
        #expect(try text("review.a11yPosition", language: "zh-Hans", Int64(1), Int64(3)) == "第 1 张，共 3 张")
        #expect(try text("review.a11yRating", language: "zh-Hans", "良好", "2 天") == "良好，2 天后复习")
    }
}
