import Foundation
import SwiftData

struct SubLine: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
    var translation: String?
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
    var lines: [SubLine] {
        get { (try? JSONDecoder().decode([SubLine].self, from: linesData)) ?? [] }
        set { linesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
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
    var rects: [[Double]] {
        get { (try? JSONDecoder().decode([[Double]].self, from: rectsData)) ?? [] }
        set { rectsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model final class PDFDoc {
    var id = UUID()
    var title: String
    var fileName: String
    var createdAt = Date()
    var pageCount = 0
    var lastPage = 0
    var translationsData: Data = Data()
    init(title: String, fileName: String) { self.title = title; self.fileName = fileName }
    var translations: [String: [String]] {
        get { (try? JSONDecoder().decode([String: [String]].self, from: translationsData)) ?? [:] }
        set { translationsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
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
    var corrections: [Correction] {
        get { (try? JSONDecoder().decode([Correction].self, from: correctionsData)) ?? [] }
        set { correctionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

struct Correction: Codable, Hashable {
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

enum Files {
    static var dir: URL {
        let d = URL.documentsDirectory.appending(path: "Imports")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ name: String) -> URL { dir.appending(path: name) }
    /// Copies a picked file into the app's storage and returns its stored name.
    static func importFile(_ src: URL) throws -> String {
        let ok = src.startAccessingSecurityScopedResource()
        defer { if ok { src.stopAccessingSecurityScopedResource() } }
        let name = UUID().uuidString.prefix(8) + "-" + src.lastPathComponent
        try FileManager.default.copyItem(at: src, to: url(String(name)))
        return String(name)
    }
}
