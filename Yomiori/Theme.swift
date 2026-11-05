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
    // The app icon's world: kinari washi paper, sumi ink, matcha leaves, sakura petals and a shu seal.
    // Native Liquid Glass still belongs to floating controls; these tones own the ground beneath them.
    static let background = Color(light: 0xF5F0E6, dark: 0x1B1916)
    static let surface = Color(light: 0xFBF8F2, dark: 0x26231F)
    static let groupedBackground = Color(light: 0xEDE7DB, dark: 0x131210)
    static let controlFill = Color(light: 0xE9E2D5, dark: 0x2A2723)
    static let controlHover = Color(light: 0xE2DACB, dark: 0x322E2A)
    static let controlSelected = Color(light: 0xD8CFBE, dark: 0x3B3732)
    static let separator = Color(light: 0xDAD1C1, dark: 0x3A352F)
    static let controlBorder = separator
    static let focusBorder = ink
    static let textSecondary = Color(light: 0x6B655C, dark: 0xA49C8F)
    static let ink = Color(light: 0x2B2824, dark: 0xECE5D7)
    /// Matcha: the single interactive tint.
    static let accent = Color(light: 0x46663F, dark: 0xA3C095)
    static let onAccent = background
    static let solid = accent
    static let solidHover = accent
    /// Shu: errors and the reading-position bookmark.
    static let vermilion = Color(light: 0xB23A26, dark: 0xEE8A70)
    static let errorText = vermilion
    static let errorBackground = Color(light: 0xF6E2D9, dark: 0x3A201A)
    static let errorBorder = vermilion
    /// Sakura wash behind highlighted text.
    static let highlight = Color(light: 0xEFA7B4, dark: 0xD27A8B).opacity(0.42)
    static let dim = textSecondary
    static let track = controlSelected
    static let weak = ink
    static let good = ink

    enum Fonts {
        static var meta: Font { .subheadline }
        static var body: Font { .body }
        static var focus: Font { .title }

        /// Hiragino Mincho lacks most Simplified Chinese glyphs; interface copy in Chinese keeps one consistent fallback face.
        static var interfaceUsesMincho: Bool { !(Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("zh") }

        /// New York for Latin text, cascading to Hiragino Mincho for kana and kanji, sized by Dynamic Type.
        static func literary(_ style: UIFont.TextStyle, bold: Bool = false, mincho: Bool = true,
                             size category: UIContentSizeCategory = UIApplication.shared.preferredContentSizeCategory) -> UIFont {
            let size = UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: category)).pointSize
            var descriptor = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular).fontDescriptor
            descriptor = descriptor.withDesign(.serif) ?? descriptor
            if mincho {
                descriptor = descriptor.addingAttributes([.cascadeList: [UIFontDescriptor(name: bold ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size)]])
            }
            return UIFont(descriptor: descriptor, size: size)
        }
    }
}

/// Original text always reads in Mincho; interface copy does when the interface language supports it.
enum LiteraryScript { case original, interface }

private struct LiteraryFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let style: UIFont.TextStyle, bold: Bool, script: LiteraryScript
    func body(content: Content) -> some View {
        content.font(Font(Theme.Fonts.literary(style, bold: bold, mincho: script == .original || Theme.Fonts.interfaceUsesMincho,
                                               size: UIContentSizeCategory(dynamicTypeSize))))
    }
}

extension View {
    func literary(_ style: UIFont.TextStyle, bold: Bool = false, _ script: LiteraryScript = .interface) -> some View {
        modifier(LiteraryFont(style: style, bold: bold, script: script))
    }
}

/// A short ink rule ending in a dot, used beside section labels like a brush stroke trailing off.
struct InkRule: View {
    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            Circle().fill(Theme.vermilion.opacity(0.85)).frame(width: 4, height: 4)
        }
        .accessibilityHidden(true)
    }
}

/// A section label set in Mincho, trailed by an ink rule.
struct SectionLabel: View {
    let title: LocalizedStringKey
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).literary(.headline, bold: true).foregroundStyle(Theme.ink).fixedSize()
            InkRule()
        }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
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

/// Shared library ordering keeps title comparisons natural (for example, Chapter 2 before Chapter 10).
enum LibraryOrder: String, CaseIterable {
    case newest, title

    var label: LocalizedStringKey {
        switch self {
        case .newest: "Newest first"
        case .title: "Title"
        }
    }

    func sorted<Item>(_ items: [Item], title: (Item) -> String, createdAt: (Item) -> Date) -> [Item] {
        items.sorted { left, right in
            if self == .title {
                let order = title(left).localizedStandardCompare(title(right))
                if order != .orderedSame { return order == .orderedAscending }
            }
            return createdAt(left) > createdAt(right)
        }
    }
}

