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
    @AppStorage("readLibraryOrder") private var order = LibraryOrder.newest
    @AppStorage("lastOpenedMaterial") private var lastOpenedID = ""
    @State private var search = ""

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var shown: [Material] {
        order.sorted(items.filter { query.isEmpty || $0.title.localizedStandardContains(query) },
                     title: { $0.title }, createdAt: { $0.createdAt })
    }
    private var resumed: Material? {
        items.first(where: { $0.id.uuidString == lastOpenedID })
            ?? items.first(where: { $0.lastLine > 0 && !$0.lines.isEmpty }) ?? items.first
    }

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
                .listRowBackground(Theme.surface)
                .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions[.trailing] }
                row("Video or audio", "") { showImport = false; importer = .media }
                row("Photos", "") { showImport = false; showPhotos = true }
                row("Subtitle file", "") { showImport = false; importer = .subtitle }
                row("Media link", "") { showImport = false; Task { try? await Task.sleep(for: .milliseconds(400)); linkMode = .link } }
                row("Podcast feed", "") { showImport = false; Task { try? await Task.sleep(for: .milliseconds(400)); linkMode = .podcast } }
            }
            .listStyle(.insetGrouped)
            .environment(\.defaultMinListRowHeight, 56)
            .listRowSeparatorTint(Theme.separator)
            .scrollContentBackground(.hidden).background(Theme.groupedBackground)
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
        .listRowBackground(Theme.surface)
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions[.trailing] }
    }

    private func ingestDownloaded(_ f: URL, title: String, kind: String, art: URL?) {
        importMedia(f, title: title, source: kind, art: art)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if items.isEmpty { empty }
                else if shown.isEmpty { LibrarySearchEmpty(search: $search) }
                else { list }
            }
            .background(Theme.background)
        .font(Theme.Fonts.body)
            .navigationTitle("Read").navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search reading titles")
            .navigationDestination(for: Material.self) { material in
                ReaderView(material: material)
                    .onAppear { lastOpenedID = material.id.uuidString }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }.sharedBackgroundVisibility(.hidden)
                if !items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort", selection: $order) {
                                ForEach(LibraryOrder.allCases, id: \.self) { value in Text(value.label).tag(value) }
                            }
                        } label: { Image(systemName: "arrow.up.arrow.down") }
                        .accessibilityLabel("Sort reading material")
                    }.sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImport = true } label: { Image(systemName: "plus") }.accessibilityLabel("Import")
                }.sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showImport) { importSheet }
            .sheet(item: Binding(get: { linkMode.map { ModeBox(mode: $0) } }, set: { if $0 == nil { linkMode = nil } })) { b in
                LinkSheet(mode: b.mode) { f, title, kind, art in ingestDownloaded(f, title: title, kind: kind, art: art) }
            }
            .onChange(of: app.jumpMaterial?.id) { _, _ in openJump() }
            .onChange(of: app.jumpMaterial?.time) { _, _ in openJump() }
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
            VStack(alignment: .leading, spacing: 0) {
                DailyStudySection().padding(.bottom, 24)
                Text("Your next read starts here.")
                    .literary(.title1)
                    .padding(.top, 20).padding(.bottom, 12)
                Text("Bring something you want to understand.")
                    .font(.body).foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 32)
                SourceAction(symbol: "play.rectangle", title: "Video or audio", detail: "Read along with what you hear.") { importer = .media }
                SourceAction(symbol: "text.alignleft", title: "Subtitle file", detail: "Open a transcript, line by line.") { importer = .subtitle }
                SourceAction(symbol: "link", title: "Media link", detail: "Open a video or audio link.") { linkMode = .link }
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
            .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private var list: some View {
        let featuredMaterial = query.isEmpty ? resumed : nil
        let recent = shown.filter { $0.id != featuredMaterial?.id }
        return List {
            if query.isEmpty {
                DailyStudySection()
                    .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 16, trailing: 24))
                    .listRowBackground(Theme.background).listRowSeparator(.hidden)
            }
            if let material = featuredMaterial {
                Section {
                    Button { path.append(material) } label: { featured(material) }
                        .accessibilityIdentifier("reading-featured")
                        .buttonStyle(PressFeedbackStyle())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Theme.background)
                        .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                        .swipeActions { Button("Delete", role: .destructive) { delete(material) } }
                }
            }
            if !recent.isEmpty {
                Section {
                    ForEach(recent) { material in
                        NavigationLink(value: material) { materialRow(material) }
                            .listRowBackground(Theme.background)
                            .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                    .onDelete { offsets in for index in offsets { delete(recent[index]) } }
                } header: {
                    SectionLabel(title: query.isEmpty ? (order == .newest ? "Recent" : "By title") : "Search results")
                        .textCase(nil)
                        .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 8, trailing: 24))
                }
            }
        }
        .listStyle(.plain)
        .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
        .listRowBackground(Theme.background)
        .listSectionSpacing(0)
        .listSectionSeparator(.hidden)
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
        .scrollContentBackground(.hidden)
    }

    private func featured(_ material: Material) -> some View {
        let lines = material.lines
        let index = min(max(0, material.lastLine), max(0, lines.count - 1))
        return VStack(alignment: .leading, spacing: 14) {
            if !lines.isEmpty {
                Text(lines[index].text)
                    .literary(.title1, .original)
                    .lineSpacing(8).lineLimit(4)
                    .foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(material.title).font(.headline).foregroundStyle(Theme.ink)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !lines.isEmpty {
                        // A shiori: the bookmark marks where the learner stopped reading.
                        Image(systemName: "bookmark.fill").foregroundStyle(Theme.vermilion).accessibilityHidden(true)
                    }
                    Text(Language.find(material.languageCode).displayName + " · " + (lines.isEmpty ? L10n.string("read.needsTranscription") : L10n.format("read.position", Int64(index + 1), Int64(lines.count))))
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.caption)
            }
            HStack(spacing: 6) {
                Text(material.lastLine > 0 ? "Continue reading" : "Start reading")
                Image(systemName: "arrow.right").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            .frame(minHeight: 44, alignment: .leading)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func materialRow(_ material: Material) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(material.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
            if let first = material.lines.first {
                Text(first.text).literary(.body, material.languageCode == "ja" ? .original : .interface).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            Label(material.lines.isEmpty ? L10n.string("read.needsTranscription") : Language.find(material.languageCode).displayName,
                  systemImage: material.isAudio ? "waveform" : "text.alignleft")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressCard(_ t: (title: String, p: Double)) -> some View {
        VStack(spacing: 12) {
            Text(L10n.format("read.transcribing", Int64(t.p * 100))).font(Theme.Fonts.body.weight(.semibold))
            ProgressLine(value: t.p)
            Button("Cancel", role: .cancel) { imports.cancel() }
        }
        .padding(24).frame(maxWidth: 320)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
    }

    private func delete(_ m: Material) {
        if let f = m.mediaFile { try? FileManager.default.removeItem(at: Files.url(f)) }
        if lastOpenedID == m.id.uuidString { lastOpenedID = "" }
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
