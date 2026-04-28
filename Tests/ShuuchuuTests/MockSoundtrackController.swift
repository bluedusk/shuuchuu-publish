import Foundation
import SwiftUI
@testable import Shuuchuu

/// In-memory recorder. Tests assert against the call log.
@MainActor
final class MockSoundtrackController: WebSoundtrackControlling {
    enum Call: Equatable {
        case load(id: UUID, autoplay: Bool)
        case setPaused(Bool)
        case setVolume(Double)
        case unload
    }
    var calls: [Call] = []
    private(set) var loadedId: UUID?
    private(set) var paused: Bool = true

    var onTitleChange: ((UUID, String) -> Void)?
    var onSignInRequired: ((UUID) -> Void)?
    var onPlaybackError: ((UUID, Int) -> Void)?

    func load(_ soundtrack: WebSoundtrack, autoplay: Bool) {
        loadedId = soundtrack.id
        paused = !autoplay
        calls.append(.load(id: soundtrack.id, autoplay: autoplay))
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        calls.append(.setPaused(paused))
    }

    func setVolume(_ volume: Double) {
        calls.append(.setVolume(volume))
    }

    func unload() {
        loadedId = nil
        calls.append(.unload)
    }

    func playerView() -> AnyView { AnyView(EmptyView()) }

    /// Test convenience — simulate the bridge firing a title-change event.
    func simulateTitleChange(title: String) {
        guard let id = loadedId else { return }
        onTitleChange?(id, title)
    }
}
