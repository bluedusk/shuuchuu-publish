import AVFoundation

/// Plays a looping audio file shipped inside the app bundle.
///
/// Unlike `StreamedNoiseSource`, no network or cache is involved — the file is
/// decoded directly from `Bundle.module` on `prepare()`.
final class BundledNoiseSource: NoiseSource, @unchecked Sendable {
    let id: String
    let displayName: String
    let node: AVAudioNode

    private let filename: String
    private var buffer: AVAudioPCMBuffer?
    private(set) var isReady: Bool = false

    /// Source PCM format — used by MixingController to connect this player's
    /// output to the mixer with the right format conversion.
    var audioFormat: AVAudioFormat? { buffer?.format }

    enum BundledError: Error {
        case resourceMissing(String)
    }

    init(id: String, displayName: String, filename: String) {
        self.id = id
        self.displayName = displayName
        self.filename = filename
        self.node = AVAudioPlayerNode()
    }

    func prepare() async throws {
        let components = filename.split(separator: ".", maxSplits: 1).map(String.init)
        let name = components.first ?? filename
        let ext = components.count > 1 ? components[1] : ""

        let locations: [(subdir: String?, name: String, ext: String)] = [
            (subdir: "sounds", name: name, ext: ext),
            (subdir: nil, name: name, ext: ext),
        ]
        var fileURL: URL?
        for loc in locations {
            if let url = Bundle.module.url(forResource: loc.name, withExtension: loc.ext, subdirectory: loc.subdir) {
                fileURL = url
                break
            }
        }
        guard let fileURL else {
            throw BundledError.resourceMissing(filename)
        }

        let file = try AVAudioFile(forReading: fileURL)
        let buf = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: buf)
        self.buffer = buf
        self.isReady = true
    }

    /// Called by AudioController once the engine is running and the node is attached + connected.
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
