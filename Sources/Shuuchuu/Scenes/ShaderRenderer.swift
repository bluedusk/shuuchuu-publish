import Foundation
import Metal

@MainActor
public final class ShaderRenderer: ShaderRendering {
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    private let vertexFunction: MTLFunction
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]

    private static let vertexSource = """
    #include <metal_stdlib>
    using namespace metal;

    vertex float4 sceneVertex(uint vid [[vertex_id]]) {
        // Single fullscreen triangle covering the viewport at NDC corners.
        float2 p = float2((vid == 1) ? 3.0 : -1.0,
                          (vid == 2) ? -3.0 : 1.0);
        return float4(p, 0.0, 1.0);
    }
    """

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        do {
            let vertLib = try device.makeLibrary(source: Self.vertexSource,
                                                 options: nil)
            guard let vertFn = vertLib.makeFunction(name: "sceneVertex") else {
                return nil
            }
            self.device = device
            self.queue = queue
            self.vertexFunction = vertFn
        } catch {
            print("[ShaderRenderer] failed to compile shared vertex stage: \(error)")
            return nil
        }
    }

    public func warm(_ sceneId: String) throws {
        _ = try cachedPipeline(for: sceneId)
    }

    public func pipeline(for sceneId: String) throws -> MTLRenderPipelineState {
        try cachedPipeline(for: sceneId)
    }

    private func cachedPipeline(for sceneId: String) throws -> MTLRenderPipelineState {
        if let cached = pipelineCache[sceneId] { return cached }

        guard let url = Bundle.module.url(forResource: sceneId,
                                          withExtension: "metal"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw ShaderRendererError.sourceNotFound(sceneId: sceneId)
        }

        let fragLib: MTLLibrary
        do {
            fragLib = try device.makeLibrary(source: source, options: nil)
        } catch {
            throw ShaderRendererError.compileFailed(
                sceneId: sceneId,
                message: String(describing: error)
            )
        }

        guard let fragFn = fragLib.makeFunction(name: "sceneMain") else {
            throw ShaderRendererError.missingFunction(sceneId: sceneId,
                                                      function: "sceneMain")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = fragFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        let pipeline = try device.makeRenderPipelineState(descriptor: desc)
        pipelineCache[sceneId] = pipeline
        return pipeline
    }
}
