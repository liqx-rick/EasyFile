import 'package:flutter/material.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/junk_file_scan_config.dart';
import 'package:easyfile/core/preferences/system_trash_preferences.dart';
import 'package:easyfile/core/services/junk_file_service.dart';
import 'package:easyfile/core/services/trash_file_service.dart';
import 'package:easyfile/data/models/junk_file_item.dart';
import 'package:easyfile/ui/pages/trash_files_page.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/ui/widgets/sliver_category_filter_delegate.dart';
import 'package:easyfile/ui/widgets/file_list_item_builder.dart';
import 'package:easyfile/ui/utils/file_details_helper.dart';
import 'package:easyfile/ui/widgets/edit_mode_widgets.dart';

/// 垃圾文件清理页面
class JunkFilesPage extends StatefulWidget {
  final JunkFileScanConfig? initialConfig;

  const JunkFilesPage({super.key, this.initialConfig});

  @override
  State<JunkFilesPage> createState() => _JunkFilesPageState();
}

class _JunkFilesPageState extends State<JunkFilesPage> {
  JunkFileService? _service;

  List<JunkFileItem> _allFiles = [];
  List<JunkFileItem> _filteredFiles = [];
  JunkFileType? _selectedType; // 筛选类型
  bool _isScanning = false;
  double _scanProgress = 0.0;
  String _scanningPath = '';

  // 选中的文件
  final Set<String> _selectedPaths = {};

  // 系统回收站相关
  Map<String, dynamic>? _systemTrashStats;
  bool _showSystemTrashPrompt = false;
  bool _expandSystemTrashDetails = false; // 折叠/展开状态

  @override
  void initState() {
    super.initState();
    _initializeService();
    // 独立检查系统回收站（不依赖垃圾文件扫描）
    _checkSystemTrashOnInit();
  }

  /// 异步初始化服务
  Future<void> _initializeService() async {
    try {
      _service = await locator.getAsync<JunkFileService>();
      if (mounted) {
        _startScan();
      }
    } catch (e) {
      logger.e('初始化 JunkFileService 失败: $e');
      if (mounted) {
        _showError('服务初始化失败: $e');
      }
    }
  }

  /// 页面初始化时独立检查系统回收站（不依赖垃圾文件扫描）
  Future<void> _checkSystemTrashOnInit() async {
    // 延迟500毫秒，避免与垃圾文件扫描初始化冲突
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // 统一的加载/扫描方法
    await _loadOrScanSystemTrash();
  }

  /// 检查是否应该显示系统回收站提示
  ///
  /// 检查条件：
  /// - 扫描缓存未超过36小时
  /// - 不在用户忽略期内（7天）
  /// - 不在清理抑制期内（7天）
  Future<bool> _shouldShowSystemTrashPrompt() async {
    // 检查用户忽略期（7天）
    if (await SystemTrashPreferences.isInUserDismissedPeriod()) {
      return false;
    }

    // 检查清理抑制期（7天）
    if (await SystemTrashPreferences.isInCleanedSuppressionPeriod()) {
      return false;
    }

    return true;
  }

  /// 加载或扫描系统回收站统计数据
  ///
  /// 流程：
  /// 1. 检查是否应该显示提示（抑制期检查）
  /// 2. 如果不应该显示，直接返回
  /// 3. 尝试加载统计数据（优先使用缓存）
  /// 4. 如果数据>=100MB，显示提示卡片并更新扫描时间
  Future<void> _loadOrScanSystemTrash() async {
    if (!mounted) return;

    try {
      // 1. 检查是否应该显示提示
      if (!await _shouldShowSystemTrashPrompt()) {
        logger.d('系统回收站提示：不满足显示条件（在抑制期内）');
        return;
      }

      // 2. 加载统计数据（优先使用缓存）
      final service = await locator.getAsync<TrashFileService>();
      await service.initialize();

      final stats = await service.getOldFilesStatistics(
        months: 3,
        forceRefresh: false,
      );

      final sizeMB = stats['sizeMB'] as int;

      // 3. 检查是否满足显示阈值（>=100MB）
      if (sizeMB >= 100) {
        // 更新扫描时间（仅在首次显示时更新）
        await SystemTrashPreferences.setLastScanTimeNow();

        if (mounted) {
          setState(() {
            _systemTrashStats = stats;
            _showSystemTrashPrompt = true;
          });
          logger.i('显示系统回收站提示卡片（${sizeMB}MB）');
        }
      } else {
        logger.d('系统回收站旧文件少于100MB（${sizeMB}MB），不显示提示');
      }
    } catch (e) {
      logger.e('加载系统回收站统计数据失败: $e');
    }
  }

