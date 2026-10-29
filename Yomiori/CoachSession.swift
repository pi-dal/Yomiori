import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class CoachSession {
    private(set) var streaming: String?
    private(set) var sending = false
    var error: String?
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var replyID = UUID()
    @ObservationIgnored private let complete: @MainActor ([AIMessage]) async throws -> String
    @ObservationIgnored private let stream: @MainActor ([AIMessage]) -> AsyncThrowingStream<String, Error>

    init(complete: @escaping @MainActor ([AIMessage]) async throws -> String = { try await AI.complete($0) },
         stream: @escaping @MainActor ([AIMessage]) -> AsyncThrowingStream<String, Error> = { AI.stream($0) }) {
        self.complete = complete; self.stream = stream
    }
    func send(_ text: String, language: String, context: String?, modelContext: ModelContext) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        do {
            try Operations.shared.checkpoint(Operations.shared.generation)
            let message = ChatMsg(role: "user", content: text)
            message.languageCode = language
            modelContext.insert(message)
            do { try modelContext.save() } catch { modelContext.delete(message); throw error }
            startReply(to: message, context: context, modelContext: modelContext)
            analyze(message, modelContext: modelContext)
        } catch { self.error = error.localizedDescription }
    }
    func retry(language: String, context: String?, modelContext: ModelContext) {
        guard !sending else { return }
        do {
            var descriptor = FetchDescriptor<ChatMsg>(predicate: #Predicate { $0.languageCode == language }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            descriptor.fetchLimit = 1
            if let message = try modelContext.fetch(descriptor).first, message.role == "user" {
                startReply(to: message, context: context, modelContext: modelContext)
            }
        } catch { self.error = error.localizedDescription }
    }
    func cancelReply() {
        replyID = UUID(); replyTask?.cancel(); replyTask = nil
        streaming = nil; sending = false
    }
    func invalidate() {
        sessionID = UUID(); cancelReply()
        analysisTasks.values.forEach { $0.cancel() }; analysisTasks.removeAll()
        error = nil
    }
    func clear(language: String, modelContext: ModelContext) {
        invalidate()
        do {
            try modelContext.delete(model: ChatMsg.self, where: #Predicate { $0.languageCode == language })
            try modelContext.save()
        } catch { self.error = error.localizedDescription }
    }
    private func startReply(to user: ChatMsg, context: String?, modelContext: ModelContext) {
        cancelReply(); error = nil
        do {
            let language = user.languageCode
            var historyQuery = FetchDescriptor<ChatMsg>(predicate: #Predicate { $0.languageCode == language }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            historyQuery.fetchLimit = 20
            let history = try modelContext.fetch(historyQuery).reversed().map { AIMessage(role: $0.role, content: $0.content) }
            let prompt = try CoachPrompts.conversation(language: language, context: context, modelContext: modelContext)
            let messages = [AIMessage(role: "system", content: prompt)] + history
            let generation = Operations.shared.generation, session = sessionID, request = UUID()
            replyID = request; sending = true; streaming = ""
            replyTask = Task {
                defer { if replyID == request { streaming = nil; sending = false; replyTask = nil } }
                do {
                    var text = ""
                    for try await delta in stream(messages) {
                        try Operations.shared.checkpoint(generation)
                        guard sessionID == session, replyID == request else { throw CancellationError() }
                        text += delta; streaming = text
                    }
                    try Operations.shared.checkpoint(generation)
                    guard sessionID == session, replyID == request, !user.isDeleted, user.modelContext != nil else { return }
                    let content = Self.clean(text)
                    guard !content.isEmpty else { throw AIError.invalidResponse }
                    let reply = ChatMsg(role: "assistant", content: content)
                    reply.languageCode = language
                    modelContext.insert(reply)
                    do { try modelContext.save() } catch { modelContext.delete(reply); throw error }
                } catch {
                    guard sessionID == session, replyID == request, !Task.isCancelled, !(error is CancellationError) else { return }
                    // A partial response is visible during streaming, but never persisted as a completed reply.
                    self.error = error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func analyze(_ message: ChatMsg, modelContext: ModelContext) {
        guard message.content.count > 3 else { return }
        let session = sessionID, generation = Operations.shared.generation, id = message.id
        let prompt = CoachPrompts.corrections(language: message.languageCode)
        let text = message.content
        analysisTasks[id] = Task {
            defer { analysisTasks[id] = nil }
            do {
                let output = try await complete([.init(role: "system", content: prompt), .init(role: "user", content: text)])
                try Operations.shared.checkpoint(generation)
                guard sessionID == session, !message.isDeleted, message.modelContext != nil else { return }
                guard let start = output.firstIndex(of: "["), let end = output.lastIndex(of: "]"), start < end,
                      let data = String(output[start...end]).data(using: .utf8) else { throw AIError.invalidResponse }
                let corrections = try JSONDecoder().decode([Correction].self, from: data).filter { !$0.wrong.isEmpty && !$0.right.isEmpty && $0.wrong != $0.right }.prefix(4)
                let old = message.correctionsData
                var inserted: [Mistake] = []
                message.corrections = Array(corrections)
                for correction in corrections {
                    let mistake = Mistake(correction); mistake.languageCode = message.languageCode
                    modelContext.insert(mistake); inserted.append(mistake)
                }
                do { try modelContext.save() }
                catch { message.correctionsData = old; inserted.forEach { modelContext.delete($0) }; throw error }
            } catch {
                // Correction failure does not invalidate a completed conversation reply.
                AI.debug("coach.analysis.failed type=\(String(describing: type(of: error)))")
            }
        }
    }
    static func clean(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("User Safety:") && !$0.hasPrefix("Response Safety:") }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor private enum CoachPrompts {
    static func conversation(language: String, context: String?, modelContext: ModelContext) throws -> String {
        var cards = FetchDescriptor<Card>(predicate: #Predicate { $0.languageCode == language }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        cards.fetchLimit = 10
        var entries = FetchDescriptor<DictEntry>(predicate: #Predicate { $0.languageCode == language }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        entries.fetchLimit = 15
        let mined = try modelContext.fetch(cards).map { "\($0.sentence) (\($0.word))" }.joined(separator: "; ")
        let words = try modelContext.fetch(entries).map(\.term).joined(separator: ", ")
        let mistakes = try modelContext.fetch(FetchDescriptor<Mistake>(predicate: #Predicate { $0.languageCode == language }))
        let top = Dictionary(grouping: mistakes, by: \.pattern).sorted { $0.value.count > $1.value.count }.prefix(5).map { "\($0.key) (\($0.value.count)x)" }.joined(separator: ", ")
        let target = Language.find(language), native = Prefs.native
        return """
        You are Coach, a friendly \(target.name) tutor for a learner whose native language is \(native.name). Keep replies under 120 words and end with a question. Do not list mistakes unless asked; they are tracked separately.
        \(CoachStage.current.promptRule)
        For Beginner stage, put each target-language sentence on its own line with its native-language translation in parentheses on the next line. Never mix languages inside a sentence. For other stages follow the stage's language rule.
        Mined sentences: \(mined.isEmpty ? "none" : mined). Known weaknesses: \(top.isEmpty ? "none yet" : top). Saved words: \(words.isEmpty ? "none" : words).
        \(context.map { "The learner is studying: \($0)." } ?? "")
        If asked about weaknesses, use the known weaknesses with examples honestly in \(native.name).
        """
    }
    static func corrections(language: String) -> String {
        """
        Check a \(Language.find(language).name) learner's message for real mistakes. Reply ONLY a JSON array, at most 4 items, or [] if correct or in another language. Each item: {"category":"Grammar|Vocabulary|Word choice|Particles|Politeness|Spelling","pattern":"short pattern name in English","wrong":"exact wrong fragment","right":"correct fragment","reason":"under 8 words in \(Prefs.native.name)"}. Check particles, verb forms, politeness and word choice. Do not invent mistakes.
        """
    }
}
