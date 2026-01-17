import Foundation

/// RDP 会话状态
enum SessionState: Equatable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case reconnecting(attempt: Int)
    case error(RDPError)

    var isActive: Bool {
        switch self {
        case .connected, .reconnecting:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .disconnected:
            return "已断开"
        case .connecting:
            return "正在连接..."
        case .authenticating:
            return "正在验证..."
        case .connected:
            return "已连接"
        case .reconnecting(let attempt):
            return "正在重连 (第\(attempt)次)"
        case .error(let error):
            return "错误: \(error.localizedDescription)"
        }
    }
}

/// RDP 错误类型
enum RDPError: Error, Equatable {
    case connectionFailed(String)
    case authenticationFailed
    case networkError(String)
    case protocolError(String)
    case timeout
    case serverDisconnected
    case certificateError(String)
    case resourceNotAvailable
    case unknown(String)

    var localizedDescription: String {
        switch self {
        case .connectionFailed(let reason):
            return "连接失败: \(reason)"
        case .authenticationFailed:
            return "身份验证失败"
        case .networkError(let reason):
            return "网络错误: \(reason)"
        case .protocolError(let reason):
            return "协议错误: \(reason)"
        case .timeout:
            return "连接超时"
        case .serverDisconnected:
            return "服务器断开连接"
        case .certificateError(let reason):
            return "证书错误: \(reason)"
        case .resourceNotAvailable:
            return "资源不可用"
        case .unknown(let reason):
            return "未知错误: \(reason)"
        }
    }

    static func == (lhs: RDPError, rhs: RDPError) -> Bool {
        switch (lhs, rhs) {
        case (.connectionFailed(let a), .connectionFailed(let b)):
            return a == b
        case (.authenticationFailed, .authenticationFailed):
            return true
        case (.networkError(let a), .networkError(let b)):
            return a == b
        case (.protocolError(let a), .protocolError(let b)):
            return a == b
        case (.timeout, .timeout):
            return true
        case (.serverDisconnected, .serverDisconnected):
            return true
        case (.certificateError(let a), .certificateError(let b)):
            return a == b
        case (.resourceNotAvailable, .resourceNotAvailable):
            return true
        case (.unknown(let a), .unknown(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// 会话统计信息
struct SessionStatistics {
    var frameRate: Double = 0
    var latency: TimeInterval = 0
    var bandwidth: Int = 0
    var framesReceived: UInt64 = 0
    var bytesReceived: UInt64 = 0
    var connectionDuration: TimeInterval = 0

    var formattedLatency: String {
        String(format: "%.0f ms", latency * 1000)
    }

    var formattedBandwidth: String {
        if bandwidth >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bandwidth) / 1_000_000)
        } else if bandwidth >= 1_000 {
            return String(format: "%.0f Kbps", Double(bandwidth) / 1_000)
        }
        return "\(bandwidth) bps"
    }

    var formattedDuration: String {
        let hours = Int(connectionDuration) / 3600
        let minutes = Int(connectionDuration) / 60 % 60
        let seconds = Int(connectionDuration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
