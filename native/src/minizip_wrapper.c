#include "minizip_wrapper.h"
#include "minizip-ng/mz.h"
#include "minizip-ng/mz_strm.h"
#include "minizip-ng/mz_zip.h"
#include "minizip-ng/mz_zip_rw.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/stat.h>
#include <errno.h>
#include <unistd.h>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "MinizipWrapper"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGD(...)
#define LOGI(...)
#define LOGE(...)
#endif

// 安全字符串拷贝
static void safe_strncpy(char* dest, const char* src, size_t size) {
    if (dest && src && size > 0) {
        strncpy(dest, src, size - 1);
        dest[size - 1] = '\0';
    }
}

int minizip_list_contents(const char* archive_path, MinizipListResult* result) {
    if (archive_path == NULL || result == NULL) {
        return MINIZIP_ERR_INVALID_PATH;
    }
    
    memset(result, 0, sizeof(MinizipListResult));
    
    LOGI("开始列出ZIP内容: %s", archive_path);
    
    // 创建ZIP读取器
    void* zip_reader = mz_zip_reader_create();
    if (zip_reader == NULL) {
        LOGE("创建ZIP读取器失败");
        safe_strncpy(result->error_message, "Failed to create zip reader", 
                     sizeof(result->error_message));
        return MINIZIP_ERR_OPEN_FAILED;
    }
    
    // 不设置编码，让minizip-ng返回原始字节流
    // 这样GBK编码的文件名会以原始字节传递给Dart层处理
    
    // 打开ZIP文件
    int32_t err = mz_zip_reader_open_file(zip_reader, archive_path);
    if (err != MZ_OK) {
        LOGE("打开ZIP文件失败: error=%d, path=%s", err, archive_path);
        snprintf(result->error_message, sizeof(result->error_message),
                 "Failed to open zip file (error: %d)", err);
        mz_zip_reader_delete(&zip_reader);
        return MINIZIP_ERR_OPEN_FAILED;
    }
    
    // 移动到第一个条目
    err = mz_zip_reader_goto_first_entry(zip_reader);
    if (err != MZ_OK && err != MZ_END_OF_LIST) {
        LOGE("无法读取第一个条目: error=%d", err);
        safe_strncpy(result->error_message, "Failed to read first entry", 
                     sizeof(result->error_message));
        mz_zip_reader_close(zip_reader);
        mz_zip_reader_delete(&zip_reader);
        return MINIZIP_ERR_READ_FAILED;
    }
    
    // 第一遍：计数
    int64_t count = 0;
    if (err == MZ_OK) {
        do {
            count++;
            err = mz_zip_reader_goto_next_entry(zip_reader);
        } while (err == MZ_OK);
    }
    
    LOGI("ZIP文件包含 %lld 个条目", (long long)count);
    
    if (count == 0) {
        LOGI("ZIP文件为空");
        result->status = MINIZIP_OK;
        result->entry_count = 0;
        result->entries = NULL;
        mz_zip_reader_close(zip_reader);
        mz_zip_reader_delete(&zip_reader);
        return MINIZIP_OK;
    }
    
    // 分配内存
    result->entries = (MinizipEntry*)calloc(count, sizeof(MinizipEntry));
    if (result->entries == NULL) {
        LOGE("内存分配失败");
        safe_strncpy(result->error_message, "Memory allocation failed", 
                     sizeof(result->error_message));
        mz_zip_reader_close(zip_reader);
        mz_zip_reader_delete(&zip_reader);
        return MINIZIP_ERR_MEMORY;
    }
    result->entry_count = count;
    
    // 第二遍：读取条目信息
    err = mz_zip_reader_goto_first_entry(zip_reader);
    int64_t index = 0;
    
    while (err == MZ_OK && index < count) {
        mz_zip_file* file_info = NULL;
        
        // 获取当前条目信息
        err = mz_zip_reader_entry_get_info(zip_reader, &file_info);
        if (err != MZ_OK || file_info == NULL) {
            LOGE("读取条目信息失败: index=%lld, error=%d", (long long)index, err);
            index++;
            err = mz_zip_reader_goto_next_entry(zip_reader);
            continue;
        }
        
        MinizipEntry* entry = &result->entries[index];
        
        // 文件名（minizip-ng已处理编码转换）
        const char* filename = file_info->filename;
        if (filename == NULL || strlen(filename) == 0) {
            filename = "Unknown";
        }
        
        // 调试：打印文件名的十六进制
        LOGD("原始文件名字节 (前20字节):");
        for (int i = 0; i < 20 && filename[i] != '\0'; i++) {
            LOGD("  [%d] = 0x%02X (%c)", i, (unsigned char)filename[i], 
                 (filename[i] >= 32 && filename[i] < 127) ? filename[i] : '.');
        }
        
        // 保存显示用的文件名（可能经过编码转换）
        safe_strncpy(entry->name, filename, sizeof(entry->name));
        safe_strncpy(entry->pathname, filename, sizeof(entry->pathname));
        
        // 保存原始路径（ZIP内部的原始字节，用于后续提取）
        safe_strncpy(entry->raw_pathname, filename, sizeof(entry->raw_pathname));
        
        // 文件信息
        entry->size = file_info->uncompressed_size;
        entry->compressed_size = file_info->compressed_size;
        entry->mtime = file_info->modified_date;
        entry->crc32 = file_info->crc;
        
        // 判断是否为目录
        entry->is_directory = mz_zip_reader_entry_is_dir(zip_reader) == MZ_OK;
        
        LOGD("条目 %lld: %s (size=%lld, compressed=%lld, dir=%d)", 
             (long long)index, entry->name, 
             (long long)entry->size, (long long)entry->compressed_size,
             entry->is_directory);
        
        index++;
        err = mz_zip_reader_goto_next_entry(zip_reader);
    }
    
    // 清理
    mz_zip_reader_close(zip_reader);
    mz_zip_reader_delete(&zip_reader);
    
    result->status = MINIZIP_OK;
    LOGI("ZIP内容列出成功: %lld 个条目", (long long)result->entry_count);
    return MINIZIP_OK;
}

