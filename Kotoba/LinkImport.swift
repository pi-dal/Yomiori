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

/// Downloads a file with progress and cancellation.
final class Downloader: NSObject, URLSessionDownloadDelegate {
    private var cont: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    var onProgress: (Double, Int64) -> Void = { _, _ in }
    private var session: URLSession?

    func download(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in
                cont = c
                let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                session = s
                task = s.downloadTask(with: url); task?.resume()
            }
        } onCancel: { task?.cancel() }
    }
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData w: Int64, totalBytesWritten t: Int64, totalBytesExpectedToWrite e: Int64) {
        if e > 0 { onProgress(Double(t) / Double(e), e) }
    }
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        if let code = (downloadTask.response as? HTTPURLResponse)?.statusCode, code >= 400 { cont?.resume(throwing: LinkError.failed); cont = nil; return }
        let dst = URL.temporaryDirectory.appending(path: UUID().uuidString + "-" + (downloadTask.originalRequest?.url?.lastPathComponent ?? "media"))
        do { try FileManager.default.moveItem(at: loc, to: dst); cont?.resume(returning: dst) } catch { cont?.resume(throwing: error) }
        cont = nil
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, let c = cont { c.resume(throwing: error); cont = nil }
        s.finishTasksAndInvalidate()
    }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let feed { episodes(feed) } else { entry }
                    if let progress {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.format("link.downloading", Int64(progress * 100))).font(Theme.Fonts.meta)
                            ProgressLine(value: progress)
                            Button("Cancel", role: .cancel) { task?.cancel(); self.progress = nil; busy = false }.frame(minHeight: 44)
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
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { task?.cancel(); dismiss() } } }
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
        error = nil; busy = true
        task = Task {
            defer { busy = false }
            do {
                let u = try LinkImport.parse(text)
                switch try await LinkImport.classify(u) {
                case .media(let m): await fetchAsync(m, title: m.deletingPathExtension().lastPathComponent, kind: "link", art: nil)
                case .feed(let f): feed = try await LinkImport.feed(f)
                }
            } catch { self.error = (error as? LinkError)?.errorDescription ?? LinkError.failed.errorDescription }
        }
    }
    private func fetch(_ u: URL, title: String, kind: String, art: URL?) {
        error = nil; busy = true
        task = Task { await fetchAsync(u, title: title, kind: kind, art: art); busy = false }
    }
    private func fetchAsync(_ u: URL, title: String, kind: String, art: URL?) async {
        progress = 0
        dl.onProgress = { p, size in Task { @MainActor in progress = p } }
        do {
            let f = try await dl.download(u)
            progress = nil
            ingest(f, title, kind, art)
            dismiss()
        } catch {
            progress = nil
            if (error as? URLError)?.code != .cancelled { self.error = LinkError.failed.errorDescription }
        }
    }
}
