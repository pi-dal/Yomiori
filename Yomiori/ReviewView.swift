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
    private var step: ReviewStep { flow.step }
    @State private var options: [String] = []
    private var choice: String? { flow.answer?.choice }
    private var correct: Bool? { flow.answer?.correct }
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
    /// Words whose rating in this session carried them from learning to known, in the order they crossed.
    @State private var stuck: [UUID] = []
    /// The word that just stuck, noted briefly beside the progress count.
    @State private var stuckNote: String?
    @State private var stuckNoteTask: Task<Void, Never>?
    @State private var keptFeedback = 0
    @State private var recapShown = false

    init(session: ReviewSession = .daily) {
        self.session = session
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
            .sensoryFeedback(.inkReveal, trigger: recallFeedback)
            .sensoryFeedback(.inkStep, trigger: missFeedback)
            .sensoryFeedback(.inkKept, trigger: keptFeedback)
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
            .onDisappear { clip.stop(); remoteAudio.stop(); stuckNoteTask?.cancel() }
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
        recapShown = false
        turn += 1
        begin()
    }

    /// Review can open straight from Read or a reminder, so it tops up today's new words itself.
    /// Preparation is local only; a failure still leaves the due reviews available.
    private func prepareDaily() async {
        do {
            let plan = try await DailyStudy.preparedPlan(context: context, library: library, defaults: defaults)
            saveError = library.error
            start(plan.queue)
        } catch is CancellationError { return }
        catch {
            saveError = L10n.string("study.prepareError")
            start(DailyStudy.plan(allCards, defaults: defaults).queue)
        }
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
        guard let item = flow.current, let card = sessionCards[item.id] else { options = []; return }
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
        let isCorrect = option.map { MeaningChoices.normalized($0) == MeaningChoices.normalized(quizMeaning(for: card)) } ?? false
        if isCorrect { recallFeedback += 1 } else { missFeedback += 1 }
        // The choices stay where they were; only their marks arrive, so the learner sees what they picked graded.
        withAnimation(ReaderMotion.veil(reduceMotion: reduceMotion)) { flow.reveal(choice: option, correct: isCorrect) }
    }

    private func reveal() {
        guard step == .recall else { return }
        withAnimation(.easeOut(duration: 0.2)) { flow.reveal() }
    }

    /// Applies the answer to the schedule (daily only) and moves on. Missed words return later in the session.
    private func commit(correct isCorrect: Bool, adjustment: Rating? = nil) {
        guard step == .result, let item = flow.current, let card = sessionCards[item.id] else { return }
        var crossed = false
        if session == .daily, let rating = ReviewSessionQueue.rating(correct: isCorrect, priorMisses: item.misses, adjustment: adjustment) {
            let wasLearning = StudyLexicon.stage(card) == .learning
            do { try DailyStudy.rate(card, rating: rating, context: context) }
            catch { saveError = L10n.string("study.saveError"); return }
            crossed = wasLearning && StudyLexicon.stage(card) == .known
        }
        if correct == nil { if isCorrect { recallFeedback += 1 } else { missFeedback += 1 } }
        clip.stop(); remoteAudio.stop()
        withAnimation(ReaderMotion.advance(reduceMotion: reduceMotion)) {
            flow.record(correct: isCorrect); turn += 1; begin()
        }
        if crossed { noteStuck(card) }
        // One kept touch for the rarer moments: a word that stuck, or the session's last card.
        if crossed || flow.isEmpty { keptFeedback += 1 }
        if session == .daily {
            Task {
                let plan = DailyStudy.plan(allCards, defaults: defaults)
                await StudyReminders.shared.refresh(defaults: defaults, completed: plan.suppressesTodayReminder)
            }
        }
    }

    /// Real scheduler data, not a reward: the rating just carried this word to a three-week interval.
    private func noteStuck(_ card: Card) {
        stuck.append(card.id)
        let word = card.word
        withAnimation(ReaderMotion.veil(reduceMotion: reduceMotion)) { stuckNote = word }
        AccessibilityNotification.Announcement(L10n.format("%@ has stuck", word)).post()
        stuckNoteTask?.cancel()
        stuckNoteTask = Task {
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { stuckNote = nil }
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Missed words return, so progress counts finished words rather than a card position.
                Text(L10n.format("review.position", Int64(flow.finished), Int64(flow.total)))
                    .font(Theme.Fonts.meta.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText(value: Double(flow.finished)))
                    .accessibilityLabel(L10n.format("review.a11yProgress", Int64(flow.finished), Int64(flow.total)))
                Spacer(minLength: 8)
                if let stuckNote {
                    Label {
                        Text("\(Text(verbatim: stuckNote).font(Font(Theme.Fonts.literary(.subheadline, bold: true)))) has stuck")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    .font(Theme.Fonts.meta.weight(.semibold)).foregroundStyle(Theme.accent)
                    .lineLimit(2).multilineTextAlignment(.trailing)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                    .accessibilityHidden(true) // Announced when it appears.
                }
            }
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
            if step == .intro {
                answerDetails(c)
                Text("review.introPrompt")
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            // One block from question to verdict, so the choices keep their place while they are graded.
            if step == .recall || graded { recall(c) }
            if step == .result {
                if !graded { feedback(c) }
                answerDetails(c, omitting: graded ? quizMeaning(for: c) : nil)
            }
            if !c.sourceID.isEmpty, step != .recall {
                Button("Go to source") {
                    open(c.sourceKind == "pdf" ? .document(id: c.sourceID, page: Int(c.sourcePos)) : .material(id: c.sourceID, position: c.sourcePos))
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

    /// A choice was made (or declined) among meanings, so the result is shown on the choices themselves.
    private var graded: Bool { step == .result && correct != nil && !options.isEmpty }

    private func mark(_ option: String, card: Card) -> AnswerMark {
        guard step == .result, correct != nil else { return .open }
        if MeaningChoices.normalized(option) == MeaningChoices.normalized(quizMeaning(for: card)) { return .correct }
        return option == choice ? .struck : .faded
    }

    private func recall(_ c: Card) -> some View {
        VStack(spacing: 12) {
            // The verdict takes the question's place.
            if let correct, step == .result {
                verdict(correct)
            } else {
                Text(selfGraded ? "review.recallSelfPrompt" : "review.quizPrompt")
                    .font(Theme.Fonts.body.weight(.semibold)).multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    let mark = mark(option, card: c)
                    Button { choose(option) } label: { AnswerChoiceLabel(text: option, mark: mark) }
                        .buttonStyle(AnswerChoiceStyle())
                        .allowsHitTesting(step == .recall)
                        .accessibilityValue(mark == .correct ? Text("review.correctA11y") : mark == .struck ? Text("review.struckA11y") : Text(""))
                        .accessibilityIdentifier("review.option")
                }
            }.padding(.top, 4)
            if correct == false, step == .result, let item = flow.current {
                Text(item.misses + 1 < ReviewSessionQueue.maximumMisses ? "review.returnsSoon" : "review.returnsLater")
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
        }.padding(.top, 8)
    }

    private func verdict(_ correct: Bool) -> some View {
        Label(correct ? "review.recalled" : "review.missed",
              systemImage: correct ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill")
            .foregroundStyle(correct ? Theme.accent : Theme.errorText)
            .font(Theme.Fonts.body.weight(.semibold))
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private func feedback(_ c: Card) -> some View {
        if correct == nil {
            Text("review.selfCheck").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
    }

    /// `omitting` skips a meaning the learner can already see, such as the checked answer among the choices.
    private func answerDetails(_ c: Card, omitting shown: String? = nil) -> some View {
        VStack(spacing: 12) {
            if c.word.trimmingCharacters(in: .whitespacesAndNewlines) != c.sentence.trimmingCharacters(in: .whitespacesAndNewlines) {
                answerText(c.word).font(Theme.Fonts.body.weight(.semibold))
            }
            if !c.reading.isEmpty { Text(c.reading).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
            let primary = primaryMeaning(for: c)
            let selectedMeaning = primary == shown ? "" : primary
            let meaning = c.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            let translation = c.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selectedMeaning.isEmpty { answerText(selectedMeaning).font(Theme.Fonts.body) }
            if !meaning.isEmpty && meaning != primary && meaning != shown { answerText(meaning).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
            if !translation.isEmpty && translation != primary && translation != meaning && translation != shown { answerText(translation).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
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
                    wordsPage(missed: Set(flow.missed)).padding(.vertical, 8)
                    Text(L10n.format("review.summaryStats", Int64(flow.recalled.count), Int64(flow.newWords.count), Int64(missed.count)))
                        .font(Theme.Fonts.meta.monospacedDigit()).foregroundStyle(Theme.textSecondary)
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

    /// The session's words set on one page, settling in the order they were met: recalled in ink,
    /// words to revisit in diluted ink, and a seal beside any word that stuck today. The words are the reward.
    private func wordsPage(missed: Set<UUID>) -> some View {
        let words = sessionList
        return FlowLayout(lineSpacing: 6) {
            ForEach(Array(words.enumerated()), id: \.element.id) { index, card in
                let revisit = missed.contains(card.id)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: card.word).literary(.title3, bold: !revisit, .original)
                        .foregroundStyle(revisit ? Theme.textSecondary : Theme.ink)
                    if stuck.contains(card.id) {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.trailing, 18)
                .opacity(recapShown ? 1 : 0)
                .offset(y: recapShown || reduceMotion ? 0 : 10)
                .animation(reduceMotion ? .easeInOut(duration: 0.2)
                           : .timingCurve(0.16, 1, 0.3, 1, duration: 0.5).delay(0.3 + 0.06 * Double(min(index, 15))),
                           value: recapShown)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("review.wordsA11y", words.map(\.word).joined(separator: L10n.string("list.separator"))))
        .onAppear { recapShown = true }
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
        dismiss()
        app.askCoach(L10n.format("review.coachPrompt", words), languageCode: language)
    }

    private func open(_ source: ReviewSource) {
        dismiss()
        app.open(source)
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
