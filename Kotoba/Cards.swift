import SwiftUI
import SwiftData
import AVFoundation

/// A mined sentence, reviewed on a schedule.
@Model final class Card {
    var id = UUID()
    var sentence: String
    var word: String
    var reading: String = ""
    var meaning: String = ""
    var definitionJa: String = ""
    var translation: String = ""
    var languageCode: String = "ja"
    var wordListID: String = ""
    var wordListEntryID: String = ""
    var audioRemoteURL: String = ""
    var definitionEnglish: String = ""
    var audioFile: String?
    var sourceID: String = ""
    var sourceName: String = ""
    var sourcePos: Double = 0
    var createdAt = Date()
    var due = Date()
    var interval: Double = 0      // days
    var ease: Double = 2.5
    var reps = 0
    var lapses = 0
    var exported = false
    init(sentence: String, word: String) { self.sentence = sentence; self.word = word }
}

enum Rating: Int, CaseIterable { case again, hard, good, easy
    var label: String { L10n.string(["review.again", "review.hard", "review.good", "review.easy"][rawValue]) }
}

enum Scheduler {
    /// The next interval in days for a rating (0 means "again in 10 minutes").
    static func next(_ c: Card, _ r: Rating) -> Double {
        switch r {
        case .again: return 0
        case .hard: return c.interval == 0 ? 1 : max(1, (c.interval * 1.2).rounded())
        case .good: return c.interval == 0 ? 2 : max(c.interval + 1, (c.interval * c.ease).rounded())
        case .easy: return c.interval == 0 ? 4 : max(c.interval + 2, (c.interval * c.ease * 1.3).rounded())
        }
    }
    static func hint(_ days: Double) -> String {
        if days == 0 { return L10n.format("review.nextMinutes", Int64(10)) }
        let d = Int(days)
        return L10n.format("review.nextDays", Int64(d))
    }
    static func apply(_ c: Card, _ r: Rating) {
        let days = next(c, r)
        switch r {
        case .again: c.lapses += 1; c.ease = max(1.3, c.ease - 0.2)
        case .hard: c.ease = max(1.3, c.ease - 0.15)
        case .good: break
        case .easy: c.ease += 0.15
        }
        c.reps += 1
        c.interval = days
        c.due = days == 0 ? Date().addingTimeInterval(600) : Calendar.current.date(byAdding: .day, value: Int(days), to: Calendar.current.startOfDay(for: Date()))!
    }
}

enum Clip {
    /// Cuts the audio between `start` and `end` seconds out of a media file into an .m4a at `dest`.
    static func export(media: URL, start: Double, end: Double, to dest: URL) async -> Bool {
        let asset = AVURLAsset(url: media)
        guard let s = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return false }
        let a = max(0, start - 0.3), b = end + 0.3
        s.timeRange = CMTimeRange(start: CMTime(seconds: a, preferredTimescale: 600), end: CMTime(seconds: b, preferredTimescale: 600))
        try? FileManager.default.removeItem(at: dest)
        do { try await s.export(to: dest, as: .m4a); return true } catch { return false }
    }
}

@MainActor @Observable
final class ClipPlayer {
    var playing = false
    private var player: AVAudioPlayer?
    private var timer: Timer?
    func play(_ url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play(); playing = player != nil
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.playing = self.player?.isPlaying ?? false; if !self.playing { self.timer?.invalidate() } }
        }
    }
    func stop() { player?.stop(); playing = false; timer?.invalidate() }
}

