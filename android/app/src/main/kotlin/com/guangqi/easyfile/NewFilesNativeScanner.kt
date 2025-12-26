package com.guangqi.easyfile

import android.content.Context
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * 新文件原生扫描器
 * 
 * 性能优化方案：
 * 1. MediaStore索引查询（图片/视频/音频/文档）- 80%覆盖
 * 2. 一级目录扫描（APK/ZIP/RAR）- 20%补充
 * 
 * 性能目标：
 * - 从15秒优化到3秒（5倍提升）
 * - UI完全不卡顿（协程异步）
 */
class NewFilesNativeScanner(private val context: Context) {
    
    companion object {
        private const val TAG = "NewFilesNativeScanner"
        
        /**
         * 系统预定义目录（复用 SystemFoldersConfig）
         * 未来：从统一配置文件读取
         */
        private val SYSTEM_DIRECTORIES = listOf(
            "/storage/emulated/0/Download",
            "/storage/emulated/0/DCIM",
            "/storage/emulated/0/Pictures",
            "/storage/emulated/0/Documents",
            "/storage/emulated/0/Music",
            "/storage/emulated/0/Movies",
            "/storage/emulated/0/bluetooth",
        )
        
        /**
         * MediaStore未索引的文件类型（需要补充扫描）
         * 未来：从统一配置文件读取
         */
        private val SUPPLEMENT_EXTENSIONS = setOf(
            "apk", "zip", "rar", "7z", "xapk"
        )
    }
    
    /**
     * 扫描最近的文件
     * 
     * @param days 保留天数
     * @return 文件列表 List<Map<String, Any>>
     */
    suspend fun scanRecentFiles(days: Int): List<Map<String, Any>> = 
        withContext(Dispatchers.IO) {
            val startTime = System.currentTimeMillis()
            val cutoffTime = startTime - days * 86400000L
            val results = mutableMapOf<String, Map<String, Any>>()
            
            Log.i(TAG, "开始扫描最近 $days 天的文件...")
            
            // 1. MediaStore查询（80%覆盖）
            try {
                val mediaStoreFiles = scanFromMediaStore(cutoffTime)
                mediaStoreFiles.forEach { 
                    results[it["path"] as String] = it 
                }
                Log.i(TAG, "MediaStore找到: ${mediaStoreFiles.size} 个文件")
            } catch (e: Exception) {
                Log.e(TAG, "MediaStore扫描失败: ${e.message}", e)
            }
            
            // 2. 一级目录补充（20%覆盖）
            try {
                val supplementFiles = scanTopLevelDirectories(cutoffTime)
                supplementFiles.forEach { 
                    results[it["path"] as String] = it 
                }
                Log.i(TAG, "补充扫描找到: ${supplementFiles.size} 个文件")
            } catch (e: Exception) {
                Log.e(TAG, "补充扫描失败: ${e.message}", e)
            }
            
            val duration = System.currentTimeMillis() - startTime
            val sortedResults = results.values
                .sortedByDescending { it["dateAdded"] as Long }
                .toList()
            
            Log.i(TAG, "扫描完成: ${sortedResults.size} 个文件，耗时 ${duration}ms")
            sortedResults
        }
    
    /**
     * MediaStore索引查询
     * 
     * 覆盖：图片、视频、音频、文档
     */
    private fun scanFromMediaStore(cutoffTime: Long): List<Map<String, Any>> {
        val files = mutableListOf<Map<String, Any>>()
        val cutoffSeconds = cutoffTime / 1000
        
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DATA,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.DATE_ADDED,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
            MediaStore.Files.FileColumns.MIME_TYPE
        )
        
        // 查询条件：
        // 1. 添加时间在cutoff之后
        // 2. 文件大小>0
        // 3. 排除隐藏文件
        val selection = "${MediaStore.Files.FileColumns.DATE_ADDED} >= ? " +
                "AND ${MediaStore.Files.FileColumns.SIZE} > 0 " +
                "AND ${MediaStore.Files.FileColumns.DISPLAY_NAME} NOT LIKE '.%'"
        val selectionArgs = arrayOf(cutoffSeconds.toString())
        val sortOrder = "${MediaStore.Files.FileColumns.DATE_ADDED} DESC"
        
        try {
            val uri = MediaStore.Files.getContentUri("external")
            val cursor = context.contentResolver.query(
                uri,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )
            
            cursor?.use {
                val pathColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATA)
                val nameColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val sizeColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                val addedColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_ADDED)
                val modifiedColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
                val mimeColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)
                
                while (it.moveToNext()) {
                    val path = it.getString(pathColumn) ?: continue
                    val name = it.getString(nameColumn) ?: continue
                    
                    // 过滤隐藏文件和隐藏目录中的文件
                    if (name.startsWith(".") || path.contains("/.")) {
                        continue
                    }
                    
                    val size = it.getLong(sizeColumn)
                    val dateAdded = it.getLong(addedColumn)
                    val dateModified = it.getLong(modifiedColumn)
                    val mimeType = it.getString(mimeColumn) ?: "application/octet-stream"
                    
                    files.add(mapOf(
                        "path" to path,
                        "name" to name,
                        "size" to size,
                        "dateAdded" to dateAdded,
                        "dateModified" to dateModified,
                        "mimeType" to mimeType
                    ))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "MediaStore查询失败: ${e.message}", e)
        }
        
        return files
    }
    
    /**
     * 一级目录扫描（不递归）
     * 
     * 覆盖：APK、ZIP、RAR等MediaStore未索引的文件
     */
    private fun scanTopLevelDirectories(cutoffTime: Long): List<Map<String, Any>> {
        val files = mutableListOf<Map<String, Any>>()
        
        for (dirPath in SYSTEM_DIRECTORIES) {
            val dir = File(dirPath)
            if (!dir.exists() || !dir.isDirectory) {
                Log.d(TAG, "目录不存在: $dirPath")
                continue
            }
            
            try {
                // 只扫描一级文件，不递归
                val listFiles = dir.listFiles() ?: continue
                
                for (file in listFiles) {
                    // 只处理文件（跳过目录）
                    if (!file.isFile) continue
                    
                    // 检查修改时间
                    if (file.lastModified() < cutoffTime) continue
                    
                    // 检查文件大小
                    if (file.length() == 0L) continue
                    
                    // 检查文件名（排除隐藏文件）
                    if (file.name.startsWith(".")) continue
                    
                    // 检查扩展名
                    val extension = file.extension.lowercase()
                    if (extension !in SUPPLEMENT_EXTENSIONS) continue
                    
                    // 添加到结果
                    files.add(mapOf(
                        "path" to file.absolutePath,
                        "name" to file.name,
                        "size" to file.length(),
                        "dateAdded" to (file.lastModified() / 1000),
                        "dateModified" to (file.lastModified() / 1000),
                        "mimeType" to getMimeType(extension)
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "扫描目录失败 $dirPath: ${e.message}", e)
            }
        }
        
        return files
    }
    
    /**
     * 获取MIME类型
     */
    private fun getMimeType(extension: String): String {
        return when (extension.lowercase()) {
            "apk" -> "application/vnd.android.package-archive"
            "zip" -> "application/zip"
            "rar" -> "application/x-rar-compressed"
            "7z" -> "application/x-7z-compressed"
            "xapk" -> "application/vnd.android.package-archive"
            else -> MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(extension) ?: "application/octet-stream"
        }
    }
}
