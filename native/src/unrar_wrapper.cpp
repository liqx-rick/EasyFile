#include "unrar_wrapper.h"

// Android/Unix平台需要的定义（dll.hpp中有_UNIX定义但可能不完整）
#ifdef __ANDROID__
  #ifndef _UNIX
    #define _UNIX
  #endif
  #define CALLBACK
  #define PASCAL
  #define LONG long
  #ifndef HANDLE
    #define HANDLE void *
  #endif
  #define LPARAM long
  #define UINT unsigned int
  #include <android/log.h>
  #define LOG_TAG "UnRARWrapper"
  #define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
  #define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
  #define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
  #define LOGD(...) printf(__VA_ARGS__)
  #define LOGI(...) printf(__VA_ARGS__)
  #define LOGE(...) printf(__VA_ARGS__)
#endif

#include "dll.hpp"  // UnRAR SDK
#include <cstring>
#include <cstdio>
#include <vector>

// ==================== 真实UnRAR SDK实现 ====================

// 检查是否为RAR文件（真实实现）
bool unrar_is_rar_file(const char* file_path) {
    if (!file_path) return false;
    
    // 使用UnRAR SDK尝试打开文件
    RAROpenArchiveDataEx arcData;
    memset(&arcData, 0, sizeof(arcData));
    arcData.ArcName = const_cast<char*>(file_path);
    arcData.OpenMode = RAR_OM_LIST;
    
    HANDLE hArc = RAROpenArchiveEx(&arcData);
    if (!hArc) {
        return false;
    }
    
    bool isRar = (arcData.OpenResult == ERAR_SUCCESS);
    RARCloseArchive(hArc);
    
    return isRar;
}

// 列出RAR内容（真实实现）
int unrar_list_contents(const char* rar_path, UnrarListResult* result) {
    if (!rar_path || !result) {
        return -1;
    }
    
    memset(result, 0, sizeof(UnrarListResult));
    
    // 打开RAR归档
    RAROpenArchiveDataEx arcData;
    memset(&arcData, 0, sizeof(arcData));
    arcData.ArcName = const_cast<char*>(rar_path);
    arcData.OpenMode = RAR_OM_LIST;
    
    HANDLE hArc = RAROpenArchiveEx(&arcData);
    if (!hArc) {
        snprintf(result->error_message, sizeof(result->error_message),
                "Failed to open archive");
        result->status = -1;
        return -1;
    }
    
    if (arcData.OpenResult != ERAR_SUCCESS) {
        RARCloseArchive(hArc);
        snprintf(result->error_message, sizeof(result->error_message),
                "Failed to open RAR: error code %d", arcData.OpenResult);
        result->status = arcData.OpenResult;
        return arcData.OpenResult;
    }
    
    // 读取所有文件条目
    std::vector<UnrarEntry> entries;
    RARHeaderDataEx headerData;
    
    while (true) {
        memset(&headerData, 0, sizeof(headerData));
        
        int readResult = RARReadHeaderEx(hArc, &headerData);
        
        if (readResult == ERAR_END_ARCHIVE) {
            break;  // 正常结束
        }
        
        if (readResult != ERAR_SUCCESS) {
            // 读取错误，记录但继续
            snprintf(result->error_message, sizeof(result->error_message),
                    "Warning: Error reading header (code %d)", readResult);
            break;
        }
        
        // 创建条目
        UnrarEntry entry;
        memset(&entry, 0, sizeof(entry));
        
        // 复制文件名（UnRAR SDK会自动处理编码，输出UTF-8）
        strncpy(entry.filename, headerData.FileName, sizeof(entry.filename) - 1);
        entry.filename[sizeof(entry.filename) - 1] = '\0';
        
        // 文件大小（支持大文件）
        entry.size = ((uint64_t)headerData.UnpSizeHigh << 32) | headerData.UnpSize;
        entry.packed_size = ((uint64_t)headerData.PackSizeHigh << 32) | headerData.PackSize;
        
        // 是否为目录
        entry.is_directory = (headerData.Flags & RHDF_DIRECTORY) != 0;
        
        entries.push_back(entry);
        
        // 跳过当前文件数据（不解压）
        int processResult = RARProcessFile(hArc, RAR_SKIP, NULL, NULL);
        if (processResult != ERAR_SUCCESS && processResult != ERAR_END_ARCHIVE) {
            // 处理错误但继续
            break;
        }
    }
    
    RARCloseArchive(hArc);
    
    // 复制结果
    result->entry_count = entries.size();
    
    if (result->entry_count > 0) {
        result->entries = (UnrarEntry*)malloc(sizeof(UnrarEntry) * result->entry_count);
        
        if (!result->entries) {
            snprintf(result->error_message, sizeof(result->error_message),
                    "Memory allocation failed");
            result->status = -4;
            return -4;
        }
        
        memcpy(result->entries, entries.data(), 
               sizeof(UnrarEntry) * result->entry_count);
    }
    
    result->status = 0;
    
    if (result->error_message[0] == '\0') {
        snprintf(result->error_message, sizeof(result->error_message),
                "Successfully read %d entries", result->entry_count);
    }
    
    return 0;
}

