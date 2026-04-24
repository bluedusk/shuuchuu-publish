import SwiftUI

struct FocusPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @ObservedObject var session: FocusSession
    @ObservedObject var mixer: MixingController

    var body: some View {
        VStack(spacing: 0) {
            header

            ring
                .padding(.top, 18)
                .padding(.bottom, 14)

            transport
                .padding(.bottom, 14)

            mixList
                .padding(.horizontal, 14)

            Spacer(minLength: 0)

            addSoundButton
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, 10)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("FOCUS SESSION")
                    .font(.system(size: 10, weight: .medium))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
                Text("Session \(session.currentSession) of \(session.totalSessions)")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            IconButton(systemName: "gearshape") { model.goTo(.settings) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - Ring

    private var ring: some View {
        let total = session.totalSec
        let remain = session.remainingSec
        let mm = String(format: "%02d", remain / 60)
        let ss = String(format: "%02d", remain % 60)
        let caption: String = {
            switch session.phase {
            case .focus:      return session.isRunning ? "focusing" : "paused"
            case .shortBreak: return "short break"
            case .longBreak:  return "long break"
            }
        }()
        return PomodoroRing(
            progress: session.progress,
            size: 172,
            stroke: 4,
            accent: design.accent,
            label: "\(mm):\(ss)",
            caption: caption
        )
        .id(total)  // force re-render on phase change
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 14) {
            IconButton(systemName: "arrow.counterclockwise", size: 32) { session.reset() }

            Button(action: { session.toggle() }) {
                Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [design.accent, design.accentDark],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    )
                    .shadow(color: design.accent.opacity(0.6), radius: 10, y: 4)
            }
            .buttonStyle(.plain)

            IconButton(systemName: "forward.end.fill", size: 32) { session.skip() }
        }
    }

    // MARK: - Mix list

    private var mixList: some View {
        VStack(alignment: .leading, spacing: 8) {
            let activeCount = mixer.live.count
            Text("NOW PLAYING · \(activeCount) \(activeCount == 1 ? "sound" : "sounds")")
                .font(.system(size: 10, weight: .medium))
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            ScrollView {
                VStack(spacing: 6) {
                    if activeCount == 0 {
                        Text("No sounds selected")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        Color.white.opacity(0.15),
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                    )
                            )
                    } else {
                        ForEach(Array(mixer.live.values), id: \.id) { live in
                            if let track = model.findTrack(id: live.id) {
                                MixChipRow(
                                    track: track,
                                    volume: live.volume,
                                    onVolumeChange: { v in model.setTrackVolume(live.id, v) },
                                    onRemove: { model.removeTrack(live.id) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }

    // MARK: - Add sound

    private var addSoundButton: some View {
        Button(action: { model.goTo(.sounds) }) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text(mixer.live.isEmpty ? "Choose sounds" : "Add sound")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .foregroundStyle(.primary)
            .glassChip(cornerRadius: 11, design: design)
        }
        .buttonStyle(.plain)
    }
}
