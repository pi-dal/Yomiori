import SwiftUI
import SwiftData

struct ReviewView: View {
    @Query private var allCards: [Card]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @AppStorage("reviewLimit") private var limit = 30
    @AppStorage("jaDefs") private var jaDefs = false
    @AppStorage("enDefs") private var enDefs = true
    @State private var queue: [Card] = []
    @State private var total = 0
    @State private var done = 0
    @State private var showBack = false
    @State private var started = false
    @State private var confirmExit = false
    @State private var clip = ClipPlayer()
    @State private var remoteAudio = AtlasPronunciationPlayer()

    static func due(_ cards: [Card], limit: Int) -> [Card] { Array(cards.filter { $0.due <= Date() }.sorted { $0.due < $1.due }.prefix(limit)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if total > 0 && !queue.isEmpty {
                    Text(L10n.format("review.position", Int64(min(done + 1, total)), Int64(total)))
                        .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel(L10n.format("review.a11yPosition", Int64(min(done + 1, total)), Int64(total)))
                        .frame(maxWidth: 640, alignment: .leading)
                        .padding(.horizontal, 24).padding(.top, 16)
                }
                if let c = queue.first { cardView(c) }
                else if started && total > 0 { finished }
                else { empty }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.ink)
            .background(Theme.background)
            .navigationTitle("nav.review").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if done > 0 && !queue.isEmpty { confirmExit = true } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 20)).frame(width: 44, height: 44)
                    }.accessibilityLabel("Close")
                }
            }
            .onAppear { if !started { queue = Self.due(allCards, limit: limit); total = queue.count; started = true; if let c = queue.first { autoplay(c) } } }
            .onDisappear { clip.stop(); remoteAudio.stop() }
            .confirmationDialog("review.stopTitle", isPresented: $confirmExit, titleVisibility: .visible) {
                Button("review.stop", role: .destructive) { dismiss() }; Button("review.continue", role: .cancel) {}
            }
        }
    }

    private var bottomActions: some View {
        Group {
            if let c = queue.first {
                if showBack {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(Rating.allCases, id: \.self) { rating in ratingButton(c, rating) }
                    }
                } else {
                    Button("Show answer") { showBack = true }.buttonStyle(InkButtonStyle())
                }
            } else {
                Button("Close") { dismiss() }.buttonStyle(InkButtonStyle())
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 24).padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
    }

    private func autoplay(_ c: Card) { if let a = c.audioFile { clip.play(Files.url(a)) } }

    private func cardView(_ c: Card) -> some View {
        ReviewStudyStage { reviewContent(c) }
            .id(c.id)
            .transaction { $0.animation = nil }
    }

    private func reviewContent(_ c: Card) -> some View {
        VStack(spacing: 16) {
            marked(c)
            if showBack {
                VStack(spacing: 12) {
                    if c.word.trimmingCharacters(in: .whitespacesAndNewlines) != c.sentence.trimmingCharacters(in: .whitespacesAndNewlines) {
                        answerText(c.word).font(Theme.Fonts.body.weight(.semibold))
                    }
                    if !c.reading.isEmpty { Text(c.reading).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                    let selectedMeaning = (enDefs && c.languageCode == "en" && !c.definitionEnglish.isEmpty ? c.definitionEnglish : (jaDefs && !c.definitionJa.isEmpty ? c.definitionJa : c.meaning)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let meaning = c.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                    let translation = c.translation.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !selectedMeaning.isEmpty { answerText(selectedMeaning).font(Theme.Fonts.body) }
                    if !meaning.isEmpty && meaning != selectedMeaning { answerText(meaning).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
                    if !translation.isEmpty && translation != selectedMeaning && translation != meaning { answerText(translation).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
                }.padding(.top, 8)
                if !c.sourceID.isEmpty {
                    Button("Go to source") { dismiss(); app.jumpMaterial = (c.sourceID, c.sourcePos); app.tab = .read }.font(Theme.Fonts.meta).frame(minHeight: 44)
                }
            }
            if c.audioFile != nil {
                Button { autoplay(c) } label: { Label("Play audio", systemImage: "play.fill").font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.ink) }
                    .frame(minHeight: 44)
                    .accessibilityLabel("review.play")
            }
            if c.audioFile == nil, let url = URL(string: c.audioRemoteURL), !c.audioRemoteURL.isEmpty {
                Button { remoteAudio.play(url) } label: { Label("Play audio", systemImage: "speaker.wave.2") }.frame(minHeight: 44).disabled(remoteAudio.loading)
                if remoteAudio.loading { ProgressView() }
                if remoteAudio.error != nil { Text("lists.audioError").font(Theme.Fonts.meta).foregroundStyle(Theme.errorText) }
            }
        }.frame(maxWidth: .infinity)
    }

    private func marked(_ c: Card) -> some View {
        var a = AttributedString(c.sentence)
        var highlighted = c.word
        if c.languageCode == "en", !c.word.isEmpty,
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
        }.font(Theme.Fonts.focus.weight(.semibold)).foregroundStyle(Theme.ink)
    }

    private func rate(_ c: Card, _ r: Rating) {
        guard showBack, queue.first?.id == c.id else { return }
        clip.stop(); remoteAudio.stop()
        Scheduler.apply(c, r)
        queue.removeFirst()
        if r == .again { queue.append(c) } else { done += 1 }
        showBack = false
        if queue.isEmpty { UINotificationFeedbackGenerator().notificationOccurred(.success) } else if let n = queue.first { autoplay(n) }
    }

    private func ratingButton(_ card: Card, _ rating: Rating) -> some View {
        let interval = Scheduler.hint(Scheduler.next(card, rating))
        return Button { rate(card, rating) } label: {
            VStack(spacing: 8) {
                Text(rating.label).font(Theme.Fonts.body.weight(.semibold))
                Text(interval).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(Theme.controlBorder, lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .accessibilityLabel(L10n.format("review.a11yRating", rating.label, interval))
    }

    private func answerText(_ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(value).fixedSize(horizontal: true, vertical: true).multilineTextAlignment(.center)
            Text(value).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var empty: some View {
        ReviewStudyStage {
            Text("review.noneDue").font(Theme.Fonts.body.weight(.semibold))
        }
    }

    private var finished: some View {
        ReviewStudyStage {
            VStack(spacing: 16) {
                Text("review.done").font(Theme.Fonts.body.weight(.semibold))
                Text(L10n.format("review.completed", Int64(total)))
                    .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
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
