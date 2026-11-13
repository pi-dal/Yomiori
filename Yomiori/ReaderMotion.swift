import SwiftUI

/// How the learner meets a line's translation. Veiled turns the translation into a recall check.
enum ReaderTranslation: String, CaseIterable, Identifiable {
    case off, veiled, shown
    var id: Self { self }
    var label: LocalizedStringKey {
        switch self {
        case .off: "read.translation.off"
        case .veiled: "read.translation.veiled"
        case .shown: "read.translation.shown"
        }
    }
}

/// Reader motion shares one decelerating curve: confident arrival, no bounce.
enum ReaderMotion {
    static func advance(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .timingCurve(0.16, 1, 0.3, 1, duration: 0.55)
    }
    static func veil(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .timingCurve(0.16, 1, 0.3, 1, duration: 0.42)
    }

    /// The focus line settles like ink into washi: it arrives from the reading direction, faint and slightly small.
    static func focus(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        // The outgoing line clears first, so two focus lines never overlap mid-flight.
        return .asymmetric(
            insertion: .modifier(active: InkSettle(settled: false, rise: forward ? 22 : -22), identity: InkSettle(settled: true, rise: 0))
                .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.5).delay(0.08)),
            removal: .opacity.combined(with: .offset(y: forward ? -18 : 18)).animation(.easeIn(duration: 0.12)))
    }

    /// Context lines drift with the reading flow as they lighten or appear.
    static func context(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: forward ? 12 : -12)),
            removal: .opacity.combined(with: .offset(y: forward ? -16 : 16)).animation(.easeIn(duration: 0.14)))
    }
}

/// Marks the studied word inside a sentence for `BrushStrokeRenderer`.
struct StudyWordAttribute: TextAttribute {}

/// The reader's study stroke, drawn under the marked word from left to right as `progress` reaches 1:
/// matcha while the word is being learned, a faint ink line once it has stuck. Saving a word draws it,
/// so the mark the reader shows afterwards is visibly the one the learner made.
struct BrushStrokeRenderer: TextRenderer {
    var progress: Double
    var known = false
    var reduceMotion = false
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        // One word can arrive as several glyph runs (font fallback, kana after kanji); its stroke is one span per line.
        var spans: [(x: CGFloat, y: CGFloat, width: CGFloat)] = []
        for line in layout {
            var minX = CGFloat.infinity, maxX = -CGFloat.infinity, y: CGFloat = 0
            for run in line {
                context.draw(run)
                guard run[StudyWordAttribute.self] != nil else { continue }
                let bounds = run.typographicBounds
                minX = min(minX, bounds.rect.minX); maxX = max(maxX, bounds.rect.maxX)
                y = max(y, bounds.origin.y + bounds.descent * 0.55)
            }
            // Inset like the reader's stroke, so the line belongs to the word rather than the gap.
            if maxX > minX { spans.append((minX + 1, y, max(0, maxX - minX - 2))) }
        }
        guard progress > 0, !spans.isEmpty else { return }
        let weight: CGFloat = known ? 1 : 2
        let color = known ? Theme.textSecondary.opacity(0.55) : Theme.accent
        let total = spans.reduce(0) { $0 + $1.width }
        var remaining = reduceMotion ? total : total * progress
        if reduceMotion { context.opacity = progress }
        for span in spans {
            let width = min(span.width, remaining)
            guard width > 0 else { break }
            remaining -= width
            let rect = CGRect(x: span.x, y: span.y, width: width, height: weight)
            context.fill(Path(roundedRect: rect, cornerRadius: weight / 2), with: .color(color))
        }
    }
}

private struct InkSettle: ViewModifier {
    let settled: Bool, rise: CGFloat
    func body(content: Content) -> some View {
        content
            .opacity(settled ? 1 : 0)
            .scaleEffect(settled ? 1 : 0.97, anchor: .topLeading)
            .offset(y: rise)
    }
}

/// The translation beneath the focus line. Veiled, it rests under frosted washi until the learner checks it.
struct TranslationGloss: View {
    let text: String
    let veiled: Bool
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 8) {
                // The frosted text keeps its length and shape visible, like writing seen through shoji paper.
                Text(text).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .blur(radius: veiled ? 5 : 0)
                    .opacity(veiled ? 0.6 : 1)
                if veiled {
                    Label("read.translation.veil", systemImage: "eye")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(veiled ? Text("read.translation.veilA11y") : Text(text))
        .accessibilityHint(veiled ? Text("read.translation.veilHint") : Text(""))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("reader-translation")
    }
}

/// A matcha hairline drawn beneath the focus line as it is spoken, for shadowing and pacing.
struct SpokenStroke: View {
    let player: PlayerModel
    let start: Double, end: Double

    var body: some View {
        let observed = player.time   // Re-renders after seeks while paused.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !player.playing)) { _ in
            let live = player.player?.currentTime().seconds ?? observed
            let now = live.isFinite ? live : observed
            let fraction = min(max((now - start) / max(end - start, 0.01), 0), 1)
            Capsule().fill(Theme.separator)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.accent).scaleEffect(x: fraction, anchor: .leading)
                }
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
        .accessibilityHidden(true)
    }
}
