import SwiftUI
import SwiftData

/// Today's checklist and a few long-run counts, all derived from real activity.
/// Vocabulary reflects the current schedule. Immersion days come from dated logs.
@MainActor
struct LearningJourneySnapshot {
    static let anchorCount = 4

    let plan: StudyPlan
    let todayImmersion: Double
    let immersionGoal: Double
    let todayReviewed: Int
    let todaySaved: Int
    let totalImmersion: Double
    let totalWords: Int
    /// Cards recalled well enough to wait three weeks or more between reviews.
    let wordsStuck: Int
    let activeDays: Int
    let activeDaysThisWeek: Int
    let coachMessages: Int
    let totalCoachMessages: Int

    var reviewDone: Bool { plan.queue.isEmpty }
    var immersionDone: Bool { todayImmersion >= immersionGoal }
    var discoveryDone: Bool { todaySaved > 0 }
    var expressionDone: Bool { coachMessages > 0 }
    var todayStepsDone: Int { [reviewDone, immersionDone, discoveryDone, expressionDone].filter { $0 }.count }

    static func make(cards: [Card], logs: [ImmersionLog], entries: [DictEntry], messages: [ChatMsg], defaults: UserDefaults, now: Date = Date(), calendar: Calendar = .current) -> LearningJourneySnapshot {
        let plan = DailyStudy.plan(cards, defaults: defaults, now: now)
        let today = { (date: Date) in calendar.isDate(date, inSameDayAs: now) }
        let dayStart = calendar.startOfDay(for: now)
        let seconds = { (log: ImmersionLog) in max(0, min(Subtitles.maximumTime, log.seconds)) }
        let todayImmersion = logs.filter { today($0.day) }.reduce(0) { $0 + seconds($1) }
        let defaultGoal = defaults.object(forKey: "dailyGoal") == nil ? 15 : defaults.integer(forKey: "dailyGoal")
        let goal = max(15, defaultGoal) * 60
        let todayReviewed = cards.filter { $0.lastCompletedAt.map(today) ?? false }.count
        let words = entries.filter { $0.kind == "word" }
        let todaySaved = Set(words.filter { today($0.createdAt) }.map { QuickDictionary.normalized($0.term) }).count
        let totalImmersion = logs.reduce(0) { $0 + seconds($1) }
        let totalWords = Set(words.map { QuickDictionary.normalized($0.term) } + cards.map { QuickDictionary.normalized($0.word) })
            .filter { !$0.isEmpty }.count
        let wordsStuck = Set(cards.filter { StudyLexicon.stage($0) == .known }.map { $0.languageCode + ":" + QuickDictionary.normalized($0.word) }).count
        let userMessages = messages.filter { $0.role == "user" }
        let days = Set(logs.filter { seconds($0) > 0 }.map { calendar.startOfDay(for: $0.day) }).filter { $0 <= dayStart }
        let weekStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        return LearningJourneySnapshot(plan: plan, todayImmersion: todayImmersion, immersionGoal: Double(goal),
                                       todayReviewed: todayReviewed, todaySaved: todaySaved, totalImmersion: totalImmersion,
                                       totalWords: totalWords, wordsStuck: wordsStuck, activeDays: days.count,
                                       activeDaysThisWeek: days.filter { $0 >= weekStart }.count,
                                       coachMessages: userMessages.filter { today($0.createdAt) }.count,
                                       totalCoachMessages: userMessages.count)
    }
}

private struct JourneyRoutineRow: View {
    let title: LocalizedStringKey
    let detail: String
    let done: Bool
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : symbol).foregroundStyle(done ? Theme.accent : Theme.ink).frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        }
        .buttonStyle(TextActionStyle())
        .disabled(done)
        .opacity(done ? 0.68 : 1)
    }
}

