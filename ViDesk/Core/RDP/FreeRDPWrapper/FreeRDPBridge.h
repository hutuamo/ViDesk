#ifndef FreeRDPBridge_h
#define FreeRDPBridge_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// 当未包含 FreeRDP 头文件时使用前向声明
#ifndef FREERDP_TYPES_H
typedef struct rdp_context rdpContext;
typedef struct rdp_freerdp freerdp;
typedef struct rdp_settings rdpSettings;
#endif

// ViDesk 自定义上下文结构
typedef struct {
    rdpContext* rdpCtx;
    void* swiftCallbackContext;

    // 帧缓冲区
    uint8_t* frameBuffer;
    uint32_t frameWidth;
    uint32_t frameHeight;
    uint32_t frameBytesPerPixel;

    // 状态标志
    bool isConnected;
    bool isAuthenticated;
} ViDeskContext;

// 回调函数类型
typedef void (*FrameUpdateCallback)(void* context, int x, int y, int width, int height);
typedef void (*ConnectionStateCallback)(void* context, int state, const char* message);
typedef bool (*AuthenticateCallback)(void* context, char** username, char** password, char** domain);
typedef bool (*VerifyCertificateCallback)(void* context, const char* commonName, const char* subject,
                                          const char* issuer, const char* fingerprint, bool hostMismatch);

// 回调结构
typedef struct {
    FrameUpdateCallback onFrameUpdate;
    ConnectionStateCallback onConnectionStateChanged;
    AuthenticateCallback onAuthenticate;
    VerifyCertificateCallback onVerifyCertificate;
} ViDeskCallbacks;

// === 初始化和清理 ===

/// 创建 ViDesk 上下文
ViDeskContext* viDesk_createContext(void);

/// 销毁上下文
void viDesk_destroyContext(ViDeskContext* ctx);

/// 设置回调函数
void viDesk_setCallbacks(ViDeskContext* ctx, ViDeskCallbacks callbacks, void* swiftContext);

// === 连接配置 ===

/// 设置服务器地址
bool viDesk_setServer(ViDeskContext* ctx, const char* hostname, int port);

/// 设置凭证
bool viDesk_setCredentials(ViDeskContext* ctx, const char* username, const char* password, const char* domain);

/// 设置显示参数
bool viDesk_setDisplay(ViDeskContext* ctx, int width, int height, int colorDepth);

/// 设置性能选项
bool viDesk_setPerformanceFlags(ViDeskContext* ctx, bool enableWallpaper, bool enableFullWindowDrag,
                                 bool enableMenuAnimations, bool enableThemes, bool enableFontSmoothing);

/// 设置安全选项
bool viDesk_setSecurity(ViDeskContext* ctx, bool useNLA, bool useTLS, bool ignoreCertErrors);

/// 设置网关 (可选)
bool viDesk_setGateway(ViDeskContext* ctx, const char* hostname, int port,
                       const char* username, const char* password, const char* domain);

// === 连接管理 ===

/// 发起连接
bool viDesk_connect(ViDeskContext* ctx);

/// 断开连接
void viDesk_disconnect(ViDeskContext* ctx);

/// 检查连接状态
bool viDesk_isConnected(ViDeskContext* ctx);

/// 处理事件循环 (需要在后台线程周期性调用)
bool viDesk_processEvents(ViDeskContext* ctx, int timeoutMs);

// === 输入事件 ===

/// 发送鼠标移动事件
bool viDesk_sendMouseMove(ViDeskContext* ctx, int x, int y);

/// 发送鼠标按钮事件
bool viDesk_sendMouseButton(ViDeskContext* ctx, int button, bool isPressed, int x, int y);

/// 发送鼠标滚轮事件
bool viDesk_sendMouseWheel(ViDeskContext* ctx, int delta, bool isHorizontal);

/// 发送键盘事件
bool viDesk_sendKeyEvent(ViDeskContext* ctx, uint16_t scanCode, bool isPressed, bool isExtended);

/// 发送 Unicode 字符
bool viDesk_sendUnicodeKey(ViDeskContext* ctx, uint16_t codePoint);

// === 剪贴板 ===

/// 设置剪贴板文本
bool viDesk_setClipboardText(ViDeskContext* ctx, const char* text);

/// 获取剪贴板文本 (调用者需要释放返回的字符串)
char* viDesk_getClipboardText(ViDeskContext* ctx);

/// 释放字符串内存
void viDesk_freeString(char* str);

// === 帧缓冲区访问 ===

/// 获取帧缓冲区指针
const uint8_t* viDesk_getFrameBuffer(ViDeskContext* ctx);

/// 获取帧缓冲区尺寸
void viDesk_getFrameSize(ViDeskContext* ctx, uint32_t* width, uint32_t* height);

/// 获取帧缓冲区每像素字节数
uint32_t viDesk_getFrameBytesPerPixel(ViDeskContext* ctx);

// === 日志 ===

/// 设置日志文件路径（同时输出到 stdout 和文件）
void viDesk_setLogFile(const char* path);

// === 调试和统计 ===

/// 获取最后错误消息
const char* viDesk_getLastError(ViDeskContext* ctx);

/// 获取连接统计信息
void viDesk_getStatistics(ViDeskContext* ctx, uint64_t* bytesReceived, uint64_t* bytesSent,
                          uint32_t* frameRate, uint32_t* latencyMs);

#ifdef __cplusplus
}
#endif

#endif /* FreeRDPBridge_h */
