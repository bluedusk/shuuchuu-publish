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

extension WebSoundtrack {
    /// Extracted from the canonical `/embed/<id>` URL produced by `SoundtrackURL.parse`.
    /// Returns nil for Spotify, playlists (`videoseries`), or malformed URLs.
    var youtubeVideoId: String? {
        guard kind == .youtube,
              let range = url.range(of: "/embed/") else { return nil }
        let tail = url[range.upperBound...]
        let id = tail.split(whereSeparator: { $0 == "?" || $0 == "/" }).first.map(String.init)
        return id == "videoseries" ? nil : id
    }

    var youtubeThumbnailURL: URL? {
        guard let id = youtubeVideoId else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }

    /// Browser-friendly URL — the stored `url` is an embed URL not meant to be
    /// opened directly. For YouTube we reconstruct a watch/playlist URL; for
    /// Spotify we strip the `/embed` segment.
    var externalURL: URL? {
        switch kind {
        case .youtube:
            if let id = youtubeVideoId {
                return URL(string: "https://www.youtube.com/watch?v=\(id)")
            }
            // Playlist embed: /embed/videoseries?list=<id>
            if let listRange = url.range(of: "list=") {
                let listId = url[listRange.upperBound...]
                    .split(whereSeparator: { $0 == "&" || $0 == "?" })
                    .first
                    .map(String.init) ?? ""
                guard !listId.isEmpty else { return nil }
                return URL(string: "https://www.youtube.com/playlist?list=\(listId)")
            }
            return nil
        case .spotify:
            return URL(string: url.replacingOccurrences(of: "/embed/", with: "/"))
        }
    }
}
