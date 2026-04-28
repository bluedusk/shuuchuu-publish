import SwiftUI

/// View modifier that applies one of the three spec-defined text opacity stops
/// (0.92 / 0.62 / 0.40), picking the right ink (white in dark, near-black in light)
/// from the resolved theme on `DesignSettings`.
struct XNTextStyle: ViewModifier {
    let stop: XNTokens.TextStop
    @EnvironmentObject var design: DesignSettings

    func body(content: Content) -> some View {
        content.foregroundStyle(XNTokens.text(stop, theme: design.resolvedTheme))
    }
}

extension View {
    /// Use the spec's primary (0.92), secondary (0.62), or tertiary (0.40) text color
    /// in a way that flips the ink correctly when the user switches between dark/light.
    func xnText(_ stop: XNTokens.TextStop) -> some View {
        modifier(XNTextStyle(stop: stop))
    }
}
