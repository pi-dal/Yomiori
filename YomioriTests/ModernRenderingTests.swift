import Foundation
import UIKit
import CoreText
import Testing
@testable import Yomiori

@MainActor struct ReaderRenderingTests {
    private func content(_ text: String, size: CGFloat = 28, ruby: Bool = true) -> ReaderTextContent.Content {
        ReaderTextContent.make(text: text, language: "ja", furigana: ruby, pointSize: size,
            rubySize: size * 0.5, lineSpacing: 8, ink: .label, supporting: .secondaryLabel,
            highlighted: false, selectedWords: ["日本語"])
    }
    @Test func rubyPathKeepsWordsTogetherAcrossWidthsAndSizes() throws {
        let text = "今日は日本語を勉強します。新しい言葉を少しずつ覚えましょう。"
        for size: CGFloat in [17, 28, 44] {
            let value = content(text, size: size)
            let ruby = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
            let annotatedWords = value.words.filter { value.attributedText.attribute(ruby, at: $0.range.location, effectiveRange: nil) != nil }
            try #require(!annotatedWords.isEmpty, "The Japanese passage must have furigana")
            let label = RubyReaderTextView()
            label.renderedKey = .init(text: text, language: "ja", furigana: true, pointSize: size, rubySize: size * 0.5,
                                      lineSpacing: 8, highlighted: false, selectedWords: [], dark: false)
            label.configure(content: value.attributedText, words: value.words.map { .init(text: $0.text, range: $0.range) }, highlights: [], language: "ja")
            for width: CGFloat in [210, 320, 600] {
                let layout = try #require(label.textFrame(width: width))
                for word in annotatedWords {
                    let wordLine = CTLineCreateWithAttributedString(value.attributedText.attributedSubstring(from: word.range))
                    if CTLineGetTypographicBounds(wordLine, nil, nil, nil) <= Double(width) {
                        let keptTogether = layout.lines.contains { line in
                            let range = CTLineGetStringRange(line)
                            return NSIntersectionRange(NSRange(location: range.location, length: range.length), word.range) == word.range
                        }
                        #expect(keptTogether, "\(word.text) at size \(size), width \(width)")
                    }
                }
            }
        }
    }
}
