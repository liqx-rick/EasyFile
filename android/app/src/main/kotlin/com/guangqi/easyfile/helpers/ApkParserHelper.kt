package com.guangqi.easyfile.helpers

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * APK解析助手
 *
 * 封装PackageManager相关功能，提供APK信息解析和安装状态检查
 */
class ApkParserHelper(private val context: Context) {
    private val packageManager: PackageManager = context.packageManager
    private val tag = "ApkParserHelper"

    /**
     * 解析单个APK文件
     *
     * @param filePath APK文件路径
     * @return APK信息Map，失败返回null
     */
    fun parseApk(filePath: String): Map<String, Any>? {
        try {
            val file = File(filePath)
            if (!file.exists() || !file.canRead()) {
                Log.e(tag, "APK文件不存在或不可读: $filePath")
                return null
            }

            // 获取包信息
            val packageInfo: PackageInfo? = try {
                packageManager.getPackageArchiveInfo(
                    filePath,
                    PackageManager.GET_META_DATA
                )
            } catch (e: Exception) {
                Log.e(tag, "解析APK失败: ${e.message}")
                null
            }

            if (packageInfo == null) {
                Log.e(tag, "无法解析APK: $filePath")
                return null
            }

            // 设置applicationInfo以便获取图标和标签
            val appInfo = packageInfo.applicationInfo
            if (appInfo == null) {
                Log.e(tag, "无法获取ApplicationInfo: $filePath")
                return null
            }

            appInfo.sourceDir = filePath
            appInfo.publicSourceDir = filePath

            val appName = packageManager.getApplicationLabel(appInfo).toString()
            val packageName = packageInfo.packageName
            val versionName = packageInfo.versionName ?: "unknown"
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode.toInt()
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode
            }

            // 获取应用图标（Base64编码）
            val appIconBase64 = try {
                val drawable = appInfo.loadIcon(packageManager)
                drawableToBase64(drawable)
            } catch (e: Exception) {
                Log.w(tag, "获取应用图标失败: ${e.message}")
                null
            }

            // 获取SDK版本信息
            val minSdkVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                appInfo.minSdkVersion
            } else {
                1 // API 24以下默认为1
            }
            val targetSdkVersion = appInfo.targetSdkVersion

            // 判断是否为Debug包
            val isDebug = (appInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

            // 获取文件信息
            val fileSize = file.length()
            val modifiedTime = file.lastModified()

            return mapOf<String, Any>(
                "filePath" to filePath,
                "appName" to appName,
                "packageName" to packageName,
                "versionName" to versionName,
                "versionCode" to versionCode,
                "appIconBase64" to (appIconBase64 ?: ""),
                "minSdkVersion" to minSdkVersion,
                "targetSdkVersion" to targetSdkVersion,
                "isDebug" to isDebug,
                "fileSize" to fileSize,
                "modifiedTime" to modifiedTime,
                "status" to "unknown" // Flutter端需要单独调用checkInstallStatus
            )
        } catch (e: Exception) {
            Log.e(tag, "解析APK异常: ${e.message}", e)
            return null
        }
    }

    /**
     * 批量解析APK文件
     *
     * @param filePaths APK文件路径列表
     * @return 成功解析的APK信息列表
     */
    fun parseApkBatch(filePaths: List<String>): List<Map<String, Any>> {
        return filePaths.mapNotNull { parseApk(it) }
    }

    /**
     * 检查APK安装状态
     *
     * @param packageName 包名
     * @param versionCode APK版本号
     * @return 安装状态字符串：notInstalled/installed/upgradable/signatureMismatch
     */
    fun checkInstallStatus(packageName: String, versionCode: Int): String {
        try {
            val installedPackage: PackageInfo? = try {
                packageManager.getPackageInfo(packageName, 0)
            } catch (e: PackageManager.NameNotFoundException) {
                null
            }

            if (installedPackage == null) {
                return "notInstalled"
            }

            val installedVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                installedPackage.longVersionCode.toInt()
            } else {
                @Suppress("DEPRECATION")
                installedPackage.versionCode
            }

            return when {
                installedVersionCode < versionCode -> "upgradable"
                installedVersionCode == versionCode -> "installed"
                else -> "notInstalled" // 已安装版本更高，视为"未安装"此APK
            }
        } catch (e: Exception) {
            Log.e(tag, "检查安装状态失败: ${e.message}", e)
            return "unknown"
        }
    }

    /**
     * 批量检查APK安装状态
     *
     * @param apkInfoList APK信息列表（包含packageName和versionCode）
     * @return Map<包名, 安装状态>
     */
    fun checkInstallStatusBatch(apkInfoList: List<Map<String, Any>>): Map<String, String> {
        return apkInfoList.associate { info ->
            val packageName = info["packageName"] as? String ?: return@associate "" to "unknown"
            val versionCode = (info["versionCode"] as? Number)?.toInt() ?: return@associate packageName to "unknown"
            packageName to checkInstallStatus(packageName, versionCode)
        }.filterKeys { it.isNotEmpty() }
    }

    /**
     * 跳转系统安装页面
     *
     * @param filePath APK文件路径
     * @return 是否成功跳转
     */
    fun launchInstall(filePath: String): Boolean {
        try {
            Log.i(tag, "=== 开始安装APK ===")
            Log.i(tag, "文件路径: $filePath")

            val file = File(filePath)
            if (!file.exists()) {
                Log.e(tag, "APK文件不存在: $filePath")
                return false
            }

            Log.i(tag, "文件存在: true, 大小: ${file.length()} bytes")

            // 检查安装权限（现代Android系统都需要此权限）
            val canInstall = context.packageManager.canRequestPackageInstalls()
            Log.i(tag, "安装权限状态: $canInstall")

            if (!canInstall) {
                Log.w(tag, "未获得安装权限，引导用户开启")
                // 跳转到设置页面让用户授权
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                intent.data = Uri.parse("package:${context.packageName}")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return false
            }

            val intent = Intent(Intent.ACTION_VIEW)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)

            // 使用FileProvider生成安全的URI
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val apkUri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )

            Log.i(tag, "生成的URI: $apkUri")
            intent.setDataAndType(apkUri, "application/vnd.android.package-archive")
            Log.i(tag, "准备启动安装Intent")

            context.startActivity(intent)

            Log.i(tag, "安装Intent已成功发送")
            return true
        } catch (e: Exception) {
            Log.e(tag, "跳转安装失败: ${e.message}", e)
            return false
        }
    }

    /**
     * 跳转应用详情页
     *
     * @param packageName 包名
     * @return 是否成功跳转
     */
    fun launchAppSettings(packageName: String): Boolean {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            context.startActivity(intent)
            Log.i(tag, "Launched app settings with NEW_TASK flag")
            return true
        } catch (e: Exception) {
            Log.e(tag, "跳转应用详情失败: ${e.message}", e)
            return false
        }
    }

    /**
     * Drawable转Base64编码
     *
     * @param drawable 图标Drawable
     * @return Base64字符串，失败返回null
     */
    private fun drawableToBase64(drawable: Drawable): String? {
        try {
            val bitmap = when (drawable) {
                is BitmapDrawable -> drawable.bitmap
                else -> {
                    val bitmap = Bitmap.createBitmap(
                        drawable.intrinsicWidth,
                        drawable.intrinsicHeight,
                        Bitmap.Config.ARGB_8888
                    )
                    val canvas = Canvas(bitmap)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                    bitmap
                }
            }

            val outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
            val byteArray = outputStream.toByteArray()
            return Base64.encodeToString(byteArray, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e(tag, "Drawable转Base64失败: ${e.message}", e)
            return null
        }
    }
}
