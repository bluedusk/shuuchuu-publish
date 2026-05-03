import AppKit
import WebKit
import Foundation
import SwiftUI

private final class BridgeMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: WebSoundtrackController?
    nonisolated func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        // WebKit invokes script-message handlers on the main thread. Hopping
        // through `Task { @MainActor }` introduces a scheduling step where two
        // messages can be reordered relative to a parallel `load(...)` — letting
        // a stale `titleChanged` from the previous soundtrack land after the new
        // one is already loaded. `assumeIsolated` runs the handler synchronously
        // in WebKit's dispatch order. (`message.body` itself is main-actor.)
        MainActor.assumeIsolated {
            guard let dict = message.body as? [String: Any] else { return }
            owner?.handleBridgeMessage(dict)
        }
    }
}

/// Hidden long-lived host for a single WKWebView. Survives popover dismissal so
/// audio continues across menubar close/reopen. Reuses one web view across
/// activations — cookie persistence (default data store) keeps the user's Spotify
/// login alive between launches.
@MainActor
final class WebSoundtrackController: NSObject, WebSoundtrackControlling {

    var onTitleChange: ((WebSoundtrack.ID, String) -> Void)?
    var onSignInRequired: ((WebSoundtrack.ID) -> Void)?
    var onPlaybackError: ((WebSoundtrack.ID, Int) -> Void)?

    private let window: NSWindow
    private let webView: WKWebView
    private var loadedSoundtrack: WebSoundtrack?
    private var bridgeReady: Bool = false
    /// Snapshot of `loadedSoundtrack?.id` taken when the bridge fires its
    /// "ready" event. Identity-bound messages (titleChanged / signInRequired /
    /// error) only fire if this still equals `loadedSoundtrack?.id` — otherwise
    /// a `load(B)` happened after `A` reported ready, and the message belongs
    /// to A's destroyed page. Cleared on every `load(...)`.
    private var bridgeReadyForId: WebSoundtrack.ID?
    private var pendingEmbedURL: String?
    private var pendingAutoplay: Bool = false
    /// Preserved across the embed → watch-page fallback so the retry honors the
    /// original caller's autoplay intent (vs. the transient `pendingAutoplay`
    /// flag, which gets cleared after the bridge `ready` handler dispatches).
    private var lastLoadAutoplay: Bool = false
    /// Tracks which YouTube soundtracks failed the embed path. We skip the embed
    /// for these and load the watch page directly. Persisted so we don't retry
    /// on every launch.
    private var watchPageFallbackIds: Set<UUID>
    /// Mode of the currently-loaded YouTube source. Drives play/pause/setVolume
    /// dispatch (embed bridge vs. injected `__shuuchuu` on the watch page).
    private enum YouTubeMode { case embed, watch }
    private var currentYouTubeMode: YouTubeMode = .embed
    private let defaults: UserDefaults
    private static let fallbackKey = "shuuchuu.soundtrack.watchPageFallback"
    /// Stable UUID for the dedicated WKWebsiteDataStore. Same id every launch so
    /// cookies (Spotify login) persist; isolated from other WebKit-using apps so a
    /// hypothetical RCE in YouTube/Spotify pages can't reach their cookies.
    private static let dataStoreIdentifier = UUID(uuidString: "5C1D4AE2-3E7D-4F7B-9C2A-D6E4F8B9A1C0")!

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = (defaults.array(forKey: Self.fallbackKey) as? [String]) ?? []
        self.watchPageFallbackIds = Set(saved.compactMap(UUID.init(uuidString:)))

