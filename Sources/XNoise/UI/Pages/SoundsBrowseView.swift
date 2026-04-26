import SwiftUI

/// Body of the Sounds tab. Sectioned grid of tiles by catalog category, with a ★ Favorites
/// section pinned at the top (auto-hidden if empty). The JumpPills bar is wired to the
/// scroll position — tapping a pill scroll-jumps to that section, and the pill matching
/// the currently topmost section is highlighted.
struct SoundsBrowseView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var favorites: Favorites
    @EnvironmentObject var state: MixState

    @State private var currentSectionId: String?

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    private struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        let isStar: Bool
        let tracks: [Track]
    }

    private var sections: [Section] {
        var result: [Section] = []
        let favTracks = model.allTracks.map(\.track).filter { favorites.contains($0.id) }
        if !favTracks.isEmpty {
            result.append(.init(id: "favorites", title: "★ Favorites", isStar: true, tracks: favTracks))
        }
        for cat in model.categories {
            result.append(.init(id: cat.id, title: cat.name, isStar: false, tracks: cat.tracks))
        }
        return result
    }

    private var jumpSections: [JumpSection] {
        sections.map { section in
            let pillTitle = section.title.replacingOccurrences(of: "★ ", with: "")
            return JumpSection(id: section.id, title: pillTitle, isStar: section.isStar)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            JumpPills(
                sections: jumpSections,
                currentSectionId: currentSectionId,
                onTap: { id in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scrollProxy?.scrollTo(id, anchor: .top)
                    }
                }
            )
            scrollBody
        }
        .onAppear {
            if currentSectionId == nil { currentSectionId = sections.first?.id }
        }
    }

    @State private var scrollProxy: ScrollViewProxy?

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        sectionView(section)
                            .id(section.id)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: SectionMinYKey.self,
                                        value: [section.id: geo.frame(in: .named("soundsScroll")).minY]
                                    )
                                }
                            )
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            .coordinateSpace(name: "soundsScroll")
            .onPreferenceChange(SectionMinYKey.self) { frames in
                // The "current" section is the last one whose minY <= 1 (i.e. has crossed the
                // scroll-area top). If none have crossed yet, fall back to the first section.
                let crossed = frames.filter { $0.value <= 1 }
                let pick = crossed.max(by: { $0.value < $1.value })?.key ?? sections.first?.id
                if pick != currentSectionId { currentSectionId = pick }
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(section.isStar ? Color(red: 1.0, green: 0.83, blue: 0.42).opacity(0.7)
                                                : Color.white.opacity(0.40))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)

            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(section.tracks) { track in
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
        }
    }
}

/// Reports each section's minY in the scroll's coordinate space so SoundsBrowseView can
/// decide which section is currently topmost.
private struct SectionMinYKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
