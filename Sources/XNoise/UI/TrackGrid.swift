import SwiftUI

struct TrackGrid: View {
    let tracks: [Track]
    let tileState: (Track) -> TrackTile.TileState
    let onTap: (Track) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tracks) { track in
                    TrackTile(track: track, state: tileState(track)) {
                        onTap(track)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }
}
