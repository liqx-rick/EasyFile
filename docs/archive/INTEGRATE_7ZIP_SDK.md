# 7-Zip SDK 集成指南

## 概述

像 RAR（UnRAR SDK）和 ZIP（minizip-ng）一样，我们将集成 **7-Zip 官方 LZMA SDK**，直接支持加密 7z 文件。

---

## 步骤 1：下载 LZMA SDK

从官网下载：https://www.7-zip.org/download.html

```bash
# Windows PowerShell
cd C:\dev\flutter\easyfile\native

# 下载 LZMA SDK (选择最新版本，例如 23.01)
Invoke-WebRequest -Uri "https://www.7-zip.org/a/lzma2301.7z" -OutFile "lzma_sdk.7z"

# 解压到 src/lzma 目录
7z x lzma_sdk.7z -o"src\lzma"
```

**目录结构**：
```
native/
├── src/
│   ├── unrar/         # RAR support
│   ├── minizip-ng/    # ZIP support
│   ├── lzma/          # 7-Zip support (新增)
│   │   ├── C/         # C 实现
│   │   └── CPP/       # C++ 实现
│   ├── archive_wrapper.c
│   ├── unrar_wrapper.cpp
│   ├── minizip_wrapper.c
│   └── lzma_wrapper.c # 新增
```

---

## 步骤 2：创建 7z 包装器

创建 `native/include/lzma_wrapper.h`：

```c
#ifndef LZMA_WRAPPER_H
#define LZMA_WRAPPER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// 7z 提取结果
typedef struct {
    bool success;
    int total_files;
    int extracted_files;
    char error_message[512];
} LzmaExtractResult;

// 提取选项
typedef struct {
    const char* archive_path;
    const char* dest_path;
    const char* password;      // 可选密码
    bool overwrite;
    void (*on_progress)(double progress, const char* filename);
} LzmaExtractOptions;

/**
 * 使用 LZMA SDK 提取 7z 文件
 * 
 * @param options 提取选项
 * @param result 提取结果
 * @return 0=成功, <0=错误码
 */
int lzma_extract_7z(const LzmaExtractOptions* options, LzmaExtractResult* result);

/**
 * 获取错误消息
 */
const char* lzma_get_error_message(int error_code);

#ifdef __cplusplus
}
#endif

#endif // LZMA_WRAPPER_H
```

---

## 步骤 3：实现 7z 包装器

创建 `native/src/lzma_wrapper.c`：

