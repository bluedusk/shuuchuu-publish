import SwiftUI
import AppKit

struct FocusPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var session: FocusSession
    @EnvironmentObject var state: MixState
    @EnvironmentObject var settings: FocusSettings
    @EnvironmentObject var license: LicenseController

    @State private var settingsHover = false
    @State private var sceneChipHover = false
    @State private var scenePickerPresented = false
    @State private var ringHover = false
    @State private var playHover = false
    @State private var clearHover = false
    @State private var addHover = false

    @State private var trialPillDismissed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if settings.pomodoroEnabled {
                ringBlock
                Hairline().padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 10)
            }
            bottomRegion
            Spacer(minLength: 0)
            modeSwitchLink
            if shouldShowTrialPill { trialPill.padding(.bottom, 8) }
        }
        .padding(.bottom, 6)
    }

    /// Anchors the "Switch to …" link to the bottom of the popover so its Y
    /// position is constant across `.mix` and `.soundtrack` regardless of how
    /// tall the active region is.
    @ViewBuilder
    private var modeSwitchLink: some View {
        switch model.mode {
        case .mix where canSwitchToSoundtrack:
            switchLink("Switch to soundtrack") { model.switchToSoundtrack() }
                .padding(.bottom, 6)
        case .soundtrack where canSwitchToMix:
            switchLink("Switch to mix") { model.switchToMix() }
                .padding(.bottom, 6)
        default:
            EmptyView()
        }
    }

    /// Show the "Trial ends tomorrow · Buy" pill on day 4-5 of the trial.
    private var shouldShowTrialPill: Bool {
        guard !trialPillDismissed else { return false }
        guard case .trial = license.state else { return false }
        let days = license.trialDaysRemaining
        return days <= 2 && days > 0
    }

    private var trialPill: some View {
        let days = license.trialDaysRemaining
        let label = days <= 1 ? "Trial ends today" : "Trial ends tomorrow"
        return HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            Button { NSWorkspace.shared.open(Constants.License.storeURL) } label: {
                Text("Buy")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(design.accent)
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.snappy(duration: 0.2)) { trialPillDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.black.opacity(0.30))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Header (Focus / dots / ghost gear)

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            if settings.pomodoroEnabled {
                VStack(alignment: .leading, spacing: 0) {
                    // Spec §06 section: 12pt SF Pro Text semibold uppercase + 0.06em.
                    Text("FOCUS")
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(0.72)
                        .shText(.secondary)
                    SessionDots(total: session.totalSessions, current: session.currentSession)
                        .padding(.top, 8)
                }
            }
            Spacer()
            sceneChip                                // NEW
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

    // MARK: - Scene chip

    private var sceneChip: some View {
        Button { scenePickerPresented = true } label: {
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(sceneChipHover ? Color.primary : Color.primary.opacity(0.45))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sceneChipHover = $0 }
        .help("Scene")
        .popover(isPresented: $scenePickerPresented, arrowEdge: .top) {
            if let renderer = model.shaderRenderer {
                ScenePicker(
                    scenes: model.scenes.scenes,
                    activeId: model.scene.activeSceneId,
                    renderer: renderer,
                    onSelect: { id in
                        model.scene.setScene(id)
                        scenePickerPresented = false
                    }
                )
            }
        }
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
        model.pauseActiveSource(!session.isRunning)
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

    private var canSwitchToSoundtrack: Bool {
        guard model.mode == .mix, let id = model.lastSoundtrackId else { return false }
        return model.soundtracksLibrary.entry(id: id) != nil
    }

    private var canSwitchToMix: Bool { !state.isEmpty }

    /// Shared style for the symmetric "Switch to …" links so both modes render
    /// the link in the same structural slot at the bottom of `bottomRegion`.
    private func switchLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var bottomRegion: some View {
        switch model.mode {
        case .soundtrack(let id):
            if let entry = model.soundtracksLibrary.entry(id: id) {
                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        addSoundButton
                    }
                    .padding(.horizontal, 16)

                    SoundtrackPanel(
                        soundtrack: entry,
                        paused: model.activeSourcePaused,
                        errorCode: model.soundtrackError?.id == id ? model.soundtrackError?.code : nil,
                        onTogglePause: { model.togglePlayAll() },
                        onVolumeChange: { v in model.setSoundtrackVolume(id: id, volume: v) }
                    )
                    .padding(.horizontal, 16)
                }
            }
        case .mix, .idle:
            mixSection
        }
    }

    private var playAllButton: some View {
        let anyPlaying = !model.activeSourcePaused
        return minimalIcon(
            systemName: anyPlaying ? "pause.fill" : "play.fill",
            size: 13,
            hover: $playHover,
            disabled: model.mode == .idle && state.isEmpty
        ) { model.togglePlayAll() }
        .help(anyPlaying ? "Pause" : "Play")
    }

    private var clearAllButton: some View {
        minimalIcon(systemName: "trash",
                    size: 12,
                    hover: $clearHover,
                    disabled: state.isEmpty) { model.clearMix() }
            .help("Clear all sounds")
    }

    private var addSoundButton: some View {
        minimalIcon(systemName: "plus",
                    size: 14,
                    hover: $addHover,
                    disabled: false) { model.goTo(.sounds) }
            .help("Select sounds")
    }

    /// Plain glyph button — no background, no border. Defaults to ~45% opacity
    /// (same as the settings gear) and brightens to full primary on hover.
    private func minimalIcon(systemName: String,
                             size: CGFloat,
                             hover: Binding<Bool>,
                             disabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(
                    disabled ? Color.primary.opacity(0.20)
                             : (hover.wrappedValue ? Color.primary : Color.primary.opacity(0.45))
                )
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hover.wrappedValue = $0 }
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
            .shText(.tertiary)
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
