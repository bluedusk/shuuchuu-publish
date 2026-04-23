import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 0) {
                CategoryTabs(
                    categories: model.categories,
                    selected: Binding(
                        get: { model.selectedCategoryId },
                        set: { if let id = $0 { model.selectCategory(id) } }
                    )
                )

                Divider()

                TrackGrid(
                    tracks: selectedTracks,
                    tileState: tileState(for:),
                    onTap: { track in
                        Task { await handleTap(track) }
                    }
                )
                .transition(.blurReplace)

                Divider()

                NowPlayingBar(
                    currentTrack: model.currentTrack,
                    isPlaying: isPlaying,
                    volume: Binding(
                        get: { model.audio.volume },
                        set: { model.setVolume($0) }
                    ),
                    onPlayPause: {
                        Task { await togglePlayback() }
                    }
                )
            }
        }
        .frame(width: 360, height: 480)
        .task {
            if model.categories.isEmpty {
                await model.loadCatalog()
            }
        }
    }

    private var selectedTracks: [Track] {
        guard let selId = model.selectedCategoryId,
              let cat = model.categories.first(where: { $0.id == selId })
        else { return [] }
        return cat.tracks
    }

    private var isPlaying: Bool {
        if case .playing = model.audio.state { return true }
        return false
    }

    private func tileState(for track: Track) -> TrackTile.TileState {
        switch model.audio.state {
        case .playing(let id) where id == track.id:
            return .playing
        case .loading(let id) where id == track.id:
            return .loading(progress: 0)
        default:
            return .idle(cached: true)
        }
    }

    private func handleTap(_ track: Track) async {
        if case .playing(let id) = model.audio.state, id == track.id {
            await model.stop()
        } else {
            await model.play(track)
        }
    }

    private func togglePlayback() async {
        if case .playing = model.audio.state {
            await model.stop()
        } else if let current = model.currentTrack {
            await model.play(current)
        }
    }
}
