import SwiftUI

/// Circular progress ring with centered time display. The design's hero element.
struct PomodoroRing: View {
    let progress: Double      // 0…1
    let size: CGFloat
    let stroke: CGFloat
    let accent: Color
    let label: String
    let caption: String

    var body: some View {
        ZStack {
            // Outer glow halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.20), .clear],
                        center: .center, startRadius: 10, endRadius: size * 0.7
                    )
                )
                .frame(width: size + 36, height: size + 36)
                .blur(radius: 12)

            // Track (unfilled) circle
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: stroke)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [accent, accent.opacity(0.65), accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.7), radius: 4)

            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 36, weight: .thin, design: .default))
                    .monospacedDigit()
                    .kerning(-1)
                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .kerning(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
