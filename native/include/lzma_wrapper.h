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

// 文件信息回调
typedef void (*LzmaProgressCallback)(double progress, const char* filename, void* user_data);

// 提取选项
typedef struct {
    const char* archive_path;
    const char* dest_path;
    const char* password;      // 可选密码
    bool overwrite;
    LzmaProgressCallback on_progress;
    void* user_data;
} LzmaExtractOptions;

/**
 * 使用 LZMA SDK 提取 7z 文件
 * 
 * @param options 提取选项
 * @param result 提取结果
 * @return 0=成功, 非0=LZMA错误码
 */
int lzma_extract_7z(const LzmaExtractOptions* options, LzmaExtractResult* result);

/**
 * 获取错误消息
 */
const char* lzma_get_error_message(int error_code);

/**
 * 检查是否是密码错误
 */
bool lzma_is_password_error(int error_code);

#ifdef __cplusplus
}
#endif

#endif // LZMA_WRAPPER_H
