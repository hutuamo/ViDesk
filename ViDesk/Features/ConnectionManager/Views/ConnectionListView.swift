import SwiftUI

/// 连接列表视图
struct ConnectionListView: View {
    @State private var viewModel = ConnectionManagerViewModel()
    @State private var quickConnectAddress = ""
    @State private var showingPasswordPrompt = false
    @State private var pendingConnection: ConnectionConfig?
    @State private var passwordInput = ""
    @State private var showingError = false

    var onConnect: ((ConnectionConfig, String?) -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                quickConnectSection

                Divider()

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.connections.isEmpty && viewModel.searchQuery.isEmpty {
                    emptyStateView
                } else {
                    connectionsList
                }
            }
            .navigationTitle("ViDesk")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.startAddingConnection()
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("导入连接") {
                            // TODO: 实现导入
                        }
                        Button("导出连接") {
                            // TODO: 实现导出
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "搜索连接")
            .sheet(isPresented: $viewModel.showAddConnection) {
                AddConnectionView { config, password in
                    viewModel.addConnection(config, password: password)
                }
            }
            .sheet(isPresented: $viewModel.showEditConnection) {
                if let config = viewModel.editingConnection {
                    AddConnectionView(existingConfig: config) { config, password in
                        viewModel.updateConnection(config, password: password)
                    }
                }
            }
            .sheet(isPresented: $showingPasswordPrompt) {
                if let config = pendingConnection {
                    PasswordInputView(
                        title: "输入密码",
                        message: "连接到 \(config.displayTitle)",
                        password: $passwordInput,
                        onConnect: {
                            connectTo(config, password: passwordInput)
                            passwordInput = ""
                            pendingConnection = nil
                            showingPasswordPrompt = false
                        },
                        onCancel: {
                            passwordInput = ""
                            pendingConnection = nil
                            showingPasswordPrompt = false
                        }
                    )
                }
            }
            .alert("错误", isPresented: $showingError) {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                showingError = newValue != nil
            }
            .onAppear {
                viewModel.loadConnections()
            }
        }
    }

    // MARK: - 快速连接区域

    private var quickConnectSection: some View {
        HStack(spacing: 12) {
            TextField("输入地址 (例: 192.168.1.100)", text: $quickConnectAddress)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    quickConnect()
                }

            Button("连接") {
                quickConnect()
            }
            .buttonStyle(.borderedProminent)
            .disabled(quickConnectAddress.isEmpty)
        }
        .padding()
    }

    // MARK: - 空状态视图

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("暂无保存的连接")
                .font(.headline)

            Text("使用上方的快速连接，或点击 + 添加新连接")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.startAddingConnection()
            } label: {
                Label("添加连接", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 连接列表

    private var connectionsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 最近使用
                if !viewModel.recentConnections.isEmpty && viewModel.searchQuery.isEmpty {
                    Section {
                        ForEach(viewModel.recentConnections) { config in
                            ConnectionCardView(config: config) {
                                initiateConnection(config)
                            }
                            .contextMenu {
                                connectionContextMenu(for: config)
                            }
                        }
                    } header: {
                        sectionHeader("最近使用")
                    }
                }

                // 搜索结果或所有连接
                let displayedConnections = viewModel.searchQuery.isEmpty
                    ? viewModel.connections
                    : viewModel.searchResults

                if !displayedConnections.isEmpty {
                    Section {
                        ForEach(displayedConnections) { config in
                            ConnectionCardView(config: config) {
                                initiateConnection(config)
                            }
                            .contextMenu {
                                connectionContextMenu(for: config)
                            }
                        }
                    } header: {
                        if viewModel.searchQuery.isEmpty {
                            sectionHeader("所有连接")
                        } else {
                            sectionHeader("搜索结果 (\(displayedConnections.count))")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func connectionContextMenu(for config: ConnectionConfig) -> some View {
        Button {
            initiateConnection(config)
        } label: {
            Label("连接", systemImage: "play.fill")
        }

        Divider()

        Button {
            viewModel.startEditing(config)
        } label: {
            Label("编辑", systemImage: "pencil")
        }

        Button {
            viewModel.duplicateConnection(config)
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.deleteConnection(config)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    // MARK: - 连接操作

    private func quickConnect() {
        guard !quickConnectAddress.isEmpty else { return }

        var hostname = quickConnectAddress
        var port = 3389

        // 解析端口
        if let colonIndex = hostname.lastIndex(of: ":"),
           let portNumber = Int(String(hostname[hostname.index(after: colonIndex)...])) {
            hostname = String(hostname[..<colonIndex])
            port = portNumber
        }

        let config = ConnectionConfig(name: "", hostname: hostname, port: port)

        // 快速连接需要输入密码
        pendingConnection = config
        showingPasswordPrompt = true
    }

    private func initiateConnection(_ config: ConnectionConfig) {
        if viewModel.hasPassword(for: config) {
            let password = viewModel.getPassword(for: config)
            connectTo(config, password: password)
        } else {
            pendingConnection = config
            showingPasswordPrompt = true
        }
    }

    private func connectTo(_ config: ConnectionConfig, password: String?) {
        print("[ViDesk] connectTo 被调用 - 密码长度: \(password?.count ?? 0), 密码为空: \(password?.isEmpty ?? true)")
        viewModel.markAsConnected(config)
        onConnect?(config, password)
    }
}

// MARK: - 密码输入视图

struct PasswordInputView: View {
    let title: String
    let message: String
    @Binding var password: String
    let onConnect: () -> Void
    let onCancel: () -> Void
    @FocusState private var isPasswordFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top)
                
                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($isPasswordFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        if !password.isEmpty {
                            onConnect()
                        }
                    }
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("连接") {
                        onConnect()
                    }
                    .disabled(password.isEmpty)
                }
            }
            .onAppear {
                isPasswordFocused = true
            }
        }
        .presentationDetents([.height(200)])
    }
}

#Preview {
    ConnectionListView()
}
