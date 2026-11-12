import Foundation
import NaturalLanguage
import SwiftData

/// Recognises the learner's card words wherever they appear: in any material, and in inflected forms
/// (読む in 読もう, remember in remembered), so meeting a word again is visible while reading and reviewing.
@MainActor struct StudyLexicon {
    enum Stage: Equatable { case learning, known }
    /// A word reviewed to an interval of three weeks or more counts as one that stuck.
    static let knownInterval: Double = 21

    let language: String
    private var exact: [String: Card] = [:]
    private var stems: [(stem: String, card: Card, bare: Bool)] = []

    init(cards: [Card], language: String) {
        self.language = language
        var stemIndex: [String: Card] = [:], bareStems: Set<String> = []
        for card in cards where card.languageCode == language {
            let key = QuickDictionary.normalized(card.word)
            guard !key.isEmpty, key.count <= 40 else { continue }
            exact[key] = Self.preferred(exact[key], card)
            if language == "ja", let stem = Self.japaneseStem(key) {
                stemIndex[stem] = Self.preferred(stemIndex[stem], card)
                // 勉強する is usually tokenized as 勉強 + し + ます, so the noun alone also counts.
                if key.hasSuffix("する") { bareStems.insert(stem) }
            }
        }
        // Longer stems first, so 覚え wins over a shorter stem that happens to share a prefix.
        stems = stemIndex.map { ($0.key, $0.value, bareStems.contains($0.key)) }.sorted { $0.stem.count == $1.stem.count ? $0.stem < $1.stem : $0.stem.count > $1.stem.count }
    }

    var isEmpty: Bool { exact.isEmpty }

    func card(for token: String) -> Card? {
        let key = QuickDictionary.normalized(token)
        guard !key.isEmpty else { return nil }
        if let card = exact[key] { return card }
        if language == "en" {
            // The tagger often has no lemma for a word without context; regular endings cover the common cases.
            let candidates = (Self.englishLemma(key).map { [$0] } ?? []) + Self.englishBaseForms(key)
            for base in candidates where base != key { if let card = exact[base] { return card } }
        }
        if language == "ja" {
            for entry in stems where key.hasPrefix(entry.stem) {
                let rest = key.dropFirst(entry.stem.count)
                if rest.isEmpty ? entry.bare : (rest.count <= 4 && rest.unicodeScalars.allSatisfy(Self.isHiragana)) { return entry.card }
            }
        }
        return nil
    }

    static func stage(_ card: Card) -> Stage { card.reps > 0 && card.interval >= knownInterval ? .known : .learning }

    /// The first token of `sentence` that is this card's word, in any inflection; used to mark the word in review.
    static func occurrence(of card: Card, in sentence: String) -> String? {
        let lexicon = StudyLexicon(cards: [card], language: card.languageCode)
        return Words.tokens(sentence, language: card.languageCode).first { $0.1 && lexicon.card(for: $0.0) != nil }?.0
    }

    /// Dictionary-form verbs and い-adjectives inflect after a kanji stem: 読む → 読, 覚える → 覚え, 高い → 高, 勉強する → 勉強.
    static func japaneseStem(_ word: String) -> String? {
        var stem = word
        if stem.hasSuffix("する"), stem.count > 2 { stem.removeLast(2) }
        else if let last = stem.last, "うくぐすつぬぶむるい".contains(last), stem.count > 1 { stem.removeLast() }
        else { return nil }
        // A kana-only stem would match far too many unrelated tokens.
        guard stem.unicodeScalars.contains(where: isKanji) else { return nil }
        return stem
    }

    /// Candidate base forms for regular inflections: remembered → remember, studies → study, running → run.
    static func englishBaseForms(_ word: String) -> [String] {
        guard word.count > 3, word.allSatisfy(\.isLetter) else { return [] }
        var forms: [String] = []
        func strip(_ suffix: String, add: String = "") {
            guard word.hasSuffix(suffix), word.count - suffix.count >= 2 else { return }
            let stem = String(word.dropLast(suffix.count))
            forms.append(stem + add)
            // Doubled final consonant: stopped → stop, running → run.
            if add.isEmpty, stem.count >= 3, let last = stem.last, stem.dropLast().last == last, !"aeiou".contains(last) {
                forms.append(String(stem.dropLast()))
            }
        }
        strip("ies", add: "y"); strip("ied", add: "y")
        strip("ing"); strip("ing", add: "e")
        strip("ed"); strip("ed", add: "e"); strip("d")
        strip("es"); strip("s")
        strip("er"); strip("est")
        return forms
    }

    static func englishLemma(_ word: String) -> String? {
        guard word.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || $0 == "'" || $0 == "-" }) else { return nil }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        return tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0.map { $0.rawValue.lowercased() }
    }

    private static func preferred(_ current: Card?, _ candidate: Card) -> Card {
        guard let current else { return candidate }
        if current.reps != candidate.reps { return current.reps > candidate.reps ? current : candidate }
        return current.createdAt <= candidate.createdAt ? current : candidate
    }
    private static func isKanji(_ scalar: Unicode.Scalar) -> Bool { (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) }
    private static func isHiragana(_ scalar: Unicode.Scalar) -> Bool { (0x3041...0x309F).contains(scalar.value) }
}

/// Reader rendering asks about the same tokens on every frame; matches are cached until the cards change.
@MainActor final class StudyLexiconCache {
    private var signature: [Int] = []
    private var lexicon = StudyLexicon(cards: [], language: "")
    private var marks: [String: [String: StudyLexicon.Stage]] = [:]

