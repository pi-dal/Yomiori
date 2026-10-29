import SwiftUI
import SwiftData

struct ExportSheet: View {
    @Query private var cards: [Card]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var onlyNew = false
    @State private var artifact: AnkiArtifact?
    @State private var message: String?
    @State private var building = false
    @State private var sharing = false
    @State private var task: Task<Void, Never>?
    @State private var archiveProgress: Progress?
    @State private var requestID = UUID()
    @State private var artifactGeneration: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Cards", selection: $onlyNew) { Text("export.all").tag(false); Text("export.new").tag(true) }
                        .pickerStyle(.menu).disabled(building)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    Label("CSV and audio in one ZIP", systemImage: "doc.zipper").font(Theme.Fonts.body.weight(.semibold))
                    Text("Extract the ZIP to import the CSV and audio into Anki. This is not an .apkg deck.")
                        .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    if let message { Text(message).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                    if building {
                        ProgressView("Preparing archive…")
                        Button("Cancel", role: .cancel) { cancelBuild() }.frame(minHeight: 44)
                    }
                }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                Button(artifact == nil ? "Export" : "Share") {
                    if artifact != nil { sharing = true } else { build() }
                }.buttonStyle(InkButtonStyle()).disabled(building || cards.isEmpty)
                    .accessibilityIdentifier("export.primary")
                    .padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .font(Theme.Fonts.body).foregroundStyle(Theme.ink).background(Theme.background)
            .navigationTitle("Anki").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
            .onChange(of: onlyNew) { _, _ in discardArtifact(); message = nil }
            .onDisappear { if !sharing { cancelBuild(); discardArtifact() } }
            .sheet(isPresented: $sharing) {
                if let artifact {
                    ActivityShare(items: artifact.files) { completed in
                        guard completed else { return }
                        markDelivered(artifact)
                    }
                }
            }
        }
    }
    private func build() {
        let selected = cards.filter { !onlyNew || !$0.exported }.map(ExportCard.init)
        guard !selected.isEmpty else { message = L10n.string("export.empty"); return }
        cancelBuild()
        building = true; message = nil
        let generation = Operations.shared.generation, request = requestID
        let progress = Progress(); archiveProgress = progress
        task = Task {
            defer { if requestID == request { building = false; archiveProgress = nil; task = nil } }
            let worker = Task.detached(priority: .userInitiated) {
                try AnkiExporter.build(selected, audioDirectory: Files.dir, outputDirectory: Files.temporaryDirectory, progress: progress)
            }
            do {
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { progress.cancel(); worker.cancel() }
                do {
                    try Operations.shared.checkpoint(generation)
                    guard requestID == request else { throw CancellationError() }
                }
                catch { try? FileManager.default.removeItem(at: result.directory); throw error }
                artifact = result; artifactGeneration = generation
                message = L10n.string("Your archive is ready. Cards are marked exported after sharing completes.")
            } catch {
                guard requestID == request, !Task.isCancelled, !(error is CancellationError) else { return }
                message = error.localizedDescription
            }
        }
    }
    private func cancelBuild() {
        requestID = UUID(); archiveProgress?.cancel(); task?.cancel(); task = nil; archiveProgress = nil; building = false
    }
    private func markDelivered(_ artifact: AnkiArtifact) {
        guard let generation = artifactGeneration else { return }
        do { try Operations.shared.checkpoint(generation) }
        catch { return }
        let selected = cards.filter { artifact.cardIDs.contains($0.id) }
        let previous = selected.map { ($0, $0.exported) }
        selected.forEach { $0.exported = true }
        do { try context.save(); message = L10n.format("export.success", Int64(selected.count)) }
        catch { previous.forEach { $0.0.exported = $0.1 }; message = error.localizedDescription }
    }
    private func discardArtifact() {
        if let artifact { try? FileManager.default.removeItem(at: artifact.directory) }
        artifact = nil; artifactGeneration = nil
    }
}

private struct ActivityShare: UIViewControllerRepresentable {
    let items: [URL]
    let completed: (Bool) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, delivered, _, error in
            Task { @MainActor in completed(delivered && error == nil) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
