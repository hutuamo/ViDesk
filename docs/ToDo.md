# ViDesk 待办事项

## 优先级说明

- **P0**: 阻塞性任务，必须完成才能运行
- **P1**: 核心功能，应用可用性必需
- **P2**: 增强功能，提升用户体验
- **P3**: 优化改进，可延后处理

---

## P0 - 阻塞性任务

### 1. ~~创建 Xcode 项目~~ ✅ 已完成

```
[x] 使用 xcodegen 创建 project.yml
[x] 生成 ViDesk.xcodeproj
[x] 配置 Bundle Identifier: com.videsk.app
[x] 配置 visionOS 2.0 部署目标
[x] 配置 FreeRDP 库链接
```

### 2. ~~编译 FreeRDP 库~~ ✅ 已完成

```
[x] 获取 FreeRDP 3.10.3 源码
[x] 配置 visionOS Simulator 交叉编译环境
[x] 编译 OpenSSL 3.2.1 (libcrypto.a, libssl.a)
[x] 编译 libwinpr3.a
[x] 编译 libfreerdp3.a
[x] 编译 libfreerdp-client3.a
[x] 将静态库放入 FreeRDPFramework/lib/
[x] 将头文件放入 FreeRDPFramework/include/
```

### 3. ~~完成 FreeRDPBridge.c 真实实现~~ ✅ 已完成

`FreeRDPBridge.c` 已替换为真实的 FreeRDP API 调用:

```
[x] viDesk_createContext(): 调用 freerdp_new() 和 freerdp_context_new()
[x] viDesk_connect(): 调用 freerdp_connect()
[x] viDesk_disconnect(): 调用 freerdp_disconnect()
[x] viDesk_processEvents(): 实现事件循环 (freerdp_check_event_handles)
[x] 实现帧更新回调 (PostConnect, EndPaint)
[x] 实现输入事件发送 (freerdp_input_send_*)
[x] 编译 cJSON 库依赖
[x] 实现 iOS 路径辅助函数 (iOSPathHelpers.m)
[x] 修复 ios_get_* 内存管理 (使用 strdup)
[x] 增强 PreConnect 配置 (安全协商、超时、压缩)
[x] 修复错误界面按钮响应问题
[ ] 调试连接失败: "transport layer failed"
[ ] 实现剪贴板通道 (cliprdr) - 待后续完善
```

---

## P1 - 核心功能

### 4. 编译 visionOS Device 版本 ⏳

```
[ ] 修改编译脚本支持 arm64 device (非 simulator)
[ ] 编译 OpenSSL for visionOS device
[ ] 编译 FreeRDP for visionOS device
[ ] 创建 Universal 静态库 (simulator + device)
```

### 5. 完善 Metal 渲染 ⏳

```
[ ] 在真机上测试 Metal 渲染
[ ] 测试不同分辨率渲染
[ ] 测试增量更新性能
[ ] 优化纹理上传 (使用 MTLBlitCommandEncoder)
[ ] 添加 YUV 到 RGB 转换 (如果 FreeRDP 输出 YUV)
```

### 6. 完善 VisionOS 手势 ⏳

```
[ ] 测试眼动追踪 + 捏合手势 (需要真机)
[ ] 优化手势识别灵敏度
[ ] 添加手势反馈 (触觉反馈)
[ ] 测试与虚拟键盘的配合
```

### 7. 网络功能 ⏳

```
[ ] 实现网络状态监听
[ ] 实现自动重连逻辑
[ ] 添加连接超时处理
[ ] 实现 RD Gateway 支持
```

### 8. 证书验证 ⏳

```
[ ] 实现证书验证回调
[ ] 显示证书信息对话框
[ ] 支持保存受信任的证书
```

---

## P2 - 增强功能

### 9. 沉浸式模式 (VisionOS) ⏳

```
[ ] 实现 ImmersiveSpace 场景
[ ] 使用 RealityKit 渲染 3D 桌面
[ ] 支持窗口大小调整
[ ] 支持多显示器布局
```

### 10. 音频转发 ⏳

```
[ ] 集成 FreeRDP 音频通道 (需要重新编译启用音频)
[ ] 测试音频延迟
[ ] 实现音量控制
[ ] 支持音频重定向方向设置
```

**注意:** 当前编译禁用了音频通道 (CoreAudio 在 visionOS 上不可用)，需要研究替代方案。

### 11. 文件传输 ⏳

```
[ ] 实现 RDPDR (设备重定向) 通道
[ ] 支持文件拖放上传
[ ] 支持文件下载
[ ] 实现传输进度显示
```

