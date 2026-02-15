import SwiftUI

/// 会话工具栏视图
/// VisionOS 风格的 Ornament 工具栏
struct SessionToolbarView: View {
    let viewModel: RemoteDesktopViewModel

    @State private var showClipboardMenu = false
    @State private var clipboardText = ""

    var body: some View {
        HStack(spacing: 16) {
            // 键盘按钮
            ToolbarButton(
                icon: "keyboard",
                label: "键盘",
                isActive: viewModel.showVirtualKeyboard
            ) {
                withAnimation {
                    viewModel.toggleVirtualKeyboard()
                }
            }

            Divider()
                .frame(height: 24)

            // 剪贴板按钮
            ToolbarButton(icon: "doc.on.clipboard", label: "剪贴板") {
                showClipboardMenu = true
            }
            .popover(isPresented: $showClipboardMenu) {
                clipboardMenu
            }

            Divider()
                .frame(height: 24)

            // 全屏按钮
            ToolbarButton(
                icon: viewModel.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                label: viewModel.isFullscreen ? "退出全屏" : "全屏"
            ) {
                viewModel.toggleFullscreen()
            }

            Divider()
                .frame(height: 24)

            // 统计信息
            statsView

            Divider()
                .frame(height: 24)

            // 断开按钮
            ToolbarButton(icon: "xmark.circle", label: "断开", tint: .red) {
                viewModel.disconnect()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 10)
        }
    }

    // MARK: - 统计信息视图

    private var statsView: some View {
        HStack(spacing: 12) {
            // 帧率
            StatItem(icon: "speedometer", value: String(format: "%.0f", viewModel.statistics.frameRate), unit: "FPS")

            // 延迟
            StatItem(icon: "clock", value: viewModel.statistics.formattedLatency, unit: "")

            // 连接时长
            StatItem(icon: "timer", value: viewModel.statistics.formattedDuration, unit: "")
        }
    }

    // MARK: - 剪贴板菜单

    private var clipboardMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("剪贴板")
                .font(.headline)

            Divider()

            Button {
                if let text = viewModel.getRemoteClipboard() {
                    #if os(iOS) || os(visionOS)
                    UIPasteboard.general.string = text
                    #endif
                }
                showClipboardMenu = false
            } label: {
                Label("从远程复制", systemImage: "arrow.down.doc")
            }

            Button {
                #if os(iOS) || os(visionOS)
                if let text = UIPasteboard.general.string {
                    viewModel.syncClipboard(text)
                }
                #endif
                showClipboardMenu = false
            } label: {
                Label("粘贴到远程", systemImage: "arrow.up.doc")
            }

            Divider()

            TextField("输入文本", text: $clipboardText)
                .textFieldStyle(.roundedBorder)

            Button {
                if !clipboardText.isEmpty {
                    viewModel.sendText(clipboardText)
                    clipboardText = ""
                }
                showClipboardMenu = false
            } label: {
                Label("发送文本", systemImage: "paperplane")
            }
            .disabled(clipboardText.isEmpty)
        }
        .padding()
        .frame(width: 250)
    }
}

// MARK: - 工具栏按钮

struct ToolbarButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isActive ? .blue : tint)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 50, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - 统计项

struct StatItem: View {
    let icon: String
    let value: String
    let unit: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.monospacedDigit())

            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        SessionToolbarView(viewModel: RemoteDesktopViewModel())
            .padding()
    }
    .background(Color.gray.opacity(0.3))
}
