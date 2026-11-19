import Foundation
import SwiftData
import Testing
@testable import Yomiori

struct WordListImportTests {
    private func entry(_ id: String, term: String? = nil) -> [String: Any] {
        ["id": id, "term": term ?? id,
         "senses": [["partOfSpeech": "n.", "definition": "A definition", "translation": ""]],
         "examples": [], "level": "", "topic": "general"]
    }

    private func fixture(entries: [[String: Any]]? = nil) -> [String: Any] {
        ["format": "kotoba.wordlist", "version": 1, "id": "my-list", "title": "My list",
         "language": "en", "translationLanguage": "ja",
         "source": ["name": "Author", "url": "https://example.com/list", "license": "CC BY 4.0",
                    "licenseURL": "https://creativecommons.org/licenses/by/4.0/", "attribution": "Author",
                    "modified": false, "contentType": "user-authored"],
         "entries": entries ?? [entry("one")]]
    }

    private func data(_ raw: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: raw) }

    private func rejects(_ raw: [String: Any], at path: String) throws {
        do {
            _ = try WordListDocument.decodeValidated(data(raw))
            Issue.record("Expected validation to reject \(path)")
        } catch let error as WordListValidationError {
            #expect(error.path == path)
        }
    }

    @Test func duplicateIDsAndMediaURLs() throws {
        try rejects(fixture(entries: [entry("one"), entry("one")]), at: "$.entries[1].id")
        for url in ["http://example.com/a.mp3", "/audio/a.mp3", "https://", "https://user:pass@example.com/a", 42, NSNull()] as [Any] {
            var word = entry("one"); word["media"] = ["pronunciationURL": url]
            try rejects(fixture(entries: [word]), at: "$.entries[0].media.pronunciationURL")
        }
        var word = entry("one"); word["media"] = ["imageURL": "https://example.com/one.webp"]
        let decoded = try WordListDocument.decodeValidated(data(fixture(entries: [word])))
        #expect(decoded.entries.first?.pictureURL?.absoluteString == "https://example.com/one.webp")
    }

    @Test @MainActor func previewDoesNotWriteAndReservedListIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = WordListLibrary(directory: directory, builtInURL: nil)
        let preview = try library.prepare(data(fixture()))
        #expect(preview.newCount == 1 && preview.duplicateCount == 0)
        #expect(preview.existing == nil && library.documents.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        var newer = fixture(); newer["version"] = 2
        #expect(throws: WordListValidationError.self) { try library.prepare(data(newer)) }
        var reserved = fixture(); reserved["id"] = "ielts"
        #expect(throws: WordListValidationError.self) { try library.prepare(data(reserved)) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test @MainActor func previewBeforeLoadEnforcesPersistedLanguageIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = WordListLibrary(directory: directory, builtInURL: nil)
        try library.confirm(library.prepare(data(fixture())), policy: .skip)
        let fresh = WordListLibrary(directory: directory, builtInURL: nil)
        for key in ["language", "translationLanguage"] {
            var raw = fixture(); raw[key] = "ja"
            if key == "translationLanguage" { raw[key] = "en" }
            #expect(throws: WordListValidationError.self) { try fresh.prepare(data(raw)) }
        }
    }

    @Test @MainActor func catalogueUpdateAndReAddPreserveSavedCardSnapshotsAndSchedules() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = WordListLibrary(directory: directory, builtInURL: nil)
        var originalWord = entry("one")
        originalWord["examples"] = [["text": "Original example", "translation": "元の例文"]]
        originalWord["pronunciations"] = ["us": "original reading"]
        originalWord["media"] = ["exampleAudioURL": "https://example.com/original.mp3"]
        let original = try library.confirm(library.prepare(data(fixture(entries: [originalWord]))), policy: .skip).document
        let container = try ModelContainer(for: Card.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let japanese = Card(sentence: "日本語の文", word: "日本語")
        japanese.meaning = "Japanese"
        japanese.interval = 9; japanese.ease = 2.1; japanese.reps = 7; japanese.lapses = 2
        japanese.due = Date(timeIntervalSince1970: 1_800_000_000)
        context.insert(japanese)
        #expect(try IELTSCardWriter.add(original.entries, context: context, document: original) == 1)
        let saved = try #require(context.fetch(FetchDescriptor<Card>()).first { $0.wordListID == original.id })
        saved.interval = 21; saved.ease = 2.7; saved.reps = 12; saved.lapses = 3
        saved.due = Date(timeIntervalSince1970: 1_900_000_000)
        try context.save()
        var changedWord = entry("one", term: "Changed term")
        changedWord["senses"] = [["partOfSpeech": "v.", "definition": "Changed definition", "translation": "変更"]]
        changedWord["examples"] = [["text": "Changed example", "translation": "変更された例"]]
        changedWord["pronunciations"] = ["us": "changed reading"]
        changedWord["media"] = ["exampleAudioURL": "https://example.com/changed.mp3"]
        let updated = try library.confirm(library.prepare(data(fixture(entries: [changedWord]))), policy: .update)
        #expect(updated.updatedCount == 1 && updated.document.entries[0].term == "Changed term")
        #expect(try IELTSCardWriter.add(updated.document.entries, context: context, document: updated.document) == 0)
        let cards = try context.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 2)
        #expect(saved.wordListID == original.id && saved.wordListEntryID == "one" && saved.languageCode == "en")
        #expect(saved.word == "one" && saved.sentence == "Original example")
        #expect(saved.definitionEnglish == "A definition" && saved.reading == "original reading")
        #expect(saved.meaning.isEmpty && saved.translation == "元の例文")
        #expect(saved.audioRemoteURL == "https://example.com/original.mp3")
        #expect(saved.interval == 21 && saved.ease == 2.7 && saved.reps == 12 && saved.lapses == 3)
        #expect(saved.due == Date(timeIntervalSince1970: 1_900_000_000))
        #expect(japanese.languageCode == "ja" && japanese.wordListID.isEmpty)
        #expect(japanese.word == "日本語" && japanese.sentence == "日本語の文" && japanese.meaning == "Japanese")
        #expect(japanese.interval == 9 && japanese.ease == 2.1 && japanese.reps == 7 && japanese.lapses == 2)
        #expect(japanese.due == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test @MainActor func clearImportedRetainsBuiltInAndRemovesPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("WordLists")
        let builtinURL = root.appendingPathComponent("builtin.json")
        var builtin = fixture(); builtin["id"] = "ielts"
        try data(builtin).write(to: builtinURL)
        let library = WordListLibrary(directory: directory, builtInURL: builtinURL)
        await library.load()
        try library.confirm(library.prepare(data(fixture())), policy: .skip)
        #expect(library.documents.count == 2)
        try library.clearImported()
        #expect(library.documents.map(\.id) == ["ielts"])
        let reloaded = WordListLibrary(directory: directory, builtInURL: builtinURL)
        await reloaded.load()
        #expect(reloaded.documents == library.documents)
    }

    @Test @MainActor func importMergesByPolicyAndRejectsStalePreviewsWithoutWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = WordListLibrary(directory: directory, builtInURL: nil)
        let initial = try library.prepare(data(fixture(entries: [entry("one"), entry("keep")])))
        let inserted = try await library.confirmInBackground(initial, policy: .skip)
        #expect(inserted.newCount == 2 && inserted.updatedCount == 0)
        let preview = try library.prepare(data(fixture(entries: [entry("one", term: "Updated"), entry("new")])))
        let skipped = try await library.confirmInBackground(preview, policy: .skip)
        #expect(skipped.document.entries.map(\.id) == ["one", "keep", "new"])
        #expect(skipped.document.entries[0].term == "one" && skipped.updatedCount == 0)
        let current = try library.prepare(data(fixture(entries: [entry("one", term: "Updated"), entry("new")])))
        let updated = try await library.confirmInBackground(current, policy: .update)
        #expect(updated.updatedCount == 1 && updated.newCount == 0)
        #expect(updated.document.entries[0].term == "Updated")
        #expect(updated.document.entries[1] == inserted.document.entries[1])
        let before = library.documents
        do {
            _ = try await library.confirmInBackground(preview, policy: .update)
            Issue.record("A stale preview must require refresh")
        } catch is WordListValidationError {}
        #expect(library.documents == before)
        let reopened = WordListLibrary(directory: directory, builtInURL: nil)
        await reopened.load()
        #expect(reopened.documents == before)
    }

    @Test @MainActor func cancelledBackgroundConfirmationDoesNotCreateFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = WordListLibrary(directory: directory, builtInURL: nil)
        let preview = try library.prepare(data(fixture()))
        let task = Task { @MainActor in try await library.confirmInBackground(preview, policy: .update) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled confirmation must not write")
        } catch is CancellationError { }
        #expect(library.documents.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
