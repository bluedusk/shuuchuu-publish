import SwiftUI

/// Overlapping row of up to 3 mini track icons. If more tracks exist, the last slot shows
/// "+N" instead. Each icon is 22×22pt with a 6pt corner radius and a 1.5pt cut-out border
/// in the row's background color so overlap reads cleanly.
struct MixIconStack: View {
    let trackIds: [String]
    /// The color the icon borders cut out to. Should match the parent row's fill so overlaps
    /// look like punches, not seams. Defaults to clear (no cut-out).
    var rowBackground: Color = .clear

    private let maxVisible = 3
    private let iconSize: CGFloat = 22
    private let overlap: CGFloat = 6  // pt of horizontal overlap between adjacent icons

    var body: some View {
        let visible = Array(trackIds.prefix(maxVisible))
        let overflow = max(0, trackIds.count - maxVisible)
        HStack(spacing: -overlap) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, id in
                iconBubble(systemName: TrackIconMap.icon(for: id).symbol)
            }
            if overflow > 0 {
                iconBubble(text: "+\(overflow)")
            }
        }
    }

    private func iconBubble(systemName: String? = nil, text: String? = nil) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.06))
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
            } else if let text {
                Text(text)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: iconSize, height: iconSize)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(rowBackground, lineWidth: 1.5)
        )
    }
}
