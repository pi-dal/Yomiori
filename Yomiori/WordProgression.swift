import Foundation

/// Chooses new words from a list so difficulty rises gradually and follows how the learner is actually doing.
///
/// Difficulty is continuous in CEFR steps: A1 covers 0..<1, A2 1..<2 and so on. Inside a level, words with
/// more senses and collocations come first; in the bundled list that tracks real-world frequency, while the
/// list's own order within a level is effectively random.
///
/// Ability is a small Bayesian estimate (a one-parameter logistic model) from the learner's reviewed,
/// levelled cards. New words aim where recall is about 80% likely: lapses pull the target down,
/// steady recalls move it up, and "Too easy" moves it up faster. The prior keeps each day's step small,
/// at most about a quarter of a level for five new words. The minimum level remains a floor.
enum WordProgression {
    /// Odds of recall change about fourfold per CEFR step.
    static let slope = log(4.0)
    /// New words aim at the difficulty the learner recalls about 80% of the time.
    static let targetGap = 1.0
    /// Before any evidence, new words start at the beginning of the floor level. A narrow prior keeps steps gradual.
    static let priorWidth = 0.5

    // MARK: Difficulty

    /// Difficulty for every levelled entry, keyed by entry id. Unlevelled entries are absent.
    static func difficulties(_ words: [AtlasWord]) -> [String: Double] {
        var result: [String: Double] = [:]
        let levelled = words.compactMap { word in WordLevel.rank(word.level).map { (word: word, rank: $0) } }
        for (rank, group) in Dictionary(grouping: levelled, by: \.rank) {
            // Midpoint percentile of how uncommon the word looks inside its level; ties share a position.
            let counts = Dictionary(grouping: group, by: { commonness($0.word) }).mapValues(\.count)
            var below = 0
            var position: [Int: Double] = [:]
            for value in counts.keys.sorted(by: >) {
                let size = counts[value]!
                position[value] = (Double(below) + Double(size) / 2) / Double(group.count)
                below += size
            }
            for item in group { result[item.word.id] = Double(rank) + position[commonness(item.word)]! }
        }
        return result
    }

    /// Commonly used words have more senses and collocations.
    static func commonness(_ word: AtlasWord) -> Int {
        word.senses.count + word.collocations.count
    }

    // MARK: Ability

    /// Whether a reviewed card was ever forgotten, and how much that answer counts.
    /// A word marked too easy (ease above the starting 2.5) counts as two recalls.
    static func outcome(_ card: Card) -> (recalled: Double, weight: Double) {
        if card.lapses > 0 { return (0, 1) }
        return (1, card.ease > 2.51 ? 2 : 1)
    }

    /// The learner's estimated ability on the same scale as `difficulties`.
    /// - Parameters:
    ///   - known: Exact difficulty for cards from this list; other levelled cards use the middle of their level.
    ///   - floor: The minimum level's rank, or nil when every level is allowed.
    static func ability(cards: [Card], language: String, known: [String: Double] = [:], listID: String? = nil, floor: Int?) -> Double {
        let evidence: [(difficulty: Double, recalled: Double, weight: Double)] = cards.compactMap { card in
            guard card.reps > 0, card.languageCode == language, let rank = WordLevel.rank(card.wordLevel) else { return nil }
            let exact = card.wordListID == listID ? known[card.wordListEntryID] : nil
            let result = outcome(card)
            return (exact ?? Double(rank) + 0.5, result.recalled, result.weight)
        }
        let prior = Double(floor ?? 0) + targetGap
        // The log-posterior gradient falls monotonically, so bisection finds its single root.
        func gradient(_ theta: Double) -> Double {
            evidence.reduce(-(theta - prior) / (priorWidth * priorWidth)) { sum, item in
                sum + item.weight * slope * (item.recalled - 1 / (1 + exp(-slope * (theta - item.difficulty))))
            }
        }
        var low = -2.0, high = Double(WordLevel.ordered.count) + 3
        for _ in 0..<60 {
            let middle = (low + high) / 2
            if gradient(middle) > 0 { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    // MARK: Selection

    /// The next `count` words, easiest first, starting at the learner's current target difficulty.
    /// When nothing remains above the target, the hardest remaining words below it are used.
    /// Unlevelled words follow the levelled ones in list order, so imported lists without levels keep their order.
    static func next(_ candidates: [AtlasWord], count: Int, difficulties: [String: Double], target: Double) -> [AtlasWord] {
        guard count > 0 else { return [] }
        let indexed = candidates.enumerated().map { (index: $0.offset, word: $0.element, difficulty: difficulties[$0.element.id]) }
        let ascending: (Int, Double, Int, Double) -> Bool = { leftIndex, left, rightIndex, right in
            left == right ? leftIndex < rightIndex : left < right
        }
        let above = indexed.filter { ($0.difficulty ?? -.infinity) >= target }
            .sorted { ascending($0.index, $0.difficulty!, $1.index, $1.difficulty!) }
        let below = indexed.filter { $0.difficulty.map { $0 < target } ?? false }
            .sorted { ascending($1.index, $1.difficulty!, $0.index, $0.difficulty!) }
        let unlevelled = indexed.filter { $0.difficulty == nil }
        let picked = (above + unlevelled + below).prefix(count)
        return picked.sorted {
            ascending($0.index, $0.difficulty ?? target, $1.index, $1.difficulty ?? target)
        }.map(\.word)
    }

    /// Picks new words for the learner from a list's remaining candidates.
    static func next(_ candidates: [AtlasWord], count: Int, document: WordListDocument, cards: [Card], minimum: String?) -> [AtlasWord] {
        let known = difficulties(document.entries)
        let floor = WordLevel.normalized(minimum).flatMap(WordLevel.rank)
        let theta = ability(cards: cards, language: document.language, known: known, listID: document.id, floor: floor)
        let target = max(Double(floor ?? 0), theta - targetGap)
        return next(candidates, count: count, difficulties: known, target: target)
    }
}
