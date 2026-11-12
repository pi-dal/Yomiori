import SwiftUI
import SwiftData

/// Today's anchors and long-run progress, all derived from real activity.
/// Nothing here is a score: missed days never take progress away, and every measure only grows.
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

    var phase: JourneyPhase {
        if activeDays < 7 { return .foundation }
        if totalImmersion < 10 * 3600 || wordsStuck < 50 { return .understanding }
        if totalCoachMessages < 20 { return .expression }
        return .expansion
    }

    var tracks: [GrowthTrack] {
        [GrowthTrack(kind: .wordsStuck, value: wordsStuck),
         GrowthTrack(kind: .hours, value: Int(totalImmersion / 3600)),
         GrowthTrack(kind: .activeDays, value: activeDays),
         GrowthTrack(kind: .expressions, value: totalCoachMessages)]
    }

    static func make(cards: [Card], logs: [ImmersionLog], entries: [DictEntry], messages: [ChatMsg], defaults: UserDefaults, now: Date = Date(), calendar: Calendar = .current) -> LearningJourneySnapshot {
        let plan = DailyStudy.plan(cards, defaults: defaults, now: now)
        let today = { (date: Date) in calendar.isDate(date, inSameDayAs: now) }
        let dayStart = calendar.startOfDay(for: now)
        let seconds = { (log: ImmersionLog) in max(0, min(Subtitles.maximumTime, log.seconds)) }
        let todayImmersion = logs.filter { today($0.day) }.reduce(0) { $0 + seconds($1) }
        let defaultGoal = defaults.object(forKey: "dailyGoal") == nil ? 60 : defaults.integer(forKey: "dailyGoal")
        let goal = max(15, defaultGoal) * 60
        let todayReviewed = cards.filter { $0.lastCompletedAt.map(today) ?? false }.count
        let words = entries.filter { $0.kind == "word" }
        let todaySaved = Set(words.filter { today($0.createdAt) }.map { QuickDictionary.normalized($0.term) }).count
        let totalImmersion = logs.reduce(0) { $0 + seconds($1) }
        let totalWords = Set(words.map { QuickDictionary.normalized($0.term) } + cards.map { QuickDictionary.normalized($0.word) })
            .filter { !$0.isEmpty }.count
        let wordsStuck = Set(cards.filter { StudyLexicon.stage($0) == .known }.map { $0.languageCode + ":" + QuickDictionary.normalized($0.word) }).count
        let userMessages = messages.filter { $0.role == "user" }
        // A day counts when the learner did something real: listened or read, reviewed, saved a word or wrote to Coach.
        let activity = Set(logs.filter { seconds($0) > 0 }.map(\.day) + cards.compactMap(\.lastCompletedAt)
            + words.map(\.createdAt) + userMessages.map(\.createdAt)).map { calendar.startOfDay(for: $0) }
        let days = Set(activity).filter { $0 <= dayStart }
        let weekStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        return LearningJourneySnapshot(plan: plan, todayImmersion: todayImmersion, immersionGoal: Double(goal),
                                       todayReviewed: todayReviewed, todaySaved: todaySaved, totalImmersion: totalImmersion,
                                       totalWords: totalWords, wordsStuck: wordsStuck, activeDays: days.count,
                                       activeDaysThisWeek: days.filter { $0 >= weekStart }.count,
                                       coachMessages: userMessages.filter { today($0.createdAt) }.count,
                                       totalCoachMessages: userMessages.count)
    }
}

enum JourneyPhase: CaseIterable, Identifiable {
    case foundation, understanding, expression, expansion
    var id: Self { self }
    var titleKey: LocalizedStringKey {
        switch self {
        case .foundation: "journey.phase.foundation"
        case .understanding: "journey.phase.understanding"
        case .expression: "journey.phase.expression"
        case .expansion: "journey.phase.expansion"
        }
    }
    var detailKey: LocalizedStringKey {
        switch self {
        case .foundation: "journey.phase.foundationDetail"
        case .understanding: "journey.phase.understandingDetail"
        case .expression: "journey.phase.expressionDetail"
        case .expansion: "journey.phase.expansionDetail"
        }
    }
    /// What moves the learner on from this phase, measured from their own activity.
    @MainActor func progress(_ snapshot: LearningJourneySnapshot) -> String? {
        switch self {
        case .foundation: L10n.format("journey.phase.foundationProgress", Int64(snapshot.activeDays))
        case .understanding: L10n.format("journey.phase.understandingProgress", Immersion.format(snapshot.totalImmersion), Int64(snapshot.wordsStuck))
        case .expression: L10n.format("journey.phase.expressionProgress", Int64(snapshot.totalCoachMessages))
        case .expansion: nil
        }
    }
}

