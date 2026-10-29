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
    @Test func decodesResponsesAndRejectsIncompleteResults() throws {
        let valid = Data(#"{"status":"completed","error":null,"output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"Hello"},{"type":"output_text","text":" world"}]}]}"#.utf8)
        #expect(try AIClient.decodeCompletion(valid, format: .responses) == "Hello world")
        for json in [#"{"status":"incomplete","output":[]}"#, #"{"status":"failed","error":{"message":"bad"},"output":[]}"#, #"{"status":"completed","output":[]}"#] {
            #expect(throws: AIError.invalidResponse) { try AIClient.decodeCompletion(Data(json.utf8), format: .responses) }
        }
        #expect(try AIClient.decodeCompletion(Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8), format: .openAI) == "OK")
        #expect(try AIClient.decodeCompletion(Data(#"{"text":"OK"}"#.utf8), format: .relay) == "OK")
    }
    @Test func responsesStreamCompletesWithoutDoneMarkerAndDoesNotDuplicateText() throws {
        var parser = AIStreamParser(format: .responses)
        #expect(try parser.consume(#"data: {"type":"response.created"}"#) == nil)
        #expect(try parser.consume(#"data: {"type":"response.output_text.delta","item_id":"a","content_index":0,"delta":"Hello"}"#) == "Hello")
        #expect(try parser.consume(#"data: {"type":"response.output_text.done","item_id":"a","content_index":0,"text":"Hello"}"#) == nil)
        #expect(try parser.consume(#"data: {"type":"response.completed","response":{"status":"completed"}}"#) == nil)
        try parser.finish()
        #expect(parser.finished)
    }
    @Test func terminalOnlyResponsesCanProvideOutput() throws {
        var parser = AIStreamParser(format: .responses)
        #expect(try parser.consume(#"data: {"type":"response.completed","response":{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}}"#) == "OK")
        try parser.finish()
    }
    @Test func interruptedAndFailedStreamsNeverSucceed() throws {
        var parser = AIStreamParser()
        #expect(try parser.consume(#"data: {"choices":[{"delta":{"content":"half"}}]}"#) == "half")
        #expect(throws: AIError.interrupted) { try parser.finish() }
        #expect(throws: AIError.invalidResponse) { try parser.consume("data: malformed") }
        for event in ["response.failed", "response.incomplete", "error"] {
            var responses = AIStreamParser(format: .responses)
            #expect(throws: AIError.failed) { try responses.consume("data: {\"type\":\"\(event)\"}") }
        }
        var responses = AIStreamParser(format: .responses)
        #expect(throws: AIError.interrupted) { try responses.consume("data: [DONE]") }
        #expect(AIError.preservingCancellation(URLError(.cancelled)) is CancellationError)
    }
    @Test func sseFramingHandlesMultilineDataCRLFCommentsAndUTF8() throws {
        var framing = ServerSentEvents()
        let source = ": heartbeat\r\nevent: response.output_text.delta\r\ndata: {\"type\":\"response.output_text.delta\",\r\ndata: \"delta\":\"你好\"}\r\n\r\n"
        var frames: [String] = []
        for byte in source.utf8 { if let frame = try framing.consume(byte) { frames.append(frame) } }
        #expect(frames.count == 1)
        var parser = AIStreamParser(format: .responses)
        let frame = try #require(frames.first)
        #expect(try parser.consume("data: " + frame) == "你好")
    }
    @Test func sseFramingBoundsUnterminatedEvents() throws {
        var framing = ServerSentEvents()
        #expect(throws: AIError.invalidResponse) {
            for byte in ("data: " + String(repeating: "x", count: 1_048_577)).utf8 { _ = try framing.consume(byte) }
        }
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
