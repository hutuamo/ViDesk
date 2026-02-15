/**
 * FreeRDPBridge.c - FreeRDP 桥接层实现
 * 将 FreeRDP C API 封装为 ViDesk 使用的接口
 */

#include "FreeRDPBridge.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <time.h>

// FreeRDP 头文件
#include <freerdp/freerdp.h>
#include <freerdp/client/cmdline.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/gdi/gfx.h>
#include <freerdp/channels/channels.h>
#include <freerdp/client/channels.h>
#include <freerdp/input.h>
#include <freerdp/settings.h>
#include <freerdp/log.h>

#include <winpr/crt.h>
#include <winpr/synch.h>
#include <winpr/thread.h>

#define TAG "viDesk"

// === 日志系统 ===
static FILE* g_logFile = NULL;

void viDesk_setLogFile(const char* path) {
    if (g_logFile) {
        fclose(g_logFile);
        g_logFile = NULL;
    }
    if (path) {
        g_logFile = fopen(path, "a");
    }
}

static void viDesk_log(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);

    if (g_logFile) {
        va_start(args, format);
        vfprintf(g_logFile, format, args);
        va_end(args);
        fflush(g_logFile);
    }
}

// 扩展上下文结构 - 继承 rdpClientContext
typedef struct {
    rdpClientContext common;  // 必须在第一位

    // ViDesk 上下文指针
    ViDeskContext* viDeskCtx;
} ViDeskClientContext;

// 全局回调
static ViDeskCallbacks g_callbacks = {0};
static char* g_lastError = NULL;

// 辅助函数
static void setLastError(const char* error) {
    if (g_lastError) {
        free(g_lastError);
        g_lastError = NULL;
    }
    if (error) {
        g_lastError = _strdup(error);
    }
}

static void notifyStateChange(ViDeskContext* ctx, int state, const char* message) {
    if (g_callbacks.onConnectionStateChanged && ctx && ctx->swiftCallbackContext) {
        g_callbacks.onConnectionStateChanged(ctx->swiftCallbackContext, state, message);
    }
}

static void notifyFrameUpdate(ViDeskContext* ctx, int x, int y, int width, int height) {
    if (g_callbacks.onFrameUpdate && ctx && ctx->swiftCallbackContext) {
        g_callbacks.onFrameUpdate(ctx->swiftCallbackContext, x, y, width, height);
    }
}

// FreeRDP 回调 - PreConnect
static BOOL viDesk_PreConnect(freerdp* instance) {
    if (!instance || !instance->context)
        return FALSE;

    rdpSettings* settings = instance->context->settings;
    if (!settings)
        return FALSE;

    viDesk_log("[ViDesk] PreConnect 开始配置...\n");

    // 配置 GDI
    if (!freerdp_settings_set_bool(settings, FreeRDP_SoftwareGdi, TRUE))
        return FALSE;

    // 设置颜色深度
    if (!freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32))
        return FALSE;

    // 异步通道配置
    freerdp_settings_set_bool(settings, FreeRDP_AsyncChannels, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_AsyncUpdate, FALSE);

    // 超时设置 (毫秒)
    freerdp_settings_set_uint32(settings, FreeRDP_TcpConnectTimeout, 30000);

    // === 证书验证配置 (开发阶段自动接受) ===
    freerdp_settings_set_bool(settings, FreeRDP_IgnoreCertificate, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_AutoAcceptCertificate, TRUE);

    // === 压缩和性能优化 ===
    freerdp_settings_set_bool(settings, FreeRDP_FastPathOutput, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_FastPathInput, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_CompressionEnabled, TRUE);

    // === xrdp 兼容性配置 ===
    // 禁用网络自动检测 - xrdp 不支持，会导致 messageChannelId 错位
    freerdp_settings_set_bool(settings, FreeRDP_NetworkAutoDetect, FALSE);

    // 禁用心跳 PDU - 与 NetworkAutoDetect 共用 message channel，一起禁用避免 channel ID 错位
    freerdp_settings_set_bool(settings, FreeRDP_SupportHeartbeatPdu, FALSE);

    // 禁用 GFX 图形管线 - xrdp 不支持 RDP 8.0+ 图形管线
    freerdp_settings_set_bool(settings, FreeRDP_SupportGraphicsPipeline, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxThinClient, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxSmallCache, FALSE);

    // 禁用显示器布局 PDU - xrdp 不支持动态显示器变更
    freerdp_settings_set_bool(settings, FreeRDP_SupportMonitorLayoutPdu, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_SupportMultitransport, FALSE);

    // xrdp 在未宣告 CAPSTYPE_GLYPHCACHE 能力的情况下使用 glyph cache 命令
    // 需要放宽检查，否则 FreeRDP 3.x 严格模式会拒绝
    freerdp_settings_set_bool(settings, FreeRDP_AllowUnanouncedOrdersFromServer, TRUE);
    freerdp_settings_set_uint32(settings, FreeRDP_GlyphSupportLevel, 2);

    // 禁用 FreeRDP 内部自动重连，由应用层控制重连逻辑
    freerdp_settings_set_bool(settings, FreeRDP_AutoReconnectionEnabled, FALSE);

    // === 协议兼容性配置 ===
    freerdp_settings_set_bool(settings, FreeRDP_SupportErrorInfoPdu, TRUE);

    // 打印当前安全设置
    BOOL nla = freerdp_settings_get_bool(settings, FreeRDP_NlaSecurity);
    BOOL tls = freerdp_settings_get_bool(settings, FreeRDP_TlsSecurity);
    BOOL rdp = freerdp_settings_get_bool(settings, FreeRDP_RdpSecurity);
    viDesk_log("[ViDesk] 安全协议: NLA=%d, TLS=%d, RDP=%d\n", nla, tls, rdp);

    // 验证 xrdp 兼容设置
    viDesk_log("[ViDesk] PreConnect 验证: AutoDetect=%d, Heartbeat=%d, GFX=%d, GlyphLevel=%u, AllowUnannounced=%d\n",
        freerdp_settings_get_bool(settings, FreeRDP_NetworkAutoDetect),
        freerdp_settings_get_bool(settings, FreeRDP_SupportHeartbeatPdu),
        freerdp_settings_get_bool(settings, FreeRDP_SupportGraphicsPipeline),
        freerdp_settings_get_uint32(settings, FreeRDP_GlyphSupportLevel),
        freerdp_settings_get_bool(settings, FreeRDP_AllowUnanouncedOrdersFromServer));

    viDesk_log("[ViDesk] PreConnect 配置完成\n");

    return TRUE;
}