        // Off-screen 1×1 window — invisible, retained for the app lifetime.
        window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.isExcludedFromWindowsMenu = true
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreIdentifier)
        config.mediaTypesRequiringUserActionForPlayback = []   // bridge plays without gesture

        let proxy = BridgeMessageProxy()
        config.userContentController.add(proxy, name: "shuuchuu")

        // Inject the YouTube control script before the watch page's own scripts run.
        // Loaded only when we navigate to youtube.com — Spotify path is untouched.
        if let scriptURL = Bundle.module.url(forResource: "youtube-control", withExtension: "js"),
           let scriptSource = try? String(contentsOf: scriptURL, encoding: .utf8) {
            let userScript = WKUserScript(source: scriptSource,
                                          injectionTime: .atDocumentEnd,
                                          forMainFrameOnly: true)
            config.userContentController.addUserScript(userScript)
        }

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        // Pretend to be desktop Safari so YouTube serves the regular watch player
        // rather than a stripped/restricted webview variant.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/618.1.15 (KHTML, like Gecko) Version/17.0 Safari/618.1.15"
        // Web Inspector exposes the loaded pages and our injected scripts — useful in
        // dev, but a debug surface in shipping builds, so debug-only.
        #if DEBUG
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        #endif

        super.init()

        webView.navigationDelegate = self
        proxy.owner = self

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        host.wantsLayer = true
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        window.contentView = host
        window.orderBack(nil)

        Task { @MainActor [webView] in
            await YouTubeCookieSync.sync(into: webView.configuration.websiteDataStore.httpCookieStore)
        }
    }

    // MARK: - WebSoundtrackControlling

    func load(_ soundtrack: WebSoundtrack, autoplay: Bool) {
        lastLoadAutoplay = autoplay
        switch soundtrack.kind {
        case .youtube: loadYouTubeBridge(soundtrack, autoplay: autoplay)
        case .spotify: loadSpotifyBridge(soundtrack, autoplay: autoplay)
        }
    }

    /// Try the lightweight iframe embed first. If we already know this soundtrack
    /// fails the embed (recorded in `watchPageFallbackIds`), skip straight to
    /// the watch-page path.
    private func loadYouTubeBridge(_ soundtrack: WebSoundtrack, autoplay: Bool) {
        if watchPageFallbackIds.contains(soundtrack.id) {
            loadYouTubeWatch(soundtrack, autoplay: autoplay)
            return
        }
        currentYouTubeMode = .embed
        loadedSoundtrack = soundtrack
        bridgeReady = false
        bridgeReadyForId = nil
        pendingEmbedURL = soundtrack.url
        pendingAutoplay = autoplay
        guard let url = Bundle.module.url(forResource: "youtube-bridge", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("youtube-bridge.html missing from bundle")
            return
        }
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com/")!)
    }

    /// Fallback: navigate the WKWebView directly to the watch page so we dodge
    /// embed restrictions (errors 101/150/152). Control via injected
    /// `youtube-control.js` — no IFrame API.
    private func loadYouTubeWatch(_ soundtrack: WebSoundtrack, autoplay: Bool) {
        guard let id = soundtrack.youtubeVideoId,
              let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else {
            return
        }
        currentYouTubeMode = .watch
        loadedSoundtrack = soundtrack
        bridgeReady = false
        bridgeReadyForId = nil
        pendingEmbedURL = nil
        pendingAutoplay = autoplay
        webView.load(URLRequest(url: url))
    }

    private func recordFallback(for id: UUID) {
        guard !watchPageFallbackIds.contains(id) else { return }
        watchPageFallbackIds.insert(id)
        defaults.set(watchPageFallbackIds.map { $0.uuidString }, forKey: Self.fallbackKey)
    }

    private func loadSpotifyBridge(_ soundtrack: WebSoundtrack, autoplay: Bool) {
        // Same Spotify already loaded → swap embed URL via the bridge.
        if loadedSoundtrack?.kind == .spotify, bridgeReady {
            loadedSoundtrack = soundtrack
            pendingEmbedURL = nil
            bridgeCall("window.bridge.load", args: [soundtrack.url])
            bridgeCall("window.bridge.setVolume", args: [soundtrack.volume])
            if autoplay { bridgeCall("window.bridge.play") }
            return
        }
        loadedSoundtrack = soundtrack
        bridgeReady = false
        bridgeReadyForId = nil
        pendingEmbedURL = soundtrack.url
        pendingAutoplay = autoplay
        guard let url = Bundle.module.url(forResource: "spotify-bridge", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("spotify-bridge.html missing from bundle")
            return
        }
        webView.loadHTMLString(html, baseURL: URL(string: "https://open.spotify.com/")!)
    }

    func setPaused(_ paused: Bool) {
        guard bridgeReady else { return }
        switch (loadedSoundtrack?.kind, currentYouTubeMode) {
        case (.youtube, .watch):
            bridgeCall(paused ? "window.__shuuchuu.pause" : "window.__shuuchuu.play")
        case (.youtube, .embed), (.spotify, _), (.none, _):
            bridgeCall(paused ? "window.bridge.pause" : "window.bridge.play")
        }
    }

    func setVolume(_ volume: Double) {
        guard bridgeReady else { return }
        switch (loadedSoundtrack?.kind, currentYouTubeMode) {
        case (.youtube, .watch):
            bridgeCall("window.__shuuchuu.setVolume", args: [volume])
        case (.youtube, .embed), (.spotify, _), (.none, _):
            bridgeCall("window.bridge.setVolume", args: [volume])
        }
    }

    func unload() {
        loadedSoundtrack = nil
        bridgeReady = false
        bridgeReadyForId = nil
        pendingEmbedURL = nil
        pendingAutoplay = false
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    // MARK: - Bridge message handling

    func handleBridgeMessage(_ dict: [String: Any]) {
        guard let type = dict["type"] as? String else { return }
        switch type {
        case "ready":
            bridgeReady = true
            bridgeReadyForId = loadedSoundtrack?.id
            switch (loadedSoundtrack?.kind, currentYouTubeMode) {
            case (.youtube, .watch):
                if let s = loadedSoundtrack {
                    bridgeCall("window.__shuuchuu.setVolume", args: [s.volume])
                    if pendingAutoplay {
                        bridgeCall("window.__shuuchuu.play")
                        pendingAutoplay = false
                    }
                }
            case (.youtube, .embed), (.spotify, _), (.none, _):
                if let url = pendingEmbedURL {
                    bridgeCall("window.bridge.load", args: [url])
                    pendingEmbedURL = nil
                }
                if let s = loadedSoundtrack {
                    bridgeCall("window.bridge.setVolume", args: [s.volume])
                    if pendingAutoplay {
                        bridgeCall("window.bridge.play")
                        pendingAutoplay = false
                    }
                }
            }
        case "titleChanged":
            guard isCurrentLoadMessage, let title = dict["title"] as? String,
                  let id = loadedSoundtrack?.id else { return }
            onTitleChange?(id, title)
        case "signInRequired":
            guard isCurrentLoadMessage, let id = loadedSoundtrack?.id else { return }
            onSignInRequired?(id)
        case "stateChange":
            // No app-level reaction in v1 beyond observability.
            break
        case "error":
            guard isCurrentLoadMessage, let c = dict["code"] as? Int else { return }
            handlePlaybackError(code: c)
        default:
            break
        }
    }

    /// True iff the most recent "ready" was for the soundtrack we still consider
    /// loaded — i.e. no `load(...)` has run since the bridge announced ready.
    /// Identity-bound events (titleChanged/signInRequired/error) consult this so
    /// a stale message from a previous page can't write under a new entry's id.
    private var isCurrentLoadMessage: Bool {
        bridgeReady && bridgeReadyForId == loadedSoundtrack?.id
    }

    /// Codes 101/150/152 are "embed disabled by publisher". Auto-fall back to the
    /// watch-page path and remember the soundtrack so future activations skip
    /// the embed retry. Other codes (100=video gone, 5=player error, 2=invalid
    /// param) are surfaced to the UI without retry.
    private func handlePlaybackError(code: Int) {
        guard let s = loadedSoundtrack else { return }
        let isEmbedRestriction = (code == 101 || code == 150 || code == 152)
        if isEmbedRestriction, s.kind == .youtube, currentYouTubeMode == .embed {
            recordFallback(for: s.id)
            loadYouTubeWatch(s, autoplay: lastLoadAutoplay)
            return
        }
        onPlaybackError?(s.id, code)
    }

    // MARK: - JS helpers

    /// Invoke `methodPath(args...)` in the web view. Args are JSON-encoded so any
    /// strings the user provided (e.g. soundtrack URLs from the library) cannot
    /// break out of their literal context and execute attacker-controlled JS in
    /// the YouTube/Spotify origin. `methodPath` itself is always a code constant.
    ///
    /// JSONSerialization is the trust boundary here — hand-rolled escape lists
    /// missed U+2028/U+2029/CR/U+0000 and produced a stored-URL → JS-injection seam.
    private func bridgeCall(_ methodPath: String, args: [Any] = []) {
        let payload: String
        if args.isEmpty {
            payload = "()"
        } else {
            guard let data = try? JSONSerialization.data(withJSONObject: args) else {
                assertionFailure("bridgeCall: failed to JSON-encode args for \(methodPath)")
                return
            }
            var json = String(data: data, encoding: .utf8) ?? "[]"
            // JSONSerialization leaves U+2028/U+2029 as raw bytes — they're valid
            // JSON but illegal inside a JS string literal (they're line terminators
            // in JS), so we'd produce a syntax error and effectively no-op.
            json = json
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            // Strip outer [ ] to use as the positional arg list of the call.
            let inner = json.dropFirst().dropLast()
            payload = "(\(inner))"
        }
        webView.evaluateJavaScript("\(methodPath)\(payload)", completionHandler: nil)
    }

    // MARK: - Inline embed support

    /// SwiftUI view that hosts the live web player in-place. Reparents the
    /// controller-owned `WKWebView` into the returned view; on disappear, the
    /// view re-parents the web view back into the hidden window so audio
    /// continues unbroken across expand → collapse.
    func playerView() -> AnyView {
        AnyView(SoundtrackPlayerEmbed(controller: self))
    }

    /// Reparent the web view back to the hidden window. Internal — only the
    /// `SoundtrackPlayerEmbed` view should call this; UI consumers go through
    /// `playerView()`.
    fileprivate func reclaimWebView() {
        guard webView.superview !== window.contentView else { return }
        webView.removeFromSuperview()
        guard let parent = window.contentView else { return }
        parent.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: parent.topAnchor),
            webView.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }

    fileprivate var hostedWebView: WKWebView { webView }
}

