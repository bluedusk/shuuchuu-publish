import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @State private var showTweaks: Bool = false

    private let size = CGSize(width: 340, height: 540)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Wallpaper(mode: design.wallpaper)
                .frame(width: size.width, height: size.height)

            GeometryReader { _ in
                HStack(spacing: 0) {
                    FocusPage()
                        .frame(width: size.width, height: size.height)
                    SoundsPage()
                        .frame(width: size.width, height: size.height)
                    SettingsPage()
                        .frame(width: size.width, height: size.height)
                }
                .offset(x: -CGFloat(pageIndex) * size.width)
                .animation(.smooth(duration: 0.32), value: model.page)
            }
            .frame(width: size.width, height: size.height)

            tweakToggle

            if showTweaks {
                TweaksPanel(isPresented: $showTweaks)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .padding(.top, 40)
                    .padding(.trailing, 10)
                    .zIndex(10)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(design.glassStroke + 0.1), lineWidth: 1)
        )
        .preferredColorScheme(design.theme.colorScheme)
        .environmentObject(model.session)
        .environmentObject(model.mixer)
        .environmentObject(model.focusSettings)
        .environmentObject(model.favorites)
        .task {
            if model.categories.isEmpty {
                await model.handleLaunch()
            }
        }
    }

    private var tweakToggle: some View {
        Button {
            withAnimation(.smooth(duration: 0.24)) { showTweaks.toggle() }
        } label: {
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .padding(.trailing, 50)
    }

    private var pageIndex: Int {
        switch model.page {
        case .focus:    return 0
        case .sounds:   return 1
        case .settings: return 2
        }
    }
}
