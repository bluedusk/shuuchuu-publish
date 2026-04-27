import AppKit
import WebKit
import Foundation

private final class BridgeMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: WebSoundtrackController?
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        Task { @MainActor [weak self] in
            self?.owner?.handleBridgeMessage(dict)
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

    private let window: NSWindow
    private let webView: WKWebView
    private var loadedSoundtrack: WebSoundtrack?
    private var bridgeReady: Bool = false
    private var pendingEmbedURL: String?
    private var pendingAutoplay: Bool = false

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

        let proxy = BridgeMessageProxy()
        config.userContentController.add(proxy, name: "xnoise")

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

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
    }

    // MARK: - WebSoundtrackControlling

    func load(_ soundtrack: WebSoundtrack, autoplay: Bool) {
        let bridgeFilename: String
        switch soundtrack.kind {
        case .youtube: bridgeFilename = "youtube-bridge"
        case .spotify: bridgeFilename = "spotify-bridge"
        }

        // Same provider already loaded → just swap the embed URL via the bridge.
        if loadedSoundtrack?.kind == soundtrack.kind, bridgeReady {
            loadedSoundtrack = soundtrack
            pendingEmbedURL = nil
            evaluate("window.bridge.load(\(jsString(soundtrack.url)))")
            evaluate("window.bridge.setVolume(\(soundtrack.volume))")
            if autoplay { evaluate("window.bridge.play()") }
            return
        }

        // Different provider (or first load) — load the bridge HTML; the embed URL
        // is replayed onto the bridge in `handleBridgeMessage(...)` when `ready` arrives.
        loadedSoundtrack = soundtrack
        bridgeReady = false
        pendingEmbedURL = soundtrack.url
        pendingAutoplay = autoplay
        guard let url = Bundle.module.url(forResource: bridgeFilename, withExtension: "html") else {
            assertionFailure("\(bridgeFilename).html missing from bundle")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func setPaused(_ paused: Bool) {
        guard bridgeReady else { return }
        evaluate(paused ? "window.bridge.pause()" : "window.bridge.play()")
    }

    func setVolume(_ volume: Double) {
        guard bridgeReady else { return }
        evaluate("window.bridge.setVolume(\(volume))")
    }

    func unload() {
        loadedSoundtrack = nil
        bridgeReady = false
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
            if let url = pendingEmbedURL {
                evaluate("window.bridge.load(\(jsString(url)))")
                pendingEmbedURL = nil
            }
            if let s = loadedSoundtrack {
                evaluate("window.bridge.setVolume(\(s.volume))")
                if pendingAutoplay {
                    evaluate("window.bridge.play()")
                    pendingAutoplay = false
                }
            }
        case "titleChanged":
            if let title = dict["title"] as? String, let id = loadedSoundtrack?.id {
                onTitleChange?(id, title)
            }
        case "signInRequired":
            if let id = loadedSoundtrack?.id {
                onSignInRequired?(id)
            }
        case "stateChange", "error":
            // No app-level reaction in v1 beyond observability.
            break
        default:
            break
        }
    }

    // MARK: - JS helpers

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
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
