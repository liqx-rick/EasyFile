package com.guangqi.easyfile

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * MediaStore回收站辅助类
 * 
 * 用于查询和删除Android 11+系统回收站中的文件
 */
class MediaStoreTrashHelper(private val context: Context) {
    
    companion object {
        private const val TAG = "MediaStoreTrash"
        
        /**
         * 检查当前Android版本是否支持MediaStore Trash
         */
        fun isSupported(): Boolean {
            return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R // Android 11+
        }
    }
    
    /**
     * 查询回收站中的文件
     * 
     * @return 回收站文件列表，每个文件包含 id, name, path, size, modified
     */
    @RequiresApi(Build.VERSION_CODES.R)
    fun queryTrashedFiles(): List<Map<String, Any>> {
        val trashedFiles = mutableListOf<Map<String, Any>>()
        
        try {
            // 方法1：查询标准MediaStore IS_TRASHED
            val standardTrashed = queryStandardTrashedFiles()
            trashedFiles.addAll(standardTrashed)
            
            // 方法2：查询图片和视频的回收站（相册"最近删除"）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val mediaTrashed = queryMediaTrashedFiles()
                trashedFiles.addAll(mediaTrashed)
            }
            
            Log.i(TAG, "总计查询到 ${trashedFiles.size} 个回收站文件")
        } catch (e: Exception) {
            Log.e(TAG, "查询回收站文件失败: ${e.message}", e)
        }
        
