import Foundation
import CryptoKit
import SwiftData
import Observation

struct TranslationKey: Hashable, Sendable {
    let source: String
    let target: String
    let texts: [String]
    var cacheID: String {
        let data = (try? JSONEncoder().encode([source, target] + texts)) ?? Data()
        return "v2:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor enum TranslationService {
    static func page(_ doc: PDFDoc, page: Int, texts: [String], source: String, target: String,
                     context: ModelContext,
                     translate: @MainActor ([String], Language, Language) async throws -> [String] = { try await AI.translate($0, from: $1, to: $2) }) async throws -> [String] {
        let generation = Operations.shared.generation
        let key = TranslationKey(source: source, target: target, texts: texts).cacheID
        let cacheKey = "\(page):\(key)"
        let cache = try doc.readTranslations()
        if let result = cache[cacheKey], result.count == texts.count { return result }
        guard !texts.isEmpty else { return [] }
        let result = try await translate(texts, Language.find(source), Language.find(target))
        guard result.count == texts.count, result.allSatisfy({ !$0.isEmpty }) else { throw AIError.invalidResponse }
        try Operations.shared.checkpoint(generation)
        guard !doc.isDeleted, doc.modelContext != nil else { throw CancellationError() }
        var updated = try doc.readTranslations()
        updated[cacheKey] = result
        let old = doc.translationsData
        do { try doc.writeTranslations(updated); try context.save() }
        catch { doc.translationsData = old; throw error }
        return result
    }
    static func subtitles(_ material: Material, target: String, context: ModelContext,
                          translate: @MainActor ([String], Language, Language) async throws -> [String] = { try await AI.translate($0, from: $1, to: $2) }) async throws {
        let generation = Operations.shared.generation
        let source = material.languageCode
        let snapshot = try material.readLines()
        let pending = snapshot.filter { $0.translation == nil || $0.translationTarget != target || $0.translationSource != source }
        for offset in stride(from: 0, to: pending.count, by: 25) {
            let chunk = Array(pending[offset..<min(offset + 25, pending.count)])
            let output = try await translate(chunk.map(\.text), Language.find(source), Language.find(target))
            guard output.count == chunk.count, output.allSatisfy({ !$0.isEmpty }) else { throw AIError.invalidResponse }
            try Operations.shared.checkpoint(generation)
            guard !material.isDeleted, material.modelContext != nil, material.languageCode == source else { throw CancellationError() }
            var current = try material.readLines()
            // Subtitle replacement or edits invalidate this request; annotations alone do not.
            guard current.map(\.id) == snapshot.map(\.id), current.map(\.text) == snapshot.map(\.text) else { throw CancellationError() }
            let translated = Dictionary(uniqueKeysWithValues: zip(chunk.map(\.id), output))
            for index in current.indices {
                if let value = translated[current[index].id] {
                    current[index].translation = value
                    current[index].translationSource = source
                    current[index].translationTarget = target
                }
            }
            let old = material.linesData
            do { try material.writeLines(current); try context.save() }
            catch { material.linesData = old; throw error }
        }
    }
}

@MainActor @Observable
final class SubtitleTranslation {
    private(set) var running = false
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    func start(_ material: Material, target: String, context: ModelContext) {
        cancel()
        let id = UUID(); requestID = id
        running = true; error = nil
        task = Task {
            defer { if requestID == id { running = false; task = nil } }
            do { try await TranslationService.subtitles(material, target: target, context: context) }
            catch {
                guard requestID == id, !Task.isCancelled, !(error is CancellationError) else { return }
                self.error = error.localizedDescription
            }
        }
    }
    func cancel() { requestID = UUID(); task?.cancel(); task = nil; running = false }
}
