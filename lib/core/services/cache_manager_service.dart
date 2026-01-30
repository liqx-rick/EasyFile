import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/app_file_list_cache.dart';
import 'package:easyfile/core/services/archive_preview_cache_manager.dart';
import 'package:easyfile/core/services/category_file_cache_service.dart';
import 'package:easyfile/core/services/enhanced_duplicate_file_scan_service.dart';
import 'package:easyfile/core/services/junk_file_cache_manager.dart';
import 'package:easyfile/core/services/large_file_cache_manager.dart';
import 'package:easyfile/core/services/mediastore_cache_service.dart';
import 'package:easyfile/core/services/search_history_service.dart';
import 'package:easyfile/core/services/trash_file_service.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/utils/thumbnail_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 缓存管理服务
///
/// 统一管理应用中的各种缓存，支持以下类型：
/// - 缩略图缓存（视频/音频）
/// - 日志文件
/// - 分类扫描缓存（图片/视频等分类统计）
/// - 搜索历史记录
/// - 视频播放数据（播放进度和时长）
/// - 大文件扫描缓存
/// - 重复文件扫描缓存
/// - 应用管理缓存（应用存储/统计/文件数量/检测）
/// - 媒体库扫描缓存（相机照片/视频/录音）
/// - 垃圾文件扫描缓存（垃圾文件清理+系统回收站扫描）
class CacheManagerService {
  static final CacheManagerService _instance = CacheManagerService._internal();
  factory CacheManagerService() => _instance;
  CacheManagerService._internal();

  final _thumbnailCache = ThumbnailCacheManager();
  final _categoryCache = CategoryFileCacheService();
  final _largeFileCache = LargeFileCacheManager();
  final _appFileListCache = AppFileListCache();

  // MediaStore缓存服务
  final _mediaStoreCache = MediaStoreCacheService();

  // 垃圾文件缓存管理器
  final _junkFileCache = JunkFileCacheManager();

  // 重复文件扫描服务（需要外部传入）
  EnhancedDuplicateFileScanService? _duplicateFileScanService;

  // 系统回收站扫描服务（需要外部传入）
  TrashFileService? _trashFileService;

  // 统一应用扫描器（需要外部传入）
  UnifiedAppScanner? _appScanner;

  /// 设置重复文件扫描服务
  void setDuplicateFileScanService(EnhancedDuplicateFileScanService service) {
    _duplicateFileScanService = service;
  }

  /// 设置系统回收站服务
  void setTrashFileService(TrashFileService service) {
    _trashFileService = service;
  }

