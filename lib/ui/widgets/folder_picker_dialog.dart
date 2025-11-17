import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';
import 'dart:io';

class FolderPickerDialog extends StatefulWidget {
  final String currentPath;
  final String title;

  const FolderPickerDialog({
    super.key,
    required this.currentPath,
    this.title = '选择目标文件夹',
  });

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  String _currentPath = '';
  String _rootPath = ''; // 记录起始根目录
  List<FileItem> _folders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.currentPath;
    _rootPath = widget.currentPath; // 保存起始路径作为根路径
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
      logger.e('Error loading folders: $e');
      setState(() {
        _folders = [];
        _isLoading = false;
      });
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
    // 不允许向上超出根路径
    if (parentPath != _currentPath && parentPath.startsWith(_rootPath)) {
      await _navigateToFolder(parentPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            // 当前路径显示
            Container(
              width: double.infinity,
              height: 48, // 固定高度
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  // 返回按钮区域（固定宽度）
                  if (_currentPath != _rootPath)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20),
                      onPressed: _navigateUp,
                      tooltip: '返回上级',
                    )
                  else
                    const SizedBox(width: 48), // 占位保持对齐
                  Expanded(
                    child: Text(
                      _getDisplayPath(),
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 文件夹列表
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _folders.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('此文件夹中没有子文件夹'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _folders.length,
                      itemBuilder: (context, index) {
                        final folder = _folders[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.folder,
                            color: Colors.amber,
                          ),
                          title: Text(folder.name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _navigateToFolder(folder.path),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_currentPath),
          child: const Text('选择此文件夹'),
        ),
      ],
    );
  }

  String _getDisplayPath() {
    if (_currentPath.contains('/storage/emulated/0')) {
      if (_currentPath == '/storage/emulated/0') return '内部存储';
      return _currentPath.replaceFirst('/storage/emulated/0', '内部存储');
    }
    return _currentPath;
  }
}
