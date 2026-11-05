import SwiftUI
import SwiftData
import AVFoundation

struct LiveCoachView: View {
    let language: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = LiveSession()
    @State private var store = LiveConfigurationStore.shared
    @State private var pronunciation = false
    @State private var settings = false
    @State private var lookup: LiveLookup?
    @State private var startError: String?
    private struct LiveLookup: Identifiable { var id = UUID(); var text: String; var word = "" }
    private var status: String {
        switch session.phase {
        case .idle: return L10n.string("Ready to talk")
        case .connecting: return L10n.string("Connecting microphone…")
        case .listening: return session.muted ? L10n.string("Microphone muted") : L10n.string("Listening — speak naturally")
        case .thinking: return L10n.string("Coach is thinking…")
        case .speaking: return L10n.string("Coach is speaking — you can interrupt")
        case .ended: return L10n.string("Conversation ended")
        }
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Label(status, systemImage: session.phase == .speaking ? "speaker.wave.2" : "waveform")
                            .font(.headline).accessibilityAddTraits(.updatesFrequently).accessibilityIdentifier("live.status")
                        if !session.active {
                            Text("Speak, listen, and try again.").literary(.title1)
                            Text("Your original voice is sent to your realtime service so Coach can listen to pronunciation, rhythm and intonation. Feedback is a model's suggestion, not a pronunciation test score.")
                                .foregroundStyle(Theme.textSecondary)
                            Toggle("Pronunciation & intonation practice", isOn: $pronunciation)
                            Label(store.configuration.webSearch ? "Web search enabled" : "Web search off", systemImage: "globe")
                                .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                            Button { settings = true } label: {
                                ActionRowLabel(title: "Voice service settings", symbol: "slider.horizontal.3")
                            }.buttonStyle(TextActionStyle())
                        }
                        ForEach(session.turns) { turn in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(turn.role == "user" ? "You" : "Coach").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                                TappableText(text: turn.text, language: language, furigana: false) { word in lookup = LiveLookup(text: turn.text, word: word) }
                                Button("Look up a word", systemImage: "character.book.closed") { lookup = LiveLookup(text: turn.text) }
                                    .buttonStyle(TextActionStyle())
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if session.searchCount > 0 {
                            Text(L10n.format("live.searchCount", Int64(session.searchCount)))
                                .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        }
                        if let error = session.error ?? startError {
                            Text(error).foregroundStyle(Theme.errorText).accessibilityAddTraits(.updatesFrequently)
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.frame(maxWidth: 680, alignment: .leading).padding(24).frame(maxWidth: .infinity)
                }
                .onChange(of: session.turns.last?.text) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
            }
            .background(Theme.background).foregroundStyle(Theme.ink).tint(Theme.accent)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if session.active {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { liveControls }
                            VStack(spacing: 12) { liveControls }
                        }
                        Button("End conversation", role: .destructive) { session.stop() }
                            .buttonStyle(PaperActionStyle(expanded: true))
                    } else {
                        Button("Start voice conversation", systemImage: "waveform") { start() }
                            .buttonStyle(InkButtonStyle()).accessibilityIdentifier("live.start")
                    }
                }.frame(maxWidth: 680).padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: .infinity).background(Theme.background)
            }
            .navigationTitle("Live Coach").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { session.stop(); dismiss() } } }
            .sheet(isPresented: $settings) { NavigationStack { LiveSettingsView() } }
            .sheet(item: $lookup) { item in QuickDictionaryView(initialQuery: item.word, sentence: item.text, initialLanguage: language) }
            .onChange(of: scenePhase) { _, value in if value == .background { session.stop() } }
            .onChange(of: store.revision) { _, _ in session.stop() }
            .onChange(of: Operations.shared.generation) { _, _ in session.stop() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in session.stop() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { session.stop() }
            }
            .onDisappear { session.stop() }
        }
    }
    @ViewBuilder private var liveControls: some View {
        Button { session.setMuted(!session.muted) } label: {
            Label(session.muted ? "Unmute" : "Mute", systemImage: session.muted ? "mic.slash" : "mic")
        }.buttonStyle(PaperActionStyle(expanded: true))
        if session.phase == .speaking {
            Button("Interrupt") { Task { await session.interrupt() } }
                .buttonStyle(PaperActionStyle(expanded: true))
        }
    }
    private func start() {
        startError = nil
        do {
            let key = try store.apiKey()
            guard !key.isEmpty else { settings = true; return }
            let generation = Operations.shared.generation
            session.start(configuration: store.configuration, apiKey: key, language: language, pronunciation: pronunciation) { role, text in
                try Operations.shared.checkpoint(generation)
                let message = ChatMsg(role: role, content: text); message.languageCode = language
                context.insert(message)
                do { try context.save() } catch { context.delete(message); throw error }
            }
        } catch { startError = error.localizedDescription }
    }
}

struct LiveSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = LiveConfiguration()
    @State private var key = ""
    @State private var failure: String?
    @State private var loaded = false
    @State private var confirmReset = false
    var body: some View {
        Form {
            Section {
                LabeledContent("Provider", value: "Qwen Omni Realtime")
                VStack(alignment: .leading, spacing: 8) {
                    Text("WebSocket endpoint").font(Theme.Fonts.meta)
                    TextField("wss://…/api-ws/v1/realtime", text: $configuration.endpoint, axis: .vertical)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("live.endpoint")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Realtime model").font(Theme.Fonts.meta)
                    TextField("Realtime model", text: $configuration.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice").font(Theme.Fonts.meta)
                    TextField("Voice", text: $configuration.voice).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                SecureField("Voice API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
            } footer: {
                Text("Use the endpoint and API key from the same Alibaba Cloud region/workspace. Voice service is configured separately from the text AI service; keys stay in this device's Keychain.")
            }.listRowBackground(Theme.surface)
            Section {
                Toggle("Allow web search in voice conversations", isOn: $configuration.webSearch)
            } footer: {
                Text("Requires a Qwen3.5 or Qwen3.8 Omni realtime model. The service decides when to search; audio and search may incur usage charges. A search count is shown only when reported by the service.")
            }.listRowBackground(Theme.surface)
            Section {
                Text("The microphone starts only after you press Start. Leaving the voice screen or backgrounding the app ends the session. Audio is streamed to your chosen service and is not saved by Yomiori; completed text captions are kept in Coach history.")
            }.listRowBackground(Theme.surface)
            if let failure { Section { Text(failure).foregroundStyle(Theme.errorText) }.listRowBackground(Theme.surface) }
            Section { Button("Remove voice configuration", role: .destructive) { confirmReset = true }.disabled(!loaded) }.listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden).background(Theme.groupedBackground).foregroundStyle(Theme.ink).tint(Theme.accent)
        .navigationTitle("Voice service").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") {
            do { try LiveConfigurationStore.shared.save(configuration, apiKey: key); dismiss() } catch { failure = error.localizedDescription }
        }.disabled(!loaded) } }
        .onAppear {
            do { configuration = LiveConfigurationStore.shared.configuration; key = try LiveConfigurationStore.shared.apiKey(); loaded = true }
            catch { failure = error.localizedDescription }
        }
        .confirmationDialog("Remove voice configuration?", isPresented: $confirmReset) {
            Button("Remove", role: .destructive) {
                do { try LiveConfigurationStore.shared.reset(); dismiss() } catch { failure = error.localizedDescription }
            }
        }
    }
}