  /// 设置统一应用扫描器
  void setAppScanner(UnifiedAppScanner scanner) {
    _appScanner = scanner;
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

      final description = hasCache ? '包含分类统计和文件列表数据${fileListSize > 0 ? "（${_formatSize(fileListSize)}）" : ""}' : '无缓存';

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
        description: history.isNotEmpty ? '包含 ${history.length} 条搜索记录' : '无搜索记录',
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

      final description = cache != null ? '包含 ${cache.files.length} 个大文件记录（${cache.formattedAge}）' : '无缓存';

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

    // 8. 应用管理缓存
    try {
      final appMgmtSize = await _getAppManagementCacheSize();
      final description = appMgmtSize > 0 ? '包含应用存储、统计、文件数量及检测缓存' : '无缓存';

      items.add(CacheItem(
        name: '应用管理缓存',
        description: description,
        size: appMgmtSize,
        type: CacheType.appManagement,
      ));
    } catch (e) {
      logger.e('Failed to get app management cache info: $e');
      items.add(CacheItem(
        name: '应用管理缓存',
        description: '获取信息失败',
        size: 0,
        type: CacheType.appManagement,
      ));
    }

    // 9. 媒体库扫描缓存
    try {
      final mediaStoreSize = await _getMediaStoreCacheSize();
      final description = mediaStoreSize > 0 ? '包含照片、视频、录音的扫描索引' : '无缓存';

      items.add(CacheItem(
        name: '媒体库扫描缓存',
        description: description,
        size: mediaStoreSize,
        type: CacheType.mediaStore,
      ));
    } catch (e) {
      logger.e('Failed to get MediaStore cache info: $e');
      items.add(CacheItem(
        name: '媒体库扫描缓存',
        description: '获取信息失败',
        size: 0,
        type: CacheType.mediaStore,
      ));
    }

    // 10. 垃圾文件扫描缓存（包含垃圾文件清理+系统回收站扫描）
    try {
      // 获取垃圾文件缓存信息
      final junkCacheInfo = await _junkFileCache.getCacheInfo();
      final junkExists = junkCacheInfo['exists'] as bool;
      final junkFileCount = junkCacheInfo['fileCount'] as int? ?? 0;
      final junkTimestamp = junkCacheInfo['timestamp'] as DateTime?;

      // 获取回收站缓存信息
      int trashFileCount = 0;
      DateTime? trashTimestamp;
      if (_trashFileService != null) {
        final trashCacheInfo = _trashFileService!.getCacheInfo();
        final hasTrashCache = trashCacheInfo['hasCache'] as bool? ?? false;
        if (hasTrashCache) {
          trashFileCount = trashCacheInfo['fileCount'] as int? ?? 0;
          trashTimestamp = trashCacheInfo['cacheTime'] as DateTime?;
        }
      }

      // 计算总缓存大小（估算）
      final junkCacheSize = junkFileCount * 150; // 垃圾文件元数据约150字节
      final trashCacheSize = trashFileCount * 200; // 回收站文件元数据约200字节
      final totalSize = junkCacheSize + trashCacheSize;

      // 构建描述信息
      final parts = <String>[];
      if (junkExists && junkFileCount > 0) {
        parts.add('垃圾文件 $junkFileCount 个');
      }
      if (trashFileCount > 0) {
        parts.add('回收站 $trashFileCount 个');
      }

      String description;
      if (parts.isEmpty) {
        description = '无缓存';
      } else {
        // 使用最新的时间戳
        DateTime? latestTime;
        if (junkTimestamp != null && trashTimestamp != null) {
          latestTime = junkTimestamp.isAfter(trashTimestamp) ? junkTimestamp : trashTimestamp;
        } else {
          latestTime = junkTimestamp ?? trashTimestamp;
        }

        String timeAgo = '';
        if (latestTime != null) {
          final duration = DateTime.now().difference(latestTime);
          if (duration.inMinutes < 60) {
            timeAgo = '${duration.inMinutes}分钟前';
          } else if (duration.inHours < 24) {
            timeAgo = '${duration.inHours}小时前';
          } else {
            timeAgo = '${duration.inDays}天前';
          }
          timeAgo = '，$timeAgo 扫描';
        }

        description = '${parts.join('、')}$timeAgo';
      }

      items.add(CacheItem(
        name: '垃圾文件扫描缓存',
        description: description,
        size: totalSize,
        type: CacheType.junkScan,
      ));
    } catch (e) {
      logger.e('Failed to get junk scan cache info: $e');
      items.add(CacheItem(
        name: '垃圾文件扫描缓存',
        description: '获取信息失败',
        size: 0,
        type: CacheType.junkScan,
      ));
    }

    // 11. 压缩包预览缓存
    try {
      final size = await ArchivePreviewCacheManager.getCacheSize();
      items.add(CacheItem(
        name: '压缩包预览缓存',
        description: size > 0 ? '临时提取的预览文件' : '无缓存',
        size: size,
        type: CacheType.archivePreview,
      ));
    } catch (e) {
      logger.e('Failed to get archive preview cache info: $e');
      items.add(CacheItem(
        name: '压缩包预览缓存',
        description: '获取信息失败',
        size: 0,
        type: CacheType.archivePreview,
      ));
    }

    // 12. 应用文件列表缓存
    try {
      final appFileListSize = await _getAppFileListCacheSize();
      final appCount = await _getAppFileListCacheCount();
      final description = appCount > 0 ? '包含 $appCount 个应用的文件列表缓存' : '无缓存';

      items.add(CacheItem(
        name: '应用文件列表缓存',
        description: description,
        size: appFileListSize,
        type: CacheType.appFileList,
      ));
    } catch (e) {
      logger.e('Failed to get app file list cache info: $e');
      items.add(CacheItem(
        name: '应用文件列表缓存',
        description: '获取信息失败',
        size: 0,
        type: CacheType.appFileList,
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

        case CacheType.appManagement:
          final result = await _clearAppManagementCache();
          logger.i('App management cache cleared: $result');
          return result;

        case CacheType.mediaStore:
          final result = await _clearMediaStoreCache();
          logger.i('MediaStore cache cleared: $result');
          return result;

        case CacheType.junkScan:
          // 清理垃圾文件缓存
          await _junkFileCache.clearCache();
          logger.i('Junk file cache cleared');

          // 清理回收站缓存
          if (_trashFileService != null) {
            await _trashFileService!.clearCache(keepSuppressionPeriods: false);
            logger.i('Trash scan cache cleared');
          } else {
            logger.w('Trash file service not initialized');
          }
          return true;

        case CacheType.archivePreview:
          await ArchivePreviewCacheManager.clearAllCache();
          logger.i('Archive preview cache cleared');
          return true;

        case CacheType.appFileList:
          await _appFileListCache.initialize();
          await _appFileListCache.clearAllCache();
          logger.i('所有应用文件列表缓存已清除（SharedPreferences）');

          // 同时清除内存缓存
          UnifiedAppScanner? scanner = _appScanner;
          if (scanner == null) {
            // 尝试从locator获取
            try {
              scanner = await locator.getAsync<UnifiedAppScanner>();
              logger.d('从locator获取到UnifiedAppScanner实例');
            } catch (e) {
              logger.w('无法获取UnifiedAppScanner: $e');
            }
          }

          if (scanner != null) {
            scanner.clearMemoryCache();
            logger.i('所有应用文件列表内存缓存已清除');
          } else {
            logger.w('UnifiedAppScanner未初始化，跳过内存缓存清理');
          }

          logger.i('App file list cache cleared');
          return true;
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
        if (key.startsWith('video_position_') || key.startsWith('video_duration_')) {
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
      logger.i('>>> [VideoCache] Step 3a: Total keys in SharedPreferences: ${keys.length}');

      // 收集需要删除的键
      logger.i('>>> [VideoCache] Step 4: Collecting keys to remove');
      final keysToRemove = <String>[];
      for (final key in keys) {
        if (key.startsWith('video_position_') || key.startsWith('video_duration_')) {
          keysToRemove.add(key);
        }
      }

      logger.i('>>> [VideoCache] Step 5: Found ${keysToRemove.length} video playback data entries to remove');

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
          logger.w('>>> [VideoCache] Step 7 TIMEOUT: Video playback data clearing timeout after 10s');
          return [];
        },
      );

      logger.i('>>> [VideoCache] Step 8: Completed removing video playback data successfully');
    } catch (e, stackTrace) {
      logger.e('>>> [VideoCache] ERROR in _clearVideoPlaybackData: $e');
      logger.e('>>> [VideoCache] StackTrace: $stackTrace');
      // 不要 rethrow，让它继续执行
    }
    logger.i('>>> [VideoCache] Step 9: Exiting _clearVideoPlaybackData');
  }

  /// 获取应用管理缓存大小（估算）
  /// 包含3个服务的缓存：AppStorageCacheManager、FileCountCache、AppDetectionService
  Future<int> _getAppManagementCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      int totalSize = 0;
      int count = 0;

      // 统计所有应用管理相关的键
      for (final key in keys) {
        if (key.startsWith('app_storage_') || // AppStorageCacheManager
            key.startsWith('file_count_') || // FileCountCache (count)
            key.startsWith('file_count_time_') || // FileCountCache (time)
            key.startsWith('app_installed_') || // AppDetectionService
            key.startsWith('app_list_cache_')) {
          // AppListCacheManager（新增）
          count++;
          // 估算每个键值对大小：键长度 + 值（JSON/int，约200-500字节）
          // 应用列表缓存可能较大（含图标），估算为1-5MB
          final estimatedSize = key.startsWith('app_list_cache_') && !key.contains('_time_')
              ? 2 * 1024 * 1024 // 应用列表缓存：约2MB
              : 300; // 其他缓存：约300字节
          totalSize += key.length * 2 + estimatedSize; // UTF-16编码
        }
      }

      logger.d('App management cache: $count keys, estimated size: ${_formatSize(totalSize)}');
      return totalSize;
    } catch (e) {
      logger.e('Error calculating app management cache size: $e');
      return 0;
    }
  }

  /// 清理应用管理缓存
  ///
  /// 优化：批量并行删除，避免串行等待
  /// 问题根源：原实现使用 `for + await remove()`，184个键串行删除需10+秒
  /// 解决方案：使用 `Future.wait()` 批量并行删除，耗时约1-2秒
  ///
  /// 包含的缓存类型：
  /// - app_storage_*: AppStorageCacheManager（应用存储信息）
  /// - app_statistics_*: AppStatisticsCache（应用统计数据）
  /// - file_count_*: FileCountCache（文件数量缓存）
  /// - file_count_time_*: FileCountCache（文件数量时间戳）
  /// - app_installed_*: AppDetectionService（应用检测缓存）
  /// - app_list_cache_*: AppListCacheManager（应用列表缓存，含图标）
  Future<bool> _clearAppManagementCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      // 收集所有需要删除的键
      final keysToRemove = allKeys
          .where((key) =>
                  key.startsWith('app_storage_') || // AppStorageCacheManager
                  key.startsWith('file_count_') || // FileCountCache (count)
                  key.startsWith('file_count_time_') || // FileCountCache (time)
                  key.startsWith('app_installed_') || // AppDetectionService
                  key.startsWith('app_list_cache_') // AppListCacheManager
              )
          .toList();

      if (keysToRemove.isEmpty) {
        logger.i('App management cache: no keys to remove');
        return true;
      }

      logger.i('App management cache: batch deleting ${keysToRemove.length} keys...');

      // ⚡ 优化：使用clear()然后重建非应用管理的键（如果需要保留其他缓存）
      // 或者直接逐个删除但使用更高效的方式
      // 方案：收集所有要保留的键值对，clear()后重建

      // 收集要保留的键值对
      final keysToKeep = allKeys.where((key) => !keysToRemove.contains(key)).toList();
      final preservedData = <String, dynamic>{};
      for (final key in keysToKeep) {
        final value = prefs.get(key);
        if (value != null) {
          preservedData[key] = value;
        }
      }

      // 清空所有数据
      await prefs.clear();

      // 重建保留的数据
      for (final entry in preservedData.entries) {
        final value = entry.value;
        if (value is bool) {
          await prefs.setBool(entry.key, value);
        } else if (value is int) {
          await prefs.setInt(entry.key, value);
        } else if (value is double) {
          await prefs.setDouble(entry.key, value);
        } else if (value is String) {
          await prefs.setString(entry.key, value);
        } else if (value is List<String>) {
          await prefs.setStringList(entry.key, value);
        }
      }

      logger
          .i('App management cache cleared: ${keysToRemove.length} keys removed (${keysToKeep.length} keys preserved)');
      return true;
    } catch (e) {
      logger.e('Failed to clear app management cache: $e');
      return false;
    }
  }

  /// 获取MediaStore缓存大小（估算）
  /// 包含相机照片、相机视频、录音文件的扫描索引
  Future<int> _getMediaStoreCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      int totalSize = 0;
      int count = 0;

      // 统计所有MediaStore相关的键
      for (final key in keys) {
        if (key.startsWith('mediastore_cache_') ||
            key.startsWith('mediastore_cache_time_') ||
            key.startsWith('mediastore_cache_count_')) {
          count++;
          // 估算每个键值对大小：键长度 + 值（JSON/int，约200-1000字节）
          totalSize += key.length * 2 + 500; // UTF-16编码
        }
      }

      logger.d('MediaStore cache: $count keys, estimated size: ${_formatSize(totalSize)}');
      return totalSize;
    } catch (e) {
      logger.e('Error calculating MediaStore cache size: $e');
      return 0;
    }
  }

  /// 清理MediaStore缓存
  ///
  /// 清理所有媒体库扫描缓存（相机照片、相机视频、录音文件）
  /// 使用MediaStoreCacheService的clearAllCache()方法
  Future<bool> _clearMediaStoreCache() async {
    try {
      await _mediaStoreCache.initialize();
      await _mediaStoreCache.clearAllCache();
      logger.i('MediaStore cache cleared successfully');
      return true;
    } catch (e) {
      logger.e('Failed to clear MediaStore cache: $e');
      return false;
    }
  }

  /// 获取应用文件列表缓存大小
  Future<int> _getAppFileListCacheSize() async {
    try {
      await _appFileListCache.initialize();
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final appCacheKeys = keys.where((key) => key.startsWith('app_file_list_'));

      int totalSize = 0;
      for (final key in appCacheKeys) {
        final value = prefs.getString(key);
        if (value != null) {
          // 估算JSON字符串大小（UTF-8编码）
          totalSize += value.length;
        }
      }

      return totalSize;
    } catch (e) {
      logger.e('Failed to get app file list cache size: $e');
      return 0;
    }
  }

  /// 获取应用文件列表缓存的应用数量
  Future<int> _getAppFileListCacheCount() async {
    try {
      await _appFileListCache.initialize();
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      return keys.where((key) => key.startsWith('app_file_list_')).length;
    } catch (e) {
      logger.e('Failed to get app file list cache count: $e');
      return 0;
    }
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
  appManagement, // 应用管理缓存（存储、统计、文件数量、检测）
  mediaStore, // 媒体库扫描缓存（照片、视频、录音）
  junkScan, // 垃圾文件扫描缓存（垃圾文件清理+系统回收站扫描）
  archivePreview, // 压缩包预览缓存
  appFileList, // 应用文件列表缓存（微信/QQ等应用的完整文件列表）
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
      case CacheType.appManagement:
        return '应用管理缓存';
      case CacheType.mediaStore:
        return '媒体库扫描缓存';
      case CacheType.junkScan:
        return '垃圾文件扫描缓存';
      case CacheType.archivePreview:
        return '压缩包预览缓存';
      case CacheType.appFileList:
        return '应用文件列表缓存';
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
