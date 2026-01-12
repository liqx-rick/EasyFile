cmake_minimum_required(VERSION 3.18.1)

project("archive_wrapper")

# 设置 C/C++ 标准
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 添加头文件路径
include_directories(
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/include/libarchive
)

# 我们的封装库源文件
add_library(archive_wrapper SHARED
    ${CMAKE_SOURCE_DIR}/src/archive_wrapper.c
)

# 预编译的 libarchive 库
set(LIBARCHIVE_PATH ${CMAKE_SOURCE_DIR}/../android/src/main/jniLibs/${ANDROID_ABI}/libarchive.so)

# 检查库文件是否存在
if(NOT EXISTS ${LIBARCHIVE_PATH})
    message(FATAL_ERROR 
        "\n"
        "========================================\n"
        "ERROR: libarchive.so not found!\n"
        "========================================\n"
        "Expected location: ${LIBARCHIVE_PATH}\n"
        "\n"
        "You need to compile libarchive with static linking.\n"
        "See: docs/LIBARCHIVE_STATIC_BUILD_GUIDE.md\n"
        "\n"
        "After compilation, place libarchive.so in:\n"
        "  android/src/main/jniLibs/arm64-v8a/libarchive.so\n"
        "  android/src/main/jniLibs/armeabi-v7a/libarchive.so\n"
        "========================================\n"
    )
endif()

add_library(archive SHARED IMPORTED)
set_target_properties(archive PROPERTIES
    IMPORTED_LOCATION ${LIBARCHIVE_PATH}
)

# 链接库
target_link_libraries(archive_wrapper
    archive  # 预编译的 libarchive
    log      # Android 日志
    z        # zlib (Android 自带)
)
