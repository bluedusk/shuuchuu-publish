import SwiftUI

/// A chip representing an active track in the "Now playing" list on the Focus page.
/// Shows the track's icon, name, a mini volume slider, and a remove button.
struct MixChipRow: View {
    let track: Track
    let volume: Float
    let onVolumeChange: (Float) -> Void
    let onRemove: () -> Void

    @EnvironmentObject var design: DesignSettings

    private var icon: TrackIcon { TrackIconMap.icon(for: track.id) }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                LinearGradient(
                    colors: [design.accent, design.accentDark],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: icon.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: design.accent.opacity(0.6), radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                MiniSlider(
                    value: Binding(get: { Double(volume) }, set: { onVolumeChange(Float($0)) }),
                    accent: design.accent
                )
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(7)
        .glassChip(design: design)
    }
}

/// A slim custom volume slider — thinner than SwiftUI's default, matches the design's look.
struct MiniSlider: View {
    @Binding var value: Double  // 0…1
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 3)
                Capsule()
                    .fill(accent)
                    .frame(width: max(0, geo.size.width * value), height: 3)
                    .shadow(color: accent.opacity(0.8), radius: 3)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let x = max(0, min(geo.size.width, g.location.x))
                        value = Double(x / max(1, geo.size.width))
                    }
            )
        }
        .frame(height: 14)
    }
}
