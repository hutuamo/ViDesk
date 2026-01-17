import SwiftUI

/// 远程桌面视图
struct RemoteDesktopView: View {
    @State private var viewModel: RemoteDesktopViewModel
    @Environment(\.dismiss) private var dismiss

    let config: ConnectionConfig
    let password: String?

    init(config: ConnectionConfig, password: String?) {
        self.config = config
        self.password = password
        self._viewModel = State(initialValue: RemoteDesktopViewModel())
    }

    var body: some View {
        ZStack {
            // 桌面画布
            DesktopCanvasView(
                session: viewModel.session,
                inputManager: viewModel.inputManager,
                scaleMode: viewModel.scaleMode
            )
            .ignoresSafeArea()

            // 连接中覆盖层
            if viewModel.isConnecting {
                connectingOverlay
            }

            // 错误覆盖层
            if let error = viewModel.errorMessage {
                errorOverlay(message: error)
            }

            // 工具栏 (使用 VisionOS Ornament 风格)
            if viewModel.showToolbar && viewModel.isConnected {
                VStack {
                    Spacer()
                    SessionToolbarView(viewModel: viewModel)
                        .padding(.bottom, 20)
                }
            }

            // 虚拟键盘面板
            if viewModel.showVirtualKeyboard {
                VStack {
                    Spacer()
                    VirtualKeyboardPanel(viewModel: viewModel)
                        .padding(.bottom, viewModel.showToolbar ? 80 : 20)
                }
                .transition(.move(edge: .bottom))
            }
        }
        .navigationBarHidden(viewModel.isFullscreen)
        .toolbar {
            if !viewModel.isFullscreen {
                ToolbarItem(placement: .cancellationAction) {
                    Button("断开") {
                        viewModel.disconnect()
                        dismiss()
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
                    dismiss()
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
        }
    }

    private func errorOverlay(message: String) -> some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.yellow)

                Text("连接失败")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HStack(spacing: 16) {
                    Button("返回") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("重试") {
                        Task {
                            await viewModel.reconnect()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top)
            }
        }
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
                                .frame(minWidth: 60)
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
            password: nil
        )
    }
}
