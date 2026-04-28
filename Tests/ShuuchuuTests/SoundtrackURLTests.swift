import XCTest
@testable import Shuuchuu

final class SoundtrackURLTests: XCTestCase {

    // MARK: - YouTube

    func testYouTubeWatchURL() {
        let r = SoundtrackURL.parse("https://www.youtube.com/watch?v=jfKfPfyJRdk")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/jfKfPfyJRdk?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }

    func testYouTubeShortURL() {
        let r = SoundtrackURL.parse("https://youtu.be/jfKfPfyJRdk")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/jfKfPfyJRdk?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }

    func testYouTubeShortURLWithSiTracker() {
        let r = SoundtrackURL.parse("https://youtu.be/jfKfPfyJRdk?si=sometoken")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/jfKfPfyJRdk?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }

    func testYouTubePlaylistURL() {
        let r = SoundtrackURL.parse("https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/videoseries?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf&enablejsapi=1",
                                         humanLabel: "YouTube playlist")))
    }

    func testYouTubeMusicURL() {
        let r = SoundtrackURL.parse("https://music.youtube.com/watch?v=jfKfPfyJRdk")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/jfKfPfyJRdk?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }

    func testYouTubeWatchWithExtraParams() {
        // si= and t= trackers should be ignored; only v= matters.
        let r = SoundtrackURL.parse("https://www.youtube.com/watch?v=abc123&t=42s&si=foo")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/abc123?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }

    func testYouTubeWatchMissingId() {
        XCTAssertEqual(SoundtrackURL.parse("https://www.youtube.com/watch?foo=bar"),
                       .failure(.invalidURL))
    }

    // MARK: - Spotify

    func testSpotifyTrackURL() {
        let r = SoundtrackURL.parse("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual(r, .success(.init(kind: .spotify,
                                         embedURL: "https://open.spotify.com/embed/track/4uLU6hMCjMI75M1A2tKUQC",
                                         humanLabel: "Spotify track")))
    }

    func testSpotifyPlaylistWithSiTracker() {
        let r = SoundtrackURL.parse("https://open.spotify.com/playlist/37i9dQZF1DX0XUsuxWHRQd?si=abc123")
        XCTAssertEqual(r, .success(.init(kind: .spotify,
                                         embedURL: "https://open.spotify.com/embed/playlist/37i9dQZF1DX0XUsuxWHRQd",
                                         humanLabel: "Spotify playlist")))
    }

    func testSpotifyAlbumURL() {
        let r = SoundtrackURL.parse("https://open.spotify.com/album/2noRn2Aes5aoNVsU6iWThc")
        XCTAssertEqual(r, .success(.init(kind: .spotify,
                                         embedURL: "https://open.spotify.com/embed/album/2noRn2Aes5aoNVsU6iWThc",
                                         humanLabel: "Spotify album")))
    }

    func testSpotifyEpisodeURL() {
        let r = SoundtrackURL.parse("https://open.spotify.com/episode/0Q86acNRm6V9GYx55SXKwf")
        XCTAssertEqual(r, .success(.init(kind: .spotify,
                                         embedURL: "https://open.spotify.com/embed/episode/0Q86acNRm6V9GYx55SXKwf",
                                         humanLabel: "Spotify episode")))
    }

    // MARK: - Rejected

    func testUnsupportedHost() {
        XCTAssertEqual(SoundtrackURL.parse("https://soundcloud.com/foo/bar"),
                       .failure(.unsupportedHost))
    }

    func testGarbageString() {
        XCTAssertEqual(SoundtrackURL.parse("not a url at all"),
                       .failure(.invalidURL))
    }

    func testEmptyString() {
        XCTAssertEqual(SoundtrackURL.parse(""), .failure(.invalidURL))
    }

    func testWhitespaceTrimmed() {
        // Common when pasting from the URL bar.
        let r = SoundtrackURL.parse("  https://youtu.be/abc123  \n")
        XCTAssertEqual(r, .success(.init(kind: .youtube,
                                         embedURL: "https://www.youtube.com/embed/abc123?enablejsapi=1",
                                         humanLabel: "YouTube video")))
    }
}
