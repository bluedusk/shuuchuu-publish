import SwiftUI

/// A customizable glass-panel modifier, parameterized by the tweakable blur/opacity/stroke.
struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    let stroke: Double
    let theme: AppTheme
    var sheen: Bool = true

    func body(content: Content) -> some View {
        content
            .background(backgroundLayers)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(stroke), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var backgroundLayers: some View {
        ZStack {
            if theme == .dark {
                Rectangle().fill(.ultraThinMaterial)
            } else {
                Rectangle().fill(.thinMaterial)
            }
            Rectangle().fill(Color.white.opacity(opacity))
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
}

struct GlassChip: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    let stroke: Double
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Rectangle().fill(.thinMaterial)
                    Rectangle().fill(Color.white.opacity(opacity + 0.02))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(stroke + 0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
