import SwiftUI
import WebKit
import AppKit

/// Row for a single soundtrack on the Soundtracks tab. Shows logo, title, sub-line,
/// active chip if this is the active soundtrack, and trailing `⌃`/`⋯` controls.
///
/// When `isExpanded` is true (Task 17), the row embeds the live WKWebView from the
/// `WebSoundtrackController` inline below the collapsed header row.
struct SoundtrackChipRow: View {
    let soundtrack: WebSoundtrack
    let isActive: Bool
    let isExpanded: Bool
    let controller: WebSoundtrackController
    let pulseChevron: Bool
    let onTap: () -> Void
    let onExpandToggle: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            collapsedRow

            if isExpanded {
                LiveSoundtrackEmbed(controller: controller)
                    .frame(height: 220)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .onDisappear { controller.reclaimWebView() }

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
                .padding(.top, 8)
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
                        .xnText(.primary)
                    if isActive { activeChip }
                }
                Text(soundtrack.kind.rawValue)
                    .font(.system(size: 10.5))
                    .xnText(.tertiary)
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

    private var providerGlyph: some View {
        let symbol: String = soundtrack.kind == .youtube ? "play.rectangle.fill" : "music.note"
        let tint: Color = soundtrack.kind == .youtube
            ? Color(red: 1.00, green: 0.00, blue: 0.00)
            : Color(red: 0.11, green: 0.73, blue: 0.33)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.18))
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            )
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

/// SwiftUI host for the live WKWebView owned by `WebSoundtrackController`. When
/// this representable appears, it pulls the web view out of the hidden window into
/// a container view; on disappear (parent), the row calls `controller.reclaimWebView()`.
struct LiveSoundtrackEmbed: NSViewRepresentable {
    let controller: WebSoundtrackController

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.wantsLayer = true
        host.layer?.cornerRadius = 8
        host.layer?.masksToBounds = true

        let web = controller.hostedWebView
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: host.topAnchor),
            web.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
