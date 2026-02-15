import Foundation
import SwiftUI

/// 连接管理 ViewModel
@MainActor
@Observable
final class ConnectionManagerViewModel {
    // MARK: - 可观察属性

    /// 所有连接
    private(set) var connections: [ConnectionConfig] = []

    /// 最近使用的连接
    private(set) var recentConnections: [ConnectionConfig] = []

    /// 搜索查询
    var searchQuery: String = "" {
        didSet {
            performSearch()
        }
    }

    /// 搜索结果
    private(set) var searchResults: [ConnectionConfig] = []

    /// 是否正在加载
    private(set) var isLoading: Bool = false

    /// 错误信息
    var errorMessage: String?

    /// 当前选中的连接
    var selectedConnection: ConnectionConfig?

    /// 是否显示添加连接表单
    var showAddConnection: Bool = false

    /// 是否显示编辑连接表单
    var showEditConnection: Bool = false

    /// 正在编辑的连接
    var editingConnection: ConnectionConfig?

    // MARK: - 私有属性

    private let storageService: ConnectionStorageService
    private let keychainService: KeychainService

    // MARK: - 初始化

    init(storageService: ConnectionStorageService = .shared,
         keychainService: KeychainService = .shared) {
        self.storageService = storageService
        self.keychainService = keychainService
    }

    // MARK: - 数据加载

    /// 加载所有连接
    func loadConnections() {
        isLoading = true
        errorMessage = nil

        do {
            connections = try storageService.fetchAll()
            recentConnections = try storageService.fetchRecent(limit: 5)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 执行搜索
    private func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        do {
            searchResults = try storageService.search(query: searchQuery)
        } catch {
            searchResults = []
        }
    }

    // MARK: - 连接管理

    /// 添加新连接
    func addConnection(_ config: ConnectionConfig, password: String?) {
        do {
            try storageService.save(config)

            if let password = password, !password.isEmpty {
                try keychainService.savePassword(password, for: config.id)
                config.credentialKeyRef = config.id.uuidString
                try storageService.update(config)
            }

            loadConnections()
        } catch {
            errorMessage = "保存连接失败: \(error.localizedDescription)"
        }
    }

    /// 更新连接
    func updateConnection(_ config: ConnectionConfig, password: String?) {
        do {
            try storageService.update(config)

            if let password = password, !password.isEmpty {
                try keychainService.savePassword(password, for: config.id)
                config.credentialKeyRef = config.id.uuidString
                try storageService.update(config)
            }

            loadConnections()
        } catch {
            errorMessage = "更新连接失败: \(error.localizedDescription)"
        }
    }

    /// 删除连接
    func deleteConnection(_ config: ConnectionConfig) {
        do {
            try storageService.delete(config)
            loadConnections()

            if selectedConnection?.id == config.id {
                selectedConnection = nil
            }
        } catch {
            errorMessage = "删除连接失败: \(error.localizedDescription)"
        }
    }

    /// 复制连接
    func duplicateConnection(_ config: ConnectionConfig) {
        let newConfig = ConnectionConfig(
            name: "\(config.name) (副本)",
            hostname: config.hostname,
            port: config.port,
            username: config.username,
            domain: config.domain,
            displaySettings: config.displaySettings,
            folderPath: config.folderPath,
            autoReconnect: config.autoReconnect,
            useNLA: config.useNLA
        )

        addConnection(newConfig, password: nil)
    }

    // MARK: - 连接操作

    /// 获取连接密码
    func getPassword(for config: ConnectionConfig) -> String? {
        // #region agent log
        let logPath = "/Users/xhl/study/ai/studio/rdpclient/ViDesk/.cursor/debug.log"
        // #endregion
        do {
            let password = try keychainService.getPassword(for: config.id)
            // #region agent log
            let logEntry = """
{"id":"log_\(UUID().uuidString)","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"location":"ConnectionManagerViewModel.swift:158","message":"Keychain获取密码","data":{"connectionId":"\(config.id.uuidString)","passwordIsNil":\(password == nil),"passwordLength":\(password?.count ?? 0)},"sessionId":"debug-session","runId":"run1","hypothesisId":"D"}
"""
            if FileManager.default.fileExists(atPath: logPath), let fileHandle = FileHandle(forWritingAtPath: logPath) {
                defer { try? fileHandle.close() }
                try? fileHandle.seekToEnd()
                try? fileHandle.write(contentsOf: logEntry.data(using: .utf8) ?? Data())
            } else {
                try? FileManager.default.createDirectory(atPath: "/Users/xhl/study/ai/studio/rdpclient/ViDesk/.cursor", withIntermediateDirectories: true, attributes: nil)
                try? logEntry.write(toFile: logPath, atomically: true, encoding: .utf8)
            }
            // #endregion
            return password
        } catch {
            // #region agent log
            let logEntry2 = """
{"id":"log_\(UUID().uuidString)","timestamp":\(Int(Date().timeIntervalSince1970 * 1000)),"location":"ConnectionManagerViewModel.swift:162","message":"Keychain获取密码失败","data":{"connectionId":"\(config.id.uuidString)","error":"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\""))"},"sessionId":"debug-session","runId":"run1","hypothesisId":"D"}
"""
            if FileManager.default.fileExists(atPath: logPath), let fileHandle = FileHandle(forWritingAtPath: logPath) {
                defer { try? fileHandle.close() }
                try? fileHandle.seekToEnd()
                try? fileHandle.write(contentsOf: logEntry2.data(using: .utf8) ?? Data())
            } else {
                try? logEntry2.write(toFile: logPath, atomically: true, encoding: .utf8)
            }
            // #endregion
            return nil
        }
    }

    /// 检查是否有保存的密码
    func hasPassword(for config: ConnectionConfig) -> Bool {
        keychainService.hasPassword(for: config.id)
    }

    /// 更新最后连接时间
    func markAsConnected(_ config: ConnectionConfig) {
        do {
            try storageService.updateLastConnected(config)
            loadConnections()
        } catch {
            // 忽略错误
        }
    }

    // MARK: - 导入导出

    /// 导出连接
    func exportConnections() -> Data? {
        do {
            return try storageService.exportAll()
        } catch {
            errorMessage = "导出失败: \(error.localizedDescription)"
            return nil
        }
    }

    /// 导入连接
    func importConnections(from data: Data) -> Int {
        do {
            let count = try storageService.importConnections(from: data)
            loadConnections()
            return count
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
            return 0
        }
    }

    // MARK: - 编辑操作

    func startEditing(_ config: ConnectionConfig) {
        editingConnection = config
        showEditConnection = true
    }

    func startAddingConnection() {
        editingConnection = nil
        showAddConnection = true
    }
}