void unrar_free_list_result(UnrarListResult* result) {
    if (result && result->entries) {
        free(result->entries);
        result->entries = NULL;
        result->entry_count = 0;
    }
}

const char* unrar_get_version() {
    return "UnRAR 7.0.9 (Real Implementation)";
}

// ==================== 解压功能实现 ====================

// 解压完整RAR文件
int unrar_extract(
    const char* rar_path,
    const char* dest_path,
    const char* password,
    UnrarExtractResult* result,
    UnrarProgressCallback progress_callback
) {
    if (!rar_path || !dest_path || !result) {
        return -1;
    }
    
    memset(result, 0, sizeof(UnrarExtractResult));
    
    // 打开RAR归档
    RAROpenArchiveDataEx arcData;
    memset(&arcData, 0, sizeof(arcData));
    arcData.ArcName = const_cast<char*>(rar_path);
    arcData.OpenMode = RAR_OM_EXTRACT;
    
    HANDLE hArc = RAROpenArchiveEx(&arcData);
    if (!hArc) {
        snprintf(result->error_message, sizeof(result->error_message),
                "Failed to open archive");
        result->status = -1;
        return -1;
    }
    
    if (arcData.OpenResult != ERAR_SUCCESS) {
        RARCloseArchive(hArc);
        snprintf(result->error_message, sizeof(result->error_message),
                "Failed to open RAR: error code %d", arcData.OpenResult);
        result->status = arcData.OpenResult;
        return arcData.OpenResult;
    }
    
    // 设置密码（如果提供）
    if (password && password[0] != '\0') {
        RARSetPassword(hArc, const_cast<char*>(password));
    }
    
    // 解压所有文件
    RARHeaderDataEx headerData;
    int64_t totalSize = 0;
    int64_t currentSize = 0;
    
    while (true) {
        memset(&headerData, 0, sizeof(headerData));
        
        int readResult = RARReadHeaderEx(hArc, &headerData);
        
        if (readResult == ERAR_END_ARCHIVE) {
            break;  // 正常结束
        }
        
        if (readResult != ERAR_SUCCESS) {
            snprintf(result->error_message, sizeof(result->error_message),
                    "Error reading header (code %d)", readResult);
            result->status = readResult;
            break;
        }
        
        // 构造完整目标路径
        char fullDestPath[4096];
        snprintf(fullDestPath, sizeof(fullDestPath), "%s/%s", 
                dest_path, headerData.FileName);
        
        // 进度回调
        if (progress_callback) {
            uint64_t fileSize = ((uint64_t)headerData.UnpSizeHigh << 32) | headerData.UnpSize;
            progress_callback(currentSize, totalSize, headerData.FileName);
        }
        
        // 解压文件
        int processResult = RARProcessFile(hArc, RAR_EXTRACT, 
                                          const_cast<char*>(dest_path), NULL);
        
        if (processResult == ERAR_SUCCESS) {
            result->extracted_count++;
            uint64_t fileSize = ((uint64_t)headerData.UnpSizeHigh << 32) | headerData.UnpSize;
            currentSize += fileSize;
        } else if (processResult == ERAR_MISSING_PASSWORD) {
            result->failed_count++;
            snprintf(result->error_message, sizeof(result->error_message),
                    "Password required for: %s", headerData.FileName);
        } else if (processResult == ERAR_BAD_PASSWORD) {
            result->failed_count++;
            snprintf(result->error_message, sizeof(result->error_message),
                    "Incorrect password for: %s", headerData.FileName);
        } else {
            result->failed_count++;
        }
    }
    
    RARCloseArchive(hArc);
    
    result->status = 0;
    if (result->error_message[0] == '\0') {
        snprintf(result->error_message, sizeof(result->error_message),
                "Extracted %lld files, %lld failed", 
                (long long)result->extracted_count,
                (long long)result->failed_count);
    }
    
    return 0;
}

