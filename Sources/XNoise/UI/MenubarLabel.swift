import SwiftUI

struct MenubarLabel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings

    var body: some View {
        HStack(spacing: 4) {
            if model.mixer.isPlaying {
                EqBars(color: design.accent)
                if model.focusSettings.menubarTimer && model.session.isRunning {
                    Text(timerString)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                } else {
                    Text(mixLabel)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "waveform")
            }
        }
    }

    private var timerString: String {
        let r = model.session.remainingSec
        return String(format: "%d:%02d", r / 60, r % 60)
    }

    private var mixLabel: String {
        let n = model.mixer.live.count
        if n == 0 { return "x-noise" }
        if n == 1, let id = model.mixer.live.keys.first, let t = model.findTrack(id: id) {
            return t.name
        }
        return "\(n) sounds"
    }
}

/// Four animated bars imitating an EQ meter. Matches design.
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
