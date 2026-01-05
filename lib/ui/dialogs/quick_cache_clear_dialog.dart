import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/cache_manager_service.dart';
import 'package:easyfile/ui/pages/cache_management_page.dart';

/// 一键清理缓存对话框
/// 
/// 提供快速清理所有缓存的简化界面，包含：
/// - 简短说明和可展开的详细说明
/// - 一键清理按钮（调用clearAllCache）
/// - 高级缓存管理入口（跳转到详细页面）
class QuickCacheClearDialog extends StatefulWidget {
  final CacheManagerService cacheManager;

  const QuickCacheClearDialog({
    super.key,
    required this.cacheManager,
  });

  @override
  State<QuickCacheClearDialog> createState() => _QuickCacheClearDialogState();
}

class _QuickCacheClearDialogState extends State<QuickCacheClearDialog> {
  bool _isExpanded = false;
  bool _isClearing = false;
  int _cacheSize = 0;
  bool _isLoadingSize = true;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  /// 加载缓存大小
  Future<void> _loadCacheSize() async {
    try {
      final size = await widget.cacheManager.getTotalCacheSize();
      if (mounted) {
        setState(() {
          _cacheSize = size;
          _isLoadingSize = false;
        });
      }
    } catch (e) {
      logger.e('Failed to load cache size: $e');
      if (mounted) {
        setState(() {
          _isLoadingSize = false;
        });
      }
    }
  }

  /// 格式化缓存大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 展开/收起详细说明
  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  /// 一键清理缓存
  Future<void> _onQuickClear() async {
    setState(() {
      _isClearing = true;
    });

    logger.i('Quick cache clear started');
    final cacheSizeBeforeClear = _cacheSize;

    // 执行清理
    ClearAllResult? result;
    bool isTimeout = false;
    try {
      result = await widget.cacheManager.clearAllCache().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          logger.w('Quick cache clear timeout');
          isTimeout = true;
          return ClearAllResult(
            successCount: 0,
            failCount: CacheType.values.length,
            errors: ['操作超时'],
          );
        },
      );
    } catch (e) {
      logger.e('Quick cache clear error: $e');
    }

    if (!mounted) return;

    setState(() {
      _isClearing = false;
    });

    // 关闭当前对话框
    Navigator.of(context).pop();

    // 显示结果对话框
    _showResultDialog(result, cacheSizeBeforeClear, isTimeout);
  }

  /// 显示清理结果对话框
  void _showResultDialog(ClearAllResult? result, int clearedSize, bool isTimeout) {
    String title;
    String mainMessage;
    String? subMessage;
    IconData icon;
    Color iconColor;

    if (result == null) {
      // 异常情况
      title = '清理遇到问题';
      mainMessage = '未能完成缓存清理，请稍后重试';
      icon = Icons.warning_amber_rounded;
      iconColor = Colors.orange;
    } else if (isTimeout) {
      // 超时
      title = '操作超时';
      mainMessage = '清理时间过长，请检查设备状态后重试';
      icon = Icons.access_time_rounded;
      iconColor = Colors.orange;
    } else if (result.successCount == 0) {
      // 完全失败
      title = '清理遇到问题';
      mainMessage = '未能完成缓存清理，请稍后重试';
      icon = Icons.warning_amber_rounded;
      iconColor = Colors.orange;
    } else if (result.failCount > 0) {
      // 部分成功
      title = '清理完成';
      mainMessage = '已释放 ${_formatSize(clearedSize)} 存储空间';
      subMessage = '成功清理 ${result.successCount} 项，${result.failCount} 项跳过';
      icon = Icons.check_circle_rounded;
      iconColor = Colors.green;
    } else {
      // 全部成功
      title = '清理完成';
      mainMessage = '已释放 ${_formatSize(clearedSize)} 存储空间';
      subMessage = '清理了 ${result.successCount} 项缓存';
      icon = Icons.check_circle_rounded;
      iconColor = Colors.green;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              mainMessage,
              style: const TextStyle(fontSize: 15),
              textAlign: TextAlign.center,
            ),
            if (subMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                subMessage,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  /// 进入高级缓存管理
  void _onAdvancedManagement() {
    Navigator.of(context).pop(); // 关闭对话框
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CacheManagementPage(
          cacheManager: widget.cacheManager,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('一键清理缓存'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缓存大小显示
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '应用缓存大小：',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  _isLoadingSize
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _formatSize(_cacheSize),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 简短说明
            const Text(
              '清理扫描和临时缓存，用于提升运行效率，不会删除或影响任何文件',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),

            // 了解更多按钮
            InkWell(
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '了解更多',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // 高级缓存管理链接（带图标）
            InkWell(
              onTap: _isClearing ? null : _onAdvancedManagement,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.settings,
                      size: 14,
                      color: _isClearing ? Colors.grey[400] : Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '高级缓存管理',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isClearing ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 详细说明（可展开）
            if (_isExpanded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '将会清理：',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '• 文件扫描、分类和统计过程中产生的缓存\n'
                      '• 图片和视频的预览与缩略图缓存\n'
                      '• 部分临时分析数据',
                      style: TextStyle(fontSize: 11, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '不会清理：',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '• 任何用户文件或文件夹\n'
                      '• 下载内容、图片、视频、文档等真实数据\n'
                      '• 应用的重要设置和记录',
                      style: TextStyle(fontSize: 11, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '清理完成后，如需再次使用相关功能，缓存会自动重新生成。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _isClearing ? null : () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _isClearing ? null : _onQuickClear,
              child: _isClearing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('一键清理'),
            ),
          ],
        ),
      ],
    );
  }
}
        