// FreeRDP 回调 - PostConnect
static BOOL viDesk_PostConnect(freerdp* instance) {
    if (!instance || !instance->context)
        return FALSE;

    rdpContext* context = instance->context;
    ViDeskClientContext* viCtx = (ViDeskClientContext*)context;
    ViDeskContext* ctx = viCtx->viDeskCtx;

    // 初始化 GDI
    if (!gdi_init(instance, PIXEL_FORMAT_BGRA32))
        return FALSE;

    rdpGdi* gdi = context->gdi;
    if (!gdi)
        return FALSE;

    // 更新帧缓冲区信息
    if (ctx) {
        ctx->frameWidth = gdi->width;
        ctx->frameHeight = gdi->height;
        ctx->frameBytesPerPixel = 4;  // BGRA32
        ctx->frameBuffer = gdi->primary_buffer;
        ctx->isConnected = TRUE;
        ctx->isAuthenticated = TRUE;

        notifyStateChange(ctx, 3, "Connected");  // 3 = connected
    }

    // GFX 图形管线初始化需要正确配置的通道，暂不使用

    return TRUE;
}

// FreeRDP 回调 - PostDisconnect
static void viDesk_PostDisconnect(freerdp* instance) {
    if (!instance || !instance->context)
        return;

    ViDeskClientContext* viCtx = (ViDeskClientContext*)instance->context;
    ViDeskContext* ctx = viCtx ? viCtx->viDeskCtx : NULL;

    // 清理 GDI
    gdi_free(instance);

    if (ctx) {
        ctx->isConnected = FALSE;
        ctx->isAuthenticated = FALSE;
        ctx->frameBuffer = NULL;

        notifyStateChange(ctx, 0, "Disconnected");  // 0 = disconnected
    }
}

// FreeRDP 回调 - EndPaint (帧更新)
static BOOL viDesk_EndPaint(rdpContext* context) {
    if (!context || !context->gdi)
        return FALSE;

    rdpGdi* gdi = context->gdi;
    ViDeskClientContext* viCtx = (ViDeskClientContext*)context;
    ViDeskContext* ctx = viCtx ? viCtx->viDeskCtx : NULL;

    if (ctx && gdi->primary->hdc->hwnd->invalid->null == FALSE) {
        int x = gdi->primary->hdc->hwnd->invalid->x;
        int y = gdi->primary->hdc->hwnd->invalid->y;
        int w = gdi->primary->hdc->hwnd->invalid->w;
        int h = gdi->primary->hdc->hwnd->invalid->h;

        // 更新帧缓冲区指针
        ctx->frameBuffer = gdi->primary_buffer;

        // 通知更新区域
        notifyFrameUpdate(ctx, x, y, w, h);
    }

    return TRUE;
}

