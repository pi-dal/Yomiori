import SwiftUI
import SwiftData

struct CoachView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \ChatMsg.createdAt) private var allMessages: [ChatMsg]
    @AppStorage("targetLang") private var languageCode = "ja"
    private var msgs: [ChatMsg] { allMessages.filter { $0.languageCode == languageCode } }
    @Query private var mistakes: [Mistake]
    @State private var input = ""
    @State private var session = CoachSession()
    private var streaming: String? { session.streaming }
    private var sending: Bool { session.sending }
    private var error: String? { session.error }
    @State private var showWeak = false
    @State private var context: String?
    @FocusState private var focused: Bool
    @State private var followsLatest = true
    @State private var userScrolling = false
    @State private var showingAI = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Picker("Language", selection: $languageCode) { Text("Japanese").tag("ja"); Text("English").tag("en") }.pickerStyle(.menu).disabled(sending)
                    Spacer()
                }.font(Theme.Fonts.body)
                    .frame(maxWidth: 720, minHeight: 44).padding(.horizontal, 24).padding(.top, 16).frame(maxWidth: .infinity)
                HStack(spacing: 4) {
                    NavigationLink { StagePicker() } label: { Text(CoachStage.current.label) }
                    Text("•")
                    Button("AI-generated content") { showingAI = true }
                }
                .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).frame(maxWidth: .infinity)
                if msgs.isEmpty && streaming == nil && error == nil { emptyState } else { chat }
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .font(Theme.Fonts.body)
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("coachtest"))) { _ in Task {
                let lines = ["昨日、友達を公園に行きました", "私は日本語が勉強しています", "先生に、明日学校へ来る？と言いました", "この本はとても面白いです。私は本を好きです", "毎日朝ごはんを食べるました"]
                for l in lines { while sending { try? await Task.sleep(for: .seconds(1)) }; send(l); try? await Task.sleep(for: .seconds(2)); while sending { try? await Task.sleep(for: .seconds(1)) }; try? await Task.sleep(for: .seconds(15)) }
            } }
            #endif
            .navigationTitle("Coach").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingAI) {
                NavigationStack {
                    ScrollView {
                        Text("Coach responses may contain mistakes. Check important information.")
                            .font(Theme.Fonts.body).frame(maxWidth: 720, alignment: .leading)
                            .padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
                    }.background(Theme.background).foregroundStyle(Theme.ink)
                    .navigationTitle("AI-generated content").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAI = false } } }
                }
            }
            .navigationDestination(isPresented: $showWeak) { WeaknessesView(practice: { prompt in showWeak = false; send(prompt) }) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Weaknesses") { showWeak = true }.foregroundStyle(Theme.ink)
                }
                if !msgs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { session.clear(language: languageCode, modelContext: ctx) } label: { Image(systemName: "trash") }.accessibilityLabel("Clear chat")
                    }
                }
            }
            .onChange(of: languageCode) { _, _ in session.invalidate(); context = nil; input = "" }
            .onDisappear { session.invalidate() }
            .onChange(of: app.pendingCoachPrompt) { _, p in
                if let p { context = app.pendingContext; app.pendingCoachPrompt = nil; app.pendingContext = nil; send(p) }
            }
            .onAppear {
                if let p = app.pendingCoachPrompt { context = app.pendingContext; app.pendingCoachPrompt = nil; app.pendingContext = nil; send(p) }
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                coachRow(icon: "bubble.left", title: "Start a conversation", detail: "Practice real-life \(Language.find(languageCode).displayName) with AI") {
                    input = L10n.string("coach.suggestTalk"); focused = true
                }
                if let latest = msgs.last {
                    coachRow(icon: "doc.text", title: "Recent conversation", detail: latest.content) { focused = true }
                }
                coachRow(icon: "chart.bar", title: "Practice & improve", detail: "Review saved words and check your weaknesses") { showWeak = true }
            }
            .frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.top, 32).frame(maxWidth: .infinity)
        }
    }

    private func coachRow(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 24)).frame(width: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.Fonts.body.weight(.semibold))
                    Text(detail).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
        }.buttonStyle(.plain)
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(msgs) { m in bubble(m).id(m.id) }
                    if let s = streaming {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coach").font(Theme.Fonts.meta.weight(.semibold))
                            if CoachSession.clean(s).isEmpty { ProgressView("Loading…").font(Theme.Fonts.meta) }
                            else { CoachMessageContent(text: CoachSession.clean(s), isStreaming: true) }
                            Button("Cancel", role: .cancel) { session.cancelReply() }.frame(minHeight: 44)
                        }.id("stream")
                    }
                    if let error {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(error, systemImage: "exclamationmark.triangle").font(Theme.Fonts.meta)
                            Button("Try again") { retry() }.frame(minHeight: 44)
                        }.foregroundStyle(Theme.vermilion).padding(12).background(Theme.errorBackground, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Color.clear.frame(height: 0.5).id("end")
                }.frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 80
            } action: { _, nearBottom in
                if userScrolling { followsLatest = nearBottom }
            }
            .onChange(of: msgs.count) { _, _ in if followsLatest { proxy.scrollTo("end") } }
            .onChange(of: streaming) { _, _ in if followsLatest { proxy.scrollTo("end") } }
            .onAppear { proxy.scrollTo("end") }
        }
    }

    @ViewBuilder private func bubble(_ m: ChatMsg) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(m.role == "user" ? L10n.string("You") : L10n.string("Coach"))
                .font(Theme.Fonts.meta.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            if m.role == "user" {
                Text(verbatim: m.content).font(Theme.Fonts.body).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                CoachMessageContent(text: m.content)
            }
            if m.role == "user" {
                ForEach(m.corrections, id: \.self) { c in
                    Button { showWeak = true } label: {
                        Text("\(Text(c.wrong).strikethrough().foregroundStyle(Theme.vermilion)) → \(Text(c.right).fontWeight(.semibold).foregroundStyle(Theme.ink))\n\(c.reason)")
                            .font(Theme.Fonts.meta).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain).frame(minHeight: 44, alignment: .leading)
                    .accessibilityLabel([c.wrong, c.right, c.reason].joined(separator: "\n"))
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("", text: $input, prompt: Text("Message Coach").foregroundStyle(Theme.textSecondary), axis: .vertical)
                .accessibilityLabel("Message Coach").foregroundStyle(Theme.ink).lineLimit(1...5).focused($focused)
                .font(Theme.Fonts.body).padding(.horizontal, 12).padding(.vertical, 12).frame(minHeight: 48).background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8))
            Button { let t = input; input = ""; send(t) } label: { Image(systemName: "arrow.up").font(.system(size: 20)).foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending ? Theme.textSecondary : Theme.background).frame(width: 48, height: 48).background(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending ? Theme.controlFill : Theme.ink, in: RoundedRectangle(cornerRadius: 10)) }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                .accessibilityLabel("Send")
        }.frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity).background(Theme.background)
            .font(Theme.Fonts.body)
    }

    private func retry() { session.retry(language: languageCode, context: context, modelContext: ctx) }
    private func send(_ text: String) {
        followsLatest = true
        session.send(text, language: languageCode, context: context, modelContext: ctx)
    }
}

