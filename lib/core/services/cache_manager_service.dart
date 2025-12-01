import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/thumbnail_cache_manager.dart';
import 'package:easyfile/core/services/category_file_cache_service.dart';
import 'package:easyfile/core/services/search_history_service.dart';
import 'package:easyfile/core/services/large_file_cache_manager.dart';
import 'package:easyfile/core/services/enhanced_duplicate_file_scan_service.dart';

/// 缓存管理服务
/// 统一管理应用中的各种缓存
class CacheManagerService {
  static final CacheManagerService _instance = CacheManagerService._internal();
  factory CacheManagerService() => _instance;
  CacheManagerService._internal();

  final _thumbnailCache = ThumbnailCacheManager();
  final _categoryCache = CategoryFileCacheService();
  final _largeFileCache = LargeFileCacheManager();

  // 重复文件扫描服务（需要外部传入）
  EnhancedDuplicateFileScanService? _duplicateFileScanService;

  /// 设置重复文件扫描服务
  void setDuplicateFileScanService(EnhancedDuplicateFileScanService service) {
    _duplicateFileScanService = service;
  }

  /// 获取所有缓存信息
  Future<List<CacheItem>> getAllCacheItems() async {
    final items = <CacheItem>[];

    // 1. 缩略图缓存
    try {
      final size = await _thumbnailCache.getCacheSize();
      final count = await _thumbnailCache.getCacheCount();
      items.add(CacheItem(
        name: '缩略图缓存',
        description: count > 0 ? '包含 $count 个缓存文件' : '无缓存文件',
        size: size,
        type: CacheType.thumbnail,
      ));
    } catch (e) {
      logger.e('Failed to get thumbnail cache info: $e');
      items.add(CacheItem(
        name: '缩略图缓存',
        description: '获取信息失败',
        size: 0,
        type: CacheType.thumbnail,
      ));
    }

    // 2. 日志文件
    try {
      final size = await logger.getLogSize();
      items.add(CacheItem(
        name: '日志文件',
        description: '应用运行日志',
        size: size,
        type: CacheType.log,
      ));
    } catch (e) {
      logger.e('Failed to get log file info: $e');
      items.add(CacheItem(
        name: '日志文件',
        description: '获取信息失败',
        size: 0,
        type: CacheType.log,
      ));
    }

    // 3. 分类扫描缓存
    try {
      final hasCache = await _categoryCache.hasCache();
      final fileListSize = await _categoryCache.getFileListsCacheSize();
      final totalSize = (hasCache ? 1024 : 0) + fileListSize; // 统计数据1KB + 文件列表

      final description = hasCache
          ? '包含分类统计和文件列表数据${fileListSize > 0 ? "（${_formatSize(fileListSize)}）" : ""}'
          : '无缓存';

      items.add(CacheItem(
        name: '分类扫描缓存',
        description: description,
        size: totalSize,
        type: CacheType.categoryScan,
      ));
    } catch (e) {
      logger.e('Failed to get category cache info: $e');
      items.add(CacheItem(
        name: '分类扫描缓存',
        description: '获取信息失败',
        size: 0,
        type: CacheType.categoryScan,
      ));
    }

    // 4. 搜索历史
    try {
      final history = await SearchHistoryService().getHistory();
      // 估算 SharedPreferences 存储的搜索历史大小
      // 每条记录约 50-100 字节
      final size = history.length * 75;

      items.add(CacheItem(
        name: '搜索历史',
        description:
            history.isNotEmpty ? '包含 ${history.length} 条搜索记录' : '无搜索记录',
        size: size,
        type: CacheType.searchHistory,
      ));
    } catch (e) {
      logger.e('Failed to get search history info: $e');
      items.add(CacheItem(
        name: '搜索历史',
        description: '获取信息失败',
        size: 0,
        type: CacheType.searchHistory,
      ));
    }

    // 5. 视频播放数据
    try {
      final videoDataSize = await _getVideoPlaybackDataSize();
      final count = await _getVideoPlaybackDataCount();

      items.add(CacheItem(
        name: '视频播放数据',
        description: count > 0 ? '包含 $count 个视频的播放记忆' : '无播放记忆',
        size: videoDataSize,
        type: CacheType.videoPlayback,
      ));
    } catch (e) {
      logger.e('Failed to get video playback data info: $e');
      items.add(CacheItem(
        name: '视频播放数据',
        description: '获取信息失败',
        size: 0,
        type: CacheType.videoPlayback,
      ));
    }

    // 6. 大文件扫描缓存
    try {
      final cacheSize = await _largeFileCache.getCacheSize();
      final cache = await _largeFileCache.loadCache();

      final description = cache != null
          ? '包含 ${cache.files.length} 个大文件记录（${cache.formattedAge}）'
          : '无缓存';

      items.add(CacheItem(
        name: '大文件扫描缓存',
        description: description,
        size: cacheSize,
        type: CacheType.largeFileScan,
      ));
    } catch (e) {
      logger.e('Failed to get large file cache info: $e');
      items.add(CacheItem(
        name: '大文件扫描缓存',
        description: '获取信息失败',
        size: 0,
        type: CacheType.largeFileScan,
      ));
    }

    // 7. 重复文件扫描缓存
    try {
      if (_duplicateFileScanService != null) {
        final cacheSize = await _duplicateFileScanService!.getCacheSize();
        final description = cacheSize > 0 ? '包含多个配置的扫描结果缓存' : '无缓存';

        items.add(CacheItem(
          name: '重复文件扫描缓存',
          description: description,
          size: cacheSize,
          type: CacheType.duplicateFileScan,
        ));
      } else {
        // 服务未初始化
        items.add(CacheItem(
          name: '重复文件扫描缓存',
          description: '暂无缓存数据',
          size: 0,
          type: CacheType.duplicateFileScan,
        ));
      }
    } catch (e) {
      logger.e('Failed to get duplicate file cache info: $e');
      items.add(CacheItem(
        name: '重复文件扫描缓存',
        description: '获取信息失败',
        size: 0,
        type: CacheType.duplicateFileScan,
      ));
    }

    return items;
  }