// 证书验证回调 - 自动接受（用于开发）
static DWORD viDesk_VerifyCertificateEx(freerdp* instance, const char* host, UINT16 port,
                                         const char* common_name, const char* subject,
                                         const char* issuer, const char* fingerprint, DWORD flags) {
    (void)host;
    (void)port;
    (void)flags;

    ViDeskClientContext* viCtx = (ViDeskClientContext*)instance->context;
    ViDeskContext* ctx = viCtx ? viCtx->viDeskCtx : NULL;

    viDesk_log("[ViDesk] 证书验证: CN=%s, Subject=%s, Issuer=%s\n",
           common_name ? common_name : "N/A",
           subject ? subject : "N/A",
           issuer ? issuer : "N/A");
    viDesk_log("[ViDesk] 证书指纹: %s\n", fingerprint ? fingerprint : "N/A");

    // 如果配置了忽略证书错误，自动接受
    rdpSettings* settings = instance->context->settings;
    if (settings && freerdp_settings_get_bool(settings, FreeRDP_IgnoreCertificate)) {
        viDesk_log("[ViDesk] 自动接受证书 (IgnoreCertificate=TRUE)\n");
        return 1;  // 1 = 永久接受, 2 = 本次会话接受
    }

    // 调用 Swift 回调
    if (g_callbacks.onVerifyCertificate && ctx && ctx->swiftCallbackContext) {
        BOOL hostMismatch = (flags & VERIFY_CERT_FLAG_MISMATCH) != 0;
        BOOL accepted = g_callbacks.onVerifyCertificate(ctx->swiftCallbackContext,
            common_name, subject, issuer, fingerprint, hostMismatch);
        return accepted ? 1 : 0;
    }

    // 默认接受证书（开发阶段）
    viDesk_log("[ViDesk] 默认接受证书\n");
    return 1;
}

// 证书变更回调 - 当服务器证书与之前存储的不同时调用
static DWORD viDesk_VerifyChangedCertificateEx(freerdp* instance, const char* host, UINT16 port,
                                                const char* common_name, const char* subject,
                                                const char* issuer, const char* new_fingerprint,
                                                const char* old_subject, const char* old_issuer,
                                                const char* old_fingerprint, DWORD flags) {
    (void)host;
    (void)port;
    (void)old_subject;
    (void)old_issuer;
    (void)flags;

    viDesk_log("[ViDesk] 证书已变更!\n");
    viDesk_log("[ViDesk] 旧指纹: %s\n", old_fingerprint ? old_fingerprint : "N/A");
    viDesk_log("[ViDesk] 新指纹: %s\n", new_fingerprint ? new_fingerprint : "N/A");
    viDesk_log("[ViDesk] CN=%s, Subject=%s, Issuer=%s\n",
           common_name ? common_name : "N/A",
           subject ? subject : "N/A",
           issuer ? issuer : "N/A");

    // 如果配置了忽略证书错误，自动接受
    rdpSettings* settings = instance->context->settings;
    if (settings && freerdp_settings_get_bool(settings, FreeRDP_IgnoreCertificate)) {
        viDesk_log("[ViDesk] 自动接受变更的证书 (IgnoreCertificate=TRUE)\n");
        return 1;
    }

    // 默认接受变更的证书（开发阶段）
    viDesk_log("[ViDesk] 默认接受变更的证书\n");
    return 1;
}

// 扩展认证回调（优先使用，支持 NLA）
static BOOL viDesk_AuthenticateEx(freerdp* instance, char** username, char** password, char** domain, rdp_auth_reason reason) {
    ViDeskClientContext* viCtx = (ViDeskClientContext*)instance->context;
    ViDeskContext* ctx = viCtx ? viCtx->viDeskCtx : NULL;

    viDesk_log("[ViDesk] AuthenticateEx 回调被调用 (原因: %s)\n", reason);
    viDesk_log("[ViDesk] 用户名: %s\n", username && *username ? *username : "(空)");
    viDesk_log("[ViDesk] 域: %s\n", domain && *domain ? *domain : "(空)");

    // 从 settings 中读取已设置的凭证
    rdpSettings* settings = instance->context->settings;
    const char* settingsUsername = NULL;
    const char* settingsPassword = NULL;
    const char* settingsDomain = NULL;
    
    if (settings) {
        settingsUsername = freerdp_settings_get_string(settings, FreeRDP_Username);
        settingsPassword = freerdp_settings_get_string(settings, FreeRDP_Password);
        settingsDomain = freerdp_settings_get_string(settings, FreeRDP_Domain);        
        viDesk_log("[ViDesk] Settings中的用户名: %s\n", settingsUsername ? settingsUsername : "(空)");
        viDesk_log("[ViDesk] Settings中的密码长度: %d\n", settingsPassword ? (int)strlen(settingsPassword) : 0);
        viDesk_log("[ViDesk] Settings中的域: %s\n", settingsDomain ? settingsDomain : "(空)");
    }

    // 调用 Swift 回调（如果设置了）
    BOOL result = TRUE;
    if (g_callbacks.onAuthenticate && ctx && ctx->swiftCallbackContext) {
        result = g_callbacks.onAuthenticate(ctx->swiftCallbackContext, username, password, domain);
    } else {
        // 如果没有设置 Swift 回调，从 settings 中更新指针
        // 这是关键修复：FreeRDP 需要指针指向有效的字符串
        if (settingsUsername && username) {
            // 释放旧的内存（如果存在）
            if (*username) {
                free(*username);
            }
            *username = _strdup(settingsUsername);
            viDesk_log("[ViDesk] 更新用户名指针: %s\n", *username);
        }
        
        if (settingsPassword && password) {
            // 释放旧的内存（如果存在）
            if (*password) {
                free(*password);
            }
            *password = _strdup(settingsPassword);
            viDesk_log("[ViDesk] 更新密码指针 (长度: %d)\n", (int)strlen(*password));
        }
        
        if (settingsDomain && domain) {
            // 释放旧的内存（如果存在）
            if (*domain) {
                free(*domain);
            }
            *domain = settingsDomain ? _strdup(settingsDomain) : NULL;
            if (*domain) {
                viDesk_log("[ViDesk] 更新域指针: %s\n", *domain);
            }
        }    }    
    // 验证凭证是否有效
    if (result && (!username || !*username || !password || !*password)) {
        viDesk_log("[ViDesk] 警告: AuthenticateEx 回调返回 TRUE，但凭证为空\n");    }
    
    return result;
}

