package com.guangqi.easyfile

import android.net.Uri
import android.provider.MediaStore

/**
 * MediaStore 扫描的媒体类型定义
 * 使用 sealed class 提供类型安全的配置
 */
sealed class MediaType(
    val uri: Uri,
    val tag: String,
    val typeName: String,
    val mimeTypes: Array<String>? = null
) {
    
    /**
     * 图片类型
     */
    object Image : MediaType(
        uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
        tag = "MediaStoreImage",
        typeName = "图片"
    )
    
    /**
     * 音频类型
     */
    object Audio : MediaType(
        uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
        tag = "MediaStoreAudio",
        typeName = "音频"
    )
    
    /**
     * 视频类型
     */
    object Video : MediaType(
        uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
        tag = "MediaStoreVideo",
        typeName = "视频"
    )
    
    /**
     * 文档类型
     */
    object Document : MediaType(
        uri = MediaStore.Files.getContentUri("external"),
        tag = "MediaStoreDocument",
        typeName = "文档",
        mimeTypes = MediaTypeConfig.DOCUMENT_MIMES
    )
    
    /**
     * 压缩包类型
     */
    object Archive : MediaType(
        uri = MediaStore.Files.getContentUri("external"),
        tag = "MediaStoreArchive",
        typeName = "压缩包",
        mimeTypes = MediaTypeConfig.ARCHIVE_MIMES
    )
    
    /**
     * APK 类型
     */
    object Apk : MediaType(
        uri = MediaStore.Files.getContentUri("external"),
        tag = "MediaStoreApk",
        typeName = "APK",
        mimeTypes = MediaTypeConfig.APK_MIMES
    )
    
    /**
     * 相机照片类型（时光记忆）
     * 仅包含相机拍摄的照片，通过 BUCKET_DISPLAY_NAME = 'Camera' 过滤
     */
    object CameraImage : MediaType(
        uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
        tag = "MediaStoreCameraImage",
        typeName = "相机照片"
    )
    
    /**
     * 相机视频类型（生活剪影）
     * 仅包含相机录制的视频，通过 BUCKET_DISPLAY_NAME = 'Camera' 过滤
     */
    object CameraVideo : MediaType(
        uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
        tag = "MediaStoreCameraVideo",
        typeName = "相机视频"
    )
    
    /**
     * 录音文件类型（声音记录）
     * 仅包含录音文件，通过路径或MIME类型过滤
     */
    object Recording : MediaType(
        uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
        tag = "MediaStoreRecording",
        typeName = "录音文件"
    )
    
    /**
     * 获取投影字段（查询的列）
     */
    fun getProjection(): Array<String> {
        return when (this) {
            is Image -> arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.DATE_MODIFIED,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.MIME_TYPE,
                MediaStore.Images.Media.WIDTH,
                MediaStore.Images.Media.HEIGHT
            )
            is CameraImage -> arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.DATE_MODIFIED,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.MIME_TYPE,
                MediaStore.Images.Media.WIDTH,
                MediaStore.Images.Media.HEIGHT,
                MediaStore.Images.Media.BUCKET_DISPLAY_NAME  // 相册名称
            )
            is Audio -> arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.SIZE,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.DATE_ADDED,
                MediaStore.Audio.Media.MIME_TYPE,
                MediaStore.Audio.Media.DURATION,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM
            )
            is Recording -> arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.SIZE,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.DATE_ADDED,
                MediaStore.Audio.Media.MIME_TYPE,
                MediaStore.Audio.Media.DURATION
            )
            is Video -> arrayOf(
                MediaStore.Video.Media._ID,
                MediaStore.Video.Media.DATA,
                MediaStore.Video.Media.DISPLAY_NAME,
                MediaStore.Video.Media.SIZE,
                MediaStore.Video.Media.DATE_MODIFIED,
                MediaStore.Video.Media.DATE_ADDED,
                MediaStore.Video.Media.MIME_TYPE,
                MediaStore.Video.Media.DURATION,
                MediaStore.Video.Media.WIDTH,
                MediaStore.Video.Media.HEIGHT
            )
            is CameraVideo -> arrayOf(
                MediaStore.Video.Media._ID,
                MediaStore.Video.Media.DATA,
                MediaStore.Video.Media.DISPLAY_NAME,
                MediaStore.Video.Media.SIZE,
                MediaStore.Video.Media.DATE_MODIFIED,
                MediaStore.Video.Media.DATE_ADDED,
                MediaStore.Video.Media.MIME_TYPE,
                MediaStore.Video.Media.DURATION,
                MediaStore.Video.Media.WIDTH,
                MediaStore.Video.Media.HEIGHT,
                MediaStore.Video.Media.BUCKET_DISPLAY_NAME  // 相册名称
            )
            is Document, is Archive, is Apk -> arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DATA,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.SIZE,
                MediaStore.Files.FileColumns.DATE_MODIFIED,
                MediaStore.Files.FileColumns.DATE_ADDED,
                MediaStore.Files.FileColumns.MIME_TYPE
            )
        }
    }
    
    /**
     * 获取排序规则
     */
    fun getSortOrder(): String {
        return when (this) {
            is Image, is CameraImage -> "${MediaStore.Images.Media.DATE_MODIFIED} DESC"
            is Audio, is Recording -> "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
            is Video, is CameraVideo -> "${MediaStore.Video.Media.DATE_MODIFIED} DESC"
            is Document, is Archive, is Apk -> "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
        }
    }
    
    /**
     * 获取查询条件（selection）
     */
    fun getSelection(): String? {
        return when (this) {
            // 相机照片：通过相册名过滤
            is CameraImage -> "${MediaStore.Images.Media.BUCKET_DISPLAY_NAME} = ?"
            
            // 相机视频：通过相册名过滤
            is CameraVideo -> "${MediaStore.Video.Media.BUCKET_DISPLAY_NAME} = ?"
            
            // 录音文件：通过路径过滤（Recordings文件夹）或MIME类型
            is Recording -> "(${MediaStore.Audio.Media.DATA} LIKE ? OR ${MediaStore.Audio.Media.DATA} LIKE ? OR ${MediaStore.Audio.Media.MIME_TYPE} = ? OR ${MediaStore.Audio.Media.MIME_TYPE} = ?)"
            
            // 文档、压缩包、APK：通过MIME类型过滤
            is Document, is Archive, is Apk -> {
                if (mimeTypes != null) {
                    mimeTypes.joinToString(" OR ") { "${MediaStore.Files.FileColumns.MIME_TYPE} = ?" }
                } else {
                    null
                }
            }
            
            // 其他类型无过滤
            else -> null
        }
    }
    
    /**
     * 获取查询参数（selectionArgs）
     */
    fun getSelectionArgs(): Array<String>? {
        return when (this) {
            // 相机照片/视频：相册名 = "Camera"
            is CameraImage, is CameraVideo -> arrayOf("Camera")
            
            // 录音文件：路径包含 Recordings 或 MIME 类型为 amr/3gpp
            is Recording -> arrayOf(
                "%/Recordings/%",      // 路径包含Recordings文件夹
                "%/Sounds/%",          // 或Sounds文件夹
                "audio/amr",            // AMR格式（常见录音格式）
                "audio/3gpp"            // 3GPP格式（常见录音格式）
            )
            
            // 文档、压缩包、APK：返回MIME类型数组
            is Document, is Archive, is Apk -> mimeTypes
            
            // 其他类型无参数
            else -> null
        }
    }
}
