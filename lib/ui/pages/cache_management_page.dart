import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/cache_manager_service.dart';
import 'package:easyfile/ui/widgets/quick_access_section.dart';
import 'package:flutter/material.dart';

/// 缓存管理页面
///
/// 用于查看和清理应用的各类缓存数据，包括：
/// - 缩略图缓存
/// - 日志文件
/// - 分类扫描缓存
/// - 搜索历史
/// - 视频播放数据
/// - 大文件扫描缓存
/// - 重复文件扫描缓存
/// - 应用管理缓存
/// - 媒体库扫描缓存
class CacheManagementPage extends StatefulWidget {
  final CacheManagerService cacheManager;

  const CacheManagementPage({
    super.key,
    required this.cacheManager,
  });

  @override
  State<CacheManagementPage> createState() => _CacheManagementPageState();
}

class _CacheManagementPageState extends State<CacheManagementPage> {
  List<CacheItem> _cacheItems = [];
  int _totalSize = 0;
  bool _isLoading = true;
  bool _isClearing = false;
  String? _clearingItemName;

  @override
  void initState() {
    super.initState();
    _loadCacheData();
  }

  Future<void> _loadCacheData() async {
    setState(() => _isLoading = true);

    final items = await widget.cacheManager.getAllCacheItems();
    final total = await widget.cacheManager.getTotalCacheSize();

    if (mounted) {
      setState(() {
        _cacheItems = items;
        _totalSize = total;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearCache(CacheItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清理'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要清理${item.name}吗？'),
            const SizedBox(height: 8),
            Text(
              '大小：${item.formattedSize}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            if (item.type == CacheType.thumbnail) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，缩略图将重新生成',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.log) ...[
              const SizedBox(height: 8),
              const Text(
                'ℹ️ 仅在遇到问题时保留，可安全清理',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ],
            if (item.type == CacheType.categoryScan) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，分类页面需要重新扫描',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.searchHistory) ...[
              const SizedBox(height: 8),
              const Text(
                'ℹ️ 将删除所有搜索记录',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ],
            if (item.type == CacheType.videoPlayback) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，视频将从头播放',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.largeFileScan) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，大文件查找需要重新扫描',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.duplicateFileScan) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，重复文件查找需要重新扫描',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.appManagement) ...[
              const SizedBox(height: 8),
              const Text(
                'ℹ️ 清理后不影响应用数据，重新加载即可恢复',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ],
            if (item.type == CacheType.mediaStore) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，媒体库功能需要重新扫描',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.junkScan) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，垃圾清理和回收站提示需要重新扫描',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.appFileList) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，首次打开主页应用文件列表会稍慢',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 在异步操作前获取 ScaffoldMessenger
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isClearing = true;
      _clearingItemName = item.name;
    });

    logger.i('=== START: Clearing ${item.name} (${item.type}) ===');

    bool success = false;
    try {
      success = await widget.cacheManager.clearCache(item.type).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          logger.w('Cache clearing TIMEOUT for ${item.name}');
          return false;
        },
      );
      logger.i('Cache clearing completed, success=$success');
    } catch (e) {
      logger.e('Error clearing cache: $e');
      success = false;
    }

    if (!mounted) return;

    // 针对日志文件特殊优化：清理后直接设置为0，不重新加载
    // 因为重新加载会因为日志写入而显示非0值
    if (success && item.type == CacheType.log) {
      setState(() {
        _isClearing = false;
        _clearingItemName = null;
        // 直接更新日志文件的大小为0
        final logIndex = _cacheItems.indexWhere(
          (i) => i.type == CacheType.log,
        );
        if (logIndex >= 0) {
          _cacheItems[logIndex] = CacheItem(
            name: '日志文件',
            description: '应用运行日志',
            size: 0,
            type: CacheType.log,
          );
          // 更新总大小
          _totalSize = _cacheItems.fold(0, (sum, item) => sum + item.size);
        }
      });
    } else {
      setState(() {
        _isClearing = false;
        _clearingItemName = null;
      });
      // 其他缓存正常重新加载
      await _loadCacheData();
    }

    // 显示结果
    messenger.showSnackBar(
      SnackBar(
        content: Text(success ? '${item.name}已清理' : '清理失败，请重试'),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清理全部缓存'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('确定要清理全部缓存吗？'),
              SizedBox(height: 8),
              Text(
                '将清理以下缓存：',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 8),
              Text(
                '【内容缓存】',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text('• 缩略图、分类扫描、媒体库扫描', style: TextStyle(fontSize: 12)),
              SizedBox(height: 6),
              Text(
                '【功能缓存】',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text('• 大文件查找、重复文件查找、应用管理', style: TextStyle(fontSize: 12)),
              SizedBox(height: 6),
              Text(
                '【用户数据】',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text('• 搜索历史、视频播放记录、日志文件', style: TextStyle(fontSize: 12)),
              SizedBox(height: 10),
              Text(
                '⚠️ 清理后不会删除您的文件，但部分功能需要重新扫描',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isClearing = true;
      _clearingItemName = '全部缓存';
    });

    ClearAllResult? result;
    try {
      result = await widget.cacheManager.clearAllCache().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          logger.w('Clear all cache timeout');
          return ClearAllResult(
            successCount: 0,
            failCount: CacheType.values.length,
            errors: ['操作超时'],
          );
        },
      );
    } catch (e) {
      logger.e('Error clearing all cache: $e');
    }

    if (mounted) {
      setState(() {
        _isClearing = false;
        _clearingItemName = null;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?.message ?? '清理失败，请重试'),
          backgroundColor: result != null && !result.hasError ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );

      // 刷新首页推荐卡片（在显示 SnackBar 后延迟执行，确保页面状态稳定）
      Future.delayed(const Duration(milliseconds: 300), () async {
        try {
          await QuickAccessSection.refreshRecommendations();
          logger.i('✓ Recommendations refreshed after cache clear');
        } catch (e) {
          logger.w('Failed to refresh recommendations: $e');
        }
      });

      // 重新加载缓存数据
      await _loadCacheData();
    }
  }

  IconData _getCacheIcon(CacheType type) {
    switch (type) {
      case CacheType.thumbnail:
        return Icons.image;
      case CacheType.log:
        return Icons.article;
      case CacheType.categoryScan:
        return Icons.analytics;
      case CacheType.searchHistory:
        return Icons.history;
      case CacheType.videoPlayback:
        return Icons.play_circle_outline;
      case CacheType.largeFileScan:
        return Icons.folder_special;
      case CacheType.duplicateFileScan:
        return Icons.content_copy;
      case CacheType.appManagement:
        return Icons.apps;
      case CacheType.mediaStore:
        return Icons.perm_media;
      case CacheType.junkScan:
        return Icons.cleaning_services;
      case CacheType.archivePreview:
        return Icons.folder_zip;
      case CacheType.appFileList:
        return Icons.list_alt;
      case CacheType.archiveList:
        return Icons.archive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('本应用缓存'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    // 缓存项列表
                    Expanded(
                      child: ListView.builder(
                        itemCount: _cacheItems.length,
                        itemBuilder: (context, index) {
                          final item = _cacheItems[index];
                          final isClearing = _isClearing && _clearingItemName == item.name;

                          return ListTile(
                            leading: Icon(
                              _getCacheIcon(item.type),
                              color: colorScheme.primary,
                            ),
                            title: Text(item.name),
                            subtitle: Text(item.description),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.formattedSize,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isClearing)
                                  const SizedBox(
                                    width: 60,
                                    height: 32,
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  )
                                else
                                  OutlinedButton(
                                    onPressed: item.size > 0 && !_isClearing ? () => _clearCache(item) : null,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      minimumSize: const Size(0, 32),
                                    ),
                                    child: const Text('清理', style: TextStyle(fontSize: 13)),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // 底部：总缓存大小和全部清理按钮
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        border: Border(
                          top: BorderSide(color: colorScheme.outlineVariant),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            '总缓存大小',
                            style: TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.cacheManager.formatSize(_totalSize),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _totalSize > 0 && !_isClearing ? _clearAllCache : null,
                            icon: const Icon(Icons.delete_sweep, size: 20),
                            label: const Text('全部清理'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 全部清理时的遮罩层
                if (_isClearing && _clearingItemName == '全部缓存')
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('正在清理全部缓存...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
