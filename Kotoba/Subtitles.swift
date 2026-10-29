import Foundation

enum Subtitles {
    static func parse(_ raw: String) -> [SubLine] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        var out: [SubLine] = []
        for block in text.components(separatedBy: "\n\n") {
            let rows = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let ti = rows.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = rows[ti].components(separatedBy: "-->")
            guard parts.count == 2, let s = time(parts[0]), let e = time(parts[1]) else { continue }
            let body = rows[(ti + 1)...].joined(separator: " ")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !body.isEmpty { out.append(SubLine(start: s, end: e, text: body)) }
        }
        return out.sorted { $0.start < $1.start }
    }

    private static func time(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let comps = t.replacingOccurrences(of: ",", with: ".").split(separator: ":").map(String.init)
        guard !comps.isEmpty, comps.count <= 3 else { return nil }
        var total = 0.0
        for c in comps { guard let v = Double(c) else { return nil }; total = total * 60 + v }
        return total
    }

    static func srt(_ lines: [SubLine]) -> String {
        func f(_ t: Double) -> String {
            let ms = Int((t * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
        }
        return lines.enumerated().map { i, l in "\(i + 1)\n\(f(l.start)) --> \(f(l.end))\n\(l.text)\n" }.joined(separator: "\n")
    }

    static func stamp(_ t: Double) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Index of the line playing at `t` (the last line that started).
    static func index(at t: Double, in lines: [SubLine]) -> Int? {
        guard let first = lines.first, t >= first.start - 0.05 else { return nil }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].start <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}
