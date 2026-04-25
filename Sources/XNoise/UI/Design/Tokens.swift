import SwiftUI

/// Single source of truth for every design token in the app.
/// Derived from `docs/superpowers/specs/2026-04-23-x-noise-design.md`'s spec page
/// (Color §02 / Accent §03 / Theme §04 / Glass §07 / Typography §06).
///
/// Views never re-mix accent or text colors — they call into here.
enum XNTokens {

    // MARK: - Accent (§03)
    // One hue (0–360), four derived expressions at fixed L/C.

    static func accent(hue: Double, theme: AppTheme = .dark) -> Color {
        let isLight = (theme == .light)
        return Color(oklchL: isLight ? 0.66 : 0.74,
                     C:      isLight ? 0.18 : 0.14,
                     H: hue)
    }

    static func accentStrong(hue: Double) -> Color {
        Color(oklchL: 0.66, C: 0.18, H: hue)
    }

    static func accentSoft(hue: Double) -> Color {
        Color(oklchL: 0.85, C: 0.08, H: hue)
    }

    static func accentGlow(hue: Double) -> Color {
        Color(oklchL: 0.74, C: 0.14, H: hue, opacity: 0.55)
    }

    static func accentInk(hue: Double) -> Color {
        Color(oklchL: 0.20, C: 0.05, H: hue)
    }

    // MARK: - Text opacity stops (§02)
    // Three opacities only. View asks for primary / secondary / tertiary.
    enum TextStop { case primary, secondary, tertiary }

    static func text(_ stop: TextStop, theme: AppTheme = .dark) -> Color {
        let base: Color = (theme == .light)
            ? Color(.sRGB, red: 20/255, green: 20/255, blue: 25/255, opacity: 1)
            : .white
        switch stop {
        case .primary:   return base.opacity(0.92)
        case .secondary: return base.opacity(0.62)
        case .tertiary:  return base.opacity(0.40)
        }
    }

    // MARK: - Surfaces (§02)
    enum Surface {
        static func chip(theme: AppTheme = .dark) -> Color {
            theme == .light ? Color.white.opacity(0.50) : Color.white.opacity(0.14)
        }
        static func recess(theme: AppTheme = .dark) -> Color {
            theme == .light ? Color.black.opacity(0.06) : Color.black.opacity(0.18)
        }
        static func hover(theme: AppTheme = .dark) -> Color {
            theme == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.06)
        }
        static func stroke(theme: AppTheme = .dark) -> Color {
            theme == .light ? Color.white.opacity(0.90) : Color.white.opacity(0.16)
        }
    }

    // MARK: - Glass (§07)
    /// Defaults — overridable via the user's tweaks panel.
    enum Glass {
        static let defaultBlur:    CGFloat = 34
        static let defaultOpacity: Double  = 0.13
        static let defaultStroke:  Double  = 0.16
        static let lightOpacity:   Double  = 0.60   // light theme override
    }

    // MARK: - Geometry (§01)
    enum Radius {
        static let popover: CGFloat = 18
        static let card:    CGFloat = 12
        static let chip:    CGFloat = 8
        static let button:  CGFloat = 6
    }
    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 24
        static let s6: CGFloat = 32
    }
    static let popoverWidth:  CGFloat = 360
    static let popoverHeight: CGFloat = 540

    // MARK: - Typography (§06)
    /// Locked 5-step scale: 11 / 12 / 13 / 22 / 56. No exceptions.
    enum XNFont {
        /// 56pt SF Pro Display Ultra-Light — the focus timer. Only place this size is allowed.
        static let timer = Font.system(size: 56, weight: .ultraLight, design: .default)
            .monospacedDigit()
        /// 22pt SF Pro Display Medium — popover title, settings page title.
        static let title = Font.system(size: 22, weight: .medium, design: .default)
        /// 12pt SF Pro Text Semibold uppercase + 0.06em — section headers.
        static let section = Font.system(size: 12, weight: .semibold, design: .default)
        /// 13pt SF Pro Text Regular — body copy.
        static let body = Font.system(size: 13, weight: .regular, design: .default)
        /// 12pt SF Pro Text Medium — sound names, button labels, chips.
        static let label = Font.system(size: 12, weight: .medium, design: .default)
        /// 11pt SF Pro Text Regular — captions, hints, microcopy.
        static let caption = Font.system(size: 11, weight: .regular, design: .default)
        /// 11pt SF Mono Regular tnum — durations, key combos, numeric readouts.
        static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
            .monospacedDigit()
    }

    // MARK: - Accent presets (§03)
    /// Six named presets the picker exposes. Custom hues remain available via the slider.
    static let accentPresets: [(name: String, hue: Double)] = [
        ("Tide",   220),
        ("Moss",   160),
        ("Iris",   290),
        ("Ember",   30),
        ("Honey",   80),
        ("Coral",  340),
    ]
}
