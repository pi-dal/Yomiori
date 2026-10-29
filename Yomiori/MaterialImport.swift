import Foundation
import SwiftData
import Observation

@MainActor @Observable
final class MaterialImport {
    private(set) var progress: (title: String, p: Double)?
    private(set) var openedID: UUID?
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var operationID = UUID()

    func subtitle(_ url: URL, language: String, context: ModelContext) throws -> Material {
        try Operations.shared.checkpoint(Operations.shared.generation)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        let lines = Subtitles.parse(text)
        guard !lines.isEmpty else { throw TranscribeError.none }
        let material = Material(title: url.deletingPathExtension().lastPathComponent)
        material.languageCode = language
        try material.writeLines(lines)
        context.insert(material)
        do { try context.save() } catch { context.delete(material); throw error }
        return material
    }
    func media(_ url: URL, title: String?, source: String, artwork: URL?, language: String, context: ModelContext) throws {
        cancel()
        try Operations.shared.checkpoint(Operations.shared.generation)
        let name = try Files.importFile(url)
        let material = Material(title: title ?? url.deletingPathExtension().lastPathComponent, mediaFile: name)
        material.languageCode = language
        material.sourceKind = source; material.artworkURL = artwork?.absoluteString
        material.isAudio = ["mp3", "m4a", "aac", "wav", "aiff", "caf"].contains(url.pathExtension.lowercased())
        material.needsTranscription = true
        context.insert(material)
        do { try context.save() } catch {
            context.delete(material)
            try? FileManager.default.removeItem(at: Files.url(name))
            throw error
        }
        let generation = Operations.shared.generation
        let id = UUID(); operationID = id
        let materialID = material.id, materialTitle = material.title, locale = Language.find(language).locale
        progress = (materialTitle, 0)
        error = nil
        task = Task {
            defer { if operationID == id { progress = nil; task = nil } }
            do {
                let lines = try await Operations.shared.run {
                    try await Transcriber.run(url: Files.url(name), locale: locale) { value in
                        Task { @MainActor in
                            guard self.operationID == id, Operations.shared.generation == generation else { return }
                            self.progress = (materialTitle, value)
                        }
                    }
                }
                try Operations.shared.checkpoint(generation)
                guard operationID == id, !material.isDeleted, material.modelContext != nil else { return }
                try material.writeLines(lines)
                material.needsTranscription = false
                try context.save()
                openedID = materialID
            } catch {
                guard operationID == id, Operations.shared.generation == generation, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                openedID = materialID
            }
        }
    }
    func cancel() {
        operationID = UUID()
        task?.cancel(); task = nil; progress = nil
    }
}
