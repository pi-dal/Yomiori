import Foundation
import Observation

/// One invalidation point for every asynchronous operation that can outlive its screen.
/// Values may return only while their original data generation is current.
@MainActor @Observable
final class Operations {
    static let shared = Operations()
    private(set) var generation = UUID()
    var resetPending: Bool
    @ObservationIgnored private var cancellations: [UUID: () -> Void] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        resetPending = defaults.bool(forKey: "dataReset.pending")
    }
    func checkpoint(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard generation == self.generation, !resetPending else { throw CancellationError() }
    }
    func run<Value: Sendable>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let snapshot = generation
        try checkpoint(snapshot)
        let id = UUID()
        let task = Task { try await operation() }
        cancellations[id] = { task.cancel() }
        defer { cancellations[id] = nil }
        return try await withTaskCancellationHandler {
            let value = try await task.value
            try checkpoint(snapshot)
            return value
        } onCancel: { task.cancel() }
    }
    func beginReset() {
        defaults.set(true, forKey: "dataReset.pending")
        resetPending = true
        generation = UUID()
        let pending = cancellations.values
        cancellations.removeAll()
        pending.forEach { $0() }
    }
    func finishReset() {
        defaults.removeObject(forKey: "dataReset.pending")
        resetPending = false
    }
}
