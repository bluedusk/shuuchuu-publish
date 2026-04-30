import Foundation
import Metal
@testable import Shuuchuu

@MainActor
final class StubShaderRenderer: ShaderRendering {
    var failOn: Set<String> = []
    private(set) var warmedIds: [String] = []

    func warm(_ sceneId: String) throws {
        warmedIds.append(sceneId)
        if failOn.contains(sceneId) {
            throw ShaderRendererError.compileFailed(
                sceneId: sceneId, message: "stub forced failure"
            )
        }
    }

    func pipeline(for sceneId: String) throws -> MTLRenderPipelineState {
        // Tests never exercise the draw path; trap so a regression surfaces loudly.
        fatalError("StubShaderRenderer.pipeline(for:) must not be called in tests")
    }
}