// 认证回调（向后兼容）
static BOOL viDesk_Authenticate(freerdp* instance, char** username, char** password, char** domain) {
    ViDeskClientContext* viCtx = (ViDeskClientContext*)instance->context;
    ViDeskContext* ctx = viCtx ? viCtx->viDeskCtx : NULL;

    viDesk_log("[ViDesk] 认证回调被调用\n");
    viDesk_log("[ViDesk] 用户名: %s\n", username && *username ? *username : "(空)");
    viDesk_log("[ViDesk] 域: %s\n", domain && *domain ? *domain : "(空)");

    // 从 settings 中读取已设置的凭证
    rdpSettings* settings = instance->context->settings;
    const char* settingsUsername = NULL;
    const char* settingsPassword = NULL;
    const char* settingsDomain = NULL;
    
    if (settings) {
        settingsUsername = freerdp_settings_get_string(settings, FreeRDP_Username);
        settingsPassword = freerdp_settings_get_string(settings, FreeRDP_Password);
        settingsDomain = freerdp_settings_get_string(settings, FreeRDP_Domain);    }

    // 调用 Swift 回调（如果设置了）
    BOOL result = TRUE;
    if (g_callbacks.onAuthenticate && ctx && ctx->swiftCallbackContext) {
        result = g_callbacks.onAuthenticate(ctx->swiftCallbackContext, username, password, domain);
    } else {
        // 如果没有设置 Swift 回调，从 settings 中更新指针
        // 这是关键修复：FreeRDP 需要指针指向有效的字符串
        if (settingsUsername && username) {
            // 释放旧的内存（如果存在）
            if (*username) {
                free(*username);
            }
            *username = _strdup(settingsUsername);
        }
        
        if (settingsPassword && password) {
            // 释放旧的内存（如果存在）
            if (*password) {
                free(*password);
            }
            *password = _strdup(settingsPassword);
        }
        
        if (settingsDomain && domain) {
            // 释放旧的内存（如果存在）
            if (*domain) {
                free(*domain);
            }
            *domain = settingsDomain ? _strdup(settingsDomain) : NULL;
        }    }    
    // 验证凭证是否有效
    if (result && (!username || !*username || !password || !*password)) {
        viDesk_log("[ViDesk] 警告: 认证回调返回 TRUE，但凭证为空\n");    }
    
    return result;
}

// === 公共 API 实现 ===

ViDeskContext* viDesk_createContext(void) {
    ViDeskContext* ctx = (ViDeskContext*)calloc(1, sizeof(ViDeskContext));
    if (!ctx) {
        setLastError("Failed to allocate ViDeskContext");
        return NULL;
    }

    // 创建 FreeRDP 实例
    freerdp* instance = freerdp_new();
    if (!instance) {
        setLastError("Failed to create FreeRDP instance");
        free(ctx);
        return NULL;
    }

    // 设置上下文大小
    instance->ContextSize = sizeof(ViDeskClientContext);

    // 设置回调
    instance->PreConnect = viDesk_PreConnect;
    instance->PostConnect = viDesk_PostConnect;
    instance->PostDisconnect = viDesk_PostDisconnect;
    // 优先使用 AuthenticateEx（支持 NLA），如果没有设置则使用 Authenticate
    instance->AuthenticateEx = viDesk_AuthenticateEx;
    instance->Authenticate = viDesk_Authenticate;
    instance->VerifyCertificateEx = viDesk_VerifyCertificateEx;
    instance->VerifyChangedCertificateEx = viDesk_VerifyChangedCertificateEx;

    // 创建上下文
    if (!freerdp_context_new(instance)) {
        setLastError("Failed to create FreeRDP context");
        freerdp_free(instance);
        free(ctx);
        return NULL;
    }

    // 关联 ViDesk 上下文
    ViDeskClientContext* viCtx = (ViDeskClientContext*)instance->context;
    viCtx->viDeskCtx = ctx;

    // 保存引用
    ctx->rdpCtx = instance->context;

    // 设置 EndPaint 回调
    instance->context->update->EndPaint = viDesk_EndPaint;

    // 初始化默认值
    ctx->frameBytesPerPixel = 4;
    ctx->isConnected = FALSE;
    ctx->isAuthenticated = FALSE;

    return ctx;
}

void viDesk_destroyContext(ViDeskContext* ctx) {
    if (!ctx)
        return;

    if (ctx->rdpCtx) {
        freerdp* instance = ctx->rdpCtx->instance;
        if (instance) {
            if (ctx->isConnected) {
                freerdp_disconnect(instance);
            }
            freerdp_context_free(instance);
            freerdp_free(instance);
        }
    }

    free(ctx);
}

