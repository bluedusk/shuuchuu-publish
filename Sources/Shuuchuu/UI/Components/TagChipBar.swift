import SwiftUI

/// Horizontal-scrolling chip bar above the soundtrack list. One chip per tag in
/// `tags`. Tap to toggle `filter.selected`. Hidden by the parent when `tags` is
/// empty.
struct TagChipBar: View {
    let tags: [String]
    @EnvironmentObject var filter: SoundtracksFilterState
    @EnvironmentObject var design: DesignSettings

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    chip(tag)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private func chip(_ tag: String) -> some View {
        let active = filter.selected.contains(tag)
        return Button(action: { filter.toggle(tag) }) {
            Text(tag)
                .font(.system(size: 10))
                .foregroundStyle(active ? design.accent : Color.white.opacity(0.65))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(active ? design.accent.opacity(0.15)
                                     : Color.white.opacity(0.04))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            active ? design.accent : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
