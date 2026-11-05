import Foundation
import Testing
import SwiftData
@testable import Yomiori

@MainActor struct LiveCoachTests {
    @Test func sessionSendsOriginalPCMAndIgnoresCancelledAudio() async throws {
        let wire = TestLiveConnection(), audio = TestLiveAudio()
        let session = LiveSession(connection: wire, audio: audio)
        var persisted: [String] = []
        session.start(configuration: LiveConfiguration(), apiKey: "test-key", language: "ja", pronunciation: true) { role, text in persisted.append(role + ":" + text) }
        await wait { wire.connected }
        wire.emit(["type": "session.created"])
        await wait { wire.sent.count == 1 }
        let update = try #require(try JSONSerialization.jsonObject(with: Data(wire.sent[0].utf8)) as? [String: Any])
        let settings = try #require(update["session"] as? [String: Any])
        #expect(settings["input_audio_format"] as? String == "pcm")
        #expect((settings["instructions"] as? String)?.contains("original microphone audio") == true)
        wire.emit(["type": "session.updated"])
        await wait { session.phase == .listening }
        audio.continuation?.yield(Data([1, 0, 2, 0]))
        await wait { wire.sent.count == 2 }
        let input = try #require(try JSONSerialization.jsonObject(with: Data(wire.sent[1].utf8)) as? [String: Any])
        #expect(input["audio"] as? String == Data([1, 0, 2, 0]).base64EncodedString())
        wire.emit(["type": "response.created", "response": ["id": "r1"]])
        wire.emit(["type": "response.audio.delta", "response_id": "r1", "delta": Data([3, 0]).base64EncodedString()])
        await wait { audio.played.count == 1 }
        wire.emit(["type": "input_audio_buffer.speech_started"])
        await wait { wire.sent.contains { $0.contains("response.cancel") } }
        wire.emit(["type": "response.audio.delta", "response_id": "r1", "delta": Data([4, 0]).base64EncodedString()])
        wire.emit(["type": "response.audio_transcript.done", "response_id": "r1", "transcript": "unfinished"])
        wire.emit(["type": "response.done", "response": ["id": "r1", "status": "cancelled"]])
        wire.emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": "u1", "transcript": "こんにちは"])
        wire.emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": "u1", "transcript": "こんにちは"])
        wire.emit(["type": "response.created", "response": ["id": "r2"]])
        wire.emit(["type": "response.audio_transcript.done", "response_id": "r2", "transcript": "もう一度"])
        wire.emit(["type": "response.done", "response": ["id": "r2", "status": "completed"]])
        await wait { persisted.count == 2 }
        #expect(audio.played == [Data([3, 0])])
        #expect(persisted == ["user:こんにちは", "assistant:もう一度"])
        session.stop()
        #expect(!session.active)
        #expect(audio.stopped)
        #expect(wire.closed)
    }
    @Test func mutedAudioAndLateEventsNeverPublishAfterEnding() async throws {
        let wire = TestLiveConnection(), audio = TestLiveAudio(), session = LiveSession(connection: TestLiveConnection(), audio: TestLiveAudio())
        // A second instance proves session state is not shared through singletons.
        #expect(!session.active)
        let live = LiveSession(connection: wire, audio: audio)
        var persisted = 0
        live.start(configuration: LiveConfiguration(), apiKey: "test", language: "en", pronunciation: false) { _, _ in persisted += 1 }
        await wait { wire.connected }
        wire.emit(["type": "session.created"]); wire.emit(["type": "session.updated"])
        await wait { live.phase == .listening }
        live.setMuted(true); audio.continuation?.yield(Data([1, 0]))
        for _ in 0..<30 { await Task.yield() }
        #expect(wire.sent.count == 1)
        live.stop()
        wire.emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": "late", "transcript": "late"])
        for _ in 0..<30 { await Task.yield() }
        #expect(persisted == 0)
        #expect(live.turns.isEmpty)
    }
    @Test func configurationRejectsInsecureURLsAndUnsupportedSearch() throws {
        var config = LiveConfiguration()
        config.endpoint = "ws://localhost/realtime"
        #expect(throws: (any Error).self) { try config.validated() }
        config = LiveConfiguration(); config.webSearch = true; config.model = "qwen3-omni-flash-realtime"
        #expect(throws: (any Error).self) { try config.validated() }
        config.model = "qwen3.5-omni-flash-realtime"
        let request = try config.request(apiKey: "test")
        #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "model" })?.value == config.model)
        #expect(throws: (any Error).self) { try config.request(apiKey: "test\nInjected: true") }
        let event = try LiveProtocol.session(configuration: config, language: "en", pronunciation: false)
        let value = try #require(try JSONSerialization.jsonObject(with: Data(event.utf8)) as? [String: Any])
        #expect((value["session"] as? [String: Any])?["enable_search"] as? Bool == true)
    }
    @Test func localLookupWorksWithoutAIAndSavingDeduplicatesWithinLanguage() throws {
        let container = try ModelContainer(for: DictEntry.self, Card.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let data = try Data(contentsOf: #require(Bundle.main.url(forResource: "word-atlas", withExtension: "json")))
        let document = try WordListDocument.decodeValidated(data)
        let word = try #require(document.entries.first)
        let hits = QuickDictionary.search("  " + word.w.uppercased() + "  ", language: "en", saved: [], documents: [document])
        let exact = try #require(hits.first)
        #expect(QuickDictionary.normalized(exact.term) == QuickDictionary.normalized(word.w))
        try QuickDictionary.save(exact, context: context)
        try QuickDictionary.save(exact, context: context)
        var japanese = exact; japanese.language = "ja"
        try QuickDictionary.save(japanese, context: context)
        let saved = try context.fetch(FetchDescriptor<DictEntry>())
        #expect(saved.count == 2)
        #expect(QuickDictionary.search(word.w, language: "en", saved: saved, documents: [document]).filter { QuickDictionary.normalized($0.term) == QuickDictionary.normalized(word.w) }.count == 1)
        #expect(QuickDictionary.search("  ", language: "en", saved: saved, documents: [document]).isEmpty)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YOMIORI_AUDIO_DEVICE_TEST"] == "1"))
    func nativeVoiceEngineStartsPlaysAndCloses() async throws {
        let audio = LiveAudio()
        defer { audio.stop() }
        let stream = try await audio.start()
        let capture = Task { () throws -> Data? in
            for try await data in stream { return data }
            return nil
        }
        defer { capture.cancel() }
        try audio.play(Data(repeating: 0, count: 4800))
        #expect(audio.isPlaying)
        try await Task.sleep(for: .milliseconds(250))
        audio.interrupt()
        #expect(!audio.isPlaying)
        audio.stop()
        let sample = try await capture.value
        #expect(sample != nil)
        #expect(sample?.count.isMultiple(of: 2) == true)
    }
    @Test func simulatorRejectsMicrophoneBeforeRemoteIOCanAbort() async throws {
        #if targetEnvironment(simulator)
        let audio = LiveAudio()
        do { _ = try await audio.start(); Issue.record("Simulator audio must fail before RemoteIO") }
        catch { #expect(error is LiveError) }
        audio.stop()
        #endif
    }
    private func wait(_ predicate: () -> Bool) async {
        for _ in 0..<2000 { if predicate() { return }; await Task.yield() }
        #expect(predicate())
    }
}

@MainActor private final class TestLiveConnection: LiveConnection {
    var connected = false, closed = false
    var sent: [String] = []
    private var pending: [Data] = []
    private var receiver: CheckedContinuation<Data, Error>?
    func connect(_ request: URLRequest) { connected = true; closed = false }
    func send(_ event: String) async throws { sent.append(event) }
    func receive() async throws -> Data {
        if !pending.isEmpty { return pending.removeFirst() }
        return try await withCheckedThrowingContinuation { receiver = $0 }
    }
    func close() { closed = true; receiver?.resume(throwing: LiveError.interrupted); receiver = nil }
    func emit(_ object: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        if let receiver { self.receiver = nil; receiver.resume(returning: data) }
        else { pending.append(data) }
    }
}
@MainActor private final class TestLiveAudio: LiveAudioIO {
    var stopped = false
    var isPlaying = false
    var played: [Data] = []
    var playbackFinished: (() -> Void)?
    var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    func start() async throws -> AsyncThrowingStream<Data, Error> {
        stopped = false
        return AsyncThrowingStream { continuation = $0 }
    }
    func play(_ pcm: Data) throws { played.append(pcm); isPlaying = true }
    func interrupt() { isPlaying = false }
    func stop() { stopped = true; continuation?.finish(); continuation = nil }
}
