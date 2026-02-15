import SwiftUI

/// 远程桌面视图
struct RemoteDesktopView: View {
    @State private var viewModel: RemoteDesktopViewModel

    let config: ConnectionConfig
    let password: String?
    let onDismiss: () -> Void

    init(config: ConnectionConfig, password: String?, onDismiss: @escaping () -> Void = {}) {
        self.config = config
        self.password = password
        self.onDismiss = onDismiss
        self._viewModel = State(initialValue: RemoteDesktopViewModel())
    }

    var body: some View {
        Group {
            // 错误状态 - 显示错误界面
            if let error = viewModel.errorMessage {
                errorView(message: error)
            }
            // 正常状态
            else {
                ZStack {
                    // 桌面画布
                    DesktopCanvasView(
                        session: viewModel.session,
                        inputManager: viewModel.inputManager,
                        scaleMode: viewModel.scaleMode
                    )
                    .ignoresSafeArea()
                    .zIndex(0)

                    // 连接中覆盖层
                    if viewModel.isConnecting {
                        connectingOverlay
                            .zIndex(1)
                    }

                    // 工具栏 (使用 VisionOS Ornament 风格)
                    if viewModel.showToolbar && viewModel.isConnected {
                        VStack {
                            Spacer()
                            SessionToolbarView(viewModel: viewModel)
                                .padding(.bottom, 20)
                        }
                        .allowsHitTesting(true)
                        .zIndex(2)
                    }

                    // 虚拟键盘面板
                    if viewModel.showVirtualKeyboard {
                        VStack {
                            Spacer()
                            VirtualKeyboardPanel(viewModel: viewModel)
                                .padding(.bottom, viewModel.showToolbar ? 80 : 20)
                        }
                        .allowsHitTesting(true)
                        .transition(.move(edge: .bottom))
                        .zIndex(3)
                    }
                }
            }
        }
        .navigationBarHidden(viewModel.isFullscreen)
        .toolbar {
            if !viewModel.isFullscreen && viewModel.errorMessage == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("断开") {
                        viewModel.disconnect()
                        onDismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    connectionStatusView
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            viewModel.toggleFullscreen()
                        } label: {
                            Label(viewModel.isFullscreen ? "退出全屏" : "全屏",
                                  systemImage: viewModel.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        }

                        Picker("缩放", selection: Binding(
                            get: { viewModel.scaleMode },
                            set: { viewModel.setScaleMode($0) }
                        )) {
                            ForEach(ScaleMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.connect(config: config, password: password)
            }
        }
        .onDisappear {
            viewModel.disconnect()
        }
        .gesture(
            TapGesture(count: 3)
                .onEnded {
                    viewModel.toggleToolbar()
                }
        )
    }

    // MARK: - 连接状态视图

    private var connectionStatusView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(config.displayTitle)
                .font(.subheadline)

            if viewModel.isConnected {
                Text(viewModel.statistics.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.sessionState {
        case .connected:
            return .green
        case .connecting, .authenticating, .reconnecting:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .gray
        }
    }

    // MARK: - 覆盖层

    private var connectingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(viewModel.sessionState.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(config.fullAddress)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                Button("取消") {
                    viewModel.disconnect()
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)

            Text("连接失败")
                .font(.title2)
                .fontWeight(.semibold)

            Text("连接失败: " + message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 20) {
                Button(action: {
                    viewModel.disconnect()
                    onDismiss()
                }) {
                    Text("返回")
                        .frame(width: 100)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: {
                    viewModel.clearError()
                    Task {
                        await viewModel.reconnect()
                    }
                }) {
                    Text("重试")
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - 虚拟键盘面板

struct VirtualKeyboardPanel: View {
    let viewModel: RemoteDesktopViewModel

    private let specialKeys: [[SpecialKey]] = [
        [.escape, .windowsKey, .altTab, .altF4],
        [.ctrlAltDel, .ctrlC, .ctrlV, .ctrlZ],
        [.ctrlA, .printScreen]
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<specialKeys.count, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(specialKeys[rowIndex], id: \.displayName) { key in
                        Button {
                            viewModel.sendSpecialKey(key)
                        } label: {
                            Text(key.displayName)
                                .font(.caption)
                                .frame(minWidth: 60, minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        }
    }
}

#Preview {
    NavigationStack {
        RemoteDesktopView(
            config: .preview,
            password: nil,
            onDismiss: {}
        )
    }
}
