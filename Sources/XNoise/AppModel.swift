import Foundation
import SwiftUI
import Combine

enum AppPage: String, CaseIterable {
    case focus, sounds, settings
}

/// Which tab of the Sounds page is active.
enum SoundsTab: String, Equatable { case sounds, mixes }

/// State machine for the inline save-mix flow.
enum SaveMode: Equatable {
    case inactive
    case naming(text: String)
    case confirmingOverwrite(text: String, existing: SavedMix)

    var isActive: Bool { self != .inactive }
}

/// Thin orchestrator. Owns the dependency graph and routes user intents to `MixState`
/// (which `MixingController` reconciles into audio). All mix mutations go through
/// `MixState` — `AppModel` doesn't touch the audio engine directly.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var categories: [Category] = []
    private var trackIndex: [String: Track] = [:]

    let catalog: Catalog
    let cache: AudioCache
    let state: MixState
    let mixer: MixingController

    let focusSettings: FocusSettings
    let session: FocusSession
    let design: DesignSettings
    let favorites: Favorites
    let prefs: Preferences
    let savedMixes: SavedMixes
    let soundtracksLibrary: SoundtracksLibrary
    let soundtrackController: WebSoundtrackControlling
    private let defaults: UserDefaults

    @Published var page: AppPage = .focus
    @Published var soundsTab: SoundsTab = .sounds
    @Published var saveMode: SaveMode = .inactive
    @Published private(set) var currentlyLoadedMixId: AnyHashable?
    @Published var mode: AudioMode = .idle { didSet { persistMode() } }

    init(
        catalog: Catalog,
        state: MixState,
        mixer: MixingController,
        cache: AudioCache,
        focusSettings: FocusSettings,
        session: FocusSession,
        design: DesignSettings,
        favorites: Favorites,
        prefs: Preferences,
        savedMixes: SavedMixes,
        soundtracksLibrary: SoundtracksLibrary,
        soundtrackController: WebSoundtrackControlling,
        defaults: UserDefaults = .standard
    ) {
        self.catalog = catalog
        self.state = state
        self.mixer = mixer
        self.cache = cache
        self.focusSettings = focusSettings
        self.session = session
        self.design = design
        self.favorites = favorites
        self.prefs = prefs
        self.savedMixes = savedMixes
        self.soundtracksLibrary = soundtracksLibrary
        self.soundtrackController = soundtrackController
        self.defaults = defaults
        self.mixer.masterVolume = prefs.volume

        // Restore persisted mode (defaults to .idle if anything is missing).
        if let data = defaults.data(forKey: "x-noise.audioMode"),
           let restored = try? JSONDecoder().decode(AudioMode.self, from: data) {
            // If the persisted mode references a soundtrack id that's no longer in the
            // library, fall back to .idle (per spec §7).
            if case .soundtrack(let id) = restored, soundtracksLibrary.entry(id: id) == nil {
                self.mode = .idle
            } else {
                self.mode = restored
            }
        }

        // Title updates from the bridge persist back to the library.
        soundtrackController.onTitleChange = { [weak self] id, title in
            self?.soundtracksLibrary.setTitle(id: id, title: title)
        }

        // Recompute the currently-loaded match whenever the active mix or the saved-mix
        // list changes. Per spec §11 — avoids per-frame allocations from view bodies.
        state.$tracks
            .combineLatest(savedMixes.$mixes)
            .map { tracks, mixes -> AnyHashable? in
                Self.matchLoadedMix(activeTracks: tracks, savedMixes: mixes)
            }
            .receive(on: RunLoop.main)
            .assign(to: &$currentlyLoadedMixId)
    }

    // MARK: - Catalog

    func loadCatalog() async {
        await catalog.refresh()
        if case .ready(let cats) = catalog.state {
            self.categories = cats
            self.trackIndex = Dictionary(uniqueKeysWithValues: cats.flatMap(\.tracks).map { ($0.id, $0) })
            // Saved tracks couldn't resolve before the catalog loaded — reconcile now
            // so the audio engine catches up to the restored MixState.
            mixer.reconcileNow()
        }
    }

    func findTrack(id: String) -> Track? { trackIndex[id] }

    /// All tracks flattened across catalog categories.
    var allTracks: [(track: Track, categoryId: String)] {
        categories.flatMap { cat in
            cat.tracks.map { t in (t, cat.id) }
        }
    }

    // MARK: - Mix mutations (route through MixState, then drive reconcile)

    func toggleTrack(_ track: Track) {
        if state.contains(track.id) {
            state.remove(id: track.id)
        } else {
            state.append(id: track.id, volume: 0.5)
        }
        mixer.reconcileNow()
    }

    func setTrackVolume(_ trackId: String, _ v: Float) {
        state.setVolume(id: trackId, volume: v)
        mixer.reconcileNow()
    }

    func removeTrack(_ trackId: String) {
        state.remove(id: trackId)
        mixer.reconcileNow()
    }

    func togglePause(trackId: String) {
        state.togglePaused(id: trackId)
        mixer.reconcileNow()
    }

    func togglePlayAll() {
        // If anything is playing, pause everything; else play everything.
        state.setAllPaused(state.anyPlaying)
        mixer.reconcileNow()
    }

    func applyPreset(_ preset: Preset) {
        let newTracks = preset.mix
            .filter { $0.value >= 0.02 }
            .map { MixTrack(id: $0.key, volume: $0.value, paused: false) }
        state.replace(with: newTracks)
        mixer.reconcileNow()
    }

    func applySavedMix(_ mix: SavedMix) {
        let newTracks = mix.tracks.filter { $0.volume >= 0.02 }
        state.replace(with: newTracks)
        mixer.reconcileNow()
    }

    func clearMix() {
        state.clear()
        mixer.reconcileNow()
    }

    // MARK: - Save mix flow

    func beginSaveMix() {
        guard !state.isEmpty else { return }
        saveMode = .naming(text: "")
    }

    func updateSaveName(_ text: String) {
        switch saveMode {
        case .naming:
            saveMode = .naming(text: text)
        case .confirmingOverwrite:
            // Editing the name from the conflict screen returns to plain naming mode.
            saveMode = .naming(text: text)
        case .inactive:
            return
        }
    }

    func commitSaveMix() {
        guard case .naming(let raw) = saveMode else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = savedMixes.save(name: trimmed, tracks: state.tracks)
        switch result {
        case .saved:
            saveMode = .inactive
        case .duplicate(let existing):
            saveMode = .confirmingOverwrite(text: trimmed, existing: existing)
        }
    }

    func overwriteExisting() {
        guard case .confirmingOverwrite(_, let existing) = saveMode else { return }
        savedMixes.overwrite(id: existing.id, tracks: state.tracks)
        saveMode = .inactive
    }

    func saveAsNewWithSuffix() {
        guard case .confirmingOverwrite(let text, _) = saveMode else { return }
        savedMixes.saveWithUniqueSuffix(baseName: text, tracks: state.tracks)
        saveMode = .inactive
    }

    func cancelSaveMix() {
        saveMode = .inactive
    }

    func deleteMix(id: UUID) {
        savedMixes.delete(id: id)
    }

    // MARK: - Currently-loaded helper

    /// Pure helper: returns the id of the saved mix or preset whose track-id set matches
    /// the active mix's track-id set. Volume + ordering are ignored. nil if no match.
    private static func matchLoadedMix(activeTracks: [MixTrack],
                                       savedMixes: [SavedMix]) -> AnyHashable? {
        guard !activeTracks.isEmpty else { return nil }
        let active = Set(activeTracks.map(\.id))
        if let m = savedMixes.first(where: { Set($0.tracks.map(\.id)) == active }) {
            return AnyHashable(m.id)
        }
        if let p = Presets.all.first(where: { Set($0.mix.keys) == active }) {
            return AnyHashable(p.id)
        }
        return nil
    }

    // MARK: - Master volume

    func setMasterVolume(_ v: Float) {
        mixer.masterVolume = v
        prefs.volume = v
    }

    // MARK: - Soundtracks

    /// Add a soundtrack to the library by parsing the raw URL. From `.idle` or
    /// `.soundtrack(other)` we auto-activate the new entry (the user just expressed
    /// intent to play something). From `.mix` we leave the mix alone.
    func addSoundtrack(rawURL: String) -> Result<WebSoundtrack, AddSoundtrackError> {
        switch SoundtrackURL.parse(rawURL) {
        case .failure(let err):
            return .failure(err)
        case .success(let parsed):
            let entry = soundtracksLibrary.add(parsed: parsed)
            switch mode {
            case .idle, .soundtrack:
                activateSoundtrack(id: entry.id)
            case .mix:
                break
            }
            return .success(entry)
        }
    }

    func activateSoundtrack(id: UUID) {
        guard let entry = soundtracksLibrary.entry(id: id) else { return }
        if case .soundtrack(let current) = mode, current == id { return }     // idempotent

        // Side effect on the mix is added in Task 6. For now, just transition mode.
        mode = .soundtrack(id)
        soundtrackController.load(entry, autoplay: true)
    }

    func deactivateSoundtrack() {
        guard case .soundtrack = mode else { return }
        soundtrackController.setPaused(true)
        mode = .idle
    }

    func removeSoundtrack(id: UUID) {
        let wasActive = (mode == .soundtrack(id))
        soundtracksLibrary.remove(id: id)
        if wasActive {
            soundtrackController.unload()
            mode = .idle
        }
    }

    func setSoundtrackVolume(id: UUID, volume: Double) {
        soundtracksLibrary.setVolume(id: id, volume: volume)
        if case .soundtrack(let active) = mode, active == id {
            soundtrackController.setVolume(volume)
        }
    }

    private func persistMode() {
        guard let data = try? JSONEncoder().encode(mode) else { return }
        defaults.set(data, forKey: "x-noise.audioMode")
    }

    // MARK: - Navigation

    func goTo(_ page: AppPage) {
        withAnimation(.smooth(duration: 0.32)) { self.page = page }
    }

    // MARK: - Lifecycle

    private var didLaunch = false

    func handleLaunch() async {
        guard !didLaunch else { return }
        didLaunch = true
        await loadCatalog()
        // No restore step — MixState loaded itself from UserDefaults at init.
        // MixingController has already begun reconciling against it.
    }

    func handleSleep() async {
        mixer.stopAll()
        session.pause()
    }

    func handleWake() async { /* no auto-resume for v2 flow */ }
}

