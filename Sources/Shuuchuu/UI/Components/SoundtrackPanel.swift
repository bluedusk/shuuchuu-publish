import SwiftUI
import AppKit

/// Single-soundtrack panel rendered on the Focus page when `mode == .soundtrack`.
/// Shows logo, title, sub-line, volume, pause, and a "Switch to mix" link if a
/// saved mix exists to fall back to.
struct SoundtrackPanel: View {
    let soundtrack: WebSoundtrack
    let paused: Bool
    let canSwitchToMix: Bool
    let errorCode: Int?
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
                        .shText(.primary)
                    HStack(spacing: 6) {
                        Text(soundtrack.kind.rawValue)
                            .font(.system(size: 10.5))
                            .shText(.tertiary)
                        ThumblessSlider(
                            value: Binding(get: { soundtrack.volume }, set: onVolumeChange),
                            tint: Color.white.opacity(0.55)
                        )
                        .frame(width: 110)
                    }
                }

                Spacer(minLength: 4)

                if let external = soundtrack.externalURL {
                    Button(action: { NSWorkspace.shared.open(external) }) {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(hovered ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: hovered)
                    .help("Open in browser")
                }

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

            if let code = errorCode {
                Text(errorMessage(for: code))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.4))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

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

    private func errorMessage(for code: Int) -> String {
        switch code {
        case 100: return "Video not available (removed or private)"
        case 101, 150, 152: return "Embedding disabled by the publisher — try a different video"
        case 2: return "Invalid video URL"
        case 5: return "Player error — try again"
        default: return "Playback failed (code \(code))"
        }
    }

    private var displayTitle: String {
        if let t = soundtrack.title, !t.isEmpty { return t }
        switch soundtrack.kind {
        case .youtube: return "YouTube"
        case .spotify: return "Spotify"
        }
    }

    @ViewBuilder
    private var providerGlyph: some View {
        if let thumb = soundtrack.youtubeThumbnailURL {
            YouTubeThumbnail(url: thumb, size: 36)
        } else {
            let symbol: String = soundtrack.kind == .youtube ? "play.rectangle.fill" : "music.note"
            let tint: Color = soundtrack.kind == .youtube
                ? Color(red: 1.00, green: 0.00, blue: 0.00)
                : Color(red: 0.11, green: 0.73, blue: 0.33)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.18))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                )
        }
    }
}
