import SwiftUI
import Foundation

struct Episode: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var date: String
    var duration: String
    var url: URL
    var art: URL?
}
struct Feed { var title: String; var art: URL?; var episodes: [Episode] }

enum LinkError: LocalizedError {
    case page, failed, noPodcast, invalid
    var errorDescription: String? {
        switch self {
        case .page: L10n.string("link.unsupported")
        case .failed: L10n.string("link.failed")
        case .noPodcast: L10n.string("link.noFeed")
        case .invalid: L10n.string("Enter a valid link.")
        }
    }
}

enum LinkKind { case media(URL), feed(URL) }

enum LinkImport {
    static let mediaExt: Set<String> = ["mp4", "m4v", "mov", "mp3", "m4a", "aac", "wav", "aiff", "caf"]

    static func parse(_ s: String) throws -> URL {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.contains("://") && t.contains(".") { t = "https://" + t }
        guard let u = URL(string: t), let sc = u.scheme?.lowercased(), sc == "http" || sc == "https", u.host != nil else { throw LinkError.invalid }
        return u
    }

    static func classify(_ url: URL) async throws -> LinkKind {
        if url.host?.contains("podcasts.apple.com") == true {
            guard let m = url.absoluteString.range(of: "id(\\d+)", options: .regularExpression) else { throw LinkError.noPodcast }
            let id = url.absoluteString[m].dropFirst(2)
            let (d, _) = try await URLSession.shared.data(from: URL(string: "https://itunes.apple.com/lookup?id=\(id)")!)
            guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any], let r = (j["results"] as? [[String: Any]])?.first,
                  let f = (r["feedUrl"] as? String).flatMap(URL.init(string:)) else { throw LinkError.noPodcast }
            return .feed(f)
        }
        if mediaExt.contains(url.pathExtension.lowercased()) { return .media(url) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "HEAD"
        let resp: URLResponse
        do { (_, resp) = try await URLSession.shared.data(for: req) } catch { throw LinkError.failed }
        let type = ((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if (resp as? HTTPURLResponse)?.statusCode ?? 200 >= 400 { throw LinkError.failed }
        if type.hasPrefix("audio/") || type.hasPrefix("video/") { return .media(url) }
        if type.contains("xml") || type.contains("rss") { return .feed(url) }
        throw LinkError.page
    }

    static func feed(_ url: URL) async throws -> Feed {
        let (d, _) = try await URLSession.shared.data(from: url)
        let p = FeedParser(); let x = XMLParser(data: d); x.delegate = p
        guard x.parse(), !p.episodes.isEmpty else { throw LinkError.noPodcast }
        return Feed(title: p.title, art: p.art, episodes: Array(p.episodes.prefix(50)))
    }
}

final class FeedParser: NSObject, XMLParserDelegate {
    var title = "", art: URL?, episodes: [Episode] = []
    private var inItem = false, text = "", cur = (title: "", date: "", dur: "", url: URL?.none, art: URL?.none)
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String]) {
        text = ""
        if e == "item" { inItem = true; cur = ("", "", "", nil, nil) }
        if e == "enclosure", inItem, let u = a["url"].flatMap(URL.init(string:)) { cur.url = u }
        if q == "itunes:image", let h = a["href"].flatMap(URL.init(string:)) { if inItem { cur.art = h } else if art == nil { art = h } }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            if e == "title" { cur.title = t }
            if e == "pubDate" { cur.date = String(t.prefix(16)) }
            if q == "itunes:duration" { cur.dur = t }
            if e == "item" {
                inItem = false
                if let u = cur.url { episodes.append(Episode(title: cur.title, date: cur.date, duration: cur.dur, url: u, art: cur.art ?? art)) }
            }
        } else if e == "title", title.isEmpty { title = t }
    }
}

/// Each async URLSession download owns its cancellation; the delegate only reports progress.
final class Downloader {
    var onProgress: @Sendable (Double, Int64) -> Void = { _, _ in }
    func download(_ url: URL) async throws -> URL {
        let delegate = DownloadProgress(onProgress)
        try Task.checkCancellation()
        let (temporary, response) = try await URLSession.shared.download(for: URLRequest(url: url, timeoutInterval: 120), delegate: delegate)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw LinkError.failed }
        try FileManager.default.createDirectory(at: Files.temporaryDirectory, withIntermediateDirectories: true)
        let destination = Files.temporaryDirectory.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double, Int64) -> Void
    init(_ progress: @escaping @Sendable (Double, Int64) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), totalBytesExpectedToWrite) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

/// What the Read tab does with a finished download.
typealias IngestHandler = (_ file: URL, _ title: String, _ kind: String, _ art: URL?) -> Void

