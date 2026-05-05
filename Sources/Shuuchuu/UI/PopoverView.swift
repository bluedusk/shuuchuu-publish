import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var license: LicenseController

    private let size = CGSize(width: 340, height: 540)

    var body: some View {
        ZStack {
            // Wallpaper is the base. When no scene is picked SceneBackground's host
            // is empty and wallpaper shows through; when a scene is active the
            // shader's MTKView fully covers it.
            Wallpaper(mode: design.wallpaper)
                .frame(width: size.width, height: size.height)

            if let renderer = model.shaderRenderer {
                SceneBackground(renderer: renderer)
                    .frame(width: size.width, height: size.height)
            }

            SceneScrim()
                .frame(width: size.width, height: size.height)
                .opacity(model.scene.activeSceneId == nil ? 0 : 1)

            // While entitlement is locked, LockedView is the only surface — no Sounds/
            // Settings overlays, no Focus body. Activation succeeds → re-renders to FocusPage.
            if !license.isUnlocked {
                LockedView()
                    .frame(width: size.width, height: size.height)
            } else {
                // Focus is always the base layer.
                FocusPage()
                    .frame(width: size.width, height: size.height)

                // Sounds & Settings push in from the right when active.
                // Edge-slide transitions instead of a fixed HStack offset means we never
                // animate the "middle" page through the viewport when navigating
                // non-adjacent screens.
                if model.page == .sounds {
                    ZStack {
                        Wallpaper(mode: design.wallpaper)
                        SoundsPage()
                    }
                    .frame(width: size.width, height: size.height)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
                }

                if model.page == .settings {
                    ZStack {
                        Wallpaper(mode: design.wallpaper)
                        SettingsPage()
                    }
                    .frame(width: size.width, height: size.height)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // contentShape AFTER clipShape — otherwise the clipped rounded corners
        // strip the hit-test region and events leak to the window underneath.
        // This must be the *last* layout-affecting modifier before scene wiring.
        .contentShape(Rectangle())
        .onHover { _ in }            // forces a tracking area covering the full frame
        .focusEffectDisabled()       // suppress system blue focus rings on every button in the popover
        .preferredColorScheme(.dark)
        .environmentObject(model.state)
        .environmentObject(model.session)
        .environmentObject(model.mixer)
        .environmentObject(model.focusSettings)
        .environmentObject(model.favorites)
        .environmentObject(model.savedMixes)
        .environmentObject(model.soundtracksLibrary)
        .environmentObject(model.soundtracksFilter)
        .environmentObject(model.scenes)
        .environmentObject(model.scene)
    }
}
