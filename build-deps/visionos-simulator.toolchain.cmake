# CMake toolchain file for visionOS Simulator

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_VERSION 2.0)
set(CMAKE_SYSTEM_PROCESSOR arm64)

# visionOS Simulator SDK
execute_process(
    COMMAND xcrun --sdk xrsimulator --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

set(CMAKE_OSX_ARCHITECTURES arm64)

# 设置目标三元组
set(TARGET_TRIPLE "arm64-apple-xros2.0-simulator")

# 编译器
set(CMAKE_C_COMPILER xcrun)
set(CMAKE_C_COMPILER_ARG1 "--sdk;xrsimulator;clang")
set(CMAKE_CXX_COMPILER xcrun)
set(CMAKE_CXX_COMPILER_ARG1 "--sdk;xrsimulator;clang++")

# 编译标志
set(CMAKE_C_FLAGS_INIT "-target ${TARGET_TRIPLE} -isysroot ${CMAKE_OSX_SYSROOT}")
set(CMAKE_CXX_FLAGS_INIT "-target ${TARGET_TRIPLE} -isysroot ${CMAKE_OSX_SYSROOT}")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-target ${TARGET_TRIPLE} -isysroot ${CMAKE_OSX_SYSROOT}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-target ${TARGET_TRIPLE} -isysroot ${CMAKE_OSX_SYSROOT}")

# 禁止在宿主机上运行测试程序
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# 查找路径设置
set(CMAKE_FIND_ROOT_PATH ${CMAKE_OSX_SYSROOT})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# 平台定义
add_definitions(-DTARGET_OS_XR=1)
add_definitions(-DTARGET_OS_SIMULATOR=1)
