import AVFoundation
import Combine

@MainActor
final class AudioController: ObservableObject {
    enum State: Equatable {
        case idle
        case loading(String)
        case playing(String)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published var volume: Float = Constants.defaultVolume {
        didSet { mixer.outputVolume = volume }
    }

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var current: NoiseSource?

    init() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        mixer.outputVolume = volume
    }

    func play(_ source: NoiseSource) async {
        state = .loading(source.id)
        do {
            try await source.prepare()
        } catch {
            state = .error("Failed to prepare: \(error.localizedDescription)")
            return
        }

        if let old = current, old.node.engine != nil {
            engine.detach(old.node)
        }

        engine.attach(source.node)
        engine.connect(source.node, to: mixer, format: nil)

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                state = .error("Engine start failed: \(error.localizedDescription)")
                return
            }
        }

        mixer.outputVolume = 0
        if let streamed = source as? StreamedNoiseSource {
            streamed.scheduleLoop()
            (streamed.node as? AVAudioPlayerNode)?.play()
        }

        await fade(from: 0, to: volume, durationMs: Constants.fadeInMs)
        current = source
        state = .playing(source.id)
    }

    func stop() async {
        guard state != .idle else { return }
        await fade(from: mixer.outputVolume, to: 0, durationMs: Constants.fadeOutMs)
        (current?.node as? AVAudioPlayerNode)?.stop()
        if engine.isRunning {
            engine.pause()
        }
        state = .idle
    }

    private func fade(from: Float, to: Float, durationMs: Double) async {
        let steps = 20
        let stepMs = durationMs / Double(steps)
        let stepDelta = (to - from) / Float(steps)
        for i in 0...steps {
            mixer.outputVolume = from + stepDelta * Float(i)
            try? await Task.sleep(nanoseconds: UInt64(stepMs * 1_000_000))
        }
        mixer.outputVolume = to
    }
}
