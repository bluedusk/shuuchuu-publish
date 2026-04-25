import SwiftUI

/// 3pt-tall capsule volume slider with no thumb. The bar stays slim visually,
/// but the drag hit-zone is 14pt tall so it's easy to grab without aiming
/// precisely at the thin bar.
struct ThumblessSlider: View {
    @Binding var value: Double
    var tint: Color = .white.opacity(0.55)
    @State private var width: CGFloat = 0

    var body: some View {
        ZStack {
            // Visible 3pt bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 3)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, width * value), height: 3)
            }

            // Invisible 14pt hit slot — this is what the cursor and DragGesture see.
            Color.clear
                .frame(height: 14)
                .contentShape(Rectangle())
        }
        .frame(height: 14)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in width = new }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard width > 0 else { return }
                    let x = max(0, min(width, g.location.x))
                    value = Double(x / width)
                }
        )
    }
}
