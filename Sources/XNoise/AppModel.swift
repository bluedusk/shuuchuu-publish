import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published private(set) var selectedCategoryId: String?
    @Published private(set) var currentTrack: Track?
    private(set) var pendingResumeTrackId: String?

    let catalog: Catalog
    let audio: AudioController
    let cache: AudioCache
    let prefs: Preferences

    init(catalog: Catalog, audio: AudioController, cache: AudioCache, prefs: Preferences) {
        self.catalog = catalog
        self.audio = audio
        self.cache = cache
        self.prefs = prefs
        self.audio.volume = prefs.volume
        self.selectedCategoryId = prefs.lastCategoryId
    }

    func loadCatalog() async {
        await catalog.refresh()
        if case .ready(let cats) = catalog.state {
            self.categories = cats
            if selectedCategoryId == nil {
                selectedCategoryId = cats.first?.id
            }
        }
    }

    func selectCategory(_ id: String) {
        selectedCategoryId = id
        prefs.lastCategoryId = id
    }

    func play(_ track: Track) async {
        let source: NoiseSource
        switch track.kind {
        case .procedural(let variant):
            source = ProceduralNoiseSource(
                variant: variant, id: track.id, displayName: track.name
            )
        case .streamed:
            source = StreamedNoiseSource(track: track, cache: cache)
        case .bundled(let filename):
            source = BundledNoiseSource(
                id: track.id, displayName: track.name, filename: filename
            )
        }
        currentTrack = track
        await audio.play(source)
        prefs.lastTrackId = track.id
    }

    func stop() async {
        await audio.stop()
        currentTrack = nil
    }

    func setVolume(_ v: Float) {
        audio.volume = v
        prefs.volume = v
    }

    func handleSleep() async {
        if case .playing(let id) = audio.state {
            pendingResumeTrackId = id
        }
        await stop()
    }

    func handleWake() async {
        guard prefs.resumeOnWake, let id = pendingResumeTrackId else { return }
        guard let track = findTrack(id: id) else { return }
        pendingResumeTrackId = nil
        await play(track)
    }

    func handleLaunch() async {
        await loadCatalog()
        guard prefs.resumeOnLaunch, let id = prefs.lastTrackId else { return }
        guard let track = findTrack(id: id) else { return }
        await play(track)
    }

    private func findTrack(id: String) -> Track? {
        for cat in categories {
            if let t = cat.tracks.first(where: { $0.id == id }) { return t }
        }
        return nil
    }
}