### 12. 打印重定向 ⏳

```
[ ] 实现打印通道
[ ] 集成 iOS 打印框架
```

### 13. 多会话支持 ⏳

```
[ ] 支持同时连接多个远程桌面
[ ] 实现会话切换 UI
[ ] 优化多会话内存管理
```

### 14. 连接导入/导出 ⏳

```
[ ] 支持 .rdp 文件导入
[ ] 支持 .rdp 文件导出
[ ] 支持批量导入
[ ] 实现 iCloud 同步
```

---

## P3 - 优化改进

### 15. 性能优化 ⏳

```
[ ] 分析渲染帧率
[ ] 优化输入延迟
[ ] 减少内存占用
[ ] 优化电池消耗
```

### 16. 可访问性 ⏳

```
[ ] 添加 VoiceOver 支持
[ ] 添加动态字体支持
[ ] 高对比度模式
```

### 17. 国际化 ⏳

```
[ ] 提取所有字符串到 Localizable.strings
[ ] 添加英文翻译
[ ] 添加其他语言支持
```

### 18. 测试 ⏳

```
[ ] 编写单元测试
[ ] 编写 UI 测试
[ ] 性能测试
[ ] Vision Pro 真机测试
```

### 19. 文档 ⏳

```
[ ] 编写用户使用指南
[ ] 编写 API 文档
[ ] 录制演示视频
```

---

## 已知问题

| 问题 | 状态 | 说明 |
|------|------|------|
| ~~FreeRDP 桥接层是占位实现~~ | ✅ 已完成 | FreeRDP 真实 API 调用已实现 |
| ~~ios_get_* 内存管理~~ | ✅ 已修复 | 改用 strdup() 返回动态分配内存 |
| ~~错误界面按钮无响应~~ | ✅ 已修复 | 重构视图，错误时不渲染 canvas |
| ~~工具栏/虚拟键盘按钮无响应~~ | ✅ 已修复 | 改用 borderless 样式 + zIndex + allowsHitTesting |
| RDP 连接失败 | ⏳ 调试中 | "transport layer failed"，可能是模拟器网络限制 |
| 音频通道禁用 | ⏳ | visionOS 不支持 CoreAudio |
| 仅支持模拟器 | ⏳ | 需要编译 device 版本库 |
| 手势未真机测试 | ⏳ | 需要 Vision Pro 真机 |

---

## 里程碑

### v0.1.0 - 基础可用版本 (当前目标)
- [x] Xcode 项目创建
- [x] FreeRDP 库编译 (simulator)
- [x] UI 框架完成
- [x] **FreeRDPBridge.c 真实实现** ✅
- [x] **ios_get_* 内存管理修复** ✅
- [x] **错误界面按钮响应修复** ✅
- [ ] 调试 RDP 连接失败 (transport layer failed) ← **下一步**
- [ ] 能够连接到 Windows 远程桌面
- [ ] 能够看到远程画面
- [ ] 能够使用手势操作
- [ ] 能够使用键盘输入

### v0.2.0 - 功能完善版本
- [ ] 音频转发
- [ ] 剪贴板同步
- [ ] 自动重连
- [ ] 设置持久化
- [ ] visionOS device 支持

### v1.0.0 - 正式发布版本
- [ ] 完整的 VisionOS 体验
- [ ] 沉浸式模式
- [ ] 多会话支持
- [ ] App Store 发布

---

## 参考资源

- [FreeRDP GitHub](https://github.com/FreeRDP/FreeRDP)
- [FreeRDP iOS 编译指南](https://github.com/AktivCo/FreeRDP)
- [FreeRDP API 文档](https://pub.freerdp.com/api/)
- [visionOS 文档](https://developer.apple.com/visionos/)
- [Metal 最佳实践](https://developer.apple.com/metal/)
- [SwiftData 文档](https://developer.apple.com/documentation/swiftdata)

---

## 下一步

调试 RDP 连接失败问题 ("The connection transport layer failed"):

1. **可能原因分析**:
   - visionOS 模拟器网络沙箱限制
   - FreeRDP 配置参数不完整
   - TCP 连接被模拟器阻止

2. **调试方向**:
   - 在 FreeRDPBridge.c 中添加更多日志输出
   - 检查 FreeRDP 错误码和详细错误信息
   - 尝试编译 visionOS device 版本并在真机测试
   - 对比其他平台 (iOS/macOS) 的 FreeRDP 配置

3. **测试需要**:
   - 有一个可访问的 Windows 远程桌面服务器
   - 确保网络连接正常 (已验证: macOS RDP 客户端可以连接)
   - 验证用户名/密码正确
