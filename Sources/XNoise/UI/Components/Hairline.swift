import SwiftUI

/// Thin gradient horizontal divider — visible in the middle, fades to transparent at the edges.
struct Hairline: View {
    var body: some View {
        LinearGradient(
            colors: [
                .clear,
                Color.white.opacity(0.15),
                Color.white.opacity(0.15),
                .clear,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}
