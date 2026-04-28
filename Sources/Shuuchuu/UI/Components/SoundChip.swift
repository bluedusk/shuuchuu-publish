import SwiftUI

/// Horizontal chip in the Sounds page grid: `[icon] [name] [★]`.
/// Tap toggles the track. Star toggles favorite. When active, multiple ways to
/// adjust per-track volume:
///   - Horizontal drag on the chip body (sets absolute volume from x-position)
///   - Mouse wheel / trackpad two-finger scroll (delta-based)
///   - Up/Down arrow keys while hovered (delta-based, ±0.05)
struct SoundChip: View {
    let track: Track
    let isOn: Bool
    let volume: Float
    let isFavorite: Bool
    let onTap: () -> Void
    let onVolumeChange: (Float) -> Void
    /// Adjust volume by a delta (positive = louder). Parent reads the latest value
    /// from the model, applies the delta, and clamps to [0, 1]. Lets event handlers
    /// (scroll, arrow keys) stay decoupled from this view's stale `volume` capture.
    let onAdjustVolume: (Float) -> Void
    let onToggleFav: () -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var dragActive = false
    @State private var hovered = false
    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?

    private var icon: TrackIcon { TrackIconMap.icon(for: track.id) }

    var body: some View {
        GeometryReader { geo in
            chipBody
                .contentShape(Rectangle())
                // highPriorityGesture wins against the enclosing vertical ScrollView's
                // pan recognizer; without it, horizontal drag was being absorbed.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            guard isOn, geo.size.width > 0 else { return }
                            dragActive = true
                            let raw = Float(value.location.x / geo.size.width)
                            onVolumeChange(max(0, min(1, raw)))
                        }
                        .onEnded { _ in dragActive = false }
                )
                .onTapGesture { onTap() }
                .onHover { hovered = $0 }
                .onChange(of: hovered) { _, _ in syncMonitors() }
                .onChange(of: isOn) { _, _ in syncMonitors() }
                .onDisappear { removeMonitors() }
        }
        // GeometryReader is greedy — pin to the chip's natural height (icon + paddings).
        .frame(height: 44)
    }

    /// Install/remove the global event monitors based on hover + active state.
    /// Only the hovered + active chip has live monitors, so events route to the
    /// right target without ambiguity. ↑/↓ arrows and scroll deltas are consumed;
    /// everything else is forwarded to the responder chain unchanged.
    private func syncMonitors() {
        if hovered && isOn {
            installMonitors()
        } else {
            removeMonitors()
        }
    }

    private func installMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 126: onAdjustVolume(0.05);  return nil  // up
                case 125: onAdjustVolume(-0.05); return nil  // down
                default:  return event
                }
            }
        }
        if scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                let dy: CGFloat = event.hasPreciseScrollingDeltas
                    ? event.scrollingDeltaY
                    : event.deltaY * 8
                onAdjustVolume(Float(dy) * 0.003)
                return nil  // consume so the popover scroll view doesn't also scroll
            }
        }
    }

    private func removeMonitors() {
        if let m = keyMonitor    { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
    }

    private var chipBody: some View {
        HStack(spacing: 10) {
            Image(systemName: icon.symbol)
                .font(.system(size: 16, weight: .light))
                .frame(width: 20, height: 20)
                .foregroundStyle(isOn ? Color.white : .primary.opacity(0.75))

            Text(track.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isOn ? Color.white : .primary.opacity(0.85))

            star
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: isOn ? design.accent.opacity(0.45) : .clear, radius: 6, y: 3)
    }

    private var star: some View {
        Button(action: onToggleFav) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(starColor)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var starColor: Color {
        if isFavorite { return Color(red: 1.0, green: 0.83, blue: 0.42) }
        return isOn ? Color.white.opacity(0.6) : .secondary.opacity(0.65)
    }

    @ViewBuilder
    private var background: some View {
        if isOn {
            // The chip background IS the volume indicator: bright accent fills
            // left-to-right to the current volume; the dim accent shows the
            // remaining headroom. No separate bar UI required.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: [design.accent.opacity(0.30), design.accentDark.opacity(0.30)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    LinearGradient(
                        colors: [design.accent, design.accentDark],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: geo.size.width * Double(volume))
                }
            }
        } else {
            Color.white.opacity(0.04)
                .background(.ultraThinMaterial)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                Color.white.opacity(isOn ? 0.40 : 0.15),
                lineWidth: 1
            )
    }
}

