import Foundation

/// What `AppModel` calls into to drive the active soundtrack. The concrete
/// implementation owns the hidden NSWindow + WKWebView + JS bridges.
///
/// Mocked in tests via `MockSoundtrackController` (test target).
@MainActor
protocol WebSoundtrackControlling: AnyObject {
    /// Activate this soundtrack. Replaces whatever was loaded, retains the WKWebView,
    /// loads the embed via the appropriate JS bridge, and (if `autoplay`) starts playback
    /// once the bridge reports ready.
    func load(_ soundtrack: WebSoundtrack, autoplay: Bool)

    /// Pause/play the currently-loaded soundtrack. No-op if nothing loaded.
    func setPaused(_ paused: Bool)

    /// Push a volume change to the loaded soundtrack. 0.0–1.0 app scale.
    func setVolume(_ volume: Double)

    /// Drop the loaded soundtrack — load `about:blank`. Used when removing the
    /// active library entry. The WKWebView itself is retained for future loads.
    func unload()

    /// Closure the controller calls when the JS bridge reports a title update.
    var onTitleChange: ((WebSoundtrack.ID, String) -> Void)? { get set }

    /// Closure the controller calls when the JS bridge detects the Spotify sign-in
    /// wall (no playback updates within 3s of `play()`).
    var onSignInRequired: ((WebSoundtrack.ID) -> Void)? { get set }
}
