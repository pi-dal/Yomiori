import Foundation
import UIKit
import CoreText
import Litext
import Testing
@testable import Yomiori

struct CoachFormattingTests {
    @Test func translationsPreserveMarkdownBlocksAndFencedCode() {
        let text = "## Practice\n\n- **Read** every day\n\n今日は晴れです。\n（It's sunny today.）\n\n```swift\n(value)\n```\n\n| Word | Meaning |\n| --- | --- |\n| 本 | Book |"
        let segments = CoachMessageSegments.parse(text)
        #expect(segments.count == 3)
        #expect(segments[1].isTranslation)
        #expect(segments[1].text == "（It's sunny today.）")
        #expect(segments[2].text.contains("```swift\n(value)\n```"))
        #expect(segments[2].text.contains("| Word | Meaning |"))
        #expect(segments.map(\.id) == [0, 5, 6])
    }
    @Test func streamAppendKeepsExistingSegmentIdentity() {
        let start = CoachMessageSegments.parse("Hello\n(你好)\n\n**Prac")
        let end = CoachMessageSegments.parse("Hello\n(你好)\n\n**Practice**\n\n- Read")
        #expect(start.map(\.id) == end.map(\.id))
        #expect(start[0] == end[0]); #expect(start[1] == end[1])
    }
}

@MainActor struct ReaderRenderingTests {
    private func content(_ text: String, size: CGFloat = 28, ruby: Bool = true) -> ReaderTextContent.Content {
        ReaderTextContent.make(text: text, language: "ja", furigana: ruby, pointSize: size,
            rubySize: size * 0.5, lineSpacing: 8, ink: .label, supporting: .secondaryLabel,
            highlighted: false, selectedWords: ["日本語"])
    }
    @Test func litextPreservesOriginalUTF16RangesAndHitTesting() throws {
        let text = "今日は日本語を勉強します。Hello 👩🏽‍💻 café。"
        let value = content(text)
        #expect(value.attributedText.string == text)
        for word in value.words {
            #expect((text as NSString).substring(with: word.range) == word.text)
        }
        let ruby = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
        var rubyCount = 0
        value.attributedText.enumerateAttribute(ruby, in: NSRange(location: 0, length: value.attributedText.length)) { annotation, _, _ in
            if annotation != nil { rubyCount += 1 }
        }
        #expect(rubyCount > 0)
        for size: CGFloat in [17, 28, 44] {
            let value = content(text, size: size, ruby: false)
            for width: CGFloat in [210, 320, 600] {
                let label = ReaderTextLabel()
                label.configure(value, language: "ja", highlight: .systemGray5)
                let measured = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
                #expect(measured.height.isFinite && measured.height > size)
                label.frame = CGRect(origin: .zero, size: measured)
                label.layoutIfNeeded()
                let lines = label.layoutLines
                #expect(lines.first?.stringRange.location == 0)
                #expect(lines.last.map { NSMaxRange($0.stringRange) } == value.attributedText.length)
                for word in value.words {
                    let rects = label.textLayout.rects(for: word.range)
                    #expect(!rects.isEmpty)
                    let rect = try #require(rects.first)
                    let point = CGPoint(x: rect.midX, y: rect.midY)
                    let index = label.textLayout.characterIndex(at: point)
                    #expect(index.map { NSLocationInRange($0, word.range) } == true)
                }
            }
        }
    }
    @Test func rubyPathKeepsWordsTogetherAcrossWidthsAndSizes() throws {
        let text = "今日は日本語を勉強します。新しい言葉を少しずつ覚えましょう。"
        for size: CGFloat in [17, 28, 44] {
            let value = content(text, size: size)
            let label = RubyReaderTextView()
            label.renderedKey = .init(text: text, language: "ja", furigana: true, pointSize: size, rubySize: size * 0.5,
                                      lineSpacing: 8, highlighted: false, selectedWords: [], dark: false)
            label.configure(content: value.attributedText, words: value.words.map { .init(text: $0.text, range: $0.range) }, highlights: [], language: "ja")
            for width: CGFloat in [210, 320, 600] {
                let layout = try #require(label.textFrame(width: width))
                #expect(layout.height.isFinite && layout.height > 0)
                for word in value.words where value.attributedText.attribute(NSAttributedString.Key(kCTRubyAnnotationAttributeName as String), at: word.range.location, effectiveRange: nil) != nil {
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
    @Test func wordTapAndSelectionMenuUseCurrentText() throws {
        let label = ReaderTextLabel(), value = content("今日は日本語を勉強します。")
        label.configure(value, language: "ja", highlight: .systemGray5)
        let size = label.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        label.frame = CGRect(origin: .zero, size: size); label.layoutIfNeeded()
        var lookedUp: String?
        label.onWord = { lookedUp = $0 }
        let word = try #require(value.words.first)
        let region = try #require(label.textLayout.highlightRegions.first { $0.linkURL?.lastPathComponent == String(word.range.location) })
        label.textLabelView(label, didTapHighlightRegion: region, at: .zero)
        #expect(lookedUp == word.text)
        label.selectionRange = word.range
        #expect(label.selectedPlainText() == word.text)
        let menu = try #require(label.textLabelView(label, editMenuForSelection: word.range, suggestedActions: []))
        #expect(menu.children.first?.title == L10n.string("Look up meaning"))
        label.configure(content("新しい文章"), language: "ja", highlight: .systemGray5)
        #expect(label.selectionRange == nil)
    }
}
