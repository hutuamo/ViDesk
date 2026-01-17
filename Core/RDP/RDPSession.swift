import Foundation
import Combine
import SwiftUI

/// RDP 会话管理器
/// 负责管理 RDP 连接的完整生命周期
@MainActor
@Observable
final class RDPSession {
    // MARK: - 可观察属性

    /// 当前会话状态
    private(set) var state: SessionState = .disconnected

    /// 会话统计信息
    private(set) var statistics: SessionStatistics = SessionStatistics()

    /// 当前帧缓冲区 (用于渲染)
    private(set) var frameBuffer: FrameBuffer?

    // MARK: - 私有属性

    private let context: FreeRDPContext
    private var config: ConnectionConfig?
    private var eventLoopTask: Task<Void, Never>?
    private var statisticsTimer: Timer?
    private var connectionStartTime: Date?
    private var reconnectAttempt: Int = 0

    private let maxReconnectAttempts = 3
    private let reconnectDelay: TimeInterval = 2.0

    // MARK: - 初始化

    init() {
        self.context = FreeRDPContext()
        setupContextCallbacks()
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.cleanup()
        }
    }

    // MARK: - 公共 API

    /// 使用配置连接到远程主机
    func connect(config: ConnectionConfig, password: String? = nil) async throws {
        guard state == .disconnected || state.isActive == false else {
            throw RDPError.connectionFailed("会话已在运行中")
        }

        self.config = config
        self.reconnectAttempt = 0

        try await performConnect(password: password)
    }

    /// 断开连接
    func disconnect() {
        stopEventLoop()
        stopStatisticsTimer()
        context.disconnect()
        state = .disconnected
        connectionStartTime = nil
        frameBuffer = nil
    }

    /// 重新连接
    func reconnect() async throws {
        guard let config = config else {
            throw RDPError.connectionFailed("无连接配置")
        }

        disconnect()
        try await connect(config: config)
    }

    // MARK: - 输入 API

    /// 发送鼠标移动
    func sendMouseMove(x: Int, y: Int) {
        guard state == .connected else { return }
        _ = context.sendMouseMove(x: x, y: y)
    }

    /// 发送鼠标点击
    func sendMouseClick(button: MouseButton, x: Int, y: Int) {
        guard state == .connected else { return }
        _ = context.sendMouseButton(button, pressed: true, x: x, y: y)
        _ = context.sendMouseButton(button, pressed: false, x: x, y: y)
    }

    /// 发送鼠标按下
    func sendMouseDown(button: MouseButton, x: Int, y: Int) {
        guard state == .connected else { return }
        _ = context.sendMouseButton(button, pressed: true, x: x, y: y)
    }

    /// 发送鼠标释放
    func sendMouseUp(button: MouseButton, x: Int, y: Int) {
        guard state == .connected else { return }
        _ = context.sendMouseButton(button, pressed: false, x: x, y: y)
    }

    /// 发送鼠标滚轮
    func sendMouseWheel(delta: Int, horizontal: Bool = false) {
        guard state == .connected else { return }
        _ = context.sendMouseWheel(delta: delta, horizontal: horizontal)
    }

    /// 发送键盘事件
    func sendKeyEvent(scanCode: UInt16, pressed: Bool, extended: Bool = false) {
        guard state == .connected else { return }
        _ = context.sendKeyEvent(scanCode: scanCode, pressed: pressed, extended: extended)
    }

    /// 发送文本输入
    func sendText(_ text: String) {
        guard state == .connected else { return }
        for scalar in text.unicodeScalars {
            if scalar.value <= UInt16.max {
                _ = context.sendUnicodeKey(UInt16(scalar.value))
            }
        }
    }

    /// 发送特殊按键组合
    func sendSpecialKey(_ specialKey: SpecialKey) {
        guard state == .connected else { return }

        for (scanCode, extended) in specialKey.keyCombination {
            _ = context.sendKeyEvent(scanCode: scanCode, pressed: true, extended: extended)
        }

        for (scanCode, extended) in specialKey.keyCombination.reversed() {
            _ = context.sendKeyEvent(scanCode: scanCode, pressed: false, extended: extended)
        }
    }

    // MARK: - 剪贴板 API

    /// 同步剪贴板到远程
    func syncClipboardToRemote(_ text: String) {
        guard state == .connected else { return }
        _ = context.setClipboardText(text)
    }

    /// 从远程获取剪贴板
    func getRemoteClipboard() -> String? {
        guard state == .connected else { return nil }
        return context.getClipboardText()
    }

    // MARK: - 私有方法

    private func setupContextCallbacks() {
        context.setFrameUpdateHandler { [weak self] rect in
            Task { @MainActor in
                self?.handleFrameUpdate(rect: rect)
            }
        }

        context.setStateChangeHandler { [weak self] connectionState in
            Task { @MainActor in
                self?.handleConnectionStateChange(connectionState)
            }
        }
    }

    private func performConnect(password: String?) async throws {
        state = .connecting

        guard context.create() else {
            state = .error(.connectionFailed("无法创建 RDP 上下文"))
            throw RDPError.connectionFailed("无法创建 RDP 上下文")
        }

        guard let config = config else {
            state = .error(.connectionFailed("无效的连接配置"))
            throw RDPError.connectionFailed("无效的连接配置")
        }

        // 配置连接
        guard context.setServer(hostname: config.hostname, port: config.port) else {
            throw RDPError.connectionFailed("无法设置服务器地址")
        }

        if !config.username.isEmpty {
            guard context.setCredentials(username: config.username,
                                         password: password ?? "",
                                         domain: config.domain) else {
                throw RDPError.connectionFailed("无法设置凭证")
            }
        }

        let displaySettings = config.displaySettings
        guard context.setDisplay(width: displaySettings.width,
                                 height: displaySettings.height,
                                 colorDepth: displaySettings.colorDepth.rawValue) else {
            throw RDPError.connectionFailed("无法设置显示参数")
        }

        guard context.setSecurity(useNLA: config.useNLA,
                                  useTLS: true,
                                  ignoreCertErrors: config.ignoreCertificateErrors) else {
            throw RDPError.connectionFailed("无法设置安全选项")
        }

        // 设置网关 (如果有)
        if let gateway = config.gatewayHostname, !gateway.isEmpty {
            _ = context.setGateway(hostname: gateway)
        }

        // 执行连接
        state = .authenticating

        let connected = await context.connect()
        if connected {
            state = .connected
            connectionStartTime = Date()
            initializeFrameBuffer()
            startEventLoop()
            startStatisticsTimer()
        } else {
            let errorMessage = context.lastError ?? "未知错误"
            state = .error(.connectionFailed(errorMessage))
            throw RDPError.connectionFailed(errorMessage)
        }
    }

    private func initializeFrameBuffer() {
        let size = context.frameSize
        let bytesPerPixel = context.bytesPerPixel

        frameBuffer = FrameBuffer(
            width: Int(size.width),
            height: Int(size.height),
            bytesPerPixel: bytesPerPixel
        )
    }

    private func handleFrameUpdate(rect: CGRect) {
        guard let frameBuffer = frameBuffer,
              let sourceBuffer = context.frameBuffer else { return }

        frameBuffer.update(from: sourceBuffer, region: rect)
    }

    private func handleConnectionStateChange(_ connectionState: FreeRDPContext.ConnectionState) {
        switch connectionState {
        case .disconnected:
            handleDisconnection()
        case .connecting:
            state = .connecting
        case .authenticating:
            state = .authenticating
        case .connected:
            state = .connected
        case .reconnecting:
            reconnectAttempt += 1
            state = .reconnecting(attempt: reconnectAttempt)
        case .error:
            let errorMessage = context.lastError ?? "未知错误"
            state = .error(.connectionFailed(errorMessage))
        }
    }

    private func handleDisconnection() {
        stopEventLoop()
        stopStatisticsTimer()

        guard let config = config, config.autoReconnect,
              reconnectAttempt < maxReconnectAttempts else {
            state = .disconnected
            return
        }

        // 自动重连
        Task {
            reconnectAttempt += 1
            state = .reconnecting(attempt: reconnectAttempt)
            try? await Task.sleep(for: .seconds(reconnectDelay))
            try? await performConnect(password: nil)
        }
    }

    private func startEventLoop() {
        eventLoopTask = Task.detached(priority: .high) { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                let success = await MainActor.run {
                    self.context.processEvents(timeout: 16)
                }

                if !success {
                    break
                }

                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    private func stopEventLoop() {
        eventLoopTask?.cancel()
        eventLoopTask = nil
    }

    private func startStatisticsTimer() {
        statisticsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatistics()
            }
        }
    }

    private func stopStatisticsTimer() {
        statisticsTimer?.invalidate()
        statisticsTimer = nil
    }

    private func updateStatistics() {
        if let startTime = connectionStartTime {
            statistics.connectionDuration = Date().timeIntervalSince(startTime)
        }

        // TODO: 从 FreeRDP 获取实际统计数据
    }

    private func cleanup() {
        disconnect()
        context.destroy()
    }
}