    func lexicon(cards: [Card], language: String) -> StudyLexicon {
        let signature = [cards.count, cards.reduce(0) { $0 &+ $1.reps &* 31 &+ Int($1.interval) }, language.hashValue]
        if signature != self.signature {
            self.signature = signature
            lexicon = StudyLexicon(cards: cards, language: language)
            marks = [:]
        }
        return lexicon
    }

    /// Study stages for the card words in one line of text.
    func marks(for text: String, cards: [Card], language: String) -> [String: StudyLexicon.Stage] {
        let lexicon = lexicon(cards: cards, language: language)
        if let cached = marks[text] { return cached }
        var result: [String: StudyLexicon.Stage] = [:]
        if !lexicon.isEmpty {
            for (token, isWord) in Words.tokens(text, language: language) where isWord {
                if let card = lexicon.card(for: token) { result[token] = StudyLexicon.stage(card) }
            }
        }
        if marks.count > 200 { marks = [:] }
        marks[text] = result
        return result
    }
}

/// Coach works with the words the learner is consolidating now, not simply the newest cards.
@MainActor enum CoachFocus {
    static func words(_ cards: [Card], language: String, now: Date = Date(), calendar: Calendar = .current, limit: Int = 10) -> [Card] {
        let today: (Date?) -> Bool = { $0.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        let usable = cards.filter { $0.languageCode == language && !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // Words missed today first, then words met for the first time today, then other words reviewed today.
        let missedToday = usable.filter { today($0.lastReviewedAt) && $0.lapses > 0 && $0.interval < StudyLexicon.knownInterval }
            .sorted { $0.lapses == $1.lapses ? ($0.lastReviewedAt ?? now) > ($1.lastReviewedAt ?? now) : $0.lapses > $1.lapses }
        let newToday = usable.filter { today($0.firstReviewedAt) }.sorted { ($0.firstReviewedAt ?? now) > ($1.firstReviewedAt ?? now) }
        let reviewedToday = usable.filter { today($0.lastReviewedAt) }.sorted { ($0.lastReviewedAt ?? now) > ($1.lastReviewedAt ?? now) }
        let recent = usable.sorted { $0.createdAt > $1.createdAt }
        var seen = Set<String>(), result: [Card] = []
        for card in missedToday + newToday + reviewedToday + recent where result.count < limit {
            if seen.insert(QuickDictionary.normalized(card.word)).inserted { result.append(card) }
        }
        return result
    }
}

/// A Coach correction becomes a review card: the corrected form in the learner's own sentence.
@MainActor enum CorrectionCards {
    static func sentence(_ message: String, correction: Correction) -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: correction.wrong) else { return correction.right }
        return text.replacingCharacters(in: range, with: correction.right)
    }

    static func exists(_ correction: Correction, message: ChatMsg, in cards: [Card]) -> Bool {
        let sentence = sentence(message.content, correction: correction)
        return cards.contains { $0.sourceKind == "coach" && $0.word == correction.right && $0.sentence == sentence && $0.languageCode == message.languageCode }
    }

    @discardableResult static func add(_ correction: Correction, message: ChatMsg, context: ModelContext, now: Date = Date()) throws -> Card? {
        let language = message.languageCode, right = correction.right
        let sentence = sentence(message.content, correction: correction)
        let existing = try context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.languageCode == language && $0.word == right }))
        guard !existing.contains(where: { $0.sentence == sentence }) else { return nil }
        let card = Card(sentence: sentence, word: right)
        card.languageCode = language
        let reason = correction.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        card.meaning = reason.isEmpty ? L10n.format("correction.instead", correction.wrong) : L10n.format("correction.meaning", reason, correction.wrong)
        card.sourceKind = "coach"
        card.sourceName = L10n.string("Coach")
        card.createdAt = now
        card.due = now
        context.insert(card)
        do { try context.save() } catch { context.delete(card); throw error }
        return card
    }
}

/// Behaviour-based measures that keep growing. No scores and no streak: missed days never take anything away.
struct GrowthTrack: Equatable {
    enum Kind: CaseIterable { case wordsStuck, hours, activeDays, expressions }
    let kind: Kind
    let value: Int

    static func tiers(_ kind: Kind) -> [Int] {
        switch kind {
        case .wordsStuck: [10, 25, 50, 100, 250, 500, 1000, 2000]
        case .hours: [1, 5, 10, 25, 50, 100, 250, 500]
        case .activeDays: [3, 7, 14, 30, 60, 100, 200, 365]
        case .expressions: [1, 10, 25, 50, 100, 250, 500]
        }
    }

    /// The last milestone reached; beyond the listed tiers, milestones continue at the largest step.
    var reached: Int? { Self.sequence(kind, through: value).last { $0 <= value } }
    var next: Int {
        let tiers = Self.tiers(kind)
        if let next = tiers.first(where: { $0 > value }) { return next }
        let step = tiers.last ?? 1
        return (value / step + 1) * step
    }
    /// Progress from the last milestone towards the next one.
    var fraction: Double {
        let start = Double(reached ?? 0), end = Double(next)
        return end > start ? min(1, max(0, (Double(value) - start) / (end - start))) : 1
    }

    private static func sequence(_ kind: Kind, through value: Int) -> [Int] {
        let tiers = tiers(kind)
        guard let last = tiers.last, value >= last else { return tiers }
        return tiers + Array(stride(from: last * 2, through: value, by: last))
    }
}