extension GrowthTrack.Kind {
    var titleKey: LocalizedStringKey {
        switch self {
        case .wordsStuck: "journey.track.words"
        case .hours: "journey.track.hours"
        case .activeDays: "journey.track.days"
        case .expressions: "journey.track.expressions"
        }
    }
    var symbol: String {
        switch self {
        case .wordsStuck: "leaf"
        case .hours: "headphones"
        case .activeDays: "calendar"
        case .expressions: "bubble.left"
        }
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

/// A milestone track: what has been reached, and how far it is to the next one.
private struct GrowthTrackRow: View {
    let track: GrowthTrack
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: track.reached == nil ? "seal" : "seal.fill")
                .foregroundStyle(track.reached == nil ? Theme.textSecondary : Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Label(track.kind.titleKey, systemImage: track.kind.symbol).labelStyle(.titleOnly).font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(verbatim: "\(track.value)").font(.body.weight(.semibold).monospacedDigit())
                }
                ProgressView(value: track.fraction).tint(Theme.accent).accessibilityHidden(true)
                Text(track.reached.map { L10n.format("journey.track.reachedNext", Int64($0), Int64(track.next)) }
                     ?? L10n.format("journey.track.next", Int64(track.next)))
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// The Read home entry: today's state and one action that starts the right thing directly.
struct DailyStudySection: View {
    @Query private var cards: [Card]
    @Query private var logs: [ImmersionLog]
    @Query private var entries: [DictEntry]
    @Query private var messages: [ChatMsg]
    @Environment(\.studyDefaults) private var defaults
    @Environment(AppState.self) private var app
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { time in
            let snapshot = LearningJourneySnapshot.make(cards: cards, logs: logs, entries: entries, messages: messages, defaults: defaults, now: time.date)
            let plan = snapshot.plan
            VStack(alignment: .leading, spacing: 12) {
                Text("study.today").literary(.title2, bold: true).accessibilityAddTraits(.isHeader)
                Text(L10n.format("journey.todaySummary", Int64(snapshot.todayStepsDone), Int64(LearningJourneySnapshot.anchorCount)))
                    .font(.body).foregroundStyle(Theme.textSecondary)
                Text(L10n.format("journey.todayStats", Immersion.format(snapshot.todayImmersion), Int64(snapshot.todayReviewed)))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                Text(plan.remaining == 0 ? "study.goalDone" : (plan.queue.isEmpty ? "study.caughtUp" : "study.ready"))
                    .font(.body).foregroundStyle(Theme.textSecondary)
                if plan.completed > 0 {
                    Text(L10n.format("study.completedCount", Int64(plan.completed)))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
                // With cards waiting, one tap starts review; otherwise it opens Today and its next step.
                Button { if plan.queue.isEmpty { app.showStudy = true } else { app.showReview = true } } label: {
                    Label(plan.queue.isEmpty ? "study.viewToday" : "study.start", systemImage: plan.queue.isEmpty ? "checkmark" : "play.fill")
                }.buttonStyle(CompactActionStyle()).accessibilityIdentifier("study.start")
                Button { app.showStudy = true } label: {
                    ActionRowLabel(title: "journey.open", symbol: "map",
                                   detail: L10n.format("journey.openDetail", Int64(snapshot.wordsStuck), Int64(snapshot.activeDaysThisWeek)))
                }.buttonStyle(TextActionStyle()).accessibilityIdentifier("journey.open")
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
                    if !cards.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Button { freePracticing = true } label: {
                                Label("study.freePractice", systemImage: "infinity")
                            }.buttonStyle(PaperActionStyle(expanded: true)).accessibilityIdentifier("study.freePractice")
                            Text("study.freePracticeDetail").font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    progress(snapshot)
                    milestones(snapshot)
                    roadmap(snapshot)
                    VStack(alignment: .leading, spacing: 8) {
                        if !reminderEnabled { reminderAction(plan) }
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
            .fullScreenCover(isPresented: $freePracticing) { ReviewView(session: .free) }
            .sheet(isPresented: $settings, onDismiss: { Task { await prepare() } }) { NavigationStack { StudySettingsView() } }
        }
    }

    // MARK: Sections

    @ViewBuilder private func primary(_ snapshot: LearningJourneySnapshot) -> some View {
        let plan = snapshot.plan
        Text(L10n.format("study.completedCount", Int64(plan.completed)))
            .font(.body).foregroundStyle(Theme.textSecondary)
        if language == "en", let minimumLevel = plan.minimumLevel {
            Text(L10n.format("study.minimumLevelSummary", WordListMetadata.level(minimumLevel)))
                .font(.body).foregroundStyle(Theme.textSecondary)
        }
        if !plan.queue.isEmpty {
            Text(L10n.format("study.queueCount", Int64(plan.queue.filter { $0.reps > 0 }.count), Int64(plan.queue.filter { $0.reps == 0 }.count)))
                .font(.body)
            Button { reviewing = true } label: { Label("study.reviewNow", systemImage: "play.fill") }
                .buttonStyle(InkButtonStyle()).accessibilityIdentifier("study.review")
        } else {
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

    private func progress(_ snapshot: LearningJourneySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("journey.progress").literary(.title2, bold: true).accessibilityAddTraits(.isHeader).padding(.bottom, 4)
            statRow("journey.wordsStuck", L10n.format("journey.wordsCount", Int64(snapshot.wordsStuck)))
            statRow("journey.weekActive", L10n.format("journey.weekValue", Int64(snapshot.activeDaysThisWeek)))
            statRow("journey.totalImmersion", Immersion.format(snapshot.totalImmersion))
            statRow("journey.wordsCollected", L10n.format("journey.wordsCount", Int64(snapshot.totalWords)))
            Text("journey.stuckHelp").font(.footnote).foregroundStyle(Theme.textSecondary).padding(.top, 8)
        }
    }

    private func milestones(_ snapshot: LearningJourneySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("journey.milestones").literary(.title2, bold: true).accessibilityAddTraits(.isHeader)
            ForEach(snapshot.tracks, id: \.kind) { GrowthTrackRow(track: $0) }
        }
    }

    private func roadmap(_ snapshot: LearningJourneySnapshot) -> some View {
        let current = snapshot.phase
        let currentIndex = JourneyPhase.allCases.firstIndex(of: current) ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            Text("journey.roadmap").literary(.title2, bold: true).accessibilityAddTraits(.isHeader)
            ForEach(JourneyPhase.allCases) { phase in
                let index = JourneyPhase.allCases.firstIndex(of: phase) ?? 0
                let done = index < currentIndex
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: done ? "checkmark.circle.fill" : phase == current ? "circle.dotted" : "circle")
                        .foregroundStyle(done ? Theme.accent : phase == current ? Theme.vermilion : Theme.textSecondary)
                        .font(.title3).frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(phase.titleKey).font(.body.weight(.semibold))
                        Text(phase.detailKey).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        if phase == current {
                            Text("journey.currentFocus").font(.caption.weight(.semibold)).foregroundStyle(Theme.vermilion)
                            if let progress = phase.progress(snapshot) {
                                Text(progress).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.ink)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
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

    private func reminderAction(_ plan: StudyPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
    }

    // MARK: Actions

    /// Back to the learner's own material: the last opened subtitle or PDF.
    private func openReading() {
        if let material = materials.first(where: { $0.id.uuidString == lastMaterial }) ?? materials.first {
            let line = material.lines.indices.contains(material.lastLine) ? material.lines[material.lastLine].start : 0
            app.jumpMaterial = (material.id.uuidString, line); app.tab = .read
        } else if let document = documents.first(where: { $0.id.uuidString == lastDocument }) ?? documents.first {
            app.jumpDoc = (document.id.uuidString, document.lastPage); app.tab = .documents
        } else { app.tab = .read }
        dismiss()
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
            let plan = DailyStudy.plan(try context.fetch(FetchDescriptor<Card>()), defaults: defaults)
            await StudyReminders.shared.refresh(defaults: defaults, completed: plan.remaining == 0 || (plan.completed > 0 && plan.queue.isEmpty && plan.nextLearningDate == nil))
        } catch { if !(error is CancellationError) { failure = L10n.string("study.prepareError") } }
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
    private var todayIntroduced: Int {
        bookCards.filter { card in
            guard let date = card.firstReviewedAt else { return false }
            return Calendar.current.isDate(date, inSameDayAs: now)
        }.count
    }

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
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title).literary(.title1, bold: true)
                    Text(Language.find(document.language).displayName)
                        .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                }
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
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            WordBookMetric(title: "wordBook.total", value: document.entries.count, symbol: "books.vertical")
            WordBookMetric(title: "wordBook.learned", value: learnedCount, symbol: "checkmark.circle")
            WordBookMetric(title: "wordBook.due", value: dueCount, symbol: "clock")
            WordBookMetric(title: "wordBook.new", value: newCount, symbol: "sparkles")
            WordBookMetric(title: "wordBook.mistakes", value: mistakeCount, symbol: "arrow.counterclockwise")
            WordBookMetric(title: "wordBook.todayGoal", value: DailyStudy.newLimit(defaults), detail: L10n.format("wordBook.todayIntroduced", Int64(todayIntroduced)), symbol: "target")
        }
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

private struct WordBookMetric: View {
    let title: LocalizedStringKey
    let value: Int
    var detail: String? = nil
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            Text(verbatim: "\(value)")
                .font(Theme.Fonts.focus.weight(.semibold))
            if let detail { Text(verbatim: detail).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        await reminders.refresh(defaults: defaults, completed: plan.remaining == 0 || (plan.completed > 0 && plan.queue.isEmpty && plan.nextLearningDate == nil))
    }
}
