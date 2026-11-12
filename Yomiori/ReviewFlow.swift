import Foundation

/// The guided word loop. New words are met in context first and recalled a few cards later;
/// due words start with recall. A missed word returns a few cards later in the same session,
/// so most sessions end on a successful recall rather than a failure.
enum ReviewStep: Equatable {
    /// A new word, shown with its meaning in the original sentence.
    case intro
    /// The word in context without its meaning.
    case recall
    /// The answer, with feedback on the learner's recall.
    case result
}

struct ReviewItem: Equatable {
    let id: UUID
    /// The word still needs its in-context introduction in this session.
    var needsIntro: Bool
    var misses = 0
}

struct ReviewSessionQueue: Equatable {
    /// How many other cards appear before a missed or newly introduced word returns.
    static let returnGap = 3
    /// A word missed this many times moves on; the schedule brings it back later.
    static let maximumMisses = 3

    private(set) var items: [ReviewItem]
    let total: Int
    private(set) var finished = 0
    /// Recalled correctly at the first attempt.
    private(set) var recalled: [UUID] = []
    /// Missed at least once, in the order they were first missed.
    private(set) var missed: [UUID] = []
    let newWords: [UUID]

    init(_ cards: [(id: UUID, isNew: Bool)]) {
        var seen = Set<UUID>()
        let unique = cards.filter { seen.insert($0.id).inserted }
        items = unique.map { ReviewItem(id: $0.id, needsIntro: $0.isNew) }
        total = unique.count
        newWords = unique.filter(\.isNew).map(\.id)
    }

    var current: ReviewItem? { items.first }
    var isEmpty: Bool { items.isEmpty }
    var step: ReviewStep { current?.needsIntro == true ? .intro : .recall }

    /// The new word has been met; it returns for recall after a few other cards.
    mutating func finishIntro() {
        guard var item = items.first, item.needsIntro else { return }
        items.removeFirst()
        item.needsIntro = false
        items.insert(item, at: min(Self.returnGap, items.count))
    }

    enum Outcome: Equatable { case finished, returnsLater }

    /// Records the current recall attempt and advances the queue.
    @discardableResult mutating func record(correct: Bool) -> Outcome {
        guard var item = items.first, !item.needsIntro else { return .finished }
        items.removeFirst()
        if correct {
            if item.misses == 0 { recalled.append(item.id) }
            finished += 1
            return .finished
        }
        item.misses += 1
        if !missed.contains(item.id) { missed.append(item.id) }
        guard item.misses < Self.maximumMisses else { finished += 1; return .finished }
        items.insert(item, at: min(Self.returnGap, items.count))
        return .returnsLater
    }

    /// The scheduler change for a recall attempt in a daily session, or nil when the schedule stays as it is.
    /// The first miss records a lapse; later misses of the same word are practice only.
    /// A word recalled after a miss counts as relearned today.
    static func rating(correct: Bool, priorMisses: Int, adjustment: Rating? = nil) -> Rating? {
        if correct { return priorMisses == 0 ? (adjustment ?? .good) : .good }
        return priorMisses == 0 ? .again : nil
    }
}

/// Multiple-choice meanings. Wrong options come from the learner's own cards in the same language,
/// preferring the same word list, the same level and a similar length, so the answer can't be spotted by shape alone.
enum MeaningChoices {
    static func make<G: RandomNumberGenerator>(answer: String, card: Card, among cards: [Card], meaning: (Card) -> String,
                                               count: Int = 4, using generator: inout G) -> [String] {
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, count > 1 else { return [] }
        var seen: Set<String> = [normalized(answer)]
        let candidates = cards.shuffled(using: &generator).compactMap { other -> (text: String, score: Double)? in
            guard other.id != card.id, other.languageCode == card.languageCode else { return nil }
            let text = meaning(other).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(normalized(text)).inserted else { return nil }
            return (text, score(other, text: text, card: card, answer: answer))
        }
        // Stable after the shuffle, so equally plausible candidates keep a random order.
        let ranked = candidates.enumerated().sorted { $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score }
        let window = ranked.prefix((count - 1) * 2).map(\.element.text)
        guard !window.isEmpty else { return [] }
        var options = Array(window.shuffled(using: &generator).prefix(count - 1))
        options.insert(answer, at: Int.random(in: 0...options.count, using: &generator))
        return options
    }

    static func make(answer: String, card: Card, among cards: [Card], meaning: (Card) -> String, count: Int = 4) -> [String] {
        var generator = SystemRandomNumberGenerator()
        return make(answer: answer, card: card, among: cards, meaning: meaning, count: count, using: &generator)
    }

    private static func score(_ other: Card, text: String, card: Card, answer: String) -> Double {
        var value = 0.0
        if !card.wordListID.isEmpty && other.wordListID == card.wordListID { value += 2 }
        if !card.wordLevel.isEmpty && other.wordLevel == card.wordLevel { value += 1 }
        let length = Double(answer.count), difference = Double(abs(text.count - answer.count))
        value += 2 * max(0, 1 - difference / max(length, 1))
        return value
    }

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// What a finished session leaves behind: the source most of its words came from, to return to it.
enum ReviewSource: Equatable {
    case material(id: String, position: Double)
    case document(id: String, page: Int)

    static func mostFrequent(_ cards: [Card], materials: Set<String>, documents: Set<String>) -> ReviewSource? {
        // Ordered by first appearance; the first card from a source decides where to resume.
        var ranked: [(key: String, count: Int, source: ReviewSource)] = []
        for card in cards where !card.sourceID.isEmpty {
            let source: ReviewSource
            if card.sourceKind == "pdf" {
                guard documents.contains(card.sourceID) else { continue }
                source = .document(id: card.sourceID, page: Int(card.sourcePos))
            } else if card.sourceKind == "subtitle" {
                guard materials.contains(card.sourceID) else { continue }
                source = .material(id: card.sourceID, position: card.sourcePos)
            } else { continue }
            let key = card.sourceKind + ":" + card.sourceID
            if let index = ranked.firstIndex(where: { $0.key == key }) { ranked[index].count += 1 }
            else { ranked.append((key, 1, source)) }
        }
        // Ties go to the source met first in the session.
        var best: (count: Int, source: ReviewSource)?
        for entry in ranked where entry.count > (best?.count ?? 0) { best = (entry.count, entry.source) }
        return best?.source
    }
}