void viDesk_setCallbacks(ViDeskContext* ctx, ViDeskCallbacks callbacks, void* swiftContext) {
    g_callbacks = callbacks;
    if (ctx) {
        ctx->swiftCallbackContext = swiftContext;
    }
}

bool viDesk_setServer(ViDeskContext* ctx, const char* hostname, int port) {
    if (!ctx || !ctx->rdpCtx || !hostname) {
        setLastError("Invalid parameters");
        return false;
    }

    rdpSettings* settings = ctx->rdpCtx->settings;
    if (!settings)
        return false;

    if (!freerdp_settings_set_string(settings, FreeRDP_ServerHostname, hostname))
        return false;

    if (!freerdp_settings_set_uint32(settings, FreeRDP_ServerPort, (UINT32)port))
        return false;

    return true;
}

bool viDesk_setCredentials(ViDeskContext* ctx, const char* username, const char* password, const char* domain) {
    if (!ctx || !ctx->rdpCtx) {
        setLastError("Invalid context");
        return false;
    }

    rdpSettings* settings = ctx->rdpCtx->settings;
    if (!settings)
        return false;

    viDesk_log("[ViDesk] 设置凭证: 用户=%s, 域=%s\n",
           username ? username : "(空)",
           domain ? domain : "(空)");
    viDesk_log("[ViDesk] 密码信息: 指针=%p, 长度=%d\n",
           password,
           password ? (int)strlen(password) : 0);

    BOOL usernameSet = TRUE;
    BOOL passwordSet = TRUE;
    BOOL domainSet = TRUE;

    // 设置用户名（即使为空也设置）
    if (username) {
        usernameSet = freerdp_settings_set_string(settings, FreeRDP_Username, username);
    }
    
    // 设置密码 - 即使为空字符串也要设置（可能是空密码）
    // 但如果是 NULL，则不设置
    if (password != NULL) {
        passwordSet = freerdp_settings_set_string(settings, FreeRDP_Password, password);
        viDesk_log("[ViDesk] 设置密码: 长度=%d, 内容=%s\n", 
               (int)strlen(password), 
               strlen(password) > 0 ? "***" : "(空)");
    } else {
        // 如果密码是 NULL，不设置（保持原有值）
        viDesk_log("[ViDesk] 警告: 密码指针为 NULL，不设置密码\n");
    }
    
    // 设置域（即使为空也设置）
    if (domain) {
        domainSet = freerdp_settings_set_string(settings, FreeRDP_Domain, domain);
    }
    if (!usernameSet || !passwordSet || !domainSet)
        return false;

    return true;
}

bool viDesk_setDisplay(ViDeskContext* ctx, int width, int height, int colorDepth) {
    if (!ctx || !ctx->rdpCtx || width <= 0 || height <= 0) {
        setLastError("Invalid display parameters");
        return false;
    }

    rdpSettings* settings = ctx->rdpCtx->settings;
    if (!settings)
        return false;

    if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, (UINT32)width))
        return false;

    if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, (UINT32)height))
        return false;

    if (!freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, (UINT32)colorDepth))
        return false;

    // 更新本地存储
    ctx->frameWidth = width;
    ctx->frameHeight = height;

    switch (colorDepth) {
        case 16: ctx->frameBytesPerPixel = 2; break;
        case 24: ctx->frameBytesPerPixel = 3; break;
        case 32:
        default: ctx->frameBytesPerPixel = 4; break;
    }

    return true;
}

bool viDesk_setPerformanceFlags(ViDeskContext* ctx, bool enableWallpaper, bool enableFullWindowDrag,
                                 bool enableMenuAnimations, bool enableThemes, bool enableFontSmoothing) {
    if (!ctx || !ctx->rdpCtx) {
        setLastError("Invalid context");
        return false;
    }

    rdpSettings* settings = ctx->rdpCtx->settings;
    if (!settings)
        return false;

    freerdp_settings_set_bool(settings, FreeRDP_DisableWallpaper, !enableWallpaper);
    freerdp_settings_set_bool(settings, FreeRDP_DisableFullWindowDrag, !enableFullWindowDrag);
    freerdp_settings_set_bool(settings, FreeRDP_DisableMenuAnims, !enableMenuAnimations);
    freerdp_settings_set_bool(settings, FreeRDP_DisableThemes, !enableThemes);
    freerdp_settings_set_bool(settings, FreeRDP_AllowFontSmoothing, enableFontSmoothing);

    return true;
}

