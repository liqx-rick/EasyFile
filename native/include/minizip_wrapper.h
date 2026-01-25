#ifndef MINIZIP_WRAPPER_H
#define MINIZIP_WRAPPER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ==================== 数据结构 ====================

typedef struct {
    char name[1024];              // 文件名
    char pathname[2048];          // 完整路径（用于显示，可能经过编码转换）
    char raw_pathname[2048];      // 原始路径（ZIP内部的原始字节，用于提取）
    int64_t size;                 // 原始大小
    int64_t compressed_size;      // 压缩后大小
    int64_t mtime;                // 修改时间（Unix时间戳）
    bool is_directory;            // 是否目录
    uint32_t crc32;               // CRC32校验
} MinizipEntry;

typedef struct {
    int status;                   // 状态码 (0=成功)
    int64_t entry_count;          // 条目数量
    MinizipEntry* entries;        // 条目数组
    char error_message[512];      // 错误消息
} MinizipListResult;

typedef struct {
    int status;                   // 状态码 (0=成功)
    int64_t total_files;          // 总文件数
    int64_t extracted_files;      // 已解压文件数
    char error_message[512];      // 错误消息
} MinizipExtractResult;

typedef struct {
    int status;                   // 状态码 (0=成功)
    int64_t file_size;            // 文件大小
    char output_path[2048];       // 输出路径
    char error_message[512];      // 错误消息
} MinizipExtractFileResult;

// ==================== 核心API ====================

/// 列出ZIP压缩包内容（支持中文编码自动检测）
/// @param archive_path ZIP文件路径
/// @param result 输出结果
/// @return 0=成功, 非0=错误码
int minizip_list_contents(
    const char* archive_path,
    MinizipListResult* result
);

/// 释放列表结果内存
void minizip_free_list_result(MinizipListResult* result);

/// 检查是否为有效的ZIP文件
bool minizip_is_zip_file(const char* archive_path);

/// 解压整个ZIP压缩包
/// @param archive_path ZIP文件路径
/// @param target_dir 目标解压目录
/// @param password 密码（可为NULL）
/// @param result 输出结果
/// @return 0=成功, 非0=错误码
int minizip_extract_archive(
    const char* archive_path,
    const char* target_dir,
    const char* password,
    MinizipExtractResult* result
);

/// 解压单个文件（用于预览）
/// @param archive_path ZIP文件路径
/// @param entry_path_raw 压缩包内文件原始路径（用于查找，原始GBK字节）
/// @param output_path 输出文件路径（UTF-8编码）
/// @param password 密码（可为NULL）
/// @param result 输出结果
/// @return 0=成功, 非0=错误码
int minizip_extract_single_file(
    const char* archive_path,
    const char* entry_path_raw,
    const char* output_path,
    const char* password,
    MinizipExtractFileResult* result
);

/// 释放解压结果内存
void minizip_free_extract_result(MinizipExtractResult* result);

/// 释放单文件解压结果内存
void minizip_free_extract_file_result(MinizipExtractFileResult* result);

// ==================== 错误码 ====================

#define MINIZIP_OK                0
#define MINIZIP_ERR_INVALID_PATH  1
#define MINIZIP_ERR_OPEN_FAILED   2
#define MINIZIP_ERR_READ_FAILED   3
#define MINIZIP_ERR_NOT_ZIP       4
#define MINIZIP_ERR_MEMORY        5

#ifdef __cplusplus
}
#endif

#endif // MINIZIP_WRAPPER_H
