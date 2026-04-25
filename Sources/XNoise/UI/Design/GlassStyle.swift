import SwiftUI

/// Spec §07 — five-layer glass recipe:
/// 1. Backdrop blur + saturate    (.thinMaterial / .ultraThinMaterial)
/// 2. Vertical tint gradient      (white α 0.21 → 0.13 → 0.09 in dark; 0.70 → 0.60 → 0.50 light)
/// 3. Inner highlight along top   (1px white α 0.45 — reads as the curved top edge)
/// 4. 1px white edge stroke       (α 0.16 dark / 0.90 light — outer perimeter)
/// 5. Specular sheen overlay      (radial gradient at top-left, mix-blend-mode overlay)
struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double      // tunable midpoint of the vertical tint gradient
    let stroke: Double
    let theme: AppTheme
    var sheen: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            // Layer 1 — backdrop blur (system material)
            .background(
                theme == .dark
                    ? AnyShapeStyle(.ultraThinMaterial)
                    : AnyShapeStyle(.thinMaterial),
                in: shape
            )
            // Layer 2 — vertical tint gradient (light at top, darker at bottom = "lit from above")
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(opacity + 0.08),
                        Color.white.opacity(opacity),
                        Color.white.opacity(max(0, opacity - 0.04)),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)
            )
            // Layer 3 — inner top-edge highlight (1px white α 0.45, fading over ~3pt)
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.45), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipShape(shape)
                .allowsHitTesting(false)
            )
            // Layer 4 — outer 1px edge stroke
            .overlay { shape.strokeBorder(Color.white.opacity(stroke), lineWidth: 1) }
            // Layer 5 — specular sheen at top-left, blended overlay
            .overlay {
                if sheen {
                    RadialGradient(
                        colors: [Color.white.opacity(0.40), .clear],
                        center: .init(x: 0.20, y: -0.10),
                        startRadius: 10,
                        endRadius: 240
                    )
                    .blendMode(.overlay)
                    .clipShape(shape)
                    .allowsHitTesting(false)
                }
            }
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
            .background(.thinMaterial, in: shape)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(opacity + 0.10),
                        Color.white.opacity(opacity + 0.02),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)
            )
            // Inner top highlight (smaller than panel — chips are short)
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.35), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipShape(shape)
                .allowsHitTesting(false)
            )
            .overlay { shape.strokeBorder(Color.white.opacity(stroke + 0.06), lineWidth: 1) }
            .clipShape(shape)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 18, design: DesignSettings, sheen: Bool = true) -> some View {
        // Spec §04 / §07: in light theme the white tint must lift to ~0.60 so glass stays
        // visible against a bright wallpaper.
        let resolved = design.resolvedTheme
        let opacity = resolved == .light
            ? max(design.glassOpacity, XNTokens.Glass.lightOpacity)
            : design.glassOpacity
        return modifier(GlassPanel(
            cornerRadius: cornerRadius,
            opacity: opacity,
            stroke: design.glassStroke,
            theme: resolved,
            sheen: sheen
        ))
    }

    func glassChip(cornerRadius: CGFloat = 10, design: DesignSettings) -> some View {
        let resolved = design.resolvedTheme
        let opacity = resolved == .light
            ? max(design.glassOpacity, XNTokens.Glass.lightOpacity)
            : design.glassOpacity
        return modifier(GlassChip(
            cornerRadius: cornerRadius,
            opacity: opacity,
            stroke: design.glassStroke,
            theme: resolved
        ))
    }
}
