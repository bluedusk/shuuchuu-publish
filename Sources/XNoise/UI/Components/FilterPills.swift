import SwiftUI

/// One pill in the filter row.
struct FilterPill: Identifiable, Equatable {
    let id: String
    let title: String
    /// If true, render in warm gold (used for ★ Favorites).
    let isStar: Bool

    init(id: String, title: String, isStar: Bool = false) {
        self.id = id
        self.title = title
        self.isStar = isStar
    }
}

/// Multi-select pill row for filtering the Sounds grid. Tap a pill to toggle it.
/// `selected` is the set of currently active pill ids; `onToggle` flips one.
struct FilterPills: View {
    let pills: [FilterPill]
    let selected: Set<String>
    let onToggle: (String) -> Void

    @EnvironmentObject var design: DesignSettings

    var body: some View {
        HStack(spacing: 0) {
            FlowLayout(spacing: 4) {
                ForEach(pills) { pill in
                    pillView(pill)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.15))
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    private func pillView(_ pill: FilterPill) -> some View {
        let isOn = selected.contains(pill.id)
        let label = pill.isStar ? "★" : pill.title
        return Button { onToggle(pill.id) } label: {
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .kerning(0.1)
                .padding(.horizontal, pill.isStar ? 7 : 9)
                .padding(.vertical, 4)
                .foregroundStyle(foreground(pill: pill, isOn: isOn))
                .background(
                    Capsule().fill(isOn ? design.accent.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? design.accent.opacity(0.45) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func foreground(pill: FilterPill, isOn: Bool) -> Color {
        if isOn { return .white }
        if pill.isStar { return Color(red: 1.0, green: 0.83, blue: 0.42) }
        return Color.white.opacity(0.55)
    }
}

/// Minimal flow layout — wraps children to multiple rows when they exceed the proposed width.
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