struct WeaknessesView: View {
    @AppStorage("targetLang") private var languageCode = "ja"
    @Query private var mistakes: [Mistake]
    @State private var filter = "All"
    let practice: (String) -> Void

    struct Group: Identifiable { let pattern: String; let category: String; let items: [Mistake]; var id: String { pattern } }

    private var groups: [Group] {
        Dictionary(grouping: mistakes.filter { $0.languageCode == languageCode }, by: \.pattern).map { Group(pattern: $0.key, category: $0.value.first?.category ?? "", items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .filter { filter == "All" || $0.category == filter }
            .sorted { $0.items.count > $1.items.count }
    }
    private var filters: [String] { ["All"] + (Prefs.target.code == "ja" ? ["Grammar", "Vocabulary", "Particles", "Politeness"] : ["Grammar", "Vocabulary", "Word choice"]) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TextTabs(items: filters.map { ($0, L10n.string($0)) }, selection: $filter).padding(.horizontal, -24).padding(.bottom, 8)
                if groups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "chart.bar").font(.system(size: 20)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                        Text("No patterns found yet").font(Theme.Fonts.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16)
                }
                let top = max(groups.first?.items.count ?? 1, 1)
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(g.pattern).font(Theme.Fonts.body.weight(.semibold))
                            Spacer()
                            Text(L10n.format("coach.seen", Int64(g.items.count))).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                                .accessibilityLabel(L10n.format("coach.seen", Int64(g.items.count)))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Theme.controlSelected)
                                Rectangle().fill(Theme.ink).frame(width: geo.size.width * Double(g.items.count) / Double(top))
                            }
                        }.frame(height: 2).accessibilityHidden(true)
                        ForEach(g.items.prefix(2), id: \.persistentModelID) { m in
                            VStack(alignment: .leading, spacing: 8) {
                            Text("\(Text(m.wrong).strikethrough().foregroundStyle(Theme.vermilion)) → \(Text(m.right).fontWeight(.semibold).foregroundStyle(Theme.ink))").font(Theme.Fonts.body)
                            if !m.reason.isEmpty { Text(m.reason).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                            }
                        }
                        Button { practice(L10n.format("Practice this pattern: %@", g.pattern)) } label: { Text("Practice").font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.ink) }
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .trailing)
                    }
                    .padding(.vertical, 16)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                    .accessibilityElement(children: .contain)
                }
            }.frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
        }
        .background(Theme.background)
            .font(Theme.Fonts.body)
        .navigationTitle("Weaknesses").navigationBarTitleDisplayMode(.inline)
    }
}
