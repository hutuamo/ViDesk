import SwiftUI

/// 设置视图
struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var showResetConfirmation = false
    @State private var showClearPasswordsConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                inputSection
                securitySection
                advancedSection
                aboutSection
            }
            .navigationTitle("设置")
            .onChange(of: viewModel.defaultResolution.width) { _, _ in
                viewModel.saveSettings()
            }
            .onChange(of: viewModel.defaultColorDepth) { _, _ in
                viewModel.saveSettings()
            }
            .onChange(of: viewModel.defaultScaleMode) { _, _ in
                viewModel.saveSettings()
            }
            .onChange(of: viewModel.scrollMultiplier) { _, _ in
                viewModel.saveSettings()
            }
            .onChange(of: viewModel.savePasswords) { _, _ in
                viewModel.saveSettings()
            }
            .onChange(of: viewModel.useBiometricAuth) { _, _ in
                viewModel.saveSettings()
            }
            .onChange(of: viewModel.enableLogging) { _, _ in
                viewModel.saveSettings()
            }
            .onChange(of: viewModel.useHardwareAcceleration) { _, _ in
                viewModel.saveSettings()
            }
            .confirmationDialog("重置设置", isPresented: $showResetConfirmation) {
                Button("重置为默认值", role: .destructive) {
                    viewModel.resetToDefaults()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确定要将所有设置重置为默认值吗？")
            }
            .confirmationDialog("清除密码", isPresented: $showClearPasswordsConfirmation) {
                Button("清除所有密码", role: .destructive) {
                    viewModel.clearAllPasswords()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确定要清除所有保存的密码吗？此操作不可撤销。")
            }
        }
    }

    // MARK: - 显示设置

    private var displaySection: some View {
        Section("显示") {
            Picker("默认分辨率", selection: Binding(
                get: { viewModel.defaultResolution.width },
                set: { width in
                    if let preset = ResolutionPreset.presets.first(where: { $0.width == width }) {
                        viewModel.defaultResolution = preset
                    }
                }
            )) {
                ForEach(ResolutionPreset.presets) { preset in
                    Text("\(preset.name) (\(preset.width)x\(preset.height))").tag(preset.width)
                }
            }

            Picker("色彩深度", selection: $viewModel.defaultColorDepth) {
                ForEach(ColorDepth.allCases) { depth in
                    Text(depth.displayName).tag(depth)
                }
            }

            Picker("缩放模式", selection: $viewModel.defaultScaleMode) {
                ForEach(ScaleMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Stepper("帧率限制: \(viewModel.maxFrameRate) FPS", value: $viewModel.maxFrameRate, in: 30...120, step: 10)
        }
    }

    // MARK: - 输入设置

    private var inputSection: some View {
        Section("输入") {
            Picker("输入模式", selection: $viewModel.inputMode) {
                Text("指针模式").tag(InputMode.pointer)
                Text("触控板模式").tag(InputMode.touchpad)
                Text("直接触控").tag(InputMode.directTouch)
            }

            HStack {
                Text("滚动速度")
                Slider(value: $viewModel.scrollMultiplier, in: 0.5...3.0, step: 0.1)
                Text(String(format: "%.1fx", viewModel.scrollMultiplier))
                    .frame(width: 40)
                    .foregroundStyle(.secondary)
            }

            Toggle("惯性滚动", isOn: $viewModel.enableInertialScroll)

            Picker("键盘布局", selection: $viewModel.keyboardLayout) {
                ForEach(KeyboardMapper.KeyboardLayout.allCases, id: \.self) { layout in
                    Text(layout.rawValue).tag(layout)
                }
            }
        }
    }

    // MARK: - 安全设置

    private var securitySection: some View {
        Section("安全") {
            Toggle("保存密码", isOn: $viewModel.savePasswords)

            Toggle("使用生物识别解锁", isOn: $viewModel.useBiometricAuth)
                .disabled(!viewModel.savePasswords)

            Toggle("断开连接时自动锁定", isOn: $viewModel.autoLockOnDisconnect)

            Button("清除所有保存的密码", role: .destructive) {
                showClearPasswordsConfirmation = true
            }
        }
    }

    // MARK: - 高级设置

    private var advancedSection: some View {
        Section("高级") {
            Toggle("硬件加速", isOn: $viewModel.useHardwareAcceleration)

            Toggle("启用日志", isOn: $viewModel.enableLogging)

            Button("重置所有设置") {
                showResetConfirmation = true
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("构建")
                Spacer()
                Text("1")
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://github.com")!) {
                HStack {
                    Text("GitHub")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink("开源许可") {
                LicensesView()
            }
        }
    }
}

/// 开源许可视图
struct LicensesView: View {
    var body: some View {
        List {
            Section("FreeRDP") {
                Text("Apache License 2.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("OpenSSL") {
                Text("OpenSSL License / SSLeay License")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("开源许可")
    }
}

#Preview {
    SettingsView()
}
