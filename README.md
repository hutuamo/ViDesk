# ViDesk 技术架构文档

## 项目概述

ViDesk 是一个运行在 Apple Vision Pro 上的远程桌面协议 (RDP) 客户端应用。

**技术栈**: visionOS 2.0+ / Swift 5.9+ / SwiftUI / SwiftData / Metal / FreeRDP

---

## 1. 系统架构

### 1.1 整体架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    表现层 (SwiftUI)                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ConnectionList│  │RemoteDesktop│  │  Settings   │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                   业务层 (ViewModels)                        │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │ConnectionManager│  │RemoteDesktopVM  │                   │
│  │    ViewModel    │  │                 │                   │
│  └─────────────────┘  └─────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                     核心层 (Core)                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │RDPSession│  │  Metal   │  │  Input   │  │ Channels │    │
│  │          │  │ Renderer │  │ Manager  │  │          │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                   桥接层 (Bridge)                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              FreeRDPContext.swift                    │   │
│  │         (C 回调 → Swift async/await)                 │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    C 层 (FreeRDP)                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ libfreerdp  │  │  libwinpr   │  │  OpenSSL    │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 目录结构

```
ViDesk/
├── ViDesk/
│   ├── App/                         # 应用入口
│   │   ├── ViDeskApp.swift
│   │   └── ContentView.swift
│   │
│   ├── Features/                    # 功能模块 (MVVM)
│   │   ├── ConnectionManager/
│   │   │   ├── Views/
│   │   │   └── ViewModels/
│   │   ├── RemoteDesktop/
│   │   │   ├── Views/
│   │   │   └── ViewModels/
│   │   └── Settings/
│   │       ├── Views/
│   │       └── ViewModels/
│   │
│   ├── Core/                        # 核心功能
│   │   ├── RDP/
│   │   │   ├── FreeRDPWrapper/      # FreeRDP 封装
│   │   │   └── Channels/            # RDP 通道
│   │   ├── Rendering/               # Metal 渲染
│   │   └── Input/                   # 输入处理
│   │
│   ├── Models/                      # 数据模型
│   ├── Services/                    # 服务层
│   └── Resources/                   # 资源文件
│
└── FreeRDPFramework/                # FreeRDP 静态库
```

---

## 2. 核心模块设计

### 2.1 RDP 协议层

#### FreeRDP 集成架构

```
┌─────────────────────────────────────────────────┐
│              Swift 应用层 (SwiftUI)              │
│  Views ←→ ViewModels ←→ RDPSession              │
└─────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────┐
│            Swift 桥接层                          │
│  FreeRDPContext.swift                           │
│  - 管理 FreeRDP 上下文生命周期                    │
│  - C 回调转换为 Swift async/await                │
│  - 类型安全的 API 封装                           │
└─────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────┐
│            C 桥接层 (Bridging Header)            │
│  FreeRDPBridge.h / FreeRDPBridge.c              │
│  - 定义 ViDeskContext 结构                       │
│  - 实现回调注册和分发                            │
└─────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────┐
│            FreeRDP C 库                          │
│  libfreerdp3 + libwinpr3 + OpenSSL              │
└─────────────────────────────────────────────────┘
```

#### RDPSession 状态机

```
                    ┌─────────────┐
                    │ Disconnected│◄────────────────┐
                    └──────┬──────┘                 │
                           │ connect()              │
                           ▼                        │
                    ┌─────────────┐                 │
                    │ Connecting  │                 │
                    └──────┬──────┘                 │
                           │                        │
                           ▼                        │
                    ┌─────────────┐                 │
             ┌──────│Authenticating│                │
             │      └──────┬──────┘                 │
             │             │ success                │
             │             ▼                        │
             │      ┌─────────────┐   disconnect()  │
             │      │  Connected  │─────────────────┤
             │      └──────┬──────┘                 │
             │             │ connection lost        │
             │             ▼                        │
             │      ┌─────────────┐                 │
             │      │ Reconnecting│─────────────────┤
             │      └─────────────┘  max attempts   │
             │                                      │
             │ auth failed  ┌─────────────┐         │
             └─────────────►│    Error    │─────────┘
                            └─────────────┘
```

### 2.2 渲染管线

#### Metal 渲染流程