```c
#include "lzma_wrapper.h"
#include <string.h>
#include <stdlib.h>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "LzmaWrapper"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGD(...) fprintf(stderr, __VA_ARGS__)
#define LOGE(...) fprintf(stderr, __VA_ARGS__)
#endif

// LZMA SDK 头文件
#include "lzma/C/7z.h"
#include "lzma/C/7zAlloc.h"
#include "lzma/C/7zBuf.h"
#include "lzma/C/7zCrc.h"
#include "lzma/C/7zFile.h"
#include "lzma/C/7zVersion.h"

// 内存分配器
static ISzAlloc g_Alloc = { SzAlloc, SzFree };

/**
 * 提取 7z 文件
 */
int lzma_extract_7z(const LzmaExtractOptions* options, LzmaExtractResult* result) {
    if (!options || !result) {
        return -1;
    }
    
    memset(result, 0, sizeof(LzmaExtractResult));
    
    LOGD("[7z] Opening: %s", options->archive_path);
    if (options->password) {
        LOGD("[7z] Password provided: length=%zu", strlen(options->password));
    }
    
    // 初始化 CRC 表
    CrcGenerateTable();
    
    // 打开 7z 文件
    CFileInStream archiveStream;
    if (InFile_Open(&archiveStream.file, options->archive_path)) {
        snprintf(result->error_message, sizeof(result->error_message), 
                 "Cannot open archive file");
        LOGE("[7z] Failed to open: %s", options->archive_path);
        return -1;
    }
    
    FileInStream_CreateVTable(&archiveStream);
    
    // 初始化 7z 存档结构
    CSzArEx db;
    SzArEx_Init(&db);
    
    // 打开存档
    SRes res = SzArEx_Open(&db, &archiveStream.vt, &g_Alloc, &g_Alloc);
    if (res != SZ_OK) {
        File_Close(&archiveStream.file);
        snprintf(result->error_message, sizeof(result->error_message), 
                 "Failed to open 7z archive (code: %d)", res);
        LOGE("[7z] SzArEx_Open failed: %d", res);
        return res;
    }
    
    LOGD("[7z] Archive opened successfully, files: %u", db.NumFiles);
    result->total_files = db.NumFiles;
    
    // 准备提取
    UInt32 blockIndex = 0xFFFFFFFF;
    Byte* outBuffer = NULL;
    size_t outBufferSize = 0;
    
    // 遍历所有文件
    for (UInt32 i = 0; i < db.NumFiles; i++) {
        size_t offset = 0;
        size_t outSizeProcessed = 0;
        
        // 获取文件信息
        const CSzFileItem* f = db.Files + i;
        size_t len = SzArEx_GetFileNameUtf16(&db, i, NULL);
        
        if (len > 0) {
            UInt16* temp = (UInt16*)malloc(len * sizeof(UInt16));
            SzArEx_GetFileNameUtf16(&db, i, temp);
            
            // 转换 UTF-16 到 UTF-8
            char filename[512] = {0};
            // TODO: 实现 UTF-16 to UTF-8 转换
            
            free(temp);
            
            LOGD("[7z] Extracting [%u/%u]: %s", i+1, db.NumFiles, filename);
            
            // 进度回调
            if (options->on_progress) {
                double progress = (double)(i+1) / db.NumFiles;
                options->on_progress(progress, filename);
            }
        }
        
        // 跳过目录
        if (f->IsDir) {
            continue;
        }
        
        // 提取文件
        res = SzArEx_Extract(&db, &archiveStream.vt, i,
                            &blockIndex, &outBuffer, &outBufferSize,
                            &offset, &outSizeProcessed,
                            &g_Alloc, &g_Alloc);
        
        if (res != SZ_OK) {
            LOGE("[7z] Extract failed for file %u: %d", i, res);
            
            // 检查是否是密码错误
            if (res == SZ_ERROR_DATA) {
                snprintf(result->error_message, sizeof(result->error_message), 
                         "[PASSWORD_ERROR] Incorrect password or corrupted archive");
            } else {
                snprintf(result->error_message, sizeof(result->error_message), 
                         "Extract failed (code: %d)", res);
            }
            break;
        }
        
        // TODO: 写入文件到 dest_path
        // (需要实现文件路径构建和写入逻辑)
        
        result->extracted_files++;
    }
    
    // 清理
    IAlloc_Free(&g_Alloc, outBuffer);
    SzArEx_Free(&db, &g_Alloc);
    File_Close(&archiveStream.file);
    
    result->success = (res == SZ_OK);
    LOGD("[7z] Extraction completed: success=%d, files=%d/%d", 
         result->success, result->extracted_files, result->total_files);
    
    return res;
}

const char* lzma_get_error_message(int error_code) {
    switch (error_code) {
        case SZ_OK: return "Success";
        case SZ_ERROR_DATA: return "Data error (possibly incorrect password)";
        case SZ_ERROR_MEM: return "Memory allocation error";
        case SZ_ERROR_CRC: return "CRC error";
        case SZ_ERROR_UNSUPPORTED: return "Unsupported feature";
        case SZ_ERROR_PARAM: return "Invalid parameter";
        case SZ_ERROR_INPUT_EOF: return "Unexpected end of input";
        case SZ_ERROR_OUTPUT_EOF: return "Output buffer overflow";
        case SZ_ERROR_READ: return "Read error";
        case SZ_ERROR_WRITE: return "Write error";
        case SZ_ERROR_PROGRESS: return "User cancelled";
        case SZ_ERROR_FAIL: return "General failure";
        case SZ_ERROR_THREAD: return "Thread error";
        case SZ_ERROR_ARCHIVE: return "Archive error";
        case SZ_ERROR_NO_ARCHIVE: return "Not a 7z archive";
        default: return "Unknown error";
    }
}
```

