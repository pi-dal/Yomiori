import SwiftUI
import SwiftData
import UIKit

@main
struct KotobaApp: App {
    @State private var app = AppState()

    init() {
        let preferences = UserDefaults.standard
        if preferences.object(forKey: "targetLang") == nil { preferences.set("ja", forKey: "targetLang") }
        if preferences.object(forKey: "nativeLang") == nil { preferences.set(Language.deviceDefault, forKey: "nativeLang") }
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(Theme.background)
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold)),
            .foregroundColor: UIColor(Theme.ink)
        ]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.ink)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
        }
        .modelContainer(for: [Material.self, DictEntry.self, PDFDoc.self, ChatMsg.self, Mistake.self, Card.self, ImmersionLog.self])
    }
}

enum AppTab: Hashable { case read, documents, dictionary, coach }

@Observable
final class AppState {
    var tab: AppTab = .read
    var pendingCoachPrompt: String?
    var pendingContext: String?
    /// "Go to source": open a subtitle at a time, or a PDF at a page.
    var jumpMaterial: (id: String, time: Double)?
    var jumpDoc: (id: String, page: Int)?
    func goToSource(_ e: DictEntry) {
        if e.sourceKind == "subtitle" { jumpMaterial = (e.sourceID, e.sourcePos); tab = .read }
        else if e.sourceKind == "pdf" { jumpDoc = (e.sourceID, Int(e.sourcePos)); tab = .documents }
    }
    func askCoach(_ prompt: String, context: String? = nil, languageCode: String? = nil) {
        if let languageCode { UserDefaults.standard.set(languageCode, forKey: "targetLang") }
        pendingCoachPrompt = prompt
        pendingContext = context
        tab = .coach
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var keyboardVisible = false
    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            TabView(selection: $app.tab) {
            Tab("Read", systemImage: "book", value: AppTab.read) { ReadView().toolbar(.hidden, for: .tabBar) }
            Tab("Documents", systemImage: "doc.text", value: AppTab.documents) { DocumentsView().toolbar(.hidden, for: .tabBar) }
            Tab("Dictionary", systemImage: "character.book.closed", value: AppTab.dictionary) { DictionaryView().toolbar(.hidden, for: .tabBar) }
            Tab("Coach", systemImage: "bubble.left.and.bubble.right", value: AppTab.coach) { CoachView().toolbar(.hidden, for: .tabBar) }
            }
            if !keyboardVisible { FocusTabBar(selection: $app.tab) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onAppear { Analytics.capture("app_opened") ; Analytics.screen(String(describing: app.tab)) }
        .onChange(of: app.tab) { _, t in Analytics.screen(String(describing: t)) }
    }
}

/// Owns the bottom safe area once; every destination keeps its native navigation stack.
private struct FocusTabBar: View {
    @Binding var selection: AppTab
    private let tabs: [(AppTab, String, String)] = [
        (.read, "Read", "book"), (.documents, "Documents", "doc.text"),
        (.dictionary, "Dictionary", "character.book.closed"), (.coach, "Coach", "bubble.left.and.bubble.right")
    ]
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(tabs, id: \.0) { tab, label, symbol in
                    let selected = selection == tab
                    Button { selection = tab } label: {
                        VStack(spacing: 4) {
                            Image(systemName: symbol).font(.system(size: 20, weight: selected ? .semibold : .regular))
                                .frame(width: 24, height: 24).accessibilityHidden(true)
                            Text(LocalizedStringKey(label)).font(Theme.Fonts.meta.weight(selected ? .semibold : .regular))
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(selected ? Theme.ink : Theme.textSecondary)
                        .padding(.horizontal, 4).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 8)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}
