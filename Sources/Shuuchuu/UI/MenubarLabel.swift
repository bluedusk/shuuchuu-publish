import SwiftUI

/// Menubar label — shows 集中 (the logo) at all times.
/// While playing, an animated EQ bar + timer / mix name appears beside it.
struct MenubarLabel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var updates: UpdateChecker
    @EnvironmentObject var session: FocusSession
    @EnvironmentObject var focusSettings: FocusSettings
    @EnvironmentObject var license: LicenseController

    var body: some View {
        // Single Text whose contents are computed reactively. Avoids structural
        // changes to the MenuBarExtra label, which macOS can drop on remount.
        HStack(spacing: 4) {
            Text(labelString)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .opacity(session.isRunning ? 1.0 : 0.6)
            if !license.isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if updates.hasUpdate {
                Circle()
                    .fill(design.accent)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Update available")
            }
        }
    }

    private var labelString: String {
        let prefix = (session.phase == .focus) ? "集中" : "休憩"
        guard focusSettings.menubarTimer else { return prefix }
        return "\(prefix) \(timerString)"
    }

    private var timerString: String {
        // Show ceiling-of-minutes so the displayed value is the minute currently
        // ticking down (e.g. 24:30 reads as "25m", flips to "24m" once it crosses).
        let mins = (session.remainingSec + 59) / 60
        return "\(mins)m"
    }
}

/// Four animated bars imitating an EQ meter.
struct EqBars: View {
    let color: Color
    @State private var anim = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            bar(height: anim ? 0.9 : 0.2, delay: 0.0)
            bar(height: anim ? 0.3 : 0.6, delay: 0.08)
            bar(height: anim ? 1.0 : 0.4, delay: 0.15)
            bar(height: anim ? 0.4 : 0.8, delay: 0.22)
        }
        .frame(width: 10, height: 10)
        .foregroundStyle(color)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                anim.toggle()
            }
        }
    }

    private func bar(height: Double, delay: Double) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 2, height: max(2, 10 * height))
            .animation(
                .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: anim
            )
    }
}