/// The Read home entry: today's state and one action that starts the right thing directly.
/// Absent until there is something to study, so a new library opens on its sources instead of "caught up".
struct DailyStudySection: View {
    @Query private var cards: [Card]
    @Environment(\.studyDefaults) private var defaults
    @Environment(AppState.self) private var app
    var body: some View {
        if !cards.isEmpty { section }
    }
    private var section: some View {
        TimelineView(.periodic(from: .now, by: 30)) { time in
            let plan = DailyStudy.plan(cards, defaults: defaults, now: time.date)
            VStack(alignment: .leading, spacing: 12) {
                // The heading is the way into Today: one entry, not a second row beside the action.
                Button { app.studyDestination = .today } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("study.today").literary(.title2, bold: true)
                        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(PressFeedbackStyle()).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("journey.open")
                Text(plan.remaining == 0 ? "study.goalDone" : (plan.queue.isEmpty ? "study.caughtUp" : "study.ready"))
                    .font(.body).foregroundStyle(Theme.textSecondary)
                // The one acknowledgement on return from a session.
                if plan.completed > 0 {
                    Text(L10n.format("study.completedCount", Int64(plan.completed)))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
                // With cards waiting, one tap starts review; otherwise it opens Today and its next step.
                Button { app.studyDestination = plan.destination } label: {
                    Label(plan.queue.isEmpty ? "study.viewToday" : "study.start", systemImage: plan.queue.isEmpty ? "checkmark" : "play.fill")
                }.buttonStyle(CompactActionStyle()).accessibilityIdentifier("study.start")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
    }
}

/// Today: the plan, the next step, today's anchors and progress that keeps growing.
struct DailyStudyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.studyDefaults) private var defaults
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var phase
    @Query private var cards: [Card]
    @Query private var logs: [ImmersionLog]
    @Query private var entries: [DictEntry]
    @Query private var messages: [ChatMsg]
    @Query(sort: \Material.createdAt, order: .reverse) private var materials: [Material]
    @Query(sort: \PDFDoc.createdAt, order: .reverse) private var documents: [PDFDoc]
    @State private var library = WordListLibrary.shared
    @State private var preparing = true
    @State private var reviewing = false
    @State private var freePracticing = false
    @State private var failure: String?
    @State private var settings = false
    @State private var reminders = StudyReminders.shared
    @State private var requestingReminder = false
    @AppStorage("study.reminders") private var reminderEnabled = false
    @State private var now = Date()
    @AppStorage("targetLang") private var language = "ja"
    @AppStorage("lastOpenedMaterial") private var lastMaterial = ""
    @AppStorage("lastOpenedDocument") private var lastDocument = ""

    private var snapshot: LearningJourneySnapshot {
        LearningJourneySnapshot.make(cards: cards, logs: logs, entries: entries, messages: messages, defaults: defaults, now: now)
    }

    var body: some View {
        let snapshot = snapshot
        let plan = snapshot.plan
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(plan.remaining == 0 ? "study.goalDone" : (plan.queue.isEmpty && !preparing ? "study.caughtUp" : "study.readyTitle"))
                            .literary(.title1, bold: true)
                        if preparing { ProgressView("study.preparing") }
                        else { primary(snapshot) }
                    }
                    anchors(snapshot)
                    // Secondary paths stay one quiet row each; long-run progress lives one level down.
                    VStack(alignment: .leading, spacing: 0) {
                        if !cards.isEmpty {
                            Button { freePracticing = true } label: {
                                ActionRowLabel(title: "study.freePractice", symbol: "infinity")
                            }.buttonStyle(TextActionStyle()).accessibilityIdentifier("study.freePractice")
                        }
                        NavigationLink { JourneyProgressView(snapshot: snapshot) } label: {
                            ActionRowLabel(title: "journey.progress", symbol: "chart.line.uptrend.xyaxis")
                        }.buttonStyle(TextActionStyle()).accessibilityIdentifier("journey.progress")
                    }
                    // The reminder opt-in belongs to the finished day, not to the start of it.
                    if !reminderEnabled && !preparing && plan.queue.isEmpty { reminderAction(plan) }
                }.padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(Theme.background).foregroundStyle(Theme.ink)
            .navigationTitle("study.today").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("study.settings").accessibilityIdentifier("study.configure")
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await prepare() }
            .onChange(of: phase) { _, phase in if phase == .active { Task { await prepare() } } }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in now = date }
            .fullScreenCover(isPresented: $reviewing, onDismiss: { Task { await prepare() } }) { ReviewView() }
            .fullScreenCover(isPresented: $freePracticing) { ReviewView(session: .free) }
            .sheet(isPresented: $settings, onDismiss: { Task { await prepare() } }) { NavigationStack { StudySettingsView() } }
        }
    }

    // MARK: Sections

    @ViewBuilder private func primary(_ snapshot: LearningJourneySnapshot) -> some View {
        let plan = snapshot.plan
        // One status line: what is waiting, or what was done.
        if !plan.queue.isEmpty {
            Text(L10n.format("study.queueCount", Int64(plan.queue.filter { $0.reps > 0 }.count), Int64(plan.queue.filter { $0.reps == 0 }.count)))
                .font(.body).foregroundStyle(Theme.textSecondary)
            Button { reviewing = true } label: { Label("study.reviewNow", systemImage: "play.fill") }
                .buttonStyle(InkButtonStyle()).accessibilityIdentifier("study.review")
        } else {
            Text(L10n.format("study.completedCount", Int64(plan.completed)))
                .font(.body).foregroundStyle(Theme.textSecondary)
            if let next = plan.nextLearningDate {
                HStack(spacing: 4) {
                    Text("study.retryLater")
                    Text(next, style: .time).monospacedDigit()
                }.font(.body).foregroundStyle(Theme.textSecondary)
            } else if plan.remaining > 0 {
                Text("study.noSource").foregroundStyle(Theme.textSecondary)
            }
            // Review is done: the next anchor becomes the one clear action.
            if let next = nextAnchor(snapshot) {
                Button { next.action() } label: { Label(next.title, systemImage: next.symbol) }
                    .buttonStyle(InkButtonStyle()).accessibilityIdentifier("journey.next")
            }
        }
        if let failure {
            Text(failure).foregroundStyle(Theme.errorText)
            Button("Try again") { Task { await prepare() } }.buttonStyle(TextActionStyle())
        }
    }

    private struct Anchor { let title: LocalizedStringKey; let symbol: String; let action: () -> Void }

    private func nextAnchor(_ snapshot: LearningJourneySnapshot) -> Anchor? {
        if !snapshot.immersionDone { return Anchor(title: "journey.action.immerse", symbol: "book", action: openReading) }
        if !snapshot.discoveryDone { return Anchor(title: "journey.action.discover", symbol: "character.magnify", action: { app.tab = .dictionary; dismiss() }) }
        if !snapshot.expressionDone { return Anchor(title: "journey.action.express", symbol: "bubble.left.and.bubble.right", action: { app.tab = .coach; dismiss() }) }
        return nil
    }

    private func anchors(_ snapshot: LearningJourneySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("journey.today").literary(.title2, bold: true).accessibilityAddTraits(.isHeader)
            Text(L10n.format("journey.todaySummary", Int64(snapshot.todayStepsDone), Int64(LearningJourneySnapshot.anchorCount)))
                .font(.subheadline).foregroundStyle(Theme.textSecondary).padding(.top, 4)
            JourneyRoutineRow(title: "journey.routine.review", detail: snapshot.reviewDone ? L10n.string("journey.routine.done") : L10n.format("journey.routine.reviewDetail", Int64(snapshot.plan.queue.count)), done: snapshot.reviewDone, symbol: "rectangle.stack") { reviewing = true }
            JourneyRoutineRow(title: "journey.routine.immerse", detail: snapshot.immersionDone ? L10n.string("journey.routine.done") : L10n.format("journey.routine.immerseDetail", Int64(snapshot.immersionGoal / 60)), done: snapshot.immersionDone, symbol: "headphones") { openReading() }
            JourneyRoutineRow(title: "journey.routine.discover", detail: snapshot.discoveryDone ? L10n.string("journey.routine.saved") : L10n.string("journey.routine.discoverDetail"), done: snapshot.discoveryDone, symbol: "bookmark") { app.tab = .dictionary; dismiss() }
            JourneyRoutineRow(title: "journey.routine.express", detail: snapshot.expressionDone ? L10n.string("journey.routine.done") : L10n.string("journey.routine.expressDetail"), done: snapshot.expressionDone, symbol: "bubble.left") { app.tab = .coach; dismiss() }
        }
    }

    private func reminderAction(_ plan: StudyPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                requestingReminder = true
                Task {
                    await reminders.enable(defaults: defaults)
                    reminderEnabled = defaults.bool(forKey: "study.reminders")
                    await reminders.refresh(defaults: defaults, completed: plan.suppressesTodayReminder)
                    requestingReminder = false
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if requestingReminder { ProgressView().tint(Theme.accent) }
                    else { Image(systemName: "bell").accessibilityHidden(true) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("study.enableReminder").font(.subheadline.weight(.semibold))
                        Text("study.defaultReminder").font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(TextActionStyle()).disabled(requestingReminder)
            if let failure = reminders.failure { Text(failure).font(.footnote).foregroundStyle(Theme.errorText) }
        }
    }

    // MARK: Actions

    /// Back to the learner's own material: the last opened subtitle or PDF.
    private func openReading() {
        if let material = materials.first(where: { $0.id.uuidString == lastMaterial }) ?? materials.first {
            let line = material.lines.indices.contains(material.lastLine) ? material.lines[material.lastLine].start : 0
            app.open(.material(id: material.id.uuidString, position: line))
        } else if let document = documents.first(where: { $0.id.uuidString == lastDocument }) ?? documents.first {
            app.open(.document(id: document.id.uuidString, page: document.lastPage))
        } else { app.tab = .read }
        dismiss()
    }

    private func prepare() async {
        preparing = true; failure = nil
        defer { preparing = false }
        do {
            let plan = try await DailyStudy.preparedPlan(context: context, library: library, defaults: defaults)
            failure = library.error
            now = Date()
            await StudyReminders.shared.refresh(defaults: defaults, completed: plan.suppressesTodayReminder)
        } catch { if !(error is CancellationError) { failure = L10n.string("study.prepareError") } }
    }
}

