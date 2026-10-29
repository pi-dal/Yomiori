import Foundation

/// OpenAI-compatible data events. Never turn a truncated or malformed stream into success.
struct AIStreamParser {
    var format: AIConfiguration.Format = .openAI
    private(set) var finished = false
    private var sawContent = false
    private var streamedItems = Set<String>()
    mutating func consume(_ line: String) throws -> String? {
        if line.hasPrefix("event:"), line.dropFirst(6).trimmingCharacters(in: .whitespaces) == "error" { throw AIError.failed }
        guard line.hasPrefix("data:"), !finished else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            guard format != .responses else { throw AIError.interrupted }
            finished = true; return nil
        }
        struct Chunk: Decodable {
            struct Choice: Decodable { struct Delta: Decodable { let content: String? }; let delta: Delta? }
            let choices: [Choice]?
        }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.invalidResponse }
        if let error = object["error"], !(error is NSNull) { throw AIError.failed }
        if format == .responses {
            guard let type = object["type"] as? String else { throw AIError.invalidResponse }
            switch type {
            case "response.output_text.delta":
                guard let delta = object["delta"] as? String else { throw AIError.invalidResponse }
                sawContent = sawContent || !delta.isEmpty
                streamedItems.insert(Self.itemKey(object))
                return delta
            case "response.output_text.done":
                guard !streamedItems.contains(Self.itemKey(object)), let text = object["text"] as? String else { return nil }
                streamedItems.insert(Self.itemKey(object))
                sawContent = sawContent || !text.isEmpty
                return text
            case "response.completed":
                guard let response = object["response"] as? [String: Any], response["status"] as? String == "completed" else { throw AIError.invalidResponse }
                finished = true
                if !sawContent, let data = try? JSONSerialization.data(withJSONObject: response),
                   let text = try? AIClient.decodeCompletion(data, format: .responses) {
                    sawContent = true; return text
                }
            case "response.failed", "response.incomplete", "error": throw AIError.failed
            default: break
            }
            return nil
        }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: data), chunk.choices != nil else { throw AIError.invalidResponse }
        guard let content = chunk.choices?.first?.delta?.content, !content.isEmpty else { return nil }
        sawContent = true
        return content
    }
    private static func itemKey(_ object: [String: Any]) -> String {
        "\(object["item_id"] as? String ?? "default"):\(object["content_index"] as? Int ?? 0)"
    }
    func finish() throws {
        guard finished else { throw AIError.interrupted }
        guard sawContent else { throw AIError.invalidResponse }
    }
}
