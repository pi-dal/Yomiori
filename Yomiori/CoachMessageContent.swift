import SwiftUI
import MarkdownView

/// The renderer owns formatting only; sessions always store the original response.
struct CoachMessageContent: View {
    let text: String
    var isStreaming = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: MarkdownTheme {
        var theme = MarkdownTheme()
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        func color(_ value: Color) -> UIColor { UIColor(value).resolvedColor(with: traits) }
        let body = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17))
        theme.fonts.body = body
        theme.fonts.bold = .systemFont(ofSize: body.pointSize, weight: .semibold)
        theme.fonts.italic = .italicSystemFont(ofSize: body.pointSize)
        theme.fonts.title = .systemFont(ofSize: body.pointSize * 1.12, weight: .semibold)
        theme.fonts.largeTitle = .systemFont(ofSize: body.pointSize * 1.25, weight: .semibold)
        theme.fonts.code = .monospacedSystemFont(ofSize: body.pointSize * 0.9, weight: .regular)
        theme.fonts.codeInline = theme.fonts.code
        theme.colors.body = color(Theme.ink)
        theme.colors.emphasis = color(Theme.ink)
        theme.colors.highlight = color(Theme.ink)
        theme.colors.code = color(Theme.ink)
        theme.colors.codeBackground = color(Theme.controlFill)
        theme.colors.codeBlockBackground = color(Theme.controlFill)
        theme.colors.codeBlockBarBackground = color(Theme.controlSelected)
        theme.colors.selectionBackground = color(Theme.highlight)
        theme.table.borderColor = color(Theme.separator)
        theme.table.headerBackgroundColor = color(Theme.controlFill)
        theme.table.cellBackgroundColor = .clear
        theme.table.stripeCellBackgroundColor = color(Theme.surface)
        theme.spacings.paragraph = 12
        theme.spacings.headingBefore = 20
        return theme
    }

    var body: some View {
        let segments = CoachMessageSegments.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                if segment.isTranslation {
                    Text(verbatim: segment.text)
                        .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                } else {
                    MarkdownView(segment.text, theme: theme)
                        .streaming(isStreaming && segment.id == segments.last?.id && !reduceMotion)
                        .accessibilityElement(children: .contain)
                        .accessibilityChildren { Text(verbatim: segment.text) }
                }
            }
        }
        // Re-evaluate UIFontMetrics when the SwiftUI environment changes.
        .environment(\.dynamicTypeSize, typeSize)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        }
    }
}

/// Beginner translations retain their supporting style without interpreting code as prose.
enum CoachMessageSegments {
    struct Segment: Identifiable, Equatable {
        let id: Int
        let text: String
        let isTranslation: Bool
    }
    static func parse(_ text: String) -> [Segment] {
        var segments: [Segment] = [], pending: [String] = []
        var start = 0, fence: Character?, fenceLength = 0
        func flush() {
            guard !pending.isEmpty else { return }
            let text = pending.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.init(id: start, text: text, isTranslation: false))
            }
            pending.removeAll()
        }
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.first
            let length = trimmed.prefix(while: { $0 == marker }).count
            let isFence = (marker == "`" || marker == "~") && length >= 3
            let translation = fence == nil && ((trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) || (trimmed.hasPrefix("（") && trimmed.hasSuffix("）")))
            if translation {
                flush()
                segments.append(.init(id: index, text: line, isTranslation: true))
            } else {
                if pending.isEmpty { start = index }
                pending.append(line)
            }
            if isFence {
                if fence == nil { fence = marker; fenceLength = length }
                else if marker == fence && length >= fenceLength && trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
            }
        }
        flush()
        return segments
    }
}