void minizip_free_list_result(MinizipListResult* result) {
    if (result != NULL && result->entries != NULL) {
        free(result->entries);
        result->entries = NULL;
        result->entry_count = 0;
    }
}

bool minizip_is_zip_file(const char* archive_path) {
    if (archive_path == NULL) {
        return false;
    }
    
    void* zip_reader = mz_zip_reader_create();
    if (zip_reader == NULL) {
        return false;
    }
    
    int32_t err = mz_zip_reader_open_file(zip_reader, archive_path);
    bool is_valid = (err == MZ_OK);
    
    if (is_valid) {
        mz_zip_reader_close(zip_reader);
    }
    mz_zip_reader_delete(&zip_reader);
    
    return is_valid;
}

// ==================== 解压缩实现 ====================

static int ensure_directory(const char* path) {
    char temp[2048];
    char* p = NULL;
    size_t len;

    snprintf(temp, sizeof(temp), "%s", path);
    len = strlen(temp);
    if (temp[len - 1] == '/') {
        temp[len - 1] = 0;
    }
    
    for (p = temp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            if (access(temp, F_OK) != 0) {
                if (mkdir(temp, 0755) != 0 && errno != EEXIST) {
                    return -1;
                }
            }
            *p = '/';
        }
    }
    
    if (access(temp, F_OK) != 0) {
        if (mkdir(temp, 0755) != 0 && errno != EEXIST) {
            return -1;
        }
    }
    
    return 0;
}

