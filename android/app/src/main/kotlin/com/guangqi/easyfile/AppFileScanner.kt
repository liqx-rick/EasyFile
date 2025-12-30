package com.guangqi.easyfile

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * 按应用包名扫描文件（用于方案对比测试）
 */
class AppFileScanner(private val context: Context) {
    
    companion object {
        private const val TAG = "AppFileScanner"
    }
    
    /**
     * 使用 MediaStore OWNER_PACKAGE_NAME 扫描（方案2 - Android 11+）
     */
    fun scanByOwnerPackage(packageName: String): List<Map<String, Any>> {
        val files = mutableListOf<Map<String, Any>>()
        val startTime = System.currentTimeMillis()
        
        // 检查 Android 版本
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            LogHelper.w(TAG, "OWNER_PACKAGE_NAME requires Android 11+, current: ${Build.VERSION.SDK_INT}")
            return files
        }
        
        try {
            val projection = arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DATA,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.SIZE,
                MediaStore.Files.FileColumns.DATE_MODIFIED,
                MediaStore.Files.FileColumns.MIME_TYPE,
                MediaStore.Files.FileColumns.OWNER_PACKAGE_NAME
            )
            
            // 过滤特定包名
            val selection = "${MediaStore.Files.FileColumns.OWNER_PACKAGE_NAME} = ?"
            val selectionArgs = arrayOf(packageName)
            val sortOrder = "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
            
