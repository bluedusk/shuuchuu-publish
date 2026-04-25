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
                // Spec §06 "timer · display": 56pt SF Pro Display ultraLight, tnum.
                // Bumped to fit the 172pt ring while staying on-scale.
                Text(label)
                    .font(.system(size: 56, weight: .ultraLight, design: .default))
                    .monospacedDigit()
                    .kerning(-1.4)
                // Spec §06 "caption · meta": 11pt regular, dim.
                Text(caption)
                    .font(.system(size: 11, weight: .regular))
                    .kerning(2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