int minizip_extract_archive(const char* archive_path, 
                           const char* target_dir,
                           const char* password,
                           MinizipExtractResult* result) {
    if (!archive_path || !target_dir || !result) {
        return MINIZIP_ERR_INVALID_PATH;
    }
    
    memset(result, 0, sizeof(MinizipExtractResult));
    
    // 创建目标目录
    if (ensure_directory(target_dir) != 0) {
        snprintf(result->error_message, sizeof(result->error_message),
                 "Failed to create target directory: %s", target_dir);
        result->status = MINIZIP_ERR_INVALID_PATH;
        return MINIZIP_ERR_INVALID_PATH;
    }
    
    // 创建reader
    void* zip_reader = mz_zip_reader_create();
    if (!zip_reader) {
        snprintf(result->error_message, sizeof(result->error_message),
                 "Failed to create zip reader");
        result->status = MINIZIP_ERR_MEMORY;
        return MINIZIP_ERR_MEMORY;
    }
    
    // 设置编码：输出UTF-8，这样文件名会被转换为UTF-8
    mz_zip_reader_set_encoding(zip_reader, 65001); // UTF-8
    
    // 设置密码
    if (password && strlen(password) > 0) {
        mz_zip_reader_set_password(zip_reader, password);
    }
    
    // 打开文件
    int32_t err = mz_zip_reader_open_file(zip_reader, archive_path);
    if (err != MZ_OK) {
        snprintf(result->error_message, sizeof(result->error_message),
                 "Failed to open archive: %d", err);
        mz_zip_reader_delete(&zip_reader);
        result->status = MINIZIP_ERR_OPEN_FAILED;
        return MINIZIP_ERR_OPEN_FAILED;
    }
    
    // 计数总文件数
    err = mz_zip_reader_goto_first_entry(zip_reader);
    while (err == MZ_OK) {
        mz_zip_file* file_info = NULL;
        err = mz_zip_reader_entry_get_info(zip_reader, &file_info);
        if (err == MZ_OK && file_info) {
            result->total_files++;
        }
        err = mz_zip_reader_goto_next_entry(zip_reader);
    }
    
    // 开始解压
    err = mz_zip_reader_goto_first_entry(zip_reader);
    while (err == MZ_OK) {
        mz_zip_file* file_info = NULL;
        err = mz_zip_reader_entry_get_info(zip_reader, &file_info);
        if (err != MZ_OK || !file_info) {
            break;
        }
        
        // 构建输出路径
        char output_path[2048];
        snprintf(output_path, sizeof(output_path), "%s/%s", 
                 target_dir, file_info->filename);
        
        // 如果是目录
        if (mz_zip_reader_entry_is_dir(zip_reader) == MZ_OK) {
            if (ensure_directory(output_path) != 0) {
                snprintf(result->error_message, sizeof(result->error_message),
                         "Failed to create directory: %s", output_path);
                result->status = MINIZIP_ERR_OPEN_FAILED;
                break;
            }
            result->extracted_files++;
        } else {
            // 确保父目录存在
            char* last_slash = strrchr(output_path, '/');
            if (last_slash) {
                char parent_dir[2048];
                size_t parent_len = last_slash - output_path;
                memcpy(parent_dir, output_path, parent_len);
                parent_dir[parent_len] = '\0';
                
                if (ensure_directory(parent_dir) != 0) {
                    snprintf(result->error_message, sizeof(result->error_message),
                             "Failed to create parent directory: %s", parent_dir);
                    result->status = MINIZIP_ERR_OPEN_FAILED;
                    break;
                }
            }
            
            // 解压文件
            err = mz_zip_reader_entry_save_file(zip_reader, output_path);
            if (err != MZ_OK) {
                snprintf(result->error_message, sizeof(result->error_message),
                         "Failed to extract file: %s (error: %d)", 
                         file_info->filename, err);
                result->status = MINIZIP_ERR_READ_FAILED;
                break;
            }
            result->extracted_files++;
        }
        
        err = mz_zip_reader_goto_next_entry(zip_reader);
    }
    
    mz_zip_reader_close(zip_reader);
    mz_zip_reader_delete(&zip_reader);
    
    // 检查是否完全成功
    if (result->status == 0) {
        result->status = MINIZIP_OK;
    }
    
    return result->status;
}

