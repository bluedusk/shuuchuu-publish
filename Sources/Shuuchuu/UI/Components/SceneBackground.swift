import SwiftUI
import Metal
import QuartzCore
import simd

struct SceneBackground: NSViewRepresentable {
    @EnvironmentObject var scene: SceneController
    @EnvironmentObject var design: DesignSettings
    let renderer: ShaderRenderer

    func makeNSView(context: Context) -> SceneHostView {
        SceneHostView(renderer: renderer)
    }

    func updateNSView(_ view: SceneHostView, context: Context) {
        view.setAccent(accentVector(design.accent))
        if let active = scene.active {
            view.show(active: active)
        } else {
            view.clear()
        }
    }

    private func accentVector(_ color: Color) -> SIMD4<Float> {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return SIMD4<Float>(Float(ns.redComponent),
                            Float(ns.greenComponent),
                            Float(ns.blueComponent),
                            Float(ns.alphaComponent))
    }
}

/// CAMetalLayer-backed NSView. Avoids `MTKView` because that wrapper has
/// a known SwiftUI compositing issue on macOS 26 — its rendered drawable
/// surface doesn't get composited into the layer tree when hosted inside
/// an `NSViewRepresentable`. With the CAMetalLayer *as* the host's backing
/// layer, SwiftUI's compositor renders the host's layer directly, and the
/// next-drawable surface lands on screen.
final class SceneHostView: NSView {
    private let renderer: ShaderRenderer
    private var link: CADisplayLink?
    private var pipeline: MTLRenderPipelineState?
    private var startTime: CFTimeInterval = 0
    private var currentId: String?
    private var resolution = SIMD2<Float>(1, 1)
    private var accent = SIMD4<Float>(1, 1, 1, 1)

    init(renderer: ShaderRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        wantsLayer = true
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

    private var metalLayer: CAMetalLayer? {
        layer as? CAMetalLayer
    }

    // MARK: - Resize

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

    // MARK: - Window lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, currentId != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    // MARK: - Show / clear

    func show(active: SceneController.Active) {
        if active.id == currentId, pipeline != nil { return }
        let p: MTLRenderPipelineState
        do {
            p = try renderer.pipeline(for: active.id)
        } catch {
            NSLog("[Scene] pipeline failed for %@: %@", active.id, "\(error)")
            clear()
            return
        }
        pipeline = p
        startTime = active.startTime
        currentId = active.id
        metalLayer?.isHidden = false
        if window != nil { startDisplayLink() }
    }

    func clear() {
        stopDisplayLink()
        pipeline = nil
        currentId = nil
        metalLayer?.isHidden = true
    }

    func setAccent(_ a: SIMD4<Float>) {
        accent = a
    }

    // MARK: - Display link

    private func startDisplayLink() {
        guard link == nil else { return }
        let l = displayLink(target: self, selector: #selector(displayLinkTick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stopDisplayLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func displayLinkTick() {
        render()
    }

    // MARK: - Render

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

        var time = Float(CACurrentMediaTime() - startTime)
        var res = resolution
        var ac = accent

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentBytes(&res, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        encoder.setFragmentBytes(&ac, length: MemoryLayout<SIMD4<Float>>.size, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

}