        return trashedFiles
    }
    
    /**
     * 查询标准MediaStore回收站文件
     */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun queryStandardTrashedFiles(): List<Map<String, Any>> {
        val trashedFiles = mutableListOf<Map<String, Any>>()
        
        try {
            val projection = arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.DATA,
                MediaStore.Files.FileColumns.SIZE,
                MediaStore.Files.FileColumns.DATE_MODIFIED,
                MediaStore.Files.FileColumns.MIME_TYPE
            )
            
            // 查询条件：is_trashed = 1
            val selection = "${MediaStore.Files.FileColumns.IS_TRASHED} = ?"
            val selectionArgs = arrayOf("1")
            
            val sortOrder = "${MediaStore.Files.FileColumns.SIZE} DESC"
            
            val contentResolver: ContentResolver = context.contentResolver
            val uri = MediaStore.Files.getContentUri("external")
            
            Log.d(TAG, "开始查询回收站文件...")
            Log.d(TAG, "URI: $uri")
            Log.d(TAG, "Selection: $selection")
            Log.d(TAG, "SelectionArgs: ${selectionArgs.joinToString()}")
            Log.d(TAG, "Android版本: ${Build.VERSION.SDK_INT}")
            
            val cursor: Cursor? = contentResolver.query(
                uri,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )
            
            Log.d(TAG, "查询结果 cursor: ${if (cursor != null) "成功 (count=${cursor.count})" else "null"}")
            
            cursor?.use {
                Log.d(TAG, "准备获取列索引...")
                val idColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                Log.d(TAG, "idColumn: $idColumn")
                val nameColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                Log.d(TAG, "nameColumn: $nameColumn")
                val pathColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATA)
                Log.d(TAG, "pathColumn: $pathColumn")
                val sizeColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                Log.d(TAG, "sizeColumn: $sizeColumn")
                val modifiedColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
                Log.d(TAG, "modifiedColumn: $modifiedColumn")
                val mimeTypeColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)
                Log.d(TAG, "mimeTypeColumn: $mimeTypeColumn, 准备遍历cursor...")
                
                while (it.moveToNext()) {
                    val id = it.getLong(idColumn)
                    val name = it.getString(nameColumn) ?: "未知文件"
                    val path = it.getString(pathColumn) ?: ""
                    val size = it.getLong(sizeColumn)
                    val modified = it.getLong(modifiedColumn) * 1000 // 转换为毫秒
                    val mimeType = it.getString(mimeTypeColumn) ?: ""
                    
                    val fileInfo = mapOf(
                        "id" to id,
                        "name" to name,
                        "path" to path,
                        "size" to size,
                        "modified" to modified,
                        "mimeType" to mimeType
                    )
                    
                    trashedFiles.add(fileInfo)
                    Log.d(TAG, "找到回收站文件: $name (${size} bytes)")
                }
            }
            
            Log.i(TAG, "标准回收站查询完成，共找到 ${trashedFiles.size} 个文件")
        } catch (e: Exception) {
            Log.e(TAG, "查询标准回收站失败: ${e.message}", e)
        }
        
        return trashedFiles
    }
    
    /**
     * 查询相册回收站（图片和视频的"最近删除"）
     */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun queryMediaTrashedFiles(): List<Map<String, Any>> {
        val trashedFiles = mutableListOf<Map<String, Any>>()
        
        try {
            Log.d(TAG, "开始查询相册回收站（图片和视频）...")
            
            // 查询图片
            trashedFiles.addAll(queryTrashedMedia(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "图片"))
            
            // 查询视频
            trashedFiles.addAll(queryTrashedMedia(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, "视频"))
            
            Log.i(TAG, "相册回收站查询完成，共找到 ${trashedFiles.size} 个文件")
        } catch (e: Exception) {
            Log.e(TAG, "查询相册回收站失败: ${e.message}", e)
        }
        
        return trashedFiles
    }
    
    /**
     * 查询特定类型媒体的回收站文件
     */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun queryTrashedMedia(uri: Uri, type: String): List<Map<String, Any>> {
        val trashedFiles = mutableListOf<Map<String, Any>>()
        
        try {
            val projection = arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.DATA,
                MediaStore.MediaColumns.SIZE,
                MediaStore.MediaColumns.DATE_MODIFIED,
                MediaStore.MediaColumns.MIME_TYPE
            )
            
            // 查询被标记为已删除的文件
            val selection = "${MediaStore.MediaColumns.IS_TRASHED} = ?"
            val selectionArgs = arrayOf("1")
            val sortOrder = "${MediaStore.MediaColumns.SIZE} DESC"
            
            val contentResolver = context.contentResolver
            val cursor: Cursor? = contentResolver.query(
                uri,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )
            
            cursor?.use {
                val count = it.count
                Log.d(TAG, "$type 回收站查询结果: $count 个文件")
                
                val idColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val pathColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                val sizeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                val modifiedColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
                val mimeTypeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
                
                while (it.moveToNext()) {
                    val id = it.getLong(idColumn)
                    val name = it.getString(nameColumn) ?: "未知文件"
                    val path = it.getString(pathColumn) ?: ""
                    val size = it.getLong(sizeColumn)
                    val modified = it.getLong(modifiedColumn) * 1000
                    val mimeType = it.getString(mimeTypeColumn) ?: ""
                    
                    val fileInfo = mapOf(
                        "id" to id,
                        "name" to name,
                        "path" to path,
                        "size" to size,
                        "modified" to modified,
                        "mimeType" to mimeType
                    )
                    
                    trashedFiles.add(fileInfo)
                    Log.d(TAG, "找到${type}回收站文件: $name (${size} bytes)")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "查询${type}回收站失败: ${e.message}", e)
        }
        
        return trashedFiles
    }
    
    /**
     * 永久删除回收站中的文件
     * 
     * @param fileId MediaStore文件ID
     * @return 删除是否成功
     */
    @RequiresApi(Build.VERSION_CODES.R)
    fun deleteTrashedFile(fileId: Long): Boolean {
        return try {
            val contentResolver: ContentResolver = context.contentResolver
            val uri = ContentUris.withAppendedId(
                MediaStore.Files.getContentUri("external"),
                fileId
            )
            
            Log.d(TAG, "删除回收站文件，ID: $fileId")
            
            val deletedRows = contentResolver.delete(uri, null, null)
            val success = deletedRows > 0
            
            if (success) {
                Log.i(TAG, "文件删除成功，ID: $fileId")
            } else {
                Log.w(TAG, "文件删除失败，ID: $fileId")
            }
            
            success
        } catch (e: Exception) {
            Log.e(TAG, "删除文件异常，ID: $fileId, 错误: ${e.message}", e)
            false
        }
    }
    
    /**
     * 批量删除回收站文件
     * 
     * @param fileIds 文件ID列表
     * @return 删除结果统计 Map，包含 success、failed、totalSize
     */
    @RequiresApi(Build.VERSION_CODES.R)
    fun deleteMultipleTrashedFiles(fileIds: List<Long>): Map<String, Int> {
        var successCount = 0
        var failedCount = 0
        
        Log.i(TAG, "开始批量删除 ${fileIds.size} 个文件")
        
        for (fileId in fileIds) {
            if (deleteTrashedFile(fileId)) {
                successCount++
            } else {
                failedCount++
            }
        }
        
        Log.i(TAG, "批量删除完成: 成功 $successCount, 失败 $failedCount")
        
        return mapOf(
            "success" to successCount,
            "failed" to failedCount
        )
    }
    
    /**
     * 清空整个回收站
     * 
     * @return 删除结果统计
     */
    @RequiresApi(Build.VERSION_CODES.R)
    fun emptyTrash(): Map<String, Int> {
        val trashedFiles = queryTrashedFiles()
        val fileIds = trashedFiles.mapNotNull { it["id"] as? Long }
        
        Log.i(TAG, "清空回收站: 共 ${fileIds.size} 个文件")
        
        return if (fileIds.isNotEmpty()) {
            deleteMultipleTrashedFiles(fileIds)
        } else {
            mapOf("success" to 0, "failed" to 0)
        }
    }
}
