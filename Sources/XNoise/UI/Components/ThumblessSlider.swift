import SwiftUI

/// 3pt-tall capsule volume slider with no thumb. The hit region matches the visible
/// 3pt bar exactly (no extended tracking area), so the cursor doesn't flip when
/// passing over the chip.
struct ThumblessSlider: View {
    @Binding var value: Double
    var tint: Color = .white.opacity(0.55)
    @State private var width: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(height: 3)
            Capsule()
                .fill(tint)
                .frame(width: max(0, width * value), height: 3)
        }
        .frame(height: 3)
        .contentShape(Rectangle())
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
