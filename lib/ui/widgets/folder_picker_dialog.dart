import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';
import 'dart:io';

class FolderPickerDialog extends StatefulWidget {
  final String currentPath;
  final String title;
  final String? sourceFileName; // 新增：源文件名，用于显示提示
  final String operationType; // 操作类型：'移动' 或 '复制'

  const FolderPickerDialog({
    super.key,
    required this.currentPath,
    this.title = '选择目标文件夹',
    this.sourceFileName,
    this.operationType = '移动', // 默认为移动
  });

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  String _currentPath = '';
  String _rootPath = ''; // 内部存储根目录
  List<FileItem> _folders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // 设置根目录为内部存储根目录，允许用户在整个存储空间导航
    _rootPath = '/storage/emulated/0';
    // 初始浏览位置也设为根目录，而不是当前文件位置
    _currentPath = _rootPath;
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _isLoading = true;
    });

    try {
      logger.d('Loading folders for path: $_currentPath');
      final dir = Directory(_currentPath);

      if (!dir.existsSync()) {
        logger.w('Directory does not exist: $_currentPath');
        setState(() {
          _folders = [];
          _isLoading = false;
        });
        return;
      }

      final entities = dir
          .listSync()
          .whereType<Directory>()
          .where(
            (entity) =>
                !entity.path.split(Platform.pathSeparator).last.startsWith('.'),
          )
          .toList();

      final folders = entities.map((e) => FileItem.fromEntity(e)).toList();
      folders.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      setState(() {
        _folders = folders;
        _isLoading = false;
      });

      logger.d('Loaded ${folders.length} folders');
    } catch (e) {
      // 捕获权限拒绝错误（如 Android/data 目录）
      if (e.toString().contains('Permission denied') ||
          e.toString().contains('errno = 13')) {
        logger.w('Permission denied for directory: $_currentPath');
        // 返回空列表，不显示错误
        setState(() {
          _folders = [];
          _isLoading = false;
        });
      } else {
        logger.e('Error loading folders: $e');
        setState(() {
          _folders = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _navigateToFolder(String folderPath) async {
    setState(() {
      _currentPath = folderPath;
    });
    await _loadFolders();
  }

  Future<void> _navigateUp() async {
    final parentPath = Directory(_currentPath).parent.path;
    // 允许向上导航，但不超出内部存储根目录
    if (parentPath != _currentPath &&
        (parentPath == _rootPath ||
            parentPath.startsWith(_rootPath + Platform.pathSeparator))) {
      await _navigateToFolder(parentPath);
    }
  }

  /// 验证文件夹名称
  String? _validateFolderName(String name) {
    if (name.trim().isEmpty) {
      return '文件夹名不能为空';
    }

    // 检查非法字符
    final invalidChars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
    for (final char in invalidChars) {
      if (name.contains(char)) {
        return '文件夹名不能包含以下字符：/ \\ : * ? " < > |';
      }
    }

    // 检查是否已存在同名文件夹
    final existingFolder = _folders.any((f) => f.name == name);
    if (existingFolder) {
      return '该文件夹名称已存在';
    }

    return null;
  }

  /// 显示创建文件夹对话框
  Future<void> _showCreateFolderDialog() async {
    final textController = TextEditingController();
    String? errorText;

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.create_new_folder, color: Colors.blue),
              SizedBox(width: 12),
              Text('创建新文件夹'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: textController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '文件夹名称',
                  hintText: '请输入文件夹名称',
                  errorText: errorText,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.folder),
                ),
                onChanged: (value) {
                  setDialogState(() {
                    errorText = _validateFolderName(value);
                  });
                },
                onSubmitted: (value) {
                  if (_validateFolderName(value) == null && value.isNotEmpty) {
                    Navigator.of(context).pop(value.trim());
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: errorText == null && textController.text.isNotEmpty
                  ? () => Navigator.of(context).pop(textController.text.trim())
                  : null,
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );

    // 延迟 dispose，等待对话框关闭动画和键盘收起动画完成
    // 这避免了在对话框重建时使用已 dispose 的 controller
    await Future.delayed(const Duration(milliseconds: 300));
    textController.dispose();

    // 如果返回了文件夹名称，则创建文件夹
    if (result != null && result.isNotEmpty) {
      await _createFolder(result);
    }
  }

  /// 创建文件夹
  Future<void> _createFolder(String folderName) async {
    try {
      final newFolderPath = '$_currentPath${Platform.pathSeparator}$folderName';
      final newFolder = Directory(newFolderPath);

      // 创建文件夹
      await newFolder.create();
      logger.i('Folder created successfully: $newFolderPath');

      // 刷新列表
      await _loadFolders();

      // 自动进入新创建的文件夹
      await _navigateToFolder(newFolderPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('文件夹 "$folderName" 创建成功'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logger.e('Error creating folder: $e');
      if (mounted) {
        _showErrorDialog(
          '无法创建文件夹',
          _getErrorMessage(e),
          _getErrorSuggestion(e),
        );
      }
    }
  }

  /// 获取错误信息
  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('permission') || errorStr.contains('denied')) {
      return '没有在此位置创建文件夹的权限';
    } else if (errorStr.contains('exist')) {
      return '该文件夹已存在';
    } else if (errorStr.contains('space')) {
      return '存储空间不足';
    } else {
      return '发生未知错误：$error';
    }
  }

  /// 获取错误建议
  String? _getErrorSuggestion(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('permission') || errorStr.contains('denied')) {
      return '请选择其他位置或检查权限设置';
    } else if (errorStr.contains('exist')) {
      return '请使用其他名称或删除现有文件夹';
    } else if (errorStr.contains('space')) {
      return '请清理存储空间后重试';
    }
    return null;
  }

  /// 显示错误对话框
  void _showErrorDialog(String title, String message, String? suggestion) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 48),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('错误原因：$message'),
            if (suggestion != null) ...[
              const SizedBox(height: 8),
              Text(
                '建议：$suggestion',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 判断是否为横屏模式
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return AlertDialog(
      contentPadding: const EdgeInsets.all(0),
      content: SizedBox(
        width: isLandscape ? 800 : double.maxFinite,
        height: 500,
        child: isLandscape
            ? _buildLandscapeLayout(theme, isDark)
            : _buildPortraitLayout(theme, isDark),
      ),
      actions: isLandscape
          ? null
          : [
              // 操作信息
              if (widget.sourceFileName != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '正在${widget.operationType}：',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_getDisplayPath(widget.currentPath)}/${widget.sourceFileName!}',
                        style: const TextStyle(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              // 按钮行
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(_currentPath),
                      child: const Text('选择此文件夹'),
                    ),
                  ],
                ),
              ),
            ],
    );
  }

  /// 竖屏布局（保持现有设计）
  Widget _buildPortraitLayout(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Icon(
                widget.operationType == '复制'
                    ? Icons.copy
                    : Icons.drive_file_move,
                size: 24,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 当前浏览路径
          _buildCurrentPathCard(theme, isDark),
          const SizedBox(height: 12),

          // 操作栏（返回上级 + 创建文件夹）
          _buildActionBar(theme, isDark),
          const SizedBox(height: 12),

          // 文件夹列表
          Expanded(child: _buildFolderList()),
        ],
      ),
    );
  }

  /// 横屏布局（左右分栏）
  Widget _buildLandscapeLayout(ThemeData theme, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧信息面板
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 提示文字
                Text(
                  '请在右侧选择文件夹',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),

                // 当前浏览路径卡片
                _buildCurrentPathCard(theme, isDark),
                const SizedBox(height: 16),

                // 操作栏（返回上级 + 创建文件夹）
                _buildActionBar(theme, isDark),

                // 操作信息（如果有）
                if (widget.sourceFileName != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.grey[700]! : Colors.blue[200]!,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              widget.operationType == '复制'
                                  ? Icons.copy
                                  : Icons.drive_file_move,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '正在${widget.operationType}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.sourceFileName!,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '当前位置：${_getDisplayPath(widget.currentPath)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],

                // 使用 Expanded 和 SizedBox 占据剩余空间
                const Expanded(child: SizedBox()),

                // 底部按钮（调整顺序：取消在左，确认在右）
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pop(_currentPath),
                        child: const Text('选择此文件夹'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // 分割线
        Container(
          width: 1,
          color: isDark ? Colors.grey[800] : Colors.grey[300],
        ),
        // 右侧文件夹选择区域
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _buildFolderList(),
          ),
        ),
      ],
    );
  }

  /// 构建当前路径卡片
  Widget _buildCurrentPathCard(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.folder_open,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _getDisplayPath(_currentPath),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建操作栏（返回上级 + 创建文件夹）
  Widget _buildActionBar(ThemeData theme, bool isDark) {
    final canNavigateUp = _currentPath != _rootPath;

    return Row(
      children: [
        // 返回上级
        TextButton.icon(
          onPressed: canNavigateUp ? _navigateUp : null,
          icon: const Icon(Icons.arrow_upward, size: 18),
          label: const Text('返回上级'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        const SizedBox(width: 8),
        // 新建文件夹
        TextButton.icon(
          onPressed: _showCreateFolderDialog,
          icon: const Icon(Icons.create_new_folder, size: 18),
          label: const Text('新建文件夹'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  /// 构建文件夹列表
  Widget _buildFolderList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_folders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('此文件夹中没有子文件夹'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -2),
          leading: const Icon(Icons.folder, color: Colors.amber),
          title: Text(folder.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _navigateToFolder(folder.path),
        );
      },
    );
  }

  String _getDisplayPath(String path) {
    if (path.contains('/storage/emulated/0')) {
      if (path == '/storage/emulated/0') return '内部存储';
      return path.replaceFirst('/storage/emulated/0', '内部存储');
    }
    return path;
  }
}
