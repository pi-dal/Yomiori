import Foundation
import CoreFoundation
import Observation

struct WordListSource: Codable, Sendable, Equatable {
    var name: String
    var url: URL
    var license: String
    var licenseURL: URL
    var attribution: String
    var modified: Bool
    var contentType: String
}

struct AtlasWord: Codable, Identifiable, Sendable, Equatable {
    struct Sense: Codable, Sendable, Equatable {
        var partOfSpeech: String
        var definition: String
        var translation: String
        var pos: String { partOfSpeech }
        var en: String { definition }
        var zh: String { translation }
    }
    struct Example: Codable, Sendable, Equatable {
        var text: String
        var translation: String
        var en: String { text }
        var zh: String { translation }
    }
    struct Pronunciations: Codable, Sendable, Equatable {
        var uk: String = ""
        var us: String = ""
        init(uk: String = "", us: String = "") { self.uk = uk; self.us = us }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            uk = try c.decodeIfPresent(String.self, forKey: .uk) ?? ""
            us = try c.decodeIfPresent(String.self, forKey: .us) ?? ""
        }
    }
    struct Media: Codable, Sendable, Equatable {
        var pronunciationURL: URL?
        var exampleAudioURL: URL?
        var imageURL: URL?
    }

    var id: String
    var term: String
    var senses: [Sense]
    var examples: [Example]
    var level: String
    var topic: String
    var pronunciations: Pronunciations = .init()
    var collocations: [String] = []
    var family: [String] = []
    var synonyms: [String] = []
    var antonyms: [String] = []
    var tip: String = ""
    var note: String? = nil
    var media: Media? = nil

    var w: String { term }
    var uk: String { pronunciations.uk }
    var us: String { pronunciations.us }
    var reading: String { us.isEmpty ? uk : us }
    var meaning: String { senses.map(\.translation).joined(separator: "; ") }
    var ex: [Example] { examples }
    var col: [String] { collocations }
    var fam: [String] { family }
    var syn: [String] { synonyms }
    var ant: [String] { antonyms }
    var cefr: String { level }
    var pictureURL: URL? { media?.imageURL }
    var pronunciationURL: URL? { media?.pronunciationURL }
    var exampleAudioURL: URL? { media?.exampleAudioURL }

    init(id: String, term: String, senses: [Sense], examples: [Example], level: String, topic: String) {
        self.id = id; self.term = term; self.senses = senses
        self.examples = examples; self.level = level; self.topic = topic
    }

    enum CodingKeys: String, CodingKey {
        case id, term, senses, examples, level, topic, pronunciations, collocations, family, synonyms, antonyms, tip, note, media
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        term = try c.decode(String.self, forKey: .term)
        senses = try c.decode([Sense].self, forKey: .senses)
        examples = try c.decode([Example].self, forKey: .examples)
        level = try c.decode(String.self, forKey: .level)
        topic = try c.decode(String.self, forKey: .topic)
        pronunciations = try c.decodeIfPresent(Pronunciations.self, forKey: .pronunciations) ?? .init()
        collocations = try c.decodeIfPresent([String].self, forKey: .collocations) ?? []
        family = try c.decodeIfPresent([String].self, forKey: .family) ?? []
        synonyms = try c.decodeIfPresent([String].self, forKey: .synonyms) ?? []
        antonyms = try c.decodeIfPresent([String].self, forKey: .antonyms) ?? []
        tip = try c.decodeIfPresent(String.self, forKey: .tip) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note)
        media = try c.decodeIfPresent(Media.self, forKey: .media)
    }
}

struct WordListDocument: Codable, Identifiable, Sendable, Equatable {
    var format: String = "kotoba.wordlist"
    var version: Int = 1
    var id: String
    var title: String
    var language: String
    var translationLanguage: String
    var source: WordListSource
    var entries: [AtlasWord]

    static func decodeValidated(_ data: Data) throws -> WordListDocument {
        guard data.count <= 20 * 1024 * 1024 else {
            throw WordListValidationError(path: "$", reason: "File exceeds 20 MiB.")
        }
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw WordListValidationError(path: "$", reason: "Invalid JSON.") }
        try WordListValidator.rejectDuplicateKeys(data)
        try WordListValidator.document(raw)
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch { throw WordListValidationError(path: "$", reason: "The word list could not be decoded: \(error.localizedDescription)") }
    }
}

