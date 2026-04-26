import AVFoundation

/// Audio engine reconciler. Observes `MixState` and makes the running `AVAudioEngine`
/// reflect what the mix list says — attaching new tracks, detaching removed ones,
/// and syncing per-track volume/pause.
///
/// **Topology:** every source gets its own `AVAudioMixerNode`:
/// `source.node → trackMixer → masterMixer → engine.mainMixerNode`.
/// Per-track volume and per-track pause are uniform: `trackMixer.outputVolume`
/// (set to the per-track volume, or to 0 when paused). This works for any source
/// kind — `AVAudioPlayerNode`-backed (bundled/streamed) and `AVAudioSourceNode`-
/// backed (procedural) alike.
///
/// **Reconcile contract:** mutating `MixState` is the only way to change what the
/// audio engine plays. Direct calls into this controller (`pauseAll`, `resumeAll`,
/// `setMasterVolume`) only configure engine-level state, not mix membership.
@MainActor
final class MixingController: ObservableObject {
    @Published var masterVolume: Float = Constants.defaultVolume {
        didSet { masterMixer.outputVolume = masterVolume }
    }

    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()

    private let state: MixState
    private let cache: AudioCache
    private let resolveTrack: (String) -> Track?

    private struct AttachedTrack {
        let source: NoiseSource
        let trackMixer: AVAudioMixerNode
        var started: Bool
    }
    private var attached: [String: AttachedTrack] = [:]
    private var attaching: Set<String> = []

    init(state: MixState, cache: AudioCache, resolveTrack: @escaping (String) -> Track?) {
        self.state = state
        self.cache = cache
        self.resolveTrack = resolveTrack

        engine.attach(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)
        masterMixer.outputVolume = masterVolume

        // No Combine subscriptions — the controller is driven explicitly via
        // `reconcileNow()` from AppModel after every state mutation. Direct calls are
        // simpler to reason about than @Published+sink+MainActor isolation.
    }

    /// Trigger a reconcile pass. Public so callers (e.g. `AppModel`) can re-trigger
    /// after the catalog loads — saved track ids can't resolve to `Track` objects until
    /// the catalog is available, so the initial reconcile at init time is a no-op for
    /// any track whose catalog entry hasn't arrived yet.
    func reconcileNow() { reconcile() }

    /// Apply the current `MixState.tracks` to the audio engine: attach new tracks,
    /// detach removed ones, and sync per-track volume/pause for the rest.
    private func reconcile() {
        let stateIDs = Set(state.tracks.map(\.id))

        // Detach what's no longer in the mix.
        for id in Array(attached.keys) where !stateIDs.contains(id) {
            detach(id: id)
        }

        // Attach new + sync existing.
        for mixTrack in state.tracks {
            if let entry = attached[mixTrack.id] {
                applyVolume(entry: entry, mixTrack: mixTrack)
            } else if !attaching.contains(mixTrack.id) {
                attaching.insert(mixTrack.id)
                Task { await attachSource(for: mixTrack.id) }
            }
            // If already attaching, the next reconcile (triggered when attach completes
            // by virtue of mutating engine state, or by any subsequent state change)
            // will sync volume.
        }

        reconcileEngineState()
    }

    /// Bring the engine running-state in line with intent: it should be running iff
    /// the mix is non-empty AND not master-paused. Also schedules deferred-start sources.
    private func reconcileEngineState() {
        let shouldRun = !attached.isEmpty && state.anyPlaying

        if shouldRun {
            if !engine.isRunning {
                try? engine.start()
            }
            // Start any sources we deferred starting (because the engine wasn't running
            // when they were attached). source.start() requires the engine to be running.
            for id in attached.keys where attached[id]?.started == false {
                attached[id]?.source.start()
                attached[id]?.started = true
            }
        } else {
            if engine.isRunning {
                engine.pause()
            }
        }
    }

    private func attachSource(for trackId: String) async {
        defer { attaching.remove(trackId) }

        guard let track = resolveTrack(trackId) else { return }
        let source = makeSource(for: track)
        do { try await source.prepare() } catch { return }

        // Mix may have changed during prep — bail if the track is no longer wanted
        // or if a parallel attach already won.
        guard state.contains(trackId), attached[trackId] == nil else { return }

        let trackMixer = AVAudioMixerNode()
        engine.attach(source.node)
        engine.attach(trackMixer)
        engine.connect(source.node, to: trackMixer, format: source.audioFormat)
        engine.connect(trackMixer, to: masterMixer, format: nil)

        let entry = AttachedTrack(source: source, trackMixer: trackMixer, started: false)
        if let mixTrack = state.track(trackId) {
            applyVolume(entry: entry, mixTrack: mixTrack)
        }
        attached[trackId] = entry

        reconcileEngineState()
    }

    private func detach(id: String) {
        guard let entry = attached.removeValue(forKey: id) else { return }
        if entry.started {
            entry.source.stop()
        }
        if entry.source.node.engine != nil {
            engine.detach(entry.source.node)
        }
        if entry.trackMixer.engine != nil {
            engine.detach(entry.trackMixer)
        }
    }

    private func applyVolume(entry: AttachedTrack, mixTrack: MixTrack) {
        entry.trackMixer.outputVolume = mixTrack.paused ? 0 : mixTrack.volume
    }

    /// Detach everything. Called on system sleep; survives across wake (reconcile
    /// re-attaches when state is touched).
    func stopAll() {
        for id in Array(attached.keys) {
            detach(id: id)
        }
        if engine.isRunning { engine.pause() }
    }

    private func makeSource(for track: Track) -> NoiseSource {
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