// MARK: - 特殊按键定义

enum SpecialKey {
    case ctrlAltDel
    case altTab
    case altF4
    case windowsKey
    case escape
    case printScreen
    case ctrlC
    case ctrlV
    case ctrlA
    case ctrlZ

    var keyCombination: [(scanCode: UInt16, extended: Bool)] {
        switch self {
        case .ctrlAltDel:
            return [(0x1D, false), (0x38, false), (0x53, true)]
        case .altTab:
            return [(0x38, false), (0x0F, false)]
        case .altF4:
            return [(0x38, false), (0x3E, false)]
        case .windowsKey:
            return [(0x5B, true)]
        case .escape:
            return [(0x01, false)]
        case .printScreen:
            return [(0x37, true)]
        case .ctrlC:
            return [(0x1D, false), (0x2E, false)]
        case .ctrlV:
            return [(0x1D, false), (0x2F, false)]
        case .ctrlA:
            return [(0x1D, false), (0x1E, false)]
        case .ctrlZ:
            return [(0x1D, false), (0x2C, false)]
        }
    }

    var displayName: String {
        switch self {
        case .ctrlAltDel: return "Ctrl+Alt+Del"
        case .altTab: return "Alt+Tab"
        case .altF4: return "Alt+F4"
        case .windowsKey: return "Win"
        case .escape: return "Esc"
        case .printScreen: return "PrtSc"
        case .ctrlC: return "Ctrl+C"
        case .ctrlV: return "Ctrl+V"
        case .ctrlA: return "Ctrl+A"
        case .ctrlZ: return "Ctrl+Z"
        }
    }
}
