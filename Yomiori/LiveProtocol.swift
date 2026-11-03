import Foundation

/// Qwen's audio protocol sends microphone PCM, not a speech-to-text substitute.
enum LiveProtocol {
    static func encode(_ type: String, _ fields: [String: Any] = [:]) throws -> String {
        var event = fields
        event["type"] = type; event["event_id"] = "event_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let data = try JSONSerialization.data(withJSONObject: event)
        return String(decoding: data, as: UTF8.self)
    }
    static func session(configuration: LiveConfiguration, language: String, pronunciation: Bool) throws -> String {
        var session: [String: Any] = [
            "modalities": ["text", "audio"], "voice": configuration.voice,
            "input_audio_format": "pcm", "output_audio_format": "pcm",
            "input_audio_transcription": ["model": "qwen3-asr-flash-realtime"],
            "turn_detection": ["type": "server_vad", "threshold": 0.5, "silence_duration_ms": 650],
            "instructions": """
            You are a live \(Language.find(language).name) conversation tutor. The learner's native language is \(Prefs.native.name).
            \(CoachStage.current.promptRule)
            You receive the original microphone audio. Listen to pronunciation, rhythm, stress and intonation, not just the reference transcript. Never claim to hear a feature not audible in the audio. If unclear, ask the learner to repeat. Do not invent a numerical pronunciation score or a phonetic measurement. Keep each spoken reply brief (one or two sentences), let the learner speak, and use the target language with concise native-language help when needed.
            \(pronunciation ? "Pronunciation practice: ask for one short sentence, listen to it, then give one specific audible improvement and demonstrate the corrected pronunciation for the learner to repeat." : "Have a natural conversation. Offer a short correction for a clear pronunciation or intonation issue without interrupting every turn.")
            Search only when useful for a factual question if web search is enabled. Distinguish retrieved information from your own suggestions. Never claim a word has been saved; saving happens only when the learner presses Add to dictionary in the app.
            """
        ]
        if configuration.webSearch { session["enable_search"] = true; session["search_options"] = ["enable_source": true] }
        return try encode("session.update", ["session": session])
    }
}

struct LiveEvent {
    let type: String
    let value: [String: Any]
    init(data: Data) throws {
        guard data.count <= 2_000_000,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = value["type"] as? String else { throw LiveError.protocolError }
        self.type = type; self.value = value
    }
    var responseID: String? { value["response_id"] as? String ?? (value["response"] as? [String: Any])?["id"] as? String }
    var itemID: String { value["item_id"] as? String ?? "" }
    var delta: String { value["delta"] as? String ?? "" }
    var transcript: String { value["transcript"] as? String ?? value["text"] as? String ?? "" }
    var responseStatus: String? { (value["response"] as? [String: Any])?["status"] as? String }
    var serviceError: Error {
        let code = ((value["error"] as? [String: Any])?["code"] as? String ?? "").lowercased()
        if code.contains("auth") || code.contains("api_key") { return AIError.unauthorized }
        if code.contains("rate") || code.contains("quota") { return AIError.limit }
        return LiveError.protocolError
    }
}

/// Response identity prevents cancelled or delayed chunks from restarting playback.
struct LiveResponseState {
    private(set) var activeID: String?
    private(set) var cancelled = Set<String>()
    mutating func begin(_ id: String?) { activeID = id }
    mutating func interrupt() -> String? {
        guard let id = activeID else { return nil }
        cancelled.insert(id); activeID = nil
        return id
    }
    func accepts(_ id: String?) -> Bool { id != nil && id == activeID && !cancelled.contains(id!) }
    mutating func finish(_ id: String?) { if activeID == id { activeID = nil } }
}
