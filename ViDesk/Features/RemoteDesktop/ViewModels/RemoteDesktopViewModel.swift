import Foundation
import Combine
import SwiftUI

/// 远程桌面 ViewModel
@MainActor
@Observable
final class RemoteDesktopViewModel {
    // MARK: - 可观察属性

    /// 会话状态
    var sessionState: SessionState {
        session.state
    }

    /// 会话统计
    var statistics: SessionStatistics {
        session.statistics
    }

    /// 是否显示虚拟键盘
    var showVirtualKeyboard: Bool = false

    /// 是否显示工具栏
    var showToolbar: Bool = true

    /// 是否全屏模式
    var isFullscreen: Bool = false

    /// 当前缩放模式
    var scaleMode: ScaleMode = .fit

    /// 错误信息
    var errorMessage: String?

    /// 是否正在连接
    var isConnecting: Bool {
        if case .connecting = sessionState { return true }
        if case .authenticating = sessionState { return true }
        return false
    }

    /// 是否已连接
    var isConnected: Bool {
        sessionState == .connected
    }

    // MARK: - 私有属性

    private(set) var session: RDPSession
    private(set) var inputManager: InputManager
    private var config: ConnectionConfig?
    private var password: String?

    // MARK: - 初始化

    init() {
        self.session = RDPSession()
        self.inputManager = InputManager()
        self.inputManager.bind(to: session)
    }

    // MARK: - 连接操作

    /// 连接到远程桌面
    func connect(config: ConnectionConfig, password: String?) async {
        self.config = config
        self.password = password
        errorMessage = nil

        do {
            try await session.connect(config: config, password: password)
        } catch let error as RDPError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 断开连接
    func disconnect() {
        session.disconnect()
        inputManager.unbind()
    }

    /// 清除错误消息
    func clearError() {
        errorMessage = nil
    }

    /// 重新连接
    func reconnect() async {
        guard let config = config else { return }

        // 保存当前密码到 session，然后使用 session 的 reconnect 方法
        // 这样可以利用 session 内部保存的密码
        do {
            // 如果 session 还没有密码，先设置
            if password != nil {
                // 通过重新连接来传递密码
                session.disconnect()
                try await session.connect(config: config, password: password)
            } else {
                // 使用 session 内部保存的密码重连
                try await session.reconnect()
            }
            errorMessage = nil
        } catch let error as RDPError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 输入操作

    /// 发送特殊按键
    func sendSpecialKey(_ key: SpecialKey) {
        inputManager.sendSpecialKey(key)
    }

    /// 发送文本
    func sendText(_ text: String) {
        inputManager.sendText(text)
    }

    /// 同步剪贴板
    func syncClipboard(_ text: String) {
        session.syncClipboardToRemote(text)
    }

    /// 获取远程剪贴板
    func getRemoteClipboard() -> String? {
        session.getRemoteClipboard()
    }

    // MARK: - UI 操作

    /// 切换虚拟键盘
    func toggleVirtualKeyboard() {
        showVirtualKeyboard.toggle()
    }

    /// 切换工具栏
    func toggleToolbar() {
        withAnimation {
            showToolbar.toggle()
        }
    }

    /// 切换全屏
    func toggleFullscreen() {
        withAnimation {
            isFullscreen.toggle()
            showToolbar = !isFullscreen
        }
    }

    /// 设置缩放模式
    func setScaleMode(_ mode: ScaleMode) {
        scaleMode = mode
    }
}
