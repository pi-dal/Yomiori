import UIKit
import CoreText

/// Learning annotations use original UTF-16 offsets; the renderer never inserts hidden characters.
@MainActor enum ReaderTextContent {
    struct Word: Equatable {
        let text: String
        let range: NSRange
    }
    struct Content {
        let attributedText: NSAttributedString
        let words: [Word]
        let highlights: [NSRange]
    }
    static func make(text: String, language: String, furigana: Bool, pointSize: CGFloat,
                     rubySize: CGFloat, lineSpacing: CGFloat, ink: UIColor, supporting: UIColor,
                     highlighted: Bool, selectedWords: [String]) -> Content {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = lineSpacing
        let descriptor = UIFont.systemFont(ofSize: pointSize, weight: .semibold).fontDescriptor.addingAttributes([
            .cascadeList: [UIFontDescriptor(name: "HiraginoSans-W6", size: pointSize)]
        ])
        let content = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont(descriptor: descriptor, size: pointSize),
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
            NSAttributedString.Key(kCTLanguageAttributeName as String): language
        ])
        var offset = 0, words: [Word] = [], highlights: [NSRange] = []
        for (token, isWord) in Words.tokens(text, language: language) {
            let range = NSRange(location: offset, length: (token as NSString).length)
            defer { offset += range.length }
            if highlighted || (isWord && selectedWords.contains(token)) {
                highlights.append(range)
                content.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            guard isWord else { continue }
            words.append(.init(text: token, range: range))
            // An internal link gives Litext native tap/press handling. It is never opened externally.
            content.addAttribute(.link, value: URL(string: "yomiori-word://lookup/\(range.location)")!, range: range)
            if furigana, let reading = Words.reading(token) {
                let ruby = CTRubyAnnotationCreateWithAttributes(.auto, .auto, .before, reading as CFString, [
                    kCTRubyAnnotationSizeFactorAttributeName: rubySize / pointSize,
                    kCTForegroundColorAttributeName: supporting.cgColor
                ] as CFDictionary)
                content.addAttribute(NSAttributedString.Key(kCTRubyAnnotationAttributeName as String), value: ruby, range: range)
            }
        }
        return Content(attributedText: content, words: words, highlights: highlights)
    }
}
