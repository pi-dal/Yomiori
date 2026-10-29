import Foundation
import NaturalLanguage

enum Words {
    /// Splits text into tappable tokens (words for Japanese, spaced words otherwise).
    static func tokens(_ text: String, language: String) -> [(String, Bool)] {
        let tk = NLTokenizer(unit: .word)
        tk.string = text
        tk.setLanguage(NLLanguage(language))
        var out: [(String, Bool)] = []
        var cursor = text.startIndex
        tk.enumerateTokens(in: text.startIndex..<text.endIndex) { r, _ in
            if r.lowerBound > cursor { out.append((String(text[cursor..<r.lowerBound]), false)) }
            out.append((String(text[r]), true))
            cursor = r.upperBound
            return true
        }
        if cursor < text.endIndex { out.append((String(text[cursor...]), false)) }
        return out
    }

    /// Hiragana reading for Japanese text containing kanji; nil otherwise.
    /// Uses a Japanese-locale tokenizer so kanji get Japanese (not Chinese) readings.
    static func reading(_ s: String) -> String? {
        guard s.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) else { return nil }
        let cf = s as CFString
        let range = CFRangeMake(0, CFStringGetLength(cf))
        let tk = CFStringTokenizerCreate(kCFAllocatorDefault, cf, range, kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale)
        var out = ""
        var type = CFStringTokenizerAdvanceToNextToken(tk)
        while !type.isEmpty {
            let r = CFStringTokenizerGetCurrentTokenRange(tk)
            let piece = (s as NSString).substring(with: NSRange(location: r.location, length: r.length))
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tk, kCFStringTokenizerAttributeLatinTranscription) as? String {
                let m = NSMutableString(string: latin)
                CFStringTransform(m, nil, kCFStringTransformLatinHiragana, false)
                out += m as String
            } else { out += piece }
            type = CFStringTokenizerAdvanceToNextToken(tk)
        }
        return out == s || out.isEmpty ? nil : out
    }

    struct Entry { var meaning: String; var pos: String }

    static func lookup(_ word: String, sentence: String, languageCode: String? = nil) async throws -> Entry {
        let t = languageCode.map(Language.find) ?? Prefs.target, n = Prefs.native
        let sys = "You are a dictionary for a \(t.name) learner whose native language is \(n.name). Reply with exactly two lines. Line 1: part of speech in \(n.name). Line 2: the meaning of the word as used in the sentence, in \(n.name), under 15 words. No other text."
        let out = try await AI.complete([.init(role: "system", content: sys), .init(role: "user", content: "Word: \(word)\nSentence: \(sentence)")])
        let rows = out.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !rows.isEmpty else { throw AIError.failed }
        if rows.count == 1 { return Entry(meaning: rows[0], pos: "") }
        return Entry(meaning: rows[1...].joined(separator: " "), pos: rows[0])
    }

    /// A short definition written in Japanese (for the "Japanese definitions" setting).
    static func definitionJa(_ word: String, sentence: String) async -> String {
        let sys = "あなたは日本語学習者向けの国語辞典です。文中での単語の意味を、やさしい日本語で20字以内で説明してください。説明だけを返してください。"
        return ((try? await AI.complete([.init(role: "system", content: sys), .init(role: "user", content: "単語: \(word)\n文: \(sentence)")])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