/// Long-run progress, one level below Today: a few honest counts and the immersion log. No tiers or phases.
struct JourneyProgressView: View {
    let snapshot: LearningJourneySnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                progress(snapshot)
            }.padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Theme.background).foregroundStyle(Theme.ink)
        .navigationTitle("journey.progress").navigationBarTitleDisplayMode(.inline)
    }

    private func progress(_ snapshot: LearningJourneySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            statRow("journey.wordsStuck", L10n.format("journey.wordsCount", Int64(snapshot.wordsStuck)))
            statRow("journey.weekActive", L10n.format("journey.weekValue", Int64(snapshot.activeDaysThisWeek)))
            statRow("journey.totalImmersion", Immersion.format(snapshot.totalImmersion))
            statRow("journey.wordsCollected", L10n.format("journey.wordsCount", Int64(snapshot.totalWords)))
            Text("journey.stuckHelp").font(.footnote).foregroundStyle(Theme.textSecondary).padding(.top, 8)
            NavigationLink { ImmersionView() } label: {
                ActionRowLabel(title: "nav.immersion", symbol: "headphones")
            }.buttonStyle(TextActionStyle()).padding(.top, 8)
        }
    }

    private func statRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(value).font(.body.weight(.semibold).monospacedDigit()).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
    }
}