bool viDesk_setSecurity(ViDeskContext* ctx, bool useNLA, bool useTLS, bool ignoreCertErrors) {
    if (!ctx || !ctx->rdpCtx) {
        setLastError("Invalid context");
        return false;
    }

    rdpSettings* settings = ctx->rdpCtx->settings;
    if (!settings)
        return false;

    viDesk_log("[ViDesk] 设置安全选项: NLA=%s, TLS=%s, 忽略证书=%s\n",
           useNLA ? "是" : "否",
           useTLS ? "是" : "否",
           ignoreCertErrors ? "是" : "否");

    // NLA 要求 TLS 作为传输层，强制启用
    if (useNLA && !useTLS) {
        useTLS = true;
        viDesk_log("[ViDesk] NLA 要求 TLS，已自动启用 TLS\n");
    }

    // 设置安全协议
    freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, useNLA);
    freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, useTLS);

    // 根据配置决定是否启用 RDP 安全层
    // 如果 NLA 和 TLS 都禁用，必须启用 RDP 安全
    // 如果启用了其他安全协议，也可以同时启用 RDP 安全作为后备
    if (!useNLA && !useTLS) {
        // 只使用 RDP 安全
        freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);
        viDesk_log("[ViDesk] 仅启用 RDP 安全层\n");
    } else {
        // 启用 RDP 安全作为后备选项
        freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);
        viDesk_log("[ViDesk] 启用 RDP 安全层作为后备\n");
    }

    // 启用安全层协商
    freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, TRUE);

    // 证书设置
    freerdp_settings_set_bool(settings, FreeRDP_IgnoreCertificate, ignoreCertErrors);
    if (ignoreCertErrors) {
        freerdp_settings_set_bool(settings, FreeRDP_AutoAcceptCertificate, TRUE);
    }

    // 对于非 Windows RDP 服务器（如 GNOME/xrdp），可能需要特殊配置
    // 禁用一些 Windows 特有的功能
    freerdp_settings_set_bool(settings, FreeRDP_ExtSecurity, FALSE);
    return true;
}

bool viDesk_setGateway(ViDeskContext* ctx, const char* hostname, int port,
                       const char* username, const char* password, const char* domain) {
    if (!ctx || !ctx->rdpCtx) {
        setLastError("Invalid context");
        return false;
    }

    rdpSettings* settings = ctx->rdpCtx->settings;
    if (!settings)
        return false;

    if (hostname) {
        freerdp_settings_set_bool(settings, FreeRDP_GatewayEnabled, TRUE);
        freerdp_settings_set_string(settings, FreeRDP_GatewayHostname, hostname);
        freerdp_settings_set_uint32(settings, FreeRDP_GatewayPort, (UINT32)port);

        if (username)
            freerdp_settings_set_string(settings, FreeRDP_GatewayUsername, username);
        if (password)
            freerdp_settings_set_string(settings, FreeRDP_GatewayPassword, password);
        if (domain)
            freerdp_settings_set_string(settings, FreeRDP_GatewayDomain, domain);
    } else {
        freerdp_settings_set_bool(settings, FreeRDP_GatewayEnabled, FALSE);
    }

    return true;
}

