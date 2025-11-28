# SAF (Storage Access Framework) 访问实现指南

## 问题背景

### 为什么 ES 文件管理器等应用能访问 Android/data？

从 Android 11 (API 30) 开始，Google 引入了 **Scoped Storage（分区存储）** 限制，即使应用拥有 `MANAGE_EXTERNAL_STORAGE` 权限，也无法直接访问以下目录：

- `/storage/emulated/0/Android/data`
- `/storage/emulated/0/Android/obb`
- `/storage/emulated/0/Android/media`

### ES 文件管理器的访问方式

老牌文件管理器（如 ES 文件管理器、Solid Explorer 等）使用以下方法：

1. **SAF API（推荐方案）**
   - 使用 `ACTION_OPEN_DOCUMENT_TREE` Intent
   - 让用户通过系统文件选择器授权访问特定目录
   - 保存授权的 URI，后续通过 DocumentFile API 访问

2. **历史权限保留**
   - Android 11 之前安装的应用可能保留旧权限模型
   - 这不是长期解决方案

3. **Root 权限**
   - 不适用于普通用户

## 实现方案：SAF 访问

### 1. 添加依赖

```yaml
# pubspec.yaml
dependencies:
  # SAF 支持
  saf: ^2.0.0  # Storage Access Framework
  # 或使用
  file_picker: ^6.0.0
```

### 2. 实现授权流程

#### 2.1 创建 SAF 服务

```dart
// lib/core/services/saf_service.dart
import 'package:flutter/services.dart';

class SafService {
  static const platform = MethodChannel('com.example.easyfile/saf');
  
  /// 请求访问 Android/data 目录
  Future<bool> requestAndroidDataAccess() async {
    try {
      final result = await platform.invokeMethod('requestTreeUri', {
        'initialPath': '/storage/emulated/0/Android/data',
      });
      return result as bool;
    } catch (e) {
      logger.e('Failed to request SAF access: $e');
      return false;
    }
  }
  
  /// 检查是否已授权访问
  Future<bool> hasAndroidDataAccess() async {
    try {
      final result = await platform.invokeMethod('hasTreeUri');
      return result as bool;
    } catch (e) {
      return false;
    }
  }
  
  /// 列出目录内容（通过 SAF）
  Future<List<FileItem>> listDirectory(String path) async {
    try {
      final result = await platform.invokeMethod('listDirectory', {
        'path': path,
      });
      // 解析结果并返回 FileItem 列表
      return _parseFileList(result);
    } catch (e) {
      logger.e('Failed to list directory via SAF: $e');
      return [];
    }
  }
}
```

#### 2.2 Android 原生实现

```kotlin
// android/app/src/main/kotlin/com/example/easyfile/MainActivity.kt
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.easyfile/saf"
    private val REQUEST_CODE_OPEN_TREE = 1001
    
    private var safResult: Result? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestTreeUri" -> {
                        safResult = result
                        requestTreeUri()
                    }
                    "hasTreeUri" -> {
                        result.success(hasPersistedUri())
                    }
                    "listDirectory" -> {
                        val path = call.argument<String>("path")
                        result.success(listDirectoryViaSaf(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }
    
    private fun requestTreeUri() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        
        // 设置初始路径（Android/data）
        val initialUri = Uri.parse("content://com.android.externalstorage.documents/tree/primary%3AAndroid%2Fdata")
        intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri)
        
        startActivityForResult(intent, REQUEST_CODE_OPEN_TREE)
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == REQUEST_CODE_OPEN_TREE) {
            if (resultCode == RESULT_OK && data != null) {
                val treeUri = data.data
                if (treeUri != null) {
                    // 持久化授权
                    contentResolver.takePersistableUriPermission(
                        treeUri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or 
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                    
                    // 保存 URI
                    saveTreeUri(treeUri.toString())
                    
                    safResult?.success(true)
                } else {
                    safResult?.success(false)
                }
            } else {
                safResult?.success(false)
            }
        }
    }
    
    private fun listDirectoryViaSaf(path: String?): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        
        val treeUri = getSavedTreeUri() ?: return results
        val documentFile = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
        
        // 遍历文件
        documentFile?.listFiles()?.forEach { file ->
            results.add(mapOf(
                "name" to (file.name ?: ""),
                "path" to (file.uri.toString()),
                "isDirectory" to file.isDirectory,
                "size" to file.length(),
                "lastModified" to file.lastModified()
            ))
        }
        
        return results
    }
    
    private fun saveTreeUri(uri: String) {
        getSharedPreferences("saf_prefs", MODE_PRIVATE)
            .edit()
            .putString("tree_uri", uri)
            .apply()
    }
    
    private fun getSavedTreeUri(): String? {
        return getSharedPreferences("saf_prefs", MODE_PRIVATE)
            .getString("tree_uri", null)
    }
    
    private fun hasPersistedUri(): Boolean {
        return getSavedTreeUri() != null
    }
}
```

