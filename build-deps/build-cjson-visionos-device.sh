#!/bin/bash
set -e

# cJSON for visionOS Device 编译脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CJSON_SRC="${SCRIPT_DIR}/cJSON"
BUILD_DIR="${SCRIPT_DIR}/build-cjson-device"
OUTPUT_DIR="${SCRIPT_DIR}/output/cjson-device"

# visionOS Device SDK
XROS_SDK=$(xcrun --sdk xros --show-sdk-path)
TARGET="arm64-apple-xros2.0"

echo "=== 编译 cJSON for visionOS Device ==="
echo "SDK: ${XROS_SDK}"

if [ ! -d "${CJSON_SRC}" ]; then
    echo "错误: cJSON 源码不存在: ${CJSON_SRC}"
    echo "请先克隆 cJSON:"
    echo "  git clone https://github.com/DaveGamble/cJSON.git ${CJSON_SRC}"
    exit 1
fi

rm -rf "${BUILD_DIR}" "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

cd "${BUILD_DIR}"

# CMake 配置 - 为 visionOS device 编译
cmake "${CJSON_SRC}" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_OSX_SYSROOT="${XROS_SDK}" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_C_FLAGS="-target ${TARGET}" \
    -DCMAKE_INSTALL_PREFIX="${OUTPUT_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_CJSON_TEST=OFF \
    -DENABLE_CJSON_UTILS=OFF \
    -G "Unix Makefiles"

echo ""
echo "开始编译..."
make -j$(sysctl -n hw.ncpu)

echo ""
echo "安装..."
make install

echo ""
echo "=== 复制到项目目录 ==="

PROJECT_LIB="${SCRIPT_DIR}/../FreeRDPFramework/lib"
PROJECT_INC="${SCRIPT_DIR}/../FreeRDPFramework/include"

mkdir -p "${PROJECT_LIB}" "${PROJECT_INC}"

cp "${OUTPUT_DIR}/lib/libcjson.a" "${PROJECT_LIB}/"
cp -r "${OUTPUT_DIR}/include/"* "${PROJECT_INC}/"

echo ""
echo "=== cJSON for visionOS Device 编译完成 ==="
ls -la "${PROJECT_LIB}/libcjson.a"

echo ""
echo "验证库架构..."
lipo -info "${PROJECT_LIB}/libcjson.a"
