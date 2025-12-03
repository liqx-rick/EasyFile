package com.example.easyfile

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.app.AppOpsManager
import android.content.Context
import android.os.Process
import android.app.usage.UsageStatsManager
import android.app.usage.UsageStats
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.easyfile/share"
    private val STATE_CHANNEL = "com.example.easyfile/state"
    private val TRASH_CHANNEL = "com.example.easyfile/trash"
    private val SYSTEM_INTENT_CHANNEL = "com.easyfile/system_intent"
    private val STORAGE_STATS_CHANNEL = "com.easyfile/storage_stats"
    private val PERMISSION_CHANNEL = "com.easyfile/permission"
    private val USAGE_STATS_CHANNEL = "com.easyfile/usage_stats"
    private val TAG = "MainActivity"
    
    private var isRestoringFromBackground = false
    private lateinit var trashHelper: MediaStoreTrashHelper
    private lateinit var storageStatsHelper: StorageStatsHelper

    companion object {
        private var isFirstActivityCreate = true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // 检查是否是从后台恢复
        isRestoringFromBackground = savedInstanceState != null || 
                                   (intent?.flags?.and(Intent.FLAG_ACTIVITY_BROUGHT_TO_FRONT) != 0)
        
        Log.i(TAG, "onCreate - isRestoring: $isRestoringFromBackground, isFirst: $isFirstActivityCreate")
        
        // 初始化 MediaStoreTrashHelper
        trashHelper = MediaStoreTrashHelper(this)
        
        // 初始化 StorageStatsHelper
        storageStatsHelper = StorageStatsHelper(this)
        
        // 决定是否显示 Native Splash
        if (isRestoringFromBackground) {
            setTheme(R.style.NormalTheme) // 跳过 Native Splash
        } else if (!isFirstActivityCreate) {
            setTheme(R.style.NormalTheme) // 非首次创建也跳过
        }
        // 否则使用默认 LaunchTheme（显示 Native Splash）
        
        isFirstActivityCreate = false
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        
        // 分享功能 Channel
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareFile" -> {
                    val filePath = call.argument<String>("filePath")
                    val mimeType = call.argument<String>("mimeType") ?: "*/*"
                    
                    if (filePath != null) {
                        try {
                            ShareHelper.shareFile(this, filePath, mimeType)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "File path is required", null)
                    }
                }
                "shareMultipleFiles" -> {
                    val filePaths = call.argument<List<String>>("filePaths")
                    
                    if (filePaths != null && filePaths.isNotEmpty()) {
                        try {
                            ShareHelper.shareMultipleFiles(this, filePaths)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "File paths are required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 应用状态 Channel
        MethodChannel(messenger, STATE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isRestoringFromBackground" -> {
                    Log.i(TAG, "Flutter query - isRestoring: $isRestoringFromBackground")
                    result.success(isRestoringFromBackground)
                }
                else -> result.notImplemented()
            }
        }
        
        // MediaStore回收站 Channel
        MethodChannel(messenger, TRASH_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    result.success(MediaStoreTrashHelper.isSupported())
                }
                "queryTrashedFiles" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        try {
                            val files = trashHelper.queryTrashedFiles()
                            result.success(files)
                        } catch (e: Exception) {
                            result.error("QUERY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("UNSUPPORTED", "Requires Android 11+", null)
                    }
                }
                "deleteTrashedFile" -> {
                    val fileId = call.argument<Long>("fileId")
                    if (fileId != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        try {
                            val success = trashHelper.deleteTrashedFile(fileId)
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("DELETE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "File ID required", null)
                    }
                }
                "deleteMultipleTrashedFiles" -> {
                    val fileIds = call.argument<List<Long>>("fileIds")
                    if (fileIds != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        try {
                            val resultMap = trashHelper.deleteMultipleTrashedFiles(fileIds)
                            result.success(resultMap)
                        } catch (e: Exception) {
                            result.error("DELETE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "File IDs required", null)
                    }
                }
                "emptyTrash" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        try {
                            val resultMap = trashHelper.emptyTrash()
                            result.success(resultMap)
                        } catch (e: Exception) {
                            result.error("EMPTY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("UNSUPPORTED", "Requires Android 11+", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 系统意图 Channel
        MethodChannel(messenger, SYSTEM_INTENT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error opening app settings: ${e.message}")
                            result.error("INTENT_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name required", null)
                    }
                }
                "openUsageStatsSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error opening usage stats settings: ${e.message}")
                        result.error("INTENT_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 存储统计 Channel
        MethodChannel(messenger, STORAGE_STATS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    result.success(StorageStatsHelper.isSupported())
                }
                "getAppStorageStats" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            try {
                                val stats = storageStatsHelper.getAppStorageStats(packageName)
                                result.success(stats)
                            } catch (e: Exception) {
                                Log.e(TAG, "Error getting storage stats: ${e.message}")
                                result.error("STATS_ERROR", e.message, null)
                            }
                        } else {
                            result.error("UNSUPPORTED", "Requires Android 8.0+", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name required", null)
                    }
                }
                "batchGetStorageStats" -> {
                    val packageNames = call.argument<List<String>>("packageNames")
                    if (packageNames != null) {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            try {
                                val stats = storageStatsHelper.batchGetAppStorageStats(packageNames)
                                result.success(stats)
                            } catch (e: Exception) {
                                Log.e(TAG, "Error batch getting storage stats: ${e.message}")
                                result.error("STATS_ERROR", e.message, null)
                            }
                        } else {
                            result.error("UNSUPPORTED", "Requires Android 8.0+", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package names required", null)
                    }
                }
                "getFirstInstallTime" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        try {
                            val packageInfo = packageManager.getPackageInfo(packageName, 0)
                            result.success(packageInfo.firstInstallTime)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error getting first install time: ${e.message}")
                            result.error("INSTALL_TIME_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 使用统计 Channel
        MethodChannel(messenger, USAGE_STATS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppUsageStats" -> {
                    val packageName = call.argument<String>("packageName")
                    val daysBack = call.argument<Int>("daysBack") ?: 7
                    
                    if (packageName != null) {
                        try {
                            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                            val endTime = System.currentTimeMillis()
                            val startTime = endTime - (daysBack * 24 * 60 * 60 * 1000L)
                            
                            // 使用 INTERVAL_BEST 获取最精确的数据
                            val usageStatsList = usageStatsManager.queryUsageStats(
                                UsageStatsManager.INTERVAL_BEST,
                                startTime,
                                endTime
                            )
                            
                            // 找到该应用的所有记录，取最新的一条
                            val appStatsList = usageStatsList.filter { it.packageName == packageName }
                            val latestStats = appStatsList.maxByOrNull { it.lastTimeUsed }
                            
                            if (latestStats != null) {
                                // 即使 lastTimeUsed == 0 也返回数据，让 Flutter 端决定如何显示
                                val statsMap = mapOf(
                                    "packageName" to latestStats.packageName,
                                    "lastTimeUsed" to latestStats.lastTimeUsed,
                                    "totalTimeInForeground" to latestStats.totalTimeInForeground,
                                    "launchCount" to 0
                                )
                                result.success(statsMap)
                            } else {
                                // 应用没有使用记录
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error getting usage stats: ${e.message}")
                            result.error("USAGE_STATS_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name required", null)
                    }
                }
                "batchGetUsageStats" -> {
                    val packageNames = call.argument<List<String>>("packageNames")
                    val daysBack = call.argument<Int>("daysBack") ?: 7
                    
                    Log.d(TAG, "========== batchGetUsageStats ==========")
                    Log.d(TAG, "请求参数: packageNames=${packageNames?.size}, daysBack=$daysBack")
                    
                    if (packageNames != null) {
                        try {
                            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                            val endTime = System.currentTimeMillis()
                            val startTime = endTime - (daysBack * 24 * 60 * 60 * 1000L)
                            
                            val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                            Log.d(TAG, "查询时间范围:")
                            Log.d(TAG, "  startTime: ${dateFormat.format(Date(startTime))} ($startTime)")
                            Log.d(TAG, "  endTime:   ${dateFormat.format(Date(endTime))} ($endTime)")
                            
                            // 使用 INTERVAL_BEST 获取最精确的数据
                            val usageStatsList = usageStatsManager.queryUsageStats(
                                UsageStatsManager.INTERVAL_BEST,
                                startTime,
                                endTime
                            )
                            
                            Log.d(TAG, "系统返回 ${usageStatsList.size} 条使用记录")
                            
                            // 按lastTimeUsed分组统计
                            var count0to7 = 0
                            var count8to30 = 0
                            var count31to180 = 0
                            var countOver180 = 0
                            var countZero = 0
                            
                            for (stat in usageStatsList) {
                                if (stat.lastTimeUsed == 0L) {
                                    countZero++
                                } else {
                                    val daysAgo = ((endTime - stat.lastTimeUsed) / (24 * 60 * 60 * 1000)).toInt()
                                    when {
                                        daysAgo <= 7 -> count0to7++
                                        daysAgo <= 30 -> count8to30++
                                        daysAgo <= 180 -> count31to180++
                                        else -> countOver180++
                                    }
                                }
                            }
                            
                            Log.d(TAG, "使用记录时间分布:")
                            Log.d(TAG, "  0-7天: $count0to7")
                            Log.d(TAG, "  8-30天: $count8to30")
                            Log.d(TAG, "  31-180天: $count31to180")
                            Log.d(TAG, "  >180天: $countOver180")
                            Log.d(TAG, "  lastTimeUsed=0: $countZero")
                            
                            // 为每个应用找到最新的使用记录
                            val statsMap = mutableMapOf<String, Map<String, Any?>>()
                            
                            for (packageName in packageNames) {
                                // 找到该应用的所有记录，取最新的一条
                                val appStatsList = usageStatsList.filter { it.packageName == packageName }
                                
                                if (appStatsList.isNotEmpty()) {
                                    Log.d(TAG, "[$packageName] 找到 ${appStatsList.size} 条记录")
                                    
                                    // 打印所有记录的lastTimeUsed
                                    appStatsList.forEachIndexed { index, stat ->
                                        val daysAgo = if (stat.lastTimeUsed > 0) {
                                            ((endTime - stat.lastTimeUsed) / (24 * 60 * 60 * 1000)).toInt()
                                        } else {
                                            -1
                                        }
                                        Log.d(TAG, "  记录$index: lastTimeUsed=${stat.lastTimeUsed}, ${daysAgo}天前, totalTime=${stat.totalTimeInForeground}ms")
                                    }
                                }
                                
                                val latestStats = appStatsList.maxByOrNull { it.lastTimeUsed }
                                
                                if (latestStats != null) {
                                    val daysSinceUsed = if (latestStats.lastTimeUsed > 0) {
                                        ((endTime - latestStats.lastTimeUsed) / (24 * 60 * 60 * 1000)).toInt()
                                    } else {
                                        -1
                                    }
                                    
                                    Log.d(TAG, "[$packageName] 最新记录: lastTimeUsed=${latestStats.lastTimeUsed}, ${daysSinceUsed}天前")
                                    
                                    // 特别标记超过30天的应用
                                    if (daysSinceUsed > 30) {
                                        Log.w(TAG, "!!! [$packageName] 发现超过30天的使用记录: ${daysSinceUsed}天前 !!!")
                                    }
                                    
                                    // 即使 lastTimeUsed == 0 也返回数据，让 Flutter 端决定如何显示
                                    statsMap[packageName] = mapOf(
                                        "packageName" to latestStats.packageName,
                                        "lastTimeUsed" to latestStats.lastTimeUsed,
                                        "totalTimeInForeground" to latestStats.totalTimeInForeground,
                                        "launchCount" to 0
                                    )
                                }
                            }
                            
                            Log.d(TAG, "========== 返回 ${statsMap.size} 个应用的统计数据 ==========")
                            result.success(statsMap)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error batch getting usage stats: ${e.message}")
                            result.error("USAGE_STATS_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package names required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 权限检查 Channel
        MethodChannel(messenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageStatsPermission" -> {
                    result.success(hasUsageStatsPermission())
                }
                else -> result.notImplemented()
            }
        }
    }
    
    /**
     * 检查是否有 PACKAGE_USAGE_STATS 权限
     */
    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.e(TAG, "Error checking usage stats permission: ${e.message}")
            false
        }
    }
}
