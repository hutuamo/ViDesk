import Foundation
import Security

/// Keychain 服务
/// 负责安全存储和检索用户凭证
final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.videsk.rdp"
    private let accessGroup: String? = nil

    private init() {}

    // MARK: - 密码管理

    /// 保存密码
    func savePassword(_ password: String, for connectionId: UUID) throws {
        let key = passwordKey(for: connectionId)

        guard let data = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // 先尝试删除旧的
        try? deletePassword(for: connectionId)

        var query = baseQuery(for: key)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// 获取密码
    func getPassword(for connectionId: UUID) throws -> String? {
        let key = passwordKey(for: connectionId)

        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }

        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return password
    }

    /// 删除密码
    func deletePassword(for connectionId: UUID) throws {
        let key = passwordKey(for: connectionId)

        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// 检查是否存在密码
    func hasPassword(for connectionId: UUID) -> Bool {
        let key = passwordKey(for: connectionId)

        var query = baseQuery(for: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - 通用凭证管理

    /// 保存通用数据
    func saveData(_ data: Data, for key: String) throws {
        try? deleteData(for: key)

        var query = baseQuery(for: key)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// 获取通用数据
    func getData(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }

        return result as? Data
    }

    /// 删除通用数据
    func deleteData(for key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - 批量操作

    /// 删除所有保存的凭证
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - 私有方法

    private func passwordKey(for connectionId: UUID) -> String {
        "password-\(connectionId.uuidString)"
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}

// MARK: - 错误类型

enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "密码编码失败"
        case .decodingFailed:
            return "密码解码失败"
        case .saveFailed(let status):
            return "保存密码失败: \(status)"
        case .loadFailed(let status):
            return "读取密码失败: \(status)"
        case .deleteFailed(let status):
            return "删除密码失败: \(status)"
        }
    }
}
