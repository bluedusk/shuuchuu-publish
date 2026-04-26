import SwiftUI

/// Section descriptor for the jump-pill nav. The id must match the `.id(...)` set on the
/// section header in the scroll body so `ScrollViewReader.scrollTo` can locate it.
struct JumpSection: Identifiable, Equatable {
    let id: String
    let title: String
    /// If true, this pill is rendered in warm gold (used for ★ Favorites).
    let isStar: Bool

    init(id: String, title: String, isStar: Bool = false) {
        self.id = id
        self.title = title
        self.isStar = isStar
    }
}

/// Wrapping pill row pinned beneath the tab bar on the Sounds tab. Each pill is a tap target
/// that scroll-jumps to the corresponding section. The pill matching `currentSectionId`
/// is highlighted in the accent color.
struct JumpPills: View {
    let sections: [JumpSection]
    let currentSectionId: String?
    let onTap: (String) -> Void

    @EnvironmentObject var design: DesignSettings

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(sections) { section in
                pill(section)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.15))
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    private func pill(_ section: JumpSection) -> some View {
        let isCurrent = section.id == currentSectionId
        let label = section.isStar ? "★" : section.title
        return Button { onTap(section.id) } label: {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .kerning(0.2)
                .padding(.horizontal, section.isStar ? 7 : 9)
                .padding(.vertical, 4)
                .foregroundStyle(pillForeground(section: section, isCurrent: isCurrent))
                .background(
                    Capsule().fill(isCurrent ? design.accent.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        isCurrent ? design.accent.opacity(0.45)
                                  : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func pillForeground(section: JumpSection, isCurrent: Bool) -> Color {
        if isCurrent { return .white }
        if section.isStar { return Color(red: 1.0, green: 0.83, blue: 0.42) }
        return Color.white.opacity(0.55)
    }
}

/// Minimal flow layout — wraps children to multiple rows when they exceed the proposed width.
/// macOS 13+; we target 26 so this is fine.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            let extraWidth = rows[rows.count - 1].isEmpty ? 0 : spacing
            if rowWidth + extraWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                totalHeight += currentRowHeight + spacing
                rows.append([])
                rowWidth = 0
                currentRowHeight = 0
            }
            rows[rows.count - 1].append(size)
            rowWidth += extraWidth + size.width
            currentRowHeight = max(currentRowHeight, size.height)
        }
        totalHeight += currentRowHeight
        let usedWidth = min(maxWidth, rows.map { row in
            row.enumerated().reduce(0.0) { $0 + $1.element.width + ($1.offset == 0 ? 0 : spacing) }
        }.max() ?? 0)
        return CGSize(width: usedWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x != bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
