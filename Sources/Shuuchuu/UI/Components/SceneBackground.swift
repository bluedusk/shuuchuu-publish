import SwiftUI
import MetalKit
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

final class SceneHostView: NSView {
    private let renderer: ShaderRenderer
    private var frontView: MTKView?
    private var frontDelegate: ShaderDrawDelegate?
    private var currentId: String?

    init(renderer: ShaderRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // SwiftUI calls this when the popover opens (window != nil) and closes (nil).
        // Pause the render loop while the popover is dismissed so the GPU stays idle.
        let paused = (window == nil)
        frontView?.isPaused = paused
    }

    // MARK: - Show / clear

    func show(active: SceneController.Active) {
        guard active.id != currentId else { return }
        currentId = active.id

        let pipeline: MTLRenderPipelineState
        do {
            pipeline = try renderer.pipeline(for: active.id)
        } catch {
            print("[SceneHostView] pipeline build failed for \(active.id): \(error)")
            clear()
            return
        }

        let delegate = ShaderDrawDelegate(pipeline: pipeline,
                                          queue: renderer.queue,
                                          startTime: active.startTime)
        let mtk = MTKView(frame: bounds, device: renderer.device)
        mtk.colorPixelFormat = .bgra8Unorm
        mtk.framebufferOnly = true
        mtk.translatesAutoresizingMaskIntoConstraints = false
        mtk.wantsLayer = true
        mtk.layer?.opacity = 0
        mtk.delegate = delegate
        addSubview(mtk)
        NSLayoutConstraint.activate([
            mtk.topAnchor.constraint(equalTo: topAnchor),
            mtk.leadingAnchor.constraint(equalTo: leadingAnchor),
            mtk.trailingAnchor.constraint(equalTo: trailingAnchor),
            mtk.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let oldView = frontView
        frontView = mtk
        frontDelegate = delegate

        crossfade(in: mtk, out: oldView)
    }

    func clear() {
        let oldId = currentId
        currentId = nil
        guard let oldView = frontView else { return }
        frontView = nil
        frontDelegate = nil
        crossfade(in: nil, out: oldView)
        _ = oldId
    }

    func setAccent(_ accent: SIMD4<Float>) {
        frontDelegate?.accent = accent
    }

    // MARK: - Crossfade

    private func crossfade(in newView: MTKView?, out oldView: NSView?) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            newView?.animator().layer?.opacity = 1
            oldView?.animator().layer?.opacity = 0
        }, completionHandler: { [weak oldView] in
            oldView?.removeFromSuperview()
        })
    }
}
