#include "archive_wrapper.h"
#include <archive.h>
#include <archive_entry.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
#include <locale.h>

// 全局状态管理（用于取消操作）
typedef struct {
    int64_t handle_id;
    bool cancelled;
    struct archive* archive;
} ExtractionHandle;

static ExtractionHandle* g_handles = NULL;
static int g_handle_count = 0;
static int64_t g_next_handle_id = 1;

// ==================== 内部工具函数 ====================

static ExtractionHandle* create_handle(struct archive* a) {
    g_handles = realloc(g_handles, sizeof(ExtractionHandle) * (g_handle_count + 1));
    ExtractionHandle* handle = &g_handles[g_handle_count];
    handle->handle_id = g_next_handle_id++;
    handle->cancelled = false;
    handle->archive = a;
    g_handle_count++;
    return handle;
}

static ExtractionHandle* find_handle(int64_t handle_id) {
    for (int i = 0; i < g_handle_count; i++) {
        if (g_handles[i].handle_id == handle_id) {
            return &g_handles[i];
        }
    }
    return NULL;
}

static void remove_handle(int64_t handle_id) {
    for (int i = 0; i < g_handle_count; i++) {
        if (g_handles[i].handle_id == handle_id) {
            // 移动后续元素
            memmove(&g_handles[i], &g_handles[i + 1], 
                    (g_handle_count - i - 1) * sizeof(ExtractionHandle));
            g_handle_count--;
            g_handles = realloc(g_handles, sizeof(ExtractionHandle) * g_handle_count);
            break;
        }
    }
}

static void safe_strncpy(char* dest, const char* src, size_t size) {
    if (src == NULL) {
        dest[0] = '\0';
        return;
    }
    strncpy(dest, src, size - 1);
    dest[size - 1] = '\0';
}

// ==================== 核心 API 实现 ====================

