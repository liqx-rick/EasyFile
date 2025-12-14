import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'package:easyfile/core/logger.dart';

/// 扫描路径选择对话框（用于新文件Tab的扫描路径配置）
class ScanPathPickerDialog extends StatefulWidget {
  final String initialPath;

  const ScanPathPickerDialog({
    super.key,
    this.initialPath = '/storage/emulated/0',
  });

  @override
  State<ScanPathPickerDialog> createState() => _ScanPathPickerDialogState();

  /// 显示扫描路径选择对话框
  static Future<String?> show(
    BuildContext context, {
    String initialPath = '/storage/emulated/0',
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) => ScanPathPickerDialog(initialPath: initialPath),
    );
  }
}

class _ScanPathPickerDialogState extends State<ScanPathPickerDialog> {
  late String _currentPath;
  List<Directory> _folders = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadFolders();
  }

  /// 加载文件夹列表
  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
    });

    try {
      final dir = Directory(_currentPath);
      if (!dir.existsSync()) {
        logger.e('Directory not exist: $_currentPath');
        setState(() {
          _folders = [];
          _loading = false;
        });
        return;
      }

      final entities = dir.listSync(recursive: false);
      final folders = <Directory>[];

      for (final entity in entities) {
        if (entity is Directory) {
          try {
            final folderName = path.basename(entity.path);

            // 跳过隐藏文件夹
            if (folderName.startsWith('.')) {
              continue;
            }

            folders.add(entity);
          } catch (e) {
            // 跳过无权限访问的文件夹
            logger.d('Skip folder ${entity.path}: $e');
          }
        }
      }

      // 按名称排序
      folders.sort(
          (a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (e) {
      logger.e('Error loading folders: $e');
      setState(() {
        _folders = [];
        _loading = false;
      });
    }
  }

  /// 导航到指定文件夹
  void _navigateToFolder(String folderPath) {
    setState(() {
      _currentPath = folderPath;
    });
    _loadFolders();
  }

  /// 返回上一级
  void _navigateUp() {
    final parent = Directory(_currentPath).parent;
    if (parent.path != _currentPath) {
      _navigateToFolder(parent.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择扫描路径'),
      contentPadding: const EdgeInsets.all(0),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            // 路径栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey[200],
              child: Row(
                children: [
                  // 返回按钮
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _currentPath != '/storage/emulated/0'
                        ? _navigateUp
                        : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  // 当前路径
                  Expanded(
                    child: Text(
                      _currentPath,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 文件夹列表
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _folders.isEmpty
                      ? const Center(child: Text('无子文件夹'))
                      : ListView.builder(
                          itemCount: _folders.length,
                          itemBuilder: (context, index) {
                            final folder = _folders[index];
                            final folderName = path.basename(folder.path);

                            return ListTile(
                              leading: const Icon(Icons.folder,
                                  color: Colors.orange),
                              title: Text(folderName),
                              onTap: () {
                                _navigateToFolder(folder.path);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(_currentPath);
          },
          child: const Text('选择当前文件夹'),
        ),
      ],
    );
  }
}
