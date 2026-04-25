import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings

    private let size = CGSize(width: 340, height: 540)

    var body: some View {
        ZStack {
            Wallpaper(mode: design.wallpaper)
                .frame(width: size.width, height: size.height)

            // Focus is always the base layer.
            FocusPage()
                .frame(width: size.width, height: size.height)

            // Sounds & Settings push in from the right when active.
            // Edge-slide transitions instead of a fixed HStack offset means we never
            // animate the "middle" page through the viewport when navigating
            // non-adjacent screens.
            if model.page == .sounds {
                SoundsPage()
                    .frame(width: size.width, height: size.height)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }

            if model.page == .settings {
                SettingsPage()
                    .frame(width: size.width, height: size.height)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
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
}
