import Foundation
import WebKit

/// Imports the user's Safari `.youtube.com` cookies into our WKWebView's cookie
/// store so the soundtrack iframe sees the user as their real (Premium) account.
/// YouTube blocks WKWebView sign-ins, so this is the only way to honor a
/// Premium subscription.
///
/// Requires Full Disk Access — the cookies file lives under
/// `~/Library/Containers/com.apple.Safari/...` which is FDA-protected. If
/// reading fails (most likely FDA not granted), `sync` quietly returns and
/// playback proceeds with the unauthenticated session.
enum YouTubeCookieSync {

    /// Read Safari's binarycookies file and inject any `.youtube.com` cookies
    /// into `store`. Idempotent — re-running just refreshes the values.
    @MainActor
    static func sync(into store: WKHTTPCookieStore) async {
        let cookies: [SafariBinaryCookies.Cookie]
        do {
            cookies = try SafariBinaryCookies.read(at: SafariBinaryCookies.defaultCookiesPath)
        } catch {
            return
        }

        let now = Date()
        for c in cookies where isYouTubeDomain(c.domain) && c.expiry > now {
            guard let cookie = makeCookie(from: c) else { continue }
            await store.setCookie(cookie)
        }
    }

    private static func isYouTubeDomain(_ domain: String) -> Bool {
        let trimmed = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return trimmed == "youtube.com" || trimmed.hasSuffix(".youtube.com") ||
               trimmed == "google.com"  || trimmed.hasSuffix(".google.com")
    }

    private static func makeCookie(from c: SafariBinaryCookies.Cookie) -> HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .domain: c.domain,
            .path: c.path.isEmpty ? "/" : c.path,
            .name: c.name,
            .value: c.value,
            .expires: c.expiry,
        ]
        if c.isSecure { props[.secure] = "TRUE" }
        return HTTPCookie(properties: props)
    }
}
