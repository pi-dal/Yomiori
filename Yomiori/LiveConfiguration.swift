import Foundation
import Observation

struct LiveConfiguration: Codable, Equatable, Sendable {
    var endpoint = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
    var model = "qwen3.5-omni-flash-realtime"
    var voice = "Tina"
    var webSearch = false

    var supportsSearch: Bool { model.hasPrefix("qwen3.5-omni-") || model.hasPrefix("qwen3.8-omni-") }
    func validated() throws -> LiveConfiguration {
        var value = self
        value.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        value.voice = voice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value.endpoint), url.scheme == "wss", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil,
              !value.endpoint.contains(where: { $0.isWhitespace || $0.isNewline }),
              !value.model.isEmpty, !value.voice.isEmpty else { throw LiveError.configuration }
        guard !value.webSearch || value.supportsSearch else { throw LiveError.searchUnsupported }
        return value
    }
    func request(apiKey: String) throws -> URLRequest {
        let value = try validated()
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }) else { throw AIError.unauthorized }
        var components = URLComponents(string: value.endpoint)!
        var query = components.queryItems?.filter { $0.name != "model" } ?? []
        query.append(URLQueryItem(name: "model", value: value.model)); components.queryItems = query
        guard let url = components.url else { throw LiveError.configuration }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}

enum LiveError: LocalizedError {
    case configuration, searchUnsupported, microphone, audio, simulator, interrupted, overloaded, protocolError
    var errorDescription: String? {
        let text = switch self {
        case .configuration: "Enter a complete WSS endpoint, realtime model and voice."
        case .searchUnsupported: "Web search requires a Qwen3.5 or Qwen3.8 Omni realtime model."
        case .microphone: "Allow microphone access in iPhone Settings to start a voice conversation."
        case .audio: "The audio device is unavailable. Check your microphone and try again."
        case .simulator: "Live microphone conversations require a real iPhone. Dictionary lookup is available in the simulator."
        case .interrupted: "The voice connection ended. Start a new conversation to reconnect."
        case .overloaded: "Audio could not keep up with the connection. Try again on a faster network."
        case .protocolError: "The realtime service returned an unsupported response. Check the model and endpoint."
        }
        return L10n.string(text)
    }
}

@MainActor @Observable final class LiveConfigurationStore {
    static let shared = LiveConfigurationStore()
    private(set) var configuration: LiveConfiguration
    private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: any SecretStorage
    private let storageKey = "ai.live.configuration.v1"
    init(defaults: UserDefaults = .standard, secrets: any SecretStorage = KeychainSecretStorage(account: "live-api-key")) {
        self.defaults = defaults; self.secrets = secrets
        configuration = defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(LiveConfiguration.self, from: $0) } ?? LiveConfiguration()
    }
    func apiKey() throws -> String { try secrets.read() }
    func save(_ configuration: LiveConfiguration, apiKey: String) throws {
        let value = try configuration.validated(), key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try value.request(apiKey: key)
        let data = try JSONEncoder().encode(value)
        try secrets.write(key)
        defaults.set(data, forKey: storageKey); self.configuration = value; revision += 1
    }
    func reset() throws {
        try secrets.write(""); defaults.removeObject(forKey: storageKey)
        configuration = LiveConfiguration(); revision += 1
    }
}