bool viDesk_connect(ViDeskContext* ctx) {
    if (!ctx || !ctx->rdpCtx) {
        setLastError("Invalid context");
        return false;
    }

    freerdp* instance = ctx->rdpCtx->instance;
    if (!instance) {
        setLastError("No FreeRDP instance");
        return false;
    }

    // 打印连接信息
    rdpSettings* settings = ctx->rdpCtx->settings;
    if (settings) {
        const char* hostname = freerdp_settings_get_string(settings, FreeRDP_ServerHostname);
        UINT32 port = freerdp_settings_get_uint32(settings, FreeRDP_ServerPort);
        const char* username = freerdp_settings_get_string(settings, FreeRDP_Username);
        const char* password = freerdp_settings_get_string(settings, FreeRDP_Password);
        const char* domain = freerdp_settings_get_string(settings, FreeRDP_Domain);
        viDesk_log("[ViDesk] 正在连接: %s:%u (用户: %s)\n",
               hostname ? hostname : "N/A",
               port,
               username ? username : "N/A");    }

    // === xrdp 兼容性: 在 connect 之前再次确认设置 ===
    freerdp_settings_set_bool(settings, FreeRDP_NetworkAutoDetect, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_SupportHeartbeatPdu, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_SupportMultitransport, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_SupportGraphicsPipeline, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxThinClient, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxSmallCache, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_SupportMonitorLayoutPdu, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_AllowUnanouncedOrdersFromServer, TRUE);
    freerdp_settings_set_uint32(settings, FreeRDP_GlyphSupportLevel, 2);
    freerdp_settings_set_bool(settings, FreeRDP_AutoReconnectionEnabled, FALSE);

    viDesk_log("[ViDesk] xrdp 兼容: AutoDetect=%d, Heartbeat=%d, GFX=%d, Multitransport=%d, GlyphLevel=%u, AutoReconnect=%d\n",
        freerdp_settings_get_bool(settings, FreeRDP_NetworkAutoDetect),
        freerdp_settings_get_bool(settings, FreeRDP_SupportHeartbeatPdu),
        freerdp_settings_get_bool(settings, FreeRDP_SupportGraphicsPipeline),
        freerdp_settings_get_bool(settings, FreeRDP_SupportMultitransport),
        freerdp_settings_get_uint32(settings, FreeRDP_GlyphSupportLevel),
        freerdp_settings_get_bool(settings, FreeRDP_AutoReconnectionEnabled));

    // 通知状态变化
    notifyStateChange(ctx, 1, "Connecting...");  // 1 = connecting

    // 执行连接
    viDesk_log("[ViDesk] 调用 freerdp_connect()...\n");
    BOOL connectResult = freerdp_connect(instance);    if (!connectResult) {
        UINT32 error = freerdp_get_last_error(ctx->rdpCtx);
        const char* errorStr = freerdp_get_last_error_string(error);
        const char* errorName = freerdp_get_last_error_name(error);
        const char* errorCategory = freerdp_get_last_error_category(error);

        char errorMsg[512];
        snprintf(errorMsg, sizeof(errorMsg), "%s (%s, code: 0x%08X)",
                 errorStr ? errorStr : "Connection failed",
                 errorName ? errorName : "UNKNOWN",
                 error);

        viDesk_log("[ViDesk] 连接失败: %s\n", errorMsg);
        viDesk_log("[ViDesk] 错误码: 0x%08X\n", error);
        viDesk_log("[ViDesk] 错误名称: %s\n", errorName ? errorName : "UNKNOWN");
        viDesk_log("[ViDesk] 错误类别: %s\n", errorCategory ? errorCategory : "UNKNOWN");
        
        // 打印详细的认证相关错误信息
        if (error == 0x00020009 || errorName) {
            if (strstr(errorName ? errorName : "", "AUTHENTICATION") != NULL) {
                viDesk_log("[ViDesk] ========== 认证失败详细信息 ==========\n");
                rdpSettings* settings = ctx->rdpCtx->settings;
                if (settings) {
                    const char* username = freerdp_settings_get_string(settings, FreeRDP_Username);
                    const char* password = freerdp_settings_get_string(settings, FreeRDP_Password);
                    const char* domain = freerdp_settings_get_string(settings, FreeRDP_Domain);
                    viDesk_log("[ViDesk] Settings中的用户名: %s\n", username ? username : "(空)");
                    viDesk_log("[ViDesk] Settings中的密码长度: %d\n", password ? (int)strlen(password) : 0);
                    viDesk_log("[ViDesk] Settings中的域: %s\n", domain ? domain : "(空)");
                    BOOL nla = freerdp_settings_get_bool(settings, FreeRDP_NlaSecurity);
                    BOOL tls = freerdp_settings_get_bool(settings, FreeRDP_TlsSecurity);
                    BOOL rdp = freerdp_settings_get_bool(settings, FreeRDP_RdpSecurity);
                    viDesk_log("[ViDesk] NLA: %s, TLS: %s, RDP: %s\n", nla ? "是" : "否", tls ? "是" : "否", rdp ? "是" : "否");
                }
                viDesk_log("[ViDesk] =========================================\n");
            }
        }        setLastError(errorMsg);
        notifyStateChange(ctx, 5, errorMsg);  // 5 = error
        return false;
    }

    viDesk_log("[ViDesk] 连接成功!\n");    return true;
}

void viDesk_disconnect(ViDeskContext* ctx) {
    if (!ctx || !ctx->rdpCtx)
        return;

    freerdp* instance = ctx->rdpCtx->instance;
    if (instance && ctx->isConnected) {
        freerdp_disconnect(instance);
    }

    ctx->isConnected = FALSE;
    ctx->isAuthenticated = FALSE;
}

bool viDesk_isConnected(ViDeskContext* ctx) {
    return ctx && ctx->isConnected;
}

bool viDesk_processEvents(ViDeskContext* ctx, int timeoutMs) {
    if (!ctx || !ctx->rdpCtx || !ctx->isConnected) {
        return false;
    }

    freerdp* instance = ctx->rdpCtx->instance;
    rdpContext* context = ctx->rdpCtx;

    if (!instance || !context)
        return false;

    // 检查是否应该断开
    if (freerdp_shall_disconnect_context(context)) {
        return false;
    }

    // 获取事件句柄
    HANDLE handles[64];
    DWORD nCount = freerdp_get_event_handles(context, handles, 64);
    if (nCount == 0) {
        return false;
    }

    // 等待事件
    DWORD waitStatus = WaitForMultipleObjects(nCount, handles, FALSE, (DWORD)timeoutMs);
    if (waitStatus == WAIT_FAILED) {
        return false;
    }

    // 检查并处理事件
    if (!freerdp_check_event_handles(context)) {
        if (freerdp_get_last_error(context) == FREERDP_ERROR_SUCCESS) {
            // 正常断开
            return false;
        }
        // 错误
        UINT32 error = freerdp_get_last_error(context);
        const char* errorStr = freerdp_get_last_error_string(error);
        setLastError(errorStr ? errorStr : "Event handling failed");
        return false;
    }

    return true;
}

// === 输入事件 ===

bool viDesk_sendMouseMove(ViDeskContext* ctx, int x, int y) {
    if (!ctx || !ctx->rdpCtx || !ctx->isConnected)
        return false;

    rdpInput* input = ctx->rdpCtx->input;
    if (!input)
        return false;

    return freerdp_input_send_mouse_event(input, PTR_FLAGS_MOVE, (UINT16)x, (UINT16)y);
}

