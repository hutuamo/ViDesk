import Foundation
import SwiftUI

/// 设置 ViewModel
@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - 显示设置

    var defaultResolution: ResolutionPreset = ResolutionPreset.presets[1]
    var defaultColorDepth: ColorDepth = .bits32
    var defaultScaleMode: ScaleMode = .fit
    var maxFrameRate: Int = 60

    // MARK: - 输入设置

    var inputMode: InputMode = .pointer
    var scrollMultiplier: Double = 1.0
    var enableInertialScroll: Bool = true
    var keyboardLayout: KeyboardMapper.KeyboardLayout = .usStandard

    // MARK: - 安全设置

    var savePasswords: Bool = true
    var useBiometricAuth: Bool = false
    var autoLockOnDisconnect: Bool = true

    // MARK: - 高级设置

    var enableLogging: Bool = false
    var useHardwareAcceleration: Bool = true

    // MARK: - 初始化

    init() {
        loadSettings()
    }

    // MARK: - 持久化

    private let defaults = UserDefaults.standard

    func loadSettings() {
        if let resolutionIndex = defaults.object(forKey: "defaultResolution") as? Int,
           resolutionIndex < ResolutionPreset.presets.count {
            defaultResolution = ResolutionPreset.presets[resolutionIndex]
        }

        if let colorDepthRaw = defaults.object(forKey: "defaultColorDepth") as? Int,
           let colorDepth = ColorDepth(rawValue: colorDepthRaw) {
            defaultColorDepth = colorDepth
        }

        if let scaleModeRaw = defaults.string(forKey: "defaultScaleMode"),
           let scaleMode = ScaleMode(rawValue: scaleModeRaw) {
            defaultScaleMode = scaleMode
        }

        maxFrameRate = defaults.integer(forKey: "maxFrameRate")
        if maxFrameRate == 0 { maxFrameRate = 60 }

        scrollMultiplier = defaults.double(forKey: "scrollMultiplier")
        if scrollMultiplier == 0 { scrollMultiplier = 1.0 }

        enableInertialScroll = defaults.bool(forKey: "enableInertialScroll")
        savePasswords = defaults.object(forKey: "savePasswords") as? Bool ?? true
        useBiometricAuth = defaults.bool(forKey: "useBiometricAuth")
        autoLockOnDisconnect = defaults.object(forKey: "autoLockOnDisconnect") as? Bool ?? true
        enableLogging = defaults.bool(forKey: "enableLogging")
        useHardwareAcceleration = defaults.object(forKey: "useHardwareAcceleration") as? Bool ?? true
    }

    func saveSettings() {
        if let index = ResolutionPreset.presets.firstIndex(where: { $0.width == defaultResolution.width }) {
            defaults.set(index, forKey: "defaultResolution")
        }

        defaults.set(defaultColorDepth.rawValue, forKey: "defaultColorDepth")
        defaults.set(defaultScaleMode.rawValue, forKey: "defaultScaleMode")
        defaults.set(maxFrameRate, forKey: "maxFrameRate")
        defaults.set(scrollMultiplier, forKey: "scrollMultiplier")
        defaults.set(enableInertialScroll, forKey: "enableInertialScroll")
        defaults.set(savePasswords, forKey: "savePasswords")
        defaults.set(useBiometricAuth, forKey: "useBiometricAuth")
        defaults.set(autoLockOnDisconnect, forKey: "autoLockOnDisconnect")
        defaults.set(enableLogging, forKey: "enableLogging")
        defaults.set(useHardwareAcceleration, forKey: "useHardwareAcceleration")
    }

    func resetToDefaults() {
        defaultResolution = ResolutionPreset.presets[1]
        defaultColorDepth = .bits32
        defaultScaleMode = .fit
        maxFrameRate = 60
        inputMode = .pointer
        scrollMultiplier = 1.0
        enableInertialScroll = true
        keyboardLayout = .usStandard
        savePasswords = true
        useBiometricAuth = false
        autoLockOnDisconnect = true
        enableLogging = false
        useHardwareAcceleration = true

        saveSettings()
    }

    /// 获取默认显示设置
    func getDefaultDisplaySettings() -> DisplaySettings {
        DisplaySettings(
            width: defaultResolution.width,
            height: defaultResolution.height,
            colorDepth: defaultColorDepth,
            maxFrameRate: maxFrameRate,
            useHardwareAcceleration: useHardwareAcceleration,
            scaleMode: defaultScaleMode
        )
    }

    /// 清除所有保存的密码
    func clearAllPasswords() {
        try? KeychainService.shared.deleteAll()
    }
}
