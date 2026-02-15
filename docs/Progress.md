# ViDesk 开发进展

## 项目状态: RDP 连接成功，远程画面可显示

**最后更新**: 2026-02-16

---

## 已完成模块

### 1. 项目结构 ✅

- [x] 创建完整的目录结构
- [x] 配置 Bridging Header
- [x] 创建 FreeRDP Framework 模块映射
- [x] 资源文件配置 (Info.plist, Assets.xcassets)

### 2. Xcode 项目 ✅ (新完成)

- [x] 使用 xcodegen 创建 project.yml
- [x] 生成 ViDesk.xcodeproj
- [x] 配置 Bundle Identifier: com.videsk.app
- [x] 配置 visionOS 2.0 部署目标
- [x] 配置 FreeRDP 库链接
- [x] 配置头文件搜索路径

### 3. FreeRDP 编译 ✅ (新完成)

**OpenSSL 3.2.1 for visionOS Simulator:**
- [x] 配置交叉编译环境
- [x] 编译 libcrypto.a (7.5MB)
- [x] 编译 libssl.a (1.4MB)

**FreeRDP 3.10.3 for visionOS Simulator:**
- [x] 克隆 FreeRDP 源码
- [x] 创建 visionOS 交叉编译脚本
- [x] 禁用不支持的功能 (opus, Carbon, CoreAudio)
- [x] 编译 libwinpr3.a (1.9MB)
- [x] 编译 libfreerdp3.a (6.4MB)
- [x] 编译 libfreerdp-client3.a (1.4MB)
- [x] 复制库文件到 FreeRDPFramework/lib/
- [x] 复制头文件到 FreeRDPFramework/include/

**编译脚本位置:**
- `build-deps/build-openssl-visionos.sh`
- `build-deps/build-freerdp-visionos.sh`

### 4. 数据模型层 ✅

| 文件 | 状态 | 说明 |
|------|------|------|
| `ConnectionConfig.swift` | ✅ 完成 | SwiftData 模型，支持完整连接配置 |
| `SessionState.swift` | ✅ 完成 | 会话状态枚举 + RDPError 错误类型 |
| `DisplaySettings.swift` | ✅ 完成 | 显示设置，支持分辨率/色深/缩放模式 |

### 5. FreeRDP 桥接层 ✅ (新完成)

| 文件 | 状态 | 说明 |
|------|------|------|
| `FreeRDPBridge.h` | ✅ 完成 | C API 头文件，定义所有接口 |
| `FreeRDPBridge.c` | ✅ 完成 | 真实 FreeRDP API 调用实现 |
| `iOSPathHelpers.m` | ✅ 完成 | iOS/visionOS 路径辅助函数 |
| `FreeRDPContext.swift` | ✅ 完成 | Swift 封装，类型安全 API |

**FreeRDPBridge.c 实现内容**:
- `viDesk_createContext()`: 使用 `freerdp_client_context_new()` (非 `freerdp_context_new()`)
- `viDesk_connect()`: 调用 `freerdp_connect()`
- `viDesk_disconnect()`: 调用 `freerdp_disconnect()`
- `viDesk_processEvents()`: 使用 `freerdp_get_event_handles()` 和 `freerdp_check_event_handles()`
- 回调实现: PreConnect, PostConnect, PostDisconnect, EndPaint, DesktopResize
- 通道加载: 自定义 `viDesk_LoadChannels` 显式加载 DRDYNVC SVC
- GFX 管道: PubSub ChannelConnected 事件订阅 → `gdi_graphics_pipeline_init()`
- 证书验证: `viDesk_VerifyCertificateEx`
- 认证回调: `viDesk_Authenticate`
- 输入事件: `freerdp_input_send_mouse_event()`, `freerdp_input_send_keyboard_event()`
- GDI 初始化: 使用 PIXEL_FORMAT_BGRA32

### 6. RDP 会话管理 ✅

| 文件 | 状态 | 说明 |
|------|------|------|
| `RDPSession.swift` | ✅ 完成 | 完整会话生命周期管理 |

