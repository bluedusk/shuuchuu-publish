import Foundation
import Combine

/// One track in the active mix as the user perceives it: id, volume, paused.
/// Pure value type — no audio engine knowledge.
struct MixTrack: Equatable, Codable, Identifiable {
    let id: String
    var volume: Float
    var paused: Bool

    init(id: String, volume: Float, paused: Bool = false) {
        self.id = id
        self.volume = volume
        self.paused = paused
    }
}

/// The single source of truth for the active mix list.
///
/// Each track is independently paused or playing. There is no "master pause" — the
/// PLAY ALL / PAUSE ALL button just batch-toggles every track. The engine is running
/// iff at least one track is unpaused.
///
/// Persistence: only the sound list (id + volume) is written to disk. Per-track play/
/// pause state is per-session — every launch starts with all tracks paused.
@MainActor
final class MixState: ObservableObject {
    @Published private(set) var tracks: [MixTrack] = [] { didSet { persist() } }

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "x-noise.savedMix") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    // MARK: - Queries

    func contains(_ id: String) -> Bool { tracks.contains(where: { $0.id == id }) }
    func track(_ id: String) -> MixTrack? { tracks.first(where: { $0.id == id }) }
    var isEmpty: Bool { tracks.isEmpty }
    var count: Int { tracks.count }
    var anyPlaying: Bool { tracks.contains(where: { !$0.paused }) }

    // MARK: - Mutations

    /// Append a new track (no-op if already present). New tracks are unpaused — adding
    /// a sound from the Sounds page implies "play this now."
    func append(id: String, volume: Float, paused: Bool = false) {
        guard !contains(id) else { return }
        tracks.append(MixTrack(id: id, volume: volume, paused: paused))
    }

    func remove(id: String) {
        tracks.removeAll { $0.id == id }
    }

    func setVolume(id: String, volume: Float) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].volume = volume
    }

    func setPaused(id: String, paused: Bool) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].paused = paused
    }

    func togglePaused(id: String) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].paused.toggle()
    }

    /// Set every track's paused flag in one mutation.
    func setAllPaused(_ paused: Bool) {
        var changed = false
        for i in tracks.indices where tracks[i].paused != paused {
            tracks[i].paused = paused
            changed = true
        }
        if changed { tracks = tracks } // force didSet/persist
    }

    /// Wholesale replacement (e.g. applying a preset). New tracks default to unpaused.
    func replace(with newTracks: [MixTrack]) {
        guard tracks != newTracks else { return }
        tracks = newTracks
    }

    func clear() {
        guard !tracks.isEmpty else { return }
        tracks = []
    }

    // MARK: - Persistence

    /// What we persist: just the list of sounds and their volumes.
    /// Play/pause state is per-session and never written to disk.
    private struct PersistedTrack: Codable {
        let id: String
        let volume: Float
    }

    private func persist() {
        let list = tracks.map { PersistedTrack(id: $0.id, volume: $0.volume) }
        guard let data = try? JSONEncoder().encode(list) else {
            assertionFailure("MixState: failed to encode list")
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        // Tracks always load with paused=true — the user explicitly plays them.
        if let list = try? decoder.decode([PersistedTrack].self, from: data) {
            tracks = list.map { MixTrack(id: $0.id, volume: $0.volume, paused: true) }
        }
        // Legacy shape (had a wrapper object). One-time migration.
        else if let legacy = try? decoder.decode(LegacySnapshot.self, from: data) {
            tracks = legacy.tracks.map { MixTrack(id: $0.id, volume: $0.volume, paused: true) }
            persist()
        }
    }

    private struct LegacySnapshot: Codable {
        struct LegacyTrack: Codable { let id: String; let volume: Float; let paused: Bool }
        let tracks: [LegacyTrack]
        let masterPaused: Bool
    }
}
