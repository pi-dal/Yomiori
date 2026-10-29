import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import UIKit

struct ReadView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Material.createdAt, order: .reverse) private var items: [Material]
    @Environment(AppState.self) private var app
    @State private var importer: ImportKind?
    @State private var linkMode: LinkSheet.Mode?
    @State private var showImport = false
    @State private var photo: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showSettings = false
    @State private var imports = MaterialImport()
    @State private var error: String?
    @State private var path: [Material] = []
    @AppStorage("targetLang") private var importLanguage = "ja"

    enum ImportKind: Identifiable { case media, subtitle; var id: Self { self } }
    struct ModeBox: Identifiable { let mode: LinkSheet.Mode; var id: Int { mode == .link ? 0 : 1 } }

    private func openJump() {
        guard let j = app.jumpMaterial, let m = items.first(where: { $0.id.uuidString == j.id }) else { return }
        m.lastLine = Subtitles.index(at: j.time, in: m.lines) ?? 0
        path = [m]
    }

    private var importSheet: some View {
        NavigationStack {
            List {
                Picker("Language", selection: $importLanguage) {
                    Text("Japanese").tag("ja"); Text("English").tag("en")
                }
                .frame(minHeight: 56)
                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                .listRowSeparatorTint(Theme.separator)
                .listRowSeparator(.hidden, edges: .top)
                .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions[.trailing] }
                row("Video or audio", "") { showImport = false; importer = .media }
                row("Photos", "") { showImport = false; showPhotos = true }
                row("Subtitle file", "") { showImport = false; importer = .subtitle }
                row("Media link", "") { showImport = false; Task { try? await Task.sleep(for: .milliseconds(400)); linkMode = .link } }
                row("Podcast feed", "") { showImport = false; Task { try? await Task.sleep(for: .milliseconds(400)); linkMode = .podcast } }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 56)
            .listRowSeparatorTint(Theme.separator)
            .scrollContentBackground(.hidden).background(Theme.background)
            .foregroundStyle(Theme.ink)
            .navigationTitle("Import").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { showImport = false } } }
        }
        .presentationDetents([.medium, .large])
    }
    private func row(_ title: LocalizedStringKey, _ sub: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        .listRowSeparatorTint(Theme.separator)
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions[.trailing] }
    }

    private func ingestDownloaded(_ f: URL, title: String, kind: String, art: URL?) {
        importMedia(f, title: title, source: kind, art: art)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if items.isEmpty { empty } else { list }
            }
            .background(Theme.background)
        .font(Theme.Fonts.body)
            .navigationTitle("Read").navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Material.self) { ReaderView(material: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showImport = true } label: { Image(systemName: "plus") }.accessibilityLabel("Import")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showImport) { importSheet }
            .sheet(item: Binding(get: { linkMode.map { ModeBox(mode: $0) } }, set: { if $0 == nil { linkMode = nil } })) { b in
                LinkSheet(mode: b.mode) { f, title, kind, art in ingestDownloaded(f, title: title, kind: kind, art: art) }
            }
            .onChange(of: app.jumpMaterial?.id) { _, id in openJump() }
            .onAppear { openJump() }
            .fileImporter(isPresented: Binding(get: { importer != nil }, set: { if !$0 { importer = nil } }),
                          allowedContentTypes: importer == .subtitle ? [UTType(filenameExtension: "srt") ?? .plainText, UTType(filenameExtension: "vtt") ?? .plainText, .plainText] : [.movie, .audio, .mpeg4Movie, .mp3]) { r in
                guard case .success(let url) = r else { return }
                let kind = importer; importer = nil
                if kind == .subtitle { importSubtitle(url) } else { importMedia(url) }
            }
            .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .videos)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let m = try? await item.loadTransferable(type: VideoFile.self) { importMedia(m.url, title: L10n.string("Video")) }
                    photo = nil
                }
            }
            .overlay { if let t = imports.progress { progressCard(t) } }
            .onChange(of: imports.openedID) { _, id in
                if let material = items.first(where: { $0.id == id }) { path = [material] }
            }
            .onChange(of: imports.error) { _, value in error = value }
            .onDisappear { imports.cancel() }
            .alert("Couldn't import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private var empty: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("No reading material").font(Theme.Fonts.body.weight(.semibold))
                Button { showImport = true } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "plus").font(.system(size: 24)).frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add Text").font(Theme.Fonts.body.weight(.semibold))
                            Text("Import or add a text to start reading.").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                }.buttonStyle(.plain)
            }
            .frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.top, 24).frame(maxWidth: .infinity)
        }
    }

    private var list: some View {
        let resumed = items.first(where: { $0.lastLine > 0 && !$0.lines.isEmpty })
        let recent = items.filter { $0.id != resumed?.id }
        return List {
            Section {
                Text("Continue where you left off or add a new text.")
                    .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 20, trailing: 24))
                    .listRowSeparator(.hidden)
            }
            if let m = resumed {
                Section("Continue reading") {
                    NavigationLink(value: m) { materialRow(m, resumed: true) }
                        .swipeActions { Button("Delete", role: .destructive) { delete(m) } }
                }
            }
            Section("Recent") {
                ForEach(recent) { m in
                    NavigationLink(value: m) { materialRow(m, resumed: false) }
                }
                .onDelete { offsets in for i in offsets { delete(recent[i]) } }
            }
            Section("Add Text") {
                Button { showImport = true } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "plus").font(.system(size: 24, weight: .regular)).frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Import or add a text").font(Theme.Fonts.body.weight(.semibold))
                            Text("Paste text, import a file, or choose from your library.").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                    }
                    .frame(minHeight: 56, alignment: .leading)
                }
            }
        }
        .listStyle(.plain)
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
        .environment(\.defaultMinListRowHeight, 56)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
    }

    private func materialRow(_ material: Material, resumed: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: material.isAudio ? "waveform" : "doc.text")
                .font(.system(size: 20)).frame(width: 24, height: 24)
                .foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(material.title).font(Theme.Fonts.body.weight(.semibold))
                Text(Language.find(material.languageCode).displayName).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                Text(resumed
                     ? L10n.format("read.position", Int64(material.lastLine + 1), Int64(material.lines.count))
                     : (material.lines.isEmpty ? L10n.string("read.needsTranscription") : L10n.format("read.ready", Int64(material.lines.count))))
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func progressCard(_ t: (title: String, p: Double)) -> some View {
        VStack(spacing: 12) {
            Text(L10n.format("read.transcribing", Int64(t.p * 100))).font(Theme.Fonts.body.weight(.semibold))
            ProgressLine(value: t.p)
            Button("Cancel", role: .cancel) { imports.cancel() }
        }
        .padding(24).frame(maxWidth: 320)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func delete(_ m: Material) {
        if let f = m.mediaFile { try? FileManager.default.removeItem(at: Files.url(f)) }
        ctx.delete(m)
    }

    private func importSubtitle(_ url: URL) {
        do { path = [try imports.subtitle(url, language: importLanguage, context: ctx)] }
        catch { self.error = error.localizedDescription }
    }

    private func importMedia(_ url: URL, title: String? = nil, source: String = "file", art: URL? = nil) {
        do { try imports.media(url, title: title, source: source, artwork: art, language: importLanguage, context: ctx) }
        catch { self.error = error.localizedDescription }
    }
}

struct VideoFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { f in
            let dst = URL.temporaryDirectory.appending(path: UUID().uuidString + "-" + f.file.lastPathComponent)
            try FileManager.default.copyItem(at: f.file, to: dst)
            return VideoFile(url: dst)
        }
    }
}

// MARK: Reader (Focus layout)
