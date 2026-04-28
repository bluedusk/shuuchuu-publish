import Foundation
import Combine

/// User's saved soundtracks library. Persisted to UserDefaults under
/// `x-noise.savedSoundtracks` as a JSON array of `WebSoundtrack`.
@MainActor
final class SoundtracksLibrary: ObservableObject {
    @Published private(set) var entries: [WebSoundtrack] = [] { didSet { persist() } }

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "x-noise.savedSoundtracks") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    // MARK: - CRUD

    /// Append a new soundtrack derived from a parsed URL. Default volume is 0.5.
    @discardableResult
    func add(parsed: SoundtrackURL) -> WebSoundtrack {
        let entry = WebSoundtrack(
            id: UUID(),
            kind: parsed.kind,
            url: parsed.embedURL,
            title: nil,
            volume: 0.5,
            addedAt: Date()
        )
        entries.append(entry)
        return entry
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func setVolume(id: UUID, volume: Double) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].volume = volume
    }

    func setTitle(id: UUID, title: String?) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].title = title
    }

    func entry(id: UUID) -> WebSoundtrack? {
        entries.first(where: { $0.id == id })
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else {
            assertionFailure("SoundtracksLibrary: failed to encode")
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([WebSoundtrack].self, from: data) {
            entries = decoded
        }
    }
}
