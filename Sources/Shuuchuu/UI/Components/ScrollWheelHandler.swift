import SwiftUI
import AppKit

/// Transparent NSView that captures macOS scroll-wheel and trackpad scroll events
/// at its bounds and forwards a normalized vertical delta (positive = "increase").
/// Use as a `.background(...)` to add scroll-to-adjust to any SwiftUI view.
struct ScrollWheelHandler: NSViewRepresentable {
    let onDelta: (CGFloat) -> Void

    func makeNSView(context: Context) -> CapturingView {
        let v = CapturingView()
        v.onDelta = onDelta
        return v
    }

    func updateNSView(_ nsView: CapturingView, context: Context) {
        nsView.onDelta = onDelta
    }

    final class CapturingView: NSView {
        var onDelta: ((CGFloat) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            // Trackpad: smooth, fractional deltas.
            // Mouse wheel: integer ticks; amplify so a single tick is a meaningful step.
            let dy: CGFloat = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY
                : event.deltaY * 8
            onDelta?(dy)
        }
    }
}
