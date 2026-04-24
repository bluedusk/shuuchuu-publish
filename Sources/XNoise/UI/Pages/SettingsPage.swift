import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @ObservedObject var settings: FocusSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Session") {
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

                    section("Sound") {
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

                    section("Notifications") {
                        SettingRow(label: "Session end chime") {
                            GlassToggle(isOn: Binding(get: { settings.chime }, set: { settings.chime = $0 }), accent: design.accent)
                        }
                        SettingRow(label: "Break reminders") {
                            GlassToggle(isOn: Binding(get: { settings.breakReminder }, set: { settings.breakReminder = $0 }), accent: design.accent)
                        }
                    }

                    section("App") {
                        SettingRow(label: "Launch at login") {
                            GlassToggle(isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }), accent: design.accent)
                        }
                        SettingRow(label: "Show timer in menubar") {
                            GlassToggle(isOn: Binding(get: { settings.menubarTimer }, set: { settings.menubarTimer = $0 }), accent: design.accent)
                        }
                        SettingRow(label: "Keyboard shortcut") {
                            Text("⌥⌘ N")
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .glassChip(cornerRadius: 5, design: design)
                        }
                    }

                    Text("x-noise · v1.0 · Quit ⌘Q")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left") { model.goTo(.focus) }
            Text("Settings").font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .medium))
            .kerning(1.2)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            .padding(.bottom, 4)
        content()
    }
}

// MARK: - Settings row + segmented control + glass toggle

struct SettingRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack {
            Text(label).font(.system(size: 11.5))
            Spacer()
            value()
        }
        .padding(.vertical, 10)
        .overlay(Divider().opacity(0.15), alignment: .bottom)
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
                Button(label(opt)) { selection = opt }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selection == opt ? Color.primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(selection == opt ? 0.18 : 0))
                    )
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
        Button(action: { isOn.toggle() }) {
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
