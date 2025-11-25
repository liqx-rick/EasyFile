package com.example.easyfile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File

object ShareHelper {
    private fun getMimeType(filePath: String): String {
        val extension = filePath.substringAfterLast('.', "")
        return if (extension.isNotEmpty()) {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase()) ?: "*/*"
        } else {
            "*/*"
        }
    }

    fun shareFile(context: Context, filePath: String, mimeType: String = "*/*") {
        val file = File(filePath)
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file
        )

        // 如果没有指定 mimeType，自动检测
        val actualMimeType = if (mimeType == "*/*") {
            getMimeType(filePath)
        } else {
            mimeType
        }

        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = actualMimeType
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
        var commonMimeType: String? = null
        var hasNonImage = false
        
        for (filePath in filePaths) {
            val file = File(filePath)
            if (file.exists()) {
                val uri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    file
                )
                uris.add(uri)
                
                // 检测并确定通用的 MIME 类型
                val mimeType = getMimeType(filePath)
                
                // 检查是否有非图片文件
                if (!mimeType.startsWith("image/")) {
                    hasNonImage = true
                }
                
                if (commonMimeType == null) {
                    commonMimeType = mimeType
                } else if (commonMimeType != mimeType) {
                    // 如果有不同类型的文件，使用通配符
                    val commonPrefix = getCommonMimePrefix(commonMimeType, mimeType)
                    commonMimeType = commonPrefix ?: "*/*"
                }
            }
        }

        if (uris.isEmpty()) {
            return
        }

        // 如果包含非图片文件，在分享文本中提示用户
        val shareTitle = if (hasNonImage && uris.size > 1) {
            "分享 ${uris.size} 个文件（注意：部分应用可能只支持图片）"
        } else {
            "分享 ${uris.size} 个文件"
        }

        val shareIntent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = commonMimeType ?: "*/*"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // 关键：让目标应用在自己的任务栈中打开
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }

        val chooserIntent = Intent.createChooser(shareIntent, shareTitle).apply {
            // 让选择器在新任务栈中打开
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        context.startActivity(chooserIntent)
    }
    
    private fun getCommonMimePrefix(mime1: String, mime2: String): String? {
        // 如果两个 MIME 类型有相同的主类型（如 image/*, video/*），返回通配符形式
        val prefix1 = mime1.substringBefore('/')
        val prefix2 = mime2.substringBefore('/')
        return if (prefix1 == prefix2 && prefix1 != "*") {
            "$prefix1/*"
        } else {
            null
        }
    }
}
