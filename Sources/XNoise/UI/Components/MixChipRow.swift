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
            iconBadge

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Slider(
                    value: Binding(
                        get: { Double(volume) },
                        set: { onVolumeChange(Float($0)) }
                    ),
                    in: 0...1
                )
                .controlSize(.mini)
                .tint(design.accent)
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

    private var iconBadge: some View {
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
    }
}
