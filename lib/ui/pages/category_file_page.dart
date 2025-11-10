import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/file_item_tile.dart';
import 'package:easyfile/ui/widgets/file_operation_sheet.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

/// 分类聚合视图页面
///
/// 显示特定类型的所有文件（如图片、音乐等）
class CategoryFilePage extends StatefulWidget {
  final CategoryType categoryType;
  final FilePresenter presenter;
  final FileViewModel viewModel;

  const CategoryFilePage({
    super.key,
    required this.categoryType,
    required this.presenter,
    required this.viewModel,
  });

  @override
  State<CategoryFilePage> createState() => _CategoryFilePageState();
}

class _CategoryFilePageState extends State<CategoryFilePage> {
  late CategoryInfo categoryInfo;
  bool _isLoading = true;
  List<FileItem> _files = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    categoryInfo = CategoryInfo.getInfoByType(widget.categoryType)!;
    _loadCategoryFiles();
  }

  /// 加载分类文件
  Future<void> _loadCategoryFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      logger.i('Loading files for category: ${categoryInfo.name}');
      final files =
          await widget.presenter.scanFilesByCategory(widget.categoryType);

      setState(() {
        _files = files;
        _isLoading = false;
      });

      logger
          .i('Loaded ${files.length} files for category ${categoryInfo.name}');
    } catch (e) {
      logger.e('Error loading category files: $e');
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FileViewModel>.value(
      value: widget.viewModel,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: categoryInfo.backgroundColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  categoryInfo.icon,
                  size: 20,
                  color: categoryInfo.iconColor,
                ),
              ),
              const SizedBox(width: 12),
              Text(categoryInfo.name),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.sort),
              onPressed: _showSortOptions,
              tooltip: '排序',
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在扫描文件...'),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadCategoryFiles,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_files.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCategoryFiles,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    categoryInfo.icon,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '没有找到${categoryInfo.name}文件',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '支持的格式: ${categoryInfo.extensions.take(5).join(', ')}${categoryInfo.extensions.length > 5 ? ' 等' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '下拉刷新',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // 统计信息栏
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: categoryInfo.backgroundColor.withOpacity(0.3),
          child: Row(
            children: [
              Icon(
                categoryInfo.icon,
                size: 16,
                color: categoryInfo.iconColor,
              ),
              const SizedBox(width: 8),
              Text(
                '找到 ${_files.length} 个${categoryInfo.name}文件',
                style: TextStyle(
                  color: categoryInfo.iconColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                _formatTotalSize(),
                style: TextStyle(
                  color: categoryInfo.iconColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        // 文件列表
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadCategoryFiles,
            child: ListView.builder(
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final file = _files[index];
                return FileItemTile(
                  file: file,
                  showFullPath: true, // 在聚合视图中显示完整路径
                  onTap: () => _previewFile(file),
                  onLongPress: () => _showFileOperations(file),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 格式化总大小
  String _formatTotalSize() {
    final totalSize = _files.fold<int>(0, (sum, file) => sum + file.size);
    if (totalSize < 1024) {
      return '${totalSize}B';
    } else if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(1)}KB';
    } else if (totalSize < 1024 * 1024 * 1024) {
      return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }

  /// 显示排序选项
  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sort_by_alpha),
              title: const Text('按名称排序'),
              onTap: () {
                Navigator.pop(context);
                _sortFiles((a, b) => a.name.compareTo(b.name));
              },
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('按修改时间排序'),
              onTap: () {
                Navigator.pop(context);
                _sortFiles((a, b) => b.modified.compareTo(a.modified));
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('按文件大小排序'),
              onTap: () {
                Navigator.pop(context);
                _sortFiles((a, b) => b.size.compareTo(a.size));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 排序文件
  void _sortFiles(int Function(FileItem, FileItem) compare) {
    setState(() {
      _files.sort(compare);
    });
  }

  /// 预览文件
  void _previewFile(FileItem file) {
    logger.d('Previewing file: ${file.path}');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FilePreviewPage(file: file),
      ),
    );
  }

  /// 显示文件操作
  void _showFileOperations(FileItem file) {
    showModalBottomSheet(
      context: context,
      builder: (context) => FileOperationSheet(
        file: file,
        onOperation: (operation) {
          // TODO: 实现文件操作功能（重命名、删除、分享等）
          // 参考 FileBrowserPage 中的实现方式
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('功能开发中: $operation')),
          );
        },
      ),
    );
  }
}
