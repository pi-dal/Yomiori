import SwiftUI
import SwiftData

/// A single place to see today's workload and enter the existing focused review experience.
struct DailyStudySection: View {
    @Query private var cards: [Card]
    @Environment(\.studyDefaults) private var defaults
    @Environment(AppState.self) private var app
    @State private var settings = false
    @AppStorage("reviewLimit") private var limit = 30
    @AppStorage("study.newLimit") private var newLimit = 5
    @AppStorage("targetLang") private var language = "ja"
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { time in
            let plan = StudyPlan(cards: cards, reviewLimit: limit, newLimit: newLimit, language: language, now: time.date)
            VStack(alignment: .leading, spacing: 12) {
                Text("study.today").literary(.title2, bold: true).accessibilityAddTraits(.isHeader)
                Text(plan.remaining == 0 ? "study.goalDone" : "study.ready")
                    .font(.body).foregroundStyle(Theme.textSecondary)
                if plan.completed > 0 {
                    Text(L10n.format("study.completedCount", Int64(plan.completed)))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
                Button { app.showStudy = true } label: {
                    Label(plan.remaining == 0 ? "study.viewToday" : "study.start", systemImage: plan.remaining == 0 ? "checkmark" : "play.fill")
                }.buttonStyle(CompactActionStyle()).accessibilityIdentifier("study.start")
                Button { settings = true } label: {
                    ActionRowLabel(title: "study.settings", symbol: "slider.horizontal.3")
                }.buttonStyle(TextActionStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $settings) { NavigationStack { StudySettingsView() }.presentationDetents([.large]) }
    }
}

struct DailyStudyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.studyDefaults) private var defaults
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var phase
    @Query private var cards: [Card]
    @Query(sort: \Material.createdAt, order: .reverse) private var materials: [Material]
    @Query(sort: \PDFDoc.createdAt, order: .reverse) private var documents: [PDFDoc]
    @State private var library = WordListLibrary.shared
    @State private var preparing = true
    @State private var reviewing = false
    @State private var enteredReview = false
    @State private var failure: String?
    @State private var settings = false
    @State private var reminders = StudyReminders.shared
    @State private var requestingReminder = false
    @AppStorage("study.reminders") private var reminderEnabled = false
    @State private var now = Date()
    @AppStorage("reviewLimit") private var limit = 30
    @AppStorage("study.newLimit") private var newLimit = 5
    @AppStorage("targetLang") private var language = "ja"
    @AppStorage("lastOpenedMaterial") private var lastMaterial = ""
    @AppStorage("lastOpenedDocument") private var lastDocument = ""
    private var plan: StudyPlan { StudyPlan(cards: cards, reviewLimit: limit, newLimit: newLimit, language: language, now: now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(plan.remaining == 0 ? "study.goalDone" : (plan.queue.isEmpty && !preparing ? "study.caughtUp" : "study.readyTitle"))
                        .literary(.title1, bold: true)
                    if preparing { ProgressView("study.preparing") }
                    else {
                        Text(L10n.format("study.completedCount", Int64(plan.completed)))
                            .font(.body).foregroundStyle(Theme.textSecondary)
                        if !plan.queue.isEmpty {
                            Text(L10n.format("study.queueCount", Int64(plan.queue.filter { $0.reps > 0 }.count), Int64(plan.queue.filter { $0.reps == 0 }.count)))
                                .font(.body)
                            Button { reviewing = true } label: { Label("study.reviewNow", systemImage: "play.fill") }
                                .buttonStyle(InkButtonStyle()).accessibilityIdentifier("study.review")
                        } else if let next = plan.nextLearningDate {
                            Text("study.retryLater").foregroundStyle(Theme.textSecondary)
                            Text(next, style: .time).font(.body.monospacedDigit())
                        } else if plan.remaining > 0 {
                            Text("study.noSource").foregroundStyle(Theme.textSecondary)
                        }
                        if let failure {
                            Text(failure).foregroundStyle(Theme.errorText)
                            Button("Try again") { Task { await prepare() } }.buttonStyle(TextActionStyle())
                        }
                        reading
                        if !reminderEnabled {
                            Button {
                                requestingReminder = true
                                Task {
                                    await reminders.enable(defaults: defaults)
                                    reminderEnabled = defaults.bool(forKey: "study.reminders")
                                    await reminders.refresh(defaults: defaults, completed: plan.remaining == 0 || (plan.completed > 0 && plan.queue.isEmpty && plan.nextLearningDate == nil))
                                    requestingReminder = false
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if requestingReminder { ProgressView().tint(Theme.accent) }
                                    else { Image(systemName: "bell").accessibilityHidden(true) }
                                    Text("study.enableReminder")
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(PaperActionStyle(expanded: true)).disabled(requestingReminder)
                            Text("study.defaultReminder").font(.footnote).foregroundStyle(Theme.textSecondary)
                            if let failure = reminders.failure { Text(failure).font(.footnote).foregroundStyle(Theme.errorText) }
                        }
                        Button { settings = true } label: {
                            ActionRowLabel(title: "study.settings", symbol: "slider.horizontal.3")
                        }.buttonStyle(TextActionStyle()).accessibilityIdentifier("study.configure")
                    }
                }.padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(Theme.background).foregroundStyle(Theme.ink)
            .navigationTitle("study.today").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await prepare() }
            .onChange(of: phase) { _, phase in if phase == .active { Task { await prepare() } } }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in now = date }
            .fullScreenCover(isPresented: $reviewing, onDismiss: { Task { await prepare() } }) { ReviewView() }
            .sheet(isPresented: $settings, onDismiss: { Task { await prepare() } }) { NavigationStack { StudySettingsView() } }
        }
    }
    @ViewBuilder private var reading: some View {
        if let material = materials.first(where: { $0.id.uuidString == lastMaterial }) ?? materials.first {
            VStack(alignment: .leading, spacing: 12) {
                Text("study.keepReading").literary(.headline, bold: true)
                Button {
                    app.jumpMaterial = (material.id.uuidString, material.lines.indices.contains(material.lastLine) ? material.lines[material.lastLine].start : 0)
                    app.tab = .read; dismiss()
                } label: {
                    ActionRowLabel(title: "Continue reading", symbol: "book", detail: material.title)
                }.buttonStyle(TextActionStyle())
            }
        } else if let document = documents.first(where: { $0.id.uuidString == lastDocument }) ?? documents.first {
            VStack(alignment: .leading, spacing: 12) {
                Text("study.keepReading").literary(.headline, bold: true)
                Button { app.jumpDoc = (document.id.uuidString, document.lastPage); app.tab = .documents; dismiss() } label: {
                    ActionRowLabel(title: "Continue reading", symbol: "doc.text", detail: document.title)
                }.buttonStyle(TextActionStyle())
            }
        }
    }
    private func prepare() async {
        preparing = true; failure = nil
        defer { preparing = false }
        let generation = Operations.shared.generation
        await library.load()
        do {
            try Operations.shared.checkpoint(generation)
            try DailyStudy.prepare(context: context, documents: library.documents, defaults: defaults)
            now = Date()
            let current = try context.fetch(FetchDescriptor<Card>())
            let plan = DailyStudy.plan(current, defaults: defaults)
            if !enteredReview {
                enteredReview = true
                if !plan.queue.isEmpty { reviewing = true }
            }
            await StudyReminders.shared.refresh(defaults: defaults, completed: plan.remaining == 0 || (plan.completed > 0 && plan.queue.isEmpty && plan.nextLearningDate == nil))
        } catch { if !(error is CancellationError) { failure = L10n.string("study.prepareError") } }
    }
}

