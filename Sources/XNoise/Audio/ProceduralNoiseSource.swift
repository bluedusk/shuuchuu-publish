import AVFoundation

final class ProceduralNoiseSource: NoiseSource {
    let id: String
    let displayName: String
    let node: AVAudioNode
    var isReady: Bool { true }

    init(variant: ProceduralVariant, id: String, displayName: String, sampleRate: Double = 48000) {
        self.id = id
        self.displayName = displayName

        let box = RendererBox(renderer: Self.makeRenderer(variant: variant, sampleRate: sampleRate))

        self.node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for bufferIdx in 0..<abl.count {
                guard let ptr = abl[bufferIdx].mData?.assumingMemoryBound(to: Float.self) else { continue }
                if bufferIdx == 0 {
                    box.render(into: ptr, frameCount: Int(frameCount))
                } else {
                    guard let src = abl[0].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for i in 0..<Int(frameCount) { ptr[i] = src[i] }
                }
            }
            return noErr
        }
    }

    func prepare() async throws { /* no-op */ }

    private static func makeRenderer(variant: ProceduralVariant, sampleRate: Double) -> any NoiseRenderer {
        switch variant {
        case .white: return WhiteNoiseRenderer()
        case .pink:  return PinkNoiseRenderer()
        case .brown: return BrownNoiseRenderer()
        case .green: return GreenNoiseRenderer(sampleRate: sampleRate)
        case .fluorescent: return FluorescentHumRenderer(sampleRate: sampleRate)
        }
    }
}

private final class RendererBox: @unchecked Sendable {
    private var renderer: any NoiseRenderer
    init(renderer: any NoiseRenderer) { self.renderer = renderer }
    func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        renderer.render(into: buffer, frameCount: frameCount)
    }
}
