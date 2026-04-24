import SwiftUI

/// Visual identity per track: an SF Symbol + a tint color.
/// Defaults are derived from the track id; fallback is a generic waveform.
struct TrackIcon {
    let symbol: String
    let tint: Color
}

enum TrackIconMap {
    static func icon(for trackId: String) -> TrackIcon {
        switch trackId {

        // MARK: Noise
        case "white_noise":     return .init(symbol: "waveform",               tint: .gray)
        case "pink_noise":      return .init(symbol: "waveform",               tint: .pink)
        case "brown_noise":     return .init(symbol: "waveform.path.ecg",      tint: .brown)
        case "green_noise":     return .init(symbol: "waveform",               tint: .green)
        case "fluorescent_hum": return .init(symbol: "lightbulb.fill",         tint: .yellow)

        // MARK: Soundscapes — weather
        case "rain":            return .init(symbol: "cloud.rain.fill",        tint: .blue)
        case "rain_on_surface": return .init(symbol: "cloud.drizzle.fill",     tint: .blue)
        case "loud_rain":       return .init(symbol: "cloud.heavyrain.fill",   tint: .indigo)
        case "thunder":         return .init(symbol: "cloud.bolt.rain.fill",   tint: .purple)
        case "wind":            return .init(symbol: "wind",                   tint: .teal)

        // MARK: Soundscapes — water
        case "ocean":           return .init(symbol: "water.waves",            tint: .blue)
        case "ocean_waves":     return .init(symbol: "water.waves",            tint: .cyan)
        case "ocean_birds":     return .init(symbol: "bird.fill",              tint: .cyan)
        case "ocean_boat":      return .init(symbol: "sailboat.fill",          tint: .blue)
        case "ocean_bubbles":   return .init(symbol: "bubbles.and.sparkles",   tint: .teal)
        case "ocean_splash":    return .init(symbol: "drop.fill",              tint: .cyan)
        case "seagulls":        return .init(symbol: "bird.fill",              tint: .blue)
        case "stream":          return .init(symbol: "drop.triangle.fill",     tint: .teal)

        // MARK: Soundscapes — nature
        case "fire":            return .init(symbol: "flame.fill",             tint: .orange)
        case "birds":           return .init(symbol: "bird.fill",              tint: .green)
        case "crickets":        return .init(symbol: "leaf.fill",              tint: .green)
        case "insects":         return .init(symbol: "ant.fill",               tint: .green)

        // MARK: Ambient — places / objects
        case "cafe":                return .init(symbol: "cup.and.saucer.fill",   tint: .brown)
        case "coffee_maker":        return .init(symbol: "cup.and.saucer.fill",   tint: .brown)
        case "mechanical_keyboard": return .init(symbol: "keyboard.fill",         tint: .gray)
        case "copier":              return .init(symbol: "printer.fill",          tint: .gray)
        case "airplane_cabin":      return .init(symbol: "airplane",              tint: .indigo)
        case "air_conditioner":     return .init(symbol: "fan",                   tint: .mint)
        case "co_workers":          return .init(symbol: "person.3.fill",         tint: .orange)
        case "chimes":              return .init(symbol: "bell.fill",             tint: .yellow)
        case "train_tracks":        return .init(symbol: "tram.fill",             tint: .red)

        // MARK: Binaural / specials
        case "binaural_music":  return .init(symbol: "brain.head.profile",     tint: .purple)
        case "speech_blocker":  return .init(symbol: "mic.slash.fill",         tint: .red)

        default:
            return .init(symbol: "waveform", tint: .accentColor)
        }
    }
}