struct WordListValidationError: LocalizedError, Equatable {
    let path: String
    let reason: String
    var errorDescription: String? { "\(path)\n\(localizedReason)" }
    var diagnosticDescription: String { "\(path): \(reason)" }

    var localizedReason: String {
        let messages = [
            "File exceeds 20 MiB.": "File exceeds 20 MiB.",
            "Invalid JSON.": "Invalid JSON.",
            "Expected an object.": "Expected an object.",
            "Unknown key.": "Unknown field.",
            "Required key is missing.": "Missing required field.",
            "Expected a string.": "Expected text.",
            "Must not be empty.": "Must not be empty.",
            "Must contain non-whitespace text.": "Enter text other than spaces.",
            "Use 1–80 ASCII letters, digits, dots, underscores or hyphens, starting with a letter or digit.": "Use 1–80 ASCII letters, digits, dots, underscores or hyphens, starting with a letter or digit.",
            "Expected an absolute HTTPS URL without credentials.": "Use an absolute HTTPS link without credentials.",
            "Expected an array.": "Expected a list.",
            "Expected kotoba.wordlist.": "Expected kotoba.wordlist.",
            "Expected integer version 1.": "Use format version 1.",
            "Supported languages are en and ja.": "Use en or ja for the learning language.",
            "Expected a BCP 47 language tag.": "Use a BCP 47 language tag.",
            "Expected a boolean.": "Expected true or false.",
            "Unsupported content type.": "Unsupported content type.",
            "At least one entry is required.": "No entries found.",
            "Must contain at most 20000 entries.": "Use at most 20,000 entries.",
            "Expected an empty level or A1, A2, B1, B2, C1, C2.": "Use an empty level or A1, A2, B1, B2, C1, C2.",
            "At least one sense is required.": "Add at least one meaning.",
            "The bundled list must use ID ielts.": "The bundled list must use ID ielts.",
            "Reserved or duplicate list ID.": "Reserved or duplicate word list ID.",
            "ielts is reserved for the built-in word list.": "ielts is reserved for the built-in word list.",
            "An existing list's language cannot change.": "An existing word list's learning language cannot change.",
            "An existing list's translation language cannot change.": "An existing word list's translation language cannot change."
        ]
        if let key = messages[reason] { return L10n.string(key) }
        if reason == "The word list changed. Refresh the import preview and try again." { return L10n.string("import.refresh") }
        if reason.hasPrefix("Must be at most "), let count = Int64(reason.dropFirst("Must be at most ".count).prefix(while: { $0.isNumber })) {
            return L10n.format("Use at most %lld characters.", count)
        }
        if reason.hasPrefix("Duplicate JSON key: ") {
            return L10n.format("Duplicate JSON field: %@", String(reason.dropFirst("Duplicate JSON key: ".count).dropLast()))
        }
        if reason.hasPrefix("Duplicate entry ID ") {
            return L10n.format("Duplicate entry ID: %@", String(reason.dropFirst("Duplicate entry ID ".count).dropLast()))
        }
        return L10n.string("Couldn't read this file.")
    }
}

