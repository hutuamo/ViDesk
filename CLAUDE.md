# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

ViDesk 是一个运行在 Apple Vision Pro 上的远程桌面协议 (RDP) 客户端应用。

**技术栈**: visionOS 2.0+ / Swift 5.9+ / SwiftUI / SwiftData / Metal / FreeRDP

## 构建说明

这是一个 visionOS 项目，需要在 Xcode 中打开并构建。项目依赖 FreeRDP 静态库（需自行编译）。

**FreeRDP 编译**（阻塞性前置任务）:
```bash
# 克隆 FreeRDP 源码
git clone https://github.com/FreeRDP/FreeRDP.git
cd FreeRDP

# 配置 visionOS 交叉编译
mkdir build-visionos && cd build-visionos
cmake .. \
  -DCMAKE_SYSTEM_NAME=visionOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=2.0 \
  -DBUILD_SHARED_LIBS=OFF \
  -DWITH_CLIENT=ON \
  -DWITH_SERVER=OFF

make -j8
```

编译产物需放置于:
- `FreeRDPFramework/lib/` - 静态库 (libfreerdp3.a, libfreerdp-client3.a, libwinpr3.a)
- `FreeRDPFramework/include/` - 头文件

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
| RDP 会话 | `Core/RDP/RDPSession.swift` | 连接生命周期管理、状态机、自动重连 |
| FreeRDP 桥接 | `Core/RDP/FreeRDPWrapper/` | C/Swift 互操作层 |
| Metal 渲染 | `Core/Rendering/` | 帧缓冲、三重缓冲、GPU 渲染 |
| 输入处理 | `Core/Input/` | VisionOS 手势→鼠标映射、键盘扫描码转换 |
| RDP 通道 | `Core/RDP/Channels/` | 剪贴板、音频转发 |

### MVVM 结构

每个功能模块位于 `Features/` 下，包含:
- `Views/` - SwiftUI 视图
- `ViewModels/` - 业务逻辑（使用 `@Observable` 宏）

三个主要功能模块: ConnectionManager、RemoteDesktop、Settings

### VisionOS 输入映射

| VisionOS 手势 | Windows 操作 |
|--------------|-------------|
| 眼动 + 捏合 | 左键单击 |
| 眼动 + 双捏 | 左键双击 |
| 眼动 + 长捏 | 右键单击 |
| 捏住拖动 | 鼠标拖拽 |
| 双指缩放 | 滚轮滚动 |

## 代码规范

- 使用 Swift 5.9+ 特性: `@Observable`、SwiftData、async/await
- 使用 `@MainActor` 保证 UI 相关操作在主线程
- 密码存储使用 `KeychainService`（不要明文存储）
- 注释使用中文

## 当前开发状态

基础框架已完成，FreeRDPBridge.c 当前为占位实现，需要替换为真实的 FreeRDP API 调用。详见 `ToDo.md`。
