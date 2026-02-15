import Foundation
import SwiftData

/// RDP 连接配置模型
@Model
final class ConnectionConfig {
    /// 唯一标识符
    @Attribute(.unique) var id: UUID

    /// 连接显示名称
    var name: String

    /// 主机地址
    var hostname: String

    /// 端口号
    var port: Int

    /// 用户名
    var username: String

    /// Keychain 凭证引用键
    var credentialKeyRef: String?

    /// 域名 (可选)
    var domain: String?

    /// 显示设置 (存储为 JSON)
    var displaySettingsData: Data?

    /// 文件夹路径 (用于分组)
    var folderPath: String?

    /// 最后连接时间
    var lastConnectedAt: Date?

    /// 创建时间
    var createdAt: Date

    /// 是否自动重连
    var autoReconnect: Bool

    /// 网关地址 (可选)
    var gatewayHostname: String?

    /// 是否使用 NLA
    var useNLA: Bool

    /// 是否使用 TLS
    var useTLS: Bool

    /// 是否忽略证书错误
    var ignoreCertificateErrors: Bool

    init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = 3389,
        username: String = "",
        domain: String? = nil,
        credentialKeyRef: String? = nil,
        displaySettings: DisplaySettings = .default,
        folderPath: String? = nil,
        autoReconnect: Bool = true,
        gatewayHostname: String? = nil,
        useNLA: Bool = false,
        useTLS: Bool = true,
        ignoreCertificateErrors: Bool = true
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.domain = domain
        self.credentialKeyRef = credentialKeyRef
        self.displaySettingsData = try? JSONEncoder().encode(displaySettings)
        self.folderPath = folderPath
        self.createdAt = Date()
        self.autoReconnect = autoReconnect
        self.gatewayHostname = gatewayHostname
        self.useNLA = useNLA
        self.useTLS = useTLS
        self.ignoreCertificateErrors = ignoreCertificateErrors
    }

    var displaySettings: DisplaySettings {
        get {
            guard let data = displaySettingsData,
                  let settings = try? JSONDecoder().decode(DisplaySettings.self, from: data) else {
                return .default
            }
            return settings
        }
        set {
            displaySettingsData = try? JSONEncoder().encode(newValue)
        }
    }

    var fullAddress: String {
        if port == 3389 {
            return hostname
        }
        return "\(hostname):\(port)"
    }

    var displayTitle: String {
        name.isEmpty ? fullAddress : name
    }
}

extension ConnectionConfig {
    static var preview: ConnectionConfig {
        ConnectionConfig(
            name: "工作电脑",
            hostname: "192.168.1.100",
            username: "admin"
        )
    }

    static var previewList: [ConnectionConfig] {
        [
            ConnectionConfig(name: "工作电脑", hostname: "192.168.1.100", username: "admin"),
            ConnectionConfig(name: "开发服务器", hostname: "dev.example.com", username: "developer"),
            ConnectionConfig(name: "测试机", hostname: "192.168.1.200", port: 3390, username: "tester")
        ]
    }
}
