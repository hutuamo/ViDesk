import Foundation

/// 键盘映射器
/// 将 macOS/visionOS 键码映射到 Windows 扫描码
final class KeyboardMapper {
    // MARK: - 键盘布局

    enum KeyboardLayout: String, CaseIterable {
        case usStandard = "US"
        case ukStandard = "UK"
        case german = "DE"
        case french = "FR"
        case japanese = "JP"
        case chinese = "CN"
    }

    var currentLayout: KeyboardLayout = .usStandard

    // MARK: - 扫描码映射

    /// macOS 虚拟键码到 Windows 扫描码的映射
    private let scanCodeMap: [UInt16: UInt16] = [
        // 字母键
        0x00: 0x1E,  // A
        0x01: 0x1F,  // S
        0x02: 0x20,  // D
        0x03: 0x21,  // F
        0x04: 0x23,  // H
        0x05: 0x22,  // G
        0x06: 0x2C,  // Z
        0x07: 0x2D,  // X
        0x08: 0x2E,  // C
        0x09: 0x2F,  // V
        0x0B: 0x30,  // B
        0x0C: 0x10,  // Q
        0x0D: 0x11,  // W
        0x0E: 0x12,  // E
        0x0F: 0x13,  // R
        0x10: 0x15,  // Y
        0x11: 0x14,  // T
        0x1F: 0x18,  // O
        0x20: 0x16,  // U
        0x21: 0x17,  // I
        0x22: 0x19,  // P
        0x23: 0x26,  // L
        0x25: 0x28,  // '
        0x26: 0x24,  // J
        0x27: 0x27,  // ;
        0x28: 0x25,  // K
        0x29: 0x33,  // ,
        0x2A: 0x35,  // /
        0x2B: 0x31,  // N
        0x2C: 0x32,  // M
        0x2D: 0x34,  // .
        0x2E: 0x1A,  // [
        0x2F: 0x1B,  // ]
        0x31: 0x39,  // Space
        0x32: 0x29,  // `

        // 数字键
        0x12: 0x02,  // 1
        0x13: 0x03,  // 2
        0x14: 0x04,  // 3
        0x15: 0x05,  // 4
        0x17: 0x06,  // 5
        0x16: 0x07,  // 6
        0x1A: 0x08,  // 7
        0x1C: 0x09,  // 8
        0x19: 0x0A,  // 9
        0x1D: 0x0B,  // 0
        0x18: 0x0D,  // =
        0x1B: 0x0C,  // -

        // 功能键
        0x7A: 0x3B,  // F1
        0x78: 0x3C,  // F2
        0x63: 0x3D,  // F3
        0x76: 0x3E,  // F4
        0x60: 0x3F,  // F5
        0x61: 0x40,  // F6
        0x62: 0x41,  // F7
        0x64: 0x42,  // F8
        0x65: 0x43,  // F9
        0x6D: 0x44,  // F10
        0x67: 0x57,  // F11
        0x6F: 0x58,  // F12

        // 修饰键
        0x38: 0x38,  // Left Shift
        0x3C: 0x36,  // Right Shift (扩展)
        0x3B: 0x1D,  // Left Control
        0x3E: 0x1D,  // Right Control (扩展)
        0x3A: 0x38,  // Left Option/Alt
        0x3D: 0x38,  // Right Option/Alt (扩展)
        0x37: 0x5B,  // Left Command -> Windows (扩展)
        0x36: 0x5C,  // Right Command -> Windows (扩展)
        0x39: 0x3A,  // Caps Lock

        // 导航键
        0x7E: 0x48,  // Up Arrow (扩展)
        0x7D: 0x50,  // Down Arrow (扩展)
        0x7B: 0x4B,  // Left Arrow (扩展)
        0x7C: 0x4D,  // Right Arrow (扩展)
        0x73: 0x47,  // Home (扩展)
        0x77: 0x4F,  // End (扩展)
        0x74: 0x49,  // Page Up (扩展)
        0x79: 0x51,  // Page Down (扩展)

        // 编辑键
        0x24: 0x1C,  // Return
        0x4C: 0x1C,  // Enter (扩展)
        0x33: 0x0E,  // Backspace
        0x75: 0x53,  // Delete (扩展)
        0x30: 0x0F,  // Tab
        0x35: 0x01,  // Escape
        0x72: 0x52,  // Insert (扩展)

        // 小键盘
        0x52: 0x52,  // Numpad 0
        0x53: 0x4F,  // Numpad 1
        0x54: 0x50,  // Numpad 2
        0x55: 0x51,  // Numpad 3
        0x56: 0x4B,  // Numpad 4
        0x57: 0x4C,  // Numpad 5
        0x58: 0x4D,  // Numpad 6
        0x59: 0x47,  // Numpad 7
        0x5B: 0x48,  // Numpad 8
        0x5C: 0x49,  // Numpad 9
        0x41: 0x53,  // Numpad .
        0x43: 0x37,  // Numpad *
        0x45: 0x4E,  // Numpad +
        0x47: 0x45,  // Numpad Clear (Num Lock)
        0x4B: 0x35,  // Numpad /
        0x4E: 0x4A,  // Numpad -
        0x51: 0x0D,  // Numpad =
    ]

