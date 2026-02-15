import Foundation

/// 显示设置配置
struct DisplaySettings: Codable, Hashable {
    /// 分辨率宽度
    var width: Int

    /// 分辨率高度
    var height: Int

    /// 色彩深度 (16/24/32位)
    var colorDepth: ColorDepth

    /// 帧率限制
    var maxFrameRate: Int

    /// 是否启用硬件加速
    var useHardwareAcceleration: Bool

    /// 缩放模式
    var scaleMode: ScaleMode

    static var `default`: DisplaySettings {
        DisplaySettings(
            width: 1920,
            height: 1080,
            colorDepth: .bits32,
            maxFrameRate: 60,
            useHardwareAcceleration: true,
            scaleMode: .fit
        )
    }

    static var visionProOptimal: DisplaySettings {
        DisplaySettings(
            width: 2560,
            height: 1440,
            colorDepth: .bits32,
            maxFrameRate: 90,
            useHardwareAcceleration: true,
            scaleMode: .fit
        )
    }
}

enum ColorDepth: Int, Codable, CaseIterable, Identifiable {
    case bits16 = 16
    case bits24 = 24
    case bits32 = 32

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .bits16: return "16位 (高性能)"
        case .bits24: return "24位 (平衡)"
        case .bits32: return "32位 (高质量)"
        }
    }

    var bytesPerPixel: Int {
        switch self {
        case .bits16: return 2
        case .bits24: return 3
        case .bits32: return 4
        }
    }
}

enum ScaleMode: String, Codable, CaseIterable, Identifiable {
    case fit = "fit"
    case fill = "fill"
    case native = "native"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit: return "适应窗口"
        case .fill: return "填充窗口"
        case .native: return "原始大小"
        }
    }
}

/// 预设分辨率选项
struct ResolutionPreset: Identifiable {
    let id = UUID()
    let name: String
    let width: Int
    let height: Int

    static let presets: [ResolutionPreset] = [
        ResolutionPreset(name: "720p", width: 1280, height: 720),
        ResolutionPreset(name: "1080p", width: 1920, height: 1080),
        ResolutionPreset(name: "1440p", width: 2560, height: 1440),
        ResolutionPreset(name: "4K", width: 3840, height: 2160),
        ResolutionPreset(name: "Vision Pro 最佳", width: 2560, height: 1440)
    ]
}
