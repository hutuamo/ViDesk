import SwiftUI
import Metal
import Network

/// 调试视图
struct DebugView: View {
    @State private var logMessages: [String] = []
    @State private var testHostname = "192.168.0.135"
    @State private var testPort = "3389"
    @State private var testUsername = "xhl"
    @State private var testPassword = ""
    @State private var testDomain = ""  // 域名（Linux 可留空或填主机名）
    @State private var connectionStatus = "未连接"

    // 安全选项 - 服务器要求 NLA，所以默认启用
    @State private var useNLA = true
    @State private var useTLS = true
    @State private var ignoreCertErrors = true

    // RDP 会话
    @State private var rdpSession: RDPSession?
    @State private var isConnecting = false

    // Ping 测试
    @State private var pingIP = "192.168.0.135"
    @State private var isPinging = false
    @State private var pingResult = ""
    @State private var pingResults: [Double] = []

    var body: some View {
        List {
            Section("RDP 连接测试") {
                TextField("主机地址", text: $testHostname)
                TextField("端口", text: $testPort)
                TextField("用户名", text: $testUsername)
                SecureField("密码", text: $testPassword)
                TextField("域名 (Linux 可留空)", text: $testDomain)

                Toggle("使用 NLA (服务器要求)", isOn: $useNLA)
                Toggle("使用 TLS", isOn: $useTLS)
                Toggle("忽略证书错误", isOn: $ignoreCertErrors)

                HStack {
                    Text("状态:")
                    Text(connectionStatus)
                        .foregroundStyle(connectionStatusColor)
                }

                HStack {
                    Button("RDP 连接") {
                        testRDPConnection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConnecting || testHostname.isEmpty || testUsername.isEmpty)

                    if rdpSession != nil {
                        Button("断开") {
                            disconnectRDP()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section("TCP 测试") {
                Button("测试 TCP 连接") {
                    testTCPConnection()
                }
                .buttonStyle(.bordered)
            }

            Section("Ping 测试") {
                TextField("IP 地址", text: $pingIP)
                    .keyboardType(.decimalPad)
                    .textContentType(.none)
                    .autocorrectionDisabled()

                HStack {
                    Button(isPinging ? "测试中..." : "开始 Ping") {
                        startPingTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPinging || pingIP.isEmpty)

                    if !pingResults.isEmpty {
                        Button("清除结果") {
                            pingResults.removeAll()
                            pingResult = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if !pingResult.isEmpty {
                    HStack {
                        Text("结果:")
                        Text(pingResult)
                            .foregroundStyle(pingResult.contains("成功") ? .green : .red)
                    }
                }

                if !pingResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(pingResults.enumerated()), id: \.offset) { index, latency in
                            Text("Ping \(index + 1): \(String(format: "%.1f", latency)) ms")
                                .font(.caption.monospaced())
                                .foregroundStyle(.green)
                        }

                        let avg = pingResults.reduce(0, +) / Double(pingResults.count)
                        Text("平均: \(String(format: "%.1f", avg)) ms")
                            .font(.caption.monospaced())
                            .fontWeight(.semibold)
                    }
                }
            }

            Section("日志") {
                if logMessages.isEmpty {
                    Text("暂无日志")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(logMessages.enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .font(.caption.monospaced())
                    }
                }

                Button("清除日志") {
                    logMessages.removeAll()
                }
            }

            Section("系统信息") {
                LabeledContent("设备") {
                    #if os(visionOS)
                    Text("Apple Vision Pro")
                    #else
                    Text("iOS 设备")
                    #endif
                }

                LabeledContent("Metal 支持") {
                    if MTLCreateSystemDefaultDevice() != nil {
                        Text("可用")
                            .foregroundStyle(.green)
                    } else {
                        Text("不可用")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("调试")
    }

    private var connectionStatusColor: Color {
        switch connectionStatus {
        case "已连接":
            return .green
        case "连接中...":
            return .orange
        case let s where s.contains("失败") || s.contains("错误"):
            return .red
        default:
            return .secondary
        }
    }

    // MARK: - RDP 连接测试

    private func testRDPConnection() {
        guard !testHostname.isEmpty, !testUsername.isEmpty else { return }

        isConnecting = true
        connectionStatus = "连接中..."
        addLog("开始 RDP 连接: \(testHostname):\(testPort)")
        addLog("用户: \(testUsername), NLA=\(useNLA), TLS=\(useTLS)")

        Task {
            let session = RDPSession()
            rdpSession = session

            let port = Int(testPort) ?? 3389
            let config = ConnectionConfig(
                name: "调试连接",
                hostname: testHostname,
                port: port,
                username: testUsername,
                domain: testDomain.isEmpty ? nil : testDomain,
                useNLA: useNLA,
                useTLS: useTLS,
                ignoreCertificateErrors: ignoreCertErrors
            )

            do {
                try await session.connect(config: config, password: testPassword)
                await MainActor.run {
                    connectionStatus = "已连接"
                    addLog("RDP 连接成功!")
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = "连接失败"
                    addLog("RDP 连接失败: \(error.localizedDescription)")
                    isConnecting = false
                    rdpSession = nil
                }
            }
        }
    }

    private func disconnectRDP() {
        rdpSession?.disconnect()
        rdpSession = nil
        connectionStatus = "已断开"
        addLog("RDP 已断开")
    }

    // MARK: - TCP 连接测试

    private struct TCPTestResult {
        let success: Bool
        let latency: Double?
        let error: String?
    }

    private func testTCPConnection() {
        connectionStatus = "测试 TCP..."
        addLog("开始 TCP 测试: \(testHostname):\(testPort)")

        Task {
            let port = Int(testPort) ?? 3389
            let result = await checkTCPConnection(host: testHostname, port: port)

            await MainActor.run {
                if result.success, let latency = result.latency {
                    connectionStatus = "TCP 可达"
                    addLog("TCP 连接成功, 延迟: \(String(format: "%.1f", latency)) ms")
                } else {
                    connectionStatus = "TCP 不可达"
                    addLog("TCP 连接失败: \(result.error ?? "未知错误")")
                }
            }
        }
    }

    private func checkTCPConnection(host: String, port: Int) async -> TCPTestResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                continuation.resume(returning: TCPTestResult(success: false, latency: nil, error: "无效端口"))
                return
            }

            let connection = NWConnection(host: host, port: nwPort, using: .tcp)

            var completed = false
            var waitingError: String?

            let timeout = DispatchWorkItem {
                if !completed {
                    completed = true
                    connection.cancel()
                    let errorMsg = waitingError ?? "连接超时 (5秒)"
                    continuation.resume(returning: TCPTestResult(success: false, latency: nil, error: errorMsg))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)

            connection.stateUpdateHandler = { state in
                guard !completed else { return }

                switch state {
                case .ready:
                    completed = true
                    timeout.cancel()
                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                    connection.cancel()
                    continuation.resume(returning: TCPTestResult(success: true, latency: elapsed, error: nil))

                case .waiting(let error):
                    waitingError = error.localizedDescription

                case .failed(let error):
                    completed = true
                    timeout.cancel()
                    connection.cancel()
                    continuation.resume(returning: TCPTestResult(success: false, latency: nil, error: error.localizedDescription))

                case .cancelled:
                    break

                default:
                    break
                }
            }

            connection.start(queue: .main)
        }
    }

    // MARK: - Ping 测试

    private func startPingTest() {
        guard !pingIP.isEmpty else { return }

        isPinging = true
        pingResults.removeAll()
        pingResult = "测试中..."
        addLog("开始 Ping 测试: \(pingIP)")

        Task {
            var successCount = 0
            let pingCount = 4

            for i in 1...pingCount {
                let result = await performSinglePing(host: pingIP)

                await MainActor.run {
                    if let latency = result {
                        pingResults.append(latency)
                        successCount += 1
                        addLog("Ping \(i): \(String(format: "%.1f", latency)) ms")
                    } else {
                        addLog("Ping \(i): 超时")
                    }
                }

                if i < pingCount {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }

            await MainActor.run {
                if successCount > 0 {
                    let avg = pingResults.reduce(0, +) / Double(pingResults.count)
                    pingResult = "成功 (\(successCount)/\(pingCount)), 平均 \(String(format: "%.1f", avg)) ms"
                    addLog("Ping 完成: \(pingResult)")
                } else {
                    pingResult = "失败 - 主机不可达"
                    addLog("Ping 失败: 主机不可达")
                }
                isPinging = false
            }
        }
    }

    private func performSinglePing(host: String) async -> Double? {
        let startTime = CFAbsoluteTimeGetCurrent()

        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(host)
            let port = NWEndpoint.Port(rawValue: 7) ?? .any
            let connection = NWConnection(host: host, port: port, using: .tcp)

            var completed = false
            let timeout = DispatchWorkItem {
                if !completed {
                    completed = true
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)

            connection.stateUpdateHandler = { state in
                guard !completed else { return }

                switch state {
                case .ready:
                    completed = true
                    timeout.cancel()
                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                    connection.cancel()
                    continuation.resume(returning: elapsed)

                case .waiting(let error):
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        completed = true
                        timeout.cancel()
                        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                        connection.cancel()
                        continuation.resume(returning: elapsed)
                    }

                case .failed:
                    completed = true
                    timeout.cancel()
                    connection.cancel()
                    continuation.resume(returning: nil)

                default:
                    break
                }
            }

            connection.start(queue: .main)
        }
    }

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logMessages.insert("[\(timestamp)] \(message)", at: 0)
        // 限制日志数量
        if logMessages.count > 100 {
            logMessages.removeLast()
        }
    }
}

#Preview {
    NavigationStack {
        DebugView()
    }
}
