import 'package:flutter/material.dart';

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/new_files_settings.dart';
import 'package:easyfile/utils/folder_search_engine.dart';
import 'package:easyfile/ui/widgets/scan_path_picker_dialog.dart';

/// 扫描路径管理页面
class ScanPathsManagerPage extends StatefulWidget {
  const ScanPathsManagerPage({super.key});

  @override
  State<ScanPathsManagerPage> createState() => _ScanPathsManagerPageState();
}

class _ScanPathsManagerPageState extends State<ScanPathsManagerPage> {
  late NewFilesSettings _settings;
  final _searchController = TextEditingController();
  List<Map<String, String>> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _settings = locator<NewFilesSettings>();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 搜索文件夹
  Future<void> _searchFolder() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
    });

    try {
      final searchEngine = FolderSearchEngine();
      final matches = await searchEngine.search(query);

      setState(() {
        _searchResults =
            matches.map((m) => {'name': m.name, 'path': m.path}).toList();
        _searching = false;
      });
    } catch (e) {
      logger.e('Error searching folder: $e');
      setState(() {
        _searchResults = [];
        _searching = false;
      });
    }
  }

  /// 添加路径
  Future<void> _addPath(String path) async {
    if (_settings.customScanPaths.contains(path)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该路径已存在')),
      );
      return;
    }

    setState(() {
      _settings.customScanPaths.add(path);
    });

    // Capture messenger before async operation
    final messenger = ScaffoldMessenger.of(context);
    await _settings.save();

    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(content: Text('已添加: $path')),
    );
  }

  /// 删除路径
  Future<void> _removePath(String path) async {
    setState(() {
      _settings.customScanPaths.remove(path);
    });

    // Capture messenger before async operation
    final messenger = ScaffoldMessenger.of(context);
    await _settings.save();

    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(content: Text('已删除: $path')),
    );
  }

  /// 显示浏览文件夹对话框
  Future<void> _browseFolders() async {
    final selectedPath = await ScanPathPickerDialog.show(context);
    if (selectedPath != null) {
      await _addPath(selectedPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理扫描路径'),
      ),
      body: Column(
        children: [
          // 常用路径快捷选择
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '常用路径',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: FolderSearchEngine.getCommonPaths().map((pathInfo) {
                    final name = pathInfo['name']!;
                    final path = pathInfo['path']!;
                    final isAdded = _settings.customScanPaths.contains(path);

                    return ActionChip(
                      label: Text(name),
                      avatar: isAdded
                          ? const Icon(Icons.check_circle,
                              size: 18, color: Colors.green)
                          : const Icon(Icons.add_circle_outline, size: 18),
                      onPressed: () {
                        if (isAdded) {
                          _removePath(path);
                        } else {
                          _addPath(path);
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const Divider(),

          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '搜索路径',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: '输入应用名或路径，如：钉钉、微信',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onSubmitted: (_) => _searchFolder(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _searchFolder,
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: _browseFolders,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 搜索结果
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          if (!_searching && _searchResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '搜索结果',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...(_searchResults.map((result) {
                    final name = result['name']!;
                    final path = result['path']!;
                    final isAdded = _settings.customScanPaths.contains(path);

                    return ListTile(
                      leading: const Icon(Icons.folder, color: Colors.orange),
                      title: Text(name),
                      subtitle: Text(path),
                      trailing: isAdded
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () => _addPath(path),
                            ),
                    );
                  }).toList()),
                ],
              ),
            ),

          const Divider(),

          // 已添加的自定义路径
          Expanded(
            child: _settings.customScanPaths.isEmpty
                ? const Center(
                    child: Text(
                      '还没有添加自定义扫描路径',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _settings.customScanPaths.length,
                    itemBuilder: (context, index) {
                      final path = _settings.customScanPaths[index];

                      return ListTile(
                        leading: const Icon(Icons.folder_special,
                            color: Colors.blue),
                        title: Text(path),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _removePath(path),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
