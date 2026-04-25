import Foundation
import SwiftUI
import Combine

enum AppPage: String, CaseIterable {
    case focus, sounds, settings
}

@MainActor
final class AppModel: ObservableObject {
    // Catalog + cache
    @Published private(set) var categories: [Category] = []
    let catalog: Catalog
    let cache: AudioCache

    // Audio
    let mixer: MixingController

    // Focus session
    let focusSettings: FocusSettings
    let session: FocusSession

    // Design / UX
    let design: DesignSettings
    let favorites: Favorites
    let prefs: Preferences

    // Navigation
    @Published var page: AppPage = .focus
    @Published var categoryFilter: CategoryFilter = .all

    init(
        catalog: Catalog,
        mixer: MixingController,
        cache: AudioCache,
        focusSettings: FocusSettings,
        session: FocusSession,
        design: DesignSettings,
        favorites: Favorites,
        prefs: Preferences
    ) {
        self.catalog = catalog
        self.mixer = mixer
        self.cache = cache
        self.focusSettings = focusSettings
        self.session = session
        self.design = design
        self.favorites = favorites
        self.prefs = prefs
        self.mixer.masterVolume = prefs.volume
    }

    func loadCatalog() async {
        await catalog.refresh()
        if case .ready(let cats) = catalog.state {
            self.categories = cats
        }
    }

    /// Toggle a track on/off. On toggling from off → on, uses a sensible default volume.
    func toggleTrack(_ track: Track) async {
        if mixer.live[track.id] != nil {
            mixer.remove(trackId: track.id)
        } else {
            await mixer.addOrUpdate(track: track, volume: 0.5, cache: cache)
        }
        persistMix()
    }

    func setTrackVolume(_ trackId: String, _ v: Float) {
        mixer.setVolume(trackId: trackId, volume: v)
        persistMix()
    }

    func removeTrack(_ trackId: String) {
        mixer.remove(trackId: trackId)
        persistMix()
    }

    func setMasterVolume(_ v: Float) {
        mixer.masterVolume = v
        prefs.volume = v
    }

    func togglePause(trackId: String) {
        if mixer.live[trackId]?.paused == true {
            mixer.resume(trackId: trackId)
        } else {
            mixer.pause(trackId: trackId)
        }
        persistMix()
    }

    func togglePlayAll() {
        if mixer.masterPaused {
            mixer.resumeAll()
        } else {
            mixer.pauseAll()
        }
        persistMix()
    }

    func applyPreset(_ preset: Preset) async {
        await mixer.applyMix(preset.mix, resolving: { self.findTrack(id: $0) }, cache: cache)
        persistMix()
    }

    // MARK: - Mix persistence

    /// Snapshot of the active mix as it survives an app restart.
    private struct SavedMix: Codable {
        struct Track: Codable {
            let id: String
            let volume: Float
            let paused: Bool
        }
        let tracks: [Track]
        let masterPaused: Bool
    }

    private static let savedMixKey = "x-noise.savedMix"

    private func persistMix() {
        let snapshot = SavedMix(
            tracks: mixer.live.values.map { .init(id: $0.id, volume: $0.volume, paused: $0.paused) },
            masterPaused: mixer.masterPaused
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.savedMixKey)
        }
    }

    private func restoreMix() async {
        guard
            let data = UserDefaults.standard.data(forKey: Self.savedMixKey),
            let snapshot = try? JSONDecoder().decode(SavedMix.self, from: data),
            !snapshot.tracks.isEmpty
        else { return }

        // Re-add each saved track at its original volume.
        for entry in snapshot.tracks {
            guard let track = findTrack(id: entry.id) else { continue }
            await mixer.addOrUpdate(track: track, volume: entry.volume, cache: cache)
            if entry.paused {
                mixer.pause(trackId: entry.id)
            }
        }
        if snapshot.masterPaused {
            mixer.pauseAll()
        }
    }

    func goTo(_ page: AppPage) {
        withAnimation(.smooth(duration: 0.32)) { self.page = page }
    }

    func findTrack(id: String) -> Track? {
        for cat in categories {
            if let t = cat.tracks.first(where: { $0.id == id }) { return t }
        }
        return nil
    }

    /// All tracks flattened across catalog categories, plus a synthetic "cat" for the pills filter.
    var allTracks: [(track: Track, filter: CategoryFilter)] {
        categories.flatMap { cat in
            cat.tracks.map { t in (t, CategoryFilter.category(for: t.id, fallback: cat.id)) }
        }
    }

    // MARK: - Lifecycle

    func handleLaunch() async {
        await loadCatalog()
        await restoreMix()
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
