package com.guangqi.easyfile.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * 应用包变化广播接收器
 *
 * 监听应用的安装、卸载、替换事件，实时通知Flutter层更新APK列表
 */
class PackageChangeReceiver(private val methodChannel: MethodChannel) : BroadcastReceiver() {

    companion object {
        private const val TAG = "PackageChangeReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val packageName = intent.data?.schemeSpecificPart ?: return

        val action = when (intent.action) {
            Intent.ACTION_PACKAGE_ADDED -> {
                val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                if (replacing) {
                    "replaced" // 应用被替换（更新）
                } else {
                    "added" // 新安装
                }
            }
            Intent.ACTION_PACKAGE_REMOVED -> {
                val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                if (replacing) {
                    return // 替换过程中的临时卸载，忽略
                } else {
                    "removed" // 卸载
                }
            }
            Intent.ACTION_PACKAGE_REPLACED -> "replaced" // 应用替换完成
            else -> return
        }

        Log.i(TAG, "应用包变化: $packageName ($action)")

        // 通知Flutter层
        methodChannel.invokeMethod("onPackageChanged", mapOf(
            "packageName" to packageName,
            "action" to action
        ))
    }
}
