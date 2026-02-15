#!/bin/bash
set -e

# OpenSSL for visionOS Simulator 编译脚本

OPENSSL_VERSION="3.2.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENSSL_SRC="${SCRIPT_DIR}/openssl-${OPENSSL_VERSION}"
OUTPUT_DIR="${SCRIPT_DIR}/output/openssl"

# visionOS SDK
XROS_SIM_SDK=$(xcrun --sdk xrsimulator --show-sdk-path)
DEVELOPER=$(xcode-select -p)

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}/simulator"

echo "=== 编译 OpenSSL ${OPENSSL_VERSION} for visionOS Simulator ==="
echo "SDK: ${XROS_SIM_SDK}"

cd "${OPENSSL_SRC}"
make clean 2>/dev/null || true

# 直接配置，使用 darwin64-arm64 作为基础
./Configure darwin64-arm64-cc \
    no-shared \
    no-dso \
    no-hw \
    no-engine \
    no-async \
    no-tests \
    --prefix="${OUTPUT_DIR}/simulator" \
    --openssldir="${OUTPUT_DIR}/simulator/ssl"

# 修改 Makefile 中的编译器标志
# 添加 visionOS 目标
sed -i '' "s|^CC=.*|CC=xcrun --sdk xrsimulator clang|g" Makefile
sed -i '' "s|^CFLAGS=|CFLAGS=-target arm64-apple-xros2.0-simulator -isysroot ${XROS_SIM_SDK} |g" Makefile
sed -i '' "s|^LDFLAGS=|LDFLAGS=-target arm64-apple-xros2.0-simulator -isysroot ${XROS_SIM_SDK} |g" Makefile

echo ""
echo "开始编译..."
make -j$(sysctl -n hw.ncpu) build_libs 2>&1 | tail -30

echo ""
echo "安装库文件..."
make install_sw 2>&1 | tail -10

echo ""
echo "=== 复制到项目目录 ==="

PROJECT_LIB="${SCRIPT_DIR}/../FreeRDPFramework/lib"
PROJECT_INC="${SCRIPT_DIR}/../FreeRDPFramework/include"

mkdir -p "${PROJECT_LIB}" "${PROJECT_INC}"

cp "${OUTPUT_DIR}/simulator/lib/libssl.a" "${PROJECT_LIB}/"
cp "${OUTPUT_DIR}/simulator/lib/libcrypto.a" "${PROJECT_LIB}/"
cp -r "${OUTPUT_DIR}/simulator/include/openssl" "${PROJECT_INC}/"

echo ""
echo "=== OpenSSL 编译完成 ==="
ls -la "${PROJECT_LIB}"
