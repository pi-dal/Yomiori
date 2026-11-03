import SwiftUI
import SwiftData
import UIKit

@main
struct YomioriApp: App {
    @State private var app = AppState()

    init() {
        let preferences = UserDefaults.standard
        if preferences.object(forKey: "targetLang") == nil { preferences.set("ja", forKey: "targetLang") }
        if preferences.object(forKey: "nativeLang") == nil { preferences.set(Language.deviceDefault, forKey: "nativeLang") }
        // Navigation titles are set like a book's chapter heads; the bar itself stays native.
        let mincho = Theme.Fonts.interfaceUsesMincho, ink = UIColor(Theme.ink)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: Theme.Fonts.literary(.largeTitle, bold: true, mincho: mincho, size: .large)), .foregroundColor: ink]
        bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: Theme.Fonts.literary(.headline, bold: true, mincho: mincho, size: .large)), .foregroundColor: ink]
    }

    var body: some Scene {
        WindowGroup {
            entryView
                .environment(app)
                .tint(Theme.accent)
                .listRowSeparatorTint(Theme.separator)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
        }
        .modelContainer(for: [Material.self, DictEntry.self, PDFDoc.self, ChatMsg.self, Mistake.self, Card.self, ImmersionLog.self])
    }

    @ViewBuilder private var entryView: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--library-design-preview") {
            LibraryDesignPreview()
                .modelContainer(for: [Material.self, DictEntry.self, PDFDoc.self, ChatMsg.self, Mistake.self, Card.self, ImmersionLog.self], inMemory: true)
        } else if ProcessInfo.processInfo.arguments.contains("--pdf-preview") {
            PDFReadingPreview().modelContainer(for: [PDFDoc.self, DictEntry.self], inMemory: true)
        } else if ProcessInfo.processInfo.arguments.contains("--component-preview") {
            ComponentPreview().modelContainer(for: Card.self, inMemory: true)
        } else { RootView() }
        #else
        RootView()
        #endif
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
    func resetNavigation() {
        tab = .read; pendingCoachPrompt = nil; pendingContext = nil; jumpMaterial = nil; jumpDoc = nil
    }
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
    @State private var operations = Operations.shared
    @Environment(\.modelContext) private var context
    @State private var resetError: String?
    var body: some View {
        @Bindable var app = app
        Group {
            if operations.resetPending {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Finish clearing data").font(Theme.Fonts.body.weight(.semibold))
                    Text("Data clearing was interrupted. Retry to finish before continuing.")
                    if let resetError { Text(resetError).foregroundStyle(Theme.errorText) }
                    Button("Try again") { finishReset() }.buttonStyle(InkButtonStyle())
                }.padding(24).frame(maxWidth: 720)
            } else { content(app: app).id(operations.generation) }
        }
        .task { if operations.resetPending { finishReset() } }
    }
    private func finishReset() {
        do { try AppDataService.clear(context: context); app.resetNavigation(); resetError = nil }
        catch { resetError = error.localizedDescription }
    }
    private func content(app: AppState) -> some View {
        @Bindable var app = app
        return TabView(selection: $app.tab) {
            Tab("Read", systemImage: "book", value: AppTab.read) { ReadView() }
            Tab("Documents", systemImage: "doc.text", value: AppTab.documents) { DocumentsView() }
            Tab("Dictionary", systemImage: "character.book.closed", value: AppTab.dictionary) { DictionaryView() }
            Tab("Coach", systemImage: "bubble.left.and.bubble.right", value: AppTab.coach) { CoachView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
