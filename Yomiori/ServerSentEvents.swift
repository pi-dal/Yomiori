import Foundation

/// Bounded UTF-8 SSE framing, independent of URLSession and provider JSON.
/// Data fields are joined before decoding; comments and heartbeat frames are ignored.
struct ServerSentEvents {
    private var line: [UInt8] = []
    private var data: [String] = []
    private var event = ""
    private var eventBytes = 0
    private var previousCR = false
    private let maximumBytes = 1_048_576

    mutating func consume(_ byte: UInt8) throws -> String? {
        if previousCR && byte == 10 { previousCR = false; return nil }
        previousCR = byte == 13
        if byte == 10 || byte == 13 { return try endLine() }
        line.append(byte)
        guard line.count + eventBytes <= maximumBytes else { throw AIError.invalidResponse }
        return nil
    }
    mutating func finish() throws -> String? {
        if !line.isEmpty { _ = try endLine() }
        return try dispatch()
    }
    private mutating func endLine() throws -> String? {
        guard let text = String(bytes: line, encoding: .utf8) else { throw AIError.invalidResponse }
        line.removeAll(keepingCapacity: true)
        if text.isEmpty { return try dispatch() }
        if text.hasPrefix(":") { return nil }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        if field == "data" {
            eventBytes += value.utf8.count + 1
            guard eventBytes <= maximumBytes else { throw AIError.invalidResponse }
            data.append(value)
        } else if field == "event" { event = value }
        return nil
    }
    private mutating func dispatch() throws -> String? {
        defer { data.removeAll(keepingCapacity: true); event = ""; eventBytes = 0 }
        if event == "error" { throw AIError.failed }
        return data.isEmpty ? nil : data.joined(separator: "\n")
    }
}
