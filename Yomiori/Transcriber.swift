import Foundation
import Speech
import AVFoundation

enum TranscribeError: LocalizedError {
    case denied, unsupported, none
    var errorDescription: String? {
        switch self {
        case .denied: L10n.string("Allow speech recognition in Settings.")
        case .unsupported: L10n.string("On-device speech recognition is unavailable for this language.")
        case .none: L10n.string("read.noSubtitlesBody")
        }
    }
}

/// Serializes callback completion and cancellation, including cancellation before task installation.
final class RecognitionOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[SubLine], Error>?
    private var recognition: SFSpeechRecognitionTask?
    private var finished = false
    private var cancelled = false

    func begin(_ continuation: CheckedContinuation<[SubLine], Error>) -> Bool {
        lock.lock()
        if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return false }
        self.continuation = continuation
        lock.unlock()
        return true
    }
    func install(_ recognition: SFSpeechRecognitionTask) {
        lock.lock()
        let shouldCancel = cancelled
        if !finished { self.recognition = recognition }
        lock.unlock()
        if shouldCancel { recognition.cancel() }
    }
    func complete(_ result: Result<[SubLine], Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation
        self.continuation = nil
        recognition = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let recognition = recognition
        lock.unlock()
        recognition?.cancel()
        complete(.failure(CancellationError()))
    }
}

enum Transcriber {
    static func run(url: URL, locale: String, progress: @escaping @Sendable (Double) -> Void) async throws -> [SubLine] {
        try Task.checkCancellation()
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        try Task.checkCancellation()
        guard status == .authorized else { throw TranscribeError.denied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { throw TranscribeError.unsupported }
        let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        try Task.checkCancellation()
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        let operation = RecognitionOperation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard operation.begin(continuation) else { return }
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        let lines = subtitles(result.bestTranscription.segments, locale: locale)
                        operation.complete(lines.isEmpty ? .failure(TranscribeError.none) : .success(lines))
                    } else if let error { operation.complete(.failure(error)) }
                    else if let result, duration > 0 {
                        let end = result.bestTranscription.segments.last.map { $0.timestamp + $0.duration } ?? 0
                        progress(min(end / duration, 1))
                    }
                }
                operation.install(task)
            }
        } onCancel: { operation.cancel() }
    }
    private static func subtitles(_ segments: [SFTranscriptionSegment], locale: String) -> [SubLine] {
        var lines: [SubLine] = [], current: [SFTranscriptionSegment] = []
        let joiner = locale.hasPrefix("ja") || locale.hasPrefix("zh") ? "" : " "
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            lines.append(SubLine(start: first.timestamp, end: last.timestamp + last.duration, text: current.map(\.substring).joined(separator: joiner)))
            current = []
        }
        for segment in segments {
            if let last = current.last, segment.timestamp - (last.timestamp + last.duration) > 0.7 { flush() }
            current.append(segment)
            if let first = current.first, segment.timestamp + segment.duration - first.timestamp > 8 || "。.!?！？".contains(segment.substring.last ?? " ") { flush() }
        }
        flush()
        return lines
    }
}
