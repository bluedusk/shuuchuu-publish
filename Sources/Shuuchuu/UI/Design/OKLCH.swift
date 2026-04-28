import SwiftUI

/// SwiftUI `Color` constructor from OKLCH (perceptually uniform) coordinates.
///
/// L: Lightness 0…1, C: Chroma 0…~0.4, H: Hue in degrees 0…360.
///
/// The design spec uses oklch() throughout; this converts to sRGB so we can
/// hand a `Color` to SwiftUI. Conversion: OKLCH → OKLab → linear sRGB → sRGB.
extension Color {
    init(oklchL L: Double, C: Double, H: Double, opacity: Double = 1.0) {
        let (r, g, b) = oklchToSRGB(L: L, C: C, H: H)
        self = Color(.sRGB,
                     red: max(0, min(1, r)),
                     green: max(0, min(1, g)),
                     blue: max(0, min(1, b)),
                     opacity: opacity)
    }
}

/// Convert OKLCH → sRGB (0…1 components, linear-gamma applied).
/// Reference: https://bottosson.github.io/posts/oklab/
func oklchToSRGB(L: Double, C: Double, H: Double) -> (Double, Double, Double) {
    // OKLCH → OKLab
    let hRad = H * .pi / 180.0
    let a = C * cos(hRad)
    let b = C * sin(hRad)

    // OKLab → linear sRGB (Björn Ottosson, 2020)
    let l_ = L + 0.3963377774 * a + 0.2158037573 * b
    let m_ = L - 0.1055613458 * a - 0.0638541728 * b
    let s_ = L - 0.0894841775 * a - 1.2914855480 * b

    let l = l_ * l_ * l_
    let m = m_ * m_ * m_
    let s = s_ * s_ * s_

    let rLin =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    let gLin = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    let bLin = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    return (linearToSrgb(rLin), linearToSrgb(gLin), linearToSrgb(bLin))
}

private func linearToSrgb(_ x: Double) -> Double {
    if x >= 0.0031308 {
        return 1.055 * pow(max(0, x), 1.0 / 2.4) - 0.055
    } else {
        return 12.92 * x
    }
}
