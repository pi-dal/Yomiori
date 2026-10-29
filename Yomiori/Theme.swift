import SwiftUI
import UIKit

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

enum Theme {
    // Official Radix Gray roles, with Red reserved for errors.
    static let background = Color("FocusBackground")
    static let surface = Color("FocusSurface")
    static let controlFill = Color("FocusControlFill")
    static let controlHover = Color("FocusControlHover")
    static let controlSelected = Color("FocusControlSelected")
    static let separator = Color("FocusSeparator")
    static let controlBorder = Color("FocusControlBorder")
    static let focusBorder = Color("FocusFocusBorder")
    static let solid = Color("FocusSolid")
    static let solidHover = Color("FocusSolidHover")
    static let textSecondary = Color("FocusTextSecondary")
    static let ink = Color("FocusInk")
    static let accent = ink
    static let errorText = Color("FocusErrorText")
    static let errorBackground = Color("FocusErrorBackground")
    static let errorBorder = Color("FocusErrorBorder")
    static let vermilion = errorText
    static let highlight = controlSelected
    static let dim = textSecondary
    static let track = controlSelected
    static let weak = ink
    static let good = ink

    enum Fonts {
        // UIKit metrics keep the three system-font roles responsive to Dynamic Type.
        static var meta: Font { font(14, relativeTo: .caption1) }
        static var body: Font { font(17, relativeTo: .body) }
        static var focus: Font { font(28, relativeTo: .title2) }
        private static func font(_ size: CGFloat, relativeTo style: UIFont.TextStyle) -> Font {
            Font(UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size)))
        }
    }
}

/// Interface copy follows the OS app language, independently of learning preferences.
enum L10n {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}

/// The single highlight colour. Entries keep a colour id for stored data, but every id maps to the one wash.
struct HL: Identifiable {
    let id: Int, name: String
    var color: Color { Theme.highlight }
    var ui: UIColor { UIColor(Theme.highlight) }
    static let all = [HL(id: 0, name: "Highlight")]
    static func color(_ i: Int) -> Color? { Theme.highlight }
    static func name(_ i: Int) -> String { L10n.string("Highlight") }
}

extension View {
    /// Highlight wash on the bottom `fraction` of the view (used behind text).
    func washed(_ on: Bool, fraction: CGFloat = 0.38) -> some View {
        background(alignment: .bottom) {
            if on {
                GeometryReader { g in
                    Theme.highlight.frame(width: g.size.width, height: g.size.height * fraction)
                        .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
                }
            }
        }
    }
}

/// Text tabs with a 2pt ink underline on the selected one.
struct TextTabs: View {
    let items: [(id: String, label: String)]
    @Binding var selection: String
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(items, id: \.id) { t in
                        let on = selection == t.id
                        Button { selection = t.id } label: {
                            Text(LocalizedStringKey(t.label))
                                .font(Theme.Fonts.body.weight(on ? .semibold : .regular))
                                .lineLimit(1).fixedSize()
                                .foregroundStyle(on ? Theme.ink : Theme.textSecondary)
                                .padding(.bottom, 6).frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if on { Rectangle().fill(Theme.ink).frame(height: 2) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .id(t.id)
                    }
                }
                .padding(.horizontal, 24)
            }
            .onChange(of: selection) { _, value in proxy.scrollTo(value, anchor: .center) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
    }
}

/// Empty state: symbol, headline, one sentence, optional ink pill button.
struct EmptyState: View {
    let symbol: String, title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var action: (label: LocalizedStringKey, run: () -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            Text(title).font(Theme.Fonts.body.weight(.semibold))
            if let message { Text(message).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.leading) }
            if let action {
                Button(action: action.run) {
                    Text(action.label)
                }.buttonStyle(InkButtonStyle()).padding(.top, 8)
            }
        }
        .padding(24).frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .center)
    }
}

/// Full-width ink button, with an explicit disabled appearance.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.Fonts.body.weight(.semibold))
            .padding(.horizontal, 16)
            .foregroundStyle(isEnabled ? Theme.background : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(isEnabled ? (configuration.isPressed ? Theme.textSecondary : Theme.ink) : Theme.controlFill,
                        in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Language: Identifiable, Hashable {
    let code: String, name: String, locale: String
    var id: String { code }
    var displayName: String { L10n.string(name) }
    static let all: [Language] = [
        .init(code: "ja", name: "Japanese", locale: "ja-JP"),
        .init(code: "en", name: "English", locale: "en-US"),
        .init(code: "zh", name: "Chinese", locale: "zh-CN"),
        .init(code: "ko", name: "Korean", locale: "ko-KR"),
        .init(code: "es", name: "Spanish", locale: "es-ES"),
        .init(code: "fr", name: "French", locale: "fr-FR"),
        .init(code: "de", name: "German", locale: "de-DE"),
    ]
    static func find(_ code: String) -> Language { all.first { $0.code == code } ?? all[0] }
    static var deviceDefault: String {
        let c = Locale.current.language.languageCode?.identifier ?? "en"
        return all.contains { $0.code == c } && c != "ja" ? c : "en"
    }
}

enum Prefs {
    static var target: Language { Language.find(UserDefaults.standard.string(forKey: "targetLang") ?? "ja") }
    static var native: Language { Language.find(UserDefaults.standard.string(forKey: "nativeLang") ?? Language.deviceDefault) }
}

/// Lays children out left to right, wrapping like text.
struct FlowLayout: Layout {
    var lineSpacing: CGFloat = 2
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w && x > 0 { x = 0; y += rowH + lineSpacing; rowH = 0 }
            x += sz.width; rowH = max(rowH, sz.height); maxX = max(maxX, x)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + lineSpacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width; rowH = max(rowH, sz.height)
        }
    }
}
