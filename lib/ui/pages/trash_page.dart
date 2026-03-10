import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/services/user_operation_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/locator.dart';
import '../../core/logger.dart';
import '../../core/services/app_trash_manager.dart';
import '../../core/settings/app_trash_settings.dart';
import '../../data/models/app_trash_item.dart';
import '../widgets/file_list_item_builder.dart';
import 'trash_config_page.dart';

/// 回收站页面 - 极简版
/// 功能：文件列表、单个操作（恢复/删除）、一键清空、统计信息
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  final AppTrashManager _trashManager = locator<AppTrashManager>();
  late final AppTrashSettings _trashSettings;
  List<AppTrashItem> _items = [];
  bool _isLoading = true;
  Map<String, dynamic>? _statistics;

  @override
  void initState() {
    super.initState();
    _trashSettings = locator<AppTrashSettings>();
    _loadData();

    // 埋点：查看回收站
    AnalyticsHelper.logTrashView();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final items = await _trashManager.getAllItems();
      final stats = await _trashManager.getStatistics();

      setState(() {
        _items = items;
        _statistics = stats;
        _isLoading = false;
      });
    } catch (e) {
      logger.e('加载回收站数据失败: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingEnabled = _trashSettings.isEnabled;
    final hasFiles = _items.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0978FE),
        foregroundColor: Colors.white,
        title: const Text('回收站'),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildBody(settingEnabled, hasFiles),
    );
  }

  /// 根据状态显示不同的内容
  Widget _buildBody(bool settingEnabled, bool hasFiles) {
    if (!settingEnabled && hasFiles) {
      // 情况1：功能关闭 + 有遗留文件
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildLegacyWarning()),
          SliverToBoxAdapter(child: _buildStatisticsCard()),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = _items[index];
                return Column(
                  children: [
                    _buildFileItem(item),
                    if (index < _items.length - 1) const Divider(height: 1),
                  ],
                );
              },
              childCount: _items.length,
            ),
          ),
        ],
      );
    } else if (!settingEnabled && !hasFiles) {
      // 情况2：功能关闭 + 无文件
      return _buildDisabledEmptyState();
    } else {
      // 情况3/4：功能开启（正常显示）
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildStatisticsCard()),
          hasFiles
              ? SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _items[index];
                      return Column(
                        children: [
                          _buildFileItem(item),
                          if (index < _items.length - 1) const Divider(height: 1),
                        ],
                      );
                    },
                    childCount: _items.length,
                  ),
                )
              : SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                ),
        ],
      );
    }
  }

  /// 空状态
  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.delete_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '您没有最近删除的文件',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 功能关闭时的空状态（无遗留文件）
  Widget _buildDisabledEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '回收站功能未开启',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TrashConfigPage(),
                  ),
                ).then((_) {
                  // 从设置页返回后刷新状态
                  _loadData();
                });
              },
              icon: const Icon(Icons.settings),
              label: const Text('前往设置'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0978FE),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 功能关闭但有遗留文件时的警告提示
  Widget _buildLegacyWarning() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border.all(color: Colors.orange[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
              const SizedBox(width: 8),
              Text(
                '回收站功能已关闭',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '以下是功能关闭前的遗留文件，您可以继续管理这些文件',
            style: TextStyle(
              fontSize: 14,
              color: Colors.orange[800],
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TrashConfigPage(),
                ),
              ).then((_) {
                // 从设置页返回后刷新状态
                _loadData();
              });
            },
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('开启回收站功能'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange[900],
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  /// 统计信息卡片
  Widget _buildStatisticsCard() {
    if (_statistics == null) return const SizedBox.shrink();

    final fileCount = (_statistics!['totalCount'] as int?) ?? 0;
    final totalSize = (_statistics!['totalSize'] as int?) ?? 0;
    final retentionDays = (_statistics!['retentionDays'] as int?) ?? 7;
    final hasItems = _items.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 统计信息
          _buildStatRow('文件数量', '$fileCount 个'),
          const SizedBox(height: 12),
          _buildStatRow('占用空间', _formatSize(totalSize)),
          const SizedBox(height: 12),
          _buildStatRow('自动清理', '删除 $retentionDays 天后清理'),
          const SizedBox(height: 20),
          // 一键清空按钮
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: hasItems ? _confirmEmptyTrash : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: hasItems ? Colors.red : Colors.grey[300],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[500],
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '一键清空回收站',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建统计行
  Widget _buildStatRow(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  /// 文件列表项
  Widget _buildFileItem(AppTrashItem item) {
    return InkWell(
      onLongPress: () => _showFileDetails(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左：缩略图 (56x56)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 56,
                height: 56,
                color: Colors.grey[100],
                child: _buildThumbnail(item),
              ),
            ),
            const SizedBox(width: 12),
            // 右：文件信息（满行）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一行：文件名
                  Text(
                    _getFileName(item.originalPath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 第二行：原路径
                  Text(
                    _truncatePath(item.originalPath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 第三行：大小、时间、操作按钮
                  Row(
                    children: [
                      // 大小和时间
                      Expanded(
                        child: Text(
                          '${_formatSize(item.size)} · ${_formatRelativeTime(item.deletedAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 恢复按钮
                      TextButton(
                        onPressed: () => _restoreFile(item),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          minimumSize: const Size(48, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('恢复', style: TextStyle(fontSize: 13)),
                      ),
                      // 分隔符
                      Text(
                        '·',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      // 删除按钮
                      TextButton(
                        onPressed: () => _confirmDeleteFile(item),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          minimumSize: const Size(48, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('删除', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建缩略图
  Widget _buildThumbnail(AppTrashItem item) {
    final fileName = _getFileName(item.originalPath);
    final isDirectory = item.mimeType.toLowerCase() == 'inode/directory';

    // 使用统一的 FileListItemBuilder 构建缩略图
    return FileListItemBuilder.buildFileThumbnail(
      filePath: item.trashPath,
      mimeType: item.mimeType,
      fileName: fileName,
      isDirectory: isDirectory,
      size: 56.0,
    );
  }

  /// 显示文件详情
  void _showFileDetails(AppTrashItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final fileName = _getFileName(item.originalPath);

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '文件详情',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // 文件名
                _buildDetailRow('文件名', fileName),
                const Divider(height: 24),
                // 原始路径
                _buildDetailRowWithCopy('原始路径', item.originalPath),
                const Divider(height: 24),
                // 文件大小
                _buildDetailRow('文件大小', _formatSize(item.size)),
                const Divider(height: 24),
                // 删除时间
                _buildDetailRow('删除时间', _formatFullTime(item.deletedAt)),
                const Divider(height: 24),
                // 剩余天数
                _buildDetailRow(
                  '保留时间',
                  '${(_statistics!['retentionDays'] as int?) ?? 7} 天后自动清理',
                ),
                const SizedBox(height: 24),
                // 关闭按钮
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建详情行
  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// 构建可复制的详情行
  Widget _buildDetailRowWithCopy(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 格式化完整时间
  String _formatFullTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// 获取文件名
  String _getFileName(String path) {
    return path.split('/').last;
  }

  /// 智能截断路径
  String _truncatePath(String path) {
    final parts = path.split('/');
    if (parts.length <= 3) return path;

    // 保留前2段和最后1段
    return '${parts[0]}/${parts[1]}/.../${parts.last}';
  }

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  /// 格式化相对时间
  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) return '刚刚';
    if (difference.inMinutes < 60) return '${difference.inMinutes}分钟前';
    if (difference.inHours < 24) return '${difference.inHours}小时前';
    if (difference.inDays < 30) return '${difference.inDays}天前';

    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }

  /// 恢复文件（无确认对话框）
  Future<void> _restoreFile(AppTrashItem item) async {
    try {
      // 显示加载中
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final result = await _trashManager.restoreFile(item);

      // 埋点：恢复文件
      if (result['success'] == true) {
        AnalyticsHelper.logTrashRestore();
      }

      // 关闭加载对话框
      if (!mounted) return;
      Navigator.of(context).pop();

      if (result['success'] == true) {
        final restoredPath = result['targetPath'] as String;

        if (!mounted) return;

        // 显示恢复成功对话框
        // 注：文件列表更新依赖UI层的didChangeDependencies自动刷新机制
        _showRestoreSuccessDialog(restoredPath);

        // 刷新列表
        await _loadData();
      } else {
        _showErrorDialog('恢复失败', result['error'] ?? '未知错误');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorDialog('恢复失败', e.toString());
    }
  }

  /// 显示恢复成功对话框
  void _showRestoreSuccessDialog(String path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[600]),
            const SizedBox(width: 8),
            const Text('恢复成功'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('文件已恢复到：'),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: path));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('路径已复制')),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.copy, size: 18, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                path,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('确定'),
          ),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  /// 确认删除单个文件
  void _confirmDeleteFile(AppTrashItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除'),
        content: Text('确定要永久删除 "${_getFileName(item.originalPath)}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteFile(item);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 删除文件
  Future<void> _deleteFile(AppTrashItem item) async {
    try {
      final success = await _trashManager.deleteFilePermanently(item);

      // 埋点：永久删除
      if (success) {
        AnalyticsHelper.logTrashPermanentDelete(1);
      }

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      if (success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('已永久删除')),
        );
        await _loadData();
      } else {
        _showErrorDialog('删除失败', '无法删除文件');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('删除失败', e.toString());
    }
  }

  /// 确认清空回收站
  void _confirmEmptyTrash() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确定要清空回收站么？'),
        content: Text('将永久删除 ${_items.length} 个文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _emptyTrash();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  /// 清空回收站
  Future<void> _emptyTrash() async {
    try {
      // 显示加载中
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // 记录清空前的文件数和大小
      final fileCountBefore = _items.length;
      final totalSizeBefore = _statistics?['totalSize'] as int? ?? 0;

      final result = await _trashManager.emptyTrash();

      // 关闭加载对话框
      if (!mounted) return;
      Navigator.of(context).pop();

      if (result.containsKey('error')) {
        _showErrorDialog('清空失败', result['error'] ?? '未知错误');
      } else {
        final deletedCount = result['success'] as int? ?? 0;

        // 记录用户操作
        if (deletedCount > 0) {
          await UserOperationLogger.log(
            type: OperationType.trashEmpty,
            fileCount: fileCountBefore,
            sizeBytes: totalSizeBefore,
          );
        }

        if (!mounted) return;

        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(content: Text('已清空回收站（$deletedCount 个文件）')),
        );
        await _loadData();
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorDialog('清空失败', e.toString());
    }
  }

  /// 从文件路径创建FileItem
  /// 显示错误对话框
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
