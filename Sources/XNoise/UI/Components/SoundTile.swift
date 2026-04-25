import SwiftUI

/// Pressable sound tile on the Sounds page. On when active in the mix.
/// Shows a favorite star in the top-right.
struct SoundTile: View {
    let track: Track
    let isOn: Bool
    let volume: Float
    let isFavorite: Bool
    let onTap: () -> Void
    let onToggleFav: () -> Void

    @EnvironmentObject var design: DesignSettings

    private var icon: TrackIcon { TrackIconMap.icon(for: track.id) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            tileButton
            favoriteStar
        }
    }

    private var tileButton: some View {
        Button(action: onTap) { tileContent }
            .buttonStyle(.plain)
    }

    private var tileContent: some View {
        VStack(spacing: 5) {
            Spacer(minLength: 0)
            iconGlyph
            nameLabel
            Spacer(minLength: 0)
            if isOn { volumeBar }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(tileBackground)
        .overlay(tileBorder)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: isOn ? design.accent.opacity(0.45) : .clear, radius: 6, y: 3)
    }

    private var iconGlyph: some View {
        Image(systemName: icon.symbol)
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(isOn ? Color.white : .primary.opacity(0.75))
    }

    private var nameLabel: some View {
        Text(track.name)
            .font(.system(size: 9.5, weight: .medium))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .foregroundStyle(isOn ? Color.white : .primary.opacity(0.7))
    }

    private var volumeBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * Double(volume))
                    .shadow(color: .white.opacity(0.9), radius: 3)
            }
            .frame(height: 2)
        }
        .frame(height: 2)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var tileBackground: some View {
        if isOn {
            LinearGradient(
                colors: [design.accent.opacity(0.88), design.accentDark.opacity(0.88)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        } else {
            Color.white.opacity(0.04)
                .background(.ultraThinMaterial)
        }
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.white.opacity(isOn ? 0.40 : 0.15), lineWidth: 1)
    }

    private var favoriteStar: some View {
        Button(action: onToggleFav) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(starColor)
                .padding(5)
        }
        .buttonStyle(.plain)
    }

    private var starColor: Color {
        if isFavorite { return Color(red: 1.0, green: 0.83, blue: 0.42) }
        return isOn ? Color.white.opacity(0.55) : .secondary.opacity(0.65)
    }
}
