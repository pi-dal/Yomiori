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
    private var observation: PlaybackObservation?

    func load(_ url: URL) {
        stop()
        time = 0; duration = 0
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        let token = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self, weak p] t in
            MainActor.assumeIsolated {
                guard let self, let p, self.player === p else { return }
                if t.seconds.isFinite { self.time = t.seconds }
                self.playing = p.rate != 0
                if self.duration == 0, let d = p.currentItem?.duration.seconds, d.isFinite { self.duration = d }
            }
        }
        observation = PlaybackObservation(player: p, token: token)
    }
    func toggle() { guard let p = player else { return }; if p.rate == 0 { p.rate = rate } else { p.pause() }; playing = p.rate != 0 }
    func seek(_ t: Double, play: Bool = false) {
        guard t.isFinite, t <= Subtitles.maximumTime else { return }
        player?.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        time = max(0, t)
        if play { player?.rate = rate; playing = true }
    }
    func setRate(_ r: Float) { rate = r; if player?.rate != 0 { player?.rate = r } }
    func stop() {
        player?.pause()
        observation = nil; player = nil; playing = false
    }
}

/// Own the token together with the player that issued it, including view teardown.
private final class PlaybackObservation {
    let player: AVPlayer
    let token: Any
    init(player: AVPlayer, token: Any) { self.player = player; self.token = token }
    deinit { player.removeTimeObserver(token) }
}
