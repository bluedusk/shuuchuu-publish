import SwiftUI

/// Body of the Soundtracks tab — the user's saved-soundtracks library plus
/// paste-flow header and one-shot Spotify hint.
struct SoundtracksTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var library: SoundtracksLibrary
    @EnvironmentObject var design: DesignSettings

    @State private var addingMode = false
    @State private var expandedRowId: WebSoundtrack.ID?

    private static let hintFlagKey = "x-noise.hasSeenSpotifyLoginHint"

    var body: some View {
        VStack(spacing: 0) {
            if addingMode {
                AddSoundtrackHeader(
                    onCommit: { withAnimation(.easeOut(duration: 0.18)) { addingMode = false } },
                    onCancel: { withAnimation(.easeOut(duration: 0.18)) { addingMode = false } }
                )
            } else {
                sectionHeader
            }

            ScrollView {
                VStack(spacing: 8) {
                    if library.entries.isEmpty {
                        emptyCard
                    } else {
                        ForEach(library.entries) { entry in
                            SoundtrackChipRow(
                                soundtrack: entry,
                                isActive: model.mode == .soundtrack(entry.id),
                                onTap: { tapRow(entry) },
                                onExpandToggle: { toggleExpand(entry) },
                                onDelete: { model.removeSoundtrack(id: entry.id) }
                            )
                        }
                    }

                    if shouldShowSpotifyHint {
                        spotifyHint.padding(.top, 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: - Section header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Text("MY SOUNDTRACKS")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.white.opacity(0.40))
            Text("\(library.entries.count)")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.30))
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.18)) { addingMode = true }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Paste a YouTube or Spotify URL")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Empty state

    private var emptyCard: some View {
        VStack(spacing: 4) {
            Text("No saved soundtracks yet")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.45))
            Text("Paste a YouTube or Spotify link")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    // MARK: - Spotify hint

    private var shouldShowSpotifyHint: Bool {
        guard !UserDefaults.standard.bool(forKey: Self.hintFlagKey) else { return false }
        return library.entries.contains(where: { $0.kind == .spotify })
    }

    private var spotifyHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(design.accent)
                .padding(.top, 1)
            Text("First time? Tap the chevron on a Spotify soundtrack to sign in. Your login is saved on this device after that.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(design.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            UserDefaults.standard.set(true, forKey: Self.hintFlagKey)
        }
    }

    // MARK: - Actions

    private func tapRow(_ entry: WebSoundtrack) {
        if model.mode == .soundtrack(entry.id) {
            model.deactivateSoundtrack()
            if expandedRowId == entry.id { expandedRowId = nil }
        } else {
            model.activateSoundtrack(id: entry.id)
        }
    }

    private func toggleExpand(_ entry: WebSoundtrack) {
        if expandedRowId == entry.id {
            expandedRowId = nil
        } else {
            expandedRowId = entry.id
        }
    }
}
