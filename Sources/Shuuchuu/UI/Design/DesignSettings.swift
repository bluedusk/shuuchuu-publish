import SwiftUI
import AppKit

enum WallpaperMode: String, CaseIterable, Codable, Identifiable {
    case defaultMode = "default"
    case sunset
    case forest
    case sky
    case mono
    var id: String { rawValue }
    var display: String {
        switch self {
        case .defaultMode: return "default"
        case .sunset: return "sunset"
        case .forest: return "forest"
        case .sky:    return "sky"
        case .mono:   return "mono"
        }
    }
}

/// All user-customizable look-and-feel state. Persisted to UserDefaults.
/// The app is dark-mode only — there is no theme switch.
final class DesignSettings: ObservableObject {
    @Published var accentHue: Double { didSet { defaults.set(accentHue, forKey: K.accentHue) } }
    @Published var wallpaper: WallpaperMode { didSet { defaults.set(wallpaper.rawValue, forKey: K.wallpaper) } }
    @Published var glassBlur: Double { didSet { defaults.set(glassBlur, forKey: K.glassBlur) } }
    @Published var glassOpacity: Double { didSet { defaults.set(glassOpacity, forKey: K.glassOpacity) } }
    @Published var glassStroke: Double { didSet { defaults.set(glassStroke, forKey: K.glassStroke) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.accentHue   = defaults.object(forKey: K.accentHue)   as? Double ?? 220
        let wp = (defaults.string(forKey: K.wallpaper)).flatMap(WallpaperMode.init(rawValue:)) ?? .defaultMode
        self.wallpaper = wp
        self.glassBlur    = defaults.object(forKey: K.glassBlur)    as? Double ?? SHTokens.Glass.defaultBlur
        self.glassOpacity = defaults.object(forKey: K.glassOpacity) as? Double ?? SHTokens.Glass.defaultOpacity
        self.glassStroke  = defaults.object(forKey: K.glassStroke)  as? Double ?? SHTokens.Glass.defaultStroke
    }

    // MARK: - Derived colors

    var accent: Color       { SHTokens.accent(hue: accentHue) }
    var accentStrong: Color { SHTokens.accentStrong(hue: accentHue) }
    var accentSoft: Color   { SHTokens.accentSoft(hue: accentHue) }
    var accentGlow: Color   { SHTokens.accentGlow(hue: accentHue) }
    var accentDark: Color   { accentStrong }   // legacy alias

    private enum K {
        static let accentHue    = "shuuchuu.ui.accentHue"
        static let wallpaper    = "shuuchuu.ui.wallpaper"
        static let glassBlur    = "shuuchuu.ui.glassBlur"
        static let glassOpacity = "shuuchuu.ui.glassOpacity"
        static let glassStroke  = "shuuchuu.ui.glassStroke"
    }
}
