import AppKit
import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var settings: FocusSettings
    @EnvironmentObject var updates: UpdateChecker

    @State private var betaTaps = 0
    @State private var betaTapStarted: Date?
    @State private var betaRevealed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    focusModeSection
                    if settings.pomodoroEnabled {
                        sessionSection
                        soundSection
                        notificationsSection
                    }
                    appSection
                    updatesSection
                    licenseSection
                    appearanceSection
                    // glassSection  // dead: blur slider is unwired; opacity/stroke
                                     // only affect the .glassChip modifier (used in
                                     // 1 place). Re-enable after wiring + redesign.
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left") { model.goTo(.focus) }
            // Spec §06 title: 22pt SF Pro Display medium.
            Text("Settings").font(.system(size: 22, weight: .medium)).kerning(-0.33)
            Spacer()
            if updates.hasUpdate, let version = updates.latestVersion {
                updateBanner(version: version)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    private func updateBanner(version: String) -> some View {
        Button { model.triggerUpdateCheck() } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(version) available")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(design.accent))
        }
        .buttonStyle(.plain)
    }

    private var focusModeSection: some View {
        Group {
            sectionLabel("Focus mode")
            SettingRow(label: "Pomodoro timer") {
                GlassToggle(
                    isOn: Binding(
                        get: { settings.pomodoroEnabled },
                        set: { settings.pomodoroEnabled = $0 }
                    ),
                    accent: design.accent
                )
            }
        }
    }

    private var sessionSection: some View {
        Group {
            sectionLabel("Session")
            SettingRow(label: "Focus duration") {
                SegControl(
                    selection: Binding(get: { settings.focusMin }, set: { settings.focusMin = $0 }),
                    options: [15, 25, 45, 60],
                    label: { "\($0)m" },
                    accent: design.accent
                )
            }
            SettingRow(label: "Short break") {
                SegControl(
                    selection: Binding(get: { settings.shortBreakMin }, set: { settings.shortBreakMin = $0 }),
                    options: [3, 5, 10],
                    label: { "\($0)m" },
                    accent: design.accent
                )
            }
            SettingRow(label: "Long break") {
                SegControl(
                    selection: Binding(get: { settings.longBreakMin }, set: { settings.longBreakMin = $0 }),
                    options: [15, 20, 30],
                    label: { "\($0)m" },
                    accent: design.accent
                )
            }
            SettingRow(label: "Sessions per cycle") {
                Stepper(
                    value: Binding(get: { settings.cycles }, set: { settings.cycles = max(1, min(8, $0)) }),
                    in: 1...8
                ) {
                    Text("\(settings.cycles)").monospacedDigit()
                        .font(.system(size: 12, weight: .semibold))
                }
                .labelsHidden()
            }
        }
    }

    private var soundSection: some View {
        Group {
            sectionLabel("Sound")
            SettingRow(label: "Fade in") {
                SegControl(
                    selection: Binding(get: { settings.fadeIn }, set: { settings.fadeIn = $0 }),
                    options: FadeIn.allCases,
                    label: { $0.display },
                    accent: design.accent
                )
            }
            SettingRow(label: "Fade out on session end") {
                GlassToggle(isOn: Binding(get: { settings.fadeOut }, set: { settings.fadeOut = $0 }), accent: design.accent)
            }
            SettingRow(label: "Auto-pause sound on break") {
                GlassToggle(isOn: Binding(get: { settings.pauseOnBreak }, set: { settings.pauseOnBreak = $0 }), accent: design.accent)
            }
        }
    }

    private var notificationsSection: some View {
        Group {
            sectionLabel("Notifications")
            SettingRow(label: "Session end chime") {
                GlassToggle(isOn: Binding(get: { settings.chime }, set: { settings.chime = $0 }), accent: design.accent)
            }
            SettingRow(label: "Break reminders") {
                GlassToggle(isOn: Binding(get: { settings.breakReminder }, set: { settings.breakReminder = $0 }), accent: design.accent)
            }
        }
    }

    private var appSection: some View {
        Group {
            sectionLabel("App")
            SettingRow(label: "Launch at login") {
                GlassToggle(isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }), accent: design.accent)
            }
            if settings.pomodoroEnabled {
                SettingRow(label: "Show timer in menubar") {
                    GlassToggle(isOn: Binding(get: { settings.menubarTimer }, set: { settings.menubarTimer = $0 }), accent: design.accent)
                }
            }
            SettingRow(label: "Keyboard shortcut") {
                Text("⌥⌘ N")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .glassChip(cornerRadius: 5, design: design)
            }
        }
    }

    private var licenseSection: some View {
        Group {
            sectionLabel("License")
            LicenseSettingsBlock()
        }
    }

    private var updatesSection: some View {
        Group {
            sectionLabel("Updates")
            SettingRow(label: "Version") {
                Text(versionString)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { handleVersionTap() }
            }
            if let last = updates.lastCheckDate {
                SettingRow(label: "Last checked") {
                    Text(last.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            SettingRow(label: "Check for updates") {
                Button { model.triggerUpdateCheck() } label: {
                    Text("Check now")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(design.accent.opacity(updates.canCheckForUpdates ? 1.0 : 0.4)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!updates.canCheckForUpdates)
            }
            SettingRow(label: "Automatically check") {
                GlassToggle(
                    isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.automaticallyChecksForUpdates = $0 }
                    ),
                    accent: design.accent
                )
            }
            SettingRow(label: "Auto-install in background") {
                GlassToggle(
                    isOn: Binding(
                        get: { updates.automaticallyDownloadsUpdates },
                        set: { updates.automaticallyDownloadsUpdates = $0 }
                    ),
                    accent: design.accent
                )
            }
            SettingRow(label: "What's new") {
                Button {
                    NSWorkspace.shared.open(UpdateChecker.releasesURL)
                } label: {
                    Text("Release notes")
                        .font(.system(size: 11, weight: .regular))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(Color.white.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)))
                }
                .buttonStyle(.plain)
            }
            if betaRevealed {
                SettingRow(label: "Beta updates") {
                    GlassToggle(
                        isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "app.betaUpdates") },
                            set: { UserDefaults.standard.set($0, forKey: "app.betaUpdates") }
                        ),
                        accent: design.accent
                    )
                }
            }
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func handleVersionTap() {
        let now = Date()
        if let started = betaTapStarted, now.timeIntervalSince(started) > 3 {
            betaTaps = 0
        }
        betaTapStarted = now
        betaTaps += 1
        if betaTaps >= 5 {
            betaRevealed = true
        }
    }

    private var appearanceSection: some View {
        Group {
            sectionLabel("Appearance")

            stackedRow(
                title: "Accent hue",
                trailing: "\(Int(design.accentHue))°"
            ) {
                HueSlider(
                    hue: Binding(get: { design.accentHue }, set: { design.accentHue = $0 })
                )

                // Spec §03 — six named presets.
                HStack(spacing: 6) {
                    ForEach(SHTokens.accentPresets, id: \.name) { preset in
                        Button { design.accentHue = preset.hue } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(SHTokens.accent(hue: preset.hue))
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle().strokeBorder(
                                            Color.white.opacity(
                                                Int(design.accentHue) == Int(preset.hue) ? 0.85 : 0.15
                                            ),
                                            lineWidth: 1.5
                                        )
                                    )
                                Text(preset.name)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }

            stackedRow(title: "Wallpaper") {
                radioRow(
                    options: WallpaperMode.allCases,
                    rows: 2,
                    label: { $0.display.capitalized },
                    selection: Binding(get: { design.wallpaper }, set: { design.wallpaper = $0 })
                )
            }

        }
    }

    // Glass tuning panel — kept around for when the chip/panel styling needs
    // user knobs again. Currently inert: glassBlur isn't wired to anything,
    // and glassOpacity/glassStroke only affect the .glassChip modifier.
    /*
    private var glassSection: some View {
        Group {
            sectionLabel("Glass")

            stackedRow(
                title: "Blur",
                trailing: "\(Int(design.glassBlur))px"
            ) {
                Slider(
                    value: Binding(get: { design.glassBlur }, set: { design.glassBlur = $0 }),
                    in: 4...60, step: 1
                )
                .tint(design.accent)
            }

            stackedRow(
                title: "Opacity",
                trailing: String(format: "%.2f", design.glassOpacity)
            ) {
                Slider(
                    value: Binding(get: { design.glassOpacity }, set: { design.glassOpacity = $0 }),
                    in: 0.04...0.5, step: 0.01
                )
                .tint(design.accent)
            }

            stackedRow(
                title: "Stroke",
                trailing: String(format: "%.2f", design.glassStroke)
            ) {
                Slider(
                    value: Binding(get: { design.glassStroke }, set: { design.glassStroke = $0 }),
                    in: 0...0.6, step: 0.01
                )
                .tint(design.accent)
            }
        }
    }
    */

    @ViewBuilder
    private func stackedRow<Body: View>(
        title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Body
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .regular))   // body
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(.vertical, 8)
    }

    private func radioChunks<Opt>(_ options: [Opt], rows: Int) -> [[Opt]] {
        let perRow = max(Int((Double(options.count) / Double(rows)).rounded(.up)), 1)
        return stride(from: 0, to: options.count, by: perRow).map {
            Array(options[$0..<min($0 + perRow, options.count)])
        }
    }

    @ViewBuilder
    private func radioRow<Opt: Hashable>(
        options: [Opt],
        rows: Int = 1,
        label: @escaping (Opt) -> String,
        selection: Binding<Opt>
    ) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(radioChunks(options, rows: rows).enumerated()), id: \.offset) { _, chunk in
                HStack(spacing: 4) {
                    ForEach(chunk, id: \.self) { opt in
                        let isOn = selection.wrappedValue == opt
                        Button { selection.wrappedValue = opt } label: {
                            Text(label(opt))
                                .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(isOn ? Color.primary : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.white.opacity(isOn ? 0.18 : 0))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    private var footer: some View {
        Text("ShuuChuu 集中 · v1.0 · Quit ⌘Q")
            .font(.system(size: 11, weight: .regular))
            .shText(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 12)
    }

    private func sectionLabel(_ title: String) -> some View {
        // Spec §06 section: 12pt SF Pro Text semibold uppercase + 0.06em.
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .kerning(0.72)
            .shText(.secondary)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

// MARK: - Settings row + segmented control + glass toggle

struct SettingRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .regular))
            Spacer()
            value()
        }
        .padding(.vertical, 10)
    }
}

struct SegControl<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String
    let accent: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { opt in
                Button { selection = opt } label: {
                    Text(label(opt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selection == opt ? Color.primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(selection == opt ? 0.18 : 0))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }
}

struct GlassToggle: View {
    @Binding var isOn: Bool
    let accent: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(accent) : AnyShapeStyle(Color.white.opacity(0.18)))
                    .frame(width: 32, height: 18)
                    .shadow(color: isOn ? accent.opacity(0.6) : .clear, radius: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .padding(2)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
            .animation(.snappy(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
    }
}
