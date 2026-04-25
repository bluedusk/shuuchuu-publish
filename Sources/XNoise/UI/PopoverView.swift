import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings

    private let size = CGSize(width: 340, height: 540)

    var body: some View {
        ZStack {
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

    private var pageIndex: Int {
        switch model.page {
        case .focus:    return 0
        case .sounds:   return 1
        case .settings: return 2
        }
    }
}
