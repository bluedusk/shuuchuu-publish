import XCTest
@testable import Shuuchuu

@MainActor
final class SceneControllerTests: XCTestCase {
    private static let defaultsKey = "shuuchuu.activeScene"

    private func makeDefaults() -> UserDefaults {
        let suite = "tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func library() -> ScenesLibrary {
        let url = Bundle.module.url(forResource: "scenes-fixture",
                                    withExtension: "json")!
        return ScenesLibrary(jsonData: try! Data(contentsOf: url))
    }

    func testSetSceneValidIdPublishesAndPersists() {
        let defaults = makeDefaults()
        let renderer = StubShaderRenderer()
        let ctl = SceneController(library: library(), renderer: renderer,
                                  defaults: defaults)
        ctl.setScene("aurora")
        XCTAssertEqual(ctl.activeSceneId, "aurora")
        XCTAssertNotNil(ctl.active)
        XCTAssertEqual(defaults.string(forKey: Self.defaultsKey), "aurora")
        XCTAssertEqual(renderer.warmedIds, ["aurora"])
    }

    func testSetSceneNilClearsAndUnpersists() {
        let defaults = makeDefaults()
        let ctl = SceneController(library: library(),
                                  renderer: StubShaderRenderer(),
                                  defaults: defaults)
        ctl.setScene("aurora")
        ctl.setScene(nil)
        XCTAssertNil(ctl.activeSceneId)
        XCTAssertNil(ctl.active)
        XCTAssertNil(defaults.string(forKey: Self.defaultsKey))
    }

    func testSetSceneUnknownIdFallsBackToNil() {
        let defaults = makeDefaults()
        let ctl = SceneController(library: library(),
                                  renderer: StubShaderRenderer(),
                                  defaults: defaults)
        ctl.setScene("not-in-library")
        XCTAssertNil(ctl.activeSceneId)
        XCTAssertNil(defaults.string(forKey: Self.defaultsKey))
    }

    func testSetSceneCompileFailureFallsBackToNil() {
        let defaults = makeDefaults()
        let renderer = StubShaderRenderer()
        renderer.failOn = ["aurora"]
        let ctl = SceneController(library: library(), renderer: renderer,
                                  defaults: defaults)
        ctl.setScene("aurora")
        XCTAssertNil(ctl.activeSceneId)
        XCTAssertNil(defaults.string(forKey: Self.defaultsKey))
    }

    func testInitRestoresFromDefaultsWhenIdValid() {
        let defaults = makeDefaults()
        defaults.set("plasma", forKey: Self.defaultsKey)
        let ctl = SceneController(library: library(),
                                  renderer: StubShaderRenderer(),
                                  defaults: defaults)
        XCTAssertEqual(ctl.activeSceneId, "plasma")
    }

    func testInitFallsBackWhenPersistedIdMissingFromLibrary() {
        let defaults = makeDefaults()
        defaults.set("ghost", forKey: Self.defaultsKey)
        let ctl = SceneController(library: library(),
                                  renderer: StubShaderRenderer(),
                                  defaults: defaults)
        XCTAssertNil(ctl.activeSceneId)
    }

    func testInitFallsBackWhenWarmFailsForPersistedId() {
        let defaults = makeDefaults()
        defaults.set("plasma", forKey: Self.defaultsKey)
        let renderer = StubShaderRenderer()
        renderer.failOn = ["plasma"]
        let ctl = SceneController(library: library(), renderer: renderer,
                                  defaults: defaults)
        XCTAssertNil(ctl.activeSceneId)
        // Should also remove the bad id from defaults so we don't retry next launch.
        XCTAssertNil(defaults.string(forKey: Self.defaultsKey))
    }
}
