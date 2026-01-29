package com.guangqi.easyfile.analytics

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.guangqi.easyfile.BuildConfig
import com.umeng.commonsdk.UMConfigure
import com.umeng.analytics.MobclickAgent

/**
 * 友盟统计 MethodChannel 实现
 *
 * 负责桥接 Flutter 层与友盟原生 SDK
 * Channel: easyfile/analytics/umeng
 *
 * 配置说明：
 * - AppKey 和 Channel 从 BuildConfig 读取（由 build.gradle.kts 注入）
 * - 配置文件位置：config/analytics_config.yaml 和 config/.env.analytics
 *
 * 支持的方法：
 * - preInit: 预初始化友盟 SDK（合规步骤1）
 * - grantPrivacy: 授权隐私政策（合规步骤2）
 * - init: 初始化友盟 SDK（合规步骤3）
 * - logEvent: 记录自定义事件
 */
class UmengAnalyticsChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "UmengAnalyticsChannel"
        private const val CHANNEL_NAME = "easyfile/analytics/umeng"
    }

    // 从 BuildConfig 读取配置（由 Gradle 注入）
    private val appKey = BuildConfig.UMENG_APP_KEY
    private val channel = BuildConfig.UMENG_CHANNEL
    private val analyticsEnabled = BuildConfig.ANALYTICS_ENABLED

    private var isInitialized = false
    private var privacyGranted = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "preInit" -> {
                handlePreInit(result)
            }
            "init" -> {
                handleInit(result)
            }
            "grantPrivacy" -> {
                handleGrantPrivacy(result)
            }
            "logEvent" -> {
                val event = call.argument<String>("event")
                val params = call.argument<Map<String, Any>>("params")
                handleLogEvent(event, params, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * 合规步骤1: 预初始化（应用启动时立即调用，无需用户同意）
     */
    private fun handlePreInit(result: MethodChannel.Result) {
        try {
            // 检查全局开关
            if (!analyticsEnabled) {
                Log.i(TAG, "Analytics globally disabled in config")
                result.success(false)
                return
            }

            // 检查 AppKey 是否配置
            if (appKey.isEmpty() || appKey == "YOUR_UMENG_ANDROID_KEY_HERE") {
                Log.w(TAG, "Umeng AppKey not configured. Please set UMENG_ANDROID_KEY in config/.env.analytics")
                result.success(false)
                return
            }

            // ===== 合规步骤1: preInit 预初始化 =====
            UMConfigure.preInit(context, appKey, channel)
            Log.d(TAG, "Umeng preInit completed with AppKey: ${appKey.take(8)}*** Channel: $channel")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to preInit Umeng: ${e.message}", e)
            result.error("PREINIT_ERROR", "Failed to preInit Umeng: ${e.message}", null)
        }
    }

    /**
     * 合规步骤3: 正式初始化（必须在用户同意隐私政策后调用）
     */
    private fun handleInit(result: MethodChannel.Result) {
        try {
            if (isInitialized) {
                Log.i(TAG, "Umeng already initialized")
                result.success(true)
                return
            }

            // 检查全局开关
            if (!analyticsEnabled) {
                Log.i(TAG, "Analytics globally disabled in config")
                result.success(false)
                return
            }

            // 检查 AppKey 是否配置
            if (appKey.isEmpty() || appKey == "YOUR_UMENG_ANDROID_KEY_HERE") {
                Log.w(TAG, "Umeng AppKey not configured. Please set UMENG_ANDROID_KEY in config/.env.analytics")
                result.success(false)
                return
            }

            // 必须先授权隐私政策
            if (!privacyGranted) {
                Log.w(TAG, "Please call grantPrivacy before init")
                result.error("PRIVACY_NOT_GRANTED", "Please grant privacy consent before initialization", null)
                return
            }

            // ===== 合规步骤3: 正式初始化 =====
            UMConfigure.init(context, appKey, channel, UMConfigure.DEVICE_TYPE_PHONE, null)
            UMConfigure.setLogEnabled(BuildConfig.DEBUG)
            MobclickAgent.setPageCollectionMode(MobclickAgent.PageMode.AUTO)

            isInitialized = true
            Log.i(TAG, "Umeng initialized successfully with AppKey: ${appKey.take(8)}*** Channel: $channel")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize Umeng: ${e.message}", e)
            result.error("INIT_ERROR", "Failed to initialize Umeng: ${e.message}", null)
        }
    }

    /**
     * 合规步骤2: 隐私授权（在用户同意隐私政策后调用）
     */
    private fun handleGrantPrivacy(result: MethodChannel.Result) {
        try {
            // ===== 合规步骤2: 提交隐私政策授权结果 =====
            UMConfigure.submitPolicyGrantResult(context, true)
            privacyGranted = true
            Log.i(TAG, "Privacy policy granted by user")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to grant privacy: ${e.message}", e)
            result.error("GRANT_ERROR", "Failed to grant privacy: ${e.message}", null)
        }
    }

    private fun handleLogEvent(event: String?, params: Map<String, Any>?, result: MethodChannel.Result) {
        if (event == null) {
            result.error("INVALID_ARGUMENT", "Event name cannot be null", null)
            return
        }

        // 检查隐私授权
        if (!privacyGranted) {
            Log.w(TAG, "Privacy not granted, skipping event: $event")
            result.success(true)
            return
        }

        try {
            // 如果没有参数则使用无参上报，避免友盟 SDK 对空 map 的校验错误
            if (params == null || params.isEmpty()) {
                MobclickAgent.onEvent(context, event)
                Log.d(TAG, "Logged event: $event with no params")
            } else {
                // 转换参数为友盟格式（保持原始类型）
                val umengParams = mutableMapOf<String, Any>()
                params.forEach { (key, value) ->
                    umengParams[key] = value ?: ""
                }

                // 调用友盟事件上报（带参数）
                MobclickAgent.onEventObject(context, event, umengParams)
                Log.d(TAG, "Logged event: $event with params: $umengParams")
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to log event: ${e.message}", e)
            result.error("LOG_ERROR", "Failed to log event: ${e.message}", null)
        }
    }
}