struct StudySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.studyDefaults) private var defaults
    @Environment(\.scenePhase) private var phase
    @Query private var cards: [Card]
    @State private var library = WordListLibrary.shared
    @State private var reminders = StudyReminders.shared
    @State private var requesting = false
    @AppStorage("study.reminders") private var enabled = false
    @AppStorage("study.hour") private var hour = 20
    @AppStorage("study.minute") private var minute = 0
    @AppStorage("reviewLimit") private var limit = 30
    @AppStorage("study.newLimit") private var newLimit = 5
    @AppStorage("study.source") private var source = "automatic"
    @AppStorage("targetLang") private var language = "ja"
    @AppStorage("study.autoCards") private var autoCards = true
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() },
                set: { hour = Calendar.current.component(.hour, from: $0); minute = Calendar.current.component(.minute, from: $0) })
    }
    var body: some View {
        List {
            Section {
                Picker("Learning language", selection: $language) { Text("Japanese").tag("ja"); Text("English").tag("en") }
                Stepper(value: $limit, in: 5...100, step: 5) { Text(L10n.format("study.dailyLimit", Int64(limit))) }
                Stepper(value: $newLimit, in: 0...20) { Text(L10n.format("study.newLimit", Int64(newLimit))) }
                Picker("study.source", selection: $source) {
                    Text("study.automatic").tag("automatic")
                    Text("study.savedOnly").tag("saved")
                    ForEach(library.documents.filter { $0.language == language }) { document in Text(document.title).tag(document.id) }
                    if source != "automatic", source != "saved", !library.documents.contains(where: { $0.id == source && $0.language == language }) {
                        Text("study.sourceUnavailable").tag(source)
                    }
                }
                Toggle("study.autoCards", isOn: $autoCards)
            } header: { Text("study.plan") } footer: { Text("study.planHelp") }.listRowBackground(Theme.surface)
            Section {
                Toggle("study.remindDaily", isOn: Binding(get: { enabled }, set: { value in
                    if value {
                        requesting = true
                        Task { await reminders.enable(defaults: defaults); enabled = defaults.bool(forKey: "study.reminders"); requesting = false; await reschedule() }
                    } else { enabled = false; reminders.cancel() }
                })).disabled(requesting).accessibilityIdentifier("study.reminderToggle")
                if requesting { ProgressView() }
                if enabled { DatePicker("study.time", selection: time, displayedComponents: .hourAndMinute) }
                if let failure = reminders.failure {
                    Text(failure).foregroundStyle(Theme.errorText)
                    if let url = URL(string: UIApplication.openSettingsURLString) { Link("study.openSettings", destination: url) }
                }
            } header: { Text("study.reminders") } footer: { Text("study.reminderHelp") }.listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden).background(Theme.groupedBackground).tint(Theme.accent)
        .navigationTitle("study.settings").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await library.load() }
        .onChange(of: hour) { _, _ in Task { await reschedule() } }
        .onChange(of: minute) { _, _ in Task { await reschedule() } }
        .onChange(of: limit) { _, _ in Task { await reschedule() } }
        .onChange(of: newLimit) { _, _ in Task { await reschedule() } }
        .onChange(of: phase) { _, value in if value == .active { Task { await reschedule() } } }
    }
    private func reschedule() async {
        let plan = DailyStudy.plan(cards, defaults: defaults)
        await reminders.refresh(defaults: defaults, completed: plan.remaining == 0 || (plan.completed > 0 && plan.queue.isEmpty && plan.nextLearningDate == nil))
    }
}
