import SwiftUI

/// Aurora gradient wallpaper that sits behind the popover.
/// Matches the design bundle's CSS `.wallpaper.mode-*` variants via SwiftUI gradients.
struct Wallpaper: View {
    let mode: WallpaperMode

    var body: some View {
        ZStack {
            baseGradient
            ForEach(stops(for: mode).indices, id: \.self) { i in
                let stop = stops(for: mode)[i]
                RadialGradient(
                    colors: [stop.color.opacity(0.9), .clear],
                    center: stop.center,
                    startRadius: 0,
                    endRadius: stop.radius
                )
                .blendMode(.plusLighter)
            }
        }
        .ignoresSafeArea()
    }

    private var baseGradient: LinearGradient {
        switch mode {
        case .defaultMode:
            return LinearGradient(
                colors: [Color(red: 0.18, green: 0.16, blue: 0.32),
                         Color(red: 0.10, green: 0.11, blue: 0.22)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .sunset:
            return LinearGradient(
                colors: [Color(red: 0.35, green: 0.18, blue: 0.20),
                         Color(red: 0.22, green: 0.10, blue: 0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .forest:
            return LinearGradient(
                colors: [Color(red: 0.12, green: 0.22, blue: 0.18),
                         Color(red: 0.08, green: 0.15, blue: 0.13)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        case .mono:
            return LinearGradient(
                colors: [Color(white: 0.20), Color(white: 0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private struct Stop { let color: Color; let center: UnitPoint; let radius: CGFloat }

    private func stops(for mode: WallpaperMode) -> [Stop] {
        switch mode {
        case .defaultMode:
            return [
                Stop(color: Color(red: 0.92, green: 0.55, blue: 0.80), center: .init(x: 0.20, y: 0.30), radius: 260),
                Stop(color: Color(red: 0.55, green: 0.80, blue: 0.98), center: .init(x: 0.80, y: 0.20), radius: 230),
                Stop(color: Color(red: 0.72, green: 0.58, blue: 0.98), center: .init(x: 0.70, y: 0.80), radius: 260),
                Stop(color: Color(red: 0.55, green: 0.95, blue: 0.85), center: .init(x: 0.10, y: 0.90), radius: 200),
            ]
        case .sunset:
            return [
                Stop(color: Color(red: 0.98, green: 0.60, blue: 0.28), center: .init(x: 0.20, y: 0.30), radius: 260),
                Stop(color: Color(red: 0.95, green: 0.45, blue: 0.65), center: .init(x: 0.80, y: 0.20), radius: 230),
                Stop(color: Color(red: 0.80, green: 0.25, blue: 0.30), center: .init(x: 0.70, y: 0.80), radius: 260),
            ]
        case .forest:
            return [
                Stop(color: Color(red: 0.45, green: 0.85, blue: 0.55), center: .init(x: 0.20, y: 0.30), radius: 260),
                Stop(color: Color(red: 0.55, green: 0.88, blue: 0.45), center: .init(x: 0.80, y: 0.20), radius: 230),
                Stop(color: Color(red: 0.40, green: 0.75, blue: 0.70), center: .init(x: 0.70, y: 0.80), radius: 260),
            ]
        case .mono:
            return [
                Stop(color: Color(white: 0.55), center: .init(x: 0.20, y: 0.30), radius: 260),
                Stop(color: Color(white: 0.70), center: .init(x: 0.80, y: 0.20), radius: 230),
            ]
        }
    }
}
