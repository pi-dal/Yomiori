import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct WordListImportView: View {
    @Environment(\.dismiss) private var dismiss
    private let onOpen: (WordListDocument) -> Void
    @State private var library = WordListLibrary.shared
    @State private var showingFilePicker = false
    @State private var openedInitialPicker = false
    @State private var filename = ""
    @State private var preview: WordListImportPreview?
    @State private var policy: WordListImportPolicy = .skip
    @State private var issue: WordListValidationError?
    @State private var failed = false
    @State private var reading = false
    @State private var writing = false
    @State private var refreshed = false
    @State private var result: WordListImportResult?
    @State private var operation: Task<Void, Never>?
    @State private var requestID = UUID()

    init(onOpen: @escaping (WordListDocument) -> Void) {
        self.onOpen = onOpen
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let result {
                        successSections(result)
                    } else if reading {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(verbatim: filename).font(Theme.Fonts.body)
                            ProgressView("Checking file…").font(Theme.Fonts.meta)
                        }
                    } else if let issue {
                        issueSections(issue)
                    } else if let preview {
                        previewSections(preview)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            if failed { Text("Import failed. No changes were saved.").foregroundStyle(Theme.errorText) }
                            Button("Choose file") { showingFilePicker = true }.buttonStyle(InkButtonStyle())
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .foregroundStyle(Theme.ink)
            .font(Theme.Fonts.body)
            .environment(\.defaultMinListRowHeight, 48)
            .tint(Theme.ink)
            .navigationTitle("Import word list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string(result == nil ? "Cancel" : "Done")) { close() }
                        .disabled(writing)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let result {
                    Button("Open word list") {
                        let document = result.document
                        close()
                        onOpen(document)
                    }
                    .buttonStyle(InkButtonStyle())
                    .frame(maxWidth: 720).padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(maxWidth: .infinity).background(Theme.background)
                } else if let preview, issue == nil, !reading {
                    importActions(preview)
                }
            }
            .disabled(writing)

        }
        .interactiveDismissDisabled(writing)
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.json]) { selection in
            switch selection {
            case .success(let url): read(url)
            case .failure(let error):
                let cocoa = error as NSError
                guard cocoa.domain != NSCocoaErrorDomain || cocoa.code != CocoaError.userCancelled.rawValue else { return }
                failed = true
            }
        }
        .task {
            guard !openedInitialPicker else { return }
            openedInitialPicker = true
            showingFilePicker = true
        }
        .onDisappear {
            operation?.cancel()
            requestID = UUID()
        }
    }

    @ViewBuilder
    private func previewSections(_ preview: WordListImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: preview.document.title).font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.ink)
            LabeledContent(L10n.string("Language"), value: languageName(preview.document.language))
            LabeledContent(L10n.string("Translation"), value: languageName(preview.document.translationLanguage))
        }
        .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)

        VStack(alignment: .leading, spacing: 12) {
            LabeledContent(L10n.string("Total"), value: preview.document.entries.count.formatted())
            WordListImportCounts(labels: ["New", "Changed", "Unchanged"], counts: [preview.newCount, preview.changedCount, preview.identicalCount])
            if refreshed {
                Text(L10n.string("The word list changed. Check the updated preview."))
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if failed {
                Text(L10n.string("Import failed. No changes were saved."))
                    .font(Theme.Fonts.meta).foregroundStyle(Theme.errorText)
            }
        }

        if preview.duplicateCount > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Existing entries").font(Theme.Fonts.meta.weight(.semibold))
                policyOption(.skip, title: "Skip existing entries")
                policyOption(.update, title: "Update existing entries")
                if policy == .update {
                    Text(L10n.string("Review cards and progress are kept.")).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                }
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("Sample entries").font(Theme.Fonts.meta.weight(.semibold))
            ForEach(Array(preview.document.entries.prefix(3))) { word in
                WordListImportEntryRow(word: word).padding(.vertical, 16).frame(minHeight: 88, alignment: .leading)
            }
            if preview.document.entries.isEmpty {
                Text(L10n.string("No entries found.")).foregroundStyle(Theme.textSecondary)
            }
            NavigationLink { WordListImportEntriesView(document: preview.document) } label: {
                Text(L10n.string("View entries")).frame(minHeight: 44)
            }
        }

        WordListSourceView(source: preview.document.source)
        DisclosureGroup(L10n.string("Details")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: filename).font(Theme.Fonts.meta).textSelection(.enabled)
                LabeledContent(L10n.string("Pronunciation audio"), value: preview.document.entries.filter { $0.pronunciationURL != nil }.count.formatted())
                LabeledContent(L10n.string("Sentence audio"), value: preview.document.entries.filter { $0.exampleAudioURL != nil }.count.formatted())
                LabeledContent(L10n.string("Images"), value: preview.document.entries.filter { $0.pictureURL != nil }.count.formatted())
            }.padding(.top, 12)
        }

        if !preview.changedIDs.isEmpty {
            DisclosureGroup {
                let existing = Dictionary(uniqueKeysWithValues: (preview.existing?.entries ?? []).map { ($0.id, $0) })
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(preview.changedEntries) { word in
                        VStack(alignment: .leading, spacing: 12) {
                            if let previous = existing[word.id] {
                                Text(L10n.string("Current")).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                                WordListImportEntryRow(word: previous, detailed: true)
                            }
                            Text(L10n.string("In this file")).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                            WordListImportEntryRow(word: word, detailed: true)
                        }
                    }
                }.padding(.top, 12)
            } label: { Text(L10n.string("Changed entries")) }
        }
        Button(L10n.string("Choose another file")) { showingFilePicker = true }.frame(minHeight: 48)
    }

    private func policyOption(_ value: WordListImportPolicy, title: String) -> some View {
        Button {
            policy = value
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: policy == value ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20)).frame(width: 24).accessibilityHidden(true)
                Text(L10n.string(title)).font(Theme.Fonts.body)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(policy == value ? .isSelected : [])
    }

    private func importActions(_ preview: WordListImportPreview) -> some View {
        let updates = policy == .update ? preview.changedCount : 0
        let skips = preview.duplicateCount - updates
        let actionCount = preview.actionCount(for: policy)
        let canImport = actionCount > 0
        return VStack(spacing: 12) {
            if !canImport {
                Text(L10n.string("No changes")).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            }
            Button { confirm(preview) } label: {
                HStack(spacing: 12) {
                    if writing { ProgressView().tint(Theme.textSecondary) }
                    Text(writing ? L10n.string("Importing…") : L10n.format("Import %lld words", Int64(actionCount)))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(InkButtonStyle())
            .accessibilityLabel(L10n.string("Import"))
            .accessibilityValue([
                L10n.format("import.addCount", Int64(preview.newCount)),
                L10n.format("import.updateCount", Int64(updates)),
                L10n.format("import.skipCount", Int64(skips))
            ].joined(separator: "\n"))
            .disabled(!canImport || writing)
        }
        .frame(maxWidth: 720).padding(.horizontal, 24).padding(.vertical, 16)
        .frame(maxWidth: .infinity).background(Theme.background)
    }

    @ViewBuilder
    private func issueSections(_ issue: WordListValidationError) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Invalid word list").font(Theme.Fonts.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                if !filename.isEmpty { Text(verbatim: filename).font(Theme.Fonts.body).textSelection(.enabled) }
                Text(verbatim: issue.path).font(Theme.Fonts.meta.monospaced()).textSelection(.enabled)
                Text(issue.localizedReason).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(L10n.string("Choose another file")) { showingFilePicker = true }.buttonStyle(InkButtonStyle())
            Button(L10n.string("Copy errors")) { UIPasteboard.general.string = issue.diagnosticDescription }.frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func successSections(_ result: WordListImportResult) -> some View {
        Text("Word list imported").font(Theme.Fonts.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
        WordListImportCounts(labels: ["Added", "Updated", "Skipped"], counts: [result.newCount, result.updatedCount, result.skippedCount])
        Text(verbatim: result.document.title).font(Theme.Fonts.body)
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func read(_ url: URL) {
        operation?.cancel()
        let id = UUID()
        requestID = id
        filename = url.lastPathComponent
        reading = true
        preview = nil
        issue = nil
        result = nil
        failed = false
        refreshed = false
        policy = .skip
        operation = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                try Self.readDocument(at: url)
            }
            do {
                let document = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                await library.load()
                try Task.checkCancellation()
                guard requestID == id else { return }
                preview = try library.previewValidated(document)
                reading = false
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                reading = false
                if let validation = error as? WordListValidationError { issue = validation }
                else { failed = true }
            }
        }
    }

    private func confirm(_ previous: WordListImportPreview) {
        guard !writing, previous.actionCount(for: policy) > 0 else { return }
        operation?.cancel()
        let id = UUID()
        requestID = id
        writing = true
        failed = false
        operation = Task { @MainActor in
            // Give the native progress indicator a chance to appear before the atomic write.
            await Task.yield()
            guard !Task.isCancelled, requestID == id else { return }
            defer { writing = false }
            do {
                let current = try library.previewValidated(previous.document)
                if current.newCount != previous.newCount || current.changedIDs != previous.changedIDs
                    || current.identicalCount != previous.identicalCount || current.existing != previous.existing {
                    preview = current
                    refreshed = true
                    return
                }
                guard current.actionCount(for: policy) > 0 else { return }
                try Task.checkCancellation()
                // Validation and encoding run away from the UI actor; the library
                // rechecks the catalogue before the atomic commit.
                result = try await library.confirmInBackground(current, policy: policy)
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                failed = true
            }
        }
    }

    private func close() {
        guard !writing else { return }
        operation?.cancel()
        requestID = UUID()
        dismiss()
    }

    nonisolated private static func readDocument(at url: URL) throws -> WordListDocument {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let limit = 20 * 1024 * 1024
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit {
            throw WordListValidationError(path: "$", reason: "File exceeds 20 MiB.")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount: min(64 * 1024, limit - data.count + 1)) ?? Data()
            guard !chunk.isEmpty else { break }
            guard data.count + chunk.count <= limit else {
                throw WordListValidationError(path: "$", reason: "File exceeds 20 MiB.")
            }
            data.append(chunk)
        }
        try Task.checkCancellation()
        let document = try WordListDocument.decodeValidated(data)
        try Task.checkCancellation()
        return document
    }
}

