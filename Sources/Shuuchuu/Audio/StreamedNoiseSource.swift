import AVFoundation

final class StreamedNoiseSource: NoiseSource, @unchecked Sendable {
    let id: String
    let displayName: String
    let node: AVAudioNode

    private let track: Track
    private let cache: AudioCache
    private var buffer: AVAudioPCMBuffer?
    private(set) var isReady: Bool = false

    var audioFormat: AVAudioFormat? { buffer?.format }

    init(track: Track, cache: AudioCache) {
        self.id = track.id
        self.displayName = track.name
        self.track = track
        self.cache = cache
        self.node = AVAudioPlayerNode()
    }

    func prepare() async throws {
        guard case .streamed(let info) = track.kind else {
            // StreamedNoiseSource only ever receives streamed tracks — a non-
            // streamed Track here would be a wiring bug in `MixingController`.
            assertionFailure("StreamedNoiseSource initialized with non-streamed track \(track.id)")
            return
        }
        let localURL = try await cache.localURL(for: info)
        let file = try AVAudioFile(forReading: localURL)
        let buf = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: buf)
        self.buffer = buf
        self.isReady = true
    }

    func scheduleLoop() {
        guard let player = node as? AVAudioPlayerNode, let buf = buffer else { return }
        player.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
    }

    func start() {
        guard let player = node as? AVAudioPlayerNode else { return }
        scheduleLoop()
        player.play()
    }

    func stop() {
        (node as? AVAudioPlayerNode)?.stop()
    }
}
