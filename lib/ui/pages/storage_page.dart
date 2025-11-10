import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/logger.dart';

/// 存储空间页面
/// 显示存储中所有文件和文件夹的列表
class StoragePage extends StatefulWidget {
  final FilePresenter presenter;
  final FileViewModel viewModel;

  const StoragePage({
    super.key,
    required this.presenter,
    required this.viewModel,
  });

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  bool _isLoading = true;
  List<FileItem> _files = [];
  String _currentPath = '';

  @override
  void initState() {
    super.initState();
    _loadStorageFiles();
  }

  Future<void> _loadStorageFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取根存储路径
      String rootPath;
      if (Platform.isAndroid) {
        rootPath = '/storage/emulated/0';
      } else if (Platform.isWindows) {
        rootPath = Platform.environment['USERPROFILE'] ?? 'C:\\';
      } else {
        rootPath = Directory.current.path;
      }

      _currentPath = rootPath;
      
      final directory = Directory(rootPath);
      if (directory.existsSync()) {
        final entities = directory.listSync()
            .where((entity) => !entity.path.split(Platform.pathSeparator).last.startsWith('.'))
            .toList();

        final files = entities.map((e) => FileItem.fromEntity(e)).toList();
        
        // 按类型排序：文件夹在前，文件在后
        files.sort((a, b) {
          if (a.isDirectory && !b.isDirectory) return -1;
          if (!a.isDirectory && b.isDirectory) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

        setState(() {
          _files = files;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      logger.e('Failed to load storage files: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  void _onFileTap(FileItem file) {
    if (file.isDirectory) {
      // 导航到该文件夹
      widget.presenter.loadFiles(file.path);
      Navigator.of(context).pop();
    } else {
      // 可以添加文件预览功能
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件: ${file.name}')),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('存储空间'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStorageFiles,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '没有找到文件',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentPath,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 路径显示
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_open,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _currentPath,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 统计信息
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      color: Colors.blue.shade50,
                      child: Text(
                        '找到 ${_files.length} 个项目 (${_files.where((f) => f.isDirectory).length} 个文件夹, ${_files.where((f) => !f.isDirectory).length} 个文件)',
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                    // 文件列表
                    Expanded(
                      child: ListView.builder(
                        itemCount: _files.length,
                        itemBuilder: (context, index) {
                          final file = _files[index];
                          return ListTile(
                            leading: Icon(
                              file.isDirectory ? Icons.folder : Icons.insert_drive_file,
                              color: file.isDirectory ? Colors.amber : Colors.grey,
                            ),
                            title: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              file.isDirectory ? '文件夹' : _formatFileSize(file.size),
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: file.isDirectory 
                                ? const Icon(Icons.chevron_right) 
                                : null,
                            onTap: () => _onFileTap(file),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
