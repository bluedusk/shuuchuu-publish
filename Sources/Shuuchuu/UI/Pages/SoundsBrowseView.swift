import SwiftUI

/// Body of the Sounds tab. Multi-select pill row at the top filters which catalog
/// categories appear below. The ★ pill, when selected, additionally narrows visible
/// tracks to favorites only. With no pills selected, every category and every track
/// is shown.
struct SoundsBrowseView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var favorites: Favorites
    @EnvironmentObject var state: MixState
    @EnvironmentObject var mixer: MixingController

    @State private var selectedFilters: Set<String> = []

    private let columnsPerRow = 2
    private let chipSpacing: CGFloat = 8
    private let bodyHorizontalPadding: CGFloat = 12
    private let favoritesPillId = "★"

    /// Pills to show in the filter row: ★ first, then one per catalog category.
    private var pills: [FilterPill] {
        var result: [FilterPill] = [FilterPill(id: favoritesPillId, title: "★", isStar: true)]
        for cat in model.categories {
            result.append(FilterPill(id: cat.id, title: cat.name))
        }
        return result
    }

    /// Visible sections after applying filters.
    /// Category filtering: if any non-★ pill is selected, only those categories appear;
    /// otherwise all categories appear. Within each section, if ★ is selected, only
    /// favorited tracks remain; sections that become empty are dropped.
    private var visibleSections: [Category] {
        let categoryFilters = selectedFilters.subtracting([favoritesPillId])
        let starOn = selectedFilters.contains(favoritesPillId)

        let baseSections = categoryFilters.isEmpty
            ? model.categories
            : model.categories.filter { categoryFilters.contains($0.id) }

        return baseSections.compactMap { cat in
            let tracks = starOn
                ? cat.tracks.filter { favorites.contains($0.id) }
                : cat.tracks
            return tracks.isEmpty ? nil : Category(id: cat.id, name: cat.name, tracks: tracks)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterPills(
                pills: pills,
                selected: selectedFilters,
                onToggle: { id in
                    if selectedFilters.contains(id) {
                        selectedFilters.remove(id)
                    } else {
                        selectedFilters.insert(id)
                    }
                }
            )
            scrollBody
        }
    }

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if visibleSections.isEmpty {
                    emptyPlaceholder
                } else {
                    ForEach(visibleSections) { section in
                        sectionView(section)
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
    }

    private var emptyPlaceholder: some View {
        Text("No sounds match the selected filters.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 32)
    }

    private func sectionView(_ section: Category) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.white.opacity(0.40))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)

            VStack(spacing: chipSpacing) {
                ForEach(rows(section.tracks), id: \.0) { _, rowTracks in
                    HStack(spacing: chipSpacing) {
                        ForEach(rowTracks) { track in
                            let mixTrack = state.track(track.id)
                            let isFailed = mixer.failed.contains(track.id)
                            SoundChip(
                                track: track,
                                isOn: mixTrack != nil,
                                volume: mixTrack?.volume ?? 0,
                                isFavorite: favorites.contains(track.id),
                                isPreparing: mixer.preparing.contains(track.id),
                                isFailed: isFailed,
                                onTap: {
                                    if isFailed { model.retryTrack(track.id) }
                                    else { model.toggleTrack(track) }
                                },
                                onVolumeChange: { v in model.setTrackVolume(track.id, v) },
                                onAdjustVolume: { delta in
                                    let cur = state.track(track.id)?.volume ?? 0
                                    model.setTrackVolume(track.id, max(0, min(1, cur + delta)))
                                },
                                onToggleFav: { favorites.toggle(track.id) }
                            )
                        }
                        ForEach(0..<(columnsPerRow - rowTracks.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal, bodyHorizontalPadding)
        }
    }

    /// Splits a track list into rows of `columnsPerRow`.
    private func rows(_ tracks: [Track]) -> [(Int, [Track])] {
        stride(from: 0, to: tracks.count, by: columnsPerRow).enumerated().map { idx, start in
            (idx, Array(tracks[start ..< min(start + columnsPerRow, tracks.count)]))
        }
    }
}
