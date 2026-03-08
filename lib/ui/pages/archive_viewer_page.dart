import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/services/archive_preview_cache_manager.dart';
import 'package:easyfile/core/services/archive_service.dart';
import 'package:easyfile/data/models/archive_entry_info.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/password_input_dialog.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

/// 压缩包查看器页面
///
/// 显示压缩包内的文件和目录列表，不实际解压
class ArchiveViewerPage extends StatefulWidget {
  final FileItem archiveFile;
  final bool isReadOnly; // 只读模式（从文件预览进入，禁止解压等操作）

  const ArchiveViewerPage({super.key, required this.archiveFile, this.isReadOnly = false});

  @override
  State<ArchiveViewerPage> createState() => _ArchiveViewerPageState();
}

class _ArchiveViewerPageState extends State<ArchiveViewerPage> {
  final ArchiveService _archiveService = ArchiveService();
  List<ArchiveEntryInfo>? _entries;
  List<ArchiveEntryInfo>? _allEntries;
  String _currentPath = '';
  bool _isLoading = true;
  String? _errorMessage;
  bool _canOpenWithOtherApp = false;

  @override
  void initState() {
    super.initState();
    _loadArchiveContents();
  }

  Future<void> _loadArchiveContents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _archiveService.listArchiveContents(widget.archiveFile.path);