### 3. 更新 UI 流程

#### 3.1 修改 LocalFileSource

```dart
// lib/data/sources/local_file_source.dart
class LocalFileRepository implements FileRepository {
  final SafService _safService = SafService();
  
  @override
  Future<List<FileItem>> getFiles(String path) async {
    // 检查是否是受保护的目录
    if (_isProtectedDirectory(path)) {
      // 检查是否有 SAF 授权
      final hasSafAccess = await _safService.hasAndroidDataAccess();
      
      if (hasSafAccess) {
        // 通过 SAF 访问
        return await _safService.listDirectory(path);
      } else {
        // 返回空列表，UI 会显示授权提示
        return [];
      }
    }
    
    // 普通目录正常访问
    // ... 现有代码 ...
  }
  
  bool _isProtectedDirectory(String path) {
    return path.contains('/Android/data') ||
           path.contains('/Android/obb') ||
           path.contains('/Android/media');
  }
}
```

#### 3.2 更新空状态 UI

```dart
// lib/ui/pages/file_browser_page.dart
actionButton = TextButton.icon(
  onPressed: () async {
    // 请求 SAF 授权
    final safService = SafService();
    final granted = await safService.requestAndroidDataAccess();
    
    if (granted) {
      // 授权成功，重新加载
      await presenter.loadFiles(viewModel.currentPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('授权成功！现在可以访问此目录'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('授权被取消或失败'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  },
  icon: const Icon(Icons.folder_special),
  label: const Text('授权访问此目录'),
  style: TextButton.styleFrom(
    foregroundColor: Colors.blue,
  ),
);
```

## 实现优先级

### 短期方案（当前版本）
- ✅ 显示友好的错误提示
- ✅ 解释为什么其他应用能访问
- ✅ 提供"返回上级"按钮

### 中期方案（下个版本）
- 🔄 实现 SAF 授权流程
- 🔄 支持通过 SAF 读取 Android/data 内容
- 🔄 支持通过 SAF 删除文件（需用户确认）

### 长期方案（未来版本）
- 📋 完整的 SAF 文件操作支持（复制、移动、重命名）
- 📋 智能缓存 SAF 访问的目录列表
- 📋 批量操作优化

## 技术限制

### SAF 的限制
1. **性能较慢**：SAF 通过系统文档提供器访问，比直接文件系统访问慢
2. **需要用户交互**：每次授权都需要用户手动选择目录
3. **URI 管理复杂**：需要维护持久化 URI 权限

### 推荐策略
- 对普通目录继续使用直接文件系统访问（快速）
- 仅对受保护目录使用 SAF（需要时）
- 缓存 SAF 访问结果以提升性能

## 参考资料

1. [Android Storage Access Framework](https://developer.android.com/guide/topics/providers/document-provider)
2. [Scoped Storage 最佳实践](https://developer.android.com/training/data-storage)
3. [DocumentFile API 文档](https://developer.android.com/reference/androidx/documentfile/provider/DocumentFile)

## 相关 Issue

- [Android 11+ 无法访问 Android/data 目录](https://github.com/liqx-rick/EasyFile/issues/XXX)
- [实现 SAF 支持请求](https://github.com/liqx-rick/EasyFile/issues/XXX)
