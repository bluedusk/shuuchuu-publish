import SwiftUI

/// A customizable glass-panel modifier, parameterized by the tweakable blur/opacity/stroke.
struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    let stroke: Double
    let theme: AppTheme
    var sheen: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(alignment: .top) {
                ZStack {
                    Color.white.opacity(opacity)
                    if sheen {
                        RadialGradient(
                            colors: [Color.white.opacity(0.40), .clear],
                            center: .init(x: 0.20, y: -0.10),
                            startRadius: 10,
                            endRadius: 240
                        )
                        .blendMode(.overlay)
                    }
                }
            }
            .background(theme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.thinMaterial), in: shape)
            .overlay { shape.strokeBorder(Color.white.opacity(stroke), lineWidth: 1) }
            .clipShape(shape)
    }
}

struct GlassChip: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    let stroke: Double
    let theme: AppTheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(Color.white.opacity(opacity + 0.02))
            .background(.thinMaterial, in: shape)
            .overlay { shape.strokeBorder(Color.white.opacity(stroke + 0.06), lineWidth: 1) }
            .clipShape(shape)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 18, design: DesignSettings, sheen: Bool = true) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius,
                            opacity: design.glassOpacity,
                            stroke: design.glassStroke,
                            theme: design.theme,
                            sheen: sheen))
    }

    func glassChip(cornerRadius: CGFloat = 10, design: DesignSettings) -> some View {
        modifier(GlassChip(cornerRadius: cornerRadius,
                           opacity: design.glassOpacity,
                           stroke: design.glassStroke,
                           theme: design.theme))
    }
}