```
FreeRDP 解码帧
       │
       ▼
┌─────────────┐
│ FrameBuffer │  CPU 内存中的像素数据
│  (RGBA)     │  支持增量更新 (脏区域)
└──────┬──────┘
       │ copyToTexture()
       ▼
┌─────────────┐
│MTLTexture   │  GPU 纹理
└──────┬──────┘
       │
       ▼
┌─────────────┐
│VertexShader │  顶点变换 + 纹理坐标
└──────┬──────┘
       │
       ▼
┌─────────────┐
│FragmentShader│  纹理采样 + 颜色输出
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  MTKView    │  屏幕显示
└─────────────┘
```

#### 三重缓冲策略

```
┌────────────┐  ┌────────────┐  ┌────────────┐
│ Buffer A   │  │ Buffer B   │  │ Buffer C   │
│ (写入中)    │  │ (待显示)   │  │ (显示中)   │
└────────────┘  └────────────┘  └────────────┘
      │               │               │
      ▼               ▼               ▼
   FreeRDP         渲染器          屏幕
   写入数据        读取渲染        当前帧
```

### 2.3 输入系统

#### VisionOS 手势映射

| VisionOS 手势 | Windows 操作 | 实现类 |
|--------------|-------------|--------|
| 眼动 + 捏合 | 左键单击 | `GestureTranslator` |
| 眼动 + 双捏 | 左键双击 | `GestureTranslator` |
| 眼动 + 长捏 | 右键单击 | `GestureTranslator` |
| 捏住拖动 | 鼠标拖拽 | `GestureTranslator` |
| 双指缩放 | 滚轮滚动 | `GestureTranslator` |
| 物理键盘 | 键盘输入 | `KeyboardMapper` |

#### 输入处理流程

```
VisionOS 手势/键盘事件
         │
         ▼
┌─────────────────┐
│  InputManager   │  统一输入管理
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌────────┐
│Gesture │ │Keyboard│
│Translator│ │Mapper │
└────┬───┘ └────┬───┘
     │          │
     └────┬─────┘
          ▼
┌─────────────────┐
│   RDPSession    │  发送到远程
└─────────────────┘
```

---

## 3. 数据模型

### 3.1 ConnectionConfig (SwiftData)

```swift
@Model
final class ConnectionConfig {
    var id: UUID
    var name: String
    var hostname: String
    var port: Int = 3389
    var username: String
    var credentialKeyRef: String?  // Keychain 引用
    var displaySettingsData: Data? // JSON 编码的 DisplaySettings
    var folderPath: String?
    var lastConnectedAt: Date?
    var createdAt: Date
    var autoReconnect: Bool
    var gatewayHostname: String?
    var useNLA: Bool
    var ignoreCertificateErrors: Bool
}
```

### 3.2 SessionState

```swift
enum SessionState {
    case disconnected
    case connecting
    case authenticating
    case connected
    case reconnecting(attempt: Int)
    case error(RDPError)
}
```

### 3.3 DisplaySettings

```swift
struct DisplaySettings: Codable {
    var width: Int
    var height: Int
    var colorDepth: ColorDepth      // 16/24/32
    var maxFrameRate: Int
    var useHardwareAcceleration: Bool
    var scaleMode: ScaleMode        // fit/fill/native
}
```

---

## 4. 服务层

### 4.1 KeychainService

- 安全存储用户密码
- 使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 保护
- 支持 Face ID 解锁

### 4.2 ConnectionStorageService

- SwiftData 持久化
- CRUD 操作
- 搜索和分组
- 导入/导出功能

---

## 5. 性能优化策略

### 5.1 渲染优化

- **增量更新**: 只更新脏区域，减少纹理传输
- **三重缓冲**: 减少帧间延迟
- **Metal 硬件加速**: GPU 渲染

### 5.2 网络优化

- **压缩**: RemoteFX / GFX 压缩
- **自适应帧率**: 根据网络状况调整

### 5.3 内存优化

- **FrameBufferPool**: 复用缓冲区
- **弱引用**: 避免循环引用

---

## 6. 安全设计

### 6.1 凭证存储

- Keychain 加密存储
- 不在内存中长期保留密码
- 支持生物识别

### 6.2 网络安全

- TLS 加密传输
- NLA (Network Level Authentication)
- 证书验证

---

## 7. 依赖关系

| 依赖 | 版本 | 用途 |
|------|------|------|
| FreeRDP | 3.x | RDP 协议实现 |
| WinPR | 3.x | Windows 可移植运行时 |
| OpenSSL | 3.x | TLS/加密 |
| Metal | visionOS SDK | GPU 渲染 |
| SwiftData | visionOS 2.0+ | 数据持久化 |
