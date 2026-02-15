/**
 * iOS/visionOS 路径辅助函数实现
 * 这些函数被 winpr 的 shell 模块使用
 *
 * 重要：返回的字符串必须是动态分配的，调用者负责释放
 */

#include <stdlib.h>
#include <string.h>
#import <Foundation/Foundation.h>

char* ios_get_home(void) {
    @autoreleasepool {
        NSString* home = NSHomeDirectory();
        if (home) {
            return strdup([home UTF8String]);
        }
        return NULL;
    }
}

char* ios_get_temp(void) {
    @autoreleasepool {
        NSString* temp = NSTemporaryDirectory();
        if (temp) {
            return strdup([temp UTF8String]);
        }
        return strdup("/tmp");
    }
}

char* ios_get_cache(void) {
    @autoreleasepool {
        NSArray* cachePaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        if (cachePaths.count > 0) {
            return strdup([cachePaths[0] UTF8String]);
        }
        // 回退到 temp 目录
        NSString* temp = NSTemporaryDirectory();
        if (temp) {
            return strdup([temp UTF8String]);
        }
        return NULL;
    }
}

char* ios_get_data(void) {
    @autoreleasepool {
        NSArray* dataPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        if (dataPaths.count > 0) {
            return strdup([dataPaths[0] UTF8String]);
        }
        // 回退到 home 目录
        NSString* home = NSHomeDirectory();
        if (home) {
            return strdup([home UTF8String]);
        }
        return NULL;
    }
}
