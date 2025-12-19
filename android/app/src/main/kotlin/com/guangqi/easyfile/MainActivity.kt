package com.guangqi.easyfile

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.provider.MediaStore
import android.content.pm.PackageManager
import android.util.Log
import android.app.AppOpsManager
import android.content.Context
import android.os.Process
import android.app.usage.UsageStatsManager
import android.app.usage.UsageStats
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Calendar
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.content.BroadcastReceiver
import android.content.IntentFilter
import androidx.exifinterface.media.ExifInterface

class MainActivity : FlutterActivity() {
    // 文件分享功能通道
    private val CHANNEL = "com.guangqi.easyfile/share"
    // 应用状态查询通道（判断是否从后台恢复）
    private val STATE_CHANNEL = "com.guangqi.easyfile/state"
    // MediaStore回收站操作通道（Android 11+）
    private val TRASH_CHANNEL = "com.guangqi.easyfile/trash"
    // 系统设置页面跳转通道
    private val SYSTEM_INTENT_CHANNEL = "com.easyfile/system_intent"
    // 应用存储空间统计通道（Android 8.0+）
    private val STORAGE_STATS_CHANNEL = "com.easyfile/storage_stats"
    // 权限检查通道
    private val PERMISSION_CHANNEL = "com.easyfile/permission"
    // 应用使用统计通道（UsageStats API）
    private val USAGE_STATS_CHANNEL = "com.easyfile/usage_stats"
    // 文件统计信息通道（获取文件创建时间等）
    private val FILE_STATS_CHANNEL = "com.easyfile/file_stats"
    // MediaStore 统一扫描通道
    private val MEDIASTORE_SCANNER_CHANNEL = "easyfile/mediastore_scanner"
    // 应用文件扫描测试通道
    private val APP_FILE_SCANNER_CHANNEL = "easyfile/app_file_scanner"
    // 本机相机照片测试通道
    private val NATIVE_CAMERA_TEST_CHANNEL = "easyfile/native_camera_test"
    // 应用安装/卸载事件通道
    private val APP_EVENT_CHANNEL = "easyfile/app_events"
    private val TAG = "MainActivity"
    
    private var isRestoringFromBackground = false
    private lateinit var trashHelper: MediaStoreTrashHelper
    private lateinit var storageStatsHelper: StorageStatsHelper
    private lateinit var mediaStoreScanner: MediaStoreScanner
    private lateinit var appFileScanner: AppFileScanner
    private var appEventSink: EventChannel.EventSink? = null
    
