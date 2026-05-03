import SwiftUI

/// Row for a single soundtrack on the Soundtracks tab. Shows logo, title, sub-line,
/// active chip if this is the active soundtrack, and trailing `⌃`/`⋯` controls.
///
/// When `isExpanded` is true, the row embeds the live player vended by the
/// soundtrack controller via `playerView()` — the row itself doesn't know or care
/// that the underlying implementation is a WKWebView, and never imports WebKit.
struct SoundtrackChipRow: View {
    let soundtrack: WebSoundtrack
    let isActive: Bool
    let isExpanded: Bool
    let controller: WebSoundtrackControlling
    let pulseChevron: Bool
    let onTap: () -> Void
    let onExpandToggle: () -> Void
    let onDelete: () -> Void
    let pool: [String]
    let onTagsChange: ([String]) -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            collapsedRow

            if isExpanded {
                controller.playerView()
                    .frame(height: 220)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                TagEditorStrip(
                    tags: soundtrack.tags,
                    pool: pool,
                    onChange: onTagsChange
                )

                HStack {
                    Spacer()
                    Button("Done", action: onExpandToggle)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isActive)
        .animation(.easeOut(duration: 0.20), value: isExpanded)
    }

    private var collapsedRow: some View {
        HStack(spacing: 10) {
            providerGlyph

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .shText(.primary)
                    if isActive { activeChip }
                }
                Text(soundtrack.kind.rawValue)
                    .font(.system(size: 10.5))
                    .shText(.tertiary)
            }

            Spacer(minLength: 4)

            if isActive {
                Button(action: onExpandToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(pulseChevron ? design.accent : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .scaleEffect(pulseChevron ? 1.06 : 1.0)
                        .animation(
                            pulseChevron
                              ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                              : .default,
                            value: pulseChevron
                        )
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide player" : "Reveal player")
            }

            Menu {
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
        }
        .onTapGesture(perform: onTap)
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
            YouTubeThumbnail(url: thumb, size: 32)
        } else {
            let symbol: String = soundtrack.kind == .youtube ? "play.rectangle.fill" : "music.note"
            let tint: Color = soundtrack.kind == .youtube
                ? Color(red: 1.00, green: 0.00, blue: 0.00)
                : Color(red: 0.11, green: 0.73, blue: 0.33)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                )
        }
    }

    private var activeChip: some View {
        Text("ACTIVE")
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(design.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(design.accent.opacity(0.15))
            )
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(hovered ? 0.055 : 0.035))
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                isActive ? design.accent : Color.white.opacity(0.08),
                lineWidth: isActive ? 1.5 : 1
            )
    }
}
