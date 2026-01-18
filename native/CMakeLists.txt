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
    ${CMAKE_SOURCE_DIR}/include/unrar  # UnRAR SDK头文件
    ${CMAKE_SOURCE_DIR}/src/minizip-ng  # minizip-ng头文件
)

# UnRAR SDK 源文件 - 只包含DLL接口需要的核心文件，排除Windows专用文件
set(UNRAR_SOURCES
    ${CMAKE_SOURCE_DIR}/src/unrar/rar.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/strlist.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/strfn.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/pathfn.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/smallfn.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/global.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/file.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/filefn.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/filcreat.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/archive.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/arcread.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/unicode.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/system.cpp
    # ${CMAKE_SOURCE_DIR}/src/unrar/isnt.cpp  # Windows专用，Android不需要
    ${CMAKE_SOURCE_DIR}/src/unrar/crypt.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/crc.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/rawread.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/encname.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/resource.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/match.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/timefn.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/rdwrfn.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/consio.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/options.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/cmddata.cpp  # 命令行数据处理
    ${CMAKE_SOURCE_DIR}/src/unrar/errhnd.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/rarvm.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/secpassword.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/rijndael.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/getbits.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/sha1.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/sha256.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/blake2s.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/hash.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/extinfo.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/extract.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/volume.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/list.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/find.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/unpack.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/headers.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/threadpool.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/rs16.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/qopen.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/ui.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/filestr.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/scantree.cpp
    ${CMAKE_SOURCE_DIR}/src/unrar/dll.cpp
)

# UnRAR 编译定义
add_definitions(
    -DRARDLL              # 编译为DLL
    -DSILENT              # 静默模式（无控制台输出）
    -DNOVOLUME            # 不支持分卷RAR
    -D_FILE_OFFSET_BITS=64  # 支持大文件
    -D_LARGEFILE_SOURCE     # 大文件支持
    -D_UNIX               # Unix平台
    # Android上禁用一些可选功能
    # -DUSE_LUTIMES       # Android上可能不支持lutimes
)

# ==================== minizip-ng 配置 ====================

# 禁用minizip-ng不需要的功能（简化编译）
set(MZ_COMPAT OFF CACHE BOOL "" FORCE)         # 不需要旧版本兼容
set(MZ_ZLIB ON CACHE BOOL "" FORCE)            # 启用zlib压缩
set(MZ_BZIP2 OFF CACHE BOOL "" FORCE)          # 禁用bzip2
set(MZ_LZMA OFF CACHE BOOL "" FORCE)           # 禁用lzma
set(MZ_ZSTD OFF CACHE BOOL "" FORCE)           # 禁用zstd
set(MZ_OPENSSL OFF CACHE BOOL "" FORCE)        # 禁用OpenSSL加密
set(MZ_LIBCOMP OFF CACHE BOOL "" FORCE)        # 禁用libcompression
set(MZ_FETCH_LIBS OFF CACHE BOOL "" FORCE)     # 不自动下载依赖
set(MZ_BUILD_TESTS OFF CACHE BOOL "" FORCE)    # 不编译测试
set(MZ_BUILD_UNIT_TESTS OFF CACHE BOOL "" FORCE)
set(MZ_BUILD_FUZZ_TESTS OFF CACHE BOOL "" FORCE)
set(MZ_ICONV ON CACHE BOOL "" FORCE)           # 启用iconv进行字符编码转换

# 添加minizip-ng子项目
add_subdirectory(${CMAKE_SOURCE_DIR}/src/minizip-ng EXCLUDE_FROM_ALL)

# ==================== 封装库配置 ====================

# 我们的封装库源文件
add_library(archive_wrapper SHARED
    ${CMAKE_SOURCE_DIR}/src/archive_wrapper.c
    ${CMAKE_SOURCE_DIR}/src/unrar_wrapper.cpp  # UnRAR封装（真实实现）
    ${UNRAR_SOURCES}  # UnRAR SDK源码
)

# minizip wrapper（单独编译以便链接minizip）
add_library(minizip_wrapper SHARED
    ${CMAKE_SOURCE_DIR}/src/minizip_wrapper.c
)

target_link_libraries(minizip_wrapper
    minizip-ng    # minizip-ng库（正确的库名）
    log        # Android 日志
    z          # zlib
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