private enum WordListValidator {
    /// JSONSerialization keeps only the last repeated key; inspect the original tokens too.
    /// Structural validity has already been checked by JSONSerialization.
    static func rejectDuplicateKeys(_ data: Data) throws {
        struct Frame {
            var isObject: Bool
            var expectsKey = true
            var keys = Set<String>()
        }
        // Normalize UTF-16/32 JSON supported by Foundation before scanning JSON tokens.
        let bytes: [UInt8]
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            bytes = Array((String(data: data, encoding: .utf32) ?? "").utf8)
        } else if data.starts(with: [0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE]) {
            bytes = Array((String(data: data, encoding: .utf16) ?? "").utf8)
        } else if data.prefix(4).contains(0) {
            let encoding: String.Encoding = (data.prefix(4).filter { $0 == 0 }.count >= 2) ? .utf32 : .utf16
            bytes = Array((String(data: data, encoding: encoding) ?? "").utf8)
        } else { bytes = Array(data) }
        var frames: [Frame] = []
        var i = 0
        while i < bytes.count {
            switch bytes[i] {
            case 123: frames.append(Frame(isObject: true))
            case 91: frames.append(Frame(isObject: false))
            case 125, 93: if !frames.isEmpty { frames.removeLast() }
            case 44:
                if let index = frames.indices.last, frames[index].isObject { frames[index].expectsKey = true }
            case 58:
                if let index = frames.indices.last { frames[index].expectsKey = false }
            case 34:
                let start = i
                var escaped = false
                i += 1
                while i < bytes.count, bytes[i] != 34 {
                    if bytes[i] == 92 { escaped = true; i += 1 }
                    i += 1
                }
                if let index = frames.indices.last, frames[index].isObject, frames[index].expectsKey {
                    let key: String
                    if escaped {
                        key = (try JSONSerialization.jsonObject(with: Data(bytes[start...i]), options: .fragmentsAllowed)) as! String
                    } else { key = String(decoding: bytes[(start + 1)..<i], as: UTF8.self) }
                    if !frames[index].keys.insert(key).inserted { try fail("$", "Duplicate JSON key: \(key).") }
                    frames[index].expectsKey = false
                }
            default: break
            }
            i += 1
        }
    }

    static func fail(_ path: String, _ reason: String) throws -> Never {
        throw WordListValidationError(path: path, reason: reason)
    }
    static func object(_ raw: Any, _ path: String, required: Set<String>, optional: Set<String> = []) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else { try fail(path, "Expected an object.") }
        if let key = Set(value.keys).subtracting(required.union(optional)).sorted().first {
            try fail("\(path).\(key)", "Unknown key.")
        }
        if let key = required.subtracting(value.keys).sorted().first { try fail("\(path).\(key)", "Required key is missing.") }
        return value
    }
    @discardableResult static func text(_ raw: Any?, _ path: String, nonempty: Bool = false, nonWhitespace: Bool = false, max: Int = 10000) throws -> String {
        guard let text = raw as? String else { try fail(path, "Expected a string.") }
        if nonempty && text.isEmpty { try fail(path, "Must not be empty.") }
        if nonWhitespace && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try fail(path, "Must contain non-whitespace text.") }
        if text.unicodeScalars.count > max { try fail(path, "Must be at most \(max) characters.") }
        return text
    }
    static func id(_ raw: Any?, _ path: String) throws {
        let value = try text(raw, path, nonempty: true, max: 80)
        if value.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$", options: .regularExpression) != value.startIndex..<value.endIndex {
            try fail(path, "Use 1–80 ASCII letters, digits, dots, underscores or hyphens, starting with a letter or digit.")
        }
    }
    static func url(_ raw: Any?, _ path: String) throws {
        let value = try text(raw, path, nonempty: true)
        let pattern = #"^https://(?:[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?|\[[0-9A-Fa-f:]+\])(?::[0-9]{1,5})?(?:[/?#][^\s\\\x00-\x20\x7f]*)?$(?![\s\S])"#
        guard value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.url != nil else {
            try fail(path, "Expected an absolute HTTPS URL without credentials.")
        }
    }
    static func array(_ raw: Any?, _ path: String) throws -> [Any] {
        guard let values = raw as? [Any] else { try fail(path, "Expected an array.") }
        return values
    }
    static func document(_ raw: Any) throws {
        let d = try object(raw, "$", required: ["format", "version", "id", "title", "language", "translationLanguage", "source", "entries"])
        if try text(d["format"], "$.format") != "kotoba.wordlist" { try fail("$.format", "Expected kotoba.wordlist.") }
        guard let version = d["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
              version.doubleValue == 1 else {
            try fail("$.version", "Expected integer version 1.")
        }
        try id(d["id"], "$.id")
        try text(d["title"], "$.title", nonempty: true, nonWhitespace: true, max: 120)
        let language = try text(d["language"], "$.language")
        if !["en", "ja"].contains(language) { try fail("$.language", "Supported languages are en and ja.") }
        let translation = try text(d["translationLanguage"], "$.translationLanguage", nonempty: true)
        if translation.range(of: "^[a-zA-Z]{2,8}(-[a-zA-Z0-9]{1,8})*$", options: .regularExpression) != translation.startIndex..<translation.endIndex {
            try fail("$.translationLanguage", "Expected a BCP 47 language tag.")
        }
        let source = try object(d["source"]!, "$.source", required: ["name", "url", "license", "licenseURL", "attribution", "modified", "contentType"])
        for key in ["name", "license", "attribution"] { try text(source[key], "$.source.\(key)", nonempty: true, nonWhitespace: true) }
        for key in ["url", "licenseURL"] { try url(source[key], "$.source.\(key)") }
        guard let modified = source["modified"] as? NSNumber, CFGetTypeID(modified) == CFBooleanGetTypeID() else {
            try fail("$.source.modified", "Expected a boolean.")
        }
        let type = try text(source["contentType"], "$.source.contentType")
        if !["ai-generated", "dictionary", "user-authored"].contains(type) { try fail("$.source.contentType", "Unsupported content type.") }
        let entries = try array(d["entries"], "$.entries")
        if entries.isEmpty { try fail("$.entries", "At least one entry is required.") }
        if entries.count > 20000 { try fail("$.entries", "Must contain at most 20000 entries.") }
        var ids = Set<String>()
        for (index, raw) in entries.enumerated() {
            let p = "$.entries[\(index)]"
            let e = try object(raw, p, required: ["id", "term", "senses", "examples", "level", "topic"], optional: ["pronunciations", "collocations", "family", "synonyms", "antonyms", "tip", "note", "media"])
            try id(e["id"], "\(p).id")
            let entryID = try text(e["id"], "\(p).id")
            if !ids.insert(entryID).inserted { try fail("\(p).id", "Duplicate entry ID \(entryID).") }
            try text(e["term"], "\(p).term", nonempty: true, max: 300)
            try text(e["topic"], "\(p).topic", nonempty: true, max: 100)
            let level = try text(e["level"], "\(p).level")
            if !["", "A1", "A2", "B1", "B2", "C1", "C2"].contains(level) { try fail("\(p).level", "Expected an empty level or A1, A2, B1, B2, C1, C2.") }
            let senses = try array(e["senses"], "\(p).senses")
            if senses.isEmpty { try fail("\(p).senses", "At least one sense is required.") }
            for (i, raw) in senses.enumerated() {
                let path = "\(p).senses[\(i)]"
                let s = try object(raw, path, required: ["partOfSpeech", "definition", "translation"])
                for key in ["partOfSpeech", "definition", "translation"] { try text(s[key], "\(path).\(key)", nonempty: key == "definition") }
            }
            for (i, raw) in try array(e["examples"], "\(p).examples").enumerated() {
                let path = "\(p).examples[\(i)]"
                let ex = try object(raw, path, required: ["text", "translation"])
                try text(ex["text"], "\(path).text", nonempty: true)
                try text(ex["translation"], "\(path).translation")
            }
            for key in ["collocations", "family", "synonyms", "antonyms"] where e[key] != nil {
                for (i, raw) in try array(e[key], "\(p).\(key)").enumerated() { try text(raw, "\(p).\(key)[\(i)]") }
            }
            for key in ["tip", "note"] where e[key] != nil { try text(e[key], "\(p).\(key)") }
            if let raw = e["pronunciations"] {
                let pronunciation = try object(raw, "\(p).pronunciations", required: [], optional: ["uk", "us"])
                for (key, value) in pronunciation { try text(value, "\(p).pronunciations.\(key)") }
            }
            if let raw = e["media"] {
                let media = try object(raw, "\(p).media", required: [], optional: ["pronunciationURL", "exampleAudioURL", "imageURL"])
                for (key, value) in media { try url(value, "\(p).media.\(key)") }
            }
        }
    }
}

