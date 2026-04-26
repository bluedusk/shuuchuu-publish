import SwiftUI

struct FocusPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var session: FocusSession
    @EnvironmentObject var state: MixState

    @State private var settingsHover = false
    @State private var ringHover = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ringBlock
            Hairline().padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 10)
            mixSection
            Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
    }

    // MARK: - Header (Focus / dots / ghost gear)

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                // Spec §06 section: 12pt SF Pro Text semibold uppercase + 0.06em.
                Text("FOCUS")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.72)
                    .xnText(.secondary)
                SessionDots(total: session.totalSessions, current: session.currentSession)
                    .padding(.top, 8)
            }
            Spacer()
            Button(action: { model.goTo(.settings) }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(settingsHover ? Color.primary : Color.primary.opacity(0.45))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .onHover { settingsHover = $0 }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - Hero ring (click to play/pause; reset & next reveal on hover)

    private var ringBlock: some View {
        ZStack {
            // Glow halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [design.accent.opacity(0.15), .clear],
                        center: .center, startRadius: 10, endRadius: 100
                    )
                )
                .frame(width: 210, height: 210)
                .blur(radius: 14)

            // Reset (left) — hover reveal
            HStack {
                ringSideButton(systemName: "arrow.counterclockwise") { session.reset() }
                    .opacity(ringHover ? 1 : 0)
                    .padding(.leading, 26)
                Spacer()
                ringSideButton(systemName: "forward.end.fill") { session.skip() }
                    .opacity(ringHover ? 1 : 0)
                    .padding(.trailing, 26)
            }
            .frame(width: 340)

            // Ring as button
            Button(action: ringTap) {
                PomodoroRing(
                    progress: session.progress,
                    size: 172,
                    stroke: 3,
                    accent: design.accent,
                    label: timeString,
                    caption: ringHover ? hoverCaption : phaseCaption
                )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 220)
        .padding(.top, 18)
        .padding(.bottom, 4)
        .onHover { ringHover = $0 }
        .animation(.easeOut(duration: 0.18), value: ringHover)
    }

    private func ringSideButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.45))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private func ringTap() {
        session.toggle()
        // Mirror to audio: starting the timer plays everything; pausing pauses everything.
        state.setAllPaused(!session.isRunning)
        model.mixer.reconcileNow()
    }

    private var timeString: String {
        let r = session.remainingSec
        return String(format: "%02d:%02d", r / 60, r % 60)
    }

    private var phaseCaption: String {
        switch session.phase {
        case .focus:      return session.isRunning ? "Focusing" : "Paused"
        case .shortBreak: return "Short break"
        case .longBreak:  return "Long break"
        }
    }

    private var hoverCaption: String {
        session.isRunning ? "Pause" : "Play"
    }

    // MARK: - Mix section

    private var mixSection: some View {
        VStack(spacing: 8) {
            HStack {
                playAllButton
                Spacer()
                clearAllButton
                addSoundButton
            }
            .padding(.horizontal, 16)

            mixList
                .padding(.horizontal, 16)
        }
    }

    private var playAllButton: some View {
        let anyPlaying = state.anyPlaying
        return IconButton(systemName: anyPlaying ? "pause.fill" : "play.fill") {
            model.togglePlayAll()
        }
        .disabled(state.isEmpty)
        .opacity(state.isEmpty ? 0.4 : 1)
        .help(anyPlaying ? "Pause all" : "Play all")
    }

    private var clearAllButton: some View {
        IconButton(systemName: "trash") { model.clearMix() }
            .disabled(state.isEmpty)
            .opacity(state.isEmpty ? 0.4 : 1)
            .help("Clear all sounds")
    }

    private var addSoundButton: some View {
        IconButton(systemName: "plus") { model.goTo(.sounds) }
            .help("Select sounds")
    }

    private var mixList: some View {
        ScrollView {
            VStack(spacing: 5) {
                if state.isEmpty {
                    emptyPlaceholder
                } else {
                    ForEach(state.tracks) { mixTrack in
                        if let track = model.findTrack(id: mixTrack.id) {
                            MixChipRow(
                                track: track,
                                volume: mixTrack.volume,
                                paused: mixTrack.paused,
                                onVolumeChange: { v in model.setTrackVolume(mixTrack.id, v) },
                                onTogglePause: { model.togglePause(trackId: mixTrack.id) },
                                onRemove: { model.removeTrack(mixTrack.id) }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 180)
        .scrollIndicators(.never)
    }

    private var emptyPlaceholder: some View {
        Text("No sounds playing — tap Select below")
            .font(.system(size: 11))
            .xnText(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.15),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
    }
}