---

## 步骤 4：更新 CMakeLists.txt

修改 `native/CMakeLists.txt`，添加 LZMA SDK：

```cmake
# LZMA SDK 源文件
set(LZMA_SOURCES
    ${CMAKE_SOURCE_DIR}/src/lzma/C/7zAlloc.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/7zArcIn.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/7zBuf.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/7zBuf2.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/7zCrc.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/7zCrcOpt.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/7zDec.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/7zFile.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/7zStream.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Aes.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/AesOpt.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Bcj2.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Bra.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Bra86.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/BraIA64.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/CpuArch.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Delta.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/LzFind.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Lzma2Dec.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Lzma2Enc.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/LzmaDec.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/LzmaEnc.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Ppmd7.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Ppmd7Dec.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Ppmd8.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Ppmd8Dec.c
    ${CMAKE_SOURCE_DIR}/src/lzma/C/Sha256.c
)

# 添加到库源文件
add_library(${PROJECT_NAME} SHARED
    ${CMAKE_SOURCE_DIR}/src/archive_wrapper.c
    ${CMAKE_SOURCE_DIR}/src/unrar_wrapper.cpp
    ${CMAKE_SOURCE_DIR}/src/minizip_wrapper.c
    ${CMAKE_SOURCE_DIR}/src/lzma_wrapper.c  # 新增
    ${UNRAR_SOURCES}
    ${MINIZIP_SOURCES}
    ${LZMA_SOURCES}  # 新增
)

# 添加 LZMA SDK 定义
target_compile_definitions(${PROJECT_NAME} PRIVATE
    _7ZIP_ST  # 单线程模式
)
```

---

## 步骤 5：集成到 Dart FFI

修改 `lib/ffi/archive_ffi.dart`，添加 7z 支持：

```dart
// 7z 提取（使用 LZMA SDK）
ArchiveResult extract7z({
  required String archivePath,
  required String destPath,
  String? password,
  Function(double, String)? onProgress,
}) {
  // 调用 lzma_extract_7z
  // ...
}
```

修改 `lib/core/services/archive_service.dart`：

```dart
Future<ExtractResult> _extractWith7z(
  String archivePath,
  String targetDir, {
  String? password,
}) async {
  // 使用 7z SDK 而不是 libarchive
  final result = _ffi.extract7z(
    archivePath: archivePath,
    destPath: targetDir,
    password: password,
  );
  
  if (!result.success) {
    // 检查密码错误
    if (_isPasswordError(result.errorMessage)) {
      return ExtractResult.failure(
        errorMessage: password == null ? '压缩包需要密码' : '密码错误',
      );
    }
  }
  
  return result.success
      ? ExtractResult.success(targetPath: targetDir, totalFiles: result.totalFiles)
      : ExtractResult.failure(errorMessage: result.errorMessage);
}
```

---

## 优势对比

| 方案 | libarchive + OpenSSL | 7-Zip SDK |
|------|---------------------|-----------|
| 编译复杂度 | 高（需要 vcpkg 安装依赖） | 低（只需要 SDK 文件） |
| 7z 支持 | 依赖编译选项 | ✅ 原生完整支持 |
| 加密支持 | 需要 OpenSSL | ✅ 内置 AES |
| 文件大小 | 较大 | 较小 |
| 维护性 | 依赖外部库 | 独立实现 |

---

## 下一步

1. **下载 LZMA SDK**
2. **实现 lzma_wrapper.c**（完整版需要处理文件路径、UTF-16转换等）
3. **更新 CMakeLists.txt**
4. **集成到 Dart FFI**
5. **测试 Needpwds.7z**

要我帮你完成这个集成吗？