      if (result.success) {
        // 埋点：压缩包密码检测
        AnalyticsHelper.logArchivePasswordCheck(false);

        setState(() {
          _allEntries = result.entries;
          _entries = _getEntriesForCurrentPath();
          _isLoading = false;
        });
      } else {
        // 检查是否可能是密码保护的压缩包
        final errorMsg = result.errorMessage ?? '无法读取压缩包内容';
        final mayNeedPassword = _needsPassword(errorMsg);

        // 检查是否是 libarchive 不支持的加密文件
        final isUnsupportedEncryption = errorMsg.toLowerCase().contains('currently not supported');

        // 埋点：压缩包密码检测
        if (isUnsupportedEncryption || mayNeedPassword) {
          AnalyticsHelper.logArchivePasswordCheck(true);
        }

        setState(() {
          if (isUnsupportedEncryption || mayNeedPassword) {
            _errorMessage = '此压缩包可能需要密码。\n请先解压后查看内容。';
          } else {
            _errorMessage = errorMsg;
          }
          _isLoading = false;
          _canOpenWithOtherApp = result.canOpenWithOtherApp;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '无法读取压缩包内容: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _currentPath.isEmpty,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;

        // 如果在子目录中，返回上级目录
        if (_currentPath.isNotEmpty) {
          setState(() {
            if (_currentPath.contains('/')) {
              _currentPath = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
            } else {
              _currentPath = '';
            }
            _entries = _getEntriesForCurrentPath();
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _currentPath.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      // 返回上级目录
                      if (_currentPath.contains('/')) {
                        _currentPath = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
                      } else {
                        _currentPath = '';
                      }
                      _entries = _getEntriesForCurrentPath();
                    });
                  },
                ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.archiveFile.name, style: const TextStyle(fontSize: 16)),
              if (_entries != null)
                Text(
                  '${_entries!.length} 个项目${widget.isReadOnly ? ' · 只读模式' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        body: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              // 如果是编码问题，显示"用其他应用打开"按钮
              if (_canOpenWithOtherApp) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      // 使用 type 参数指定 MIME 类型，强制显示应用选择器
                      final result = await OpenFile.open(widget.archiveFile.path, type: 'application/vnd.rar');

                      // 如果返回 noAppToOpen，尝试使用通用的 zip 类型
                      if (result.type == ResultType.noAppToOpen) {
                        final result2 = await OpenFile.open(widget.archiveFile.path, type: 'application/zip');

                        // 如果还是没有应用，尝试使用通配符
                        if (result2.type == ResultType.noAppToOpen) {
                          final result3 = await OpenFile.open(widget.archiveFile.path, type: '*/*');

                          if (result3.type != ResultType.done && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到可以打开此文件的应用')));
                          }
                        } else if (result2.type != ResultType.done && mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('打开失败: ${result2.message}')));
                        }
                      } else if (result.type == ResultType.error && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打开失败: ${result.message}')));
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打开失败: $e')));
                      }
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('用其他应用打开'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_entries == null || (_entries!.isEmpty && (_allEntries == null || _allEntries!.isEmpty))) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.folder_zip_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text('无法读取压缩包内容', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface)),
              const SizedBox(height: 8),
              Text('可能的原因：', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text(
                '• 压缩包需要密码\n'
                '• 文件已损坏\n'
                '• 不支持的压缩格式版本\n'
                '• RAR 5.0 及以上版本',
                textAlign: TextAlign.left,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadArchiveContents,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    // 显示文件列表，顶部添加提示横幅
    return Column(
      children: [
        // 提示横幅
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2), width: 1)),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_zip, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '当前页面仅支持预览，如需更多操作，请先解压',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
        // 文件列表
        Expanded(child: _buildEntriesList(theme)),
      ],
    );
  }

  List<ArchiveEntryInfo> _getEntriesForCurrentPath() {
    if (_allEntries == null) {
      return [];
    }

    if (_currentPath.isEmpty) {
      // 显示根目录内容：只显示直接子项
      // 文件夹：以'/'结尾且只有1个'/' -> "dir/"
      // 文件：不包含'/' -> "file.txt"

      // 先找出所有直接的文件和目录
      final directEntries = _allEntries!.where((entry) {
        final path = entry.path;
        final slashCount = '/'.allMatches(path).length;

        if (path.endsWith('/')) {
          // 文件夹：只显示第一级
          return slashCount == 1;
        } else {
          // 文件：只显示根目录的文件
          return slashCount == 0;
        }
      }).toList();

      // 如果直接项为空，但有条目，说明所有文件都在子目录中
      // 需要提取出第一级目录
      if (directEntries.isEmpty && _allEntries!.isNotEmpty) {
        final Set<String> topLevelDirs = {};
        for (var entry in _allEntries!) {
          final path = entry.path;
          if (path.contains('/')) {
            final firstSlash = path.indexOf('/');
            final topDir = path.substring(0, firstSlash);
            topLevelDirs.add(topDir);
          }
        }

        // 为每个顶级目录创建虚拟目录条目
        return topLevelDirs.map((dirName) {
          return ArchiveEntryInfo(
            name: dirName,
            path: '$dirName/',
            size: 0,
            compressedSize: 0,
            isDirectory: true,
            modificationDate: DateTime.now(),
            compressionMethod: 0,
            crc: 0,
          );
        }).toList();
      }

      return directEntries;
    } else {
      // 显示当前路径下的内容
      final prefix = _currentPath.endsWith('/') ? _currentPath : '$_currentPath/';
      return _allEntries!.where((entry) {
        final path = entry.path;
        // 排除目录自身
        if (path == _currentPath) return false;
        // 只显示以prefix开头的项
        if (!path.startsWith(prefix)) return false;

        // 只显示直接子项
        final relativePath = path.substring(prefix.length);
        if (relativePath.isEmpty) return false;

        if (path.endsWith('/')) {
          // 文件夹：相对路径应该只有一级（如 "subdir/"）
          final slashCount = '/'.allMatches(relativePath).length;
          return slashCount == 1;
        } else {
          // 文件：相对路径不应该包含 '/'
          return !relativePath.contains('/');
        }
      }).toList();
    }
  }

  void _handleEntryTap(ArchiveEntryInfo entry) {
    if (entry.isDirectory) {
      // 进入文件夹
      setState(() {
        _currentPath = entry.path;
        _entries = _getEntriesForCurrentPath();
      });

      // 显示当前路径的导航提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('当前位置: ${_getCurrentPathDisplay()}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      // 预览文件
      _previewFile(entry);
    }
  }

  String _getCurrentPathDisplay() {
    if (_currentPath.isEmpty) {
      return widget.archiveFile.name;
    }
    // 移除末尾的 '/'
    final path = _currentPath.endsWith('/') ? _currentPath.substring(0, _currentPath.length - 1) : _currentPath;
    return '${widget.archiveFile.name}/$path';
  }

  Future<void> _previewFile(ArchiveEntryInfo entry) async {
    // 检查文件大小限制
    final maxSizeBytes = AppConfig.instance.cacheConfig.archivePreviewMaxFileSizeMB * 1024 * 1024;
    if (entry.size > maxSizeBytes) {
      if (!mounted) return;
      _showSizeExceedDialog(entry);
      return;
    }

    // 显示进度对话框（文件>1MB时）
    bool showProgress = entry.size > 1024 * 1024;
    if (showProgress && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [CircularProgressIndicator(), SizedBox(height: 16), Text('正在提取文件...')],
          ),
        ),
      );
    }

    // 提取文件到缓存，支持密码重试
    String? password;
    int attempts = 0;
    const maxAttempts = 3;
    bool needRetry = true;

    String? cachedPath;
    String? errorMessage;

    while (attempts < maxAttempts && needRetry) {
      cachedPath = await ArchivePreviewCacheManager.extractForPreview(
        archivePath: widget.archiveFile.path,
        entryPath: entry.path,
        password: password,
        onError: (msg) {
          errorMessage = msg;
        },
      );

      if (cachedPath != null) {
        // 提取成功
        needRetry = false;
        break;
      }

      // 检查是否需要密码
      if (errorMessage != null && _needsPassword(errorMessage)) {
        attempts++;

        // 显示密码输入对话框
        if (!mounted) return;
        password = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PasswordInputDialog(remainingAttempts: maxAttempts - attempts),
        );
      } else {
        // 非密码错误，直接退出
        needRetry = false;
      }
    }

    // 关闭进度对话框
    if (showProgress && mounted) {
      Navigator.of(context).pop();
    }

    if (!mounted) return;

    if (cachedPath == null) {
      // 提取失败 - 显示错误消息
      String displayError = errorMessage ?? '提取文件失败';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(displayError), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
      );
      return;
    }

    // 创建临时FileItem用于预览
    final tempFile = FileItem(
      name: entry.fileName,
      path: cachedPath,
      size: entry.size,
      modified: entry.modificationDate,
      isDirectory: false,
    );

    // 打开预览页面（只读模式）
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FilePreviewPage(file: tempFile, isReadOnly: true, archiveName: widget.archiveFile.name),
      ),
    );
  }

  void _showSizeExceedDialog(ArchiveEntryInfo entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文件过大'),
        content: Text(
          '文件大小为 ${FileSizeFormatter.formatBytes(entry.size)}，'
          '超过 ${AppConfig.instance.cacheConfig.archivePreviewMaxFileSizeMB}MB 限制。\n\n'
          '请解压整个压缩包后操作。',
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('知道了'))],
      ),
    );
  }

  Widget _buildEntriesList(ThemeData theme) {
    return ListView.builder(
      itemCount: _entries!.length,
      itemBuilder: (context, index) {
        final entry = _entries![index];
        return _buildEntryItem(entry, theme);
      },
    );
  }

  Widget _buildEntryItem(ArchiveEntryInfo entry, ThemeData theme) {
    return ListTile(
      leading: _buildEntryIcon(entry, theme),
      title: Text(entry.fileName.isEmpty ? entry.path : entry.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: _buildEntrySubtitle(entry, theme),
      trailing: entry.isDirectory
          ? const Icon(Icons.chevron_right)
          : Text(
              FileSizeFormatter.formatBytes(entry.size),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
      onTap: () => _handleEntryTap(entry),
    );
  }

  Widget _buildEntryIcon(ArchiveEntryInfo entry, ThemeData theme) {
    if (entry.isDirectory) {
      return Icon(Icons.folder, color: theme.colorScheme.primary);
    }

    // 使用 AppConfig 获取文件图标
    final iconData = _getFileIcon(entry.fileName);
    // 判断文件是否支持预览，不支持的显示灰色
    final isSupported = _canPreviewFile(entry.fileName);
    return Icon(iconData, color: isSupported ? theme.colorScheme.primary : Colors.grey);
  }

  IconData _getFileIcon(String fileName) {
    final config = AppConfig.instance.fileTypes;

    if (config.isImageFile(fileName)) {
      return Icons.image;
    } else if (config.isVideoFile(fileName)) {
      return Icons.movie;
    } else if (config.isAudioFile(fileName)) {
      return Icons.audiotrack;
    } else if (config.isPdfFile(fileName)) {
      return Icons.picture_as_pdf;
    } else if (config.isDocumentFile(fileName)) {
      final ext = FileUtils.getExtension(fileName);
      if (config.getWordExtensions().contains(ext)) {
        return Icons.article;
      } else if (config.getExcelExtensions().contains(ext)) {
        return Icons.table_chart;
      } else if (config.getTextExtensions().contains(ext)) {
        return Icons.description;
      }
      return Icons.description;
    } else if (config.isApkFile(fileName)) {
      return Icons.android;
    } else if (config.isArchiveFile(fileName)) {
      return Icons.folder_zip;
    }
    return Icons.insert_drive_file;
  }

  Widget? _buildEntrySubtitle(ArchiveEntryInfo entry, ThemeData theme) {
    if (entry.isDirectory) {
      return null;
    }

    // 显示路径（如果不同于文件名）
    if (entry.path != entry.fileName && entry.path.isNotEmpty) {
      return Text(
        entry.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return null;
  }

  /// 判断文件是否支持预览
  ///
  /// 遵循 FilePreviewPage 的判断逻辑：
  /// - 已知支持类型（图片、视频、音频、PDF、文本、文档）→ 彩色图标
  /// - 未知类型（二进制文件、压缩包等）→ 灰色图标
  ///
  /// 注意：在列表中无法读取文件内容判断是否为文本，所以未知扩展名默认灰色
  bool _canPreviewFile(String fileName) {
    final config = AppConfig.instance.fileTypes;
    return config.isImageFile(fileName) ||
        config.isVideoFile(fileName) ||
        config.isAudioFile(fileName) ||
        config.isPdfFile(fileName) ||
        config.isTextFile(fileName) ||
        config.isDocumentFile(fileName);
  }

  /// 检查错误消息是否表示需要密码
  bool _needsPassword(String? errorMessage) {
    if (errorMessage == null) return false;
    final lowerError = errorMessage.toLowerCase();

    return lowerError.contains('password') ||
        lowerError.contains('encrypted') ||
        lowerError.contains('密码') ||
        lowerError.contains('error code: -108') || // minizip-ng密码错误码（entry_open）
        lowerError.contains('error code: -3') || // minizip-ng密码错误码（read）
        lowerError.contains('error code: -10') || // CRC错误（也可能是密码问题）
        lowerError.contains('(error code: -108)') ||
        lowerError.contains('(error code: -3)') ||
        lowerError.contains('(error code: -10)');
  }
}
