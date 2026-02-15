#!/bin/bash
set -e

# 为 visionOS 真机编译所有依赖库的主脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo "  visionOS Device 依赖库编译"
echo "=========================================="
echo ""

# 检查 SDK
if ! xcrun --sdk xros --show-sdk-path > /dev/null 2>&1; then
    echo "错误: 未找到 visionOS SDK"
    echo "请确保已安装 Xcode 并包含 visionOS 支持"
    exit 1
fi

echo "visionOS SDK: $(xcrun --sdk xros --show-sdk-path)"
echo ""

# 1. 编译 OpenSSL
echo "=========================================="
echo "[1/3] 编译 OpenSSL"
echo "=========================================="
chmod +x "${SCRIPT_DIR}/build-openssl-visionos-device.sh"
"${SCRIPT_DIR}/build-openssl-visionos-device.sh"

echo ""
echo ""

# 2. 编译 cJSON
echo "=========================================="
echo "[2/3] 编译 cJSON"
echo "=========================================="
chmod +x "${SCRIPT_DIR}/build-cjson-visionos-device.sh"
"${SCRIPT_DIR}/build-cjson-visionos-device.sh"

echo ""
echo ""

# 3. 编译 FreeRDP
echo "=========================================="
echo "[3/3] 编译 FreeRDP"
echo "=========================================="
chmod +x "${SCRIPT_DIR}/build-freerdp-visionos-device.sh"
"${SCRIPT_DIR}/build-freerdp-visionos-device.sh"

echo ""
echo ""
echo "=========================================="
echo "  编译完成!"
echo "=========================================="
echo ""
echo "编译产物位于: ${SCRIPT_DIR}/../FreeRDPFramework/"
echo ""
ls -la "${SCRIPT_DIR}/../FreeRDPFramework/lib/"