bool viDesk_sendMouseButton(ViDeskContext* ctx, int button, bool isPressed, int x, int y) {
    if (!ctx || !ctx->rdpCtx || !ctx->isConnected)
        return false;

    rdpInput* input = ctx->rdpCtx->input;
    if (!input)
        return false;

    UINT16 flags = 0;
    switch (button) {
        case 0: flags = PTR_FLAGS_BUTTON1; break;  // 左键
        case 1: flags = PTR_FLAGS_BUTTON2; break;  // 右键
        case 2: flags = PTR_FLAGS_BUTTON3; break;  // 中键
        default: return false;
    }

    if (isPressed)
        flags |= PTR_FLAGS_DOWN;

    return freerdp_input_send_mouse_event(input, flags, (UINT16)x, (UINT16)y);
}

bool viDesk_sendMouseWheel(ViDeskContext* ctx, int delta, bool isHorizontal) {
    if (!ctx || !ctx->rdpCtx || !ctx->isConnected)
        return false;

    rdpInput* input = ctx->rdpCtx->input;
    if (!input)
        return false;

    UINT16 flags = isHorizontal ? PTR_FLAGS_HWHEEL : PTR_FLAGS_WHEEL;

    if (delta < 0) {
        flags |= PTR_FLAGS_WHEEL_NEGATIVE;
        delta = -delta;
    }

    // 限制范围
    if (delta > 0xFF)
        delta = 0xFF;

    flags |= (UINT16)(delta & 0xFF);

    return freerdp_input_send_mouse_event(input, flags, 0, 0);
}

bool viDesk_sendKeyEvent(ViDeskContext* ctx, uint16_t scanCode, bool isPressed, bool isExtended) {
    if (!ctx || !ctx->rdpCtx || !ctx->isConnected)
        return false;

    rdpInput* input = ctx->rdpCtx->input;
    if (!input)
        return false;

    UINT16 flags = isPressed ? 0 : KBD_FLAGS_RELEASE;
    if (isExtended)
        flags |= KBD_FLAGS_EXTENDED;

    return freerdp_input_send_keyboard_event(input, flags, (UINT8)scanCode);
}

bool viDesk_sendUnicodeKey(ViDeskContext* ctx, uint16_t codePoint) {
    if (!ctx || !ctx->rdpCtx || !ctx->isConnected)
        return false;

    rdpInput* input = ctx->rdpCtx->input;
    if (!input)
        return false;

    // 按下
    if (!freerdp_input_send_unicode_keyboard_event(input, 0, codePoint))
        return false;

    // 释放
    return freerdp_input_send_unicode_keyboard_event(input, KBD_FLAGS_RELEASE, codePoint);
}

// === 剪贴板 ===

bool viDesk_setClipboardText(ViDeskContext* ctx, const char* text) {
    if (!ctx || !ctx->rdpCtx || !ctx->isConnected || !text)
        return false;

    // TODO: 实现剪贴板通道发送
    // 需要 cliprdr 通道支持
    return true;
}

char* viDesk_getClipboardText(ViDeskContext* ctx) {
    if (!ctx || !ctx->rdpCtx || !ctx->isConnected)
        return NULL;

    // TODO: 实现剪贴板通道接收
    // 需要 cliprdr 通道支持
    return NULL;
}

void viDesk_freeString(char* str) {
    if (str) {
        free(str);
    }
}

// === 帧缓冲区 ===

const uint8_t* viDesk_getFrameBuffer(ViDeskContext* ctx) {
    return ctx ? ctx->frameBuffer : NULL;
}

void viDesk_getFrameSize(ViDeskContext* ctx, uint32_t* width, uint32_t* height) {
    if (ctx) {
        if (width) *width = ctx->frameWidth;
        if (height) *height = ctx->frameHeight;
    }
}

uint32_t viDesk_getFrameBytesPerPixel(ViDeskContext* ctx) {
    return ctx ? ctx->frameBytesPerPixel : 0;
}

// === 调试 ===

const char* viDesk_getLastError(ViDeskContext* ctx) {
    (void)ctx;
    return g_lastError;
}

void viDesk_getStatistics(ViDeskContext* ctx, uint64_t* bytesReceived, uint64_t* bytesSent,
                          uint32_t* frameRate, uint32_t* latencyMs) {
    if (!ctx || !ctx->rdpCtx) {
        if (bytesReceived) *bytesReceived = 0;
        if (bytesSent) *bytesSent = 0;
        if (frameRate) *frameRate = 0;
        if (latencyMs) *latencyMs = 0;
        return;
    }

    // 从 FreeRDP 获取统计信息
    rdpContext* context = ctx->rdpCtx;
    if (context && context->rdp) {
        UINT64 inBytes = 0, outBytes = 0, inPackets = 0, outPackets = 0;
        freerdp_get_stats(context->rdp, &inBytes, &outBytes, &inPackets, &outPackets);

        if (bytesReceived) *bytesReceived = inBytes;
        if (bytesSent) *bytesSent = outBytes;
    }

    if (frameRate) *frameRate = 60;  // TODO: 实现实际帧率计算
    if (latencyMs) *latencyMs = 0;   // TODO: 实现延迟测量
}
