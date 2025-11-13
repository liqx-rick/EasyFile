package com.example.easyfile

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.easyfile/share"
    private val STATE_CHANNEL = "com.example.easyfile/state"
    private val TAG = "MainActivity"
    
    private var isRestoringFromBackground = false

    companion object {
        private var isFirstActivityCreate = true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // 检查是否是从后台恢复
        isRestoringFromBackground = savedInstanceState != null || 
                                   (intent?.flags?.and(Intent.FLAG_ACTIVITY_BROUGHT_TO_FRONT) != 0)
        
        Log.i(TAG, "onCreate - isRestoring: $isRestoringFromBackground, isFirst: $isFirstActivityCreate")
        
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
    }
}
