import Foundation
import Testing
@testable import Yomiori

struct AIClientTests {
    @Test func requestsUseSelectedProtocolAndExplicitEndpoint() throws {
        for format in AIConfiguration.Format.allCases {
            let client = try AIClient(configuration: .init(format: format, endpoint: "https://example.com/custom/path?version=1", model: "test-model"), apiKey: "secret")
            let request = try client.request([.init(role: "user", content: "hello")], stream: true)
            let requestData = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
            #expect(request.url?.absoluteString == "https://example.com/custom/path?version=1")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            #expect(body["model"] as? String == "test-model")
            #expect(body["stream"] as? Bool == true)
            if format == .responses {
                #expect(body["input"] != nil); #expect(body["messages"] == nil); #expect(body["store"] as? Bool == false)
            } else { #expect(body["messages"] != nil); #expect(body["input"] == nil) }
        }
    }
    @Test func invalidConfigurationFailsBeforeSending() throws {
        for endpoint in ["", "http://example.com/v1/responses", "https://user:password@example.com/v1/responses", "https://example.com/path#fragment"] {
            #expect(throws: AIError.invalidConfiguration) { try AIConfiguration(format: .responses, endpoint: endpoint, model: "model").validated() }
        }
        #expect(throws: AIError.invalidConfiguration) { try AIConfiguration(format: .responses, endpoint: "https://example.com/v1/responses", model: " ").validated() }
        #expect(try AIConfiguration(format: .relay, endpoint: "https://example.com/api/ai/chat").validated().model.isEmpty)
    }
    @Test @MainActor func configurationStoresSecretsSeparatelyAndSurvivesReload() throws {
        let defaults = try #require(UserDefaults(suiteName: "ai-test-\(UUID())"))
        let secret = MemorySecret()
        let store = AIConfigurationStore(defaults: defaults, secrets: secret)
        let configuration = AIConfiguration(format: .responses, endpoint: "https://example.com/v1/responses", model: "model")
        try store.save(configuration, apiKey: "private-key")
        #expect(secret.value == "private-key")
        let stored = try #require(defaults.data(forKey: "ai.configuration.v1"))
        #expect(!String(decoding: stored, as: UTF8.self).contains("private-key"))
        let reloaded = AIConfigurationStore(defaults: defaults, secrets: secret)
        #expect(reloaded.configuration == configuration)
        #expect(try reloaded.apiKey() == "private-key")
        secret.fail = true
        #expect(throws: AIError.credentials) { try store.reset() }
        #expect(store.configuration == configuration)
        secret.fail = false
        try store.reset()
        #expect(secret.value.isEmpty); #expect(store.configuration.endpoint.isEmpty)
    }
}

private final class MemorySecret: SecretStorage {
    var value = ""
    var fail = false
    func read() throws -> String { if fail { throw AIError.credentials }; return value }
    func write(_ value: String) throws { if fail { throw AIError.credentials }; self.value = value }
}
