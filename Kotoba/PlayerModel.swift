import Foundation
import AVFoundation
import Observation

@MainActor @Observable
final class PlayerModel {
    var time: Double = 0
    var duration: Double = 0
    var playing = false
    var rate: Float = 1
    private(set) var player: AVPlayer?
    private var observer: Any?

    func load(_ url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                if t.seconds.isFinite { self.time = t.seconds }
                self.playing = p.rate != 0
                if self.duration == 0, let d = p.currentItem?.duration.seconds, d.isFinite { self.duration = d }
            }
        }
    }
    func toggle() { guard let p = player else { return }; if p.rate == 0 { p.rate = rate } else { p.pause() }; playing = p.rate != 0 }
    func seek(_ t: Double, play: Bool = false) {
        guard t.isFinite else { return }
        player?.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        time = max(0, t)
        if play { player?.rate = rate; playing = true }
    }
    func setRate(_ r: Float) { rate = r; if player?.rate != 0 { player?.rate = r } }
    func stop() { player?.pause(); if let o = observer { player?.removeTimeObserver(o) }; observer = nil; player = nil }
}
