import Foundation
import Testing
@testable import Yomiori

struct AITransportTests {
    private func client(_ path: String, format: AIConfiguration.Format = .responses) throws -> AIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        return try AIClient(configuration: .init(format: format, endpoint: "https://fixture.invalid/\(path)", model: "fixture"), session: URLSession(configuration: configuration))
    }
    @Test func completionAndResponsesStreamingUseRealURLSessionAdapter() async throws {
        let completion = try await client("completion").complete([.init(role: "user", content: "hello")])
        #expect(completion == "你好")
        var text = ""
        for try await delta in try client("stream").stream([.init(role: "user", content: "hello")]) { text += delta }
        #expect(text == "你好")
    }
    @Test func transportRejectsUnauthorizedAndTruncatedStream() async throws {
        do { _ = try await client("unauthorized").complete([]); Issue.record("Expected credential failure") }
        catch { #expect(error as? AIError == .unauthorized) }
        do {
            for try await _ in try client("truncated").stream([]) {}
            Issue.record("Truncated stream succeeded")
        } catch { #expect(error as? AIError == .interrupted) }
    }
    @Test func cancellingStreamPreservesCancellation() async throws {
        let client = try client("stream")
        let task = Task {
            for try await _ in client.stream([]) { try Task.checkCancellation() }
            // AsyncThrowingStream may end iteration normally when its consumer is cancelled.
            try Task.checkCancellation()
        }
        task.cancel()
        do { try await task.value; Issue.record("Cancelled request succeeded") }
        catch { #expect(error is CancellationError) }
    }
}

private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.lastPathComponent
        let stream = path == "stream" || path == "truncated"
        let response = HTTPURLResponse(url: request.url!, statusCode: path == "unauthorized" ? 401 : 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": stream ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body: String
        if stream {
            body = "event: response.output_text.delta\r\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"你好\"}\r\n\r\n" + (path == "truncated" ? "" : "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n")
        } else {
            body = #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"你好"}]}]}"#
        }
        // Split in the middle of UTF-8 and SSE fields to exercise framing across network chunks.
        let bytes = Array(body.utf8)
        for offset in stride(from: 0, to: bytes.count, by: 7) {
            client?.urlProtocol(self, didLoad: Data(bytes[offset..<min(offset + 7, bytes.count)]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
