package com.guangqi.easyfile

import android.content.Context
import android.database.Cursor
import android.util.Log

/**
 * MediaStore 通用扫描器
 * 消除代码重复，支持所有媒体类型的统一扫描逻辑
 */
class MediaStoreScanner(private val context: Context) {
    
    /**
     * 扫描指定类型的媒体文件
     * 
     * @param type 媒体类型（Image, Audio, Video, Document, Archive, Apk）
     * @return 文件信息列表，包含 path, name, size, modified 等
     */
    fun scan(type: MediaType): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        val startTime = System.currentTimeMillis()
        
        try {
            val projection = type.getProjection()
            val selection = type.getSelection()
            val selectionArgs = type.getSelectionArgs()
            val sortOrder = type.getSortOrder()
            
            val contentResolver = context.contentResolver
            val cursor = contentResolver.query(
                type.uri,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )
            
            cursor?.use {
                LogHelper.d(type.tag, "开始遍历 MediaStore 查询结果，总数: ${it.count}")
                
                while (it.moveToNext()) {
                    val fileData = extractFileData(it, type)
                    
                    // 过滤隐藏文件
                    if (fileData != null && !isHiddenFile(fileData)) {
                        results.add(fileData)
                    }
                }
            }
            
            val endTime = System.currentTimeMillis()
            val duration = endTime - startTime
            
            LogHelper.i(type.tag, "MediaStore 扫描完成: ${results.size} 个${type.typeName}, 耗时: ${duration}ms")
            
        } catch (e: Exception) {
            LogHelper.e(type.tag, "MediaStore 扫描失败: ${e.message}", e)
        }
        
