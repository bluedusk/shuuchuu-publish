import SwiftUI

struct CategoryTabs: View {
    let categories: [Category]
    @Binding var selected: String?
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { cat in
                        Button(cat.name) { selected = cat.id }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassEffect(
                                selected == cat.id
                                    ? .regular.tint(.accentColor)
                                    : .regular
                            )
                            .glassEffectID(cat.id, in: ns)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}
