import Foundation
import Speech
import AVFoundation

enum TranscribeError: LocalizedError {
    case denied, unsupported, none
    var errorDescription: String? {
        switch self {
        case .denied: L10n.string("Allow speech recognition in Settings.")
        case .unsupported: L10n.string("Speech recognition is unavailable for this language.")
        case .none: L10n.string("read.noSubtitlesBody")
        }
    }
}

enum Transcriber {
    static func run(url: URL, locale: String, progress: @escaping @Sendable (Double) -> Void) async throws -> [SubLine] {
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard status == .authorized else { throw TranscribeError.denied }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: locale)), rec.isAvailable else { throw TranscribeError.unsupported }
        let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        let segments: [SFTranscriptionSegment] = try await withCheckedThrowingContinuation { c in
            var done = false
            rec.recognitionTask(with: req) { result, error in
                if done { return }
                if let result {
                    let end = result.bestTranscription.segments.last.map { $0.timestamp + $0.duration } ?? 0
                    if duration > 0 { progress(min(end / duration, 1)) }
                    if result.isFinal { done = true; c.resume(returning: result.bestTranscription.segments) }
                } else if let error { done = true; c.resume(throwing: error) }
            }
        }
        guard !segments.isEmpty else { throw TranscribeError.none }
        // Group word segments into subtitle lines at pauses or after ~14 seconds / sentence ends.
        var lines: [SubLine] = []
        var cur: [SFTranscriptionSegment] = []
        let joiner = locale.hasPrefix("ja") || locale.hasPrefix("zh") ? "" : " "
        func flush() {
            guard let f = cur.first, let l = cur.last else { return }
            lines.append(SubLine(start: f.timestamp, end: l.timestamp + l.duration, text: cur.map(\.substring).joined(separator: joiner)))
            cur = []
        }
        for s in segments {
            if let l = cur.last, s.timestamp - (l.timestamp + l.duration) > 0.7 { flush() }
            cur.append(s)
            if let f = cur.first, s.timestamp + s.duration - f.timestamp > 8 || "。.!?！？".contains(s.substring.last ?? " ") { flush() }
        }
        flush()
        return lines
    }
}
