import AVFoundation

protocol NoiseSource: AnyObject, Sendable {
    var id: String { get }
    var displayName: String { get }
    var node: AVAudioNode { get }
    var isReady: Bool { get }
    func prepare() async throws
}
