package com.guangqi.easyfile

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

object ShareHelper {
    fun shareFile(context: Context, filePath: String, mimeType: String = "*/*") {
        val file = File(filePath)
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file
        )

        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // 关键：让目标应用在自己的任务栈中打开
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }

        val chooserIntent = Intent.createChooser(shareIntent, "分享文件").apply {
            // 让选择器在新任务栈中打开
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        context.startActivity(chooserIntent)
    }

    fun shareMultipleFiles(context: Context, filePaths: List<String>) {
        val uris = ArrayList<Uri>()

        for (filePath in filePaths) {
            val file = File(filePath)
            if (file.exists()) {
                val uri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    file
                )
                uris.add(uri)
            }
        }

        if (uris.isEmpty()) {
            return
        }

        val shareIntent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "*/*"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // 关键：让目标应用在自己的任务栈中打开
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }

        val chooserIntent = Intent.createChooser(shareIntent, "分享 ${uris.size} 个文件").apply {
            // 让选择器在新任务栈中打开
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        context.startActivity(chooserIntent)
    }
}
