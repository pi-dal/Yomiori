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
            #expect(error.localizedDescription.contains(path))
        }
    }

    @Test func optionalDefaultsAndDescriptiveRoundTrip() throws {
        let document = try WordListDocument.decodeValidated(data(fixture()))
        let word = try #require(document.entries.first)
        #expect(word.w == "one")
        #expect(word.uk.isEmpty && word.us.isEmpty && word.col.isEmpty && word.tip.isEmpty)
        #expect(word.pictureURL == nil && word.pronunciationURL == nil && word.exampleAudioURL == nil)
        #expect(word.senses.first?.en == "A definition")
        let encoded = try JSONEncoder().encode(document)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let entries = try #require(object["entries"] as? [[String: Any]])
        #expect(entries[0]["term"] as? String == "one")
        #expect(entries[0]["w"] == nil)
        #expect(try WordListDocument.decodeValidated(encoded) == document)
    }

    @Test func invalidVersionsAndBooleanTypes() throws {
        for version in [true, "1", 2, 1.5] as [Any] {
            var raw = fixture(); raw["version"] = version
            try rejects(raw, at: "$.version")
        }
        var raw = fixture()
        var source = try #require(raw["source"] as? [String: Any])
        source["modified"] = 1; raw["source"] = source
        try rejects(raw, at: "$.source.modified")
    }

    @Test func jsonSchemaInteroperabilityEdges() throws {
        var raw = fixture(); raw["version"] = 1.0
        #expect(try WordListDocument.decodeValidated(data(raw)).version == 1)
        raw = fixture(entries: [])
        try rejects(raw, at: "$.entries")
        raw = fixture(); raw["id"] = "valid\n"
        try rejects(raw, at: "$.id")
        raw = fixture(); raw["translationLanguage"] = "en\n"
        try rejects(raw, at: "$.translationLanguage")
        raw = fixture(); raw["title"] = " \n\t"
        try rejects(raw, at: "$.title")
        var word = entry("one", term: String(repeating: "e\u{301}", count: 151))
        try rejects(fixture(entries: [word]), at: "$.entries[0].term")
        word = entry("one"); word["media"] = ["imageURL": "https://example.com/path\\invalid"]
        try rejects(fixture(entries: [word]), at: "$.entries[0].media.imageURL")
        let valid = String(decoding: try data(fixture()), as: UTF8.self)
        let duplicated = "{\"title\":\"discarded\"," + valid.dropFirst()
        #expect(throws: WordListValidationError.self) {
            try WordListDocument.decodeValidated(Data(duplicated.utf8))
        }
        let escapedDuplicate = "{\"ti\\u0074le\":\"discarded\"," + valid.dropFirst()
        #expect(throws: WordListValidationError.self) {
            try WordListDocument.decodeValidated(Data(escapedDuplicate.utf8))
        }
    }

    @Test func recursiveUnknownKeysAndExactTypes() throws {
        var word = entry("one")
        word["senses"] = [["partOfSpeech": "n", "definition": "Meaning", "translation": "", "extra": true]]
        try rejects(fixture(entries: [word]), at: "$.entries[0].senses[0].extra")
        word = entry("one"); word["collocations"] = [1]
        try rejects(fixture(entries: [word]), at: "$.entries[0].collocations[0]")
        word = entry("one"); word["note"] = NSNull()
        try rejects(fixture(entries: [word]), at: "$.entries[0].note")
        word = entry("one"); word["pronunciations"] = ["us": true]
        try rejects(fixture(entries: [word]), at: "$.entries[0].pronunciations.us")
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

    @Test func requiredFieldsLimitsAndLanguages() throws {
        var raw = fixture(); raw["translationLanguage"] = "zh_Hans"
        try rejects(raw, at: "$.translationLanguage")
        raw = fixture(); raw["language"] = "fr"
        try rejects(raw, at: "$.language")
        raw = fixture(); raw["title"] = String(repeating: "a", count: 121)
        try rejects(raw, at: "$.title")
        try rejects(fixture(entries: [entry("../one")]), at: "$.entries[0].id")
        var word = entry("one"); word["term"] = String(repeating: "a", count: 301)
        try rejects(fixture(entries: [word]), at: "$.entries[0].term")
        word = entry("one"); word["senses"] = []
        try rejects(fixture(entries: [word]), at: "$.entries[0].senses")
        word = entry("one"); word.removeValue(forKey: "examples")
        try rejects(fixture(entries: [word]), at: "$.entries[0].examples")
    }

    @Test @MainActor func previewDoesNotWriteAndReservedListIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = WordListLibrary(directory: directory, builtInURL: nil)
        let preview = try library.prepare(data(fixture()))
        let backgroundDecoded = try WordListDocument.decodeValidated(data(fixture()))
        let lightweight = try library.previewValidated(backgroundDecoded)
        #expect(lightweight.document == preview.document && lightweight.newCount == preview.newCount)
        #expect(preview.newCount == 1 && preview.duplicateCount == 0)
        #expect(preview.existing == nil && library.documents.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        var reserved = fixture(); reserved["id"] = "ielts"
        #expect(throws: WordListValidationError.self) { try library.prepare(data(reserved)) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test @MainActor func mergePoliciesKeepMissingEntriesAndStableIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = WordListLibrary(directory: directory, builtInURL: nil)
        let initial = try library.prepare(data(fixture(entries: [entry("one"), entry("keep"), entry("same")])))
        try library.confirm(initial, policy: .skip)
        let before = try #require(library.documents.first)
        let changed = try library.prepare(data(fixture(entries: [entry("one", term: "Changed"), entry("same"), entry("new")])))
        #expect(changed.newCount == 1 && changed.changedCount == 1 && changed.identicalCount == 1)
        #expect(changed.changedIDs == ["one"])
        let skipped = try library.confirm(changed, policy: .skip)
        #expect(skipped.newCount == 1 && skipped.updatedCount == 0 && skipped.skippedCount == 2)
        #expect(skipped.document.entries.map(\.id) == ["one", "keep", "same", "new"])
        #expect(skipped.document.entries[0] == before.entries[0])
        let updated = try library.confirm(changed, policy: .update)
        #expect(updated.newCount == 0 && updated.updatedCount == 1)
        #expect(updated.document.id == before.id)
        #expect(updated.document.entries[0].id == before.entries[0].id)
        #expect(updated.document.entries[0].term == "Changed")
        #expect(updated.document.entries[1] == before.entries[1])
        let identical = try library.prepare(data(fixture(entries: [entry("one", term: "Changed"), entry("same"), entry("new")])))
        #expect(identical.actionCount(for: .update) == 0)
        #expect(identical.actionCount(for: .skip) == 0)
        let reloaded = WordListLibrary(directory: directory, builtInURL: nil)
        await reloaded.load()
        #expect(reloaded.error == nil)
        #expect(reloaded.documents == library.documents)
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
        let savedID = saved.id
        let japaneseID = japanese.id
        let createdAt = saved.createdAt
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
        #expect(saved.id == savedID && saved.createdAt == createdAt)
        #expect(saved.wordListID == original.id && saved.wordListEntryID == "one" && saved.languageCode == "en")
        #expect(saved.word == "one" && saved.sentence == "Original example")
        #expect(saved.definitionEnglish == "A definition" && saved.reading == "original reading")
        #expect(saved.meaning.isEmpty && saved.translation == "元の例文")
        #expect(saved.audioRemoteURL == "https://example.com/original.mp3")
        #expect(saved.interval == 21 && saved.ease == 2.7 && saved.reps == 12 && saved.lapses == 3)
        #expect(saved.due == Date(timeIntervalSince1970: 1_900_000_000))
        #expect(japanese.id == japaneseID && japanese.languageCode == "ja" && japanese.wordListID.isEmpty)
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
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(FileManager.default.fileExists(atPath: builtinURL.path))
        try library.clearImported()
        let reloaded = WordListLibrary(directory: directory, builtInURL: builtinURL)
        await reloaded.load()
        #expect(reloaded.documents == library.documents)
    }

    @Test @MainActor func backgroundConfirmationMergesAndRejectsInvalidOrStalePreviewsWithoutWrites() async throws {
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
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let bytes = try Data(contentsOf: file)
        do {
            _ = try await library.confirmInBackground(preview, policy: .update)
            Issue.record("A stale preview must require refresh")
        } catch let error as WordListValidationError { #expect(error.reason.contains("Refresh")) }
        #expect(library.documents == before)
        #expect(try Data(contentsOf: file) == bytes)
        let validPreview = try library.prepare(data(fixture()))
        var invalid = validPreview.document
        invalid.entries.append(invalid.entries[0])
        let invalidPreview = WordListImportPreview(document: invalid, existing: validPreview.existing,
                                                   newCount: 0, changedIDs: [], identicalCount: 0)
        do {
            _ = try await library.confirmInBackground(invalidPreview, policy: .update)
            Issue.record("Invalid async confirmation must fail")
        } catch let error as WordListValidationError { #expect(error.path == "$.entries[1].id") }
        #expect(library.documents == before)
        #expect(try Data(contentsOf: file) == bytes)
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

    @Test @MainActor func rejectedConfirmLeavesDiskAndCatalogueUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = WordListLibrary(directory: directory, builtInURL: nil)
        try library.confirm(library.prepare(data(fixture())), policy: .skip)
        let before = library.documents
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let bytes = try Data(contentsOf: file)
        var invalid = try #require(before.first)
        invalid.entries.append(invalid.entries[0])
        #expect(throws: WordListValidationError.self) { try library.confirm(invalid, policy: .update) }
        #expect(library.documents == before)
        #expect(try Data(contentsOf: file) == bytes)
    }
}
