import SwiftUI

/// Hue-picker slider: track is a continuous OKLCH rainbow at fixed L/C, the
/// thumb is a small circle filled with the current accent that you drag along
/// the rainbow. No gray inactive portion — both sides of the thumb show the
/// hues you'd land on.
struct HueSlider: View {
    @Binding var hue: Double            // 0…360
    var trackHeight: CGFloat = 6
    var thumbSize: CGFloat = 16
    var theme: AppTheme = .dark

    @State private var width: CGFloat = 0

    private var rainbow: [Color] {
        // Sample the hue circle at fixed L/C (matches XNTokens.accent values).
        stride(from: 0, through: 360, by: 30).map {
            Color(oklchL: 0.74, C: 0.14, H: Double($0))
        }
    }

    private var thumbX: CGFloat {
        max(thumbSize / 2,
            min(width - thumbSize / 2,
                (hue / 360.0) * width))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Rainbow track
            LinearGradient(colors: rainbow, startPoint: .leading, endPoint: .trailing)
                .frame(height: trackHeight)
                .clipShape(Capsule())

            // Thumb — small circle filled with the current accent
            Circle()
                .fill(XNTokens.accent(hue: hue, theme: theme))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.95), lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .frame(width: thumbSize, height: thumbSize)
                .offset(x: thumbX - thumbSize / 2)
        }
        .frame(height: max(trackHeight, thumbSize))
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
                    hue = Double(x / width) * 360.0
                }
        )
    }
}
