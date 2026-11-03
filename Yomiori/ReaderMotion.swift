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