/// SwiftUI host for the controller-owned WKWebView. Lifts it out of the hidden
/// window into an inline container while present; reclaims on disappear so
/// playback continues across the expand/collapse boundary.
private struct SoundtrackPlayerEmbed: View {
    let controller: WebSoundtrackController

    var body: some View {
        SoundtrackPlayerEmbedRepresentable(controller: controller)
            .onDisappear { controller.reclaimWebView() }
    }
}

private struct SoundtrackPlayerEmbedRepresentable: NSViewRepresentable {
    let controller: WebSoundtrackController

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.wantsLayer = true
        host.layer?.cornerRadius = 8
        host.layer?.masksToBounds = true

        let web = controller.hostedWebView
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: host.topAnchor),
            web.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Navigation policy

extension WebSoundtrackController: WKNavigationDelegate {
    /// Block main-frame redirects to anything outside our trust circle. The
    /// motivation: `evaluateJavaScript` runs against the current document's origin,
    /// so if a compromised YouTube/Spotify page redirected us to attacker.example,
    /// our subsequent `bridgeCall("window.bridge.play")` would call into their
    /// `window.bridge.play` and we'd be exfiltrating to them. Sub-frame loads
    /// (ads, analytics, video CDNs) pass through — locking those down breaks the
    /// embeds, and they don't host our scripts.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame == true
        if isMainFrame {
            decisionHandler(Self.allowsMainFrame(url: navigationAction.request.url) ? .allow : .cancel)
            return
        }
        // No targetFrame → new-window / pop-up request. Cancel; we don't surface those.
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    static func allowsMainFrame(url: URL?) -> Bool {
        guard let url = url else { return true }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" || scheme == "data" { return true }
        if scheme != "https" { return false }
        guard let host = url.host?.lowercased() else { return false }
        return mainFrameAllowedHosts.contains { suffix in
            host == suffix || host.hasSuffix("." + suffix)
        }
    }

    private static let mainFrameAllowedHosts: [String] = [
        "youtube.com",
        "youtube-nocookie.com",
        "youtu.be",
        "spotify.com",        // covers open.spotify.com
    ]
}