int64_t archive_extract_async(const ExtractOptions* options, ExtractResult* result) {
    if (options == NULL || result == NULL) {
        return -1;
    }

    memset(result, 0, sizeof(ExtractResult));
    
    // 设置 locale 为 UTF-8 以支持 Unicode 文件名
    setlocale(LC_ALL, "en_US.UTF-8");
    
    struct archive* a = archive_read_new();
    struct archive* ext = archive_write_disk_new();
    struct archive_entry* entry;
    
    // 创建句柄用于取消操作
    ExtractionHandle* handle = create_handle(a);
    
    // 支持所有格式和压缩算法
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    
    // 设置 libarchive 选项以更好地处理 Unicode
    // 对所有格式设置 hdrcharset
    archive_read_set_options(a, "hdrcharset=UTF-8,CP936");
    archive_read_set_options(a, "rar:hdrcharset=UTF-8");
    
    // 设置写入选项
    int flags = ARCHIVE_EXTRACT_TIME;
    if (options->preserve_permissions) {
        flags |= ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_ACL | ARCHIVE_EXTRACT_FFLAGS;
    }
    archive_write_disk_set_options(ext, flags);
    archive_write_disk_set_standard_lookup(ext);
    
    // 打开压缩包
    int r = archive_read_open_filename(a, options->archive_path, 10240);
    if (r != ARCHIVE_OK) {
        safe_strncpy(result->error_message, archive_error_string(a), 
                     sizeof(result->error_message));
        result->status = ARCHIVE_ERR_OPEN_FAILED;
        archive_read_free(a);
        archive_write_free(ext);
        remove_handle(handle->handle_id);
        return -1;
    }
    
    // 计算总大小（用于进度）
    int64_t total_size = 0;
    int64_t current_size = 0;
    int64_t file_count = 0;
    
    // 第一遍：计算总大小并检查格式
    const char* format_name = archive_format_name(a);
    int first_pass_error = ARCHIVE_OK;
    
    while ((r = archive_read_next_header(a, &entry)) == ARCHIVE_OK) {
        total_size += archive_entry_size(entry);
        file_count++;
        archive_read_data_skip(a);
    }
    
    // 记录第一遍扫描的错误
    if (r != ARCHIVE_EOF) {
        first_pass_error = r;
    }
    
    result->total_files = file_count;
    result->total_bytes = total_size;
    
    // 如果没有文件，记录格式信息
    if (file_count == 0) {
        if (format_name != NULL && strlen(format_name) > 0) {
            char msg[512];
            snprintf(msg, sizeof(msg), "Unsupported or encrypted format: %s", format_name);
            safe_strncpy(result->error_message, msg, sizeof(result->error_message));
        } else {
            safe_strncpy(result->error_message, 
                         "Archive format not recognized or encrypted", 
                         sizeof(result->error_message));
        }
        result->status = ARCHIVE_ERR_OPEN_FAILED;
        archive_read_close(a);
        archive_read_free(a);
        archive_write_free(ext);
        remove_handle(handle->handle_id);
        return -1;
    }
    
    // 重新打开压缩包进行实际解压
    archive_read_close(a);
    archive_read_free(a);
    a = archive_read_new();
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    
    // 再次设置选项
    archive_read_set_options(a, "rar:hdrcharset=UTF-8");
    
    archive_read_open_filename(a, options->archive_path, 10240);
    handle->archive = a;
    
    // 第二遍：实际解压
    while ((r = archive_read_next_header(a, &entry)) == ARCHIVE_OK) {
        // 检查是否被取消
        if (handle->cancelled) {
            safe_strncpy(result->error_message, "Operation cancelled by user", 
                         sizeof(result->error_message));
            result->status = ARCHIVE_ERR_CANCELLED;
            archive_read_close(a);
            archive_read_free(a);
            archive_write_close(ext);
            archive_write_free(ext);
            remove_handle(handle->handle_id);
            return handle->handle_id;
        }
        
        // Try UTF-8 pathname first
        const char* pathname_utf8 = archive_entry_pathname_utf8(entry);
        const char* current_file = pathname_utf8 ? pathname_utf8 : archive_entry_pathname(entry);
        
        if (current_file == NULL) {
            continue;
        }
        
        // 构造完整路径
        char full_path[4096];
        snprintf(full_path, sizeof(full_path), "%s/%s", 
                 options->dest_path, current_file);
        archive_entry_set_pathname(entry, full_path);
        
        // 写入文件
        r = archive_write_header(ext, entry);
        if (r == ARCHIVE_OK) {
            const void* buff;
            size_t size;
            int64_t offset;
            
            while ((r = archive_read_data_block(a, &buff, &size, &offset)) == ARCHIVE_OK) {
                archive_write_data_block(ext, buff, size, offset);
                current_size += size;
                
                // 进度回调
                if (options->on_progress != NULL && total_size > 0) {
                    double progress = (double)current_size / (double)total_size;
                    options->on_progress(progress, current_file, current_size, total_size);
                }
            }
            
            if (r != ARCHIVE_EOF) {
                safe_strncpy(result->error_message, archive_error_string(a), 
                             sizeof(result->error_message));
            }
        }
        
        archive_write_finish_entry(ext);
        result->extracted_files++;
    }
    
    // 清理资源
    archive_read_close(a);
    archive_read_free(a);
    archive_write_close(ext);
    archive_write_free(ext);
    
    int64_t handle_id = handle->handle_id;
    remove_handle(handle_id);
    
    result->status = ARCHIVE_OK;
    return handle_id;
}

bool archive_cancel(int64_t handle_id) {
    ExtractionHandle* handle = find_handle(handle_id);
    if (handle != NULL) {
        handle->cancelled = true;
        return true;
    }
    return false;
}

