import Foundation
import SwiftUI
import Combine

enum AppPage: String, CaseIterable {
    case focus, sounds, settings
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

    @Published var page: AppPage = .focus
    @Published var categoryFilter: CategoryFilter = .all

    init(
        catalog: Catalog,
        state: MixState,
        mixer: MixingController,
        cache: AudioCache,
        focusSettings: FocusSettings,
        session: FocusSession,
        design: DesignSettings,
        favorites: Favorites,
        prefs: Preferences
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
