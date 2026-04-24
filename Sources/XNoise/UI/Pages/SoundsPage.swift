import SwiftUI

struct SoundsPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @ObservedObject var favorites: Favorites
    @ObservedObject var mixer: MixingController

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
                Text("Sounds").font(.system(size: 13, weight: .semibold))
                Text("\(mixer.live.count) in current mix")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { model.goTo(.focus) }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [design.accent, design.accentDark],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                )
                .shadow(color: design.accent.opacity(0.6), radius: 8)
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
        return Button(action: { model.categoryFilter = f }) {
            Text(f.display)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isOn ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.white.opacity(isOn ? 0.14 : 0.04))
                )
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(isOn ? 0.30 : 0.12), lineWidth: 1)
                )
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
                    let live = mixer.live[track.id]
                    SoundTile(
                        track: track,
                        isOn: live != nil,
                        volume: live?.volume ?? 0,
                        isFavorite: favorites.contains(track.id),
                        onTap: { Task { await model.toggleTrack(track) } },
                        onToggleFav: { favorites.toggle(track.id) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    private var presetsStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRESETS")
                .font(.system(size: 9.5, weight: .medium))
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Presets.all) { preset in
                        Button(preset.name) {
                            Task { await model.applyPreset(preset) }
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .glassChip(cornerRadius: 14, design: design)
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
