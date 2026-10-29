import Foundation
import SwiftData

@MainActor enum AppDataService {
    /// Durable intent + idempotent steps: an interrupted reset is retried at next launch.
    /// No claim of a transaction spanning SQLite and the filesystem.
    static func clear(context: ModelContext, operations: Operations? = nil,
                      library: WordListLibrary? = nil, directories: [URL]? = nil,
                      removeDirectory: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) throws {
        let operations = operations ?? .shared
        let library = library ?? .shared
        let directories = directories ?? managedDirectories
        operations.beginReset()
        do {
            // Preserve pending edits before deleting in a separate context. That context owns its rollback.
            try context.save()
            let deletion = ModelContext(context.container)
            deletion.autosaveEnabled = false
            try deletion.transaction {
                try deletion.delete(model: Material.self)
                try deletion.delete(model: DictEntry.self)
                try deletion.delete(model: PDFDoc.self)
                try deletion.delete(model: ChatMsg.self)
                try deletion.delete(model: Mistake.self)
                try deletion.delete(model: Card.self)
                try deletion.delete(model: ImmersionLog.self)
                try deletion.save()
            }
            // Ensure registered instances cannot later auto-save stale changes.
            context.rollback()
            try library.clearImported()
            for directory in directories where FileManager.default.fileExists(atPath: directory.path) {
                try removeDirectory(directory)
            }
            operations.finishReset()
        } catch {
            // Keep the reset marker and block content views until retry succeeds.
            throw error
        }
    }
    static var managedDirectories: [URL] {
        [Files.dir, FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "WordAtlasAudio"), Files.temporaryDirectory]
    }
}
