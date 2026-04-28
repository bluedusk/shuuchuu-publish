import Foundation

/// Parsed + normalized representation of a pasted URL. Pure value type.
struct SoundtrackURL: Equatable {
    enum Kind: String, Codable, Sendable, Equatable { case youtube, spotify }

    let kind: Kind
    /// Canonical embed URL — what the WKWebView's bridge should load.
    let embedURL: String
    /// Short label suitable for the paste-flow validation sub-text
    /// (`"YouTube video"`, `"Spotify playlist"`, etc.). Not user-input.
    let humanLabel: String
}

enum AddSoundtrackError: Error, Equatable {
    case invalidURL
    case unsupportedHost
}

extension SoundtrackURL {
    static func parse(_ raw: String) -> Result<SoundtrackURL, AddSoundtrackError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return .failure(.invalidURL)
        }

        if host == "youtu.be" {
            // youtu.be/<id>
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty else { return .failure(.invalidURL) }
            return .success(.init(kind: .youtube,
                                  embedURL: "https://www.youtube.com/embed/\(id)?enablejsapi=1",
                                  humanLabel: "YouTube video"))
        }

        if host.hasSuffix("youtube.com") {
            let path = url.path
            let query = queryItems(url)
            if path == "/watch" {
                guard let id = query["v"], !id.isEmpty else { return .failure(.invalidURL) }
                return .success(.init(kind: .youtube,
                                      embedURL: "https://www.youtube.com/embed/\(id)?enablejsapi=1",
                                      humanLabel: "YouTube video"))
            }
            if path == "/playlist" {
                guard let listId = query["list"], !listId.isEmpty else { return .failure(.invalidURL) }
                return .success(.init(kind: .youtube,
                                      embedURL: "https://www.youtube.com/embed/videoseries?list=\(listId)&enablejsapi=1",
                                      humanLabel: "YouTube playlist"))
            }
            return .failure(.invalidURL)
        }

        if host == "open.spotify.com" {
            // /<type>/<id>[?...]
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return .failure(.invalidURL) }
            let contentType = parts[0]
            let id = parts[1]
            let allowed: Set<String> = ["track", "album", "playlist", "episode", "show"]
            guard allowed.contains(contentType), !id.isEmpty else { return .failure(.invalidURL) }
            return .success(.init(kind: .spotify,
                                  embedURL: "https://open.spotify.com/embed/\(contentType)/\(id)",
                                  humanLabel: "Spotify \(contentType)"))
        }

        return .failure(.unsupportedHost)
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        var out: [String: String] = [:]
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .forEach { if let v = $0.value { out[$0.name] = v } }
        return out
    }
}