// 解压单个文件
int unrar_extract_file(
    const char* rar_path,
    const char* filename,
    const char* dest_path,
    const char* password
) {
    if (!rar_path || !filename || !dest_path) {
        return -1;
    }
    
    // 打开RAR归档
    RAROpenArchiveDataEx arcData;
    memset(&arcData, 0, sizeof(arcData));
    arcData.ArcName = const_cast<char*>(rar_path);
    arcData.OpenMode = RAR_OM_EXTRACT;
    
    HANDLE hArc = RAROpenArchiveEx(&arcData);
    if (!hArc || arcData.OpenResult != ERAR_SUCCESS) {
        LOGE("Failed to open archive, result=%d", arcData.OpenResult);
        return -1;
    }
    
    // 设置密码
    if (password && password[0] != '\0') {
        RARSetPassword(hArc, const_cast<char*>(password));
    }
    
    LOGI("Looking for file: %s", filename);
    
    // 查找目标文件
    RARHeaderDataEx headerData;
    memset(&headerData, 0, sizeof(headerData));  // 必须初始化为0
    bool found = false;
    int entry_count = 0;
    
    while (RARReadHeaderEx(hArc, &headerData) == ERAR_SUCCESS) {
        entry_count++;
        LOGD("Entry %d: %s", entry_count, headerData.FileName);
        
        if (strcmp(headerData.FileName, filename) == 0) {
            found = true;
            LOGI("Found matching file! Extracting to: %s", dest_path);
            
            // 解压这个文件
            int result = RARProcessFile(hArc, RAR_EXTRACT, 
                                       const_cast<char*>(dest_path), NULL);
            RARCloseArchive(hArc);
            
            if (result == ERAR_SUCCESS) {
                LOGI("Extract success");
                return 0;
            } else {
                const char* errorMsg = "Unknown error";
                switch(result) {
                    case 11: errorMsg = "NO_MEMORY"; break;
                    case 12: errorMsg = "BAD_DATA"; break;
                    case 13: errorMsg = "BAD_ARCHIVE"; break;
                    case 14: errorMsg = "UNKNOWN_FORMAT"; break;
                    case 15: errorMsg = "EOPEN"; break;
                    case 16: errorMsg = "ECREATE"; break;
                    case 17: errorMsg = "ECLOSE"; break;
                    case 18: errorMsg = "EREAD"; break;
                    case 19: errorMsg = "EWRITE"; break;
                    case 20: errorMsg = "SMALL_BUF"; break;
                    case 21: errorMsg = "UNKNOWN"; break;
                    case 22: errorMsg = "MISSING_PASSWORD"; break;
                    case 23: errorMsg = "EREFERENCE"; break;
                    case 24: errorMsg = "BAD_PASSWORD"; break;
                    case 25: errorMsg = "LARGE_DICT"; break;
                }
                LOGE("Extract failed, result=%d (%s)", result, errorMsg);
                return -2;
            }
        }
        
        // 跳过其他文件
        RARProcessFile(hArc, RAR_SKIP, NULL, NULL);
        
        // 重新初始化headerData以读取下一个条目
        memset(&headerData, 0, sizeof(headerData));
    }
    
    LOGE("File not found after checking %d entries", entry_count);
    RARCloseArchive(hArc);
    return -3;  // -3 = 文件未找到
}
