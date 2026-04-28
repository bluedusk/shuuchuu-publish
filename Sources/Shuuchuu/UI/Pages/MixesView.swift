import SwiftUI

/// Body of the Mixes tab. Renders MY MIXES (user-saved) above PRESETS (built-in),
/// each as a stack of MixRow cards.
struct MixesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var savedMixes: SavedMixes

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(title: "MY MIXES", count: savedMixes.mixes.count)
                if savedMixes.mixes.isEmpty {
                    emptyCard
                } else {
                    VStack(spacing: 6) {
                        ForEach(savedMixes.mixes) { mix in
                            MixRow(
                                mix: .custom(mix),
                                isActive: model.currentlyLoadedMixId == AnyHashable(mix.id),
                                trackName: { id in model.findTrack(id: id)?.name },
                                onApply: { model.applySavedMix(mix) },
                                onDelete: { model.deleteMix(id: mix.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                }

                sectionHeader(title: "PRESETS", count: Presets.all.count)
                VStack(spacing: 6) {
                    ForEach(Presets.all) { preset in
                        MixRow(
                            mix: .preset(preset),
                            isActive: model.currentlyLoadedMixId == AnyHashable(preset.id),
                            trackName: { id in model.findTrack(id: id)?.name },
                            onApply: { model.applyPreset(preset) },
                            onDelete: {}  // presets don't surface delete
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .scrollIndicators(.never)
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .xnText(.tertiary)
            Text("\(count)")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.30))
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var emptyCard: some View {
        VStack(spacing: 4) {
            Text("No saved mixes yet")
                .font(.system(size: 11))
                .xnText(.tertiary)
            Text("Build a mix on the Sounds tab and tap \"Save mix\"")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .padding(.horizontal, 12)
    }
}
