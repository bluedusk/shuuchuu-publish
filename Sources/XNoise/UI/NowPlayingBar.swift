import SwiftUI

struct NowPlayingBar: View {
    let currentTrack: Track?
    let isPlaying: Bool
    @Binding var volume: Float
    let onPlayPause: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let t = currentTrack {
                Image(systemName: "waveform.circle.fill").font(.title3)
                Text(t.name).font(.body).lineLimit(1)
            } else {
                Text("Nothing playing").foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)

            Image(systemName: "speaker.fill").font(.caption)
            Slider(value: $volume, in: 0...1).frame(width: 80)
            Image(systemName: "speaker.wave.3.fill").font(.caption)

            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
            .disabled(currentTrack == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular)
    }
}
