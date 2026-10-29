import SwiftUI
import UIKit
import CoreText

/// CoreText uses one frame for ruby drawing, native line breaking and token hit tests.
struct RubyTappableText: UIViewRepresentable {
    let text: String, language: String, furigana: Bool
    var pointSize: CGFloat = 17
    var lineSpacing: CGFloat = 4
    var highlighted = false
    var washed: (String) -> Bool = { _ in false }
    let onTap: (String) -> Void
    @ScaledMetric(relativeTo: .caption) private var rubySize: CGFloat = 14
    @Environment(\.colorScheme) private var colorScheme

    init(text: String, language: String, furigana: Bool, pointSize: CGFloat = 17,
         lineSpacing: CGFloat = 4, highlighted: Bool = false,
         washed: @escaping (String) -> Bool = { _ in false }, onTap: @escaping (String) -> Void) {
        self.text = text; self.language = language; self.furigana = furigana
        self.pointSize = pointSize; self.lineSpacing = lineSpacing; self.highlighted = highlighted
        self.washed = washed; self.onTap = onTap
    }
    func makeUIView(context: Context) -> RubyReaderTextView { RubyReaderTextView() }
    func updateUIView(_ view: RubyReaderTextView, context: Context) {
        view.onWord = onTap
        let tokens = Words.tokens(text, language: language)
        let selectedWords = tokens.filter { $0.1 && washed($0.0) }.map(\.0)
        let key = RenderKey(text: text, language: language, furigana: furigana,
                            pointSize: pointSize, rubySize: rubySize, lineSpacing: lineSpacing,
                            highlighted: highlighted, selectedWords: selectedWords, dark: colorScheme == .dark)
        guard view.renderedKey != key else { return }
        view.renderedKey = key
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let ink = UIColor(Theme.ink).resolvedColor(with: traits)
        let supporting = UIColor(Theme.textSecondary).resolvedColor(with: traits)
        view.selectionColor = UIColor(Theme.highlight).resolvedColor(with: traits)
        view.tintColor = ink
        let content = ReaderTextContent.make(text: text, language: language, furigana: furigana,
            pointSize: pointSize, rubySize: rubySize, lineSpacing: lineSpacing, ink: ink, supporting: supporting,
            highlighted: highlighted, selectedWords: selectedWords)
        view.configure(content: content.attributedText, words: content.words.map { .init(text: $0.text, range: $0.range) },
                       highlights: content.highlights, language: language)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RubyReaderTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
    struct RenderKey: Equatable {
        let text: String, language: String
        let furigana: Bool
        let pointSize: CGFloat, rubySize: CGFloat, lineSpacing: CGFloat
        let highlighted: Bool
        let selectedWords: [String]
        let dark: Bool
    }
}

/// CoreText suggests native Japanese line breaks; ruby base ranges that fit
/// stay together. Drawing and selection share lines with original UTF-16 offsets.
final class RubyReaderTextView: UIView, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
    struct WordRange { let text: String; let range: NSRange }
    struct TextFrame { let width: CGFloat; let height: CGFloat; let lines: [CTLine]; let origins: [CGPoint] }
    var renderedKey: RubyTappableText.RenderKey?
    var onWord: ((String) -> Void)?
    var selectionColor = UIColor(Theme.highlight)
    private var content = NSAttributedString(string: "")
    private var framesetter: CTFramesetter?
    private var cachedFrame: TextFrame?
    private var words: [WordRange] = []
    private var highlights: [NSRange] = []
    private var selectedRange: NSRange? {
        didSet {
            accessibilityValue = selectedExcerpt
            accessibilityTraits = selectedRange == nil ? .staticText : [.staticText, .selected]
        }
    }
    // Keep the latest presented excerpt after visual selection is dismissed;
    // UIKit may reuse the same UIActions after either handle extends the range.
    private var menuExcerpt: String?
    private var selectionAnchor = NSRange(location: 0, length: 0)
    private lazy var editMenu = UIEditMenuInteraction(delegate: self)
    private weak var observedWindow: UIWindow?
    private lazy var outsideTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tappedOutside(_:)))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()
    private lazy var handleDrag: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(draggedHandle(_:)))
        gesture.delegate = self
        return gesture
    }()

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let select = UILongPressGestureRecognizer(target: self, action: #selector(selected(_:)))
        tap.require(toFail: select)
        tap.require(toFail: handleDrag)
        addGestureRecognizer(tap)
        addGestureRecognizer(select)
        addGestureRecognizer(handleDrag)
        addInteraction(editMenu)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(content: NSAttributedString, words: [WordRange], highlights: [NSRange], language: String) {
        if self.content.string != content.string { clearSelection() }
        self.content = content; self.words = words; self.highlights = highlights
        framesetter = CTFramesetterCreateWithAttributedString(content as CFAttributedString)
        cachedFrame = nil
        accessibilityLabel = content.string
        accessibilityLanguage = language
        // Read the authentic sentence once; each word also has a VoiceOver lookup action.
        var seen: Set<String> = []
        accessibilityCustomActions = words.filter { seen.insert($0.text).inserted }.map { word in
            UIAccessibilityCustomAction(name: word.text) { [weak self] _ in
                self?.onWord?(word.text)
                return true
            }
        }
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    func textFrame(width: CGFloat) -> TextFrame? {
        guard width.isFinite, width > 0, let framesetter else { return nil }
        if let cachedFrame, cachedFrame.width == width { return cachedFrame }
        let typesetter = CTFramesetterGetTypesetter(framesetter)
        let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
        let rubyWords = words.filter { content.attribute(rubyKey, at: $0.range.location, effectiveRange: nil) != nil }
        var lines: [CTLine] = []
        var baselineDepths: [CGFloat] = []
        var height: CGFloat = 0
        var start = 0
        while start < content.length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            if count <= 0 {
                count = (content.string as NSString).rangeOfComposedCharacterSequence(at: start).length
            }
            var end = min(content.length, start + count)
            if let word = rubyWords.first(where: { $0.range.location < end && end < NSMaxRange($0.range) && $0.range.location > start }) {
                let wholeWord = CTTypesetterCreateLine(typesetter, CFRange(location: word.range.location, length: word.range.length))
                if CTLineGetTypographicBounds(wholeWord, nil, nil, nil) <= Double(width) {
                    end = word.range.location
                }
            }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: end - start))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            if ascent + descent <= 0 {
                let font = UIFont.systemFont(ofSize: renderedKey?.pointSize ?? 28, weight: .semibold)
                ascent = font.ascender; descent = -font.descender
            }
            if !lines.isEmpty { height += max(0, renderedKey?.lineSpacing ?? 0) }
            baselineDepths.append(height + ascent)
            height += ascent + descent + max(0, leading)
            lines.append(line)
            start = end
        }
        height = max(1, ceil(height) + 1)
        let origins = baselineDepths.map { CGPoint(x: 0, y: height - $0) }
        let result = TextFrame(width: width, height: height, lines: lines, origins: origins)
        cachedFrame = result
        return result
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: textFrame(width: size.width)?.height ?? 0)
    }
    override func layoutSubviews() { super.layoutSubviews(); setNeedsDisplay() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let layout = textFrame(width: bounds.width) else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: layout.height)
        context.scaleBy(x: 1, y: -1)
        let lines = layout.lines
        let origins = layout.origins
        context.setFillColor(selectionColor.cgColor)
        for (line, origin) in zip(lines, origins) {
            let lineRange = CTLineGetStringRange(line)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            for highlight in highlights + (selectedRange.map { [$0] } ?? []) {
                let range = NSIntersectionRange(highlight, NSRange(location: lineRange.location, length: lineRange.length))
                guard range.length > 0 else { continue }
                let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
                let end = CTLineGetOffsetForStringIndex(line, NSMaxRange(range), nil)
                context.fill(CGRect(x: origin.x + min(start, end), y: origin.y - descent,
                                    width: abs(end - start), height: ascent + descent))
            }
        }
        for (line, origin) in zip(lines, origins) {
            context.textPosition = origin
            CTLineDraw(line, context)
        }
        context.restoreGState()
        if let selectedRange {
            // UIKit coordinates for functional selection stems and drag endpoints.
            context.setStrokeColor(tintColor.cgColor)
            context.setFillColor(tintColor.cgColor)
            context.setLineWidth(2)
            for (index, leading) in [(selectedRange.location, true), (NSMaxRange(selectedRange), false)] {
                if let caret = caretRect(at: index, preferPreviousLine: !leading) {
                    context.move(to: CGPoint(x: caret.midX, y: caret.minY))
                    context.addLine(to: CGPoint(x: caret.midX, y: caret.maxY))
                    context.strokePath()
                    let y = leading ? caret.minY : caret.maxY
                    context.fillEllipse(in: CGRect(x: caret.midX - 4, y: y - 4, width: 8, height: 8))
                }
            }
        }
    }
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let layout = textFrame(width: bounds.width) else { return }
        let location = recognizer.location(in: self)
        if let selectedRange {
            if let index = characterIndex(at: location), NSLocationInRange(index, selectedRange) { showSelectionMenu() }
            else { clearSelection() }
            return
        }
        let point = CGPoint(x: location.x, y: layout.height - location.y)
        let lines = layout.lines
        let origins = layout.origins
        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            guard point.y >= origin.y - descent, point.y <= origin.y + ascent,
                  point.x >= origin.x, point.x <= origin.x + width else { continue }
            let index = CTLineGetStringIndexForPosition(line, CGPoint(x: point.x - origin.x, y: point.y - origin.y))
            if let word = words.first(where: { NSLocationInRange(index, $0.range) }) { onWord?(word.text) }
            return
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if observedWindow !== window {
            observedWindow?.removeGestureRecognizer(outsideTap)
            observedWindow = window
            window?.addGestureRecognizer(outsideTap)
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === outsideTap || otherGestureRecognizer === outsideTap
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === handleDrag else { return true }
        return nearestEndpoint(to: gestureRecognizer.location(in: self)) != nil
    }
    @objc private func tappedOutside(_ gesture: UITapGestureRecognizer) {
        if selectedRange != nil, !bounds.contains(gesture.location(in: self)) {
            // The native menu sits outside these text bounds. Let UIKit finish
            // dispatching its Copy/Lookup action before it manages dismissal.
            selectedRange = nil
            setNeedsDisplay()
        }
    }
    private func clearSelection() {
        selectedRange = nil
        editMenu.dismissMenu()
        setNeedsDisplay()
    }
    /// Closest native line and UTF-16 insertion position; clamps a drag beyond the
    /// line ends so a continuous gesture can select across whitespace and lines.
    private func characterIndex(at point: CGPoint) -> Int? {
        guard let layout = textFrame(width: bounds.width), content.length > 0 else { return nil }
        let lines = layout.lines
        guard !lines.isEmpty else { return nil }
        let origins = layout.origins
        let flipped = CGPoint(x: point.x, y: layout.height - point.y)
        let verticalBounds = lines.indices.map { row -> ClosedRange<CGFloat> in
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTLineGetTypographicBounds(lines[row], &ascent, &descent, nil)
            return (origins[row].y - descent)...(origins[row].y + ascent)
        }
        // Prefer the line containing the finger, including its ascender/ruby
        // region. Only snap across a gap using distance to the bounds.
        let row = lines.indices.first(where: { verticalBounds[$0].contains(flipped.y) })
            ?? lines.indices.min { first, second in
                func distance(to interval: ClosedRange<CGFloat>) -> CGFloat {
                    max(interval.lowerBound - flipped.y, flipped.y - interval.upperBound, 0)
                }
                return distance(to: verticalBounds[first]) < distance(to: verticalBounds[second])
            }!
        let line = lines[row], origin = origins[row]
        let lineRange = CTLineGetStringRange(line)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if flipped.x <= origin.x { return lineRange.location }
        if flipped.x >= origin.x + width { return min(content.length, lineRange.location + lineRange.length) }
        let index = CTLineGetStringIndexForPosition(line, CGPoint(x: flipped.x - origin.x, y: 0))
        return index == kCFNotFound ? nil : min(max(0, index), content.length)
    }
    private func caretRect(at index: Int, preferPreviousLine: Bool) -> CGRect? {
        guard let layout = textFrame(width: bounds.width) else { return nil }
        let lines = layout.lines
        let origins = layout.origins
        for (line, origin) in zip(lines, origins) {
            let range = CTLineGetStringRange(line)
            let end = range.location + range.length
            guard index >= range.location, index < end || (preferPreviousLine && index == end) || index == content.length && index == end else { continue }
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let x = origin.x + CTLineGetOffsetForStringIndex(line, index, nil)
            return CGRect(x: x, y: layout.height - origin.y - ascent, width: 2, height: ascent + descent)
        }
        return nil
    }
    private func nearestEndpoint(to point: CGPoint) -> Bool? {
        guard let range = selectedRange,
              let start = caretRect(at: range.location, preferPreviousLine: false),
              let end = caretRect(at: NSMaxRange(range), preferPreviousLine: true) else { return nil }
        let first = hypot(point.x - start.midX, point.y - start.minY)
        let last = hypot(point.x - end.midX, point.y - end.maxY)
        guard min(first, last) <= 28 else { return nil }
        return first <= last
    }
    private func updateSelection(to index: Int) {
        let lower = min(selectionAnchor.location, index)
        let upper = max(NSMaxRange(selectionAnchor), index)
        let proposed = NSRange(location: lower, length: upper - lower)
        guard proposed.length > 0 else { return }
        // Never cut a surrogate pair, combining mark or other composed character.
        selectedRange = (content.string as NSString).rangeOfComposedCharacterSequences(for: proposed)
        setNeedsDisplay()
    }
    @objc private func selected(_ gesture: UILongPressGestureRecognizer) {
        guard let index = characterIndex(at: gesture.location(in: self)) else { return }
        switch gesture.state {
        case .began:
            editMenu.dismissMenu()
            let position = min(index, max(0, content.length - 1))
            selectionAnchor = words.first(where: { NSLocationInRange(position, $0.range) })?.range
                ?? (content.string as NSString).rangeOfComposedCharacterSequence(at: position)
            selectedRange = selectionAnchor
            setNeedsDisplay()
        case .changed: updateSelection(to: index)
        case .ended: updateSelection(to: index); showSelectionMenu()
        case .cancelled: showSelectionMenu()
        default: break
        }
    }
    @objc private func draggedHandle(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard let range = selectedRange, let leading = nearestEndpoint(to: point) else { return }
            editMenu.dismissMenu()
            selectionAnchor = NSRange(location: leading ? NSMaxRange(range) : range.location, length: 0)
        case .changed:
            if let index = characterIndex(at: point) { updateSelection(to: index) }
        case .ended, .cancelled: showSelectionMenu()
        default: break
        }
    }
    private var selectedExcerpt: String? {
        guard let range = selectedRange, range.length > 0, NSMaxRange(range) <= content.length else { return nil }
        return (content.string as NSString).substring(with: range)
    }
    private var selectionMenuTargetRect: CGRect? {
        guard let range = selectedRange,
              let start = caretRect(at: range.location, preferPreviousLine: false),
              let end = caretRect(at: NSMaxRange(range), preferPreviousLine: true) else { return nil }
        // Exclude the complete selected line span and both endpoint hit regions
        // from native menu placement, including the ruby above the first line.
        return start.union(end).insetBy(dx: -28, dy: -28)
    }
    private func showSelectionMenu() {
        guard let excerpt = selectedExcerpt, let target = selectionMenuTargetRect else { return }
        menuExcerpt = excerpt
        let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: target.midX, y: target.minY))
        configuration.preferredArrowDirection = .down
        editMenu.presentEditMenu(with: configuration)
    }
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        selectionMenuTargetRect ?? CGRect(origin: configuration.sourcePoint, size: .zero)
    }
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard menuExcerpt != nil else { return nil }
        return UIMenu(children: [
            UIAction(title: L10n.string("Copy"), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                guard let excerpt = self?.menuExcerpt else { return }
                UIPasteboard.general.string = excerpt
            },
            UIAction(title: L10n.string("Look up meaning"), image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
                guard let self, let excerpt = self.menuExcerpt else { return }
                self.onWord?(excerpt)
            }
        ])
    }

}
