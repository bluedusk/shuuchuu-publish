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

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                artwork
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(stateOverlay)
                Text(track.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
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
                placeholderArt
            }
        } else {
            placeholderArt
        }
    }

    private var placeholderArt: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "waveform")
                .imageScale(.large)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch state {
        case .idle(let cached):
            if !cached {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.secondary)
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
        case .playing:
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, lineWidth: 3)
                .overlay(
                    Image(systemName: "waveform")
                        .symbolEffect(.pulse)
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
