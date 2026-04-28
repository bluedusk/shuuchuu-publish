import SwiftUI

/// Active-track row in the "Now playing" list on the Focus page.
/// Per-track play/pause + (hover-only) remove.
struct MixChipRow: View {
    let track: Track
    let volume: Float
    let paused: Bool
    let onVolumeChange: (Float) -> Void
    let onTogglePause: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    private var icon: TrackIcon { TrackIconMap.icon(for: track.id) }
    private var dim: Bool { paused }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon.symbol)
                .font(.system(size: 14, weight: .light))
                .frame(width: 22, height: 22)
                .xnText(dim ? .tertiary : .primary)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .xnText(dim ? .tertiary : .primary)
                ThumblessSlider(
                    value: Binding(get: { Double(volume) }, set: { onVolumeChange(Float($0)) }),
                    tint: Color.white.opacity(0.55)
                )
            }
            .opacity(dim ? 0.6 : 1)

            // Per-track play/pause — visible always when paused, only on hover when playing
            Button(action: onTogglePause) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(paused || isHovered ? 1 : 0)

            // Remove × — only on hover
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.055 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
