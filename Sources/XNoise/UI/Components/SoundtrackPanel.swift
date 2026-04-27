import SwiftUI

/// Single-soundtrack panel rendered on the Focus page when `mode == .soundtrack`.
/// Shows logo, title, sub-line, volume, pause, and a "Switch to mix" link if a
/// saved mix exists to fall back to.
struct SoundtrackPanel: View {
    let soundtrack: WebSoundtrack
    let paused: Bool
    let canSwitchToMix: Bool
    let onTogglePause: () -> Void
    let onVolumeChange: (Double) -> Void
    let onSwitchToMix: () -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                providerGlyph

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .xnText(.primary)
                    HStack(spacing: 6) {
                        Text(soundtrack.kind.rawValue)
                            .font(.system(size: 10.5))
                            .xnText(.tertiary)
                        ThumblessSlider(
                            value: Binding(get: { soundtrack.volume }, set: onVolumeChange),
                            tint: Color.white.opacity(0.55)
                        )
                        .frame(width: 110)
                    }
                }

                Spacer(minLength: 4)

                Button(action: onTogglePause) {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.055 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .onHover { hovered = $0 }

            if canSwitchToMix {
                Button(action: onSwitchToMix) {
                    Text("Switch to mix")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private var displayTitle: String {
        if let t = soundtrack.title, !t.isEmpty { return t }
        switch soundtrack.kind {
        case .youtube: return "YouTube"
        case .spotify: return "Spotify"
        }
    }

    private var providerGlyph: some View {
        let symbol: String = soundtrack.kind == .youtube ? "play.rectangle.fill" : "music.note"
        let tint: Color = soundtrack.kind == .youtube
            ? Color(red: 1.00, green: 0.00, blue: 0.00)
            : Color(red: 0.11, green: 0.73, blue: 0.33)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.18))
            .frame(width: 22, height: 22)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}
