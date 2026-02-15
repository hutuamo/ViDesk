#!/bin/bash
set -e

# OpenSSL for visionOS Device 编译脚本

OPENSSL_VERSION="3.2.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENSSL_SRC="${SCRIPT_DIR}/openssl-${OPENSSL_VERSION}"
OUTPUT_DIR="${SCRIPT_DIR}/output/openssl-device"

# visionOS Device SDK
XROS_SDK=$(xcrun --sdk xros --show-sdk-path)
DEVELOPER=$(xcode-select -p)

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

echo "=== 编译 OpenSSL ${OPENSSL_VERSION} for visionOS Device ==="
echo "SDK: ${XROS_SDK}"

if [ ! -d "${OPENSSL_SRC}" ]; then
    echo "错误: OpenSSL 源码不存在: ${OPENSSL_SRC}"
    echo "请先下载 OpenSSL 源码:"
    echo "  curl -LO https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
    echo "  tar xzf openssl-${OPENSSL_VERSION}.tar.gz -C ${SCRIPT_DIR}"
    exit 1
fi

cd "${OPENSSL_SRC}"
make clean 2>/dev/null || true

# 配置 OpenSSL
./Configure darwin64-arm64-cc \
    no-shared \
    no-dso \
    no-hw \
    no-engine \
    no-async \
    no-tests \
    --prefix="${OUTPUT_DIR}" \
    --openssldir="${OUTPUT_DIR}/ssl"

# 修改 Makefile 中的编译器标志为 visionOS device
sed -i '' "s|^CC=.*|CC=xcrun --sdk xros clang|g" Makefile
sed -i '' "s|^CFLAGS=|CFLAGS=-target arm64-apple-xros2.0 -isysroot ${XROS_SDK} |g" Makefile
sed -i '' "s|^LDFLAGS=|LDFLAGS=-target arm64-apple-xros2.0 -isysroot ${XROS_SDK} |g" Makefile

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

cp "${OUTPUT_DIR}/lib/libssl.a" "${PROJECT_LIB}/"
cp "${OUTPUT_DIR}/lib/libcrypto.a" "${PROJECT_LIB}/"
cp -r "${OUTPUT_DIR}/include/openssl" "${PROJECT_INC}/"

echo ""
echo "=== OpenSSL for visionOS Device 编译完成 ==="
ls -la "${PROJECT_LIB}"
