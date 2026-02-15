#!/bin/bash
set -e

# FreeRDP for visionOS Simulator 编译脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FREERDP_SRC="${SCRIPT_DIR}/FreeRDP"
BUILD_DIR="${SCRIPT_DIR}/build-freerdp"
OUTPUT_DIR="${SCRIPT_DIR}/output/freerdp"
OPENSSL_DIR="${SCRIPT_DIR}/output/openssl/simulator"

# visionOS SDK
XROS_SIM_SDK=$(xcrun --sdk xrsimulator --show-sdk-path)
TARGET="arm64-apple-xros2.0-simulator"

echo "=== 编译 FreeRDP for visionOS Simulator ==="
echo "SDK: ${XROS_SIM_SDK}"
echo "OpenSSL: ${OPENSSL_DIR}"

# 应用补丁修复 PDU_TYPE_DEACTIVATE_ALL 处理问题
PATCH_FILE="${SCRIPT_DIR}/fix-deactivate-all.patch"
if [ -f "${PATCH_FILE}" ]; then
    echo "应用补丁: ${PATCH_FILE}"
    cd "${FREERDP_SRC}"
    if ! patch -p1 -N --dry-run < "${PATCH_FILE}" > /dev/null 2>&1; then
        echo "补丁已应用或无法应用，跳过"
    else
        patch -p1 < "${PATCH_FILE}"
        echo "补丁应用成功"
    fi
    cd - > /dev/null
fi

rm -rf "${BUILD_DIR}" "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

cd "${BUILD_DIR}"

# CMake 配置 - 禁用所有非必要组件
cmake "${FREERDP_SRC}" \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_OSX_SYSROOT="${XROS_SIM_SDK}" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_C_FLAGS="-target ${TARGET}" \
    -DCMAKE_EXE_LINKER_FLAGS="-target ${TARGET}" \
    -DCMAKE_INSTALL_PREFIX="${OUTPUT_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DVISIONOS=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DWITH_CLIENT=OFF \
    -DWITH_SERVER=OFF \
    -DWITH_SAMPLE=OFF \
    -DWITH_MANPAGES=OFF \
    -DWITH_LIBSYSTEMD=OFF \
    -DWITH_WAYLAND=OFF \
    -DWITH_X11=OFF \
    -DWITH_XCURSOR=OFF \
    -DWITH_XEXT=OFF \
    -DWITH_XFIXES=OFF \
    -DWITH_XINERAMA=OFF \
    -DWITH_XKBFILE=OFF \
    -DWITH_XRANDR=OFF \
    -DWITH_XRENDER=OFF \
    -DWITH_XV=OFF \
    -DWITH_ALSA=OFF \
    -DWITH_PULSE=OFF \
    -DWITH_CUPS=OFF \
    -DWITH_PCSC=OFF \
    -DWITH_FFMPEG=OFF \
    -DWITH_SWSCALE=OFF \
    -DWITH_CAIRO=OFF \
    -DWITH_JPEG=OFF \
    -DWITH_WEBVIEW=OFF \
    -DWITH_OSS=OFF \
    -DWITH_CJSON_REQUIRED=OFF \
    -DWITH_WINPR_JSON=OFF \
    -DWITH_WINPR_TOOLS=OFF \
    -DWITH_CHANNELS=ON \
    -DWITH_CLIENT_CHANNELS=ON \
    -DCHANNEL_URBDRC=OFF \
    -DCHANNEL_TSMF=OFF \
    -DCHANNEL_VIDEO=OFF \
    -DWITH_DSP_FFMPEG=OFF \
    -DWITH_FAAC=OFF \
    -DWITH_FAAD2=OFF \
    -DWITH_OPUS=OFF \
    -DWITH_SOXR=OFF \
    -DWITH_LAME=OFF \
    -DCHANNEL_AUDIN=OFF \
    -DCHANNEL_RDPSND=OFF \
    -DOPENSSL_ROOT_DIR="${OPENSSL_DIR}" \
    -DOPENSSL_INCLUDE_DIR="${OPENSSL_DIR}/include" \
    -DOPENSSL_CRYPTO_LIBRARY="${OPENSSL_DIR}/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="${OPENSSL_DIR}/lib/libssl.a" \
    -DWITH_INTERNAL_MD4=ON \
    -DWITH_INTERNAL_RC4=ON \
    -G "Unix Makefiles"

echo ""
echo "开始编译核心库..."

# 只编译核心库
make -j$(sysctl -n hw.ncpu) winpr freerdp freerdp-client 2>&1 | tail -50

echo ""
echo "=== 复制到项目目录 ==="

PROJECT_LIB="${SCRIPT_DIR}/../FreeRDPFramework/lib"
PROJECT_INC="${SCRIPT_DIR}/../FreeRDPFramework/include"

mkdir -p "${PROJECT_LIB}" "${PROJECT_INC}"

# 复制已编译的库文件
cp "${BUILD_DIR}/winpr/libwinpr/libwinpr3.a" "${PROJECT_LIB}/" 2>/dev/null || true
cp "${BUILD_DIR}/libfreerdp/libfreerdp3.a" "${PROJECT_LIB}/" 2>/dev/null || true

# 合并 libfreerdp-client3.a 和通道公共库（如 remdesk-common）
CLIENT_LIBS=("${BUILD_DIR}/client/common/libfreerdp-client3.a")
for common_lib in "${BUILD_DIR}"/channels/*/common/lib*-common.a; do
    [ -f "$common_lib" ] && CLIENT_LIBS+=("$common_lib")
done
libtool -static -o "${PROJECT_LIB}/libfreerdp-client3.a" "${CLIENT_LIBS[@]}"

# 复制头文件
mkdir -p "${PROJECT_INC}/freerdp" "${PROJECT_INC}/winpr"
cp -r "${FREERDP_SRC}/include/freerdp/"* "${PROJECT_INC}/freerdp/" 2>/dev/null || true
cp -r "${FREERDP_SRC}/winpr/include/winpr/"* "${PROJECT_INC}/winpr/" 2>/dev/null || true

# 复制生成的配置头文件
cp "${BUILD_DIR}/include/freerdp/version.h" "${PROJECT_INC}/freerdp/" 2>/dev/null || true
cp "${BUILD_DIR}/include/freerdp/config.h" "${PROJECT_INC}/freerdp/" 2>/dev/null || true
cp "${BUILD_DIR}/include/freerdp/buildflags.h" "${PROJECT_INC}/freerdp/" 2>/dev/null || true
cp "${BUILD_DIR}/winpr/include/winpr/version.h" "${PROJECT_INC}/winpr/" 2>/dev/null || true
cp "${BUILD_DIR}/winpr/include/winpr/config.h" "${PROJECT_INC}/winpr/" 2>/dev/null || true
cp "${BUILD_DIR}/winpr/include/winpr/wtypes.h" "${PROJECT_INC}/winpr/" 2>/dev/null || true

echo ""
echo "=== FreeRDP 编译结果 ==="
ls -la "${PROJECT_LIB}"
