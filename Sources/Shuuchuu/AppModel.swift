import Foundation
import SwiftUI
import Combine

enum AppPage: String, CaseIterable {
    case focus, sounds, settings
}

/// Which tab of the Sounds page is active.
enum SoundsTab: String, Equatable { case sounds, mixes, soundtracks }

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
    let soundtracksFilter = SoundtracksFilterState()
    let soundtrackController: WebSoundtrackControlling
    let scenes: ScenesLibrary
    /// Optional because tests construct `AppModel` without wiring a Metal
    /// renderer — they don't render UI. Production always supplies one;
    /// `ShuuchuuApp.live` aborts startup if `ShaderRenderer()` returns nil.
    let shaderRenderer: ShaderRenderer?
    let scene: SceneController
    let license: LicenseController
    let updates: UpdateChecker
    private let defaults: UserDefaults

    @Published var page: AppPage = .focus
    @Published var soundsTab: SoundsTab = .sounds
    @Published var saveMode: SaveMode = .inactive
    @Published private(set) var currentlyLoadedMixId: AnyHashable?
    @Published var mode: AudioMode = .idle { didSet { persistMode() } }
    /// Most recently active soundtrack id, retained when the user flips to mix
    /// mode so a "Switch to soundtrack" link can resume it. Persisted so the
    /// link survives relaunch.
    @Published private(set) var lastSoundtrackId: WebSoundtrack.ID? {
        didSet { persistLastSoundtrackId() }
    }
    /// Tracks whether the active soundtrack is currently paused. Mirrors the bridge.
    /// In mix mode this property is unused — `state.anyPlaying` is the source of truth.
    @Published private(set) var soundtrackPaused: Bool = true
    @Published var signInRequired: Bool = false
    @Published var soundtrackError: (id: WebSoundtrack.ID, code: Int)? = nil

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
        scenes: ScenesLibrary,
        shaderRenderer: ShaderRenderer?,
        scene: SceneController,
        license: LicenseController,
        updates: UpdateChecker,
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
        self.scenes = scenes
        self.shaderRenderer = shaderRenderer
        self.scene = scene
        self.license = license
        self.updates = updates
        self.defaults = defaults
        self.mixer.masterVolume = prefs.volume

        // Boot license state synchronously — must happen before the soundtrack
        // restore check below (which reads `license.isUnlocked`) and before any
        // SwiftUI surface reads `model.license.state`.
        license.startTrialIfNeeded()

        // Restore persisted mode (defaults to .idle if anything is missing).
        if let data = defaults.data(forKey: "shuuchuu.audioMode"),
           let restored = try? JSONDecoder().decode(AudioMode.self, from: data) {
            // If the persisted mode references a soundtrack id that's no longer in the
            // library, fall back to .idle (per spec §7).
            if case .soundtrack(let id) = restored, soundtracksLibrary.entry(id: id) == nil {
                self.mode = .idle
            } else {
                self.mode = restored
            }
        }

        // Restore last-soundtrack target (for the "Switch to soundtrack" link).
        // If invalid, fall back to the active soundtrack id (if any).
        if let str = defaults.string(forKey: "shuuchuu.lastSoundtrackId"),
           let id = UUID(uuidString: str),
           soundtracksLibrary.entry(id: id) != nil {
            self.lastSoundtrackId = id
        } else if case .soundtrack(let id) = self.mode {
            self.lastSoundtrackId = id
        }

        // If we restored a soundtrack mode, prime the controller paused so the
        // user can hit play without re-activating from the list. Skip while locked —
        // the LockedView covers Focus and we don't want a hidden web view fetching
        // a YouTube/Spotify page behind it.
        if case .soundtrack(let id) = mode,
           let entry = soundtracksLibrary.entry(id: id),
           license.isUnlocked {
            soundtrackController.load(entry, autoplay: false)
            soundtrackPaused = true
        }

        // Title updates from the bridge persist back to the library.
        soundtrackController.onTitleChange = { [weak self] id, title in
            self?.soundtracksLibrary.setTitle(id: id, title: title)
        }

        soundtrackController.onSignInRequired = { [weak self] _ in
            self?.signInRequired = true
        }

        soundtrackController.onPlaybackError = { [weak self] id, code in
            self?.soundtrackError = (id, code)
        }

        // Auto break/focus transitions mirror to whichever audio source is active.
        // Pause when leaving focus; resume when entering focus. (The user's manual
        // ring-tap takes a separate path — see FocusPage.ringTap.)
        session.onPhaseChange = { [weak self] phase in
            guard let self = self else { return }
            switch phase {
            case .focus:                        self.pauseActiveSource(false)
            case .shortBreak, .longBreak:       self.pauseActiveSource(true)
            }
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

    // MARK: - License gate

    /// Centralised entitlement check used by every gated user-action method.
    private var isLicensed: Bool { license.isUnlocked }

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

    /// True iff the active source (mix or soundtrack) is currently inaudible.
    /// `.idle` returns `true` (nothing is playing).
    var activeSourcePaused: Bool {
        switch mode {
        case .idle:                return true
        case .mix:                 return !state.anyPlaying
        case .soundtrack:          return soundtrackPaused
        }
    }

    /// All tracks flattened across catalog categories.
    var allTracks: [(track: Track, categoryId: String)] {
        categories.flatMap { cat in
            cat.tracks.map { t in (t, cat.id) }
        }
    }

    // MARK: - Mix mutations (route through MixState, then drive reconcile)

    /// Called by every mix-shaped mutation. If we were in soundtrack mode, pause the
    /// soundtrack (web view retained — per spec §2.4) and flip mode. Idempotent for `.mix`.
    private func enterMixMode() {
        if case .soundtrack = mode {
            soundtrackController.setPaused(true)
            soundtrackPaused = true
        }
        if mode != .mix {
            mode = .mix
        }
    }

    func toggleTrack(_ track: Track) {
        guard isLicensed else { return }
        if state.contains(track.id) {
            state.remove(id: track.id)
        } else {
            state.append(id: track.id, volume: 0.5)
        }
        if !state.isEmpty { enterMixMode() } else if mode == .mix { mode = .idle }
        mixer.reconcileNow()
    }

    func setTrackVolume(_ trackId: String, _ v: Float) {
        guard isLicensed else { return }
        state.setVolume(id: trackId, volume: v)
        // Fast path: volume drags hit this 60Hz. A full reconcile would walk the
        // mix twice per tick; setTrackVolume writes the trackMixer directly.
        mixer.setTrackVolume(trackId, v)
        // Volume changes don't change mode — only structural changes do.
    }

    func removeTrack(_ trackId: String) {
        state.remove(id: trackId)
        if state.isEmpty, mode == .mix { mode = .idle }
        mixer.reconcileNow()
    }

    func togglePause(trackId: String) {
        guard isLicensed else { return }
        state.togglePaused(id: trackId)
        mixer.reconcileNow()
    }

    /// Pause or resume whichever source is active. No-op in `.idle`.
    func pauseActiveSource(_ paused: Bool) {
        guard isLicensed else { return }
        switch mode {
        case .idle:
            return
        case .mix:
            state.setAllPaused(paused)
            mixer.reconcileNow()
        case .soundtrack:
            soundtrackController.setPaused(paused)
            soundtrackPaused = paused
        }
    }

    func togglePlayAll() {
        guard isLicensed else { return }
        pauseActiveSource(!activeSourcePaused)
    }

    func applyPreset(_ preset: Preset) {
        guard isLicensed else { return }
        let newTracks = preset.mix
            .filter { $0.value >= 0.02 }
            .map { MixTrack(id: $0.key, volume: $0.value, paused: false) }
        state.replace(with: newTracks)
        if !newTracks.isEmpty { enterMixMode() }
        mixer.reconcileNow()
    }

    func applySavedMix(_ mix: SavedMix) {
        guard isLicensed else { return }
        let newTracks = mix.tracks.filter { $0.volume >= 0.02 }
        state.replace(with: newTracks)
        if !newTracks.isEmpty { enterMixMode() }
        mixer.reconcileNow()
    }

    func clearMix() {
        state.clear()
        if mode == .mix { mode = .idle }
        mixer.reconcileNow()
    }

    // MARK: - Save mix flow

    func beginSaveMix() {
        guard isLicensed else { return }
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
        guard isLicensed else { return .failure(.unsupportedHost) }
        switch SoundtrackURL.parse(rawURL) {
        case .failure(let err):
            return .failure(err)
        case .success(let parsed):
            let entry = soundtracksLibrary.add(parsed: parsed)
            fetchYouTubeTitleIfNeeded(for: entry)
            switch mode {
            case .idle, .soundtrack:
                activateSoundtrack(id: entry.id)
            case .mix:
                // User added a soundtrack while keeping the mix running — make
                // it the target of the "Switch to soundtrack" link.
                lastSoundtrackId = entry.id
            }
            return .success(entry)
        }
    }

    /// Fire-and-forget oEmbed lookup so YouTube entries get a real title before
    /// the bridge fires `titleChanged` (which only happens after playback starts).
    private func fetchYouTubeTitleIfNeeded(for entry: WebSoundtrack) {
        guard let videoId = entry.youtubeVideoId,
              let url = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoId)&format=json") else { return }
        Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let title = json["title"] as? String else { return }
                self?.soundtracksLibrary.setTitle(id: entry.id, title: title)
            } catch {}
        }
    }

    func activateSoundtrack(id: UUID) {
        guard isLicensed else { return }
        guard let entry = soundtracksLibrary.entry(id: id) else { return }
        if case .soundtrack(let current) = mode, current == id { return }     // idempotent

        // Pause the mix (preserves per-track state — the user can switch back via
        // the "Switch to mix" link on Focus).
        if mode == .mix {
            state.setAllPaused(true)
            mixer.reconcileNow()
        }

        mode = .soundtrack(id)
        lastSoundtrackId = id
        soundtrackError = nil
        soundtrackController.load(entry, autoplay: true)
        soundtrackPaused = false
    }

    func deactivateSoundtrack() {
        guard case .soundtrack = mode else { return }
        soundtrackController.setPaused(true)
        soundtrackPaused = true
        mode = .idle
    }

    /// Triggered by the "Switch to mix" link on the Focus page when in `.soundtrack`.
    /// Pauses the soundtrack, flips to mix mode, and resumes the previously-paused mix.
    func switchToMix() {
        guard case .soundtrack = mode else { return }
        soundtrackController.setPaused(true)
        soundtrackPaused = true
        mode = .mix
        state.setAllPaused(false)
        mixer.reconcileNow()
    }

    /// Triggered by the "Switch to soundtrack" link on the Focus page when in `.mix`.
    /// Mirror of `switchToMix`: pauses the mix and activates the most recently used
    /// soundtrack. No-op if `lastSoundtrackId` no longer resolves.
    func switchToSoundtrack() {
        guard isLicensed else { return }
        guard mode == .mix,
              let id = lastSoundtrackId,
              soundtracksLibrary.entry(id: id) != nil else { return }
        activateSoundtrack(id: id)
    }

    func removeSoundtrack(id: UUID) {
        let wasActive = (mode == .soundtrack(id))
        soundtracksLibrary.remove(id: id)
        if wasActive {
            soundtrackController.unload()
            mode = .idle
        }
        if lastSoundtrackId == id {
            lastSoundtrackId = nil
        }
    }

    func setSoundtrackVolume(id: UUID, volume: Double) {
        soundtracksLibrary.setVolume(id: id, volume: volume)
        if case .soundtrack(let active) = mode, active == id {
            soundtrackController.setVolume(volume)
        }
    }

    func setSoundtrackTags(id: UUID, tags: [String]) {
        soundtracksLibrary.setTags(id: id, tags: tags)
    }

    private func persistMode() {
        guard let data = try? JSONEncoder().encode(mode) else { return }
        defaults.set(data, forKey: "shuuchuu.audioMode")
    }

    private func persistLastSoundtrackId() {
        if let id = lastSoundtrackId {
            defaults.set(id.uuidString, forKey: "shuuchuu.lastSoundtrackId")
        } else {
            defaults.removeObject(forKey: "shuuchuu.lastSoundtrackId")
        }
    }

    // MARK: - Navigation

    func goTo(_ page: AppPage) {
        withAnimation(.smooth(duration: 0.32)) { self.page = page }
    }

    // MARK: - Updates

    func triggerUpdateCheck() {
        updates.checkForUpdates()
    }

    // MARK: - Lifecycle

    private var didLaunch = false

    func handleLaunch() async {
        guard !didLaunch else { return }
        didLaunch = true
        // License state was bootstrapped synchronously in init; revalidate now if licensed.
        if case .licensed = license.state {
            Task { await license.revalidate() }
        }
        updates.startIfNeeded()
        await loadCatalog()
        // No restore step — MixState loaded itself from UserDefaults at init.
        // MixingController has already begun reconciling against it.
    }

    func handleSleep() async {
        mixer.stopAll()
        // Flush any debounced persist so a mid-drag volume isn't lost on sleep.
        state.flushPersist()
        // Push the in-memory wall-clock floor to keychain so a relaunch after
        // sleep can detect clock rollback. (License timer doesn't persist on
        // every tick — see LicenseStorage.lastSeenWallclock.)
        license.flushPersist()
        session.pause()
    }

    func handleWake() async { /* no auto-resume for v2 flow */ }
}