**功能**:
- 连接/断开/重连
- 自动重连 (最多 3 次)
- 输入事件转发
- 特殊按键支持 (Ctrl+Alt+Del, Alt+Tab 等)
- 剪贴板同步
- 会话统计

### 7. Metal 渲染系统 ✅

| 文件 | 状态 | 说明 |
|------|------|------|
| `FrameBuffer.swift` | ✅ 完成 | 帧缓冲管理，支持脏区域更新 |
| `MetalRenderer.swift` | ✅ 完成 | Metal 渲染器，支持多种缩放模式 |
| `DesktopShaders.metal` | ✅ 完成 | GPU 着色器 (基础/YUV/光标叠加/双三次插值) |
| `DesktopCanvasView.swift` | ✅ 完成 | Metal 渲染画布 + 模拟器占位视图 |

**特性**:
- 增量纹理更新
- 视图坐标到纹理坐标转换
- 三重缓冲池
- visionOS 模拟器兼容 (Metal 不可用时显示占位界面)

### 8. 输入处理系统 ✅

| 文件 | 状态 | 说明 |
|------|------|------|
| `InputManager.swift` | ✅ 完成 | 统一输入管理器 |
| `GestureTranslator.swift` | ✅ 完成 | VisionOS 手势翻译 |
| `KeyboardMapper.swift` | ✅ 完成 | macOS/visionOS 键码映射到 Windows 扫描码 (已修复重复键) |

**手势支持**:
- 单击/双击/长按
- 拖拽
- 缩放 (映射为滚轮)
- VisionOS SpatialTapGesture

### 9. 服务层 ✅

| 文件 | 状态 | 说明 |
|------|------|------|
| `KeychainService.swift` | ✅ 完成 | 密码安全存储 |
| `ConnectionStorageService.swift` | ✅ 完成 | SwiftData CRUD + 搜索 + 导入导出 |

### 10. RDP 通道 ✅

| 文件 | 状态 | 说明 |
|------|------|------|
| `ClipboardChannel.swift` | ✅ 完成 | 剪贴板同步 |
| `AudioChannel.swift` | ✅ 完成 | 音频转发 (AVAudioEngine) |

### 11. 用户界面 ✅

#### 连接管理模块

| 文件 | 状态 | 说明 |
|------|------|------|
| `ConnectionManagerViewModel.swift` | ✅ 完成 | 连接列表业务逻辑 |
| `ConnectionListView.swift` | ✅ 完成 | 主列表界面 |
| `ConnectionCardView.swift` | ✅ 完成 | 连接卡片组件 |
| `AddConnectionView.swift` | ✅ 完成 | 添加/编辑连接表单 (已修复输入问题) |

**功能**:
- 快速连接
- 保存的连接列表
- 最近使用
- 搜索
- 编辑/删除/复制

#### 远程桌面模块

| 文件 | 状态 | 说明 |
|------|------|------|
| `RemoteDesktopViewModel.swift` | ✅ 完成 | 远程桌面业务逻辑 |
| `RemoteDesktopView.swift` | ✅ 完成 | 远程桌面主视图 |
| `DesktopCanvasView.swift` | ✅ 完成 | Metal 渲染画布 |
| `SessionToolbarView.swift` | ✅ 完成 | 会话工具栏 (Ornament 风格) |

**功能**:
- Metal 渲染
- 手势识别
- 虚拟键盘
- 剪贴板操作
- 全屏模式
- 会话统计显示

#### 设置模块

| 文件 | 状态 | 说明 |
|------|------|------|
| `SettingsViewModel.swift` | ✅ 完成 | 设置业务逻辑 + 持久化 |
| `SettingsView.swift` | ✅ 完成 | 设置界面 |

**设置项**:
- 显示: 分辨率/色深/缩放/帧率
- 输入: 输入模式/滚动速度/键盘布局
- 安全: 保存密码/生物识别/自动锁定
- 高级: 硬件加速/日志

### 12. 应用入口 ✅

| 文件 | 状态 | 说明 |
|------|------|------|
| `ViDeskApp.swift` | ✅ 完成 | @main 入口，Scene 配置 |
| `ContentView.swift` | ✅ 完成 | 主内容视图，TabView 布局 |

---