struct AudioRow: View {
    let url: URL?
    let duration: Double
    var label = "Play audio"
    @State private var clip = ClipPlayer()
    var body: some View {
        HStack(spacing: 12) {
            Button { if let url { clip.play(url) } } label: {
                Image(systemName: clip.playing ? "waveform" : "play.fill").font(.system(size: 20)).foregroundStyle(url == nil ? Theme.textSecondary : Theme.background)
                    .frame(width: 44, height: 44).background(url == nil ? Theme.controlFill : Theme.ink, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(url == nil)
            .accessibilityLabel(L10n.string(label))
            HStack(spacing: 2) {
                ForEach(0..<28, id: \.self) { i in
                    Rectangle().fill(Theme.controlSelected).frame(width: 2, height: CGFloat(6 + (i * 7 % 11)))
                }
            }.frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
            if duration > 0 { Text(Duration.seconds(duration.rounded()).formatted(.time(pattern: .minuteSecond))).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
        }
        .onDisappear { clip.stop() }
    }
}

enum Anki {
    /// Writes cards.csv and the audio files into a temp folder and returns their URLs.
    static func export(_ cards: [Card]) -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appending(path: "anki-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var csv = "sentence,word,meaning,audio\n"
        var urls: [URL] = []
        for c in cards {
            var audio = ""
            if let a = c.audioFile, FileManager.default.fileExists(atPath: Files.url(a).path) {
                audio = "[sound:\(a)]"
                let d = dir.appending(path: a); try? FileManager.default.copyItem(at: Files.url(a), to: d); urls.append(d)
            }
            let meaning = [c.reading, c.meaning, c.translation].filter { !$0.isEmpty }.joined(separator: "\n")
            csv += [esc(c.sentence), esc(c.word), esc(meaning), esc(audio)].joined(separator: ",") + "\n"
        }
        let f = dir.appending(path: "cards.csv"); try? csv.write(to: f, atomically: true, encoding: .utf8)
        return [f] + urls
    }
}

struct ExportSheet: View {
    @Query private var cards: [Card]
    @Environment(\.dismiss) private var dismiss
    @State private var onlyNew = false
    @State private var files: [URL] = []
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Cards", selection: $onlyNew) { Text("export.all").tag(false); Text("export.new").tag(true) }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Theme.controlBorder, lineWidth: 0.5) }
                    if let message { Text(message).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                }.padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    .font(Theme.Fonts.body).foregroundStyle(Theme.ink)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group {
                    if files.isEmpty {
                        Button { build() } label: { Text("Export") }.buttonStyle(InkButtonStyle())
                    } else {
                        ShareLink(items: files) { Text("Share") }.buttonStyle(InkButtonStyle())
                    }
                }
                .frame(maxWidth: 720).padding(.horizontal, 24).padding(.vertical, 16)
                .frame(maxWidth: .infinity).background(Theme.background)
            }
            .background(Theme.background)
            .navigationTitle("Anki").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
        }
    }
    private func build() {
        let sel = cards.filter { !onlyNew || !$0.exported }
        if sel.isEmpty { message = L10n.string("export.empty"); return }
        files = Anki.export(sel); sel.forEach { $0.exported = true }
        message = L10n.format("export.success", Int64(sel.count))
    }
}

enum CoachStage: String, CaseIterable {
    case beginner = "Beginner", immersion = "Immersion", output = "Output"
    var label: String {
        switch self {
        case .beginner: L10n.string("coach.beginner")
        case .immersion: L10n.string("coach.immersion")
        case .output: L10n.string("coach.output")
        }
    }
    var detail: String {
        switch self {
        case .beginner: L10n.string("coach.stageBeginner")
        case .immersion: L10n.string("coach.stageImmersion")
        case .output: L10n.string("coach.stageOutput")
        }
    }
    static var current: CoachStage { CoachStage(rawValue: UserDefaults.standard.string(forKey: "coachStage") ?? "") ?? .beginner }
    var promptRule: String {
        switch self {
        case .beginner: "Stage: Beginner. Use simple words and short sentences, with the learner's native language for help."
        case .immersion: "Stage: Immersion. Reply almost entirely in the target language, using the learner's mined sentences and words naturally."
        case .output: "Stage: Output. Reply only in the target language; the learner leads the conversation. No translations."
        }
    }
}

struct StagePicker: View {
    @AppStorage("coachStage") private var stage = CoachStage.beginner.rawValue
    var body: some View {
        List {
            Section {
                ForEach(CoachStage.allCases, id: \.self) { s in
                    Button { stage = s.rawValue } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) { Text(s.label).font(Theme.Fonts.body.weight(.semibold)); Text(s.detail).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                            Spacer()
                            Image(systemName: stage == s.rawValue ? "largecircle.fill.circle" : "circle")
                        }.foregroundStyle(Theme.ink).frame(minHeight: 56)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                    .listRowBackground(Theme.background)
                    .listRowSeparator(.hidden)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                    .accessibilityAddTraits(stage == s.rawValue ? .isSelected : [])
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Theme.background)
        .font(Theme.Fonts.body).foregroundStyle(Theme.ink)
        .navigationTitle("coach.stage").navigationBarTitleDisplayMode(.inline)
    }
}