enum WordListImportPolicy: Sendable { case skip, update }

struct WordListImportPreview: Sendable {
    let document: WordListDocument
    let existing: WordListDocument?
    let newCount: Int
    let changedIDs: Set<String>
    let identicalCount: Int
    var changedCount: Int { changedIDs.count }
    var duplicateCount: Int { changedCount + identicalCount }
    var changedEntries: [AtlasWord] { document.entries.filter { changedIDs.contains($0.id) } }
    func actionCount(for policy: WordListImportPolicy) -> Int {
        newCount + (policy == .update ? changedCount : 0)
    }
}
typealias ImportPreview = WordListImportPreview

struct WordListImportResult: Sendable {
    let document: WordListDocument
    let newCount: Int
    let updatedCount: Int
    let skippedCount: Int
    var insertedCount: Int { newCount }
}

/// Imports update the catalogue only. Cards are independent snapshots with their own schedules.
@MainActor @Observable
final class WordListLibrary {
    static let shared = WordListLibrary()
    private(set) var documents: [WordListDocument] = []
    private(set) var loading = false
    private(set) var error: String?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let builtInURL: URL?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var clearGeneration = 0
    @ObservationIgnored private var revision = 0

    init(directory: URL? = nil, builtInURL: URL? = Bundle.main.url(forResource: "word-atlas", withExtension: "json")) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WordLists", isDirectory: true)
        self.builtInURL = builtInURL
    }

    func load() async {
        guard !loaded, !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        let directory = directory
        let builtInURL = builtInURL
        let generation = clearGeneration
        let result = await Task.detached(priority: .userInitiated) { () -> ([WordListDocument], [String]) in
            var documents: [WordListDocument] = []
            var errors: [String] = []
            if let builtInURL {
                do {
                    let document = try WordListDocument.decodeValidated(Data(contentsOf: builtInURL))
                    guard document.id == "ielts" else { throw WordListValidationError(path: "$.id", reason: "The bundled list must use ID ielts.") }
                    documents.append(document)
                } catch { errors.append(L10n.string("Couldn't open the offline word list.") + "\n" + error.localizedDescription) }
            }
            if FileManager.default.fileExists(atPath: directory.path) {
                do {
                    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                        .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                    for file in files {
                        do {
                            let document = try WordListDocument.decodeValidated(Data(contentsOf: file))
                            guard document.id != "ielts", !documents.contains(where: { $0.id == document.id }) else {
                                throw WordListValidationError(path: "$.id", reason: "Reserved or duplicate list ID.")
                            }
                            documents.append(document)
                        } catch { errors.append("\(file.lastPathComponent): \(error.localizedDescription)") }
                    }
                } catch { errors.append(L10n.string("Couldn't open imported word lists.") + "\n" + error.localizedDescription) }
            }
            return (documents, errors)
        }.value
        // A confirmation can occur while disk loading is in flight. Keep its newer catalogue.
        let currentIDs = Set(documents.map(\.id))
        documents = result.0.filter {
            !currentIDs.contains($0.id) && ($0.id == "ielts" || generation == clearGeneration)
        } + documents
        error = result.1.isEmpty ? nil : result.1.joined(separator: "\n")
        loaded = result.1.isEmpty
        revision += 1
    }

    func prepare(_ data: Data) throws -> WordListImportPreview {
        try makePreview(WordListDocument.decodeValidated(data))
    }

    /// Use after decodeValidated on a background task to compute preview counts without JSON work.
    /// Confirmation always performs full validation again before writing.
    func previewValidated(_ document: WordListDocument) throws -> WordListImportPreview {
        try makePreview(document)
    }

    func counts(_ document: WordListDocument) throws -> WordListImportPreview {
        let validated = try WordListDocument.decodeValidated(JSONEncoder().encode(document))
        return try makePreview(validated)
    }

    private func makePreview(_ document: WordListDocument) throws -> WordListImportPreview {
        guard document.id != "ielts" else {
            throw WordListValidationError(path: "$.id", reason: "ielts is reserved for the built-in word list.")
        }
        // Read the persisted copy too, so preparing before load cannot bypass identity checks.
        var existing = documents.first { $0.id == document.id }
        let file = fileURL(for: document.id)
        if existing == nil, FileManager.default.fileExists(atPath: file.path) {
            existing = try WordListDocument.decodeValidated(Data(contentsOf: file))
        }
        return try Self.preview(document, existing: existing)
    }

    nonisolated private static func preview(_ document: WordListDocument, existing: WordListDocument?) throws -> WordListImportPreview {
        guard document.id != "ielts" else {
            throw WordListValidationError(path: "$.id", reason: "ielts is reserved for the built-in word list.")
        }
        if let existing {
            guard document.language == existing.language else {
                throw WordListValidationError(path: "$.language", reason: "An existing list's language cannot change.")
            }
            guard document.translationLanguage == existing.translationLanguage else {
                throw WordListValidationError(path: "$.translationLanguage", reason: "An existing list's translation language cannot change.")
            }
        }
        let old = Dictionary(uniqueKeysWithValues: (existing?.entries ?? []).map { ($0.id, $0) })
        var newCount = 0
        var identicalCount = 0
        var changedIDs = Set<String>()
        for entry in document.entries {
            if let previous = old[entry.id] {
                if previous == entry { identicalCount += 1 } else { changedIDs.insert(entry.id) }
            } else { newCount += 1 }
        }
        return WordListImportPreview(document: document, existing: existing, newCount: newCount, changedIDs: changedIDs, identicalCount: identicalCount)
    }

    @discardableResult
    func confirm(_ document: WordListDocument, policy: WordListImportPolicy) throws -> WordListImportResult {
        let existing = try makePreview(document).existing
        let prepared = try Self.prepareCommit(document, existing: existing, policy: policy)
        try install(prepared.result, data: prepared.data)
        return prepared.result
    }

    @discardableResult
    func confirm(_ preview: WordListImportPreview, policy: WordListImportPolicy) throws -> WordListImportResult {
        try confirm(preview.document, policy: policy)
    }

    /// Performs validation, merging and encoding off the main actor. A stale catalogue
    /// requires a fresh preview; there is no suspension between the final check and write.
    @discardableResult
    func confirmInBackground(_ preview: WordListImportPreview, policy: WordListImportPolicy) async throws -> WordListImportResult {
        let snapshotRevision = revision
        let snapshotGeneration = clearGeneration
        let document = preview.document
        let existing = try makePreview(document).existing
        guard existing == preview.existing else {
            throw WordListValidationError(path: "$", reason: "The word list changed. Refresh the import preview and try again.")
        }
        let prepared = try await Task.detached(priority: .userInitiated) {
            try Self.prepareCommit(document, existing: existing, policy: policy)
        }.value
        try Task.checkCancellation()
        guard revision == snapshotRevision, clearGeneration == snapshotGeneration,
              try makePreview(document).existing == existing else {
            throw WordListValidationError(path: "$", reason: "The word list changed. Refresh the import preview and try again.")
        }
        try install(prepared.result, data: prepared.data)
        return prepared.result
    }

    nonisolated private static func prepareCommit(_ document: WordListDocument, existing: WordListDocument?, policy: WordListImportPolicy) throws -> (result: WordListImportResult, data: Data) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let validated = try WordListDocument.decodeValidated(encoder.encode(document))
        let preview = try Self.preview(validated, existing: existing)
        var merged = validated
        var entries = existing?.entries ?? []
        let positions = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
        for entry in validated.entries {
            if let position = positions[entry.id] {
                if policy == .update, preview.changedIDs.contains(entry.id) { entries[position] = entry }
            } else { entries.append(entry) }
        }
        merged.entries = entries
        let data = try encoder.encode(merged)
        // Merging two valid documents may exceed the file or entry limits.
        _ = try WordListDocument.decodeValidated(data)
        let updated = policy == .update ? preview.changedCount : 0
        let result = WordListImportResult(document: merged, newCount: preview.newCount, updatedCount: updated,
                                          skippedCount: preview.duplicateCount - updated)
        return (result, data)
    }

    private func install(_ result: WordListImportResult, data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: result.document.id), options: .atomic)
        if let index = documents.firstIndex(where: { $0.id == result.document.id }) { documents[index] = result.document }
        else { documents.append(result.document) }
        revision += 1
    }

    /// Used by Settings when clearing app data. The bundled catalogue is retained.
    func clearImported() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        clearGeneration += 1
        revision += 1
        documents.removeAll { $0.id != "ielts" }
    }

    private func fileURL(for id: String) -> URL {
        // IDs are case sensitive, including on filesystems that ignore filename case.
        let encoded = id.utf8.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(encoded).appendingPathExtension("json")
    }
}