        return results
    }
    
    /**
     * 从 Cursor 中提取文件数据
     */
    private fun extractFileData(cursor: Cursor, type: MediaType): Map<String, Any>? {
        return try {
            // 基础字段（所有类型都有）
            val pathColumn = cursor.getColumnIndex(getDataColumnName(type))
            val nameColumn = cursor.getColumnIndex(getDisplayNameColumnName(type))
            val sizeColumn = cursor.getColumnIndex(getSizeColumnName(type))
            val modifiedColumn = cursor.getColumnIndex(getDateModifiedColumnName(type))
            val addedColumn = cursor.getColumnIndex(getDateAddedColumnName(type))
            val mimeColumn = cursor.getColumnIndex(getMimeTypeColumnName(type))
            
            val path = cursor.getString(pathColumn) ?: return null
            val name = cursor.getString(nameColumn) ?: return null
            val size = cursor.getLong(sizeColumn)
            val modified = cursor.getLong(modifiedColumn) * 1000  // 转换为毫秒
            val added = cursor.getLong(addedColumn) * 1000
            val mimeType = cursor.getString(mimeColumn) ?: getDefaultMimeType(type)
            
            // 构建基础数据
            val data = mutableMapOf<String, Any>(
                "path" to path,
                "name" to name,
                "size" to size,
                "modified" to modified,
                "added" to added,
                "mimeType" to mimeType
            )
            
            // 添加类型特定的字段
            addTypeSpecificFields(cursor, type, data)
            
            data
        } catch (e: Exception) {
            LogHelper.w(type.tag, "提取文件数据失败: ${e.message}")
            null
        }
    }
    
    /**
     * 添加类型特定的字段
     */
    private fun addTypeSpecificFields(
        cursor: Cursor,
        type: MediaType,
        data: MutableMap<String, Any>
    ) {
        when (type) {
            is MediaType.Image, is MediaType.CameraImage -> {
                val widthColumn = cursor.getColumnIndex(android.provider.MediaStore.Images.Media.WIDTH)
                val heightColumn = cursor.getColumnIndex(android.provider.MediaStore.Images.Media.HEIGHT)
                if (widthColumn >= 0) data["width"] = cursor.getInt(widthColumn)
                if (heightColumn >= 0) data["height"] = cursor.getInt(heightColumn)
            }
            is MediaType.Audio, is MediaType.Recording -> {
                val durationColumn = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.DURATION)
                val artistColumn = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.ARTIST)
                val albumColumn = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.ALBUM)
                if (durationColumn >= 0) data["duration"] = cursor.getLong(durationColumn)
                if (artistColumn >= 0) cursor.getString(artistColumn)?.let { data["artist"] = it }
                if (albumColumn >= 0) cursor.getString(albumColumn)?.let { data["album"] = it }
            }
            is MediaType.Video, is MediaType.CameraVideo -> {
                val durationColumn = cursor.getColumnIndex(android.provider.MediaStore.Video.Media.DURATION)
                val widthColumn = cursor.getColumnIndex(android.provider.MediaStore.Video.Media.WIDTH)
                val heightColumn = cursor.getColumnIndex(android.provider.MediaStore.Video.Media.HEIGHT)
                if (durationColumn >= 0) data["duration"] = cursor.getLong(durationColumn)
                if (widthColumn >= 0) data["width"] = cursor.getInt(widthColumn)
                if (heightColumn >= 0) data["height"] = cursor.getInt(heightColumn)
            }
            // Document, Archive, Apk 只有基础字段
            else -> {}
        }
    }
    
    /**
     * 检查是否为隐藏文件
     */
    private fun isHiddenFile(fileData: Map<String, Any>): Boolean {
        val name = fileData["name"] as? String ?: return true
        val path = fileData["path"] as? String ?: return true
        
        // 1. 文件名以.开头
        if (name.startsWith(".")) return true
        
        // 2. 路径中包含隐藏文件夹（/.开头的文件夹）
        if (path.contains("/.")) return true
        
        return false
    }
    
    /**
     * 获取统计信息
     */
    fun getStats(type: MediaType): Map<String, Any> {
        val startTime = System.currentTimeMillis()
        val files = scan(type)
        val endTime = System.currentTimeMillis()
        
        val totalSize = files.fold(0L) { sum, file -> sum + (file["size"] as Long) }
        
        return mapOf(
            "count" to files.size,
            "totalSize" to totalSize,
            "scanTime" to (endTime - startTime),
            "averageSize" to if (files.isNotEmpty()) totalSize / files.size else 0L
        )
    }
    
    // 辅助方法：获取列名（根据媒体类型）
    private fun getDataColumnName(type: MediaType): String {
        return when (type) {
            is MediaType.Image, is MediaType.CameraImage -> android.provider.MediaStore.Images.Media.DATA
            is MediaType.Audio, is MediaType.Recording -> android.provider.MediaStore.Audio.Media.DATA
            is MediaType.Video, is MediaType.CameraVideo -> android.provider.MediaStore.Video.Media.DATA
            else -> android.provider.MediaStore.Files.FileColumns.DATA
        }
    }
    
    private fun getDisplayNameColumnName(type: MediaType): String {
        return when (type) {
            is MediaType.Image, is MediaType.CameraImage -> android.provider.MediaStore.Images.Media.DISPLAY_NAME
            is MediaType.Audio, is MediaType.Recording -> android.provider.MediaStore.Audio.Media.DISPLAY_NAME
            is MediaType.Video, is MediaType.CameraVideo -> android.provider.MediaStore.Video.Media.DISPLAY_NAME
            else -> android.provider.MediaStore.Files.FileColumns.DISPLAY_NAME
        }
    }
    
    private fun getSizeColumnName(type: MediaType): String {
        return when (type) {
            is MediaType.Image, is MediaType.CameraImage -> android.provider.MediaStore.Images.Media.SIZE
            is MediaType.Audio, is MediaType.Recording -> android.provider.MediaStore.Audio.Media.SIZE
            is MediaType.Video, is MediaType.CameraVideo -> android.provider.MediaStore.Video.Media.SIZE
            else -> android.provider.MediaStore.Files.FileColumns.SIZE
        }
    }
    
    private fun getDateModifiedColumnName(type: MediaType): String {
        return when (type) {
            is MediaType.Image, is MediaType.CameraImage -> android.provider.MediaStore.Images.Media.DATE_MODIFIED
            is MediaType.Audio, is MediaType.Recording -> android.provider.MediaStore.Audio.Media.DATE_MODIFIED
            is MediaType.Video, is MediaType.CameraVideo -> android.provider.MediaStore.Video.Media.DATE_MODIFIED
            else -> android.provider.MediaStore.Files.FileColumns.DATE_MODIFIED
        }
    }
    
    private fun getDateAddedColumnName(type: MediaType): String {
        return when (type) {
            is MediaType.Image, is MediaType.CameraImage -> android.provider.MediaStore.Images.Media.DATE_ADDED
            is MediaType.Audio, is MediaType.Recording -> android.provider.MediaStore.Audio.Media.DATE_ADDED
            is MediaType.Video, is MediaType.CameraVideo -> android.provider.MediaStore.Video.Media.DATE_ADDED
            else -> android.provider.MediaStore.Files.FileColumns.DATE_ADDED
        }
    }
    
    private fun getMimeTypeColumnName(type: MediaType): String {
        return when (type) {
            is MediaType.Image, is MediaType.CameraImage -> android.provider.MediaStore.Images.Media.MIME_TYPE
            is MediaType.Audio, is MediaType.Recording -> android.provider.MediaStore.Audio.Media.MIME_TYPE
            is MediaType.Video, is MediaType.CameraVideo -> android.provider.MediaStore.Video.Media.MIME_TYPE
            else -> android.provider.MediaStore.Files.FileColumns.MIME_TYPE
        }
    }
    
    private fun getDefaultMimeType(type: MediaType): String {
        return when (type) {
            is MediaType.Image, is MediaType.CameraImage -> "image/*"
            is MediaType.Audio, is MediaType.Recording -> "audio/*"
            is MediaType.Video, is MediaType.CameraVideo -> "video/*"
            is MediaType.Document -> "application/octet-stream"
            is MediaType.Archive -> "application/zip"
            is MediaType.Apk -> "application/vnd.android.package-archive"
        }
    }
}
