import Foundation

/// 剪贴板通道
/// 负责本地和远程剪贴板的同步
final class ClipboardChannel: @unchecked Sendable {
    private weak var context: FreeRDPContext?
    private var isEnabled: Bool = true

    /// 支持的剪贴板格式
    enum ClipboardFormat {
        case text
        case unicodeText
        case html
        case rtf
        case image
        case fileList
    }

    init(context: FreeRDPContext) {
        self.context = context
    }

    // MARK: - 公共方法

    /// 启用/禁用剪贴板同步
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// 发送文本到远程剪贴板
    func sendText(_ text: String) -> Bool {
        guard isEnabled, let context = context else { return false }
        return context.setClipboardText(text)
    }

    /// 从远程获取文本
    func getText() -> String? {
        guard isEnabled, let context = context else { return nil }
        return context.getClipboardText()
    }

    /// 发送 HTML 到远程剪贴板
    func sendHTML(_ html: String) -> Bool {
        // TODO: 实现 HTML 格式支持
        return false
    }

    /// 发送图片到远程剪贴板
    func sendImage(_ imageData: Data) -> Bool {
        // TODO: 实现图片格式支持
        return false
    }

    // MARK: - 本地剪贴板操作

    #if os(iOS) || os(visionOS)
    import UIKit

    /// 从本地剪贴板获取文本
    func getLocalText() -> String? {
        return UIPasteboard.general.string
    }

    /// 设置本地剪贴板文本
    func setLocalText(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// 同步本地剪贴板到远程
    func syncLocalToRemote() -> Bool {
        guard let text = getLocalText() else { return false }
        return sendText(text)
    }

    /// 同步远程剪贴板到本地
    func syncRemoteToLocal() -> Bool {
        guard let text = getText() else { return false }
        setLocalText(text)
        return true
    }
    #endif
}

/// 剪贴板变化监听器
final class ClipboardMonitor {
    private var lastContent: String?
    private var timer: Timer?
    private let checkInterval: TimeInterval = 1.0

    var onClipboardChanged: ((String) -> Void)?

    func startMonitoring() {
        #if os(iOS) || os(visionOS)
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        #endif
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    #if os(iOS) || os(visionOS)
    private func checkClipboard() {
        guard let currentContent = UIPasteboard.general.string else { return }

        if currentContent != lastContent {
            lastContent = currentContent
            onClipboardChanged?(currentContent)
        }
    }
    #endif
}
