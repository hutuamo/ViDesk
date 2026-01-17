import SwiftUI
import MetalKit

/// 桌面画布视图
/// 使用 Metal 渲染远程桌面画面
struct DesktopCanvasView: View {
    let session: RDPSession
    let inputManager: InputManager
    let scaleMode: ScaleMode

    @State private var viewSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            MetalDesktopView(
                session: session,
                inputManager: inputManager,
                scaleMode: scaleMode
            )
            .onAppear {
                viewSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                viewSize = newSize
            }
        }
    }
}

/// Metal 渲染视图
struct MetalDesktopView: UIViewRepresentable {
    let session: RDPSession
    let inputManager: InputManager
    let scaleMode: ScaleMode

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        // 设置渲染器
        if let renderer = MetalRenderer(device: device) {
            renderer.scaleMode = scaleMode
            mtkView.delegate = renderer
            context.coordinator.renderer = renderer
        }

        // 添加手势识别
        setupGestures(on: mtkView, coordinator: context.coordinator)

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.scaleMode = scaleMode
        context.coordinator.renderer?.frameBuffer = session.frameBuffer
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(inputManager: inputManager)
    }

    private func setupGestures(on view: MTKView, coordinator: Coordinator) {
        // 单击手势
        let tapGesture = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        // 双击手势
        let doubleTapGesture = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapGesture)
        tapGesture.require(toFail: doubleTapGesture)

        // 长按手势 (右键)
        let longPressGesture = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPressGesture)

        // 拖拽手势
        let panGesture = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(panGesture)

        // 缩放手势 (滚轮)
        let pinchGesture = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        let inputManager: InputManager
        var renderer: MetalRenderer?

        init(inputManager: InputManager) {
            self.inputManager = inputManager
        }

        private func convertToTextureCoordinate(_ point: CGPoint, in view: UIView) -> CGPoint? {
            return renderer?.viewToTextureCoordinate(point, viewSize: view.bounds.size)
        }

        @MainActor
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let point = convertToTextureCoordinate(gesture.location(in: gesture.view), in: gesture.view!) else {
                return
            }
            inputManager.leftClick(at: point)
        }

        @MainActor
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let point = convertToTextureCoordinate(gesture.location(in: gesture.view), in: gesture.view!) else {
                return
            }
            inputManager.leftDoubleClick(at: point)
        }

        @MainActor
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let point = convertToTextureCoordinate(gesture.location(in: gesture.view), in: gesture.view!) else {
                return
            }
            inputManager.rightClick(at: point)
        }

        @MainActor
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view,
                  let point = convertToTextureCoordinate(gesture.location(in: view), in: view) else {
                return
            }

            switch gesture.state {
            case .began:
                inputManager.beginDrag(at: point)
            case .changed:
                inputManager.drag(to: point)
            case .ended, .cancelled:
                inputManager.endDrag(at: point)
            default:
                break
            }
        }

        @MainActor
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .ended else { return }

            let delta = (gesture.scale - 1.0) * 120
            inputManager.scroll(delta: delta)
        }
    }
}

#Preview {
    DesktopCanvasView(
        session: RDPSession(),
        inputManager: InputManager(),
        scaleMode: .fit
    )
}
