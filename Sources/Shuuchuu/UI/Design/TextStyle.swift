import SwiftUI

/// View modifier that applies one of the three spec-defined text opacity stops
/// (0.92 / 0.62 / 0.40). White ink only — the app is dark-mode only.
struct SHTextStyle: ViewModifier {
    let stop: SHTokens.TextStop

    func body(content: Content) -> some View {
        content.foregroundStyle(SHTokens.text(stop))
    }
}

extension View {
    /// Use the spec's primary (0.92), secondary (0.62), or tertiary (0.40) text color.
    func shText(_ stop: SHTokens.TextStop) -> some View {
        modifier(SHTextStyle(stop: stop))
    }
}
