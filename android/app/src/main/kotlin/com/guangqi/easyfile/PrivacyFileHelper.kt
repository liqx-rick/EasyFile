package com.guangqi.easyfile

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import java.io.File

/**
 * 隐私空间文件操作辅助类
 *
 * 用于在移入隐私空间时彻底删除源文件，避免触发系统相册/文件管理器的回收站
 */
class PrivacyFileHelper(private val context: Context) {

    companion object {
        private const val TAG = "PrivacyFileHelper"
    }

    /**
     * 彻底删除文件（不进入回收站）
     *
     * 在 Android 10+ 上，普通的 File.delete() 可能触发系统相册/文件管理器的回收站。
     * 此方法尝试使用 MediaStore API 直接删除，或标记为 IS_PENDING 后删除。
     *
     * @param filePath 要删除的文件路径
     * @return true 删除成功，false 删除失败
     */
    fun deleteFileCompletely(filePath: String): Boolean {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                LogHelper.w(TAG, "文件不存在: $filePath")
                return false
            }

            // Android 10+ (API 29+) 尝试使用 MediaStore API
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val deleted = deleteViaMediaStore(filePath)
                if (deleted) {
                    LogHelper.i(TAG, "✅ 通过 MediaStore 删除成功: $filePath")
                    return true
                }
                LogHelper.d(TAG, "MediaStore 删除失败，尝试直接删除")
            }

            // 降级方案：直接删除文件
            val success = file.delete()
            if (success) {
                LogHelper.i(TAG, "✅ 直接删除成功: $filePath")
            } else {
                LogHelper.e(TAG, "❌ 删除失败: $filePath")
            }

            return success
        } catch (e: Exception) {
            LogHelper.e(TAG, "删除文件异常: ${e.message}", e)
            return false
        }
    }

    /**
     * 通过 MediaStore API 删除文件
     *
     * 使用 ContentResolver.delete() 直接删除 MediaStore 记录和文件，
     * 不会触发系统相册的"最近删除"功能
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun deleteViaMediaStore(filePath: String): Boolean {
        try {
            val contentResolver: ContentResolver = context.contentResolver
            val file = File(filePath)

            // 1. 查找 MediaStore 中对应的记录
            val uri = findMediaStoreUri(filePath) ?: run {
                LogHelper.d(TAG, "未在 MediaStore 中找到文件: $filePath")
                return false
            }

            LogHelper.d(TAG, "找到 MediaStore URI: $uri")

            // 2. Android 11+ 可以设置 IS_PENDING 来标记文件为待删除状态
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // 先标记为 pending
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                contentResolver.update(uri, values, null, null)
                LogHelper.d(TAG, "已标记文件为 IS_PENDING")
            }

            // 3. 直接删除 MediaStore 记录
            val deletedRows = contentResolver.delete(uri, null, null)

            if (deletedRows > 0) {
                LogHelper.i(TAG, "✅ MediaStore 记录已删除")

                // 4. 如果文件仍然存在，直接删除文件
                if (file.exists()) {
                    file.delete()
                    LogHelper.d(TAG, "删除了残留文件")
                }

                return true
            } else {
                LogHelper.w(TAG, "MediaStore 删除返回 0 行")
                return false
            }
        } catch (e: SecurityException) {
            LogHelper.w(TAG, "权限不足: ${e.message}")
            return false
        } catch (e: Exception) {
            LogHelper.e(TAG, "MediaStore 删除异常: ${e.message}", e)
            return false
        }
    }

    /**
     * 在 MediaStore 中查找文件的 URI
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun findMediaStoreUri(filePath: String): Uri? {
        try {
            val contentResolver: ContentResolver = context.contentResolver
            val file = File(filePath)

            // 根据文件扩展名确定 MediaStore URI
            val extension = file.extension.lowercase()
            val collection = when {
                // 图片格式
                extension in listOf("jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif") ->
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI

                // 视频格式
                extension in listOf("mp4", "avi", "mkv", "mov", "wmv", "flv", "webm", "3gp", "m4v") ->
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI

                // 音频格式
                extension in listOf("mp3", "wav", "flac", "aac", "ogg", "m4a", "wma") ->
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI

                // 其他文件
                else -> MediaStore.Files.getContentUri("external")
            }

            LogHelper.d(TAG, "查找文件: $filePath, 扩展名: $extension, 使用集合: $collection")

            // 查询条件
            val projection = arrayOf(MediaStore.MediaColumns._ID)
            val selection = "${MediaStore.MediaColumns.DATA} = ?"
            val selectionArgs = arrayOf(filePath)

            contentResolver.query(
                collection,
                projection,
                selection,
                selectionArgs,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                    val uri = Uri.withAppendedPath(collection, id.toString())
                    LogHelper.d(TAG, "✅ 找到 MediaStore URI: $uri")
                    return uri
                }
            }

            LogHelper.d(TAG, "⚠️ 未在 MediaStore 中找到文件记录")
            return null
        } catch (e: Exception) {
            LogHelper.e(TAG, "查找 MediaStore URI 失败: ${e.message}", e)
            return null
        }
    }

    /**
     * 通知 MediaStore 扫描文件
     *
     * 当文件从隐私空间恢复到公共存储后，需要通知系统相册/媒体库重新扫描
     * 这样文件才会显示在相册中
     *
     * @param filePath 要扫描的文件路径
     * @param callback 扫描完成回调
     */
    fun scanFile(filePath: String, callback: ((success: Boolean) -> Unit)? = null) {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                LogHelper.w(TAG, "文件不存在，无法扫描: $filePath")
                callback?.invoke(false)
                return
            }

            LogHelper.d(TAG, "开始扫描文件: $filePath")

            MediaScannerConnection.scanFile(
                context,
                arrayOf(filePath),
                null  // mimeType 自动检测
            ) { path, uri ->
                if (uri != null) {
                    LogHelper.i(TAG, "✅ 文件扫描成功: $path -> $uri")
                    callback?.invoke(true)
                } else {
                    LogHelper.w(TAG, "⚠️ 文件扫描返回 null URI: $path")
                    callback?.invoke(false)
                }
            }
        } catch (e: Exception) {
            LogHelper.e(TAG, "扫描文件异常: ${e.message}", e)
            callback?.invoke(false)
        }
    }
}
