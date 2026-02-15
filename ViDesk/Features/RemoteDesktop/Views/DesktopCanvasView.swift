import SwiftUI
import MetalKit

/// 桌面画布视图
/// 使用 Metal 渲染远程桌面画面
struct DesktopCanvasView: View {
    let session: RDPSession
    let inputManager: InputManager
    let scaleMode: ScaleMode

    @State private var viewSize: CGSize = .zero
    @State private var metalAvailable: Bool = true

    var body: some View {
        GeometryReader { geometry in
            if metalAvailable {
                MetalDesktopView(
                    session: session,
                    inputManager: inputManager,
                    scaleMode: scaleMode,
                    metalAvailable: $metalAvailable
                )
                .onAppear {
                    viewSize = geometry.size
                }
                .onChange(of: geometry.size) { _, newSize in
                    viewSize = newSize
                }
            } else {
                // Metal 不可用时显示占位视图
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        ZStack {
            Color.black

            VStack(spacing: 16) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 64))
                    .foregroundStyle(.gray)

                Text("远程桌面")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("已连接 (模拟器模式)")
                    .font(.subheadline)
                    .foregroundStyle(.gray)

                Text("Metal 渲染在模拟器上不可用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Metal 渲染视图
struct MetalDesktopView: UIViewRepresentable {
    let session: RDPSession
    let inputManager: InputManager
    let scaleMode: ScaleMode
    @Binding var metalAvailable: Bool

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView(frame: .zero, device: nil)

        // 尝试获取 Metal 设备
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("警告: Metal 在此设备上不可用")
            DispatchQueue.main.async {
                metalAvailable = false
            }
            return mtkView
        }

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)

        // 设置渲染器
        if let renderer = MetalRenderer(device: device) {
            renderer.scaleMode = scaleMode
            mtkView.delegate = renderer
            context.coordinator.renderer = renderer
        } else {
            print("警告: MetalRenderer 初始化失败")
            DispatchQueue.main.async {
                metalAvailable = false
            }
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
