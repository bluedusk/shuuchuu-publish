import SwiftUI

/// Aurora gradient wallpaper. Each variant follows the spec §05 formula:
/// up to 4 radial blobs over 1 base linear gradient, all in OKLCH.
struct Wallpaper: View {
    let mode: WallpaperMode

    var body: some View {
        ZStack {
            baseGradient
            ForEach(blobs(for: mode).indices, id: \.self) { i in
                let b = blobs(for: mode)[i]
                RadialGradient(
                    colors: [b.color, .clear],
                    center: b.center,
                    startRadius: 0,
                    endRadius: b.radius
                )
                .blendMode(.normal)
            }
        }
        .ignoresSafeArea()
    }

    private var baseGradient: LinearGradient {
        let stops = baseStops(for: mode)
        return LinearGradient(
            colors: [stops.0, stops.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Spec values

    private struct Blob {
        let color: Color
        let center: UnitPoint
        let radius: CGFloat
    }

    private func baseStops(for mode: WallpaperMode) -> (Color, Color) {
        switch mode {
        case .defaultMode: return (Color(oklchL: 0.38, C: 0.10, H: 280), Color(oklchL: 0.28, C: 0.08, H: 250))
        case .sunset:      return (Color(oklchL: 0.50, C: 0.12, H:  30), Color(oklchL: 0.35, C: 0.10, H: 350))
        case .forest:      return (Color(oklchL: 0.40, C: 0.10, H: 160), Color(oklchL: 0.30, C: 0.08, H: 140))
        case .sky:         return (Color(oklchL: 0.42, C: 0.10, H: 235), Color(oklchL: 0.30, C: 0.08, H: 220))
        case .mono:        return (Color(oklchL: 0.25, C: 0.01, H: 260), Color(oklchL: 0.15, C: 0.01, H: 260))
        case .noir:        return (Color(oklchL: 0.10, C: 0.00, H:   0), Color(oklchL: 0.04, C: 0.00, H:   0))
        case .noirRed:     return (Color(oklchL: 0.08, C: 0.02, H:  25), Color(oklchL: 0.04, C: 0.00, H:   0))
        case .midnight:    return (Color(oklchL: 0.12, C: 0.03, H: 250), Color(oklchL: 0.05, C: 0.02, H: 240))
        }
    }

    private func blobs(for mode: WallpaperMode) -> [Blob] {
        // Slot template: positions are fixed; per-mode we vary the OKLCH values + count.
        // Slot 1 (60% wide × 50% tall) at (20%, 30%)
        // Slot 2 (50% × 40%) at (80%, 20%)
        // Slot 3 (55% × 45%) at (70%, 80%)
        // Slot 4 (45% × 35%) at (10%, 90%)
        switch mode {
        case .defaultMode:
            return [
                Blob(color: Color(oklchL: 0.78, C: 0.16, H: 330), center: .init(x: 0.20, y: 0.30), radius: 260),
                Blob(color: Color(oklchL: 0.82, C: 0.14, H: 220), center: .init(x: 0.80, y: 0.20), radius: 230),
                Blob(color: Color(oklchL: 0.78, C: 0.15, H: 280), center: .init(x: 0.70, y: 0.80), radius: 260),
                Blob(color: Color(oklchL: 0.82, C: 0.14, H: 170), center: .init(x: 0.10, y: 0.90), radius: 200),
            ]
        case .sunset:
            return [
                Blob(color: Color(oklchL: 0.82, C: 0.16, H:  30), center: .init(x: 0.20, y: 0.30), radius: 260),
                Blob(color: Color(oklchL: 0.78, C: 0.15, H: 350), center: .init(x: 0.80, y: 0.20), radius: 230),
                Blob(color: Color(oklchL: 0.72, C: 0.14, H:  20), center: .init(x: 0.70, y: 0.80), radius: 260),
            ]
        case .forest:
            return [
                Blob(color: Color(oklchL: 0.75, C: 0.14, H: 160), center: .init(x: 0.20, y: 0.30), radius: 260),
                Blob(color: Color(oklchL: 0.78, C: 0.14, H: 120), center: .init(x: 0.80, y: 0.20), radius: 230),
                Blob(color: Color(oklchL: 0.70, C: 0.14, H: 200), center: .init(x: 0.70, y: 0.80), radius: 260),
            ]
        case .sky:
            // Spec §05: 4 blobs, blue family 200–240, all within L 0.78–0.82.
            return [
                Blob(color: Color(oklchL: 0.82, C: 0.14, H: 210), center: .init(x: 0.20, y: 0.30), radius: 260),
                Blob(color: Color(oklchL: 0.78, C: 0.15, H: 240), center: .init(x: 0.80, y: 0.20), radius: 230),
                Blob(color: Color(oklchL: 0.80, C: 0.12, H: 200), center: .init(x: 0.70, y: 0.80), radius: 260),
                Blob(color: Color(oklchL: 0.82, C: 0.10, H: 220), center: .init(x: 0.10, y: 0.90), radius: 200),
            ]
        case .mono:
            return [
                Blob(color: Color(oklchL: 0.60, C: 0.02, H: 260), center: .init(x: 0.20, y: 0.30), radius: 260),
                Blob(color: Color(oklchL: 0.70, C: 0.02, H: 260), center: .init(x: 0.80, y: 0.20), radius: 230),
            ]
        case .noir:
            return [
                Blob(color: Color(oklchL: 0.30, C: 0.00, H:   0), center: .init(x: 0.20, y: 0.30), radius: 260),
                Blob(color: Color(oklchL: 0.40, C: 0.00, H:   0), center: .init(x: 0.80, y: 0.20), radius: 230),
            ]
        case .noirRed:
            return [
                Blob(color: Color(oklchL: 0.50, C: 0.22, H:  25), center: .init(x: 0.20, y: 0.30), radius: 260),
                Blob(color: Color(oklchL: 0.55, C: 0.20, H:  15), center: .init(x: 0.80, y: 0.20), radius: 230),
                Blob(color: Color(oklchL: 0.30, C: 0.02, H:   0), center: .init(x: 0.70, y: 0.80), radius: 260),
            ]
        case .midnight:
            return [
                Blob(color: Color(oklchL: 0.30, C: 0.04, H: 245), center: .init(x: 0.20, y: 0.30), radius: 260),
                Blob(color: Color(oklchL: 0.35, C: 0.03, H: 230), center: .init(x: 0.80, y: 0.20), radius: 230),
                Blob(color: Color(oklchL: 0.25, C: 0.05, H: 260), center: .init(x: 0.70, y: 0.80), radius: 260),
            ]
        }
    }
}
