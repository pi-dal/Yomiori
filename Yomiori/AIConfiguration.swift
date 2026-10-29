import Foundation
import Security
import Observation

struct AIConfiguration: Codable, Equatable, Sendable {
    enum Format: String, Codable, CaseIterable, Sendable { case responses, openAI, relay }
    var format: Format = .responses
    var endpoint = ""
    var model = ""

    func validated() throws -> AIConfiguration {
        var value = self
        value.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value.endpoint), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else { throw AIError.invalidConfiguration }
        guard !value.endpoint.contains(where: { $0.isWhitespace || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }),
              value.format == .relay || !value.model.isEmpty else { throw AIError.invalidConfiguration }
        return value
    }
}

protocol SecretStorage {
    func read() throws -> String
    func write(_ value: String) throws
}

struct KeychainSecretStorage: SecretStorage {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "Yomiori") + ".ai",
         kSecAttrAccount as String: "api-key"]
    }
    func read() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else { throw AIError.credentials }
        return text
    }
    func write(_ value: String) throws {
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AIError.credentials }
            return
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AIError.credentials }
        } else if status != errSecSuccess { throw AIError.credentials }
    }
}

@MainActor @Observable
final class AIConfigurationStore {
    static let shared = AIConfigurationStore()
    private(set) var configuration: AIConfiguration
    private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: any SecretStorage
    private let storageKey = "ai.configuration.v1"

    init(defaults: UserDefaults = .standard, secrets: any SecretStorage = KeychainSecretStorage()) {
        self.defaults = defaults
        self.secrets = secrets
        configuration = defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(AIConfiguration.self, from: $0) } ?? AIConfiguration()
    }
    func apiKey() throws -> String { try secrets.read() }
    func save(_ configuration: AIConfiguration, apiKey: String) throws {
        let validated = try configuration.validated()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }) else { throw AIError.invalidConfiguration }
        let data = try JSONEncoder().encode(validated)
        try secrets.write(key)
        defaults.set(data, forKey: storageKey)
        self.configuration = validated
        revision += 1
    }
    func reset() throws {
        try secrets.write("")
        defaults.removeObject(forKey: storageKey)
        configuration = AIConfiguration()
        revision += 1
    }
    func client() throws -> AIClient {
        guard !configuration.endpoint.isEmpty else { throw AIError.notConfigured }
        return try AIClient(configuration: configuration.validated(), apiKey: apiKey())
    }
}
