import Foundation
import SwiftData

/// 连接存储服务
/// 负责使用 SwiftData 持久化连接配置
@MainActor
final class ConnectionStorageService {
    static let shared = ConnectionStorageService()

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    private init() {
        setupContainer()
    }

    // MARK: - 初始化

    private func setupContainer() {
        do {
            let schema = Schema([ConnectionConfig.self])
            let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: configuration)
            modelContext = modelContainer?.mainContext
        } catch {
            print("Failed to setup SwiftData container: \(error)")
        }
    }

    // MARK: - CRUD 操作

    /// 保存连接配置
    func save(_ config: ConnectionConfig) throws {
        guard let context = modelContext else {
            throw StorageError.contextNotAvailable
        }

        context.insert(config)
        try context.save()
    }

    /// 更新连接配置
    func update(_ config: ConnectionConfig) throws {
        guard let context = modelContext else {
            throw StorageError.contextNotAvailable
        }

        try context.save()
    }

    /// 删除连接配置
    func delete(_ config: ConnectionConfig) throws {
        guard let context = modelContext else {
            throw StorageError.contextNotAvailable
        }

        // 同时删除关联的密码
        try? KeychainService.shared.deletePassword(for: config.id)

        context.delete(config)
        try context.save()
    }

    /// 获取所有连接配置
    func fetchAll() throws -> [ConnectionConfig] {
        guard let context = modelContext else {
            throw StorageError.contextNotAvailable
        }

        let descriptor = FetchDescriptor<ConnectionConfig>(
            sortBy: [SortDescriptor(\ConnectionConfig.lastConnectedAt, order: .reverse)]
        )

        return try context.fetch(descriptor)
    }

    /// 根据 ID 获取连接配置
    func fetch(by id: UUID) throws -> ConnectionConfig? {
        guard let context = modelContext else {
            throw StorageError.contextNotAvailable
        }

        let predicate = #Predicate<ConnectionConfig> { $0.id == id }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }

    /// 搜索连接配置
    func search(query: String) throws -> [ConnectionConfig] {
        guard let context = modelContext else {
            throw StorageError.contextNotAvailable
        }

        let lowercasedQuery = query.lowercased()

        let predicate = #Predicate<ConnectionConfig> {
            $0.name.localizedStandardContains(lowercasedQuery) ||
            $0.hostname.localizedStandardContains(lowercasedQuery) ||
            $0.username.localizedStandardContains(lowercasedQuery)
        }

        let descriptor = FetchDescriptor(predicate: predicate)
        return try context.fetch(descriptor)
    }

    /// 获取指定文件夹下的连接
    func fetchByFolder(_ folderPath: String?) throws -> [ConnectionConfig] {
        guard let context = modelContext else {
            throw StorageError.contextNotAvailable
        }

        let predicate: Predicate<ConnectionConfig>
        if let path = folderPath {
            predicate = #Predicate { $0.folderPath == path }
        } else {
            predicate = #Predicate { $0.folderPath == nil }
        }

        let descriptor = FetchDescriptor(predicate: predicate)
        return try context.fetch(descriptor)
    }

    /// 获取最近使用的连接
    func fetchRecent(limit: Int = 5) throws -> [ConnectionConfig] {
        guard let context = modelContext else {
            throw StorageError.contextNotAvailable
        }

        let predicate = #Predicate<ConnectionConfig> { $0.lastConnectedAt != nil }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\ConnectionConfig.lastConnectedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        return try context.fetch(descriptor)
    }

    /// 更新最后连接时间
    func updateLastConnected(_ config: ConnectionConfig) throws {
        config.lastConnectedAt = Date()
        try update(config)
    }

    // MARK: - 文件夹管理

    /// 获取所有文件夹路径
    func fetchAllFolders() throws -> [String] {
        guard let context = modelContext else {
            throw StorageError.contextNotAvailable
        }

        let descriptor = FetchDescriptor<ConnectionConfig>()
        let configs = try context.fetch(descriptor)

        let folders = Set(configs.compactMap { $0.folderPath })
        return Array(folders).sorted()
    }

    /// 移动连接到文件夹
    func moveToFolder(_ config: ConnectionConfig, folderPath: String?) throws {
        config.folderPath = folderPath
        try update(config)
    }

    // MARK: - 导入导出

    /// 导出所有连接 (不包含密码)
    func exportAll() throws -> Data {
        let configs = try fetchAll()
        let exportData = configs.map { config -> [String: Any] in
            [
                "id": config.id.uuidString,
                "name": config.name,
                "hostname": config.hostname,
                "port": config.port,
                "username": config.username,
                "domain": config.domain ?? "",
                "folderPath": config.folderPath ?? "",
                "autoReconnect": config.autoReconnect,
                "useNLA": config.useNLA,
                "displaySettings": [
                    "width": config.displaySettings.width,
                    "height": config.displaySettings.height,
                    "colorDepth": config.displaySettings.colorDepth.rawValue
                ]
            ]
        }

        return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    /// 导入连接配置
    func importConnections(from data: Data) throws -> Int {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw StorageError.invalidData
        }

        var importedCount = 0

        for json in jsonArray {
            guard let name = json["name"] as? String,
                  let hostname = json["hostname"] as? String else {
                continue
            }

            let port = json["port"] as? Int ?? 3389
            let username = json["username"] as? String ?? ""
            let domain = json["domain"] as? String
            let folderPath = json["folderPath"] as? String
            let autoReconnect = json["autoReconnect"] as? Bool ?? true
            let useNLA = json["useNLA"] as? Bool ?? true

            var displaySettings = DisplaySettings.default
            if let displayJson = json["displaySettings"] as? [String: Any] {
                if let width = displayJson["width"] as? Int {
                    displaySettings.width = width
                }
                if let height = displayJson["height"] as? Int {
                    displaySettings.height = height
                }
                if let depth = displayJson["colorDepth"] as? Int,
                   let colorDepth = ColorDepth(rawValue: depth) {
                    displaySettings.colorDepth = colorDepth
                }
            }

            let config = ConnectionConfig(
                name: name,
                hostname: hostname,
                port: port,
                username: username,
                domain: domain?.isEmpty == true ? nil : domain,
                displaySettings: displaySettings,
                folderPath: folderPath?.isEmpty == true ? nil : folderPath,
                autoReconnect: autoReconnect,
                useNLA: useNLA
            )

            try save(config)
            importedCount += 1
        }

        return importedCount
    }
}

// MARK: - 错误类型

enum StorageError: LocalizedError {
    case contextNotAvailable
    case invalidData
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .contextNotAvailable:
            return "存储上下文不可用"
        case .invalidData:
            return "无效的数据格式"
        case .saveFailed(let reason):
            return "保存失败: \(reason)"
        }
    }
}
