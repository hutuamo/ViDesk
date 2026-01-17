import Foundation
import Combine

/// 输入管理器
/// 负责协调手势和键盘输入，并转发到 RDP 会话
@MainActor
@Observable
final class InputManager {
    // MARK: - 属性

    /// 当前输入模式
    var inputMode: InputMode = .pointer

    /// 鼠标指针位置 (纹理坐标)
    private(set) var cursorPosition: CGPoint = .zero

    /// 鼠标是否按下
    private(set) var isMouseDown: Bool = false

    /// 滚动速度倍数
    var scrollMultiplier: CGFloat = 1.0

    /// 是否启用惯性滚动
    var enableInertialScroll: Bool = true

    // MARK: - 私有属性

    private weak var session: RDPSession?
    private var gestureTranslator: GestureTranslator?
    private var keyboardMapper: KeyboardMapper

    private var lastMoveTime: Date = Date()
    private var moveThrottleInterval: TimeInterval = 1.0 / 120.0

    // MARK: - 初始化

    init() {
        self.keyboardMapper = KeyboardMapper()
    }

    /// 绑定到 RDP 会话
    func bind(to session: RDPSession) {
        self.session = session
        self.gestureTranslator = GestureTranslator(inputManager: self)
    }

    /// 解除绑定
    func unbind() {
        self.session = nil
        self.gestureTranslator = nil
    }

    // MARK: - 鼠标事件

    /// 移动鼠标到指定位置
    func moveCursor(to point: CGPoint) {
        let now = Date()
        guard now.timeIntervalSince(lastMoveTime) >= moveThrottleInterval else { return }
        lastMoveTime = now

        cursorPosition = point
        session?.sendMouseMove(x: Int(point.x), y: Int(point.y))
    }

    /// 鼠标左键单击
    func leftClick(at point: CGPoint) {
        cursorPosition = point
        session?.sendMouseClick(button: .left, x: Int(point.x), y: Int(point.y))
    }

    /// 鼠标左键双击
    func leftDoubleClick(at point: CGPoint) {
        cursorPosition = point
        session?.sendMouseClick(button: .left, x: Int(point.x), y: Int(point.y))
        session?.sendMouseClick(button: .left, x: Int(point.x), y: Int(point.y))
    }

    /// 鼠标右键单击
    func rightClick(at point: CGPoint) {
        cursorPosition = point
        session?.sendMouseClick(button: .right, x: Int(point.x), y: Int(point.y))
    }

    /// 开始拖拽
    func beginDrag(at point: CGPoint) {
        cursorPosition = point
        isMouseDown = true
        session?.sendMouseDown(button: .left, x: Int(point.x), y: Int(point.y))
    }

    /// 拖拽移动
    func drag(to point: CGPoint) {
        cursorPosition = point
        session?.sendMouseMove(x: Int(point.x), y: Int(point.y))
    }

    /// 结束拖拽
    func endDrag(at point: CGPoint) {
        cursorPosition = point
        isMouseDown = false
        session?.sendMouseUp(button: .left, x: Int(point.x), y: Int(point.y))
    }

    /// 滚轮滚动
    func scroll(delta: CGFloat, horizontal: Bool = false) {
        let scaledDelta = Int(delta * scrollMultiplier)
        session?.sendMouseWheel(delta: scaledDelta, horizontal: horizontal)
    }

    // MARK: - 键盘事件

    /// 处理按键事件
    func handleKeyEvent(_ keyCode: UInt16, characters: String?, modifiers: KeyModifiers, isDown: Bool) {
        guard let scanCode = keyboardMapper.scanCode(for: keyCode) else { return }

        let extended = keyboardMapper.isExtendedKey(keyCode)
        session?.sendKeyEvent(scanCode: scanCode, pressed: isDown, extended: extended)
    }

    /// 发送文本
    func sendText(_ text: String) {
        session?.sendText(text)
    }

    /// 发送特殊按键
    func sendSpecialKey(_ key: SpecialKey) {
        session?.sendSpecialKey(key)
    }

    // MARK: - 手势处理 (VisionOS)

    /// 处理眼动+捏合手势
    func handleGazePinch(at point: CGPoint, phase: GesturePhase) {
        switch phase {
        case .began:
            moveCursor(to: point)
        case .ended:
            leftClick(at: point)
        case .cancelled:
            break
        }
    }

    /// 处理眼动+双捏手势
    func handleGazeDoublePinch(at point: CGPoint) {
        leftDoubleClick(at: point)
    }

    /// 处理眼动+长捏手势
    func handleGazeLongPinch(at point: CGPoint, phase: GesturePhase) {
        switch phase {
        case .began:
            moveCursor(to: point)
        case .ended:
            rightClick(at: point)
        case .cancelled:
            break
        }
    }

    /// 处理拖拽手势
    func handleDragGesture(at point: CGPoint, phase: GesturePhase) {
        switch phase {
        case .began:
            beginDrag(at: point)
        case .ended:
            endDrag(at: point)
        case .cancelled:
            endDrag(at: point)
        }
    }

    /// 处理双指缩放手势 (映射为滚轮)
    func handlePinchGesture(scale: CGFloat, phase: GesturePhase) {
        guard phase == .ended else { return }

        let delta = (scale - 1.0) * 120
        scroll(delta: delta)
    }
}

// MARK: - 辅助类型

/// 输入模式
enum InputMode {
    case pointer      // 指针模式 (眼动控制)
    case touchpad     // 触控板模式
    case directTouch  // 直接触控模式
}

/// 手势阶段
enum GesturePhase {
    case began
    case ended
    case cancelled
}

/// 键盘修饰键
struct KeyModifiers: OptionSet {
    let rawValue: Int

    static let shift   = KeyModifiers(rawValue: 1 << 0)
    static let control = KeyModifiers(rawValue: 1 << 1)
    static let alt     = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
}
