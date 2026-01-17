import SwiftUI

/// 添加/编辑连接视图
struct AddConnectionView: View {
    @Environment(\.dismiss) private var dismiss

    let existingConfig: ConnectionConfig?
    let onSave: (ConnectionConfig, String?) -> Void

    @State private var name: String = ""
    @State private var hostname: String = ""
    @State private var port: String = "3389"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var domain: String = ""

    @State private var showAdvancedSettings = false
    @State private var displayWidth: Int = 1920
    @State private var displayHeight: Int = 1080
    @State private var colorDepth: ColorDepth = .bits32
    @State private var autoReconnect: Bool = true
    @State private var useNLA: Bool = true
    @State private var ignoreCertErrors: Bool = false
    @State private var gatewayHostname: String = ""

    @State private var showingError = false
    @State private var errorMessage = ""

    init(existingConfig: ConnectionConfig? = nil, onSave: @escaping (ConnectionConfig, String?) -> Void) {
        self.existingConfig = existingConfig
        self.onSave = onSave
    }

    var isEditing: Bool {
        existingConfig != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                credentialsSection
                advancedSection
            }
            .navigationTitle(isEditing ? "编辑连接" : "添加连接")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "保存" : "添加") {
                        saveConnection()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("错误", isPresented: $showingError) {
                Button("确定") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadExistingConfig()
            }
        }
    }

    // MARK: - 基本信息

    private var basicInfoSection: some View {
        Section("基本信息") {
            TextField("名称 (可选)", text: $name)

            TextField("主机地址", text: $hostname)
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS) || os(visionOS)
                .keyboardType(.URL)
                #endif

            HStack {
                Text("端口")
                Spacer()
                TextField("3389", text: $port)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    #if os(iOS) || os(visionOS)
                    .keyboardType(.numberPad)
                    #endif
            }
        }
    }

    // MARK: - 凭证信息

    private var credentialsSection: some View {
        Section("凭证") {
            TextField("用户名", text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()

            SecureField("密码", text: $password)
                .textContentType(.password)

            TextField("域 (可选)", text: $domain)
                .autocorrectionDisabled()
        }
    }

    // MARK: - 高级设置

    private var advancedSection: some View {
        Section {
            DisclosureGroup("高级设置", isExpanded: $showAdvancedSettings) {
                // 显示设置
                Picker("分辨率", selection: $displayWidth) {
                    ForEach(ResolutionPreset.presets) { preset in
                        Text(preset.name).tag(preset.width)
                    }
                }
                .onChange(of: displayWidth) { _, newValue in
                    if let preset = ResolutionPreset.presets.first(where: { $0.width == newValue }) {
                        displayHeight = preset.height
                    }
                }

                Picker("色彩深度", selection: $colorDepth) {
                    ForEach(ColorDepth.allCases) { depth in
                        Text(depth.displayName).tag(depth)
                    }
                }

                // 连接设置
                Toggle("自动重连", isOn: $autoReconnect)

                Toggle("使用 NLA 认证", isOn: $useNLA)

                Toggle("忽略证书错误", isOn: $ignoreCertErrors)

                // 网关
                TextField("RD 网关 (可选)", text: $gatewayHostname)
                    .autocorrectionDisabled()
            }
        }
    }

    // MARK: - 验证

    private var isValid: Bool {
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Int(port) ?? 0) > 0 && (Int(port) ?? 0) <= 65535
    }

    // MARK: - 操作

    private func loadExistingConfig() {
        guard let config = existingConfig else { return }

        name = config.name
        hostname = config.hostname
        port = String(config.port)
        username = config.username
        domain = config.domain ?? ""

        let settings = config.displaySettings
        displayWidth = settings.width
        displayHeight = settings.height
        colorDepth = settings.colorDepth

        autoReconnect = config.autoReconnect
        useNLA = config.useNLA
        ignoreCertErrors = config.ignoreCertificateErrors
        gatewayHostname = config.gatewayHostname ?? ""
    }

    private func saveConnection() {
        guard isValid else {
            errorMessage = "请填写有效的主机地址和端口"
            showingError = true
            return
        }

        let displaySettings = DisplaySettings(
            width: displayWidth,
            height: displayHeight,
            colorDepth: colorDepth,
            maxFrameRate: 60,
            useHardwareAcceleration: true,
            scaleMode: .fit
        )

        let config: ConnectionConfig

        if let existing = existingConfig {
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.hostname = hostname.trimmingCharacters(in: .whitespaces)
            existing.port = Int(port) ?? 3389
            existing.username = username.trimmingCharacters(in: .whitespaces)
            existing.domain = domain.isEmpty ? nil : domain.trimmingCharacters(in: .whitespaces)
            existing.displaySettings = displaySettings
            existing.autoReconnect = autoReconnect
            existing.useNLA = useNLA
            existing.ignoreCertificateErrors = ignoreCertErrors
            existing.gatewayHostname = gatewayHostname.isEmpty ? nil : gatewayHostname
            config = existing
        } else {
            config = ConnectionConfig(
                name: name.trimmingCharacters(in: .whitespaces),
                hostname: hostname.trimmingCharacters(in: .whitespaces),
                port: Int(port) ?? 3389,
                username: username.trimmingCharacters(in: .whitespaces),
                domain: domain.isEmpty ? nil : domain.trimmingCharacters(in: .whitespaces),
                displaySettings: displaySettings,
                autoReconnect: autoReconnect,
                gatewayHostname: gatewayHostname.isEmpty ? nil : gatewayHostname,
                useNLA: useNLA,
                ignoreCertificateErrors: ignoreCertErrors
            )
        }

        let passwordToSave = password.isEmpty ? nil : password

        onSave(config, passwordToSave)
        dismiss()
    }
}

#Preview("Add") {
    AddConnectionView { _, _ in }
}

#Preview("Edit") {
    AddConnectionView(existingConfig: .preview) { _, _ in }
}