int archive_list_contents(const char* archive_path, ListResult* result) {
    if (archive_path == NULL || result == NULL) {
        return ARCHIVE_ERR_INVALID_PATH;
    }

    memset(result, 0, sizeof(ListResult));
    
    setlocale(LC_ALL, "en_US.UTF-8");
    
    struct archive* a = archive_read_new();
    struct archive_entry* entry;
    
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    
    // 设置 libarchive 选项以更好地处理 Unicode
    // 对所有格式设置 hdrcharset
    archive_read_set_options(a, "hdrcharset=UTF-8,CP936");
    archive_read_set_options(a, "rar:hdrcharset=UTF-8");
    
    int r = archive_read_open_filename(a, archive_path, 10240);
    if (r != ARCHIVE_OK) {
        safe_strncpy(result->error_message, archive_error_string(a),
                     sizeof(result->error_message));
        result->status = ARCHIVE_ERR_OPEN_FAILED;
        archive_read_free(a);
        return result->status;
    }
    
    // 检查格式
    const char* format_name = archive_format_name(a);
    
    // 第一遍：计数并检查错误
    int64_t count = 0;
    int last_error = ARCHIVE_OK;
    const char* last_error_msg = NULL;
    
    while ((r = archive_read_next_header(a, &entry)) == ARCHIVE_OK) {
        count++;
        archive_read_data_skip(a);
    }
    
    // 记录最后的错误状态
    if (r != ARCHIVE_EOF) {
        last_error = r;
        last_error_msg = archive_error_string(a);
        if (count == 0 && last_error_msg != NULL) {
            safe_strncpy(result->error_message, last_error_msg,
                         sizeof(result->error_message));
        }
    }
    
    // 如果没有条目，检查是否是不支持的格式
    if (count == 0) {
        if (result->error_message[0] == '\0') {
            if (format_name != NULL && strlen(format_name) > 0) {
                char msg[512];
                snprintf(msg, sizeof(msg), "Unsupported or encrypted format: %s", format_name);
                safe_strncpy(result->error_message, msg, sizeof(result->error_message));
            } else {
                safe_strncpy(result->error_message, "Archive format not recognized or encrypted",
                             sizeof(result->error_message));
            }
        }
    }
    
    // 分配内存
    result->entries = (ArchiveEntry*)calloc(count, sizeof(ArchiveEntry));
    result->entry_count = count;
    
    // 重新打开以读取实际数据
    archive_read_close(a);
    archive_read_free(a);
    a = archive_read_new();
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    // 设置编码，支持 GBK/CP936 和 UTF-8
    archive_read_set_options(a, "hdrcharset=UTF-8,CP936");
    archive_read_set_options(a, "rar:hdrcharset=UTF-8");
    archive_read_open_filename(a, archive_path, 10240);
    
    // 第二遍：填充数据
    int64_t index = 0;
    while (archive_read_next_header(a, &entry) == ARCHIVE_OK && index < count) {
        ArchiveEntry* ae = &result->entries[index];
        
        const char* pathname = archive_entry_pathname(entry);
        if (pathname == NULL) {
            pathname = "Unknown";
        }
        
        safe_strncpy(ae->name, pathname, sizeof(ae->name));
        safe_strncpy(ae->pathname, pathname, sizeof(ae->pathname));
        
        ae->size = archive_entry_size(entry);
        ae->compressed_size = archive_entry_size(entry);
        ae->mtime = archive_entry_mtime(entry);
        ae->is_directory = (archive_entry_filetype(entry) == AE_IFDIR);
        ae->mode = archive_entry_mode(entry);
        ae->crc32 = 0;
        
        index++;
        archive_read_data_skip(a);
    }
    
    archive_read_close(a);
    archive_read_free(a);
    
    result->status = ARCHIVE_OK;
    return ARCHIVE_OK;
}

void archive_free_list_result(ListResult* result) {
    if (result != NULL && result->entries != NULL) {
        free(result->entries);
        result->entries = NULL;
        result->entry_count = 0;
    }
}

int archive_validate(const char* archive_path) {
    if (archive_path == NULL) {
        return ARCHIVE_ERR_INVALID_PATH;
    }
    
    struct archive* a = archive_read_new();
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    
    int r = archive_read_open_filename(a, archive_path, 10240);
    if (r != ARCHIVE_OK) {
        archive_read_free(a);
        return ARCHIVE_ERR_OPEN_FAILED;
    }
    
    // 尝试读取第一个条目
    struct archive_entry* entry;
    r = archive_read_next_header(a, &entry);
    
    archive_read_close(a);
    archive_read_free(a);
    
    return (r == ARCHIVE_OK) ? ARCHIVE_OK : ARCHIVE_ERR_FORMAT;
}