  /// 获取总缓存大小
  Future<int> getTotalCacheSize() async {
    final items = await getAllCacheItems();
    return items.fold<int>(0, (sum, item) => sum + item.size);
  }

  /// 清理指定类型的缓存
  Future<bool> clearCache(CacheType type) async {
    // 对于日志清理，不记录日志避免清理后立即写入
    if (type != CacheType.log) {
      logger.i('>>> clearCache called for type: $type');
    }
    try {
      switch (type) {
        case CacheType.thumbnail:
          await _thumbnailCache.clearCache();
          logger.i('Thumbnail cache cleared');
          return true;

        case CacheType.log:
          await logger.clearLogs();
          // 不记录日志，避免清理后立即写入导致文件不为0
          return true;

        case CacheType.categoryScan:
          await _categoryCache.clearCache();
          logger.i('Category scan cache cleared');
          return true;

        case CacheType.searchHistory:
          // 清理 SharedPreferences 存储的搜索历史
          await SearchHistoryService().clearHistory();
          logger.i('Search history cleared (SharedPreferences)');
          return true;

        case CacheType.videoPlayback:
          logger.i('>>> Entering videoPlayback case');
          await _clearVideoPlaybackData();
          logger.i('>>> Video playback data cleared successfully');
          return true;

        case CacheType.largeFileScan:
          await _largeFileCache.clearCache();
          logger.i('Large file scan cache cleared');
          return true;

        case CacheType.duplicateFileScan:
          if (_duplicateFileScanService != null) {
            await _duplicateFileScanService!.clearAllCaches();
            logger.i('Duplicate file scan cache cleared');
            return true;
          } else {
            logger.w('Duplicate file scan service not initialized');
            return false;
          }
      }
    } catch (e) {
      logger.e('>>> EXCEPTION in clearCache for $type: $e');
      return false;
    }
  }

  /// 清理所有缓存
  Future<ClearAllResult> clearAllCache() async {
    int successCount = 0;
    int failCount = 0;
    final errors = <String>[];

    for (final type in CacheType.values) {
      final success = await clearCache(type);
      if (success) {
        successCount++;
      } else {
        failCount++;
        errors.add(type.displayName);
      }
    }

    return ClearAllResult(
      successCount: successCount,
      failCount: failCount,
      errors: errors,
    );
  }

