import Foundation

/// FreeRDP C 库的 Swift 封装
/// 负责管理 FreeRDP 上下文生命周期，将 C 回调转换为 Swift async/await
@MainActor
final class FreeRDPContext: @unchecked Sendable {
    private var context: UnsafeMutablePointer<ViDeskContext>?
    private var callbacks: ViDeskCallbacks
    private var callbackContext: UnsafeMutableRawPointer?

    // 回调闭包
    private var onFrameUpdate: ((CGRect) -> Void)?
    private var onStateChange: ((ConnectionState) -> Void)?
    private var onAuthenticationRequired: (() async -> Credentials?)?
    private var onCertificateVerify: ((CertificateInfo) async -> Bool)?

    /// 连接状态 (从 C 层映射)
    enum ConnectionState: Int {
        case disconnected = 0
        case connecting = 1
        case authenticating = 2
        case connected = 3
        case reconnecting = 4
        case error = 5
    }

    /// 用户凭证
    struct Credentials {
        let username: String
        let password: String
        let domain: String?
    }

    /// 证书信息
    struct CertificateInfo {
        let commonName: String
        let subject: String
        let issuer: String
        let fingerprint: String
        let hostMismatch: Bool
    }

    init() {
        self.callbacks = ViDeskCallbacks()
    }

    deinit {
        // deinit 是非隔离的，直接清理资源
        if let ctx = context {
            viDesk_destroyContext(ctx)
        }
        if let callbackCtx = callbackContext {
            Unmanaged<FreeRDPContext>.fromOpaque(callbackCtx).release()
        }
    }

    /// 创建上下文
    func create() -> Bool {
        guard context == nil else { return true }

        context = viDesk_createContext()
        guard context != nil else { return false }

        setupCallbacks()
        return true
    }

    /// 销毁上下文
    func destroy() {
        if let ctx = context {
            viDesk_destroyContext(ctx)
            context = nil
        }

        if let callbackCtx = callbackContext {
            Unmanaged<FreeRDPContext>.fromOpaque(callbackCtx).release()
            callbackContext = nil
        }
    }

    /// 设置帧更新回调
    func setFrameUpdateHandler(_ handler: @escaping (CGRect) -> Void) {
        onFrameUpdate = handler
    }

    /// 设置状态变化回调
    func setStateChangeHandler(_ handler: @escaping (ConnectionState) -> Void) {
        onStateChange = handler
    }

    /// 设置认证回调
    func setAuthenticationHandler(_ handler: @escaping () async -> Credentials?) {
        onAuthenticationRequired = handler
    }

    /// 设置证书验证回调
    func setCertificateVerifyHandler(_ handler: @escaping (CertificateInfo) async -> Bool) {
        onCertificateVerify = handler
    }

    /// 暴露原始上下文指针，用于后台线程事件处理
    var rawContextPointer: UnsafeMutablePointer<ViDeskContext>? {
        context
    }

    // MARK: - 配置

    /// 设置服务器
    func setServer(hostname: String, port: Int) -> Bool {
        guard let ctx = context else { return false }
        return hostname.withCString { hostnamePtr in
            viDesk_setServer(ctx, hostnamePtr, Int32(port))
        }
    }

    /// 设置凭证
    func setCredentials(username: String, password: String, domain: String? = nil) -> Bool {
        guard let ctx = context else { return false }

        let result = username.withCString { usernamePtr in
            password.withCString { passwordPtr in
                if let domain = domain {
                    return domain.withCString { domainPtr in
                        viDesk_setCredentials(ctx, usernamePtr, passwordPtr, domainPtr)
                    }
                } else {
                    return viDesk_setCredentials(ctx, usernamePtr, passwordPtr, nil)
                }
            }
        }
        return result
    }

    /// 设置显示参数
    func setDisplay(width: Int, height: Int, colorDepth: Int) -> Bool {
        guard let ctx = context else { return false }
        return viDesk_setDisplay(ctx, Int32(width), Int32(height), Int32(colorDepth))
    }

    /// 设置性能选项
    func setPerformanceFlags(
        enableWallpaper: Bool = false,
        enableFullWindowDrag: Bool = false,
        enableMenuAnimations: Bool = false,
        enableThemes: Bool = true,
        enableFontSmoothing: Bool = true
    ) -> Bool {
        guard let ctx = context else { return false }
        return viDesk_setPerformanceFlags(ctx, enableWallpaper, enableFullWindowDrag,
                                          enableMenuAnimations, enableThemes, enableFontSmoothing)
    }

    /// 设置安全选项
    func setSecurity(useNLA: Bool = true, useTLS: Bool = true, ignoreCertErrors: Bool = false) -> Bool {
        guard let ctx = context else { return false }
        return viDesk_setSecurity(ctx, useNLA, useTLS, ignoreCertErrors)
    }

    /// 设置网关
    func setGateway(hostname: String, port: Int = 443,
                    username: String? = nil, password: String? = nil, domain: String? = nil) -> Bool {
        guard let ctx = context else { return false }

        return hostname.withCString { hostnamePtr in
            let usernamePtr = username?.withCString { $0 }
            let passwordPtr = password?.withCString { $0 }
            let domainPtr = domain?.withCString { $0 }

            return viDesk_setGateway(ctx, hostnamePtr, Int32(port),
                                     usernamePtr, passwordPtr, domainPtr)
        }
    }

    // MARK: - 连接管理