## 本次会话修复的问题

| 问题 | 修复 |
|------|------|
| TextField 无法输入 | 移除 `.textContentType` 和 `.keyboardType` 修饰符 |
| KeyboardMapper 重复键崩溃 | 修复 `0x24` 和 `0x28` 的重复定义 |
| Metal 渲染器崩溃 | 添加 Metal 不可用时的占位视图 |
| visionOS 模拟器兼容 | MetalRenderer 在 pipeline 未准备好时清空屏幕 |
| FreeRDPBridge.h 前向声明冲突 | 使用条件编译避免与 FreeRDP 头文件冲突 |
| 缺少 settings_keys.h | 复制 FreeRDP 编译生成的配置头文件 |
| 缺少 cJSON 库 | 编译 cJSON 为 visionOS Simulator 静态库 |
| 缺少 ios_get_* 函数 | 创建 iOSPathHelpers.m 实现 iOS 路径辅助函数 |
| ios_get_* 内存管理崩溃 | 改用 `strdup()` 返回动态分配内存，FreeRDP 会负责释放 |
| 错误界面按钮无响应 | 重构 RemoteDesktopView，错误状态时不渲染 DesktopCanvasView |
| PreConnect 配置不完整 | 增强安全协商、超时、压缩等配置项 |
| 工具栏/虚拟键盘按钮无响应 | ToolbarButton 改用 `.borderless` 样式 + `.contentShape(Rectangle())` 增加点击区域；添加 `.zIndex` 和 `.allowsHitTesting(true)` 确保层级正确 |
| 自签名证书验证失败 | 添加 `VerifyChangedCertificateEx` 回调；启用 `FreeRDP_AutoAcceptCertificate`；增强 PreConnect 安全配置 |

---

## 文件统计

```
Swift 源文件:    26 个
C/Objective-C:   3 个 (FreeRDPBridge.h, FreeRDPBridge.c, iOSPathHelpers.m)
Metal Shader:    1 个
配置文件:        6 个 (project.yml, Info.plist, Assets 等)
编译脚本:        2 个 (build-openssl-visionos.sh, build-freerdp-visionos.sh)
```

---

## 编译产物

### FreeRDPFramework/lib/
```
libcrypto.a         7.5MB
libssl.a            1.4MB
libwinpr3.a         1.9MB
libfreerdp3.a       6.4MB
libfreerdp-client3.a 1.4MB
libcjson.a          30KB
```

---

## 代码质量

- [x] 使用 `@Observable` 宏 (Swift 5.9+)
- [x] 使用 SwiftData
- [x] 使用 async/await
- [x] 使用 `@MainActor` 保证主线程安全
- [x] 中文注释
- [x] MVVM 架构
- [x] visionOS 模拟器兼容

---

## 测试状态

| 测试项 | 状态 |
|--------|------|
| Xcode 项目编译 | ✅ 通过 |
| FreeRDP 真实实现编译 | ✅ 通过 |
| visionOS 模拟器启动 | ✅ 通过 |
| 连接列表界面 | ✅ 通过 |
| 快速连接输入 | ✅ 通过 |
| RDP 连接 (GNOME Remote Desktop) | ✅ 通过 |
| 远程画面显示 | ✅ 通过 (GFX 管道 + 分辨率调整) |
| 错误界面按钮响应 | ✅ 通过 (已修复) |
| 鼠标/键盘输入 | ⏳ 待测试 |
| 剪贴板同步 | ⏳ 待测试 |
| Windows RDP 连接 | ⏳ 待测试 |

---

## 当前已知问题

| 问题 | 状态 | 说明 |
|------|------|------|
| ~~RDP 连接失败~~ | ✅ 已修复 | DRDYNVC/GFX 通道 + 桌面分辨率回调 |
| 仅支持模拟器 | ⏳ 待处理 | 需要编译 visionOS device 版本库 |
| 音频通道禁用 | ⏳ 待处理 | visionOS 不支持 CoreAudio |
| 手势未真机测试 | ⏳ 待处理 | 需要 Vision Pro 真机 |
| 无 H.264 支持 | ⏳ 待处理 | WITH_GFX_H264=OFF |