            val cursor = context.contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                projection,
                selection,
                selectionArgs,
                sortOrder
            )
            
            cursor?.use {
                val pathColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATA)
                val nameColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val sizeColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                val modifiedColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
                val mimeColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)
                
                LogHelper.d(TAG, "开始遍历 MediaStore 查询结果，总数: ${it.count}")
                
                while (it.moveToNext()) {
                    val path = it.getString(pathColumn) ?: continue
                    val name = it.getString(nameColumn) ?: continue
                    
                    // 过滤隐藏文件和隐藏文件夹中的文件
                    if (name.startsWith(".") || path.contains("/.")) continue
                    
                    val size = it.getLong(sizeColumn)
                    val modified = it.getLong(modifiedColumn) * 1000
                    val mimeType = it.getString(mimeColumn) ?: "application/octet-stream"
                    
                    files.add(mapOf(
                        "path" to path,
                        "name" to name,
                        "size" to size,
                        "modified" to modified,
                        "mimeType" to mimeType
                    ))
                }
            }
            
            val endTime = System.currentTimeMillis()
            val duration = endTime - startTime
            
            LogHelper.i(TAG, "MediaStore OWNER_PACKAGE_NAME 扫描完成: ${files.size} 个文件, 耗时: ${duration}ms")
            
        } catch (e: Exception) {
            LogHelper.e(TAG, "MediaStore 扫描失败: ${e.message}", e)
        }
        
        return files
    }
    
    /**
     * 检查当前 Android 版本是否支持 OWNER_PACKAGE_NAME
     */
    fun isOwnerPackageSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
    }
    
    /**
     * 通过文件名模式扫描（例如微信相机文件）
     * @param patterns 文件名模式列表（支持 SQL LIKE 语法，% 代表任意字符）
     */
    fun scanByFileNamePattern(patterns: List<String>): List<Map<String, Any>> {
        val files = mutableListOf<Map<String, Any>>()
        val startTime = System.currentTimeMillis()
        
        try {
            val projection = arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DATA,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.SIZE,
                MediaStore.Files.FileColumns.DATE_MODIFIED,
                MediaStore.Files.FileColumns.MIME_TYPE
            )
            
            // 构建文件名匹配条件 (DISPLAY_NAME LIKE 'wx_camera_%' OR DISPLAY_NAME LIKE 'mmexport%')
            val selectionParts = patterns.map { "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?" }
            val selection = selectionParts.joinToString(" OR ")
            val selectionArgs = patterns.toTypedArray()
            
            val sortOrder = "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
            
            val cursor = context.contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                projection,
                selection,
                selectionArgs,
                sortOrder
            )
            
            cursor?.use {
                val pathColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATA)
                val nameColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val sizeColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                val modifiedColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
                val mimeColumn = it.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)
                
                LogHelper.d(TAG, "开始遍历文件名模式查询结果，总数: ${it.count}")
                
                while (it.moveToNext()) {
                    val path = it.getString(pathColumn) ?: continue
                    val name = it.getString(nameColumn) ?: continue
                    
                    // 过滤隐藏文件和隐藏文件夹中的文件
                    if (name.startsWith(".") || path.contains("/.")) continue
                    
                    val size = it.getLong(sizeColumn)
                    val modified = it.getLong(modifiedColumn) * 1000
                    val mimeType = it.getString(mimeColumn) ?: "application/octet-stream"
                    
                    files.add(mapOf(
                        "path" to path,
                        "name" to name,
                        "size" to size,
                        "modified" to modified,
                        "mimeType" to mimeType
                    ))
                }
            }
            
            val endTime = System.currentTimeMillis()
            val duration = endTime - startTime
            
            LogHelper.i(TAG, "文件名模式扫描完成: ${files.size} 个文件, 耗时: ${duration}ms")
            
        } catch (e: Exception) {
            LogHelper.e(TAG, "文件名模式扫描失败: ${e.message}", e)
        }
        
        return files
    }
    
    /**
     * 获取应用特定的文件名模式
     */
    fun getAppFileNamePatterns(appKey: String): List<String> {
        return when (appKey) {
            "wechat" -> listOf(
                "wx_camera_%",  // 微信相机拍摄的文件
                "mmexport%"     // 微信导出的文件
            )
            else -> emptyList()
        }
    }
    
    /**
     * 获取已知应用的路径列表
     */
    fun getKnownAppPaths(appKey: String): List<String> {
        return when (appKey) {
            "wechat" -> listOf(
                "/storage/emulated/0/Download/WeiXin/",
                "/storage/emulated/0/Pictures/WeiXin/",
                "/storage/emulated/0/DCIM/WeiXin/",
                "/storage/emulated/0/Music/WeiXin/",
                "/storage/emulated/0/Movies/WeiXin/",
                "/storage/emulated/0/Documents/WeiXin/",
                "/storage/emulated/0/tencent/MicroMsg/WeiXin/"
            )
            "qq" -> listOf(
                "/storage/emulated/0/tencent/QQfile_recv/"
            )
            "telegram" -> listOf(
                "/storage/emulated/0/Telegram/"
            )
            else -> emptyList()
        }
    }
    
    /**
     * 在指定基础路径下查找包含特定关键字的子文件夹
     * @param basePaths 基础搜索路径列表
     * @param keyword 文件夹名称关键字（不区分大小写）
     * @return 匹配的文件夹路径列表
     */
    fun findFoldersContaining(basePaths: List<String>, keyword: String): List<String> {
        val matchedFolders = mutableListOf<String>()
        val startTime = System.currentTimeMillis()
        
        try {
            val keywordLower = keyword.lowercase()
            
            for (basePath in basePaths) {
                val baseDir = java.io.File(basePath)
                if (!baseDir.exists() || !baseDir.isDirectory) {
                    continue
                }
                
                // 遍历子文件夹（只搜索一层）
                baseDir.listFiles()?.forEach { file ->
                    if (file.isDirectory) {
                        val folderName = file.name.lowercase()
                        // 严格匹配文件夹名称（不区分大小写）
                        if (folderName == keywordLower) {
                            matchedFolders.add(file.absolutePath + "/")
                            LogHelper.d(TAG, "找到匹配文件夹: ${file.absolutePath}")
                        }
                    }
                }
            }
            
            val endTime = System.currentTimeMillis()
            val duration = endTime - startTime
            
            LogHelper.i(TAG, "查找严格匹配 '$keyword' 的文件夹完成: ${matchedFolders.size} 个, 耗时: ${duration}ms")
            
        } catch (e: Exception) {
            LogHelper.e(TAG, "查找文件夹失败: ${e.message}", e)
        }
        
        return matchedFolders
    }
    
    /**
     * 检查应用是否已安装
     * 
     * @param packageName 应用包名，如 "com.tencent.mm"
     * @return true 表示已安装
     */
    fun isAppInstalled(packageName: String): Boolean {
        return try {
            context.packageManager.getPackageInfo(packageName, 0)
            LogHelper.d(TAG, "应用已安装: $packageName")
            true
        } catch (e: PackageManager.NameNotFoundException) {
            LogHelper.d(TAG, "应用未安装: $packageName")
            false
        } catch (e: Exception) {
            LogHelper.e(TAG, "检测应用安装失败: ${e.message}", e)
            false
        }
    }
    
    /**
     * 获取应用图标
     * 
     * @param packageName 应用包名
     * @return 图标的字节数组（PNG格式），如果应用未安装或获取失败则返回 null
     */
    fun getAppIcon(packageName: String): ByteArray? {
        return try {
            val startTime = System.currentTimeMillis()
            
            // 获取应用信息
            val appInfo = context.packageManager.getApplicationInfo(packageName, 0)
            
            // 获取应用图标
            val drawable = context.packageManager.getApplicationIcon(appInfo)
            
            // 将 Drawable 转换为 Bitmap
            val bitmap = when (drawable) {
                is BitmapDrawable -> drawable.bitmap
                else -> {
                    // 其他类型的 Drawable 需要手动绘制到 Bitmap 上
                    val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
                    val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
                    
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bitmap)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                    bitmap
                }
            }
            
            // 转换为字节数组（PNG 格式）
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            val byteArray = stream.toByteArray()
            
            val endTime = System.currentTimeMillis()
            val duration = endTime - startTime
            
            LogHelper.d(TAG, "获取应用图标成功: $packageName, 大小: ${byteArray.size} bytes, 耗时: ${duration}ms")
            
            byteArray
        } catch (e: PackageManager.NameNotFoundException) {
            LogHelper.w(TAG, "应用未安装，无法获取图标: $packageName")
            null
        } catch (e: Exception) {
            LogHelper.e(TAG, "获取应用图标失败: ${e.message}", e)
            null
        }
    }
}