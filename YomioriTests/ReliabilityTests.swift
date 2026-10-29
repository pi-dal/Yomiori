import Foundation
import SwiftData
import Testing
import ZIPFoundation
@testable import Yomiori

@MainActor struct ReliabilityTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Material.self, DictEntry.self, PDFDoc.self, ChatMsg.self, Mistake.self, Card.self, ImmersionLog.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    @Test func resetPersistsFailureThenRetriesAndInvalidatesOperations() throws {
        let container = try container(), context = container.mainContext
        let defaults = try #require(UserDefaults(suiteName: "reset-test-\(UUID())"))
        let operations = Operations(defaults: defaults), original = operations.generation
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let library = WordListLibrary(directory: root.appending(path: "catalogue"), builtInURL: nil)
        context.insert(Card(sentence: "hello", word: "hello")); try context.save()
        #expect(throws: (any Error).self) {
            try AppDataService.clear(context: context, operations: operations, library: library, directories: [root], removeDirectory: { _ in throw CocoaError(.fileWriteNoPermission) })
        }
        #expect(operations.resetPending)
        #expect(operations.generation != original)
        #expect(Operations(defaults: defaults).resetPending)
        #expect(throws: CancellationError.self) { try operations.checkpoint(original) }
        try AppDataService.clear(context: context, operations: operations, library: WordListLibrary(directory: root.appending(path: "lists"), builtInURL: nil), directories: [root])
        #expect(!operations.resetPending)
        #expect(try context.fetch(FetchDescriptor<Card>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
    @Test func lateOperationResultIsRejectedAfterReset() async throws {
        let defaults = try #require(UserDefaults(suiteName: "operation-test-\(UUID())"))
        let operations = Operations(defaults: defaults)
        let gate = AsyncGate<String>()
        let task = Task { try await operations.run { await gate.wait() } }
        while !gate.waiting { await Task.yield() }
        operations.beginReset()
        gate.resume("late result")
        do { _ = try await task.value; Issue.record("Stale result was accepted") }
        catch { #expect(error is CancellationError) }
    }
    @Test func clearingCoachRejectsLateReplyAndAnalysisEvenIfTransportIgnoresCancellation() async throws {
        let container = try container(), context = container.mainContext
        let gate = AsyncGate<String>()
        var streamContinuation: AsyncThrowingStream<String, Error>.Continuation?
        let session = CoachSession(complete: { _ in await gate.wait() }, stream: { _ in
            AsyncThrowingStream { streamContinuation = $0 }
        })
        session.send("hello world", language: "en", context: nil, modelContext: context)
        while !gate.waiting || streamContinuation == nil { await Task.yield() }
        session.clear(language: "en", modelContext: context)
        streamContinuation?.yield("late reply"); streamContinuation?.finish()
        gate.resume(#"[{"category":"Grammar","pattern":"Tense","wrong":"hello","right":"hi","reason":"test"}]"#)
        for _ in 0..<20 { await Task.yield() }
        #expect(!session.sending)
        #expect(session.streaming == nil)
        #expect(try context.fetch(FetchDescriptor<ChatMsg>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Mistake>()).isEmpty)
    }
    @Test func failedStreamDoesNotPersistPartialReply() async throws {
        let container = try container(), context = container.mainContext
        let session = CoachSession(complete: { _ in "[]" }, stream: { _ in
            AsyncThrowingStream { $0.yield("half reply"); $0.finish(throwing: AIError.interrupted) }
        })
        session.send("hi", language: "en", context: nil, modelContext: context)
        while session.sending { await Task.yield() }
        let messages = try context.fetch(FetchDescriptor<ChatMsg>())
        #expect(messages.count == 1)
        #expect(messages.first?.role == "user")
        #expect(session.error != nil)
    }
    @Test func translationIdentityIncludesBothLanguagesAndTextBoundaries() {
        let original = TranslationKey(source: "en", target: "zh", texts: ["ab", "c"])
        #expect(original.cacheID != TranslationKey(source: "en", target: "ja", texts: ["ab", "c"]).cacheID)
        #expect(original.cacheID != TranslationKey(source: "ja", target: "zh", texts: ["ab", "c"]).cacheID)
        #expect(original.cacheID != TranslationKey(source: "en", target: "zh", texts: ["a", "bc"]).cacheID)
    }
    @Test func pageCacheSeparatesLanguagesAndContentAndRejectsMalformedOutput() async throws {
        let container = try container(), context = container.mainContext
        let doc = PDFDoc(title: "test", fileName: "test.pdf"); context.insert(doc); try context.save()
        var requests = 0
        let translator: @MainActor ([String], Language, Language) async throws -> [String] = { texts, _, target in
            requests += 1; return texts.map { "\(target.code):\($0)" }
        }
        _ = try await TranslationService.page(doc, page: 0, texts: ["hello"], source: "en", target: "zh", context: context, translate: translator)
        let cached = try await TranslationService.page(doc, page: 0, texts: ["hello"], source: "en", target: "zh", context: context, translate: translator)
        #expect(cached == ["zh:hello"]); #expect(requests == 1)
        _ = try await TranslationService.page(doc, page: 0, texts: ["hello"], source: "en", target: "ja", context: context, translate: translator)
        _ = try await TranslationService.page(doc, page: 0, texts: ["changed"], source: "en", target: "ja", context: context, translate: translator)
        #expect(requests == 3)
        do {
            _ = try await TranslationService.page(doc, page: 1, texts: ["hello"], source: "en", target: "zh", context: context, translate: { _, _, _ in [] })
            Issue.record("Malformed translation accepted")
        } catch { #expect(error as? AIError == .invalidResponse) }
        #expect(try doc.readTranslations().count == 3)
    }
    @Test func replacedSubtitlesRejectLateTranslation() async throws {
        let container = try container(), context = container.mainContext
        let material = Material(title: "test"); material.languageCode = "en"
        try material.writeLines([SubLine(start: 0, end: 1, text: "original")]); context.insert(material); try context.save()
        let gate = AsyncGate<[String]>()
        let task = Task {
            try await TranslationService.subtitles(material, target: "zh", context: context, translate: { _, _, _ in await gate.wait() })
        }
        while !gate.waiting { await Task.yield() }
        try material.writeLines([SubLine(start: 0, end: 1, text: "replacement")])
        gate.resume(["旧翻译"])
        do { try await task.value; Issue.record("Stale translation committed") }
        catch { #expect(error is CancellationError) }
        #expect(try material.readLines().first?.text == "replacement")
        #expect(try material.readLines().first?.translation == nil)
    }
    @Test func recognitionBridgeCancelsBeforeStartAndCompletesOnlyOnce() async throws {
        let cancelled = RecognitionOperation(); cancelled.cancel()
        do {
            let _: [SubLine] = try await withCheckedThrowingContinuation { continuation in
                #expect(!cancelled.begin(continuation))
            }
            Issue.record("Pre-cancelled recognition started")
        } catch { #expect(error is CancellationError) }
        let operation = RecognitionOperation()
        let result: [SubLine] = try await withCheckedThrowingContinuation { continuation in
            #expect(operation.begin(continuation))
            operation.complete(.success([SubLine(start: 0, end: 1, text: "done")]))
            operation.cancel()
            operation.complete(.failure(TranscribeError.none))
        }
        #expect(result.first?.text == "done")
    }
    @Test func legacySubtitlesDecodeAndCorruptBlobIsPreserved() throws {
        let material = Material(title: "test")
        let id = UUID()
        material.linesData = Data("[{\"id\":\"\(id)\",\"start\":0,\"end\":1,\"text\":\"hello\",\"translation\":\"old\"}]".utf8)
        #expect(try material.readLines().first?.translationTarget == nil)
        #expect(material.lines.first?.id == id)
        let corrupt = Data("corrupt".utf8)
        material.linesData = corrupt
        #expect(throws: (any Error).self) { try material.readLines() }
        #expect(material.lines.isEmpty)
        #expect(material.contentError != nil)
        #expect(material.linesData == corrupt)
    }
    @Test func exporterBuildsExistingFilesAndFailsWithoutMarkingCards() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audio = root.appending(path: "audio.m4a"); try Data("audio".utf8).write(to: audio)
        let card = Card(sentence: "a,\"quote\"\nline", word: "word"); card.audioFile = "audio.m4a"
        let artifact = try AnkiExporter.build([ExportCard(card), ExportCard(card)], audioDirectory: root, outputDirectory: root)
        #expect(artifact.files.count == 1)
        #expect(artifact.files[0].pathExtension == "zip")
        let archive = try Archive(url: artifact.files[0], accessMode: .read)
        #expect(Set(archive.map(\.path)) == ["cards.csv", "audio.m4a", "README.txt"])
        let csv = try #require(archive["cards.csv"])
        var contents = Data()
        _ = try archive.extract(csv) { contents.append($0) }
        #expect(String(decoding: contents, as: UTF8.self).contains("\"a,\"\"quote\"\"\nline\""))
        let audioEntry = try #require(archive["audio.m4a"])
        var audioContents = Data()
        _ = try archive.extract(audioEntry) { audioContents.append($0) }
        #expect(audioContents == Data("audio".utf8))
        #expect(!card.exported)
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(throws: (any Error).self) {
            try AnkiExporter.build([ExportCard(sentence: "test", word: "test", meaning: "test", audioFile: "missing.m4a")], audioDirectory: root, outputDirectory: root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == before)
        #expect(!card.exported)
    }
    @Test func exporterCancellationAndInvalidAudioLeaveNoArtifacts() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cancelled = Progress(); cancelled.cancel()
        #expect(throws: CancellationError.self) {
            try AnkiExporter.build([ExportCard(sentence: "text", word: "word", meaning: "meaning")],
                                   audioDirectory: root, outputDirectory: root, progress: cancelled)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        #expect(throws: (any Error).self) {
            try AnkiExporter.build([ExportCard(sentence: "text", word: "word", meaning: "meaning", audioFile: "../outside.m4a")],
                                   audioDirectory: root, outputDirectory: root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}

@MainActor private final class AsyncGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    var waiting: Bool { continuation != nil }
    func wait() async -> Value { await withCheckedContinuation { continuation = $0 } }
    func resume(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
}
