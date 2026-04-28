import SwiftUI

/// Row of small dots indicating progress through a focus cycle.
/// Filled dots = completed/current sessions; faint dots = upcoming.
struct SessionDots: View {
    let total: Int
    let current: Int   // 1-based session number

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < current
                          ? Color.white.opacity(0.55)
                          : Color.white.opacity(0.12))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
