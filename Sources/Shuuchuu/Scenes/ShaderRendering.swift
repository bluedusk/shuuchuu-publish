import Foundation
import Metal

/// Errors thrown by `ShaderRendering` implementations.
public enum ShaderRendererError: Error, Equatable {
    case noMetalDevice
    case sourceNotFound(sceneId: String)
    case compileFailed(sceneId: String, message: String)
    case missingFunction(sceneId: String, function: String)
}

/// Compiles and caches Metal pipelines for shader scenes.
///
/// `warm(_:)` is called by `SceneController.setScene` when the user picks a scene —
/// it surfaces compile errors *before* the controller publishes the new id, so a
/// broken `.metal` file falls back to no scene instead of producing a black square.
///
/// `pipeline(for:)` is called by `SceneBackground`/`SceneHostView` at MTKView build
/// time. It is expected to return a cached pipeline (warm has already been called).
@MainActor
public protocol ShaderRendering: AnyObject {
    func warm(_ sceneId: String) throws
    func pipeline(for sceneId: String) throws -> MTLRenderPipelineState
}
