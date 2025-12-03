package com.example.easyfile

import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.storage.StorageManager
import android.util.Log
import androidx.annotation.RequiresApi
import java.util.UUID

/**
 * 应用存储统计助手
 * 
 * 使用 StorageStatsManager API 获取应用的真实存储占用信息
 * 需要 Android 8.0 (API 26) 及以上版本
 */
class StorageStatsHelper(private val context: Context) {

    private val storageStatsManager: StorageStatsManager? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.getSystemService(Context.STORAGE_STATS_SERVICE) as? StorageStatsManager
        } else {
            null
        }
    }

    private val storageManager: StorageManager by lazy {
        context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
    }

    /**
     * 获取应用的存储统计信息
     * 
     * 需要 PACKAGE_USAGE_STATS 权限才能查询其他应用
     * 
     * @param packageName 应用包名
     * @return Map包含 appSize, dataSize, cacheSize (单位：字节)，失败返回null
     */
    @RequiresApi(Build.VERSION_CODES.O)
    fun getAppStorageStats(packageName: String): Map<String, Long>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return null
        }

        try {
            val statsManager = storageStatsManager ?: return null

            // 获取存储卷UUID (通常是内部存储)
            val storageVolume = storageManager.primaryStorageVolume
            val uuidStr = storageVolume.uuid
            val uuid = if (uuidStr == null) {
                StorageManager.UUID_DEFAULT
            } else {
                UUID.fromString(uuidStr)
            }

            // 获取当前用户
            val user = android.os.Process.myUserHandle()

            // 使用 queryStatsForPackage 查询指定应用的存储统计
            // 注意：查询其他应用需要 PACKAGE_USAGE_STATS 权限
            val stats = statsManager.queryStatsForPackage(uuid, packageName, user)

            val appBytes = stats.appBytes
            val dataBytes = stats.dataBytes
            val cacheBytes = stats.cacheBytes
            
            // 详细日志（特别关注微信）
            if (packageName == "com.tencent.mm") {
                Log.i("StorageStatsHelper", "=== WeChat Storage Stats (API Values) ===")
                Log.i("StorageStatsHelper", "appBytes (code): $appBytes (${appBytes / 1024 / 1024}MB)")
                Log.i("StorageStatsHelper", "dataBytes (all data including cache): $dataBytes (${dataBytes / 1024 / 1024}MB)")
                Log.i("StorageStatsHelper", "cacheBytes (subset of dataBytes): $cacheBytes (${cacheBytes / 1024 / 1024}MB)")
                Log.i("StorageStatsHelper", "OLD calculation (WRONG - double counts cache): ${(appBytes + dataBytes + cacheBytes) / 1024 / 1024}MB")
                Log.i("StorageStatsHelper", "NEW calculation (CORRECT - no double counting): ${(appBytes + dataBytes) / 1024 / 1024}MB")
                Log.i("StorageStatsHelper", "============================")
            }

            return mapOf(
                "appSize" to appBytes,
                "dataSize" to dataBytes,
                "cacheSize" to cacheBytes
            )
        } catch (e: PackageManager.NameNotFoundException) {
            // 应用未安装
            return null
        } catch (e: SecurityException) {
            // 缺少 PACKAGE_USAGE_STATS 权限
            return null
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    /**
     * 批量获取多个应用的存储统计
     * 
     * @param packageNames 包名列表
     * @return Map<包名, 存储统计>
     */
    @RequiresApi(Build.VERSION_CODES.O)
    fun batchGetAppStorageStats(packageNames: List<String>): Map<String, Map<String, Long>> {
        val results = mutableMapOf<String, Map<String, Long>>()
        
        for (packageName in packageNames) {
            val stats = getAppStorageStats(packageName)
            if (stats != null) {
                results[packageName] = stats
            }
        }
        
        return results
    }

    companion object {
        /**
         * 检查当前设备是否支持 StorageStatsManager API
         */
        fun isSupported(): Boolean {
            return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
        }
    }
}
