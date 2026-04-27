import Foundation

/// One saved soundtrack in the user's library. Persisted to UserDefaults.
struct WebSoundtrack: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: SoundtrackURL.Kind
    /// Canonical embed URL — produced by `SoundtrackURL.parse`.
    let url: String
    /// Best-effort, populated by the JS bridge once the player reports it.
    /// Cached for nicer launch UX (avoids an empty title flicker before the bridge fires).
    var title: String?
    var volume: Double      // 0.0–1.0 app scale; bridge converts per-provider
    let addedAt: Date
}
