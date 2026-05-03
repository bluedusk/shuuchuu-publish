import Foundation

enum TagNormalize {
    static let maxTagsPerSoundtrack = 3

    /// Lowercased, trimmed. Returns nil if the result is empty.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Normalize each entry, drop empties, dedupe preserving first-occurrence
    /// order, then clamp to `maxTagsPerSoundtrack`.
    static func normalize(list: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in list {
            guard let n = normalize(raw), !seen.contains(n) else { continue }
            seen.insert(n)
            out.append(n)
            if out.count == maxTagsPerSoundtrack { break }
        }
        return out
    }
}