    /// 连接到远程主机（在后台线程执行，避免阻塞 UI）
    func connect() async -> Bool {
        guard let ctx = context else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = viDesk_connect(ctx)
                continuation.resume(returning: result)
            }
        }
    }

    /// 断开连接
    func disconnect() {
        guard let ctx = context else { return }
        viDesk_disconnect(ctx)
    }

    /// 检查是否已连接
    var isConnected: Bool {
        guard let ctx = context else { return false }
        return viDesk_isConnected(ctx)
    }

    /// 处理事件 (在后台线程调用)
    func processEvents(timeout: Int = 100) -> Bool {
        guard let ctx = context else { return false }
        return viDesk_processEvents(ctx, Int32(timeout))
    }

    // MARK: - 输入

    /// 发送鼠标移动
    func sendMouseMove(x: Int, y: Int) -> Bool {
        guard let ctx = context else { return false }
        return viDesk_sendMouseMove(ctx, Int32(x), Int32(y))
    }

    /// 发送鼠标按钮
    func sendMouseButton(_ button: MouseButton, pressed: Bool, x: Int, y: Int) -> Bool {
        guard let ctx = context else { return false }
        return viDesk_sendMouseButton(ctx, Int32(button.rawValue), pressed, Int32(x), Int32(y))
    }

    /// 发送鼠标滚轮
    func sendMouseWheel(delta: Int, horizontal: Bool = false) -> Bool {
        guard let ctx = context else { return false }
        return viDesk_sendMouseWheel(ctx, Int32(delta), horizontal)
    }

    /// 发送键盘扫描码
    func sendKeyEvent(scanCode: UInt16, pressed: Bool, extended: Bool = false) -> Bool {
        guard let ctx = context else { return false }
        return viDesk_sendKeyEvent(ctx, scanCode, pressed, extended)
    }

    /// 发送 Unicode 字符
    func sendUnicodeKey(_ codePoint: UInt16) -> Bool {
        guard let ctx = context else { return false }
        return viDesk_sendUnicodeKey(ctx, codePoint)
    }

    // MARK: - 剪贴板

    /// 设置剪贴板文本
    func setClipboardText(_ text: String) -> Bool {
        guard let ctx = context else { return false }
        return text.withCString { textPtr in
            viDesk_setClipboardText(ctx, textPtr)
        }
    }

    /// 获取剪贴板文本
    func getClipboardText() -> String? {
        guard let ctx = context else { return nil }
        guard let cString = viDesk_getClipboardText(ctx) else { return nil }
        let result = String(cString: cString)
        viDesk_freeString(cString)
        return result
    }

    // MARK: - 帧缓冲区

    /// 获取帧缓冲区
    var frameBuffer: UnsafePointer<UInt8>? {
        guard let ctx = context else { return nil }
        return viDesk_getFrameBuffer(ctx)
    }

    /// 获取帧尺寸
    var frameSize: CGSize {
        guard let ctx = context else { return .zero }
        var width: UInt32 = 0
        var height: UInt32 = 0
        viDesk_getFrameSize(ctx, &width, &height)
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    /// 获取每像素字节数
    var bytesPerPixel: Int {
        guard let ctx = context else { return 4 }
        return Int(viDesk_getFrameBytesPerPixel(ctx))
    }

    /// 获取最后错误
    var lastError: String? {
        guard let ctx = context else { return nil }
        guard let cString = viDesk_getLastError(ctx) else { return nil }
        return String(cString: cString)
    }

    // MARK: - 私有方法

    private func setupCallbacks() {
        guard let ctx = context else { return }

        // 保持对 self 的引用
        callbackContext = Unmanaged.passRetained(self).toOpaque()

        callbacks.onFrameUpdate = { (context, x, y, width, height) in
            guard let context = context else { return }
            let wrapper = Unmanaged<FreeRDPContext>.fromOpaque(context).takeUnretainedValue()
            let rect = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
            Task { @MainActor in
                wrapper.onFrameUpdate?(rect)
            }
        }

        callbacks.onConnectionStateChanged = { (context, state, message) in
            guard let context = context else { return }
            let wrapper = Unmanaged<FreeRDPContext>.fromOpaque(context).takeUnretainedValue()
            let connectionState = ConnectionState(rawValue: Int(state)) ?? .error
            Task { @MainActor in
                wrapper.onStateChange?(connectionState)
            }
        }

        // 设置认证回调 - 当 FreeRDP 需要认证时调用
        // 如果凭证已经在 setCredentials 中设置，这里只需要返回 TRUE
        // 如果需要动态获取凭证（例如从 Keychain），可以在这里实现
        callbacks.onAuthenticate = { (context, username, password, domain) in
            guard let context = context else { return false }
            let wrapper = Unmanaged<FreeRDPContext>.fromOpaque(context).takeUnretainedValue()            
            // 如果设置了认证处理器，调用它获取凭证
            if let handler = wrapper.onAuthenticationRequired {
                // 注意：这里不能直接使用 async/await，因为 C 回调是同步的
                // 所以我们需要使用已设置的凭证，或者使用同步方式获取
                // 对于当前实现，凭证应该已经在 setCredentials 中设置好了
                // 所以这里只需要返回 TRUE 表示使用已设置的凭证
            }
            
            // 返回 TRUE 表示使用已经在 settings 中设置的凭证
            // FreeRDP 会在 settings 中查找凭证
            return true
        }

        viDesk_setCallbacks(ctx, callbacks, callbackContext)
    }
}

/// 鼠标按钮类型
enum MouseButton: Int {
    case left = 0
    case right = 1
    case middle = 2
}