    /// 扩展键集合 (需要设置扩展标志)
    private let extendedKeys: Set<UInt16> = [
        0x3C,  // Right Shift
        0x3E,  // Right Control
        0x3D,  // Right Alt
        0x37,  // Left Command
        0x36,  // Right Command
        0x7E,  // Up
        0x7D,  // Down
        0x7B,  // Left
        0x7C,  // Right
        0x73,  // Home
        0x77,  // End
        0x74,  // Page Up
        0x79,  // Page Down
        0x75,  // Delete
        0x72,  // Insert
        0x4C,  // Enter
    ]

    // MARK: - 公共方法

    /// 将 macOS 键码转换为 Windows 扫描码
    func scanCode(for keyCode: UInt16) -> UInt16? {
        return scanCodeMap[keyCode]
    }

    /// 检查是否为扩展键
    func isExtendedKey(_ keyCode: UInt16) -> Bool {
        return extendedKeys.contains(keyCode)
    }

    /// 获取特殊按键的扫描码序列
    func scanCodes(for specialKey: SpecialKey) -> [(scanCode: UInt16, extended: Bool)] {
        return specialKey.keyCombination
    }

    /// 将字符转换为键盘事件序列
    func keySequence(for character: Character) -> [(scanCode: UInt16, extended: Bool, shift: Bool)]? {
        guard let ascii = character.asciiValue else { return nil }

        // 简化实现: 只处理基本 ASCII 字符
        let charMap: [UInt8: (scanCode: UInt16, shift: Bool)] = [
            // 小写字母
            0x61: (0x1E, false), // a
            0x62: (0x30, false), // b
            0x63: (0x2E, false), // c
            0x64: (0x20, false), // d
            0x65: (0x12, false), // e
            0x66: (0x21, false), // f
            0x67: (0x22, false), // g
            0x68: (0x23, false), // h
            0x69: (0x17, false), // i
            0x6A: (0x24, false), // j
            0x6B: (0x25, false), // k
            0x6C: (0x26, false), // l
            0x6D: (0x32, false), // m
            0x6E: (0x31, false), // n
            0x6F: (0x18, false), // o
            0x70: (0x19, false), // p
            0x71: (0x10, false), // q
            0x72: (0x13, false), // r
            0x73: (0x1F, false), // s
            0x74: (0x14, false), // t
            0x75: (0x16, false), // u
            0x76: (0x2F, false), // v
            0x77: (0x11, false), // w
            0x78: (0x2D, false), // x
            0x79: (0x15, false), // y
            0x7A: (0x2C, false), // z

            // 大写字母 (需要 Shift)
            0x41: (0x1E, true),  // A
            0x42: (0x30, true),  // B
            0x43: (0x2E, true),  // C
            0x44: (0x20, true),  // D
            0x45: (0x12, true),  // E
            0x46: (0x21, true),  // F
            0x47: (0x22, true),  // G
            0x48: (0x23, true),  // H
            0x49: (0x17, true),  // I
            0x4A: (0x24, true),  // J
            0x4B: (0x25, true),  // K
            0x4C: (0x26, true),  // L
            0x4D: (0x32, true),  // M
            0x4E: (0x31, true),  // N
            0x4F: (0x18, true),  // O
            0x50: (0x19, true),  // P
            0x51: (0x10, true),  // Q
            0x52: (0x13, true),  // R
            0x53: (0x1F, true),  // S
            0x54: (0x14, true),  // T
            0x55: (0x16, true),  // U
            0x56: (0x2F, true),  // V
            0x57: (0x11, true),  // W
            0x58: (0x2D, true),  // X
            0x59: (0x15, true),  // Y
            0x5A: (0x2C, true),  // Z

            // 数字
            0x30: (0x0B, false), // 0
            0x31: (0x02, false), // 1
            0x32: (0x03, false), // 2
            0x33: (0x04, false), // 3
            0x34: (0x05, false), // 4
            0x35: (0x06, false), // 5
            0x36: (0x07, false), // 6
            0x37: (0x08, false), // 7
            0x38: (0x09, false), // 8
            0x39: (0x0A, false), // 9

            // 特殊字符
            0x20: (0x39, false), // Space
            0x0D: (0x1C, false), // Enter
            0x09: (0x0F, false), // Tab
        ]

        if let mapping = charMap[ascii] {
            return [(mapping.scanCode, false, mapping.shift)]
        }

        return nil
    }
}
