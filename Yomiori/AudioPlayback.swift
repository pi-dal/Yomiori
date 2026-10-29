import SwiftUI
import AVFoundation

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
