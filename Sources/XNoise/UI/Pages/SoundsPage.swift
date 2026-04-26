import SwiftUI

struct SoundsPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var favorites: Favorites
    @EnvironmentObject var state: MixState

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            header
            pills
            grid
            presetsStrip
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left") { model.goTo(.focus) }
            VStack(alignment: .leading, spacing: 1) {
                Text("SOUNDS")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.72)
                    .xnText(.secondary)
                Text("\(state.count) in current mix")
                    .font(.system(size: 12))
                    .xnText(.primary)
            }
            Spacer()
            Button { model.goTo(.focus) } label: {
                Text("Save mix")
                    .font(.system(size: 11, weight: .medium))
                    .xnText(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(CategoryFilter.allCases, id: \.self) { f in
                    pill(f)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
    }

    private func pill(_ f: CategoryFilter) -> some View {
        let isOn = model.categoryFilter == f
        return Button { model.categoryFilter = f } label: {
            Text(f.display)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? Color.primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(isOn ? 0.14 : 0.04)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0.30 : 0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var filteredTracks: [Track] {
        switch model.categoryFilter {
        case .all:
            return model.allTracks.map(\.track)
        case .favorites:
            return model.allTracks.filter { favorites.contains($0.track.id) }.map(\.track)
        default:
            return model.allTracks.filter { $0.filter == model.categoryFilter }.map(\.track)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(filteredTracks) { track in
                    let mixTrack = state.track(track.id)
                    SoundTile(
                        track: track,
                        isOn: mixTrack != nil,
                        volume: mixTrack?.volume ?? 0,
                        isFavorite: favorites.contains(track.id),
                        onTap: { model.toggleTrack(track) },
                        onVolumeChange: { v in model.setTrackVolume(track.id, v) },
                        onToggleFav: { favorites.toggle(track.id) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }

    private var presetsStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRESETS")
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.72)
                .xnText(.secondary)
                .padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Presets.all) { preset in
                        Button {
                            model.applyPreset(preset)
                        } label: {
                            Text(preset.name)
                                .font(.system(size: 11, weight: .medium))
                                .xnText(.primary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .glassChip(cornerRadius: 14, design: design)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .overlay(Divider().opacity(0.3), alignment: .top)
    }
}
