import SwiftUI

/// Vertical card row for the Mixes tab. Renders a `MixDisplay` (custom or preset),
/// optionally highlighted as the currently-loaded mix. Custom mixes get an inline
/// delete-confirm overlay when the user opens the ⋯ menu and chooses Delete.
struct MixRow: View {
    let mix: MixDisplay
    let isActive: Bool
    /// Resolves a track id to a display name for the sub-line. Tracks not in the catalog
    /// (e.g. removed in an update) are omitted from the sub-line.
    let trackName: (String) -> String?
    let onApply: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var confirmingDelete = false

    var body: some View {
        if confirmingDelete {
            confirmRow
        } else {
            applyRow
        }
    }

    private var rowBackground: Color {
        switch mix {
        case .custom: return Color.white.opacity(0.04)
        case .preset: return XNTokens.accent(hue: design.accentHue).opacity(0.07)
        }
    }

    private var rowBorder: Color {
        if isActive { return design.accent.opacity(0.6) }
        switch mix {
        case .custom: return Color.white.opacity(0.08)
        case .preset: return design.accent.opacity(0.18)
        }
    }

    private var applyRow: some View {
        Button(action: onApply) {
            HStack(spacing: 10) {
                MixIconStack(trackIds: mix.trackIds, rowBackground: solidRowBg)
                    .frame(width: 56, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mix.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .xnText(.primary)
                    Text(subline)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .xnText(.tertiary)
                    if isActive {
                        Text("▶ ACTIVE")
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(design.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(design.accent.opacity(0.15))
                            )
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                if mix.isCustom {
                    Menu {
                        Button("Delete", role: .destructive) {
                            confirmingDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(rowBorder, lineWidth: isActive ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A solid color matching the row fill, used for icon-bubble cut-outs.
    private var solidRowBg: Color {
        // Liquid Glass over a wallpaper makes computing a literal compositor color hard;
        // approximate with a near-popover-bg solid so the cut-outs read as a clean punch.
        Color(red: 0.10, green: 0.12, blue: 0.16)
    }

    private var subline: String {
        let resolved = mix.trackIds.compactMap(trackName)
        let total = mix.trackIds.count
        let available = resolved.count
        // If catalog is missing some tracks, surface that explicitly per spec §9.
        let countText: String
        if available < total {
            countText = "\(available) of \(total) sounds available"
        } else {
            countText = "\(total) sound\(total == 1 ? "" : "s")"
        }
        let names = resolved.prefix(3).joined(separator: " · ")
        return names.isEmpty ? countText : "\(countText) · \(names)"
    }

    private var confirmRow: some View {
        HStack(spacing: 8) {
            Text("Delete \"\(mix.name)\"?")
                .font(.system(size: 12))
                .xnText(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Cancel") { confirmingDelete = false }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .xnText(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            Button {
                onDelete()
                confirmingDelete = false
            } label: {
                Text("Delete")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.red.opacity(0.45), lineWidth: 1)
        )
    }
}
