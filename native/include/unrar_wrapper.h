#ifndef UNRAR_WRAPPER_H
#define UNRAR_WRAPPER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ==================== PoC: 最小化UnRAR封装 ====================

/// RAR文件条目（简化版）
typedef struct {
    char filename[2048];          // 文件名（UTF-8编码）
    int64_t size;                 // 未压缩大小
    int64_t packed_size;          // 压缩大小
    bool is_directory;            // 是否目录
} UnrarEntry;

/// RAR列表结果
typedef struct {
    int status;                   // 0=成功, 非0=错误
    int64_t entry_count;          // 条目数量
    UnrarEntry* entries;          // 条目数组
    char error_message[512];      // 错误消息
} UnrarListResult;

// ==================== PoC API ====================

/// 列出RAR文件内容
/// @param rar_path RAR文件路径
/// @param result 输出结果
/// @return 0=成功, 非0=失败
int unrar_list_contents(const char* rar_path, UnrarListResult* result);

/// 释放列表结果
void unrar_free_list_result(UnrarListResult* result);

/// 检查文件是否为RAR格式（通过文件头）
bool unrar_is_rar_file(const char* file_path);

/// 获取UnRAR版本信息（用于验证库已正确加载）
const char* unrar_get_version();

// ==================== 解压功能 ====================

/// 解压进度回调
/// @param current 当前进度（已处理字节）
/// @param total 总大小（字节）
/// @param filename 当前文件名
typedef void (*UnrarProgressCallback)(int64_t current, int64_t total, const char* filename);

/// 解压结果
typedef struct {
    int status;                   // 0=成功, 非0=错误
    int64_t extracted_count;      // 成功解压的文件数
    int64_t skipped_count;        // 跳过的文件数
    int64_t failed_count;         // 失败的文件数
    char error_message[512];      // 错误消息
} UnrarExtractResult;

/// 解压RAR文件到指定目录
/// @param rar_path RAR文件路径
/// @param dest_path 目标目录路径
/// @param password 密码（可选，传NULL表示无密码）
/// @param result 输出结果
/// @param progress_callback 进度回调（可选）
/// @return 0=成功, 非0=失败
int unrar_extract(
    const char* rar_path,
    const char* dest_path,
    const char* password,
    UnrarExtractResult* result,
    UnrarProgressCallback progress_callback
);

/// 解压RAR中的单个文件
/// @param rar_path RAR文件路径
/// @param filename 要解压的文件名（RAR内路径）
/// @param dest_path 目标文件路径
/// @param password 密码（可选）
/// @return 0=成功, 非0=失败
int unrar_extract_file(
    const char* rar_path,
    const char* filename,
    const char* dest_path,
    const char* password
);

#ifdef __cplusplus
}
#endif

#endif // UNRAR_WRAPPER_H
