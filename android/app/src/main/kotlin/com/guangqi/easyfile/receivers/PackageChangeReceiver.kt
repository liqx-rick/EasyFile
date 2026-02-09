package com.guangqi.easyfile.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 应用包变化广播接收器
 *
 * 监听应用的安装、卸载、替换事件，实时通知Flutter层
 */
class PackageChangeReceiver(private val listener: PackageChangeListener) : BroadcastReceiver() {

    companion object {
        private const val TAG = "PackageChangeReceiver"
    }

    /**
     * 包变化监听器接口
     */
    interface PackageChangeListener {
        fun onPackageInstalled(packageName: String)
        fun onPackageUninstalled(packageName: String)
        fun onPackageReplaced(packageName: String)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val packageName = intent.data?.schemeSpecificPart ?: return

        when (intent.action) {
            Intent.ACTION_PACKAGE_ADDED -> {
                val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                if (!replacing) {
                    Log.i(TAG, "应用已安装: $packageName")
                    listener.onPackageInstalled(packageName)
                }
            }
            Intent.ACTION_PACKAGE_REMOVED -> {
                val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                if (!replacing) {
                    Log.i(TAG, "应用已卸载: $packageName")
                    listener.onPackageUninstalled(packageName)
                }
            }
            Intent.ACTION_PACKAGE_REPLACED -> {
                Log.i(TAG, "应用已替换: $packageName")
                listener.onPackageReplaced(packageName)
            }
        }
    }
}
