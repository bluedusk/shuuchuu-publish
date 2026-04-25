import SwiftUI

/// Subtle accent-tinted vertical scroll indicator that overlays a ScrollView.
/// Tracks scroll progress via `coordinateSpace`. The indicator is a slim accent-
/// colored capsule on a faint track. Native scroll bars should be hidden via
/// `.scrollIndicators(.hidden)` on the parent ScrollView.
struct HueScrollIndicator: View {
    /// Visible viewport height of the ScrollView.
    let viewportHeight: CGFloat
    /// Total content height inside the ScrollView.
    let contentHeight: CGFloat
    /// Negative scroll offset — i.e. how many points of content are above the viewport top.
    let scrollOffset: CGFloat
    /// Tint color of the thumb.
    let tint: Color

    private var hidden: Bool { contentHeight <= viewportHeight + 1 }

    private var thumbHeightFraction: CGFloat {
        guard contentHeight > 0 else { return 0 }
        return min(1, max(0.08, viewportHeight / contentHeight))
    }

    private var thumbOffsetFraction: CGFloat {
        let scrollableHeight = max(1, contentHeight - viewportHeight)
        return min(1, max(0, -scrollOffset / scrollableHeight))
    }

    var body: some View {
        if hidden {
            EmptyView()
        } else {
            GeometryReader { geo in
                let trackH = geo.size.height
                let thumbH = trackH * thumbHeightFraction
                let thumbY = (trackH - thumbH) * thumbOffsetFraction

                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 3)
                    Capsule()
                        .fill(tint.opacity(0.45))
                        .frame(width: 3, height: thumbH)
                        .offset(y: thumbY)
                        .shadow(color: tint.opacity(0.3), radius: 2)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: 3)
            .padding(.trailing, 4)
            .allowsHitTesting(false)
        }
    }
}
