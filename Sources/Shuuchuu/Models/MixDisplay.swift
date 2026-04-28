import Foundation

/// Unified view-model for any mix the user can apply from the Mixes tab.
enum MixDisplay: Identifiable, Equatable {
    case custom(SavedMix)
    case preset(Preset)

    var id: AnyHashable {
        switch self {
        case .custom(let m): return m.id
        case .preset(let p): return p.id
        }
    }

    var name: String {
        switch self {
        case .custom(let m): return m.name
        case .preset(let p): return p.name
        }
    }

    /// Track ids in the order they should appear in the icon stack.
    var trackIds: [String] {
        switch self {
        case .custom(let m): return m.tracks.map(\.id)
        case .preset(let p): return Array(p.mix.keys).sorted()
        }
    }

    /// `[id: volume]` — used when applying the mix.
    var trackVolumes: [String: Float] {
        switch self {
        case .custom(let m):
            return Dictionary(uniqueKeysWithValues: m.tracks.map { ($0.id, $0.volume) })
        case .preset(let p):
            return p.mix
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true } else { return false }
    }
}
