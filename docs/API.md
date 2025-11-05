# EasyFile API 文档

## 概述

本文档描述了 EasyFile 应用的核心 API 和组件接口。

## 数据模型

### FileItem

文件和文件夹的数据模型。

```dart
class FileItem {
  final String name;          // 文件/文件夹名称
  final String path;          // 完整路径
  final bool isDirectory;     // 是否为文件夹
  final int size;            // 文件大小（字节）
  final DateTime lastModified; // 最后修改时间
  final String extension;     // 文件扩展名
  final FileType type;       // 文件类型枚举
}
```

#### 属性说明
- `name`: 不包含路径的文件名
- `path`: 文件的完整绝对路径
- `isDirectory`: 用于区分文件夹和文件
- `size`: 文件大小，文件夹为0
- `lastModified`: 文件的最后修改时间
- `extension`: 文件扩展名（不含点号）
- `type`: 根据扩展名确定的文件类型

### FileType

文件类型枚举。

```dart
enum FileType {
  image,      // 图片文件 (jpg, png, gif, bmp, webp)
  text,       // 文本文件 (txt, json, xml, html, dart, py, js, css)
  video,      // 视频文件 (mp4, avi, mkv, mov)
  audio,      // 音频文件 (mp3, wav, aac, flac)
  document,   // 文档文件 (pdf, doc, docx, xls, xlsx, ppt, pptx)
  archive,    // 压缩文件 (zip, rar, 7z, tar)
  executable, // 可执行文件 (exe, apk, deb, dmg)
  other       // 其他文件类型
}
```

## 核心接口

### FileRepository

文件操作的核心接口。

```dart
abstract class FileRepository {
  /// 获取指定目录下的文件列表
  Future<List<FileItem>> getFiles(String path);
  
  /// 搜索文件
  Future<List<FileItem>> searchFiles(String path, String query, {int maxDepth = 3});
  
  /// 复制文件或文件夹
  Future<bool> copyFile(String sourcePath, String destinationPath);
  
  /// 移动文件或文件夹
  Future<bool> moveFile(String sourcePath, String destinationPath);
  
  /// 重命名文件或文件夹
  Future<bool> renameFile(String oldPath, String newName);
  
  /// 删除文件或文件夹
  Future<bool> deleteFile(String path);
  
  /// 检查路径是否存在
  Future<bool> exists(String path);
  
  /// 获取可用存储空间
  Future<int> getAvailableSpace(String path);
  
  /// 获取文件或文件夹大小
  Future<int> getFileSize(String path);
}
```

#### 方法详解

##### getFiles(String path)
获取指定目录下的文件和文件夹列表。

**参数**:
- `path`: 目录路径

**返回值**: `Future<List<FileItem>>` - 文件列表

**异常**: 
- `FileSystemException` - 路径不存在或权限不足

##### searchFiles(String path, String query, {int maxDepth = 3})
在指定目录及其子目录中搜索文件。

**参数**:
- `path`: 搜索的根目录
- `query`: 搜索关键词
- `maxDepth`: 最大搜索深度

**返回值**: `Future<List<FileItem>>` - 匹配的文件列表

##### copyFile(String sourcePath, String destinationPath)
复制文件或文件夹到目标位置。

**参数**:
- `sourcePath`: 源文件/文件夹路径
- `destinationPath`: 目标路径

**返回值**: `Future<bool>` - 操作是否成功

##### moveFile(String sourcePath, String destinationPath)
移动文件或文件夹到目标位置。

**参数**:
- `sourcePath`: 源文件/文件夹路径
- `destinationPath`: 目标路径

**返回值**: `Future<bool>` - 操作是否成功

**说明**: 如果直接移动失败，会尝试复制后删除源文件

##### renameFile(String oldPath, String newName)
重命名文件或文件夹。

**参数**:
- `oldPath`: 原文件路径
- `newName`: 新文件名（不包含路径）

**返回值**: `Future<bool>` - 操作是否成功

##### deleteFile(String path)
删除文件或文件夹。

**参数**:
- `path`: 要删除的文件/文件夹路径

**返回值**: `Future<bool>` - 操作是否成功

**说明**: 支持递归删除文件夹

## Presenter 层

### FilePresenter

业务逻辑处理类，连接UI和数据层。

