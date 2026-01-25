#ifndef ARCHIVE_WRAPPER_H
#define ARCHIVE_WRAPPER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ==================== 数据结构 ====================

/// 解压进度回调
typedef void (*ProgressCallback)(
    double progress,      // 0.0 - 1.0
    const char* filename,
    int64_t current_size,
    int64_t total_size
);

/// 解压选项
typedef struct {
    const char* archive_path;     // 压缩包路径
    const char* dest_path;        // 目标路径
    bool overwrite;               // 是否覆盖
    bool preserve_permissions;    // 保留权限
    const char* password;         // 密码（可为 NULL）
    ProgressCallback on_progress; // 进度回调
    void* user_data;              // 用户数据
} ExtractOptions;

/// 解压结果
typedef struct {
    int status;                   // 0=成功, 非0=错误码
    int64_t total_files;          // 总文件数
    int64_t extracted_files;      // 已解压文件数
    int64_t total_bytes;          // 总字节数
    char error_message[512];      // 错误消息
} ExtractResult;

/// 文件条目信息
typedef struct {
    char name[1024];              // 文件名（UTF-8或尝试转换后）
    char pathname[2048];          // 完整路径（UTF-8或尝试转换后）
    int64_t size;                 // 未压缩大小
    int64_t compressed_size;      // 压缩后大小
    int64_t mtime;                // 修改时间 (Unix timestamp)
    bool is_directory;            // 是否是目录
    uint32_t mode;                // 权限模式
    uint32_t crc32;               // CRC32 校验
} ArchiveEntry;

/// 列表结果
typedef struct {
    int status;                   // 0=成功, 非0=错误码
    int64_t entry_count;          // 条目数量
    ArchiveEntry* entries;        // 条目数组
    char error_message[512];      // 错误消息
} ListResult;

/// 单文件提取结果
typedef struct {
    bool success;                 // 是否成功
    int64_t extracted_size;       // 提取的文件大小（字节）
    char error_message[512];      // 错误消息
} SingleFileExtractResult;

// ==================== 核心 API ====================

/// 解压压缩包
/// @param options 解压选项
/// @param result 解压结果（输出参数）
/// @return 句柄 ID（用于取消），失败返回 -1
int64_t archive_extract_async(
    const ExtractOptions* options,
    ExtractResult* result
);

/// 取消解压
/// @param handle_id archive_extract_async 返回的句柄
/// @return true=成功取消, false=失败
bool archive_cancel(int64_t handle_id);

/// 列出压缩包内容
/// @param archive_path 压缩包路径
/// @param result 列表结果（输出参数）
/// @return 0=成功, 非0=错误码
int archive_list_contents(
    const char* archive_path,
    ListResult* result
);

/// 释放列表结果
/// @param result 由 archive_list_contents 返回的结果
void archive_free_list_result(ListResult* result);

/// 验证压缩包
/// @param archive_path 压缩包路径
/// @return 0=有效, 非0=无效（错误码）
int archive_validate(const char* archive_path);

/// 提取单个文件
/// @param archive_path 压缩包路径
/// @param entry_path 条目在压缩包中的路径
/// @param output_path 输出文件路径
/// @param password 密码（可为 NULL）
/// @param result 提取结果（输出参数）
/// @return 0=成功, 非0=错误码
int archive_extract_single_file(
    const char* archive_path,
    const char* entry_path,
    const char* output_path,
    const char* password,
    SingleFileExtractResult* result
);

/// 获取错误消息
/// @param error_code 错误码
/// @return 错误描述字符串
const char* archive_get_error_message(int error_code);

// ==================== 错误码定义 ====================

#define ARCHIVE_OK                0
#define ARCHIVE_ERR_INVALID_PATH  1
#define ARCHIVE_ERR_OPEN_FAILED   2
#define ARCHIVE_ERR_READ_FAILED   3
#define ARCHIVE_ERR_WRITE_FAILED  4
#define ARCHIVE_ERR_FORMAT        5
#define ARCHIVE_ERR_CANCELLED     6
#define ARCHIVE_ERR_MEMORY        7
#define ARCHIVE_ERR_PERMISSION    8

#ifdef __cplusplus
}
#endif

#endif // ARCHIVE_WRAPPER_H
