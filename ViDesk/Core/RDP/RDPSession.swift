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
    private var savedPassword: String?  // 保存密码用于重连
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

        vLog("connect() 开始 - 主机: \(config.hostname):\(config.port), 用户: \(config.username)")
        vLog("  密码长度: \(password?.count ?? 0), NLA: \(config.useNLA), TLS: \(config.useTLS)")
        vLog("  显示: \(config.displaySettings.width)x\(config.displaySettings.height), 色深: \(config.displaySettings.colorDepth.rawValue)")

        self.config = config
        self.savedPassword = password
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
        // 注意：不断开 savedPassword，以便重连时使用
    }

    /// 重新连接
    func reconnect() async throws {
        guard let config = config else {
            throw RDPError.connectionFailed("无连接配置")
        }

        disconnect()
        vLog("reconnect() 使用保存的密码，长度: \(savedPassword?.count ?? 0)")
        try await connect(config: config, password: savedPassword)
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
        vLog("performConnect() 开始 - 密码长度: \(password?.count ?? 0)")
        state = .connecting

        vLog("  创建 FreeRDP 上下文...")
        guard context.create() else {
            vLog("  [失败] 无法创建 RDP 上下文")
            state = .error(.connectionFailed("无法创建 RDP 上下文"))
            throw RDPError.connectionFailed("无法创建 RDP 上下文")
        }
        vLog("  [成功] FreeRDP 上下文已创建")

        guard let config = config else {
            vLog("  [失败] 无效的连接配置")
            state = .error(.connectionFailed("无效的连接配置"))
            throw RDPError.connectionFailed("无效的连接配置")
        }

        vLog("  设置服务器: \(config.hostname):\(config.port)")
        guard context.setServer(hostname: config.hostname, port: config.port) else {
            vLog("  [失败] 无法设置服务器地址")
            throw RDPError.connectionFailed("无法设置服务器地址")
        }

        if !config.username.isEmpty {
            let finalPassword = password ?? ""
            vLog("  设置凭证: 用户=\(config.username), 密码长度=\(finalPassword.count), 域=\(config.domain ?? "nil")")
            guard context.setCredentials(username: config.username,
                                         password: finalPassword,
                                         domain: config.domain) else {
                vLog("  [失败] 无法设置凭证")
                throw RDPError.connectionFailed("无法设置凭证")
            }
        } else {
            vLog("  跳过凭证设置 (用户名为空)")
        }

        let displaySettings = config.displaySettings
        vLog("  设置显示: \(displaySettings.width)x\(displaySettings.height), 色深=\(displaySettings.colorDepth.rawValue)")
        guard context.setDisplay(width: displaySettings.width,
                                 height: displaySettings.height,
                                 colorDepth: displaySettings.colorDepth.rawValue) else {
            vLog("  [失败] 无法设置显示参数")
            throw RDPError.connectionFailed("无法设置显示参数")
        }

        vLog("  设置安全: NLA=\(config.useNLA), TLS=\(config.useTLS), 忽略证书=\(config.ignoreCertificateErrors)")
        guard context.setSecurity(useNLA: config.useNLA,
                                  useTLS: config.useTLS,
                                  ignoreCertErrors: config.ignoreCertificateErrors) else {
            vLog("  [失败] 无法设置安全选项")
            throw RDPError.connectionFailed("无法设置安全选项")
        }

        if let gateway = config.gatewayHostname, !gateway.isEmpty {
            vLog("  设置网关: \(gateway)")
            _ = context.setGateway(hostname: gateway)
        }

        vLog("  开始执行连接...")
        state = .authenticating
        let connected = await context.connect()
        if connected {
            vLog("  [成功] 连接已建立!")
            connectionStartTime = Date()
            initializeFrameBuffer()
            vLog("  帧缓冲区: \(frameBuffer?.width ?? 0)x\(frameBuffer?.height ?? 0)")
            startEventLoop()
            startStatisticsTimer()
            state = .connected
        } else {
            let errorMessage = context.lastError ?? "未知错误"
            vLog("  [失败] 连接失败: \(errorMessage)")
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
        vLog("状态变更: \(connectionState)")
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
            vLog("状态变更 -> 错误: \(errorMessage)")
            state = .error(.connectionFailed(errorMessage))
        }
    }

    private func handleDisconnection() {
        vLog("handleDisconnection() - autoReconnect: \(config?.autoReconnect ?? false), attempt: \(reconnectAttempt)/\(maxReconnectAttempts)")
        stopEventLoop()
        stopStatisticsTimer()

        guard let config = config, config.autoReconnect,
              reconnectAttempt < maxReconnectAttempts else {
            vLog("  不再重连，设为 disconnected")
            state = .disconnected
            return
        }

        Task {
            reconnectAttempt += 1
            vLog("  自动重连 #\(reconnectAttempt), savedPassword长度: \(savedPassword?.count ?? 0)")
            state = .reconnecting(attempt: reconnectAttempt)

            context.disconnect()
            context.destroy()

            try? await Task.sleep(for: .seconds(reconnectDelay))
            try? await performConnect(password: savedPassword)
        }
    }

    private func startEventLoop() {
        let rawCtx = context.rawContextPointer
        eventLoopTask = Task.detached(priority: .high) {
            while !Task.isCancelled {
                guard let rawCtx = rawCtx else { break }
                let success = viDesk_processEvents(rawCtx, 16)
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
