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

    @Published var page: AppPage = .focus
    @Published var categoryFilter: CategoryFilter = .all
    @Published var soundsTab: SoundsTab = .sounds
    @Published var saveMode: SaveMode = .inactive

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
        savedMixes: SavedMixes
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
        self.mixer.masterVolume = prefs.volume
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

    /// All tracks flattened across catalog categories, paired with their pill filter.
    var allTracks: [(track: Track, filter: CategoryFilter)] {
        categories.flatMap { cat in
            cat.tracks.map { t in (t, CategoryFilter.category(for: t.id, fallback: cat.id)) }
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
        _ = savedMixes.saveWithUniqueSuffix(baseName: text, tracks: state.tracks)
        saveMode = .inactive
    }

    func cancelSaveMix() {
        saveMode = .inactive
    }

    func deleteMix(id: UUID) {
        savedMixes.delete(id: id)
    }

    // MARK: - Currently-loaded helper

    /// Returns the id (UUID for SavedMix or String for Preset) of the mix whose track-id set
    /// matches the current MixState. Volume differences and ordering are ignored. Nil if no
    /// match (or the active mix is empty).
    var currentlyLoadedMixId: AnyHashable? {
        guard !state.tracks.isEmpty else { return nil }
        let active = Set(state.tracks.map(\.id))
        if let m = savedMixes.mixes.first(where: { Set($0.tracks.map(\.id)) == active }) {
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

/// Sound filter categories used by the Sounds page pills.
enum CategoryFilter: String, CaseIterable, Equatable {
    case all, favorites, weather, water, nature, ambient, noise

    var display: String {
        switch self {
        case .all: return "All"
        case .favorites: return "★ Favs"
        case .weather: return "Weather"
        case .water: return "Water"
        case .nature: return "Nature"
        case .ambient: return "Ambient"
        case .noise: return "Noise"
        }
    }

    /// Map a track id to the filter pill it belongs in. Tracks that don't fit any
    /// pill (e.g. binaural_music, speech_blocker) are findable only via .all.
    static func category(for id: String, fallback: String) -> CategoryFilter {
        switch id {
        case "rain", "rain_on_surface", "loud_rain", "thunder", "wind":
            return .weather
        case "ocean", "ocean_waves", "ocean_birds", "ocean_boat",
             "ocean_bubbles", "ocean_splash", "seagulls", "stream":
            return .water
        case "fire", "birds", "crickets", "insects":
            return .nature
        case "cafe", "coffee_maker", "mechanical_keyboard", "copier",
             "airplane_cabin", "air_conditioner", "co_workers", "chimes", "train_tracks":
            return .ambient
        case "white_noise", "pink_noise", "brown_noise", "green_noise", "fluorescent_hum":
            return .noise
        default:
            return .all
        }
    }
}
