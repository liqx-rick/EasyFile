import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/cache_manager_service.dart';

/// 缓存管理页面
/// 
/// 用于查看和清理应用的各类缓存数据，包括：
/// - 缩略图缓存
/// - 日志文件
/// - 分类扫描缓存
/// - 搜索历史
/// - 视频播放数据
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
                '⚠️ 清理后，视频和音频缩略图将在下次浏览时重新生成',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.categoryScan) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，下次打开分类页面（图片、视频等）时需要重新扫描',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.searchHistory) ...[
              const SizedBox(height: 8),
              const Text(
                'ℹ️ 将删除所有搜索历史记录，清理后可重新积累',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ],
            if (item.type == CacheType.videoPlayback) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，所有视频将从头播放，需重新读取视频时长',
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

    if (mounted) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '${item.name}已清理' : '清理失败，请重试'),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    logger.i('=== END: Clearing ${item.name} ===');
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清理全部缓存'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要清理全部缓存吗？'),
            SizedBox(height: 8),
            Text(
              '这将清理以下内容：',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            Text('• 视频和音频缩略图', style: TextStyle(fontSize: 13)),
            Text('• 应用日志文件', style: TextStyle(fontSize: 13)),
            Text('• 分类统计和文件列表', style: TextStyle(fontSize: 13)),
            Text('• 搜索历史记录', style: TextStyle(fontSize: 13)),
            Text('• 视频播放数据', style: TextStyle(fontSize: 13)),
            SizedBox(height: 8),
            Text(
              '⚠️ 缩略图和文件列表将重新生成，视频将从头播放',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?.message ?? '清理失败，请重试'),
          backgroundColor:
              result != null && !result.hasError ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );

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
                          final isClearing =
                              _isClearing && _clearingItemName == item.name;

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
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    ),
                                  )
                                else
                                  OutlinedButton(
                                    onPressed: item.size > 0 && !_isClearing
                                        ? () => _clearCache(item)
                                        : null,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      minimumSize: const Size(0, 32),
                                    ),
                                    child: const Text('清理',
                                        style: TextStyle(fontSize: 13)),
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
                            onPressed: _totalSize > 0 && !_isClearing
                                ? _clearAllCache
                                : null,
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