struct WordBookDetailView: View {
    let document: WordListDocument
    @Query private var cards: [Card]
    @Environment(\.studyDefaults) private var defaults
    @State private var now = Date()

    private var bookCards: [Card] {
        cards.filter { $0.wordListID == document.id && $0.languageCode == document.language }
    }
    private var learnedCount: Int { bookCards.filter { $0.reps > 0 }.count }
    private var dueCount: Int { bookCards.filter { $0.reps > 0 && $0.due <= now }.count }
    private var newCount: Int { bookCards.filter { $0.reps == 0 }.count }
    private var mistakeCount: Int { bookCards.filter { $0.lapses > 0 }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                progressHeader
                metrics
                actions
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.ink)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Language.find(document.language).displayName)
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(L10n.format("wordBook.percent", Int64(progressPercent)))
                    .font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            ProgressView(value: Double(learnedCount), total: Double(max(1, document.entries.count)))
                .tint(Theme.accent)
            Text(L10n.format("wordBook.learnedSummary", Int64(learnedCount), Int64(document.entries.count)))
                .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
        }
    }

    private var progressPercent: Int {
        guard !document.entries.isEmpty else { return 0 }
        return min(100, learnedCount * 100 / document.entries.count)
    }

    private var metrics: some View {
        VStack(spacing: 0) {
            metricRow("wordBook.due", dueCount)
            metricRow("wordBook.new", newCount)
            metricRow("wordBook.mistakes", mistakeCount)
        }
    }

    private func metricRow(_ title: LocalizedStringKey, _ value: Int) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(verbatim: "\(value)").font(.body.weight(.semibold).monospacedDigit())
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { ReviewView(session: .daily) } label: {
                Label("wordBook.startDaily", systemImage: "rectangle.stack.fill")
            }.buttonStyle(InkButtonStyle())
            NavigationLink { ReviewView(session: .free) } label: {
                Label("review.freePractice", systemImage: "infinity")
            }.buttonStyle(PaperActionStyle(expanded: true))
        }
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
    @AppStorage("study.minimumLevel") private var minimumLevel = DailyStudy.defaultEnglishMinimumLevel
    @AppStorage("study.autoCards") private var autoCards = true
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() },
                set: { hour = Calendar.current.component(.hour, from: $0); minute = Calendar.current.component(.minute, from: $0) })
    }
    private var currentDocument: WordListDocument? {
        guard source != "automatic", source != "saved" else { return nil }
        return library.documents.first { $0.id == source && $0.language == language }
    }

    private var currentBookLearnedCount: Int {
        guard let document = currentDocument else { return 0 }
        return cards.filter { $0.wordListID == document.id && $0.reps > 0 }.count
    }

    private var wordBookPicker: some View {
        Picker("study.wordBook", selection: $source) {
            Text("study.automatic").tag("automatic")
            Text("study.savedOnly").tag("saved")
            ForEach(library.documents.filter { $0.language == language }) { document in
                Text(document.title).tag(document.id)
            }
            if source != "automatic", source != "saved", !library.documents.contains(where: { $0.id == source && $0.language == language }) {
                Text("study.sourceUnavailable").tag(source)
            }
        }
    }

    private var currentBookSummary: some View {
        Group {
            if let document = currentDocument {
                NavigationLink {
                    WordBookDetailView(document: document)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(document.title).font(Theme.Fonts.body.weight(.semibold))
                            Spacer()
                            Text(L10n.format("study.bookProgress", Int64(currentBookLearnedCount), Int64(document.entries.count)))
                                .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        }
                        ProgressView(value: Double(currentBookLearnedCount), total: Double(max(1, document.entries.count)))
                            .tint(Theme.accent)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } else if source == "saved" {
                Label("study.savedBookDetail", systemImage: "bookmark")
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            } else {
                Label("study.automaticBookDetail", systemImage: "wand.and.stars")
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("study.remindDaily", isOn: Binding(get: { enabled }, set: { value in
                if value {
                    requesting = true
                    Task { await reminders.enable(defaults: defaults); enabled = defaults.bool(forKey: "study.reminders"); requesting = false; await reschedule() }
                } else {
                    enabled = false
                    reminders.cancel()
                }
            })).disabled(requesting).accessibilityIdentifier("study.reminderToggle")
            if requesting { ProgressView() }
            if enabled { DatePicker("study.time", selection: time, displayedComponents: .hourAndMinute) }
            if let failure = reminders.failure {
                Text(failure).foregroundStyle(Theme.errorText)
                if let url = URL(string: UIApplication.openSettingsURLString) { Link("study.openSettings", destination: url) }
            }
        } header: { Text("study.reminders") } footer: { Text("study.reminderHelp") }.listRowBackground(Theme.surface)
    }

    var body: some View {
        List {
            Section {
                Picker("Learning language", selection: $language) { Text("Japanese").tag("ja"); Text("English").tag("en") }
                Stepper(value: $limit, in: 5...100, step: 5) { Text(L10n.format("study.dailyLimit", Int64(limit))) }
                Stepper(value: $newLimit, in: 0...20) { Text(L10n.format("study.newLimit", Int64(newLimit))) }
                if language == "en" {
                    Picker("study.minimumLevel", selection: $minimumLevel) {
                        Text("All levels").tag("all")
                        ForEach(WordLevel.ordered, id: \.self) { level in
                            Text(L10n.format("study.levelAndAbove", WordListMetadata.level(level))).tag(level)
                        }
                    }
                }
                wordBookPicker
                currentBookSummary
                Toggle("study.autoCards", isOn: $autoCards)
            } header: { Text("study.plan") } footer: { Text("study.planHelp") }.listRowBackground(Theme.surface)
            remindersSection
        }
        .scrollContentBackground(.hidden).background(Theme.groupedBackground).tint(Theme.accent)
        .navigationTitle("study.settings").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await library.load() }
        .onChange(of: hour) { _, _ in Task { await reschedule() } }
        .onChange(of: minute) { _, _ in Task { await reschedule() } }
        .onChange(of: limit) { _, _ in Task { await reschedule() } }
        .onChange(of: newLimit) { _, _ in Task { await reschedule() } }
        .onChange(of: minimumLevel) { _, _ in Task { await reschedule() } }
        .onChange(of: phase) { _, value in handlePhase(value) }
    }
    private func handlePhase(_ value: ScenePhase) {
        guard value == .active else { return }
        Task { await reschedule() }
    }

    private func reschedule() async {
        let plan = DailyStudy.plan(cards, defaults: defaults)
        await reminders.refresh(defaults: defaults, completed: plan.suppressesTodayReminder)
    }
}
