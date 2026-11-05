import SwiftUI
import SwiftData

/// Reconcile on launch, foreground and calendar changes; iOS delivers the local reminders while suspended.
struct StudyLifecycle: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.studyDefaults) private var defaults
    @Environment(\.scenePhase) private var phase
    @Environment(AppState.self) private var app
    @State private var reminders = StudyReminders.shared
    @State private var library = WordListLibrary.shared
    @State private var revision = 0
    @State private var error: String?
    func body(content: Content) -> some View {
        content
            .task(id: revision) { await refresh() }
            .onChange(of: phase) { _, phase in if phase == .active { revision += 1 } }
            .onChange(of: reminders.openStudy) { _, value in route(value) }
            .onAppear { route(reminders.openStudy) }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in revision += 1 }
            .alert("study.prepareError", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Try again") { revision += 1 }
                Button("Cancel", role: .cancel) {}
            }
    }
    private func route(_ value: Bool) {
        guard value, !Operations.shared.resetPending else { return }
        reminders.openStudy = false; app.tab = .read; app.showStudy = true
    }
    private func refresh() async {
        let generation = Operations.shared.generation
        await library.load()
        do {
            try Operations.shared.checkpoint(generation)
            try DailyStudy.prepare(context: context, documents: library.documents, defaults: defaults)
            let cards = try context.fetch(FetchDescriptor<Card>())
            let plan = DailyStudy.plan(cards, defaults: defaults)
            await reminders.refresh(defaults: defaults, completed: plan.remaining == 0 || (plan.completed > 0 && plan.queue.isEmpty && plan.nextLearningDate == nil))
        } catch { if !(error is CancellationError) { self.error = L10n.string("study.prepareError") } }
    }
}