```dart
class FilePresenter {
  final FileRepository _repository;
  final FileViewModel _viewModel;
  
  /// 加载文件列表
  Future<void> loadFiles(String path);
  
  /// 搜索文件
  Future<void> searchFiles(String query);
  
  /// 复制文件操作
  Future<void> copyFile(FileItem file, String destinationPath);
  
  /// 移动文件操作
  Future<void> moveFile(FileItem file, String destinationPath);
  
  /// 重命名文件操作
  Future<void> renameFile(FileItem file, String newName);
  
  /// 删除文件操作
  Future<void> deleteFile(FileItem file);
  
  /// 返回上级目录
  void navigateUp();
  
  /// 进入子目录
  void navigateToDirectory(String path);
}
```

### FileViewModel

管理UI状态的ViewModel。

```dart
class FileViewModel extends ChangeNotifier {
  List<FileItem> _files = [];
  String _currentPath = '';
  bool _isLoading = false;
  bool _isSearching = false;
  String _searchQuery = '';
  String? _errorMessage;
  
  // Getters
  List<FileItem> get files => _files;
  String get currentPath => _currentPath;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;
  String? get errorMessage => _errorMessage;
  
  // 状态更新方法
  void setFiles(List<FileItem> files);
  void setCurrentPath(String path);
  void setLoading(bool loading);
  void setSearching(bool searching);
  void setSearchQuery(String query);
  void setError(String? message);
  void clearError();
}
```

## UI 组件

### FileBrowserPage

主文件浏览页面。

```dart
class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({Key? key}) : super(key: key);
}
```

**主要功能**:
- 文件列表显示
- 搜索功能
- 导航控制
- 文件操作入口

### FilePreviewPage

文件预览页面。

```dart
class FilePreviewPage extends StatelessWidget {
  final FileItem file;
  
  const FilePreviewPage({Key? key, required this.file}) : super(key: key);
}
```

**支持预览的文件类型**:
- 图片: JPG, PNG, GIF, BMP, WebP
- 文本: TXT, JSON, XML, HTML, Dart, Python, JavaScript, CSS

### FileItemTile

文件列表项组件。

```dart
class FileItemTile extends StatelessWidget {
  final FileItem file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  
  const FileItemTile({
    Key? key,
    required this.file,
    this.onTap,
    this.onLongPress,
  }) : super(key: key);
}
```

### FileOperationSheet

文件操作底部弹出菜单。

```dart
class FileOperationSheet extends StatelessWidget {
  final FileItem file;
  final Function(FileOperation) onOperationSelected;
  
  const FileOperationSheet({
    Key? key,
    required this.file,
    required this.onOperationSelected,
  }) : super(key: key);
}
```

**操作类型**:
```dart
enum FileOperation {
  copy,    // 复制
  move,    // 移动
  rename,  // 重命名
  delete,  // 删除
}
```

### 对话框组件

#### RenameDialog
重命名文件对话框。

```dart
class RenameDialog extends StatelessWidget {
  final String currentName;
  final Function(String) onRenamed;
  
  const RenameDialog({
    Key? key,
    required this.currentName,
    required this.onRenamed,
  }) : super(key: key);
}
```

#### FolderPickerDialog
文件夹选择对话框。

```dart
class FolderPickerDialog extends StatefulWidget {
  final String initialPath;
  final Function(String) onFolderSelected;
  
  const FolderPickerDialog({
    Key? key,
    required this.initialPath,
    required this.onFolderSelected,
  }) : super(key: key);
}
```

#### ProgressDialog
操作进度对话框。

```dart
class ProgressDialog extends StatelessWidget {
  final String title;
  final String message;
  final double? progress;
  
  const ProgressDialog({
    Key? key,
    required this.title,
    required this.message,
    this.progress,
  }) : super(key: key);
}
```

## 日志系统

### Logger

应用日志管理类。

```dart
class Logger {
  static const String _fileName = 'app_log.txt';
  
  /// 日志级别
  enum Level {
    debug,   // 调试信息
    info,    // 一般信息
    warning, // 警告
    error,   // 错误
    severe,  // 严重错误
  }
  
  /// 记录日志
  static void log(Level level, String message, [String? tag]);
  
  /// 调试日志
  static void debug(String message, [String? tag]);
  
  /// 信息日志
  static void info(String message, [String? tag]);
  
  /// 警告日志
  static void warning(String message, [String? tag]);
  
  /// 错误日志
  static void error(String message, [String? tag]);
  
  /// 严重错误日志
  static void severe(String message, [String? tag]);
  
  /// 清空日志文件
  static Future<void> clearLogs();
  
  /// 获取日志文件路径
  static Future<String> getLogFilePath();
}
```