int minizip_extract_single_file(const char* archive_path,
                               const char* entry_path_raw,
                               const char* output_path,
                               const char* password,
                               MinizipExtractFileResult* result) {
    if (!archive_path || !entry_path_raw || !output_path || !result) {
        return MINIZIP_ERR_INVALID_PATH;
    }
    
    memset(result, 0, sizeof(MinizipExtractFileResult));
    
    // 创建reader
    void* zip_reader = mz_zip_reader_create();
    if (!zip_reader) {
        snprintf(result->error_message, sizeof(result->error_message),
                 "Failed to create zip reader");
        result->status = MINIZIP_ERR_MEMORY;
        return MINIZIP_ERR_MEMORY;
    }
    
    // 不设置encoding，保持原始字节用于查找
    
    // 设置密码
    if (password && strlen(password) > 0) {
        mz_zip_reader_set_password(zip_reader, password);
    }
    
    // 打开文件
    int32_t err = mz_zip_reader_open_file(zip_reader, archive_path);
    if (err != MZ_OK) {
        snprintf(result->error_message, sizeof(result->error_message),
                 "Failed to open archive: %d", err);
        mz_zip_reader_delete(&zip_reader);
        result->status = MINIZIP_ERR_OPEN_FAILED;
        return MINIZIP_ERR_OPEN_FAILED;
    }
    
    // 用原始路径定位文件（GBK字节）
    err = mz_zip_reader_locate_entry(zip_reader, entry_path_raw, 0);
    if (err != MZ_OK) {
        snprintf(result->error_message, sizeof(result->error_message),
                 "Failed to locate entry: %s", entry_path_raw);
        mz_zip_reader_close(zip_reader);
        mz_zip_reader_delete(&zip_reader);
        result->status = MINIZIP_ERR_READ_FAILED;
        return MINIZIP_ERR_READ_FAILED;
    }
    
    // 获取文件信息
    mz_zip_file* file_info = NULL;
    err = mz_zip_reader_entry_get_info(zip_reader, &file_info);
    if (err != MZ_OK || !file_info) {
        snprintf(result->error_message, sizeof(result->error_message),
                 "Failed to get entry info");
        mz_zip_reader_close(zip_reader);
        mz_zip_reader_delete(&zip_reader);
        result->status = MINIZIP_ERR_READ_FAILED;
        return MINIZIP_ERR_READ_FAILED;
    }
    
    result->file_size = file_info->uncompressed_size;
    strncpy(result->output_path, output_path, sizeof(result->output_path) - 1);
    
    // 确保父目录存在
    char parent_dir[2048];
    strncpy(parent_dir, output_path, sizeof(parent_dir) - 1);
    char* last_slash = strrchr(parent_dir, '/');
    if (last_slash) {
        *last_slash = '\0';
        if (ensure_directory(parent_dir) != 0) {
            snprintf(result->error_message, sizeof(result->error_message),
                     "Failed to create parent directory: %s", parent_dir);
            mz_zip_reader_close(zip_reader);
            mz_zip_reader_delete(&zip_reader);
            result->status = MINIZIP_ERR_OPEN_FAILED;
            return MINIZIP_ERR_OPEN_FAILED;
        }
    }
    
    // 打开entry准备读取
    err = mz_zip_reader_entry_open(zip_reader);
    if (err != MZ_OK) {
        // 错误码 -108 (MZ_PASSWORD_ERROR) 表示密码错误或需要密码
        if (err == -108 || err == -3 || err == -10) {
            snprintf(result->error_message, sizeof(result->error_message),
                     "Password required or incorrect");
        } else {
            snprintf(result->error_message, sizeof(result->error_message),
                     "Failed to open entry for reading (error code: %d)", err);
        }
        mz_zip_reader_close(zip_reader);
        mz_zip_reader_delete(&zip_reader);
        result->status = MINIZIP_ERR_READ_FAILED;
        return MINIZIP_ERR_READ_FAILED;
    }
    
    // 创建输出文件
    FILE* out_file = fopen(output_path, "wb");
    if (!out_file) {
        snprintf(result->error_message, sizeof(result->error_message),
                 "Failed to create output file: %s", output_path);
        mz_zip_reader_entry_close(zip_reader);
        mz_zip_reader_close(zip_reader);
        mz_zip_reader_delete(&zip_reader);
        result->status = MINIZIP_ERR_OPEN_FAILED;
        return MINIZIP_ERR_OPEN_FAILED;
    }
    
    // 读取并写入文件
    char buffer[8192];
    int32_t bytes_read = 0;
    while ((bytes_read = mz_zip_reader_entry_read(zip_reader, buffer, sizeof(buffer))) > 0) {
        if (fwrite(buffer, 1, bytes_read, out_file) != (size_t)bytes_read) {
            snprintf(result->error_message, sizeof(result->error_message),
                     "Failed to write to output file");
            fclose(out_file);
            remove(output_path); // 删除损坏的文件
            mz_zip_reader_entry_close(zip_reader);
            mz_zip_reader_close(zip_reader);
            mz_zip_reader_delete(&zip_reader);
            result->status = MINIZIP_ERR_READ_FAILED;
            return MINIZIP_ERR_READ_FAILED;
        }
    }
    
    fclose(out_file);
    
    if (bytes_read < 0) {
        // 删除损坏的输出文件
        remove(output_path);
        
        // 错误码 -3 (MZ_PASSWORD_ERROR) 表示密码错误或需要密码
        // 错误码 -10 (MZ_CRC_ERROR) 也可能表示密码错误
        if (bytes_read == MZ_PASSWORD_ERROR || bytes_read == -3 || bytes_read == -10) {
            snprintf(result->error_message, sizeof(result->error_message),
                     "Password required or incorrect");
        } else {
            snprintf(result->error_message, sizeof(result->error_message),
                     "Failed to read entry data (error code: %d)", bytes_read);
        }
        mz_zip_reader_entry_close(zip_reader);
        mz_zip_reader_close(zip_reader);
        mz_zip_reader_delete(&zip_reader);
        result->status = MINIZIP_ERR_READ_FAILED;
        return MINIZIP_ERR_READ_FAILED;
    }
    
    mz_zip_reader_entry_close(zip_reader);
    mz_zip_reader_close(zip_reader);
    mz_zip_reader_delete(&zip_reader);
    
    result->status = MINIZIP_OK;
    return MINIZIP_OK;
}

void minizip_free_extract_result(MinizipExtractResult* result) {
    // 当前结构无需释放额外内存
    if (result) {
        memset(result, 0, sizeof(MinizipExtractResult));
    }
}

void minizip_free_extract_file_result(MinizipExtractFileResult* result) {
    // 当前结构无需释放额外内存
    if (result) {
        memset(result, 0, sizeof(MinizipExtractFileResult));
    }
}