struct LibrarySearchEmpty: View {
    @Binding var search: String

    var body: some View {
        ContentUnavailableView {
            Label("No matching titles", systemImage: "magnifyingglass")
        } description: {
            Text("Try another title or clear your search.")
        } actions: {
            Button("Clear search") { search = "" }
                .foregroundStyle(Theme.accent).frame(minHeight: 44)
        }
    }
}

/// Native segmented controls retain system selection, focus and accessibility behavior.
struct TextTabs: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let items: [(id: String, label: String)]
    @Binding var selection: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                Picker("", selection: $selection) {
                    ForEach(items, id: \.id) { item in
                        Text(LocalizedStringKey(item.label)).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.id) { item in
                        Button { selection = item.id } label: {
                            Text(LocalizedStringKey(item.label))
                                .font(Theme.Fonts.meta.weight(.semibold))
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .foregroundStyle(selection == item.id ? Theme.onAccent : Theme.ink)
                                .background(selection == item.id ? Theme.accent : Theme.controlFill, in: Capsule())
                        }
                        .buttonStyle(PressFeedbackStyle())
                        .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 4)
    }
}

/// A reading-oriented introduction with compact controls and room for the library.
struct EmptyState: View {
    let symbol: String, title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var action: (label: LocalizedStringKey, run: () -> Void)?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).literary(.title2)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                if let action {
                    Button(action: action.run) {
                        HStack(spacing: 10) {
                            Text(action.label)
                            Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(CompactActionStyle())
                    .padding(.top, 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 32)
        }
        .frame(maxWidth: 640).frame(maxWidth: .infinity)
    }
}

/// A direct source entry point, with native-sized hit areas and structural separators.
struct SourceAction: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: symbol).font(.title3).frame(width: 28)
                    .foregroundStyle(Theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackStyle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
    }
}

/// Shared action treatment; visual density is independent from the 44pt touch target.
struct CompactActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(ActionSurface(pressed: configuration.isPressed, role: configuration.role))
    }
}

/// A paper inset for secondary tasks; destructive actions retain vermilion in every state.
struct PaperActionStyle: ButtonStyle {
    var expanded = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(ActionSurface(pressed: configuration.isPressed, role: configuration.role,
                                                   primary: false, expanded: expanded))
    }
}

private struct ActionSurface: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pressed: Bool
    let role: ButtonRole?
    var primary = true
    var expanded = false
    var isStatic = false
    private var foreground: Color {
        guard enabled else { return Theme.textSecondary }
        if role == .destructive { return primary ? Theme.background : Theme.vermilion }
        return primary ? Theme.background : Theme.accent
    }
    private var fill: Color {
        guard enabled else { return Theme.controlFill }
        if primary { return role == .destructive ? Theme.vermilion : Theme.ink }
        return pressed ? Theme.controlSelected : Theme.controlFill
    }
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18).padding(.vertical, 13)
            .frame(maxWidth: expanded ? .infinity : nil, minHeight: 48)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(pressed && enabled && primary ? 0.88 : 1)
            .scaleEffect(pressed && enabled && !reduceMotion && !isStatic ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: pressed)
    }
}

/// Inline commands retain the reading rhythm while keeping a full-size touch target.
struct TextActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(enabled ? (configuration.role == .destructive ? Theme.vermilion : Theme.accent) : Theme.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed && enabled ? 0.6 : 1)
    }
}

/// Navigation-like actions belong to the content grid, with a quiet directional affordance.
struct ActionRowLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    var detail: String? = nil
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).font(.body).frame(width: iconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail { Text(verbatim: detail).font(.footnote).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 12)
            Image(systemName: "chevron.right").font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Consistent page heading inside a system navigation stack.
struct PageHeading: View {
    let title: LocalizedStringKey
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).literary(.title1, bold: true)
            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
        .accessibilityElement(children: .combine)
    }
}

/// Full-width version for tasks that need a single primary action.
struct InkButtonStyle: ButtonStyle {
    var isStatic = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(ActionSurface(pressed: configuration.isPressed, role: configuration.role,
                                                   expanded: true, isStatic: isStatic))
    }
}

/// Tactile feedback for custom content buttons; native controls keep native behavior.
struct PressFeedbackStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isStatic = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && enabled ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && enabled && !reduceMotion && !isStatic ? 0.985 : 1)
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0, 0, 1, duration: 0.15), value: configuration.isPressed)
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
