import Foundation

/// Injectable network adapter shared by Coach, dictionary and translation.
struct AIClient: Sendable {
    let configuration: AIConfiguration
    let apiKey: String
    let session: URLSession

    init(configuration: AIConfiguration, apiKey: String = "", session: URLSession = .shared) throws {
        self.configuration = try configuration.validated()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }) else { throw AIError.invalidConfiguration }
        self.apiKey = key
        self.session = session
    }
    func request(_ messages: [AIMessage], stream: Bool) throws -> URLRequest {
        guard let endpoint = URL(string: configuration.endpoint) else { throw AIError.invalidConfiguration }
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let messageKey = configuration.format == .responses ? "input" : "messages"
        var body: [String: Any] = [messageKey: messages.map { ["role": $0.role, "content": $0.content] }, "stream": stream]
        if configuration.format == .responses { body["store"] = false }
        if !configuration.model.isEmpty { body["model"] = configuration.model }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw AIError.unauthorized
        case 429: throw AIError.limit
        default: throw AIError.unavailable
        }
    }
    func complete(_ messages: [AIMessage]) async throws -> String {
        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request(messages, stream: false))
            try Task.checkCancellation()
            try check(response)
            return try Self.decodeCompletion(data, format: configuration.format)
        } catch { throw AIError.preservingCancellation(error) }
    }
    static func decodeCompletion(_ data: Data, format: AIConfiguration.Format) throws -> String {
        if format == .responses {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["status"] as? String == "completed", object["error"] == nil || object["error"] is NSNull,
                  let output = object["output"] as? [[String: Any]] else { throw AIError.invalidResponse }
            let text = output.filter { $0["type"] as? String == "message" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidResponse }
            return text
        }
        struct Reply: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            let text: String?
            let choices: [Choice]?
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let text = format == .relay ? reply.text : reply.choices?.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidResponse }
        return text
    }
    func stream(_ messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let (bytes, response) = try await session.bytes(for: request(messages, stream: true))
                    try check(response)
                    guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else { throw AIError.invalidResponse }
                    var framing = ServerSentEvents()
                    var parser = AIStreamParser(format: configuration.format)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if let event = try framing.consume(byte), let content = try parser.consume("data: " + event) { continuation.yield(content) }
                        if parser.finished { break }
                    }
                    if !parser.finished, let event = try framing.finish(), let content = try parser.consume("data: " + event) { continuation.yield(content) }
                    try Task.checkCancellation()
                    try parser.finish()
                    continuation.finish()
                } catch { continuation.finish(throwing: AIError.preservingCancellation(error)) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