### 使用示例

```dart
// 记录文件操作
Logger.info('Starting file copy operation', 'FileRepository');

// 记录错误
Logger.error('Failed to access file: $path', 'FileRepository');

// 记录用户操作
Logger.debug('User selected file: ${file.name}', 'UI');
```

## 工具类

### PathUtils

路径处理工具类。

```dart
class PathUtils {
  /// 获取外部存储目录
  static Future<String> getExternalStorageDirectory();
  
  /// 获取下载目录
  static Future<String> getDownloadsDirectory();
  
  /// 获取文档目录
  static Future<String> getDocumentsDirectory();
  
  /// 格式化文件大小
  static String formatFileSize(int bytes);
  
  /// 格式化时间
  static String formatDateTime(DateTime dateTime);
  
  /// 获取文件类型
  static FileType getFileType(String extension);
  
  /// 获取文件类型图标
  static IconData getFileTypeIcon(FileType type);
}
```

### PermissionUtils

权限管理工具类。

```dart
class PermissionUtils {
  /// 检查存储权限
  static Future<bool> checkStoragePermission();
  
  /// 请求存储权限
  static Future<bool> requestStoragePermission();
  
  /// 检查管理外部存储权限 (Android 11+)
  static Future<bool> checkManageExternalStoragePermission();
  
  /// 请求管理外部存储权限 (Android 11+)
  static Future<bool> requestManageExternalStoragePermission();
  
  /// 打开应用设置页面
  static Future<void> openAppSettings();
}
```

## 错误处理

### 异常类型

```dart
// 文件系统异常
class FileSystemException implements Exception {
  final String message;
  final String? path;
  FileSystemException(this.message, [this.path]);
}

// 权限异常
class PermissionException implements Exception {
  final String message;
  PermissionException(this.message);
}

// 操作取消异常
class OperationCancelledException implements Exception {
  final String message;
  OperationCancelledException(this.message);
}
```

### 错误处理策略

1. **文件访问错误**: 检查权限，提示用户授予权限
2. **网络错误**: 显示重试按钮
3. **存储空间不足**: 显示空间不足提示
4. **文件不存在**: 刷新文件列表
5. **操作超时**: 提供取消操作选项

## 最佳实践

### 1. 异步操作
所有文件操作都应该是异步的，避免阻塞UI线程。

```dart
// 正确方式
Future<void> loadFiles() async {
  setLoading(true);
  try {
    final files = await _repository.getFiles(_currentPath);
    setFiles(files);
  } catch (e) {
    setError(e.toString());
  } finally {
    setLoading(false);
  }
}
```

### 2. 错误处理
总是包含适当的错误处理和用户反馈。

```dart
try {
  await _repository.copyFile(sourcePath, destPath);
  _showSuccess('文件复制成功');
} catch (e) {
  Logger.error('Copy failed: $e');
  _showError('复制失败: $e');
}
```

### 3. 权限检查
在执行文件操作前检查权限。

```dart
Future<bool> _checkPermissions() async {
  if (!await PermissionUtils.checkStoragePermission()) {
    return await PermissionUtils.requestStoragePermission();
  }
  return true;
}
```

### 4. 内存管理
对于大文件操作，注意内存使用。

```dart
// 分块读取大文件
Stream<List<int>> readFileInChunks(String path) async* {
  final file = File(path);
  final stream = file.openRead();
  await for (final chunk in stream) {
    yield chunk;
  }
}
```

### 5. 用户体验
提供适当的加载状态和进度指示。

```dart
void _showProgress(String operation, double progress) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => ProgressDialog(
      title: operation,
      message: '正在处理...',
      progress: progress,
    ),
  );
}
```

## 版本历史

### v1.0.0
- 基础文件浏览功能
- 文件搜索
- 图片和文本预览
- 文件操作（复制、移动、重命名、删除）
- 日志系统
- 权限管理

---

更多详细信息请参考源代码注释和示例。