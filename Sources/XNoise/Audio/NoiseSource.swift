import AVFoundation

protocol NoiseSource: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var node: AVAudioNode { get }
    var isReady: Bool { get }
    func prepare() async throws
}
