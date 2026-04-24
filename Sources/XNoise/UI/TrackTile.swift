import SwiftUI

struct TrackTile: View {
    let track: Track
    let state: TileState
    let onTap: () -> Void

    enum TileState: Equatable {
        case idle(cached: Bool)
        case loading(progress: Double)
        case playing
        case error
    }

    private var icon: TrackIcon { TrackIconMap.icon(for: track.id) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                artwork
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(glassOverlay)
                    .overlay(stateOverlay)
                    .shadow(color: icon.tint.opacity(0.35), radius: 6, y: 3)
                Text(track.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = track.artworkUrl {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                gradientArt
            }
        } else {
            gradientArt
        }
    }

    private var gradientArt: some View {
        ZStack {
            LinearGradient(
                colors: [
                    icon.tint.opacity(0.85),
                    icon.tint.opacity(0.45),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: icon.symbol)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
    }

    /// Subtle glass highlight + inner stroke so tiles feel like material, not flat rectangles.
    private var glassOverlay: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.45), .white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch state {
        case .idle(let cached):
            if !cached {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        case .loading(let progress):
            ZStack {
                Color.black.opacity(0.4)
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .playing:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white, lineWidth: 2.5)
                .shadow(color: .white.opacity(0.6), radius: 4)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .symbolEffect(.pulse)
                        .foregroundStyle(.white)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                )
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}
