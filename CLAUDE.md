# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

ViDesk 是一个运行在 Apple Vision Pro 上的远程桌面协议 (RDP) 客户端应用。

**技术栈**: visionOS 2.0+ / Swift 5.9+ / SwiftUI / SwiftData / Metal / FreeRDP 3.x

## 构建说明

### Xcode 项目生成

项目使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理，配置文件为 `project.yml`。

```bash
# 生成/更新 Xcode 项目
xcodegen generate
```

生成后在 Xcode 中打开 `ViDesk.xcodeproj`，选择 visionOS Simulator 或 Device target 构建。

### FreeRDP 依赖编译

项目依赖 FreeRDP 静态库，编译脚本位于 `build-deps/`：

```bash
# 一键编译所有依赖（OpenSSL → cJSON → FreeRDP）for visionOS device
cd build-deps && ./build-all-device.sh

# 或分别编译 simulator 版本
./build-openssl-visionos.sh
./build-freerdp-visionos.sh
```

编译产物自动放入 `FreeRDPFramework/lib/` 和 `FreeRDPFramework/include/`。

链接的库：libfreerdp3, libfreerdp-client3, libwinpr3, libcjson, libssl, libcrypto, libz

## 架构概览

```
表现层 (SwiftUI Views)
        ↓
业务层 (ViewModels, @Observable)
        ↓
核心层 (RDPSession, MetalRenderer, InputManager)
        ↓
桥接层 (FreeRDPContext.swift → FreeRDPBridge.c)
        ↓
C 层 (FreeRDP + WinPR + OpenSSL)
```

### 关键模块

| 模块 | 路径 | 职责 |
|------|------|------|
| RDP 会话 | `Core/RDP/RDPSession.swift` | 连接生命周期管理、状态机（6 种状态）、自动重连 |
| FreeRDP 桥接 | `Core/RDP/FreeRDPWrapper/` | C/Swift 互操作：FreeRDPContext.swift（Swift 封装）、FreeRDPBridge.c/h（C 实现）、iOSPathHelpers.m |
| Metal 渲染 | `Core/Rendering/` | FrameBuffer（帧缓冲/三重缓冲）、MetalRenderer、DesktopShaders.metal |
| 输入处理 | `Core/Input/` | InputManager 统一管理，GestureTranslator（手势→鼠标）、KeyboardMapper（扫描码转换） |
| RDP 通道 | `Core/RDP/Channels/` | ClipboardChannel、AudioChannel（音频因 visionOS 无 CoreAudio 暂不可用） |

### MVVM 结构

每个功能模块位于 `Features/` 下，包含 `Views/` + `ViewModels/`（使用 `@Observable` 宏）。

四个功能模块：ConnectionManager、RemoteDesktop、Settings、Debug

### C/Swift 桥接机制

- `ViDesk-Bridging-Header.h` → 引入 `FreeRDPBridge.h`
- `FreeRDPBridge.h/c`：定义 `ViDeskContext` 结构体和 `viDesk_*` 系列 C API（连接、输入、帧缓冲、剪贴板）
- `FreeRDPContext.swift`：将 C 回调转为 Swift async/await，管理 `ViDeskContext` 生命周期
- `iOSPathHelpers.m`：Objective-C 路径辅助函数（使用 strdup 返回动态内存）
- 回调类型：FrameUpdateCallback、ConnectionStateCallback、DesktopResizeCallback、AuthenticateCallback、VerifyCertificateCallback

### VisionOS 输入映射

| VisionOS 手势 | Windows 操作 |
|--------------|-------------|
| 眼动 + 捏合 | 左键单击 |
| 眼动 + 双捏 | 左键双击 |
| 眼动 + 长捏 | 右键单击 |
| 捏住拖动 | 鼠标拖拽 |
| 双指缩放 | 滚轮滚动 |

## 代码规范

- 使用 Swift 5.9+ 特性：`@Observable`、SwiftData、async/await
- 使用 `@MainActor` 保证 UI 相关操作在主线程
- 密码存储使用 `KeychainService`（不要明文存储）
- 注释使用中文
- 服务层使用单例模式（`ConnectionStorageService.shared`、`KeychainService.shared`）

## 当前开发状态

RDP 连接和远程画面显示已成功（连接到 GNOME Remote Desktop / Ubuntu）。使用 GFX 管道（非 H.264，RDPGFX_CAPVERSION_107）。

当前重点：输入功能验证（鼠标/键盘）、剪贴板同步、Windows RDP 兼容性测试。

仅支持 visionOS Simulator，visionOS Device 版本的库编译尚未完成。详见 `docs/ToDo.md` 和 `docs/Progress.md`。
