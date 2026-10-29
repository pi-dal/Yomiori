import Foundation

enum Files {
    static var dir: URL {
        URL.documentsDirectory.appending(path: "Imports")
    }
    static var temporaryDirectory: URL { FileManager.default.temporaryDirectory.appending(path: "Yomiori", directoryHint: .isDirectory) }
    static func url(_ name: String) -> URL { dir.appending(path: name) }
    /// Copies a picked file into the app's storage and returns its stored name.
    static func importFile(_ src: URL) throws -> String {
        let ok = src.startAccessingSecurityScopedResource()
        defer { if ok { src.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = UUID().uuidString + "-" + src.lastPathComponent
        try FileManager.default.copyItem(at: src, to: url(String(name)))
        return String(name)
    }
}