int archive_extract_single_file(const char* archive_path, const char* entry_path, 
                                const char* output_path, SingleFileExtractResult* result) {
    if (archive_path == NULL || entry_path == NULL || output_path == NULL || result == NULL) {
        return ARCHIVE_ERR_INVALID_PATH;
    }

    memset(result, 0, sizeof(SingleFileExtractResult));
    result->success = false;
    result->extracted_size = 0;

    struct archive* a = archive_read_new();
    struct archive* ext = archive_write_disk_new();
    struct archive_entry* entry;
    int r;

    // 配置读取器
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    // 设置编码，支持 GBK/CP936 和 UTF-8
    archive_read_set_options(a, "hdrcharset=UTF-8,CP936");
    archive_read_set_options(a, "rar:hdrcharset=UTF-8");

    // 配置写入器
    archive_write_disk_set_options(ext, 
        ARCHIVE_EXTRACT_TIME | 
        ARCHIVE_EXTRACT_PERM | 
        ARCHIVE_EXTRACT_ACL | 
        ARCHIVE_EXTRACT_FFLAGS);
    archive_write_disk_set_standard_lookup(ext);

    // 打开压缩包
    r = archive_read_open_filename(a, archive_path, 10240);
    if (r != ARCHIVE_OK) {
        safe_strncpy(result->error_message, archive_error_string(a), 
                     sizeof(result->error_message));
        archive_read_free(a);
        archive_write_free(ext);
        return ARCHIVE_ERR_OPEN_FAILED;
    }

    bool found = false;
    int64_t total_size = 0;

    // 遍历条目查找目标文件
    while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
        const char* current_pathname = archive_entry_pathname_utf8(entry);
        if (current_pathname == NULL) {
            current_pathname = archive_entry_pathname(entry);
        }

        if (current_pathname == NULL) {
            continue;
        }

        // 精确匹配路径
        if (strcmp(current_pathname, entry_path) == 0) {
            found = true;
            int64_t size = archive_entry_size(entry);
            
            // 检查文件大小限制（200MB）
            if (size > 200 * 1024 * 1024) {
                safe_strncpy(result->error_message, 
                             "File too large (>200MB), please extract entire archive", 
                             sizeof(result->error_message));
                archive_read_free(a);
                archive_write_free(ext);
                return ARCHIVE_ERR_WRITE_FAILED;
            }

            // 设置输出路径
            archive_entry_set_pathname(entry, output_path);

            // 写入文件
            r = archive_write_header(ext, entry);
            if (r != ARCHIVE_OK) {
                safe_strncpy(result->error_message, archive_error_string(ext), 
                             sizeof(result->error_message));
                // 删除可能创建的损坏文件
                remove(output_path);
                archive_read_free(a);
                archive_write_free(ext);
                return ARCHIVE_ERR_WRITE_FAILED;
            }

            // 复制数据
            if (size > 0) {
                const void* buff;
                size_t size_read;
                int64_t offset;

                while (true) {
                    r = archive_read_data_block(a, &buff, &size_read, &offset);
                    if (r == ARCHIVE_EOF) {
                        break;
                    }
                    if (r != ARCHIVE_OK) {
                        safe_strncpy(result->error_message, archive_error_string(a), 
                                     sizeof(result->error_message));
                        // 删除可能创建的损坏文件
                        remove(output_path);
                        archive_read_free(a);
                        archive_write_free(ext);
                        return ARCHIVE_ERR_READ_FAILED;
                    }

                    r = archive_write_data_block(ext, buff, size_read, offset);
                    if (r != ARCHIVE_OK) {
                        safe_strncpy(result->error_message, archive_error_string(ext), 
                                     sizeof(result->error_message));
                        // 删除可能创建的损坏文件
                        remove(output_path);
                        archive_read_free(a);
                        archive_write_free(ext);
                        return ARCHIVE_ERR_WRITE_FAILED;
                    }

                    total_size += size_read;
                }
            }

            r = archive_write_finish_entry(ext);
            if (r != ARCHIVE_OK) {
                safe_strncpy(result->error_message, archive_error_string(ext), 
                             sizeof(result->error_message));
                // 删除可能创建的损坏文件
                remove(output_path);
                archive_read_free(a);
                archive_write_free(ext);
                return ARCHIVE_ERR_WRITE_FAILED;
            }

            result->success = true;
            result->extracted_size = total_size;
            break;  // 找到文件后立即停止
        } else {
            // 跳过不需要的条目
            archive_read_data_skip(a);
        }
    }

    archive_read_close(a);
    archive_read_free(a);
    archive_write_close(ext);
    archive_write_free(ext);

    if (!found) {
        safe_strncpy(result->error_message, "File not found in archive", 
                     sizeof(result->error_message));
        return ARCHIVE_ERR_READ_FAILED;
    }

    return ARCHIVE_OK;
}

const char* archive_get_error_message(int error_code) {
    switch (error_code) {
        case ARCHIVE_OK: return "Success";
        case ARCHIVE_ERR_INVALID_PATH: return "Invalid archive path";
        case ARCHIVE_ERR_OPEN_FAILED: return "Failed to open archive";
        case ARCHIVE_ERR_READ_FAILED: return "Failed to read archive";
        case ARCHIVE_ERR_WRITE_FAILED: return "Failed to write file";
        case ARCHIVE_ERR_FORMAT: return "Invalid archive format";
        case ARCHIVE_ERR_CANCELLED: return "Operation cancelled";
        case ARCHIVE_ERR_MEMORY: return "Out of memory";
        case ARCHIVE_ERR_PERMISSION: return "Permission denied";
        default: return "Unknown error";
    }
}
