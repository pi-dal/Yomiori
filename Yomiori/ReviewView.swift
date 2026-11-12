import SwiftUI
import SwiftData

enum ReviewSession: Equatable { case daily, free }

struct ReviewView: View {
    /// Free practice comes in short rounds, so every round has an ending.
    static let freeRoundSize = 10

    let session: ReviewSession
    @Query private var allCards: [Card]
    @Query private var materials: [Material]
    @Query private var documents: [PDFDoc]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.studyDefaults) private var defaults
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("jaDefs") private var jaDefs = false
    @AppStorage("enDefs") private var enDefs = true
    @State private var saveError: String?
    @State private var flow = ReviewSessionQueue([])
    @State private var sessionCards: [UUID: Card] = [:]
    @State private var order: [UUID] = []
    @State private var step: ReviewStep = .intro
    @State private var options: [String] = []
    @State private var choice: String?
    @State private var correct: Bool?
    @State private var turn = 0
    @State private var recallFeedback = 0
    @State private var missFeedback = 0
    @State private var freePool: [Card] = []
    @State private var freeOffset = 0
    @State private var started = false
    @State private var library = WordListLibrary.shared
    @State private var confirmExit = false
    @State private var clip = ClipPlayer()
    @State private var remoteAudio = AtlasPronunciationPlayer()

    init(session: ReviewSession = .daily) {
        self.session = session
    }

    static func due(_ cards: [Card], limit: Int, newLimit: Int = 5) -> [Card] {
        StudyPlan(cards: cards, reviewLimit: limit, newLimit: newLimit).queue
    }

    private var currentCard: Card? { flow.current.flatMap { sessionCards[$0.id] } }
    /// Without at least one other meaning, recall is checked by the learner instead of by choice.
    private var selfGraded: Bool { options.count < 2 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if flow.total > 0 && !flow.isEmpty { progressHeader }
                if let c = currentCard {
                    ReviewStudyStage { reviewContent(c) }
                        .id(turn)
                        .transition(ReaderMotion.focus(forward: true, reduceMotion: reduceMotion))
                } else if started && flow.total > 0 { finished }
                else if started { empty }
                else { ProgressView("study.preparing").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.ink)
            .background(Theme.background)
            .sensoryFeedback(.success, trigger: recallFeedback)
            .sensoryFeedback(.impact(weight: .light), trigger: missFeedback)
            .navigationTitle(session == .daily ? LocalizedStringKey("nav.review") : LocalizedStringKey("review.freePractice")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if flow.finished > 0 && !flow.isEmpty { confirmExit = true } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 20)).frame(width: 44, height: 44)
                    }.accessibilityLabel("Close")
                }
            }
            .task {
                guard !started else { return }
                if session == .daily { await prepareDaily() }
                else { freePool = FreePractice.cards(allCards, defaults: defaults); freeOffset = 0; startFreeRound() }
                started = true
            }
            .alert("Couldn't save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
            .onDisappear { clip.stop(); remoteAudio.stop() }
            .confirmationDialog("review.stopTitle", isPresented: $confirmExit, titleVisibility: .visible) {
                Button("review.stop", role: .destructive) { dismiss() }; Button("review.continue", role: .cancel) {}
            } message: { if session == .daily { Text("review.stopBody") } }
        }
    }

    // MARK: Session

    private func start(_ cards: [Card]) {
        sessionCards = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        order = cards.map(\.id)
        flow = ReviewSessionQueue(cards.map { ($0.id, $0.reps == 0) })
        turn += 1
        begin()
    }

    /// Review can open straight from Read or a reminder, so it tops up today's new words itself.
    /// Preparation is local only; a failure still leaves the due reviews available.
    private func prepareDaily() async {
        let generation = Operations.shared.generation
        await library.load()
        if (try? Operations.shared.checkpoint(generation)) != nil {
            try? DailyStudy.prepare(context: context, documents: library.documents, defaults: defaults)
        }
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? allCards
        start(DailyStudy.plan(cards, defaults: defaults).queue)
    }

    private func startFreeRound() {
        let end = min(freePool.count, freeOffset + Self.freeRoundSize)
        let round = Array(freePool[min(freeOffset, end)..<end])
        freeOffset = end
        start(round)
    }

    private var freeRemaining: Int { session == .free ? max(0, freePool.count - freeOffset) : 0 }

    /// Sets up the current card: a new word starts with its introduction, anything else with recall.
    private func begin() {
        choice = nil; correct = nil
        guard let item = flow.current, let card = sessionCards[item.id] else { options = []; return }
        step = flow.step
        options = step == .recall
            ? MeaningChoices.make(answer: quizMeaning(for: card), card: card, among: allCards, meaning: quizMeaning(for:))
            : []
        autoplay(card)
    }

    private func finishIntro() {
        clip.stop(); remoteAudio.stop()
        withAnimation(ReaderMotion.advance(reduceMotion: reduceMotion)) {
            flow.finishIntro(); turn += 1; begin()
        }
    }

    private func choose(_ option: String?) {
        guard step == .recall, let card = currentCard else { return }
        choice = option
        let isCorrect = option.map { MeaningChoices.normalized($0) == MeaningChoices.normalized(quizMeaning(for: card)) } ?? false
        correct = isCorrect
        if isCorrect { recallFeedback += 1 } else { missFeedback += 1 }
        withAnimation(.easeOut(duration: 0.2)) { step = .result }
    }

    private func reveal() {
        guard step == .recall else { return }
        withAnimation(.easeOut(duration: 0.2)) { step = .result }
    }

    /// Applies the answer to the schedule (daily only) and moves on. Missed words return later in the session.
    private func commit(correct isCorrect: Bool, adjustment: Rating? = nil) {
        guard step == .result, let item = flow.current, let card = sessionCards[item.id] else { return }
        if session == .daily, let rating = ReviewSessionQueue.rating(correct: isCorrect, priorMisses: item.misses, adjustment: adjustment) {
            do { try DailyStudy.rate(card, rating: rating, context: context) }
            catch { saveError = L10n.string("study.saveError"); return }
        }
        if correct == nil { if isCorrect { recallFeedback += 1 } else { missFeedback += 1 } }
        clip.stop(); remoteAudio.stop()
        withAnimation(ReaderMotion.advance(reduceMotion: reduceMotion)) {
            flow.record(correct: isCorrect); turn += 1; begin()
        }
        if session == .daily {
            Task {
                let plan = DailyStudy.plan(allCards, defaults: defaults)
                await StudyReminders.shared.refresh(defaults: defaults, completed: plan.remaining == 0 || (plan.completed > 0 && plan.queue.isEmpty && plan.nextLearningDate == nil))
            }
        }
    }

    private func autoplay(_ c: Card) { if let a = c.audioFile { clip.play(Files.url(a)) } }

    // MARK: Layout

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(flow.finished), total: Double(max(1, flow.total)))
                .tint(Theme.accent)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: flow.finished)
                .accessibilityHidden(true)
            // Missed words return, so progress counts finished words rather than a card position.
            Text(L10n.format("review.position", Int64(flow.finished), Int64(flow.total)))
                .font(Theme.Fonts.meta.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                .accessibilityLabel(L10n.format("review.a11yProgress", Int64(flow.finished), Int64(flow.total)))
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 16)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var bottomActions: some View {
        VStack(spacing: 12) {
            if let c = currentCard, let item = flow.current {
                switch step {
                case .intro:
                    Button("review.gotIt") { finishIntro() }.buttonStyle(InkButtonStyle()).accessibilityIdentifier("review.gotIt")
                case .recall:
                    if selfGraded {
                        Button("review.seeAnswer") { reveal() }.buttonStyle(InkButtonStyle()).accessibilityIdentifier("review.reveal")
                    } else {
                        Button("review.dontKnow") { choose(nil) }.buttonStyle(PaperActionStyle(expanded: true)).accessibilityIdentifier("review.dontKnow")
                    }
                case .result:
                    resultActions(c, item: item)
                }
            } else if started {
                if freeRemaining > 0 {
                    Button(L10n.format("review.moreRound", Int64(min(Self.freeRoundSize, freeRemaining)))) {
                        withAnimation(ReaderMotion.advance(reduceMotion: reduceMotion)) { startFreeRound() }
                    }.buttonStyle(InkButtonStyle()).accessibilityIdentifier("review.moreRound")
                }
                Button("Close") { dismiss() }.buttonStyle(PaperActionStyle(expanded: true)).accessibilityIdentifier("review.finish")
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 24).padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
    }

    @ViewBuilder private func resultActions(_ c: Card, item: ReviewItem) -> some View {
        if let correct {
            if session == .daily, correct, item.misses == 0 {
                let good = Scheduler.hint(Scheduler.next(c, .good))
                Button { commit(correct: true) } label: {
                    VStack(spacing: 2) {
                        Text("review.next")
                        Text(L10n.format("review.nextReview", good)).font(Theme.Fonts.meta).opacity(0.8)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(InkButtonStyle()).accessibilityIdentifier("review.next")
                .accessibilityLabel(L10n.format("review.a11yRating", Rating.good.label, good))
                HStack(spacing: 12) {
                    adjustButton(c, .hard)
                    adjustButton(c, .easy)
                }
            } else {
                Button("review.next") { commit(correct: correct) }
                    .buttonStyle(InkButtonStyle()).accessibilityIdentifier("review.next")
            }
        } else {
            // Self-check when the learner's cards don't yet offer other meanings to choose from.
            HStack(spacing: 12) {
                Button("review.forgot") { commit(correct: false) }
                    .buttonStyle(PaperActionStyle(expanded: true)).accessibilityIdentifier("review.forgot")
                Button("review.remembered") { commit(correct: true) }
                    .buttonStyle(InkButtonStyle()).accessibilityIdentifier("review.remembered")
            }
        }
    }

    private func adjustButton(_ c: Card, _ rating: Rating) -> some View {
        let interval = Scheduler.hint(Scheduler.next(c, rating))
        return Button { commit(correct: true, adjustment: rating) } label: {
            Text(L10n.format("review.adjust", rating == .hard ? L10n.string("review.wasHard") : L10n.string("review.tooEasy"), interval))
                .font(Theme.Fonts.meta.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(TextActionStyle())
        .accessibilityLabel(L10n.format("review.a11yRating", rating.label, interval))
    }

    private func reviewContent(_ c: Card) -> some View {
        VStack(spacing: 16) {
            // One line when it fits; stacked at large accessibility sizes instead of wrapping inside each label.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { cardLabels(c) }.fixedSize()
                VStack(spacing: 4) { cardLabels(c) }.multilineTextAlignment(.center)
            }
            .font(Theme.Fonts.meta)
            .accessibilityElement(children: .combine)
            marked(c)
            switch step {
            case .intro:
                answerDetails(c)
                Text("review.introPrompt")
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            case .recall:
                recall(c)
            case .result:
                feedback(c)
                answerDetails(c)
            }
            if !c.sourceID.isEmpty, step != .recall {
                Button("Go to source") {
                    dismiss(); app.showStudy = false; app.showReview = false
                    if c.sourceKind == "pdf" { app.jumpDoc = (c.sourceID, Int(c.sourcePos)); app.tab = .documents }
                    else { app.jumpMaterial = (c.sourceID, c.sourcePos); app.tab = .read }
                }.font(Theme.Fonts.meta).frame(minHeight: 44)
            }
            audioControls(c)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private func cardLabels(_ c: Card) -> some View {
        Text(stageTitle).foregroundStyle(Theme.accent).fontWeight(.semibold)
        if !c.wordLevel.isEmpty {
            Text(L10n.format("review.level", WordListMetadata.level(c.wordLevel))).foregroundStyle(Theme.textSecondary)
        }
        if step != .intro { Text(L10n.string(StudyCardStatus.key(c))).foregroundStyle(Theme.textSecondary) }
        if session == .free { Text("review.freeBadge").foregroundStyle(Theme.accent) }
    }

    @ViewBuilder private func audioControls(_ c: Card) -> some View {
        if c.audioFile != nil {
            Button { autoplay(c) } label: { Label("Play audio", systemImage: "play.fill").font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.ink) }
                .frame(minHeight: 44)
                .accessibilityLabel("review.play")
        } else if let url = URL(string: c.audioRemoteURL), !c.audioRemoteURL.isEmpty {
            Button { remoteAudio.play(url) } label: { Label("Play audio", systemImage: "speaker.wave.2") }.frame(minHeight: 44).disabled(remoteAudio.loading)
            if remoteAudio.loading { ProgressView() }
            if remoteAudio.error != nil { Text("lists.audioError").font(Theme.Fonts.meta).foregroundStyle(Theme.errorText) }
        }
    }

    private var stageTitle: String {
        switch step {
        case .intro: return L10n.string("review.stepNew")
        case .recall: return L10n.string("review.stepQuiz")
        case .result: return L10n.string("review.stepFeedback")
        }
    }

    private func recall(_ c: Card) -> some View {
        VStack(spacing: 12) {
            Text(selfGraded ? "review.recallSelfPrompt" : "review.quizPrompt")
                .font(Theme.Fonts.body.weight(.semibold)).multilineTextAlignment(.center)
            VStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    Button { choose(option) } label: { Text(option) }
                        .buttonStyle(AnswerChoiceStyle())
                        .accessibilityIdentifier("review.option")
                }
            }.padding(.top, 4)
        }.padding(.top, 8)
    }

    @ViewBuilder private func feedback(_ c: Card) -> some View {
        if let correct, let item = flow.current {
            VStack(spacing: 6) {
                Label(correct ? "review.recalled" : "review.missed",
                      systemImage: correct ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill")
                    .foregroundStyle(correct ? Theme.accent : Theme.errorText)
                    .font(Theme.Fonts.body.weight(.semibold))
                if !correct {
                    if let choice { Text(L10n.format("review.yourChoice", choice)).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                    Text(item.misses + 1 < ReviewSessionQueue.maximumMisses ? "review.returnsSoon" : "review.returnsLater")
                        .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                }
            }.multilineTextAlignment(.center)
        } else {
            Text("review.selfCheck").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
    }

    private func answerDetails(_ c: Card) -> some View {
        VStack(spacing: 12) {
            if c.word.trimmingCharacters(in: .whitespacesAndNewlines) != c.sentence.trimmingCharacters(in: .whitespacesAndNewlines) {
                answerText(c.word).font(Theme.Fonts.body.weight(.semibold))
            }
            if !c.reading.isEmpty { Text(c.reading).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
            let selectedMeaning = primaryMeaning(for: c)
            let meaning = c.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            let translation = c.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selectedMeaning.isEmpty { answerText(selectedMeaning).font(Theme.Fonts.body) }
            if !meaning.isEmpty && meaning != selectedMeaning { answerText(meaning).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
            if !translation.isEmpty && translation != selectedMeaning && translation != meaning { answerText(translation).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
        }.padding(.top, 8)
    }

    private func primaryMeaning(for card: Card) -> String {
        let preferred = (enDefs && card.languageCode == "en" && !card.definitionEnglish.isEmpty ? card.definitionEnglish : (jaDefs && !card.definitionJa.isEmpty ? card.definitionJa : card.meaning))
        let fallback = card.translation.isEmpty ? card.meaning : card.translation
        return (preferred.isEmpty ? fallback : preferred).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One sense is enough to recognise the word; several stacked senses turn every choice into a paragraph.
    private func quizMeaning(for card: Card) -> String {
        let meaning = primaryMeaning(for: card)
        return meaning.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? meaning
    }

    private func marked(_ c: Card) -> some View {
        var a = AttributedString(c.sentence)
        // Inflected forms count too: 読む is marked in 読もう, remember in remembered.
        var highlighted = StudyLexicon.occurrence(of: c, in: c.sentence) ?? c.word
        if highlighted == c.word, c.languageCode == "en", !c.word.isEmpty,
           let match = c.sentence.range(of: c.word, options: .caseInsensitive) {
            c.sentence.enumerateSubstrings(in: c.sentence.startIndex..<c.sentence.endIndex, options: .byWords) { token, range, _, stop in
                if range.overlaps(match), let token {
                    highlighted = token
                    stop = true
                }
            }
        }
        if !highlighted.isEmpty, let r = a.range(of: highlighted, options: .caseInsensitive) {
            a[r].backgroundColor = UIColor(Theme.highlight)
            a[r].underlineStyle = .single
        }
        return ViewThatFits(in: .horizontal) {
            Text(a).fixedSize(horizontal: true, vertical: true).multilineTextAlignment(.center)
            Text(a).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.literary(.title1, bold: true, .original).foregroundStyle(Theme.ink)
    }

    private func answerText(_ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(value).fixedSize(horizontal: true, vertical: true).multilineTextAlignment(.center)
            Text(value).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: End of session

    private var empty: some View {
        ReviewStudyStage {
            Text("review.noneDue").font(Theme.Fonts.body.weight(.semibold))
        }
    }

    private var sessionList: [Card] { order.compactMap { sessionCards[$0] } }

    private var finished: some View {
        let missed = flow.missed.compactMap { sessionCards[$0] }
        // Tricky words first, then new ones: the words most worth using in a sentence today.
        let practice = Array((missed + flow.newWords.compactMap { sessionCards[$0] })
            .reduce(into: [Card]()) { list, card in if !list.contains(where: { $0.id == card.id }) { list.append(card) } }
            .prefix(5))
        let source = ReviewSource.mostFrequent(sessionList,
                                               materials: Set(materials.map(\.id.uuidString)),
                                               documents: Set(documents.map(\.id.uuidString)))
        return ReviewStudyStage {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session == .free ? "review.roundDone" : "review.done")
                        .literary(.title2, bold: true)
                    Text(L10n.format("review.summaryStats", Int64(flow.recalled.count), Int64(flow.newWords.count), Int64(missed.count)))
                        .font(Theme.Fonts.body.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    // Free practice saves nothing to the schedule, so it says so instead of claiming saved progress.
                    if session == .free {
                        if freeRemaining == 0 { Text("review.freeFinished").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                    } else {
                        Text(L10n.format("study.sessionFinished", Int64(flow.total)))
                            .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    }
                }
                if !missed.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("review.revisitTitle").font(Theme.Fonts.meta.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            .accessibilityAddTraits(.isHeader).padding(.bottom, 4)
                        ForEach(missed.prefix(6)) { card in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.word).literary(.headline, bold: true, .original)
                                let meaning = primaryMeaning(for: card)
                                if !meaning.isEmpty { Text(meaning).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.vertical, 6)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if !practice.isEmpty {
                    Button { practiseWithCoach(practice) } label: {
                        ActionRowLabel(title: "review.practiseWithCoach", symbol: "bubble.left.and.bubble.right",
                                       detail: practice.map(\.word).joined(separator: L10n.string("list.separator")))
                    }.buttonStyle(TextActionStyle()).accessibilityIdentifier("review.coach")
                }
                if let source, let title = title(of: source) {
                    Button { open(source) } label: {
                        ActionRowLabel(title: "review.backToSource", symbol: "book", detail: title)
                    }.buttonStyle(TextActionStyle()).accessibilityIdentifier("review.backToSource")
                }
                if session == .daily, let next = DailyStudy.plan(allCards, defaults: defaults).nextLearningDate {
                    HStack(spacing: 4) {
                        Text("study.retryLater")
                        Text(next, style: .time).monospacedDigit()
                    }.font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func title(of source: ReviewSource) -> String? {
        switch source {
        case .material(let id, _): materials.first { $0.id.uuidString == id }?.title
        case .document(let id, _): documents.first { $0.id.uuidString == id }?.title
        }
    }

    /// An explicit request: Coach starts a short conversation built around these words.
    private func practiseWithCoach(_ cards: [Card]) {
        guard let language = cards.first?.languageCode else { return }
        let words = cards.map(\.word).joined(separator: L10n.string("list.separator"))
        dismiss(); app.showStudy = false; app.showReview = false
        app.askCoach(L10n.format("review.coachPrompt", words), languageCode: language)
    }

    private func open(_ source: ReviewSource) {
        dismiss(); app.showStudy = false; app.showReview = false
        switch source {
        case .material(let id, let position): app.jumpMaterial = (id, position); app.tab = .read
        case .document(let id, let page): app.jumpDoc = (id, page); app.tab = .documents
        }
    }
}

/// The parent owns navigation and fixed actions. The remaining proposal is the study stage.
private struct ReviewStudyStage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, geometry.size.height - 48), alignment: .center)
                    .padding(.horizontal, 24).padding(.vertical, 24)
            }
        }
    }
}
