import SwiftUI

/// Thin two-stop gradient overlay that keeps the popover UI legible against
/// busy shader backgrounds. Dark band at the top (under the FOCUS title) and
/// a heavier dark band at the bottom (under the mix list).
struct SceneScrim: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.25), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.30)
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: UnitPoint(x: 0.5, y: 0.70),
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}
