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

        self.config = config
        self.savedPassword = password  // 保存密码用于重连
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

        // 使用保存的密码重连
        disconnect()
        print("[ViDesk] reconnect 使用保存的密码，长度: \(savedPassword?.count ?? 0)")
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
        // #region agent log
        let logPath: String = {
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                return documentsPath.appendingPathComponent("debug.log").path
            }
            return "/Users/xhl/study/ai/studio/rdpclient/ViDesk/.cursor/debug.log"
        }()
        print("[ViDesk] performConnect 开始 - 密码: \(password == nil ? "nil" : (password!.isEmpty ? "空字符串" : "有值(长度:\(password!.count))"))")
        let logEntry = """
{"id":"log_\(UUID().uuidString)","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"location":"RDPSession.swift:172","message":"performConnect开始","data":{"passwordIsNil":\(password == nil),"passwordLength":\(password?.count ?? 0),"passwordIsEmpty":\(password?.isEmpty ?? true),"username":"\(config?.username ?? "")"},"sessionId":"debug-session","runId":"run1","hypothesisId":"A"}
"""
        if FileManager.default.fileExists(atPath: logPath) {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                defer { try? fileHandle.close() }
                try? fileHandle.seekToEnd()
                try? fileHandle.write(contentsOf: logEntry.data(using: .utf8) ?? Data())
            }
        } else {
            try? FileManager.default.createDirectory(atPath: "/Users/xhl/study/ai/studio/rdpclient/ViDesk/.cursor", withIntermediateDirectories: true, attributes: nil)
            try? logEntry.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
        // #endregion
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
            // #region agent log
            let finalPassword = password ?? ""
            print("[ViDesk] 准备设置凭证 - 用户名: \(config.username), 密码长度: \(finalPassword.count), 域: \(config.domain ?? "(空)")")
            let logEntry2 = """
{"id":"log_\(UUID().uuidString)","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"location":"RDPSession.swift:191","message":"设置凭证前","data":{"username":"\(config.username)","passwordLength":\(finalPassword.count),"domain":"\(config.domain ?? "")","passwordIsEmpty":\(finalPassword.isEmpty)},"sessionId":"debug-session","runId":"run1","hypothesisId":"A"}
"""
            if FileManager.default.fileExists(atPath: logPath), let fileHandle = FileHandle(forWritingAtPath: logPath) {
                defer { try? fileHandle.close() }
                try? fileHandle.seekToEnd()
                try? fileHandle.write(contentsOf: logEntry2.data(using: .utf8) ?? Data())
            } else {
                try? logEntry2.write(toFile: logPath, atomically: true, encoding: .utf8)
            }
            // #endregion
            guard context.setCredentials(username: config.username,
                                         password: finalPassword,
                                         domain: config.domain) else {
                // #region agent log
                let logEntry3 = """
{"id":"log_\(UUID().uuidString)","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"location":"RDPSession.swift:194","message":"setCredentials失败","data":{"username":"\(config.username)"},"sessionId":"debug-session","runId":"run1","hypothesisId":"A"}
"""
                if FileManager.default.fileExists(atPath: logPath), let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    defer { try? fileHandle.close() }
                    try? fileHandle.seekToEnd()
                    try? fileHandle.write(contentsOf: logEntry3.data(using: .utf8) ?? Data())
                } else {
                    try? logEntry3.write(toFile: logPath, atomically: true, encoding: .utf8)
                }
                // #endregion
                throw RDPError.connectionFailed("无法设置凭证")
            }
            // #region agent log
            let logEntry4 = """
{"id":"log_\(UUID().uuidString)","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"location":"RDPSession.swift:196","message":"setCredentials成功","data":{"username":"\(config.username)"},"sessionId":"debug-session","runId":"run1","hypothesisId":"A"}
"""
            if FileManager.default.fileExists(atPath: logPath), let fileHandle = FileHandle(forWritingAtPath: logPath) {
                defer { try? fileHandle.close() }
                try? fileHandle.seekToEnd()
                try? fileHandle.write(contentsOf: logEntry4.data(using: .utf8) ?? Data())
            } else {
                try? logEntry4.write(toFile: logPath, atomically: true, encoding: .utf8)
            }
            // #endregion
        }

        let displaySettings = config.displaySettings
        guard context.setDisplay(width: displaySettings.width,
                                 height: displaySettings.height,
                                 colorDepth: displaySettings.colorDepth.rawValue) else {
            throw RDPError.connectionFailed("无法设置显示参数")
        }

        guard context.setSecurity(useNLA: config.useNLA,
                                  useTLS: config.useTLS,
                                  ignoreCertErrors: config.ignoreCertificateErrors) else {
            throw RDPError.connectionFailed("无法设置安全选项")
        }
        // #region agent log
        let logEntry5 = """
{"id":"log_\(UUID().uuidString)","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"location":"RDPSession.swift:205","message":"安全选项设置","data":{"useNLA":\(config.useNLA),"useTLS":\(config.useTLS),"ignoreCertErrors":\(config.ignoreCertificateErrors)},"sessionId":"debug-session","runId":"run1","hypothesisId":"C"}
"""
        if FileManager.default.fileExists(atPath: logPath), let fileHandle = FileHandle(forWritingAtPath: logPath) {
            defer { try? fileHandle.close() }
            try? fileHandle.seekToEnd()
            try? fileHandle.write(contentsOf: logEntry5.data(using: .utf8) ?? Data())
        } else {
            try? logEntry5.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
        // #endregion

        // 设置网关 (如果有)
        if let gateway = config.gatewayHostname, !gateway.isEmpty {
            _ = context.setGateway(hostname: gateway)
        }

        // 执行连接
        state = .authenticating
        // #region agent log
        let logEntry6 = """
{"id":"log_\(UUID().uuidString)","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"location":"RDPSession.swift:219","message":"开始连接","data":{},"sessionId":"debug-session","runId":"run1","hypothesisId":"A"}
"""
        if FileManager.default.fileExists(atPath: logPath), let fileHandle = FileHandle(forWritingAtPath: logPath) {
            defer { try? fileHandle.close() }
            try? fileHandle.seekToEnd()
            try? fileHandle.write(contentsOf: logEntry6.data(using: .utf8) ?? Data())
        } else {
            try? logEntry6.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
        // #endregion

        let connected = await context.connect()
        // #region agent log
        let logEntry7 = """
{"id":"log_\(UUID().uuidString)","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"location":"RDPSession.swift:220","message":"连接结果","data":{"connected":\(connected),"lastError":"\(context.lastError?.replacingOccurrences(of: "\"", with: "\\\"") ?? "")"},"sessionId":"debug-session","runId":"run1","hypothesisId":"A"}
"""
        if FileManager.default.fileExists(atPath: logPath), let fileHandle = FileHandle(forWritingAtPath: logPath) {
            defer { try? fileHandle.close() }
            try? fileHandle.seekToEnd()
            try? fileHandle.write(contentsOf: logEntry7.data(using: .utf8) ?? Data())
        } else {
            try? logEntry7.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
        // #endregion
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
