import Foundation
import Combine

/// A user-saved mix: ordered list of (trackId, volume) plus a display name.
struct SavedMix: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var tracks: [MixTrack]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, tracks: [MixTrack], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.createdAt = createdAt
    }
}

/// Result of attempting to save under a given name.
enum SaveMixResult: Equatable {
    case saved(SavedMix)
    case duplicate(existing: SavedMix)
}

/// User-saved mixes. Persists to UserDefaults; sorted most-recently-saved first for display.
@MainActor
final class SavedMixes: ObservableObject {
    @Published private(set) var mixes: [SavedMix] = []

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "x-noise.savedMixes") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    /// Attempt to save a new mix. Returns `.duplicate(existing:)` if a mix with the same
    /// trimmed name already exists; the caller decides whether to overwrite or save-as-new.
    func save(name: String, tracks: [MixTrack]) -> SaveMixResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = mix(named: trimmed) {
            return .duplicate(existing: existing)
        }
        let mix = SavedMix(name: trimmed, tracks: tracks)
        mixes.insert(mix, at: 0)
        persist()
        return .saved(mix)
    }

    /// Replace the tracks of an existing mix with a new set, preserving id/name/createdAt.
    func overwrite(id: UUID, tracks: [MixTrack]) {
        guard let idx = mixes.firstIndex(where: { $0.id == id }) else { return }
        mixes[idx].tracks = tracks
        persist()
    }

    /// Save under a "(N)" suffix, picking the smallest N that doesn't collide.
    @discardableResult
    func saveWithUniqueSuffix(baseName: String, tracks: [MixTrack]) -> SavedMix {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        var n = 2
        var candidate = "\(base) (\(n))"
        while mix(named: candidate) != nil {
            n += 1
            candidate = "\(base) (\(n))"
        }
        let mix = SavedMix(name: candidate, tracks: tracks)
        mixes.insert(mix, at: 0)
        persist()
        return mix
    }

    func delete(id: UUID) {
        mixes.removeAll { $0.id == id }
        persist()
    }

    func mix(named name: String) -> SavedMix? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return mixes.first(where: { $0.name == trimmed })
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(mixes) else {
            assertionFailure("SavedMixes: encode failed")
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([SavedMix].self, from: data)
        else { return }
        // Preserve stored order; on save we always insert at index 0, so storage is already
        // most-recent-first.
        mixes = decoded
    }
}
