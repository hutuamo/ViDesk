import Foundation
import SwiftUI

/// 手势翻译器
/// 将 VisionOS 手势转换为 Windows 鼠标/键盘操作
@MainActor
final class GestureTranslator {
    // MARK: - 属性

    private weak var inputManager: InputManager?

    /// 长按识别阈值
    private let longPressThreshold: TimeInterval = 0.5

    /// 双击识别阈值
    private let doubleTapThreshold: TimeInterval = 0.3

    /// 拖拽移动阈值
    private let dragThreshold: CGFloat = 10.0

    // MARK: - 状态

    private var tapStartTime: Date?
    private var lastTapTime: Date?
    private var lastTapLocation: CGPoint?
    private var isDragging: Bool = false
    private var dragStartLocation: CGPoint?

    // MARK: - 初始化

    init(inputManager: InputManager) {
        self.inputManager = inputManager
    }

    // MARK: - VisionOS 手势映射

    /// 处理空间点击手势 (眼动 + 捏合)
    /// 映射: 鼠标左键单击
    func handleSpatialTap(at location: CGPoint) {
        let now = Date()

        // 检查是否为双击
        if let lastTap = lastTapTime,
           let lastLocation = lastTapLocation,
           now.timeIntervalSince(lastTap) < doubleTapThreshold,
           distance(location, lastLocation) < dragThreshold {
            inputManager?.leftDoubleClick(at: location)
            lastTapTime = nil
            lastTapLocation = nil
        } else {
            inputManager?.leftClick(at: location)
            lastTapTime = now
            lastTapLocation = location
        }
    }

    /// 处理空间长按手势
    /// 映射: 鼠标右键单击
    func handleSpatialLongPress(at location: CGPoint) {
        inputManager?.rightClick(at: location)
    }

    /// 处理拖拽手势开始
    func handleDragStart(at location: CGPoint) {
        dragStartLocation = location
        isDragging = false
    }

    /// 处理拖拽手势移动
    func handleDragChanged(at location: CGPoint) {
        guard let startLocation = dragStartLocation else { return }

        if !isDragging {
            if distance(location, startLocation) > dragThreshold {
                isDragging = true
                inputManager?.beginDrag(at: startLocation)
            }
        }

        if isDragging {
            inputManager?.drag(to: location)
        }
    }

    /// 处理拖拽手势结束
    func handleDragEnd(at location: CGPoint) {
        if isDragging {
            inputManager?.endDrag(at: location)
        }
        isDragging = false
        dragStartLocation = nil
    }

    /// 处理缩放手势
    /// 映射: 鼠标滚轮
    func handleMagnification(scale: CGFloat, velocity: CGFloat = 0) {
        // 将缩放比例转换为滚轮增量
        // scale > 1 表示放大 (向上滚动)
        // scale < 1 表示缩小 (向下滚动)
        let delta = (scale - 1.0) * 120
        inputManager?.scroll(delta: delta)
    }

    /// 处理旋转手势
    /// 映射: 可配置 (默认忽略)
    func handleRotation(angle: CGFloat) {
        // VisionOS 中旋转手势可能不常用
        // 可以映射为特殊操作
    }

    /// 处理滑动手势
    /// 映射: 鼠标滚轮
    func handleScroll(translation: CGSize, velocity: CGSize) {
        // 垂直滚动
        if abs(translation.height) > 1 {
            inputManager?.scroll(delta: -translation.height)
        }

        // 水平滚动
        if abs(translation.width) > 1 {
            inputManager?.scroll(delta: translation.width, horizontal: true)
        }
    }

    // MARK: - 辅助方法

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - VisionOS 手势视图修饰器

#if os(visionOS)
import RealityKit

/// 为视图添加 VisionOS 手势支持
struct VisionOSGestureModifier: ViewModifier {
    let translator: GestureTranslator
    let coordinateConverter: (CGPoint) -> CGPoint?

    func body(content: Content) -> some View {
        content
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if let point = coordinateConverter(value.location) {
                            translator.handleSpatialTap(at: point)
                        }
                    }
            )
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: SpatialTapGesture())
                    .onEnded { value in
                        switch value {
                        case .second(true, let tap):
                            if let tap = tap,
                               let point = coordinateConverter(tap.location) {
                                translator.handleSpatialLongPress(at: point)
                            }
                        default:
                            break
                        }
                    }
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if let start = coordinateConverter(value.startLocation),
                           let current = coordinateConverter(value.location) {
                            if value.translation == .zero {
                                translator.handleDragStart(at: start)
                            } else {
                                translator.handleDragChanged(at: current)
                            }
                        }
                    }
                    .onEnded { value in
                        if let point = coordinateConverter(value.location) {
                            translator.handleDragEnd(at: point)
                        }
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onEnded { value in
                        translator.handleMagnification(scale: value.magnification)
                    }
            )
    }
}

extension View {
    func visionOSGestures(translator: GestureTranslator,
                         coordinateConverter: @escaping (CGPoint) -> CGPoint?) -> some View {
        modifier(VisionOSGestureModifier(translator: translator,
                                          coordinateConverter: coordinateConverter))
    }
}
#endif
