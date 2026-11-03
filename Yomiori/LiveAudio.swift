import AVFoundation

@MainActor protocol LiveAudioIO: AnyObject {
    func start() async throws -> AsyncThrowingStream<Data, Error>
    func play(_ pcm: Data) throws
    func interrupt()
    func stop()
    var isPlaying: Bool { get }
    var playbackFinished: (() -> Void)? { get set }
}

/// One voice-processing engine provides echo cancellation and full-duplex audio.
@MainActor final class LiveAudio: LiveAudioIO {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var pendingSamples = 0
    private var playbackGeneration = UUID()
    private var tapInstalled = false
    private var ownsSession = false
    private static let sessionQueue = DispatchQueue(label: "Yomiori.live.audio-session", qos: .userInitiated)
    var isPlaying: Bool { pendingSamples > 0 }
    var playbackFinished: (() -> Void)?
    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

    func start() async throws -> AsyncThrowingStream<Data, Error> {
        #if targetEnvironment(simulator)
        // CoreSimulator's RemoteIO can abort inside Apple audio RPC before returning an error.
        throw LiveError.simulator
        #else
        guard await AVAudioApplication.requestRecordPermission() else { throw LiveError.microphone }
        try Task.checkCancellation()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.sessionQueue.async {
                do { try session.setActive(true); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
        ownsSession = true
        do {
            try Task.checkCancellation()
            let engine = AVAudioEngine(), player = AVAudioPlayerNode()
            self.engine = engine; self.player = player
            try engine.inputNode.setVoiceProcessingEnabled(true)
            engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0,
                  let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: inputFormat, to: target) else { throw LiveError.audio }
            let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
            let continuation = pair.continuation
            self.continuation = continuation
            engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
                let frames = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / inputFormat.sampleRate + 8)
                guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frames) else { return }
                var supplied = false, failure: NSError?
                let status = converter.convert(to: output, error: &failure) { _, state in
                    if supplied { state.pointee = .noDataNow; return nil }
                    supplied = true; state.pointee = .haveData; return buffer
                }
                guard failure == nil, status != .error, let samples = output.int16ChannelData else {
                    continuation.finish(throwing: LiveError.audio); return
                }
                let data = Data(bytes: samples[0], count: Int(output.frameLength) * 2)
                guard !data.isEmpty else { return }
                if case .dropped = continuation.yield(data) { continuation.finish(throwing: LiveError.overloaded) }
            }
            tapInstalled = true
            engine.prepare(); try engine.start(); player.play()
            return pair.stream
        } catch { stop(); throw error }
        #endif
    }
    func play(_ pcm: Data) throws {
        guard !pcm.isEmpty, pcm.count.isMultiple(of: 2), pcm.count <= 480_000,
              let player, engine?.isRunning == true else { throw LiveError.audio }
        let count = pcm.count / 2
        guard pendingSamples + count <= 24_000 * 30 else { throw LiveError.overloaded }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0] else { throw LiveError.audio }
        buffer.frameLength = AVAudioFrameCount(count)
        pcm.withUnsafeBytes { raw in
            for index in 0..<count {
                channel[index] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))) / 32768
            }
        }
        let generation = playbackGeneration
        pendingSamples += count
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                self.pendingSamples -= count
                if self.pendingSamples == 0 { self.playbackFinished?() }
            }
        }
        if !player.isPlaying { player.play() }
    }
    func interrupt() {
        playbackGeneration = UUID(); pendingSamples = 0
        player?.stop()
    }
    func stop() {
        continuation?.finish(); continuation = nil
        interrupt()
        if let engine {
            if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
            engine.stop(); player = nil; self.engine = nil
        }
        if ownsSession {
            ownsSession = false
            Self.sessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
}
