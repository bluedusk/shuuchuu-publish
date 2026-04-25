import SwiftUI
import AppKit

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
    case system, dark, light
    var id: String { rawValue }

    /// `.preferredColorScheme` value. `.system` returns nil so SwiftUI uses NSApp's appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark:   return .dark
        case .light:  return .light
        }
    }

    /// Resolves `.system` to the OS's current dark/light. Used internally for token lookups
    /// that need a concrete (non-system) value.
    var resolved: AppTheme {
        if self != .system { return self }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? .dark : .light
    }
}

/// All user-customizable look-and-feel state. Persisted to UserDefaults.
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
        self.accentHue   = defaults.object(forKey: K.accentHue)   as? Double ?? 220
        let wp = (defaults.string(forKey: K.wallpaper)).flatMap(WallpaperMode.init(rawValue:)) ?? .defaultMode
        self.wallpaper = wp
        let th = (defaults.string(forKey: K.theme)).flatMap(AppTheme.init(rawValue:)) ?? .system
        self.theme = th
        self.glassBlur    = defaults.object(forKey: K.glassBlur)    as? Double ?? XNTokens.Glass.defaultBlur
        self.glassOpacity = defaults.object(forKey: K.glassOpacity) as? Double ?? XNTokens.Glass.defaultOpacity
        self.glassStroke  = defaults.object(forKey: K.glassStroke)  as? Double ?? XNTokens.Glass.defaultStroke
    }

    // MARK: - Resolved theme + derived colors

    /// Concrete dark/light, after resolving .system. Use this for color lookups.
    var resolvedTheme: AppTheme { theme.resolved }

    var accent: Color       { XNTokens.accent(hue: accentHue, theme: resolvedTheme) }
    var accentStrong: Color { XNTokens.accentStrong(hue: accentHue) }
    var accentSoft: Color   { XNTokens.accentSoft(hue: accentHue) }
    var accentGlow: Color   { XNTokens.accentGlow(hue: accentHue) }
    var accentDark: Color   { accentStrong }   // legacy alias

    private enum K {
        static let accentHue    = "x-noise.ui.accentHue"
        static let wallpaper    = "x-noise.ui.wallpaper"
        static let theme        = "x-noise.ui.theme"
        static let glassBlur    = "x-noise.ui.glassBlur"
        static let glassOpacity = "x-noise.ui.glassOpacity"
        static let glassStroke  = "x-noise.ui.glassStroke"
    }
}
