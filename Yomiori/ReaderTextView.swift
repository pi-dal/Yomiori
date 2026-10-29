import SwiftUI
import UIKit
import CoreText
import Litext

/// 2pt ink progress line on a light track. Tap or drag to seek when `onSeek` is set.
struct ProgressLine: View {
    let value: Double
    var onSeek: ((Double) -> Void)?
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.track)
                Rectangle().fill(Theme.ink).frame(width: g.size.width * min(max(value, 0), 1))
            }
            .frame(height: 2).frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                onSeek?(min(max(v.location.x / max(g.size.width, 1), 0), 1))
            })
        }
        .frame(height: onSeek == nil ? 20 : 44)
    }
}

struct ReaderStudyLayout: Layout {
    let stageHeight: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let height = subviews.first?.sizeThatFits(.init(width: min(width, 640), height: nil)).height ?? 0
        return CGSize(width: width, height: height > stageHeight ? height + 48 : stageHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let group = subviews.first else { return }
        let width = min(bounds.width, 640)
        let size = group.sizeThatFits(.init(width: width, height: nil))
        let top = size.height > stageHeight ? 24 : max(0, stageHeight * 0.45 - size.height / 2)
        group.place(at: CGPoint(x: bounds.midX, y: bounds.minY + top), anchor: .top,
                    proposal: .init(width: width, height: size.height))
    }
}

/// Litext owns ordinary text layout and native selection; Yomiori supplies learning actions.
struct LitextTappableText: UIViewRepresentable {
    let text: String, language: String, furigana: Bool
    var pointSize: CGFloat = 17
    var lineSpacing: CGFloat = 4
    var highlighted = false
    var washed: (String) -> Bool = { _ in false }
    let onTap: (String) -> Void
    @ScaledMetric(relativeTo: .caption) private var rubySize: CGFloat = 14
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> ReaderTextLabel { ReaderTextLabel() }
    func updateUIView(_ view: ReaderTextLabel, context: Context) {
        view.onWord = onTap
        let selectedWords = Words.tokens(text, language: language).filter { $0.1 && washed($0.0) }.map(\.0)
        let key = RenderKey(text: text, language: language, furigana: furigana,
                            pointSize: pointSize, rubySize: rubySize, lineSpacing: lineSpacing,
                            highlighted: highlighted, selectedWords: selectedWords, dark: colorScheme == .dark)
        guard view.renderedKey != key else { return }
        view.renderedKey = key
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let ink = UIColor(Theme.ink).resolvedColor(with: traits)
        let highlight = UIColor(Theme.highlight).resolvedColor(with: traits)
        view.tintColor = ink
        view.linkHighlightColor = highlight
        let content = ReaderTextContent.make(text: text, language: language, furigana: furigana,
            pointSize: pointSize, rubySize: rubySize, lineSpacing: lineSpacing, ink: ink,
            supporting: UIColor(Theme.textSecondary).resolvedColor(with: traits),
            highlighted: highlighted, selectedWords: selectedWords)
        view.configure(content, language: language, highlight: highlight)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReaderTextLabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
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

final class ReaderTextLabel: TextLabelView, TextLabelViewDelegate {
    var renderedKey: LitextTappableText.RenderKey?
    var onWord: ((String) -> Void)?
    private(set) var words: [ReaderTextContent.Word] = []

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isSelectable = true
        isAccessibilityElement = true
        // nil uses UIKit selection handles and magnifier rather than drawing our own.
        selectionBackgroundColor = nil
        delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ content: ReaderTextContent.Content, language: String, highlight: UIColor) {
        words = content.words
        lineRenderer = ReaderHighlightRenderer(ranges: content.highlights, color: highlight)
        attributedText = content.attributedText
        accessibilityLabel = content.attributedText.string
        accessibilityLanguage = language
        accessibilityTraits = .staticText
        var seen: Set<String> = []
        accessibilityCustomActions = words.filter { seen.insert($0.text).inserted }.map { word in
            UIAccessibilityCustomAction(name: word.text) { [weak self] _ in self?.onWord?(word.text); return true }
        }
    }
    func textLabelView(_ textLabelView: TextLabelView, didTapHighlightRegion region: TextLabel.HighlightRegion, at location: CGPoint) {
        guard let url = region.linkURL, url.scheme == "yomiori-word",
              let offset = Int(url.lastPathComponent), let word = words.first(where: { $0.range.location == offset }) else { return }
        onWord?(word.text)
    }
    func textLabelView(_ textLabelView: TextLabelView, editMenuForSelection selection: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let lookup = UIAction(title: L10n.string("Look up meaning"), image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
            guard let self, let excerpt = self.selectedPlainText(), !excerpt.isEmpty else { return }
            self.onWord?(excerpt)
        }
        return UIMenu(children: [lookup] + suggestedActions)
    }
}

@MainActor private final class ReaderHighlightRenderer: TextLabel.LineRenderer {
    let ranges: [NSRange]
    let color: UIColor
    init(ranges: [NSRange], color: UIColor) { self.ranges = ranges; self.color = color }
    override func drawBackground(of line: CTLine, at index: Int, in context: CGContext, layout: TextLabel.Layout) {
        let lineRange = CTLineGetStringRange(line)
        let origin = context.textPosition
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        context.setFillColor(color.cgColor)
        for range in ranges {
            let overlap = NSIntersectionRange(range, NSRange(location: lineRange.location, length: lineRange.length))
            guard overlap.length > 0 else { continue }
            let start = CTLineGetOffsetForStringIndex(line, overlap.location, nil)
            let end = CTLineGetOffsetForStringIndex(line, NSMaxRange(overlap), nil)
            context.fill(CGRect(x: origin.x + min(start, end), y: origin.y - descent, width: abs(end - start), height: ascent + descent))
        }
    }
}
