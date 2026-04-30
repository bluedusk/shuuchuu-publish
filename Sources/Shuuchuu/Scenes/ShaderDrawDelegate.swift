import Foundation
import MetalKit
import simd

/// Per-MTKView delegate that owns one pipeline + start time and binds the three
/// uniform buffers each frame. Stateless across frames otherwise.
final class ShaderDrawDelegate: NSObject, MTKViewDelegate {
    private let pipeline: MTLRenderPipelineState
    private let queue: MTLCommandQueue
    private let startTime: CFTimeInterval
    private var resolution = SIMD2<Float>(1, 1)

    /// Updated by the host on each `updateNSView` so live hue-slider changes
    /// in `DesignSettings` flow through to the shader.
    var accent: SIMD4<Float> = .init(1, 1, 1, 1)

    init(pipeline: MTLRenderPipelineState,
         queue: MTLCommandQueue,
         startTime: CFTimeInterval) {
        self.pipeline = pipeline
        self.queue = queue
        self.startTime = startTime
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        resolution = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        var time = Float(CACurrentMediaTime() - startTime)
        var res = resolution
        var ac = accent

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&time,
                                 length: MemoryLayout<Float>.size,
                                 index: 0)
        encoder.setFragmentBytes(&res,
                                 length: MemoryLayout<SIMD2<Float>>.size,
                                 index: 1)
        encoder.setFragmentBytes(&ac,
                                 length: MemoryLayout<SIMD4<Float>>.size,
                                 index: 2)
        encoder.drawPrimitives(type: .triangle,
                               vertexStart: 0,
                               vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