  /// 格式化文件大小
  String formatSize(int bytes) {
    return _formatSize(bytes);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 获取视频播放数据大小（估算）
  Future<int> _getVideoPlaybackDataSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      int totalSize = 0;
      for (final key in keys) {
        if (key.startsWith('video_position_') ||
            key.startsWith('video_duration_')) {
          // 每个键值对估算：键长度 + 值（int/string，约20-50字节）
          totalSize += key.length * 2 + 40; // UTF-16编码
        }
      }

      return totalSize;
    } catch (e) {
      logger.e('Error calculating video playback data size: $e');
      return 0;
    }
  }

  /// 获取视频播放数据条目数量
  Future<int> _getVideoPlaybackDataCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // 统计唯一视频数量（每个视频可能有position和duration两个键）
      final videoIds = <String>{};
      for (final key in keys) {
        if (key.startsWith('video_position_')) {
          videoIds.add(key.replaceFirst('video_position_', ''));
        } else if (key.startsWith('video_duration_')) {
          videoIds.add(key.replaceFirst('video_duration_', ''));
        }
      }

      return videoIds.length;
    } catch (e) {
      logger.e('Error counting video playback data: $e');
      return 0;
    }
  }

  /// 清理视频播放数据
  Future<void> _clearVideoPlaybackData() async {
    logger.i('>>> [VideoCache] Step 1: Starting _clearVideoPlaybackData');
    try {
      logger.i('>>> [VideoCache] Step 2: Getting SharedPreferences instance');
      final prefs = await SharedPreferences.getInstance();

      logger.i('>>> [VideoCache] Step 3: Getting all keys');
      final keys = prefs.getKeys();
      logger.i(
          '>>> [VideoCache] Step 3a: Total keys in SharedPreferences: ${keys.length}');

      // 收集需要删除的键
      logger.i('>>> [VideoCache] Step 4: Collecting keys to remove');
      final keysToRemove = <String>[];
      for (final key in keys) {
        if (key.startsWith('video_position_') ||
            key.startsWith('video_duration_')) {
          keysToRemove.add(key);
        }
      }

      logger.i(
          '>>> [VideoCache] Step 5: Found ${keysToRemove.length} video playback data entries to remove');

      if (keysToRemove.isEmpty) {
        logger.i('>>> [VideoCache] Step 6: No keys to remove, returning');
        return;
      }

      // 批量删除（添加超时保护）
      logger.i('>>> [VideoCache] Step 7: Starting batch removal with timeout');
      await Future.wait(
        keysToRemove.map((key) => prefs.remove(key)),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          logger.w(
              '>>> [VideoCache] Step 7 TIMEOUT: Video playback data clearing timeout after 10s');
          return [];
        },
      );

      logger.i(
          '>>> [VideoCache] Step 8: Completed removing video playback data successfully');
    } catch (e, stackTrace) {
      logger.e('>>> [VideoCache] ERROR in _clearVideoPlaybackData: $e');
      logger.e('>>> [VideoCache] StackTrace: $stackTrace');
      // 不要 rethrow，让它继续执行
    }
    logger.i('>>> [VideoCache] Step 9: Exiting _clearVideoPlaybackData');
  }
}

/// 缓存类型
enum CacheType {
  thumbnail,
  log,
  categoryScan,
  searchHistory,
  videoPlayback,
  largeFileScan, // 大文件扫描缓存
  duplicateFileScan, // 重复文件扫描缓存
}

extension CacheTypeExtension on CacheType {
  String get displayName {
    switch (this) {
      case CacheType.thumbnail:
        return '缩略图缓存';
      case CacheType.log:
        return '日志文件';
      case CacheType.categoryScan:
        return '分类扫描缓存';
      case CacheType.searchHistory:
        return '搜索历史';
      case CacheType.videoPlayback:
        return '视频播放数据';
      case CacheType.largeFileScan:
        return '大文件扫描缓存';
      case CacheType.duplicateFileScan:
        return '重复文件扫描缓存';
    }
  }
}

/// 缓存项信息
class CacheItem {
  final String name;
  final String description;
  final int size;
  final CacheType type;

  CacheItem({
    required this.name,
    required this.description,
    required this.size,
    required this.type,
  });

  String get formattedSize {
    return CacheManagerService().formatSize(size);
  }
}

/// 清理所有缓存的结果
class ClearAllResult {
  final int successCount;
  final int failCount;
  final List<String> errors;

  ClearAllResult({
    required this.successCount,
    required this.failCount,
    required this.errors,
  });

  bool get hasError => failCount > 0;

  String get message {
    if (failCount == 0) {
      return '已清理 $successCount 项缓存';
    } else {
      return '已清理 $successCount 项，$failCount 项失败';
    }
  }
}