private struct WordListImportEntryRow: View {
    let word: AtlasWord
    var detailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: word.term).font(Theme.Fonts.body.weight(.semibold))
            if !word.reading.isEmpty {
                Text(verbatim: word.reading).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(word.senses.enumerated()), id: \.offset) { _, sense in
                VStack(alignment: .leading, spacing: 8) {
                    if !sense.partOfSpeech.isEmpty {
                        Text(WordListMetadata.partOfSpeech(sense.partOfSpeech)).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    }
                    Text(verbatim: sense.definition).font(Theme.Fonts.body)
                    if !sense.translation.isEmpty {
                        Text(verbatim: sense.translation).font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if detailed {
                LabeledContent(L10n.string("Entry ID"), value: word.id).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                if !word.level.isEmpty { LabeledContent(L10n.string("Level"), value: WordListMetadata.level(word.level)).font(Theme.Fonts.meta) }
                if !word.topic.isEmpty { LabeledContent(L10n.string("Topic"), value: WordListMetadata.topic(word.topic)).font(Theme.Fonts.meta) }
                if !word.uk.isEmpty { Text(L10n.format("UK %@", word.uk)).font(Theme.Fonts.meta) }
                if !word.us.isEmpty { Text(L10n.format("US %@", word.us)).font(Theme.Fonts.meta) }
                ForEach(Array(word.examples.enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: example.text)
                        if !example.translation.isEmpty { Text(verbatim: example.translation).foregroundStyle(Theme.textSecondary) }
                    }.font(Theme.Fonts.body)
                }
                detail("Collocations", values: word.collocations)
                detail("Word family", values: word.family)
                detail("Synonyms", values: word.synonyms)
                detail("Antonyms", values: word.antonyms)
                let usage = [word.tip, word.note ?? ""].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.reduce(into: [String]()) { result, value in
                    if !value.isEmpty && !result.contains(value) { result.append(value) }
                }
                if !usage.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Usage").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        ForEach(usage, id: \.self) { Text(verbatim: $0).font(Theme.Fonts.body) }
                    }
                }
                if let url = word.pronunciationURL { LabeledContent(L10n.string("Pronunciation audio"), value: url.absoluteString).font(Theme.Fonts.meta) }
                if let url = word.exampleAudioURL { LabeledContent(L10n.string("Sentence audio"), value: url.absoluteString).font(Theme.Fonts.meta) }
                if let url = word.pictureURL { LabeledContent(L10n.string("Image"), value: url.absoluteString).font(Theme.Fonts.meta) }
            }
        }

        .textSelection(.enabled)
    }

    @ViewBuilder
    private func detail(_ title: String, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string(title)).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                Text(verbatim: values.joined(separator: "; ")).font(Theme.Fonts.body)
            }
        }
    }
}

private struct WordListImportEntriesView: View {
    let document: WordListDocument
    @State private var search = ""

    private var entries: [AtlasWord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return document.entries }
        return document.entries.filter { word in
            ([word.term, word.id, word.topic, word.level] + word.senses.flatMap { [$0.definition, $0.translation] })
                .contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(entries) { word in
                    WordListImportEntryRow(word: word, detailed: true).wordListRows()
                }
                if entries.isEmpty { Text("No entries match your search.").foregroundStyle(Theme.textSecondary) }
            } header: { Text(L10n.format("lists.count", Int64(entries.count))).font(Theme.Fonts.meta) }
        }
        .font(Theme.Fonts.body)
        .environment(\.defaultMinListRowHeight, 48)
        .listStyle(.plain).listSectionSpacing(24)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .foregroundStyle(Theme.ink)
        .navigationTitle("View entries")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search this list")
    }
}

private struct WordListImportCounts: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let labels: [String]
    let counts: [Int]

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            ForEach(labels.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string(labels[index])).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    Text(counts[index].formatted()).font(Theme.Fonts.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
