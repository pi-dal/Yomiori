import Foundation
import SwiftData

struct SubLine: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
    var translation: String?
    var translationSource: String?
    var translationTarget: String?
    var note: String?
    var hl: Int?
}

@Model final class Material {
    var languageCode: String = "ja"
    var id = UUID()
    var title: String
    var mediaFile: String?
    var linesData: Data = Data()
    var createdAt = Date()
    var lastLine = 0
    var needsTranscription = false
    var duration: Double = 0
    var sourceKind = "file"   // file | link | podcast
    var artworkURL: String?
    var isAudio = false
    init(title: String, mediaFile: String? = nil) { self.title = title; self.mediaFile = mediaFile }
    @Transient private var decodedLines: [SubLine] = []
    @Transient private var decodedData: Data?
    @Transient var contentError: String?
    var lines: [SubLine] {
        get {
            if decodedData == linesData { return decodedLines }
            do {
                decodedLines = try readLines()
                decodedData = linesData
                contentError = nil
                return decodedLines
            } catch {
                contentError = L10n.string("Saved content is damaged. Export or restore the original file before editing.")
                return []
            }
        }
        set {
            do { try writeLines(newValue) }
            catch { contentError = error.localizedDescription }
        }
    }
    func readLines() throws -> [SubLine] {
        linesData.isEmpty ? [] : try JSONDecoder().decode([SubLine].self, from: linesData)
    }
    func writeLines(_ lines: [SubLine]) throws {
        let encoded = try JSONEncoder().encode(lines)
        linesData = encoded
        decodedData = encoded
        decodedLines = lines
        contentError = nil
    }
}

/// One item in the Dictionary: a saved word or line, a highlight, or a note.
@Model final class DictEntry {
    var languageCode: String = "ja"
    var id = UUID()
    var term: String
    var reading: String = ""
    var meaning: String = ""
    var context: String = ""
    var kind: String          // word | line | highlight | note
    var colorIdx: Int = -1
    var note: String = ""
    var sourceKind: String    // subtitle | pdf | coach
    var sourceID: String = ""
    var sourceName: String = ""
    var sourcePos: Double = 0 // seconds for subtitle, page index for pdf
    var rectsData: Data = Data()
    var createdAt = Date()
    init(term: String, kind: String, sourceKind: String) { self.term = term; self.kind = kind; self.sourceKind = sourceKind }
    @Transient var contentError: String?
    var rects: [[Double]] {
        get {
            do { return rectsData.isEmpty ? [] : try JSONDecoder().decode([[Double]].self, from: rectsData) }
            catch { contentError = error.localizedDescription; return [] }
        }
        set {
            do { rectsData = try JSONEncoder().encode(newValue); contentError = nil }
            catch { contentError = error.localizedDescription }
        }
    }
}

@Model final class PDFDoc {
    var id = UUID()
    var languageCode: String = "ja"
    var title: String
    var fileName: String
    var createdAt = Date()
    var pageCount = 0
    var lastPage = 0
    var translationsData: Data = Data()
    init(title: String, fileName: String) { self.title = title; self.fileName = fileName }
    func readTranslations() throws -> [String: [String]] {
        translationsData.isEmpty ? [:] : try JSONDecoder().decode([String: [String]].self, from: translationsData)
    }
    func writeTranslations(_ values: [String: [String]]) throws {
        translationsData = try JSONEncoder().encode(values)
    }
}

@Model final class ChatMsg {
    var languageCode: String = "ja"
    var id = UUID()
    var role: String
    var content: String
    var createdAt = Date()
    var correctionsData: Data = Data()
    init(role: String, content: String) { self.role = role; self.content = content }
    @Transient var contentError: String?
    var corrections: [Correction] {
        get {
            do { return correctionsData.isEmpty ? [] : try JSONDecoder().decode([Correction].self, from: correctionsData) }
            catch { contentError = error.localizedDescription; return [] }
        }
        set {
            do { correctionsData = try JSONEncoder().encode(newValue); contentError = nil }
            catch { contentError = error.localizedDescription }
        }
    }
}

struct Correction: Codable, Hashable, Sendable {
    var category: String
    var pattern: String
    var wrong: String
    var right: String
    var reason: String
}

@Model final class Mistake {
    var languageCode: String = "ja"
    var category: String
    var pattern: String
    var wrong: String
    var right: String
    var reason: String
    var createdAt = Date()
    init(_ c: Correction) {
        category = c.category; pattern = c.pattern; wrong = c.wrong; right = c.right; reason = c.reason
    }
}
