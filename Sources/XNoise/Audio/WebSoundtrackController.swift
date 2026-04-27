import AppKit
import WebKit
import Foundation

/// Hidden long-lived host for a single WKWebView. Survives popover dismissal so
/// audio continues across menubar close/reopen. Reuses one web view across
/// activations — cookie persistence (default data store) keeps the user's Spotify
/// login alive between launches.
@MainActor
final class WebSoundtrackController: NSObject, WebSoundtrackControlling {

    var onTitleChange: ((WebSoundtrack.ID, String) -> Void)?
    var onSignInRequired: ((WebSoundtrack.ID) -> Void)?

    private let window: NSWindow
    private let webView: WKWebView
    private var loadedSoundtrack: WebSoundtrack?

    override init() {
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
        config.websiteDataStore = .default()         // persistent cookies
        config.mediaTypesRequiringUserActionForPlayback = []   // bridge plays without gesture

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

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
    }

    // MARK: - WebSoundtrackControlling

    func load(_ soundtrack: WebSoundtrack, autoplay: Bool) {
        loadedSoundtrack = soundtrack
        // Bridge HTML loading lands in Task 13. For now load `about:blank` so the
        // scaffold is observable and harmless.
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    func setPaused(_ paused: Bool) {
        // JS bridge command added in Task 13.
    }

    func setVolume(_ volume: Double) {
        // JS bridge command added in Task 13.
    }

    func unload() {
        loadedSoundtrack = nil
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    // MARK: - Expand-row reveal support (used by Task 17)

    /// The live web view, exposed so a row in the Soundtracks tab can lift it
    /// into an inline expand container. Caller is responsible for calling
    /// `reclaimWebView()` when the row collapses.
    var hostedWebView: WKWebView { webView }

    /// Re-attach the web view to the hidden window after an expand-row collapses.
    func reclaimWebView() {
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
}
