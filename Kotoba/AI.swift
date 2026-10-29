import Foundation
import OSLog

struct AIMessage: Codable { var role: String; var content: String }

private let aiLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Kotoba", category: "AI")

#if DEBUG
private func aiErrorName(_ error: Error) -> String { String(describing: type(of: error)) }
#endif

enum AIError: LocalizedError {
    case offline, limit, unavailable, failed
    var errorDescription: String? {
        switch self {
        case .offline: "You're offline."
        case .limit: "Coach has reached today's limit. Try again tomorrow."
        case .unavailable: "Coach can't answer right now. Check your connection and try again."
        case .failed: "Coach can't answer right now. Check your connection and try again."
        }
    }
}

/// Talks to Kotoba's own Worker, which relays to AirRouter. No keys in the app.
enum AI {
    static let endpoint = URL(string: "https://your-backend.example.invalid/api/ai/chat")!

    #if DEBUG
    static func debug(_ event: String) { aiLogger.debug("\(event, privacy: .public)") }
    #else
    static func debug(_ event: String) {}
    #endif

    static var installID: String {
        let k = "installID"
        if let v = UserDefaults.standard.string(forKey: k) { return v }
        let v = UUID().uuidString.lowercased()
        UserDefaults.standard.set(v, forKey: k)
        return v
    }

    private static func request(_ messages: [AIMessage], stream: Bool) throws -> URLRequest {
        var r = URLRequest(url: endpoint, timeoutInterval: 60)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(installID, forHTTPHeaderField: "X-Install-Id")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": messages.map { ["role": $0.role, "content": $0.content] }, "stream": stream,
        ])
        #if DEBUG
        debug("request.start stream=\(stream) messages=\(messages.count) bodyBytes=\(r.httpBody?.count ?? 0)")
        #endif
        return r
    }

    private static func map(_ error: Error) -> AIError {
        if let e = error as? AIError { return e }
        if (error as? URLError)?.code == .notConnectedToInternet { return .offline }
        return .unavailable
    }
    private static func check(_ response: URLResponse?) throws {
        guard let h = response as? HTTPURLResponse else { throw AIError.failed }
        #if DEBUG
        debug("response.status code=\(h.statusCode)")
        #endif
        if h.statusCode == 429 { throw AIError.limit }
        if h.statusCode != 200 { throw AIError.unavailable }
    }

    static func complete(_ messages: [AIMessage]) async throws -> String {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request(messages, stream: false))
            try check(resp)
            struct R: Decodable { let text: String }
            let result = try JSONDecoder().decode(R.self, from: data).text
            #if DEBUG
            debug("complete.success responseBytes=\(data.count) textChars=\(result.count)")
            #endif
            return result
        } catch {
            #if DEBUG
            debug("complete.error type=\(aiErrorName(error))")
            #endif
            throw map(error)
        }
    }

    static func stream(_ messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                var lines = 0
                var decoded = 0
                var parseFailures = 0
                var contentChunks = 0
                var reasoningOnlyChunks = 0
                var contentChars = 0
                var sawDone = false
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: request(messages, stream: true))
                    try check(resp)
                    struct Chunk: Decodable { struct C: Decodable { struct D: Decodable { let content: String?; let reasoning: String? }; let delta: D? }; let choices: [C]? }
                    for try await line in bytes.lines {
                        lines += 1
                        guard line.hasPrefix("data:") else { continue }
                        let p = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if p == "[DONE]" { sawDone = true; break }
                        guard let d = p.data(using: .utf8) else { parseFailures += 1; continue }
                        guard let c = try? JSONDecoder().decode(Chunk.self, from: d) else { parseFailures += 1; continue }
                        decoded += 1
                        let delta = c.choices?.first?.delta
                        if let t = delta?.content, !t.isEmpty {
                            contentChunks += 1; contentChars += t.count; cont.yield(t)
                        } else if delta?.reasoning?.isEmpty == false {
                            reasoningOnlyChunks += 1
                        }
                    }
                    #if DEBUG
                    debug("stream.end lines=\(lines) decoded=\(decoded) parseFailures=\(parseFailures) contentChunks=\(contentChunks) contentChars=\(contentChars) reasoningOnly=\(reasoningOnlyChunks) done=\(sawDone)")
                    #endif
                    cont.finish()
                } catch {
                    #if DEBUG
                    debug("stream.error lines=\(lines) decoded=\(decoded) contentChunks=\(contentChunks) reasoningOnly=\(reasoningOnlyChunks) type=\(aiErrorName(error))")
                    #endif
                    cont.finish(throwing: map(error))
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    /// Translates numbered segments; returns translations in the same order.
    static func translate(_ parts: [String], from: Language, to: Language) async throws -> [String] {
        let numbered = parts.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
        let sys = "You translate \(from.name) into \(to.name). Translate each numbered segment. Reply with the same numbering, one segment per entry, in the form [n] translation. No commentary."
        let out = try await complete([.init(role: "system", content: sys), .init(role: "user", content: numbered)])
        return parseNumbered(out, count: parts.count)
    }

    static func parseNumbered(_ text: String, count: Int) -> [String] {
        var result = Array(repeating: "", count: count)
        let re = try! NSRegularExpression(pattern: "\\[(\\d+)\\]")
        let ns = text as NSString
        let ms = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for (i, m) in ms.enumerated() {
            let n = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let end = i + 1 < ms.count ? ms[i + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: m.range.upperBound, length: end - m.range.upperBound))
            if n >= 1 && n <= count { result[n - 1] = body.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return result
    }
}
