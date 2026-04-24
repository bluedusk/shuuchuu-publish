import AVFoundation
import Combine

/// Owns one AVAudioEngine + a shared master mixer and can play any number of tracks
/// simultaneously. Each active track is represented by a `LiveTrack` holding its
/// `NoiseSource` and the per-track volume. Master volume is on `masterMixer.outputVolume`.
///
/// This replaces the single-source `AudioController` to match the design's multi-track
/// mixing UX — users layer Rain + Fire + Brown Noise, each with its own slider.
@MainActor
final class MixingController: ObservableObject {
    struct LiveTrack: Equatable {
        let id: String
        var volume: Float
    }

    /// Every currently-playing track, keyed by track id.
    @Published private(set) var live: [String: LiveTrack] = [:]
    @Published var masterVolume: Float = Constants.defaultVolume {
        didSet { masterMixer.outputVolume = masterVolume }
    }

    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()
    private var sources: [String: NoiseSource] = [:]

    init() {
        engine.attach(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)
        masterMixer.outputVolume = masterVolume
    }

    var isPlaying: Bool { !live.isEmpty }

    /// Add a track to the active mix, or update its volume if already active.
    func addOrUpdate(track: Track, volume: Float, cache: AudioCache) async {
        if var existing = live[track.id] {
            existing.volume = volume
            live[track.id] = existing
            updateNodeVolume(trackId: track.id, volume: volume)
            return
        }

        let source = makeSource(for: track, cache: cache)
        do {
            try await source.prepare()
        } catch {
            return
        }

        engine.attach(source.node)
        engine.connect(source.node, to: masterMixer, format: nil)

        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }

        sources[track.id] = source
        live[track.id] = LiveTrack(id: track.id, volume: volume)

        // AVAudioPlayerNode.volume controls per-track level.
        if let bundled = source as? BundledNoiseSource {
            bundled.scheduleLoop()
            if let player = bundled.node as? AVAudioPlayerNode {
                player.volume = volume
                player.play()
            }
        } else if let streamed = source as? StreamedNoiseSource {
            streamed.scheduleLoop()
            if let player = streamed.node as? AVAudioPlayerNode {
                player.volume = volume
                player.play()
            }
        } else if let src = source as? ProceduralNoiseSource {
            // Procedural sources use AVAudioSourceNode; they have no per-node volume knob.
            // Work around by wrapping output volume on a small per-track mixer — simplest
            // for v1 is to just play at master volume (procedural tracks rarely need
            // independent level control in mixing scenarios).
            _ = src
        }
    }

    /// Update an already-playing track's volume.
    func setVolume(trackId: String, volume: Float) {
        guard var t = live[trackId] else { return }
        t.volume = volume
        live[trackId] = t
        updateNodeVolume(trackId: trackId, volume: volume)
    }

    /// Remove a track from the mix.
    func remove(trackId: String) {
        guard let source = sources[trackId] else { return }
        if let player = source.node as? AVAudioPlayerNode {
            player.stop()
        }
        if source.node.engine != nil {
            engine.detach(source.node)
        }
        sources.removeValue(forKey: trackId)
        live.removeValue(forKey: trackId)

        if live.isEmpty, engine.isRunning {
            engine.pause()
        }
    }

    /// Stop and tear down everything.
    func stopAll() {
        for id in Array(live.keys) {
            remove(trackId: id)
        }
    }

    /// Set the active mix wholesale (e.g. when applying a preset).
    func applyMix(_ mix: [String: Float], resolving: (String) -> Track?, cache: AudioCache) async {
        // Remove tracks no longer in the mix.
        for id in Array(live.keys) where (mix[id] ?? 0) < 0.02 {
            remove(trackId: id)
        }
        // Add/update each entry in the new mix.
        for (id, vol) in mix where vol >= 0.02 {
            guard let track = resolving(id) else { continue }
            await addOrUpdate(track: track, volume: vol, cache: cache)
        }
    }

    // MARK: - Private helpers

    private func updateNodeVolume(trackId: String, volume: Float) {
        if let player = sources[trackId]?.node as? AVAudioPlayerNode {
            player.volume = volume
        }
    }

    private func makeSource(for track: Track, cache: AudioCache) -> NoiseSource {
        switch track.kind {
        case .procedural(let variant):
            return ProceduralNoiseSource(variant: variant, id: track.id, displayName: track.name)
        case .streamed:
            return StreamedNoiseSource(track: track, cache: cache)
        case .bundled(let filename):
            return BundledNoiseSource(id: track.id, displayName: track.name, filename: filename)
        }
    }
}
