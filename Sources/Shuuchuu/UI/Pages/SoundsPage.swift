import SwiftUI

/// Container for the Sounds page. Hosts two child views (SoundsBrowseView, MixesView)
/// behind a tab bar. The page header is replaced by SaveMixHeader during save mode.
struct SoundsPage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings

    var body: some View {
        VStack(spacing: 0) {
            if model.saveMode.isActive {
                SaveMixHeader()
            } else {
                pageHeader
            }
            tabBar
            switch model.soundsTab {
            case .sounds:       SoundsBrowseView()
            case .mixes:        MixesView()
            case .soundtracks:  SoundtracksTab()
            }
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left") { model.goTo(.focus) }
            VStack(alignment: .leading, spacing: 1) {
                Text("SOUNDS")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.72)
                    .shText(.secondary)
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .shText(.primary)
            }
            Spacer()
            saveButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    private var saveButton: some View {
        Button { model.beginSaveMix() } label: {
            Text("Save mix")
                .font(.system(size: 11, weight: .medium))
                .shText(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(model.state.isEmpty || model.mode.isSoundtrack)
        .opacity(model.state.isEmpty || model.mode.isSoundtrack ? 0.4 : 1)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabItem(.sounds, label: "Sounds")
            tabItem(.mixes, label: "Mixes")
            tabItem(.soundtracks, label: "Soundtracks")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    private var headerSubtitle: String {
        switch model.mode {
        case .soundtrack:       return "playing soundtrack"
        case .mix, .idle:       return "\(model.state.count) in current mix"
        }
    }

    private func tabItem(_ tab: SoundsTab, label: String) -> some View {
        let isOn = model.soundsTab == tab
        return Button {
            // Switching tabs cancels an in-flight save (per spec §5.4).
            if model.saveMode.isActive { model.cancelSaveMix() }
            withAnimation(.easeOut(duration: 0.18)) { model.soundsTab = tab }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.bottom, 2)
                .overlay(
                    Rectangle()
                        .fill(isOn ? design.accent : Color.clear)
                        .frame(height: 1.5)
                        .padding(.top, 28),
                    alignment: .top
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
