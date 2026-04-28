import Foundation

/// A named mix preset: (track id → volume).
struct Preset: Identifiable, Equatable {
    let id: String
    let name: String
    let mix: [String: Float]
}

/// Built-in presets matching the design bundle's PRESETS table.
/// Track ids reference the ids we emit in catalog.json.
enum Presets {
    static let all: [Preset] = [
        Preset(id: "deep",     name: "Deep Focus",
               mix: ["rain": 0.6, "brown_noise": 0.3]),
        Preset(id: "sleep",    name: "Sleep",
               mix: ["rain": 0.4, "thunder": 0.2, "pink_noise": 0.3]),
        Preset(id: "creative", name: "Creative",
               mix: ["cafe": 0.6, "stream": 0.3]),
        Preset(id: "storm",    name: "Storm",
               mix: ["rain": 0.7, "thunder": 0.5, "wind": 0.4]),
        Preset(id: "cabin",    name: "Cabin",
               mix: ["fire": 0.6, "wind": 0.3]),
    ]
}
