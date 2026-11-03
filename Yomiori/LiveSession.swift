import Foundation
import Observation

@MainActor protocol LiveConnection: AnyObject {
    func connect(_ request: URLRequest)
    func send(_ event: String) async throws
    func receive() async throws -> Data
    func close()
}
@MainActor final class LiveWebSocket: LiveConnection {
    private var socket: URLSessionWebSocketTask?
    func connect(_ request: URLRequest) {
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = 2_000_000
        self.socket = socket; socket.resume()
    }
    func send(_ event: String) async throws {
        guard let socket else { throw LiveError.interrupted }
        try await socket.send(.string(event))
    }
    func receive() async throws -> Data {
        guard let socket else { throw LiveError.interrupted }
        switch try await socket.receive() {
        case .string(let text): return Data(text.utf8)
        case .data(let data): return data
        @unknown default: throw LiveError.protocolError
        }
    }
    func close() { socket?.cancel(with: .normalClosure, reason: nil); socket = nil }
}

@MainActor @Observable final class LiveSession {
    enum Phase { case idle, connecting, listening, thinking, speaking, ended }
    struct Turn: Identifiable { let id: String; let role: String; var text: String }
    private(set) var phase = Phase.idle
    private(set) var turns: [Turn] = []
    private(set) var error: String?
    private(set) var muted = false
    private(set) var searchCount = 0
    var active: Bool { [.connecting, .listening, .thinking, .speaking].contains(phase) }
    @ObservationIgnored private let connection: any LiveConnection
    @ObservationIgnored private let audio: any LiveAudioIO
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var microphoneTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var id = UUID()
    @ObservationIgnored private var responses = LiveResponseState()
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var sentUpdate = false
    @ObservationIgnored private var assistantText: [String: String] = [:]
    @ObservationIgnored private var completed = Set<String>()
    @ObservationIgnored private var persist: ((String, String) throws -> Void)?

    init(connection: (any LiveConnection)? = nil, audio: (any LiveAudioIO)? = nil) {
        self.connection = connection ?? LiveWebSocket(); self.audio = audio ?? LiveAudio()
        self.audio.playbackFinished = { [weak self] in
            if self?.phase == .speaking, self?.responses.activeID == nil { self?.phase = .listening }
        }
    }
    func start(configuration: LiveConfiguration, apiKey: String, language: String, pronunciation: Bool,
               persist: @escaping (String, String) throws -> Void) {
        stop(); turns = []; completed = []; assistantText = [:]; responses = LiveResponseState()
        error = nil; searchCount = 0; muted = false; self.persist = persist
        let token = UUID(); id = token; phase = .connecting
        let generation = Operations.shared.generation
        task = Task {
            do {
                let request = try configuration.request(apiKey: apiKey)
                let update = try LiveProtocol.session(configuration: configuration, language: language, pronunciation: pronunciation)
                let stream = try await audio.start()
                try Operations.shared.checkpoint(generation)
                guard id == token else { return }
                connection.connect(request)
                timeoutTask = Task {
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled, id == token, !ready else { return }
                    fail(LiveError.interrupted)
                }
                microphoneTask = Task {
                    do {
                        for try await pcm in stream {
                            try Operations.shared.checkpoint(generation)
                            guard id == token else { return }
                            if ready && !muted { try await connection.send(LiveProtocol.encode("input_audio_buffer.append", ["audio": pcm.base64EncodedString()])) }
                        }
                    } catch { if id == token, !Task.isCancelled { fail(error) } }
                }
                while !Task.isCancelled {
                    let data = try await connection.receive()
                    try Operations.shared.checkpoint(generation)
                    guard id == token else { return }
                    let event = try LiveEvent(data: data)
                    if event.type == "session.created", !sentUpdate {
                        sentUpdate = true; try await connection.send(update)
                    } else {
                        try await handle(event)
                    }
                }
            } catch { if id == token, !Task.isCancelled, !(error is CancellationError) { fail(error) } }
        }
    }
    func stop() {
        id = UUID(); ready = false; sentUpdate = false
        timeoutTask?.cancel(); timeoutTask = nil
        microphoneTask?.cancel(); microphoneTask = nil; task?.cancel(); task = nil
        connection.close(); audio.stop(); persist = nil
        if phase != .idle { phase = .ended }
    }
    func setMuted(_ value: Bool) { muted = value }
    func interrupt() async {
        audio.interrupt()
        if responses.interrupt() != nil {
            do { try await connection.send(LiveProtocol.encode("response.cancel")) }
            catch { fail(error) }
        }
        if active { phase = .listening }
    }
    private func fail(_ failure: Error) {
        stop(); error = failure.localizedDescription
    }
    private func storeTurn(id: String, role: String, text: String) throws {
        guard !id.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !completed.contains(id) else { return }
        try persist?(role, text)
        completed.insert(id)
        if let index = turns.firstIndex(where: { $0.id == id }) { turns[index].text = text }
        else { turns.append(Turn(id: id, role: role, text: text)) }
    }
    private func showAssistant(_ event: LiveEvent, final: Bool) {
        let key = event.responseID ?? event.itemID
        guard !key.isEmpty else { return }
        let text = final ? event.transcript : (assistantText[key, default: ""] + event.delta)
        assistantText[key] = String(text.prefix(24_000))
        if let index = turns.firstIndex(where: { $0.id == key }) { turns[index].text = assistantText[key]! }
        else { turns.append(.init(id: key, role: "assistant", text: assistantText[key]!)) }
    }
    private func handle(_ event: LiveEvent) async throws {
        switch event.type {
        case "session.updated":
            ready = true; timeoutTask?.cancel(); timeoutTask = nil; phase = .listening
        case "input_audio_buffer.speech_started":
            await interrupt()
        case "input_audio_buffer.speech_stopped": phase = .thinking
        case "conversation.item.input_audio_transcription.completed":
            try storeTurn(id: event.itemID, role: "user", text: event.transcript)
        case "conversation.item.input_audio_transcription.failed":
            // The audio model still receives the original speech; no invented transcript.
            error = L10n.string("Speech captions are unavailable. The voice model still receives your audio.")
        case "response.created":
            responses.begin(event.responseID); phase = .thinking
        case "response.audio.delta":
            guard responses.accepts(event.responseID) else { return }
            guard let data = Data(base64Encoded: event.delta) else { throw LiveError.protocolError }
            try audio.play(data); phase = .speaking
        case "response.audio_transcript.delta", "response.text.delta":
            guard responses.accepts(event.responseID) else { return }
            showAssistant(event, final: false)
        case "response.audio_transcript.done", "response.text.done":
            guard responses.accepts(event.responseID) else { return }
            showAssistant(event, final: true)
        case "response.done":
            guard responses.accepts(event.responseID) else { return }
            if event.responseStatus == "completed", let responseID = event.responseID {
                try storeTurn(id: responseID, role: "assistant", text: assistantText[responseID, default: ""])
            } else if event.responseStatus == "failed" { throw LiveError.protocolError }
            if let usage = (event.value["response"] as? [String: Any])?["usage"] as? [String: Any],
               let plugins = usage["plugins"] as? [String: Any], let search = plugins["search"] as? [String: Any] {
                searchCount += search["count"] as? Int ?? 0
            }
            responses.finish(event.responseID)
            if !audio.isPlaying { phase = .listening }
        case "error": throw event.serviceError
        case "session.finished": throw LiveError.interrupted
        default: break
        }
    }
}