  /// 开始扫描
  Future<void> _startScan({bool forceRefresh = false}) async {
    if (_service == null) {
      logger.e('服务未初始化');
      return;
    }

    setState(() {
      _isScanning = true;
      _scanProgress = 0.0;
      _allFiles = [];
      _filteredFiles = [];
      _selectedPaths.clear();
    });

    try {
      final config = widget.initialConfig ?? const JunkFileScanConfig();

      final files = await _service!.scanJunkFiles(
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

        // 注意：系统回收站扫描现在在 initState 时独立触发
        // 不再依赖垃圾文件扫描完成
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

    final result = await _service!.deleteMultiple(toDelete);

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
            SelectAllButton(
              selectedCount: _filteredFiles
                  .where((f) => _selectedPaths.contains(f.path))
                  .length,
              totalCount: _filteredFiles.length,
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
                    // 统计卡片（包含系统回收站提示）
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
                    color: Colors.black.withValues(alpha: 0.1),
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
      child: Column(
        children: [
          // 上部：垃圾文件统计信息
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
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
          ),

          // 下部：系统回收站提示（如果有）
          if (_showSystemTrashPrompt && _systemTrashStats != null)
            _buildSystemTrashSection(),
        ],
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
              label: Text(isSelected ? '${entry.value} ($count)' : entry.value),
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
      onLongPress: () =>
          FileDetailsHelper.showJunkFileDetailsBottomSheet(context, file),
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
                        FileDetailsHelper.showJunkFileDetailsBottomSheet(
                            context, file);
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

    // 临时文件 - 使用配置判断
    return AppConfig.instance.fileTypes.getSimplifiedMimeType(file.name);
  }

  /// 系统回收站提示卡片（折叠版）
  /// 系统回收站提示区域（在统计卡片内）
  Widget _buildSystemTrashSection() {
    final count = _systemTrashStats!['count'] as int;
    final sizeMB = _systemTrashStats!['sizeMB'] as int;
    final oldestFileDate = _systemTrashStats!['oldestFileDate'] as DateTime?;

    // 格式化最久时间显示
    String oldestTimeDisplay = '未知';
    if (oldestFileDate != null) {
      final duration = DateTime.now().difference(oldestFileDate);
      final days = duration.inDays;

      if (days >= 365) {
        final years = days ~/ 365;
        final months = (days % 365) ~/ 30;
        oldestTimeDisplay = months > 0 ? '$years年$months个月前' : '$years年前';
      } else if (days >= 30) {
        final months = days ~/ 30;
        oldestTimeDisplay = '$months个月前';
      } else {
        oldestTimeDisplay = '$days天前';
      }

      // 添加实际日期
      final dateStr =
          '${oldestFileDate.year}年${oldestFileDate.month}月${oldestFileDate.day}日';
      oldestTimeDisplay = '$oldestTimeDisplay ($dateStr)';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Column(
        children: [
          // 主标题区域（可折叠）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 折叠图标
                InkWell(
                  onTap: () {
                    setState(() =>
                        _expandSystemTrashDetails = !_expandSystemTrashDetails);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      _expandSystemTrashDetails
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 文案和按钮（Stack布局）
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 文案（可点击展开）
                      GestureDetector(
                        onTap: () {
                          setState(() => _expandSystemTrashDetails =
                              !_expandSystemTrashDetails);
                        },
                        child: Padding(
                          padding:
                              const EdgeInsets.only(bottom: 12), // 为下方按钮留出空间
                          child: Text(
                            '检测到系统回收站中存在长期未清理的文件',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ),
                      ),
                      // 按钮（定位在折叠图标下方，靠右显示）
                      Positioned(
                        right: 0,
                        top: 28, // 折叠图标下方位置
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const TrashFilesPage(),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cleaning_services,
                                  color: Color.fromARGB(255, 140, 141, 141),
                                  size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '前往清理',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      const Color.fromARGB(255, 140, 141, 141),
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

          // 详细信息（折叠内容）
          if (_expandSystemTrashDetails) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    '这些文件可能来自旧设备迁移或历史删除操作\n'
                    '当前可能不会自动清理，仍占用存储空间',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow('📊 文件数', '$count 个'),
                  const SizedBox(height: 6),
                  _buildStatRow('💾 占用空间', '$sizeMB MB'),
                  const SizedBox(height: 6),
                  _buildStatRow('⏰ 最久时间', oldestTimeDisplay),
                  const SizedBox(height: 8),
                  // 一周内不再提示（移到折叠内容末尾）
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        await SystemTrashPreferences.setUserDismissedPeriod(
                          const Duration(days: 7),
                        );

                        setState(() => _showSystemTrashPrompt = false);

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已设置一周内不再提示')),
                          );
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                      ),
                      child: Text(
                        '一周内不再提示',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
