import SwiftUI
import Metal
import QuartzCore
import simd

/// Live shader thumbnail used inside `ScenePicker`. A tiny CAMetalLayer-backed
/// NSView running the picked shader at the tile size — each tile is its own
/// fragment shader render at ~260×150. Pauses when the picker dismisses.
struct SceneTilePreview: View {
    let scene: Scene
    let renderer: ShaderRenderer

    var body: some View {
        ShaderTilePreview(sceneId: scene.id, renderer: renderer)
    }
}

struct ShaderTilePreview: NSViewRepresentable {
    let sceneId: String
    let renderer: ShaderRenderer

    func makeNSView(context: Context) -> ShaderTileView {
        ShaderTileView(sceneId: sceneId, renderer: renderer)
    }

    func updateNSView(_ view: ShaderTileView, context: Context) { }
}

final class ShaderTileView: NSView {
    private let sceneId: String
    private let renderer: ShaderRenderer
    private let startTime: CFTimeInterval
    private var pipeline: MTLRenderPipelineState?
    private var link: CADisplayLink?
    private var resolution = SIMD2<Float>(1, 1)

    init(sceneId: String, renderer: ShaderRenderer) {
        self.sceneId = sceneId
        self.renderer = renderer
        self.startTime = CACurrentMediaTime()
        super.init(frame: .zero)
        wantsLayer = true
        do {
            pipeline = try renderer.pipeline(for: sceneId)
        } catch {
            NSLog("[ScenePreview] pipeline failed for %@: %@", sceneId, "\(error)")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.contentsGravity = .resize
        return layer
    }

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override func layout() {
        super.layout()
        guard let metalLayer else { return }
        let scale = window?.backingScaleFactor ?? 2.0
        let pixelSize = CGSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )
        if metalLayer.drawableSize != pixelSize {
            metalLayer.drawableSize = pixelSize
        }
        resolution = SIMD2<Float>(Float(pixelSize.width), Float(pixelSize.height))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, pipeline != nil { startLink() } else { stopLink() }
    }

    private func startLink() {
        guard link == nil else { return }
        let l = displayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() { render() }

    private func render() {
        guard let pipeline,
              let metalLayer,
              let drawable = metalLayer.nextDrawable() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let buffer = renderer.queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        var t   = Float(CACurrentMediaTime() - startTime)
        var res = resolution
        var ac  = SIMD4<Float>(1.0, 0.55, 0.40, 1.0)

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&t,   length: MemoryLayout<Float>.size,        index: 0)
        encoder.setFragmentBytes(&res, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder.setFragmentBytes(&ac,  length: MemoryLayout<SIMD4<Float>>.size, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
