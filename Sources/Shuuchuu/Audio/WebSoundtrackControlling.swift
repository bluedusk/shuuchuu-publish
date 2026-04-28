import Foundation
import SwiftUI

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

    /// SwiftUI view that hosts the live player inline (e.g. the expand-row on the
    /// Soundtracks tab). The controller owns the underlying web view; the returned
    /// view handles reparenting + automatic reclaim back to the hidden window when
    /// removed from the hierarchy. UI consumers must not reach into the controller
    /// for the web view themselves — this is the only sanctioned embed surface.
    func playerView() -> AnyView

    /// Closure the controller calls when the JS bridge reports a title update.
    var onTitleChange: ((WebSoundtrack.ID, String) -> Void)? { get set }

    /// Closure the controller calls when the JS bridge detects the Spotify sign-in
    /// wall (no playback updates within 3s of `play()`).
    var onSignInRequired: ((WebSoundtrack.ID) -> Void)? { get set }

    /// Closure the controller calls when the YouTube IFrame player reports an error
    /// (100=video gone, 101/150/152=embed disabled). UI surfaces this inline.
    var onPlaybackError: ((WebSoundtrack.ID, Int) -> Void)? { get set }
}
