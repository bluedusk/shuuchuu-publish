import AVFoundation

protocol NoiseSource: AnyObject, Sendable {
    var id: String { get }
    var displayName: String { get }
    var node: AVAudioNode { get }
    var isReady: Bool { get }
    /// PCM format the node outputs. Used by MixingController to format-match the
    /// node→trackMixer connection — `nil` defers to the engine's auto-detection.
    var audioFormat: AVAudioFormat? { get }
    func prepare() async throws
    /// Begin producing audio. Called once after the source has been attached and
    /// connected, before any unpause. Default no-op for sources that produce audio
    /// passively (e.g. AVAudioSourceNode-backed) — only AVAudioPlayerNode-backed
    /// sources need to schedule + play().
    func start()
    /// Stop producing audio (terminal). Called by MixingController on detach.
    func stop()
}

extension NoiseSource {
    func start() {}
    func stop() {}
}
