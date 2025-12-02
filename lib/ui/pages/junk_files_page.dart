import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/junk_file_scan_config.dart';
import 'package:easyfile/core/services/junk_file_service.dart';
import 'package:easyfile/data/models/junk_file_item.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/ui/widgets/sliver_category_filter_delegate.dart';
import 'package:easyfile/ui/widgets/file_list_item_builder.dart';

/// 垃圾文件清理页面
class JunkFilesPage extends StatefulWidget {
  final JunkFileScanConfig? initialConfig;

  const JunkFilesPage({super.key, this.initialConfig});

  @override
  State<JunkFilesPage> createState() => _JunkFilesPageState();
}

class _JunkFilesPageState extends State<JunkFilesPage> {
  late final JunkFileService _service;

  List<JunkFileItem> _allFiles = [];
  List<JunkFileItem> _filteredFiles = [];
  JunkFileType? _selectedType; // 筛选类型
  bool _isScanning = false;
  double _scanProgress = 0.0;
  String _scanningPath = '';

  // 选中的文件
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _service = locator<JunkFileService>();
    _startScan();
  }

  /// 开始扫描
  Future<void> _startScan({bool forceRefresh = false}) async {
    setState(() {
      _isScanning = true;
      _scanProgress = 0.0;
      _allFiles = [];
      _filteredFiles = [];
      _selectedPaths.clear();
    });

    try {
      final config = widget.initialConfig ?? const JunkFileScanConfig();

      final files = await _service.scanJunkFiles(
        config: config,
        forceRefresh: forceRefresh,
        onProgress: (current, total, path) {
          if (mounted) {
            setState(() {
              _scanProgress = total > 0 ? current / total : 0;
              _scanningPath = path;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _allFiles = files;
          _applyFilter();
          _isScanning = false;
        });
      }
    } catch (e) {
      logger.e('扫描垃圾文件失败: $e');
      if (mounted) {
        setState(() => _isScanning = false);
        _showError('扫描失败: $e');
      }
    }
  }

  /// 应用筛选
  void _applyFilter() {
    if (_selectedType == null) {
      _filteredFiles = _allFiles;
    } else {
      _filteredFiles = _allFiles.where((f) => f.type == _selectedType).toList();
    }
  }

  /// 删除选中的文件
  Future<void> _deleteSelected() async {
    if (_selectedPaths.isEmpty) return;

    final confirmed = await _showDeleteConfirmDialog();
    if (confirmed != true || !mounted) return;

    final toDelete =
        _allFiles.where((f) => _selectedPaths.contains(f.path)).toList();

    // 显示加载对话框
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在删除...'),
          ],
        ),
      ),
    );

    final result = await _service.deleteMultiple(toDelete);

    if (mounted) {
      Navigator.of(context).pop(); // 关闭加载对话框

      _showResultDialog(result);

      // 刷新列表
      setState(() {
        _allFiles.removeWhere((f) => _selectedPaths.contains(f.path));
        _applyFilter();
        _selectedPaths.clear();
      });
    }
  }

  /// 显示删除确认对话框
  Future<bool?> _showDeleteConfirmDialog() {
    final totalSize = _allFiles
        .where((f) => _selectedPaths.contains(f.path))
        .fold<int>(0, (sum, f) => sum + f.size);

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          '确定要删除选中的 ${_selectedPaths.length} 个垃圾文件吗？\n'
          '共计 ${FileSizeFormatter.formatBytes(totalSize)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 显示删除结果对话框
  void _showResultDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除完成'),
        content: Text(
          '成功删除: ${result['success']} 个\n'
          '失败: ${result['failed']} 个\n'
          '释放空间: ${result['formattedSize']}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示错误消息
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('垃圾文件清理'),
        actions: [
          // 刷新按钮（扫描时隐藏）
          if (!_isScanning)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: () => _startScan(forceRefresh: true),
            ),
          // 全选/取消全选
          if (!_isScanning && _filteredFiles.isNotEmpty)
            IconButton(
              icon: Icon(
                _selectedPaths.length == _filteredFiles.length &&
                        _selectedPaths.isNotEmpty
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              tooltip: _selectedPaths.length == _filteredFiles.length &&
                      _selectedPaths.isNotEmpty
                  ? '取消全选'
                  : '全选',
              onPressed: () {
                setState(() {
                  final filteredPaths =
                      _filteredFiles.map((f) => f.path).toSet();
                  if (_selectedPaths.containsAll(filteredPaths)) {
                    // 取消选择当前过滤的文件
                    _selectedPaths.removeAll(filteredPaths);
                  } else {
                    // 选择当前过滤的文件
                    _selectedPaths.addAll(filteredPaths);
                  }
                });
              },
            ),
        ],
      ),
      body: _isScanning
          ? _buildScanningView()
          : _allFiles.isEmpty
              ? _buildEmptyView()
              : CustomScrollView(
                  slivers: [
                    // 统计卡片
                    SliverToBoxAdapter(
                      child: _buildSummaryCard(),
                    ),

                    // 分类筛选 - 置顶显示
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: SliverCategoryFilterDelegate(
                        child: _buildTypeFilter(),
                      ),
                    ),

                    // 提示信息（如果筛选后为空）
                    if (_filteredFiles.isEmpty)
                      SliverFillRemaining(
                        child: _buildEmptyCategoryView(),
                      )
                    else
                      // 文件列表
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final file = _filteredFiles[index];
                            final isSelected =
                                _selectedPaths.contains(file.path);

                            return _buildFileListItem(file, isSelected);
                          },
                          childCount: _filteredFiles.length,
                        ),
                      ),
                  ],
                ),
      // 底部工具栏（替代FloatingActionButton）
      bottomNavigationBar: _selectedPaths.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: ElevatedButton.icon(
                  onPressed: _deleteSelected,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('删除'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            ),
    );
  }

  /// 统计卡片
  Widget _buildSummaryCard() {
    final totalSize = _filteredFiles.fold<int>(0, (sum, f) => sum + f.size);
    final totalCount = _filteredFiles.length;
    final selectedSize = _allFiles
        .where((f) => _selectedPaths.contains(f.path))
        .fold<int>(0, (sum, f) => sum + f.size);

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  icon: Icons.description_outlined,
                  label: '文件数',
                  value: '$totalCount',
                  color: Colors.blue,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[300],
                ),
                _buildStatItem(
                  icon: Icons.storage_outlined,
                  label: '可清理',
                  value: FileSizeFormatter.formatBytes(totalSize),
                  color: Colors.orange,
                ),
                if (_selectedPaths.isNotEmpty) ...[
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.grey[300],
                  ),
                  _buildStatItem(
                    icon: Icons.check_circle_outline,
                    label: '已选',
                    value: '${_selectedPaths.length}',
                    valueSecondary: FileSizeFormatter.formatBytes(selectedSize),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 统计项
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    String? valueSecondary,
    Color? color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color ?? Colors.grey[700], size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black87,
            ),
          ),
          if (valueSecondary != null) ...[
            const SizedBox(height: 2),
            Text(
              valueSecondary,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 类型筛选
  Widget _buildTypeFilter() {
    final types = {
      null: '全部',
      JunkFileType.apk: 'APK',
      JunkFileType.tempFile: '临时文件',
      JunkFileType.emptyFolder: '空文件夹',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: types.entries.map((entry) {
          final isSelected = _selectedType == entry.key;
          final count = entry.key == null
              ? _allFiles.length
              : _allFiles.where((f) => f.type == entry.key).length;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('${entry.value} ($count)'),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _selectedType = entry.key;
                  _applyFilter();
                });
              },
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 扫描中视图
  Widget _buildScanningView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              '扫描中...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${(_scanProgress * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _scanProgress),
            const SizedBox(height: 16),
            Text(
              _scanningPath,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 空状态视图
  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          Text(
            '未发现垃圾文件',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('您的设备很干净！'),
        ],
      ),
    );
  }

  /// 构建空分类视图
  Widget _buildEmptyCategoryView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_list_off,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '该分类下没有文件',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ],
      ),
    );
  }

  /// 构建文件列表项
  Widget _buildFileListItem(JunkFileItem file, bool isSelected) {
    return InkWell(
      onLongPress: () => _showFileDetailsDialog(file),
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedPaths.remove(file.path);
          } else {
            _selectedPaths.add(file.path);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧图标或缩略图
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 4),
              child: FileListItemBuilder.buildFileThumbnail(
                filePath: file.path,
                mimeType: _getMimeTypeForJunkFile(file),
                fileName: file.name,
                isDirectory: file.type == JunkFileType.emptyFolder,
                size: 48.0,
              ),
            ),
            // 中间内容区域
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行：文件名 + 勾选框
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          FileListItemBuilder.truncateFileName(file.name,
                              maxLength: 35),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 勾选框
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: isSelected,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedPaths.add(file.path);
                              } else {
                                _selectedPaths.remove(file.path);
                              }
                            });
                          },
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 第二行：类型和大小
                  Text(
                    '${file.type.displayName} · ${FileSizeFormatter.formatBytes(file.size)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF757575),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 第三行：来源 · 时间 · 详情
                  GestureDetector(
                    onTapUp: (details) {
                      final textPainter = TextPainter(
                        text: TextSpan(
                          text:
                              '${file.parentDirectoryName.isNotEmpty ? file.parentDirectoryName : '根目录'} · ${FileListItemBuilder.formatRelativeDate(file.modified)} · ',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF757575),
                          ),
                        ),
                        textDirection: TextDirection.ltr,
                      );
                      textPainter.layout();
                      final offset = textPainter.width;

                      if (details.localPosition.dx >= offset) {
                        _showFileDetailsDialog(file);
                      }
                    },
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF757575),
                          fontFamily: 'Roboto',
                        ),
                        children: [
                          TextSpan(
                            text:
                                '${file.parentDirectoryName.isNotEmpty ? file.parentDirectoryName : '根目录'} · ${FileListItemBuilder.formatRelativeDate(file.modified)} · ',
                          ),
                          const TextSpan(
                            text: '详情',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 文件列表
  /// 显示文件详情对话框
  void _showFileDetailsDialog(JunkFileItem file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('类型', file.type.displayName),
              _buildDetailRow('大小', FileSizeFormatter.formatBytes(file.size)),
              _buildDetailRow(
                  '修改时间', FileListItemBuilder.formatDetailDate(file.modified)),
              if (file.packageName != null)
                _buildDetailRow('包名', file.packageName!),
              const Divider(height: 24),
              _buildDetailRow('完整路径', file.path, isPath: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: file.path));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('路径已复制到剪贴板')),
              );
            },
            child: const Text('复制路径'),
          ),
        ],
      ),
    );
  }

  /// 根据垃圾文件类型和文件名推断MIME类型
  String _getMimeTypeForJunkFile(JunkFileItem file) {
    // 空文件夹
    if (file.type == JunkFileType.emptyFolder) {
      return 'inode/directory';
    }

    // APK文件
    if (file.type == JunkFileType.apk) {
      return 'application/vnd.android.package-archive';
    }

    // 临时文件 - 根据扩展名判断
    final ext = file.name.split('.').last.toLowerCase();

    // 图片类型
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif']
        .contains(ext)) {
      return 'image/$ext';
    }

    // 视频类型
    if (['mp4', 'avi', 'mov', 'mkv', '3gp', 'webm', 'flv', 'm4v']
        .contains(ext)) {
      return 'video/$ext';
    }

    // 音频类型
    if (['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'wma'].contains(ext)) {
      return 'audio/$ext';
    }

    // 文档类型
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'].contains(ext)) {
      return 'application/$ext';
    }

    // 文本类型
    if (['txt', 'log', 'xml', 'json', 'yaml', 'yml'].contains(ext)) {
      return 'text/plain';
    }

    // 默认类型
    return 'application/octet-stream';
  }

  /// 构建详情行
  Widget _buildDetailRow(String label, String value, {bool isPath = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontFamily: isPath ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}