struct LinkSheet: View {
    enum Mode { case link, podcast }
    let mode: Mode
    let ingest: IngestHandler
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var busy = false
    @State private var progress: Double?
    @State private var feed: Feed?
    @State private var dl = Downloader()
    @State private var task: Task<Void, Never>?
    @State private var requestID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let feed { episodes(feed) } else { entry }
                    if let progress {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.format("link.downloading", Int64(progress * 100))).font(Theme.Fonts.meta)
                            ProgressLine(value: progress)
                            Button("Cancel", role: .cancel) { cancel() }.frame(minHeight: 44)
                        }
                    } else if busy { ProgressView("Loading…").font(Theme.Fonts.meta) }
                    if let error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Couldn't import").font(Theme.Fonts.body.weight(.semibold))
                            Text(error).font(Theme.Fonts.body)
                        }.foregroundStyle(Theme.errorText).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
            }
            .background(Theme.background).font(Theme.Fonts.body).foregroundStyle(Theme.ink).tint(Theme.ink)
            .navigationTitle(L10n.string(feed != nil ? "link.episodes" : mode == .link ? "link.title" : "link.podcastTitle")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { cancel(); dismiss() } } }
            .onDisappear { cancel() }
        }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("", text: $text, prompt: Text(L10n.string(mode == .link ? "https://" : "RSS link")).foregroundStyle(Theme.textSecondary))
                    .foregroundStyle(Theme.ink).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel(L10n.string(mode == .link ? "Media link" : "Podcast feed"))
                Button { text = UIPasteboard.general.string ?? text } label: { Image(systemName: "doc.on.clipboard") }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Paste")
            }
            .padding(.horizontal, 12).frame(minHeight: 48).background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8))
            Button { go() } label: { Text(LocalizedStringKey(mode == .link ? "Import" : "Find episodes")) }
                .buttonStyle(InkButtonStyle()).disabled(busy || text.isEmpty)
            }
    }

    private func episodes(_ f: Feed) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(f.title).font(Theme.Fonts.body.weight(.semibold))
            ForEach(f.episodes) { e in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: e.art) { $0.resizable().scaledToFill() } placeholder: { Theme.controlFill }
                        .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(e.title).font(Theme.Fonts.body.weight(.semibold))
                        VStack(alignment: .leading, spacing: 8) {
                            if !e.date.isEmpty { Text(e.date) }
                            if !e.duration.isEmpty { Text(e.duration) }
                        }.font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    }
                    }
                    Button("Import episode") { fetch(e.url, title: e.title, kind: "podcast", art: e.art) }.font(Theme.Fonts.body.weight(.semibold)).frame(minHeight: 44).foregroundStyle(Theme.ink).disabled(busy)
                }
            }
        }
    }

    private func go() {
        cancel(); error = nil; busy = true
        let request = requestID, generation = Operations.shared.generation
        task = Task {
            defer { if requestID == request { busy = false } }
            do {
                let u = try LinkImport.parse(text)
                let classification = try await LinkImport.classify(u)
                try Operations.shared.checkpoint(generation)
                guard requestID == request else { return }
                switch classification {
                case .media(let m): await fetchAsync(m, title: m.deletingPathExtension().lastPathComponent, kind: "link", art: nil)
                case .feed(let f):
                    let result = try await LinkImport.feed(f)
                    try Operations.shared.checkpoint(generation)
                    feed = result
                }
            } catch {
                if requestID == request, !Task.isCancelled, !(error is CancellationError) { self.error = (error as? LinkError)?.errorDescription ?? LinkError.failed.errorDescription }
            }
        }
    }
    private func cancel() {
        requestID = UUID(); task?.cancel(); task = nil; progress = nil; busy = false
    }
    private func fetch(_ u: URL, title: String, kind: String, art: URL?) {
        cancel(); error = nil; busy = true
        let request = requestID
        task = Task {
            await fetchAsync(u, title: title, kind: kind, art: art)
            if requestID == request { busy = false }
        }
    }
    private func fetchAsync(_ u: URL, title: String, kind: String, art: URL?) async {
        progress = 0
        let generation = Operations.shared.generation, request = requestID
        dl.onProgress = { p, _ in Task { @MainActor in
            guard requestID == request, Operations.shared.generation == generation else { return }
            progress = p
        } }
        do {
            let f = try await Operations.shared.run { try await dl.download(u) }
            defer { try? FileManager.default.removeItem(at: f) }
            try Operations.shared.checkpoint(generation)
            guard requestID == request else { return }
            progress = nil
            ingest(f, title, kind, art)
            dismiss()
        } catch {
            guard requestID == request else { return }
            progress = nil
            if !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = LinkError.failed.errorDescription }
        }
    }
}
