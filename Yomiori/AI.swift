import Foundation
import OSLog

struct AIMessage: Codable, Equatable, Sendable { var role: String; var content: String }

enum AIError: LocalizedError, Equatable {
    case offline, limit, unavailable, failed, notConfigured, invalidConfiguration, credentials, unauthorized, interrupted, invalidResponse
    var errorDescription: String? {
        let message = switch self {
        case .offline: "You're offline."
        case .limit: "AI service is busy or its quota is exhausted. Try again later."
        case .unavailable: "AI service is unavailable. Check the address and connection."
        case .failed: "The AI request failed. Try again."
        case .notConfigured: "Configure an AI service in Settings first."
        case .invalidConfiguration: "Enter a complete HTTPS endpoint and a model for OpenAI-compatible services."
        case .credentials: "Couldn't access the API key in Keychain. Unlock your device and try again."
        case .unauthorized: "The AI service rejected your credentials. Check your API key."
        case .interrupted: "The reply was interrupted. Try again."
        case .invalidResponse: "The AI service returned an invalid response."
        }
        return L10n.string(message)
    }
    static func preservingCancellation(_ error: Error) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return CancellationError() }
        if let error = error as? AIError { return error }
        if (error as? URLError)?.code == .notConnectedToInternet { return AIError.offline }
        return AIError.unavailable
    }
}

/// Compatibility facade: all features resolve the same user configuration at request time.
@MainActor enum AI {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Yomiori", category: "AI")
    static func debug(_ event: String) {
        #if DEBUG
        logger.debug("\(event, privacy: .public)")
        #endif
    }
    static func complete(_ messages: [AIMessage]) async throws -> String {
        guard !AIConfigurationStore.shared.configuration.endpoint.isEmpty else { throw AIError.notConfigured }
        let revision = AIConfigurationStore.shared.revision
        let client = try AIConfigurationStore.shared.client()
        let result = try await Operations.shared.run { try await client.complete(messages) }
        guard revision == AIConfigurationStore.shared.revision else { throw CancellationError() }
        return result
    }
    static func stream(_ messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let revision = AIConfigurationStore.shared.revision
                    let client = try AIConfigurationStore.shared.client()
                    try await Operations.shared.run {
                        for try await piece in client.stream(messages) {
                            try Task.checkCancellation()
                            guard revision == AIConfigurationStore.shared.revision else { throw CancellationError() }
                            continuation.yield(piece)
                        }
                    }
                    guard revision == AIConfigurationStore.shared.revision else { throw CancellationError() }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    static func translate(_ parts: [String], from: Language, to: Language) async throws -> [String] {
        let numbered = parts.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
        let sys = "You translate \(from.name) into \(to.name). Translate each numbered segment. Reply with the same numbering, one segment per entry, in the form [n] translation. No commentary."
        let out = try await complete([.init(role: "system", content: sys), .init(role: "user", content: numbered)])
        let values = parseNumbered(out, count: parts.count)
        guard values.allSatisfy({ !$0.isEmpty }) else { throw AIError.invalidResponse }
        return values
    }
    nonisolated static func parseNumbered(_ text: String, count: Int) -> [String] {
        var result = Array(repeating: "", count: count)
        let re = try! NSRegularExpression(pattern: "\\[(\\d+)\\]")
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for (i, match) in matches.enumerated() {
            let n = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            if n >= 1 && n <= count { result[n - 1] = ns.substring(with: NSRange(location: match.range.upperBound, length: end - match.range.upperBound)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return result
    }
}
