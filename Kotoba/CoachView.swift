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
    @State private var streaming: String?
    @State private var sending = false
    @State private var error: String?
    @State private var showWeak = false
    @State private var task: Task<Void, Never>?
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
                if msgs.isEmpty && streaming == nil { emptyState } else { chat }
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
                        Button { for m in msgs { ctx.delete(m) } } label: { Image(systemName: "trash") }.accessibilityLabel("Clear chat")
                    }
                }
            }
            .onChange(of: languageCode) { _, _ in context = nil; error = nil; input = "" }
            .onChange(of: app.pendingCoachPrompt) { _, p in
                if let p { context = app.pendingContext; app.pendingCoachPrompt = nil; app.pendingContext = nil; send(p) }
            }
            .onAppear {
                if let p = app.pendingCoachPrompt { context = app.pendingContext; app.pendingCoachPrompt = nil; send(p) }
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
                            if Self.clean(s).isEmpty { ProgressView("Loading…").font(Theme.Fonts.meta) }
                            else { Bubble(text: Self.clean(s), user: false) }
                            Button("Cancel", role: .cancel) { task?.cancel() }.frame(minHeight: 44)
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
            Bubble(text: m.content, user: m.role == "user")
            if m.role == "user" {
                ForEach(m.corrections, id: \.self) { c in
                    Button { showWeak = true } label: {
                        (Text(c.wrong).strikethrough().foregroundStyle(Theme.vermilion) + Text(" → ").foregroundStyle(Theme.textSecondary) + Text(c.right).fontWeight(.semibold).foregroundStyle(Theme.ink) + Text("\n\(c.reason)").foregroundStyle(Theme.textSecondary))
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

    private var minedList: String {
        let cs = (try? ctx.fetch(FetchDescriptor<Card>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        let s = cs.filter { $0.languageCode == languageCode }.prefix(10).map { "\($0.sentence) (\($0.word))" }.joined(separator: "; ")
        return s.isEmpty ? "none" : s
    }
    private func systemPrompt() -> String {
        let t = Prefs.target, n = Prefs.native
        let top = Dictionary(grouping: mistakes.filter { $0.languageCode == languageCode }, by: \.pattern).sorted { $0.value.count > $1.value.count }.prefix(5)
            .map { "\($0.key) (\($0.value.count)x)" }.joined(separator: ", ")
        let words = (try? ctx.fetch(FetchDescriptor<DictEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])))?.filter { $0.languageCode == languageCode }.prefix(15).map(\.term).joined(separator: ", ") ?? ""
        return """
        You are Coach, a friendly \(t.name) tutor for a learner whose native language is \(n.name). Reply in \(t.name) first, at a level a learner can follow. Put each \(t.name) sentence on its own line, and put its \(n.name) translation in parentheses on the next line. Never mix \(n.name) into the \(t.name) sentence itself. Keep replies under 120 words and end with a question to keep the conversation going. Do not list the learner's mistakes in your reply unless asked; they are tracked separately. \
        \(CoachStage.current.promptRule) Mined sentences: \(minedList). Known weaknesses of this learner so far: \(top.isEmpty ? "none yet" : top). Saved words: \(words.isEmpty ? "none" : words). \
        \(context.map { "The learner is studying the material: \($0)." } ?? "") \
        If asked "what are my weaknesses", answer from the known weaknesses above with examples, honestly, in \(n.name).
        """
    }

    private func retry() {
        error = nil
        if let last = msgs.last, last.role == "user" { stream(for: last) }
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else {
            AI.debug("coach.send.skipped empty=\(t.isEmpty) sending=\(sending)")
            return
        }
        AI.debug("coach.send.accepted chars=\(t.count)")
        error = nil
        followsLatest = true
        Analytics.capture("coach_message_sent")
        let m = ChatMsg(role: "user", content: t)
        m.languageCode = languageCode
        ctx.insert(m)
        stream(for: m)
        analyze(m)
    }

    private func stream(for user: ChatMsg) {
        sending = true; streaming = ""
        AI.debug("coach.state sending=true history=\(msgs.count)")
        var history = msgs.suffix(20).map { AIMessage(role: $0.role, content: $0.content) }
        if !history.contains(where: { $0.content == user.content && $0.role == "user" }) { history.append(.init(role: "user", content: user.content)) }
        let all = [AIMessage(role: "system", content: systemPrompt())] + history
        let replyLanguage = user.languageCode
        task = Task {
            func saveReply(_ content: String) { let reply = ChatMsg(role: "assistant", content: content); reply.languageCode = replyLanguage; ctx.insert(reply); AI.debug("coach.reply.saved chars=\(content.count)") }
            var acc = ""
            do {
                for try await piece in AI.stream(all) { acc += piece; streaming = acc; AI.debug("coach.state streaming chars=\(acc.count)") }
                let beforeClean = acc.count
                acc = Self.clean(acc)
                AI.debug("coach.filter beforeChars=\(beforeClean) afterChars=\(acc.count)")
                if acc.isEmpty { self.error = L10n.string("coach.error"); AI.debug("coach.state empty_after_filter") }
                if !acc.isEmpty { saveReply(acc) }
            } catch is CancellationError {
                AI.debug("coach.error cancellation chars=\(acc.count)")
                if !acc.isEmpty { saveReply(Self.clean(acc)) }
            } catch {
                AI.debug("coach.error type=\(String(describing: type(of: error))) chars=\(acc.count)")
                self.error = L10n.string("coach.error")
                if !acc.isEmpty { saveReply(acc) }
            }
            streaming = nil; sending = false
            AI.debug("coach.state sending=false")
        }
    }

    static func clean(_ s: String) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.filter { !$0.hasPrefix("User Safety:") && !$0.hasPrefix("Response Safety:") }
        let result = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        AI.debug("coach.filter.lines input=\(lines.count) removed=\(lines.count - kept.count) outputChars=\(result.count)")
        return result
    }

    /// Silently checks the learner's message for mistakes and records them.
    private func analyze(_ m: ChatMsg) {
        let t = Prefs.target, n = Prefs.native
        guard m.content.count > 3 else { return }
        let sys = """
        You check a \(t.name) learner's message for mistakes. Reply with ONLY a JSON array, no prose. Each item: {"category": one of "Grammar","Vocabulary","Word choice","Particles","Politeness","Spelling", "pattern": short name of the pattern in English like "Past tense" or "Particles は/が", "wrong": the exact wrong fragment from the message, "right": the corrected fragment, "reason": under 8 words in \(n.name)}. If the message is not in \(t.name) or has no mistakes, reply []. Be thorough: check every particle (は/が/を/に/で/へ), verb conjugation (e.g. 食べるました should be 食べました), politeness level, and word choice. Example: message \"私は本を好きです\" -> [{\"category\":\"Particles\",\"pattern\":\"Particles が/を with 好き\",\"wrong\":\"本を好き\",\"right\":\"本が好き\",\"reason\":\"好き takes が\"}]. Only real mistakes, max 4.
        """
        Task {
            guard let out = try? await AI.complete([.init(role: "system", content: sys), .init(role: "user", content: m.content)]) else { return }
            guard let s = out.firstIndex(of: "["), let e = out.lastIndex(of: "]"), s < e,
                  let data = String(out[s...e]).data(using: .utf8),
                  let items = try? JSONDecoder().decode([Correction].self, from: data) else { return }
            let valid = items.filter { !$0.wrong.isEmpty && !$0.right.isEmpty && $0.wrong != $0.right }
            guard !valid.isEmpty else { return }
            m.corrections = valid
            for c in valid { let mistake = Mistake(c); mistake.languageCode = m.languageCode; ctx.insert(mistake) }
        }
    }
}

struct Bubble: View {
    let text: String, user: Bool
    private var styled: Text {
        if user { return Text(text).font(Theme.Fonts.body) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out = Text("")
        for (i, l) in lines.enumerated() {
            let t = l.trimmingCharacters(in: .whitespaces)
            let tr = (t.hasPrefix("(") || t.hasPrefix("（")) && (t.hasSuffix(")") || t.hasSuffix("）"))
            out = out + (tr ? Text(l).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) : Text(l).font(Theme.Fonts.body))
            if i < lines.count - 1 { out = out + Text("\n") }
        }
        return out
    }
    var body: some View {
        styled.textSelection(.enabled)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                            (Text(m.wrong).strikethrough().foregroundStyle(Theme.vermilion) + Text(" → ").foregroundStyle(Theme.textSecondary) + Text(m.right).fontWeight(.semibold).foregroundStyle(Theme.ink)).font(Theme.Fonts.body)
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
