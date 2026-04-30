import SwiftUI

struct ScenePicker: View {
    let scenes: [Scene]
    let activeId: String?
    let onSelect: (String?) -> Void

    private static let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scenes")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 14)

            if scenes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 12) {
                        noneTile
                        ForEach(scenes) { scene in
                            sceneTile(scene)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(width: 280, height: 360)
        .background(.regularMaterial)
    }

    private var noneTile: some View {
        Button { onSelect(nil) } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.4))
                    Image(systemName: "circle.slash")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(height: 75)
                .overlay(activeId == nil ? selectionRing : nil)
                Text("None")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func sceneTile(_ scene: Scene) -> some View {
        Button { onSelect(scene.id) } label: {
            VStack(spacing: 4) {
                thumbnail(scene)
                    .frame(height: 75)
                    .overlay(activeId == scene.id ? selectionRing : nil)
                Text(scene.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(_ scene: Scene) -> some View {
        if let img = thumbnailImage(scene) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.5))
        }
    }

    private func thumbnailImage(_ scene: Scene) -> NSImage? {
        // SPM `process` resources flatten paths; thumbnails live alongside .metal
        // files but appear at the bundle root. Look up by stem.
        let stem = (scene.thumbnail as NSString).deletingPathExtension
        guard let url = Bundle.module.url(forResource: stem,
                                          withExtension: "jpg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private var selectionRing: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor, lineWidth: 2)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No scenes installed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Drop .metal files into\nSources/Shuuchuu/Resources/shaders/")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
