import Foundation

/// What audio source is currently active. The app guarantees mutual exclusion:
/// at most one of `.mix` or `.soundtrack(_)` is active at a time.
enum AudioMode: Equatable, Sendable {
    case idle
    case mix
    case soundtrack(WebSoundtrack.ID)

    var isSoundtrack: Bool {
        if case .soundtrack = self { return true } else { return false }
    }

    var soundtrackId: WebSoundtrack.ID? {
        if case .soundtrack(let id) = self { return id } else { return nil }
    }
}

// MARK: - Codable
//
// Hand-rolled because automatic synthesis for enums-with-associated-values produces
// a verbose nested-keyed shape that's awkward to migrate. Our shape is flat:
//   {"kind":"idle"} | {"kind":"mix"} | {"kind":"soundtrack","id":"<uuid>"}
extension AudioMode: Codable {
    private enum CodingKeys: String, CodingKey { case kind, id }
    private enum Kind: String, Codable { case idle, mix, soundtrack }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:               try c.encode(Kind.idle, forKey: .kind)
        case .mix:                try c.encode(Kind.mix, forKey: .kind)
        case .soundtrack(let id):
            try c.encode(Kind.soundtrack, forKey: .kind)
            try c.encode(id, forKey: .id)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .idle: self = .idle
        case .mix:  self = .mix
        case .soundtrack:
            let id = try c.decode(UUID.self, forKey: .id)
            self = .soundtrack(id)
        }
    }
}