    // 应用安装/卸载广播接收器
    private val packageChangeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_PACKAGE_ADDED -> {
                    val packageName = intent.data?.schemeSpecificPart
                    Log.i(TAG, "应用安装: $packageName")
                    packageName?.let {
                        appEventSink?.success(mapOf(
                            "event" to "installed",
                            "packageName" to it
                        ))
                    }
                }
                Intent.ACTION_PACKAGE_REMOVED -> {
                    val packageName = intent.data?.schemeSpecificPart
                    Log.i(TAG, "应用卸载: $packageName")
                    packageName?.let {
                        appEventSink?.success(mapOf(
                            "event" to "uninstalled",
                            "packageName" to it
                        ))
                    }
                }
            }
        }
    }

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
        
        // 初始化 MediaStoreScanner (统一扫描器)
        mediaStoreScanner = MediaStoreScanner(this)
        
        // 初始化 AppFileScanner
        appFileScanner = AppFileScanner(this)
        
        // 注册应用安装/卸载监听器
        registerPackageChangeReceiver()
        
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
                            
                            // 获取PackageInfo的lastUpdateTime（无论有无UsageStats都获取）
                            var lastUpdateTime: Long? = null
                            try {
                                val packageInfo = packageManager.getPackageInfo(packageName, 0)
                                lastUpdateTime = packageInfo.lastUpdateTime
                            } catch (e: Exception) {
                                Log.w(TAG, "[$packageName] 无法获取PackageInfo: ${e.message}")
                            }
                            
                            // 如果有UsageStats或有lastUpdateTime，就返回数据
                            if (latestStats != null || lastUpdateTime != null) {
                                val statsMap = mapOf(
                                    "packageName" to packageName,
                                    "lastTimeUsed" to (latestStats?.lastTimeUsed ?: 0L),
                                    "lastUpdateTime" to lastUpdateTime,
                                    "totalTimeInForeground" to (latestStats?.totalTimeInForeground ?: 0L),
                                    "launchCount" to 0
                                )
                                result.success(statsMap)
                            } else {
                                // 既没有使用记录也获取不到PackageInfo
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
                                
                                // 获取PackageInfo的lastUpdateTime（无论有无UsageStats都获取）
                                var lastUpdateTime: Long? = null
                                try {
                                    val packageInfo = packageManager.getPackageInfo(packageName, 0)
                                    lastUpdateTime = packageInfo.lastUpdateTime
                                    Log.d(TAG, "[$packageName] lastUpdateTime=${lastUpdateTime}")
                                } catch (e: Exception) {
                                    Log.w(TAG, "[$packageName] 无法获取PackageInfo: ${e.message}")
                                }
                                
                                // 如果有UsageStats或有lastUpdateTime，就返回数据
                                if (latestStats != null || lastUpdateTime != null) {
                                    val lastTimeUsed = latestStats?.lastTimeUsed ?: 0L
                                    val totalTimeInForeground = latestStats?.totalTimeInForeground ?: 0L
                                    
                                    if (latestStats != null) {
                                        val daysSinceUsed = if (lastTimeUsed > 0) {
                                            ((endTime - lastTimeUsed) / (24 * 60 * 60 * 1000)).toInt()
                                        } else {
                                            -1
                                        }
                                        Log.d(TAG, "[$packageName] 最新记录: lastTimeUsed=${lastTimeUsed}, ${daysSinceUsed}天前")
                                        
                                        // 特别标记超过30天的应用
                                        if (daysSinceUsed > 30) {
                                            Log.w(TAG, "!!! [$packageName] 发现超过30天的使用记录: ${daysSinceUsed}天前 !!!")
                                        }
                                    } else {
                                        Log.d(TAG, "[$packageName] 无UsageStats记录，仅使用lastUpdateTime")
                                    }
                                    
                                    // 返回数据，让 Flutter 端决定如何显示
                                    statsMap[packageName] = mapOf(
                                        "packageName" to packageName,
                                        "lastTimeUsed" to lastTimeUsed,
                                        "lastUpdateTime" to lastUpdateTime,
                                        "totalTimeInForeground" to totalTimeInForeground,
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
                "testAllIntervals" -> {
                    val packageName = call.argument<String>("packageName")
                    val daysBack = call.argument<Int>("daysBack") ?: 90
                    
                    if (packageName != null) {
                        try {
                            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                            val endTime = System.currentTimeMillis()
                            val startTime = endTime - (daysBack * 24 * 60 * 60 * 1000L)
                            
                            val results = mutableMapOf<String, Map<String, Any?>>()
                            
                            // 测试所有 INTERVAL 类型
                            val intervals = listOf(
                                "BEST" to UsageStatsManager.INTERVAL_BEST,
                                "DAILY" to UsageStatsManager.INTERVAL_DAILY,
                                "WEEKLY" to UsageStatsManager.INTERVAL_WEEKLY,
                                "MONTHLY" to UsageStatsManager.INTERVAL_MONTHLY,
                                "YEARLY" to UsageStatsManager.INTERVAL_YEARLY
                            )
                            
                            for ((name, intervalType) in intervals) {
                                val usageStatsList = usageStatsManager.queryUsageStats(
                                    intervalType,
                                    startTime,
                                    endTime
                                )
                                
                                val appStatsList = usageStatsList.filter { it.packageName == packageName }
                                val latestStats = appStatsList.maxByOrNull { it.lastTimeUsed }
                                
                                if (latestStats != null) {
                                    results[name] = mapOf(
                                        "lastTimeUsed" to latestStats.lastTimeUsed,
                                        "totalTimeInForeground" to latestStats.totalTimeInForeground,
                                        "recordCount" to appStatsList.size
                                    )
                                    Log.d(TAG, "[$name] Found ${appStatsList.size} records, lastTimeUsed=${latestStats.lastTimeUsed}")
                                } else {
                                    results[name] = mapOf(
                                        "lastTimeUsed" to 0,
                                        "totalTimeInForeground" to 0,
                                        "recordCount" to 0
                                    )
                                    Log.d(TAG, "[$name] No data found")
                                }
                            }
                            
                            result.success(results)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error testing intervals: ${e.message}")
                            result.error("INTERVAL_TEST_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name required", null)
                    }
                }
                "querySpecificDate" -> {
                    val packageName = call.argument<String>("packageName")
                    val year = call.argument<Int>("year")
                    val month = call.argument<Int>("month")  // 1-12
                    val day = call.argument<Int>("day")
                    
                    if (packageName != null && year != null && month != null && day != null) {
                        try {
                            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                            
                            // 设置查询的起始时间（当天 00:00:00）
                            val calendar = Calendar.getInstance()
                            calendar.set(year, month - 1, day, 0, 0, 0)  // month是0-based
                            calendar.set(Calendar.MILLISECOND, 0)
                            val startTime = calendar.timeInMillis
                            
                            // 设置查询的结束时间（当天 23:59:59）
                            calendar.set(year, month - 1, day, 23, 59, 59)
                            calendar.set(Calendar.MILLISECOND, 999)
                            val endTime = calendar.timeInMillis
                            
                            val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                            Log.d(TAG, "查询特定日期: $year-$month-$day")
                            Log.d(TAG, "  startTime: ${dateFormat.format(Date(startTime))}")
                            Log.d(TAG, "  endTime: ${dateFormat.format(Date(endTime))}")
                            
                            // 使用 INTERVAL_DAILY 查询当天数据
                            val usageStatsList = usageStatsManager.queryUsageStats(
                                UsageStatsManager.INTERVAL_DAILY,
                                startTime,
                                endTime
                            )
                            
                            Log.d(TAG, "系统返回 ${usageStatsList.size} 条记录")
                            
                            // 找到该应用的记录
                            val appStatsList = usageStatsList.filter { it.packageName == packageName }
                            Log.d(TAG, "找到 ${appStatsList.size} 条 $packageName 的记录")
                            
                            if (appStatsList.isNotEmpty()) {
                                val latestStats = appStatsList.maxByOrNull { it.lastTimeUsed }
                                
                                if (latestStats != null) {
                                    val resultMap = mapOf(
                                        "packageName" to latestStats.packageName,
                                        "lastTimeUsed" to latestStats.lastTimeUsed,
                                        "totalTimeInForeground" to latestStats.totalTimeInForeground,
                                        "firstTimeStamp" to latestStats.firstTimeStamp,
                                        "lastTimeStamp" to latestStats.lastTimeStamp,
                                        "recordCount" to appStatsList.size
                                    )
                                    
                                    Log.d(TAG, "查询结果: lastTimeUsed=${latestStats.lastTimeUsed}, totalTime=${latestStats.totalTimeInForeground}ms")
                                    result.success(resultMap)
                                } else {
                                    result.success(null)
                                }
                            } else {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error querying specific date: ${e.message}")
                            result.error("QUERY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "packageName, year, month, day required", null)
                    }
                }
                "getAppFullInfo" -> {
                    val packageName = call.argument<String>("packageName")
                    val daysBack = call.argument<Int>("daysBack") ?: 365
                    
                    if (packageName != null) {
                        try {
                            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                            val endTime = System.currentTimeMillis()
                            val startTime = endTime - (daysBack * 24 * 60 * 60 * 1000L)
                            
                            Log.d(TAG, "获取应用完整信息（使用UsageEvents）: $packageName (最近${daysBack}天)")
                            
                            val fullInfo = mutableMapOf<String, Any?>()
                            fullInfo["packageName"] = packageName
                            
                            // 使用 UsageEvents 获取详细事件
                            val events = usageStatsManager.queryEvents(startTime, endTime)
                            
                            var eventCount = 0
                            var firstEventTime: Long? = null
                            var lastEventTime: Long? = null
                            var totalForegroundTime = 0L
                            var lastResumeTime: Long? = null
                            
                            val usedDates = mutableSetOf<String>()
                            val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
                            
                            while (events.hasNextEvent()) {
                                val event = android.app.usage.UsageEvents.Event()
                                events.getNextEvent(event)
                                
                                if (event.packageName == packageName) {
                                    eventCount++
                                    
                                    // 记录第一次和最后一次事件
                                    if (firstEventTime == null || event.timeStamp < firstEventTime) {
                                        firstEventTime = event.timeStamp
                                    }
                                    if (lastEventTime == null || event.timeStamp > lastEventTime) {
                                        lastEventTime = event.timeStamp
                                    }
                                    
                                    // 记录使用日期
                                    usedDates.add(dateFormat.format(Date(event.timeStamp)))
                                    
                                    // 计算前台时长
                                    when (event.eventType) {
                                        1 -> { // ACTIVITY_RESUMED
                                            lastResumeTime = event.timeStamp
                                        }
                                        2 -> { // ACTIVITY_PAUSED
                                            if (lastResumeTime != null) {
                                                totalForegroundTime += (event.timeStamp - lastResumeTime)
                                                lastResumeTime = null
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // 如果应用当前仍在前台，计算到现在的时间
                            if (lastResumeTime != null) {
                                totalForegroundTime += (endTime - lastResumeTime)
                            }
                            
                            Log.d(TAG, "找到 $eventCount 个事件，使用天数: ${usedDates.size}")
                            
                            if (eventCount > 0) {
                                fullInfo["eventCount"] = eventCount
                                fullInfo["firstEventTime"] = firstEventTime
                                fullInfo["lastEventTime"] = lastEventTime
                                fullInfo["totalForegroundTime"] = totalForegroundTime
                                fullInfo["usedDaysCount"] = usedDates.size
                                
                                result.success(fullInfo)
                            } else {
                                Log.d(TAG, "未找到使用记录")
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error getting full app info: ${e.message}")
                            e.printStackTrace()
                            result.error("QUERY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name required", null)
                    }
                }
                "queryUsageEvents" -> {
                    val packageName = call.argument<String>("packageName")
                    val year = call.argument<Int>("year")
                    val month = call.argument<Int>("month")
                    val day = call.argument<Int>("day")
                    
                    if (packageName != null && year != null && month != null && day != null) {
                        try {
                            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                            
                            // 设置查询时间范围（当天）
                            val calendar = Calendar.getInstance()
                            calendar.set(year, month - 1, day, 0, 0, 0)
                            calendar.set(Calendar.MILLISECOND, 0)
                            val startTime = calendar.timeInMillis
                            
                            calendar.set(year, month - 1, day, 23, 59, 59)
                            calendar.set(Calendar.MILLISECOND, 999)
                            val endTime = calendar.timeInMillis
                            
                            val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                            Log.d(TAG, "查询UsageEvents: $year-$month-$day")
                            Log.d(TAG, "  startTime: ${dateFormat.format(Date(startTime))}")
                            Log.d(TAG, "  endTime: ${dateFormat.format(Date(endTime))}")
                            
                            // 使用 queryEvents 获取详细事件
                            val events = usageStatsManager.queryEvents(startTime, endTime)
                            val eventsList = mutableListOf<Map<String, Any?>>()
                            
                            var count = 0
                            while (events.hasNextEvent()) {
                                val event = android.app.usage.UsageEvents.Event()
                                events.getNextEvent(event)
                                
                                // 只保存目标应用的事件
                                if (event.packageName == packageName) {
                                    val eventMap = mutableMapOf<String, Any?>()
                                    eventMap["packageName"] = event.packageName
                                    eventMap["timeStamp"] = event.timeStamp
                                    eventMap["eventType"] = event.eventType
                                    eventMap["eventTypeName"] = getEventTypeName(event.eventType)
                                    
                                    // 如果有类名
                                    if (event.className != null) {
                                        eventMap["className"] = event.className
                                    }
                                    
                                    eventsList.add(eventMap)
                                    count++
                                    
                                    Log.d(TAG, "Event #$count: ${dateFormat.format(Date(event.timeStamp))} - ${getEventTypeName(event.eventType)}")
                                }
                            }
                            
                            Log.d(TAG, "找到 $count 个事件")
                            
                            val resultMap = mapOf(
                                "packageName" to packageName,
                                "eventCount" to count,
                                "events" to eventsList
                            )
                            
                            result.success(resultMap)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error querying usage events: ${e.message}")
                            e.printStackTrace()
                            result.error("QUERY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "packageName, year, month, day required", null)
                    }
                }
                "queryDateRange" -> {
                    val packageName = call.argument<String>("packageName")
                    val startYear = call.argument<Int>("startYear")
                    val startMonth = call.argument<Int>("startMonth")
                    val startDay = call.argument<Int>("startDay")
                    val endYear = call.argument<Int>("endYear")
                    val endMonth = call.argument<Int>("endMonth")
                    val endDay = call.argument<Int>("endDay")
                    
                    if (packageName != null && startYear != null && startMonth != null && startDay != null
                        && endYear != null && endMonth != null && endDay != null) {
                        try {
                            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                            
                            // 设置开始时间
                            val startCalendar = Calendar.getInstance()
                            startCalendar.set(startYear, startMonth - 1, startDay, 0, 0, 0)
                            startCalendar.set(Calendar.MILLISECOND, 0)
                            val startTime = startCalendar.timeInMillis
                            
                            // 设置结束时间
                            val endCalendar = Calendar.getInstance()
                            endCalendar.set(endYear, endMonth - 1, endDay, 23, 59, 59)
                            endCalendar.set(Calendar.MILLISECOND, 999)
                            val endTime = endCalendar.timeInMillis
                            
                            val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
                            Log.d(TAG, "查询日期范围: $packageName")
                            Log.d(TAG, "  从: ${dateFormat.format(Date(startTime))}")
                            Log.d(TAG, "  到: ${dateFormat.format(Date(endTime))}")
                            
                            // 使用 queryEvents 获取详细事件
                            val events = usageStatsManager.queryEvents(startTime, endTime)
                            val eventsList = mutableListOf<Map<String, Any?>>()
                            
                            var count = 0
                            while (events.hasNextEvent()) {
                                val event = android.app.usage.UsageEvents.Event()
                                events.getNextEvent(event)
                                
                                // 只保存目标应用的事件
                                if (event.packageName == packageName) {
                                    val eventMap = mutableMapOf<String, Any?>()
                                    eventMap["packageName"] = event.packageName
                                    eventMap["timeStamp"] = event.timeStamp
                                    eventMap["eventType"] = event.eventType
                                    eventMap["eventTypeName"] = getEventTypeName(event.eventType)
                                    
                                    // 如果有类名
                                    if (event.className != null) {
                                        eventMap["className"] = event.className
                                    }
                                    
                                    eventsList.add(eventMap)
                                    count++
                                }
                            }
                            
                            Log.d(TAG, "找到 $count 个事件")
                            
                            val resultMap = mapOf(
                                "packageName" to packageName,
                                "startDate" to dateFormat.format(Date(startTime)),
                                "endDate" to dateFormat.format(Date(endTime)),
                                "eventCount" to count,
                                "events" to eventsList
                            )
                            
                            result.success(resultMap)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error querying date range: ${e.message}")
                            e.printStackTrace()
                            result.error("QUERY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "packageName, startYear, startMonth, startDay, endYear, endMonth, endDay required", null)
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
        
        // 应用信息 Channel
        MethodChannel(messenger, "com.easyfile/app_info").setMethodCallHandler { call, result ->
            when (call.method) {
                "getPackageInstallTime" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        try {
                            val packageInfo = packageManager.getPackageInfo(packageName, 0)
                            val resultMap = mapOf(
                                "firstInstallTime" to packageInfo.firstInstallTime,
                                "lastUpdateTime" to packageInfo.lastUpdateTime
                            )
                            result.success(resultMap)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "packageName required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 文件统计信息 Channel（获取文件创建时间等）
        MethodChannel(messenger, FILE_STATS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFileCreationTime" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val file = java.io.File(filePath)
                            if (file.exists()) {
                                // Android中，我们使用lastModified作为创建时间的近似值
                                // 对于新创建且从未修改的文件，lastModified就是创建时间
                                val creationTime = file.lastModified()
                                result.success(creationTime)
                            } else {
                                result.error("FILE_NOT_FOUND", "File does not exist", null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath required", null)
                    }
                }
                "getFilesCreationTimes" -> {
                    val filePaths = call.argument<List<String>>("filePaths")
                    if (filePaths != null) {
                        try {
                            val times = mutableMapOf<String, Long?>()
                            for (path in filePaths) {
                                val file = java.io.File(path)
                                times[path] = if (file.exists()) file.lastModified() else null
                            }
                            result.success(times)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "filePaths required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // MediaStore 统一扫描 Channel
        MethodChannel(messenger, MEDIASTORE_SCANNER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scan" -> {
                    lifecycleScope.launch(Dispatchers.IO) {
                        try {
                            val typeStr = call.argument<String>("type") ?: ""
                            val mediaType = when (typeStr) {
                                "image" -> MediaType.Image
                                "audio" -> MediaType.Audio
                                "video" -> MediaType.Video
                                "document" -> MediaType.Document
                                "apk" -> MediaType.Apk
                                "archive" -> MediaType.Archive
                                "cameraImage" -> MediaType.CameraImage
                                "cameraVideo" -> MediaType.CameraVideo
                                "recording" -> MediaType.Recording
                                else -> {
                                    withContext(Dispatchers.Main) {
                                        result.error("INVALID_TYPE", "Unknown media type: $typeStr", null)
                                    }
                                    return@launch
                                }
                            }
                            
                            val files = mediaStoreScanner.scan(mediaType)
                            withContext(Dispatchers.Main) {
                                result.success(files)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error scanning with MediaStore: ${e.message}")
                            withContext(Dispatchers.Main) {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "getScanStats" -> {
                    lifecycleScope.launch(Dispatchers.IO) {
                        try {
                            val typeStr = call.argument<String>("type") ?: ""
                            val mediaType = when (typeStr) {
                                "image" -> MediaType.Image
                                "audio" -> MediaType.Audio
                                "video" -> MediaType.Video
                                "document" -> MediaType.Document
                                "apk" -> MediaType.Apk
                                "archive" -> MediaType.Archive
                                "cameraImage" -> MediaType.CameraImage
                                "cameraVideo" -> MediaType.CameraVideo
                                "recording" -> MediaType.Recording
                                else -> {
                                    withContext(Dispatchers.Main) {
                                        result.error("INVALID_TYPE", "Unknown media type: $typeStr", null)
                                    }
                                    return@launch
                                }
                            }
                            
                            val stats = mediaStoreScanner.getStats(mediaType)
                            withContext(Dispatchers.Main) {
                                result.success(stats)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error getting MediaStore scan stats: ${e.message}")
                            withContext(Dispatchers.Main) {
                                result.error("STATS_ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 应用文件扫描测试 Channel
        MethodChannel(messenger, APP_FILE_SCANNER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanByOwnerPackage" -> {
                    try {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val files = appFileScanner.scanByOwnerPackage(packageName)
                        result.success(files)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error scanning by owner package: ${e.message}")
                        result.error("SCAN_ERROR", e.message, null)
                    }
                }
                "isOwnerPackageSupported" -> {
                    try {
                        val supported = appFileScanner.isOwnerPackageSupported()
                        result.success(supported)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error checking owner package support: ${e.message}")
                        result.error("CHECK_ERROR", e.message, null)
                    }
                }
                "getKnownAppPaths" -> {
                    try {
                        val appKey = call.argument<String>("appKey") ?: ""
                        val paths = appFileScanner.getKnownAppPaths(appKey)
                        result.success(paths)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting known app paths: ${e.message}")
                        result.error("PATH_ERROR", e.message, null)
                    }
                }
                "scanByFileNamePattern" -> {
                    try {
                        val patterns = call.argument<List<String>>("patterns") ?: emptyList()
                        val files = appFileScanner.scanByFileNamePattern(patterns)
                        result.success(files)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error scanning by file name pattern: ${e.message}")
                        result.error("SCAN_ERROR", e.message, null)
                    }
                }
                "getAppFileNamePatterns" -> {
                    try {
                        val appKey = call.argument<String>("appKey") ?: ""
                        val patterns = appFileScanner.getAppFileNamePatterns(appKey)
                        result.success(patterns)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting app file name patterns: ${e.message}")
                        result.error("PATTERN_ERROR", e.message, null)
                    }
                }
                "findFoldersContaining" -> {
                    try {
                        val basePaths = call.argument<List<String>>("basePaths") ?: emptyList()
                        val keyword = call.argument<String>("keyword") ?: ""
                        val folders = appFileScanner.findFoldersContaining(basePaths, keyword)
                        result.success(folders)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error finding folders: ${e.message}")
                        result.error("FIND_ERROR", e.message, null)
                    }
                }
                "isAppInstalled" -> {
                    try {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val isInstalled = appFileScanner.isAppInstalled(packageName)
                        result.success(isInstalled)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error checking app installation: ${e.message}")
                        result.error("CHECK_ERROR", e.message, null)
                    }
                }
                "getAppIcon" -> {
                    try {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val iconBytes = appFileScanner.getAppIcon(packageName)
                        result.success(iconBytes)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting app icon: ${e.message}")
                        result.error("ICON_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 本机相机照片测试 Channel
        MethodChannel(messenger, NATIVE_CAMERA_TEST_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    try {
                        val deviceInfo = mapOf(
                            "make" to android.os.Build.MANUFACTURER,
                            "model" to android.os.Build.MODEL
                        )
                        result.success(deviceInfo)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting device info: ${e.message}")
                        result.error("DEVICE_INFO_ERROR", e.message, null)
                    }
                }
                "scanNativeCameraPhotos" -> {
                    lifecycleScope.launch(Dispatchers.IO) {
                        try {
                            val photos = scanNativeCameraPhotos()
                            withContext(Dispatchers.Main) {
                                result.success(photos)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error scanning native camera photos: ${e.message}")
                            withContext(Dispatchers.Main) {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "scanCameraPackagePhotos" -> {
                    lifecycleScope.launch(Dispatchers.IO) {
                        try {
                            val photos = scanCameraPackagePhotos()
                            withContext(Dispatchers.Main) {
                                result.success(photos)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error scanning camera package photos: ${e.message}")
                            withContext(Dispatchers.Main) {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "scanCameraPackageVideos" -> {
                    lifecycleScope.launch(Dispatchers.IO) {
                        try {
                            val videos = scanCameraPackageVideos()
                            withContext(Dispatchers.Main) {
                                result.success(videos)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error scanning camera package videos: ${e.message}")
                            withContext(Dispatchers.Main) {
                                result.error("SCAN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // 应用安装/卸载事件通道
        EventChannel(messenger, APP_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.i(TAG, "应用事件监听已启动")
                    appEventSink = events
                }
                
                override fun onCancel(arguments: Any?) {
                    Log.i(TAG, "应用事件监听已取消")
                    appEventSink = null
                }
            }
        )
    }
    
    /**
     * 注册应用安装/卸载广播接收器
     */
    private fun registerPackageChangeReceiver() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addDataScheme("package")
        }
        registerReceiver(packageChangeReceiver, filter)
        Log.i(TAG, "应用安装/卸载监听器已注册")
    }
    
    override fun onDestroy() {
        // 注销广播接收器
        try {
            unregisterReceiver(packageChangeReceiver)
            Log.i(TAG, "应用安装/卸载监听器已注销")
        } catch (e: Exception) {
            Log.e(TAG, "注销监听器失败: ${e.message}")
        }
        super.onDestroy()
    }
    
    /**
     * 扫描并分析本机相机拍摄的照片
     * 通过读取 EXIF 信息判断是否为本机拍摄
     */
    private fun scanNativeCameraPhotos(): List<Map<String, Any>> {
        Log.i(TAG, "开始扫描设备所有图片...")
        
        val deviceMake = android.os.Build.MANUFACTURER
        val deviceModel = android.os.Build.MODEL
        
        Log.i(TAG, "设备信息: $deviceMake $deviceModel")
        
        val results = mutableListOf<Map<String, Any>>()
        
        // 扫描所有图片（不加过滤）
        val allPhotos = mediaStoreScanner.scan(MediaType.Image)
        
        Log.i(TAG, "找到 ${allPhotos.size} 张图片，开始分析 EXIF...")
        
        for (photo in allPhotos) {
            try {
                val path = photo["path"] as? String ?: continue
                val name = photo["name"] as? String ?: ""
                val size = (photo["size"] as? Number)?.toLong() ?: 0L
                val bucket = photo["bucket"] as? String ?: ""
                
                // 读取 EXIF 信息
                val exif = ExifInterface(path)
                val make = exif.getAttribute(ExifInterface.TAG_MAKE)
                val model = exif.getAttribute(ExifInterface.TAG_MODEL)
                val date = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                
                // 判断是否为本机拍摄
                val isNative = isNativePhoto(make, model, deviceMake, deviceModel)
                
                results.add(mapOf(
                    "path" to path,
                    "name" to name,
                    "size" to size,
                    "bucket" to bucket,
                    "make" to (make ?: ""),
                    "model" to (model ?: ""),
                    "date" to (date ?: ""),
                    "isNative" to isNative
                ))
            } catch (e: Exception) {
                Log.w(TAG, "读取 EXIF 失败: ${photo["path"]}, ${e.message}")
            }
        }
        
        val nativeCount = results.count { it["isNative"] as Boolean }
        Log.i(TAG, "扫描完成: 总数 ${results.size}, 本机拍摄 $nativeCount")
        
        return results
    }
    
    /**
     * 判断照片是否为本机拍摄
     * 通过比较 EXIF 中的品牌和型号与设备信息
     */
    private fun isNativePhoto(
        exifMake: String?,
        exifModel: String?,
        deviceMake: String,
        deviceModel: String
    ): Boolean {
        if (exifMake == null || exifModel == null) {
            return false
        }
        
        // 品牌匹配（不区分大小写）
        val makeMatches = exifMake.equals(deviceMake, ignoreCase = true)
        
        // 型号匹配（不区分大小写，支持部分匹配）
        val modelMatches = exifModel.equals(deviceModel, ignoreCase = true) ||
                          exifModel.contains(deviceModel, ignoreCase = true) ||
                          deviceModel.contains(exifModel, ignoreCase = true)
        
        return makeMatches && modelMatches
    }
    
    /**
     * 通过系统相机包名扫描照片
     * 使用 OWNER_PACKAGE_NAME 字段过滤系统相机创建的图片
     */
    private fun scanCameraPackagePhotos(): List<Map<String, Any>> {
        Log.i(TAG, "开始扫描系统相机包名创建的图片...")
        
        // 获取系统相机包名
        val cameraPackageName = getCameraPackageName()
        Log.i(TAG, "系统相机包名: $cameraPackageName")
        
        if (cameraPackageName.isEmpty()) {
            Log.w(TAG, "无法获取系统相机包名")
            return emptyList()
        }
        
        val results = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            "owner_package_name"  // OWNER_PACKAGE_NAME
        )
        
        // 过滤条件：OWNER_PACKAGE_NAME = 系统相机包名
        val selection = "owner_package_name = ?"
        val selectionArgs = arrayOf(cameraPackageName)
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
        
        try {
            contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
                val pathColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
                val dateAddedColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
                val dateTakenColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
                val bucketColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
                val widthColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
                val heightColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
                
                Log.i(TAG, "找到 ${cursor.count} 张系统相机照片")
                
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idColumn)
                    val name = cursor.getString(nameColumn) ?: ""
                    val path = cursor.getString(pathColumn) ?: ""
                    val size = cursor.getLong(sizeColumn)
                    val dateAdded = cursor.getLong(dateAddedColumn)
                    val dateTaken = cursor.getLong(dateTakenColumn)
                    val bucket = cursor.getString(bucketColumn) ?: ""
                    val width = cursor.getInt(widthColumn)
                    val height = cursor.getInt(heightColumn)
                    
                    results.add(mapOf(
                        "id" to id,
                        "name" to name,
                        "path" to path,
                        "size" to size,
                        "dateAdded" to dateAdded,
                        "dateTaken" to dateTaken,
                        "bucket" to bucket,
                        "width" to width,
                        "height" to height,
                        "ownerPackage" to cameraPackageName
                    ))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "扫描系统相机照片失败: ${e.message}", e)
        }
        
        Log.i(TAG, "扫描完成: ${results.size} 张系统相机照片")
        return results
    }
    
    /**
     * 获取系统相机应用的包名
     */
    private fun getCameraPackageName(): String {
        return try {
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
            val resolveInfo = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
            resolveInfo?.activityInfo?.packageName ?: ""
        } catch (e: Exception) {
            Log.e(TAG, "获取相机包名失败: ${e.message}")
            ""
        }
    }
    
    /**
     * 通过系统相机包名扫描视频
     * 使用 OWNER_PACKAGE_NAME 字段过滤系统相机创建的视频
     */
    private fun scanCameraPackageVideos(): List<Map<String, Any>> {
        Log.i(TAG, "开始扫描系统相机包名创建的视频...")
        
        // 获取系统相机包名
        val cameraPackageName = getCameraPackageName()
        Log.i(TAG, "系统相机包名: $cameraPackageName")
        
        if (cameraPackageName.isEmpty()) {
            Log.w(TAG, "无法获取系统相机包名")
            return emptyList()
        }
        
        val results = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATE_ADDED,
            MediaStore.Video.Media.DATE_TAKEN,
            MediaStore.Video.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.DURATION,
            "owner_package_name"  // OWNER_PACKAGE_NAME
        )
        
        // 过滤条件：OWNER_PACKAGE_NAME = 系统相机包名
        val selection = "owner_package_name = ?"
        val selectionArgs = arrayOf(cameraPackageName)
        val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC"
        
        try {
            contentResolver.query(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val pathColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                val dateAddedColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
                val dateTakenColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_TAKEN)
                val bucketColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
                val widthColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.WIDTH)
                val heightColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.HEIGHT)
                val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                
                Log.i(TAG, "找到 ${cursor.count} 个系统相机视频")
                
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idColumn)
                    val name = cursor.getString(nameColumn) ?: ""
                    val path = cursor.getString(pathColumn) ?: ""
                    val size = cursor.getLong(sizeColumn)
                    val dateAdded = cursor.getLong(dateAddedColumn)
                    val dateTaken = cursor.getLong(dateTakenColumn)
                    val bucket = cursor.getString(bucketColumn) ?: ""
                    val width = cursor.getInt(widthColumn)
                    val height = cursor.getInt(heightColumn)
                    val duration = cursor.getLong(durationColumn)
                    
                    results.add(mapOf(
                        "id" to id,
                        "name" to name,
                        "path" to path,
                        "size" to size,
                        "dateAdded" to dateAdded,
                        "dateTaken" to dateTaken,
                        "bucket" to bucket,
                        "width" to width,
                        "height" to height,
                        "duration" to duration,
                        "ownerPackage" to cameraPackageName
                    ))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "扫描系统相机视频失败: ${e.message}", e)
        }
        
        Log.i(TAG, "扫描完成: ${results.size} 个系统相机视频")
        return results
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
    
    /**
     * 获取事件类型的名称
     */
    private fun getEventTypeName(eventType: Int): String {
        return when (eventType) {
            1 -> "ACTIVITY_RESUMED"      // 应用进入前台
            2 -> "ACTIVITY_PAUSED"       // 应用离开前台
            5 -> "CONFIGURATION_CHANGE"  // 配置改变
            7 -> "USER_INTERACTION"      // 用户交互
            8 -> "SHORTCUT_INVOCATION"   // 快捷方式调用
            15 -> "SCREEN_INTERACTIVE"   // 屏幕交互
            16 -> "SCREEN_NON_INTERACTIVE" // 屏幕非交互
            18 -> "KEYGUARD_SHOWN"       // 锁屏显示
            19 -> "KEYGUARD_HIDDEN"      // 锁屏隐藏
            23 -> "FOREGROUND_SERVICE_START" // 前台服务开始
            24 -> "FOREGROUND_SERVICE_STOP"  // 前台服务停止
            26 -> "ACTIVITY_STOPPED"     // Activity停止
            else -> "UNKNOWN($eventType)"
        }
    }
}
