import SwiftUI

enum WallpaperMode: String, CaseIterable, Codable, Identifiable {
    case defaultMode = "default"
    case sunset
    case forest
    case mono
    var id: String { rawValue }
    var display: String {
        switch self {
        case .defaultMode: return "default"
        case .sunset: return "sunset"
        case .forest: return "forest"
        case .mono: return "mono"
        }
    }
}

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case dark, light
    var id: String { rawValue }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// All user-customizable look-and-feel state. Persisted to UserDefaults.
/// Mirrors the tweaks panel from the design bundle.
final class DesignSettings: ObservableObject {
    @Published var accentHue: Double { didSet { defaults.set(accentHue, forKey: K.accentHue) } }
    @Published var wallpaper: WallpaperMode { didSet { defaults.set(wallpaper.rawValue, forKey: K.wallpaper) } }
    @Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: K.theme) } }
    @Published var glassBlur: Double { didSet { defaults.set(glassBlur, forKey: K.glassBlur) } }
    @Published var glassOpacity: Double { didSet { defaults.set(glassOpacity, forKey: K.glassOpacity) } }
    @Published var glassStroke: Double { didSet { defaults.set(glassStroke, forKey: K.glassStroke) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.accentHue   = defaults.object(forKey: K.accentHue)   as? Double ?? 134
        let wp = (defaults.string(forKey: K.wallpaper)).flatMap(WallpaperMode.init(rawValue:)) ?? .mono
        self.wallpaper = wp
        let th = (defaults.string(forKey: K.theme)).flatMap(AppTheme.init(rawValue:)) ?? .dark
        self.theme = th
        self.glassBlur    = defaults.object(forKey: K.glassBlur)    as? Double ?? 34
        self.glassOpacity = defaults.object(forKey: K.glassOpacity) as? Double ?? 0.13
        self.glassStroke  = defaults.object(forKey: K.glassStroke)  as? Double ?? 0.16
    }

    /// Accent color derived from hue — oklch(0.72 0.14 hue) approximated in HSB.
    var accent: Color {
        // HSB approximation of oklch(0.72 0.14 hue). Acceptable drift for a menubar app.
        Color(hue: accentHue / 360.0, saturation: 0.55, brightness: 0.92)
    }

    /// A darker sibling used for gradient tiles.
    var accentDark: Color {
        Color(hue: ((accentHue + 40).truncatingRemainder(dividingBy: 360)) / 360.0,
              saturation: 0.70, brightness: 0.60)
    }

    private enum K {
        static let accentHue    = "x-noise.ui.accentHue"
        static let wallpaper    = "x-noise.ui.wallpaper"
        static let theme        = "x-noise.ui.theme"
        static let glassBlur    = "x-noise.ui.glassBlur"
        static let glassOpacity = "x-noise.ui.glassOpacity"
        static let glassStroke  = "x-noise.ui.glassStroke"
    }
}
