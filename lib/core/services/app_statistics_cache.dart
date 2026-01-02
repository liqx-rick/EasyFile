import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';

/// 应用统计数据模型
class AppStatistics {
  /// 缓存版本号（用于标识统计逻辑的变更）
  /// 
  /// 版本历史：
  /// - v1 (2025-01-01): 初始版本，未应用 FileTypesConfig 过滤
  /// - v2 (2026-01-01): 应用 FileTypesConfig 过滤，只统计支持的文件类型
  static const int currentVersion = 2;
  
  /// 此缓存数据的版本号
  final int version;
  
  /// 文件数量
  final int fileCount;
  
  /// 总大小（字节）
  final int totalSize;
  
  /// 本周新增数量
  /// 
  /// 注意：当前 UI 未使用此字段，保留供将来可能的趋势展示功能使用。
  final int weeklyGrowth;
  
  /// 缓存时间
  final DateTime cachedAt;

  AppStatistics({
    this.version = currentVersion,
    required this.fileCount,
    required this.totalSize,
    required this.weeklyGrowth,
    required this.cachedAt,
  });

  /// 从JSON反序列化
  factory AppStatistics.fromJson(Map<String, dynamic> json) {
    return AppStatistics(
      version: json['version'] as int? ?? 1, // 旧缓存默认为 v1
      fileCount: json['fileCount'] as int,
      totalSize: json['totalSize'] as int,
      weeklyGrowth: json['weeklyGrowth'] as int,
      cachedAt: DateTime.fromMillisecondsSinceEpoch(json['cachedAt'] as int),
    );
  }

  /// 序列化为JSON
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'fileCount': fileCount,
      'totalSize': totalSize,
      'weeklyGrowth': weeklyGrowth,
      'cachedAt': cachedAt.millisecondsSinceEpoch,
    };
  }

  /// 检查缓存是否有效
  /// 
  /// 检查条件：
  /// 1. 版本号必须与当前版本一致
  /// 2. 缓存未过期
  bool isValid(Duration cacheDuration) {
    // 版本不匹配，缓存失效
    if (version != currentVersion) {
      return false;
    }
    
    // 检查时间是否过期
    final age = DateTime.now().difference(cachedAt);
    return age < cacheDuration;
  }
}

/// 应用统计数据缓存服务
/// 
/// 缓存内容：
/// - 文件数量 (fileCount)
/// - 总大小 (totalSize)
/// - 本周新增 (weeklyGrowth)
/// 
/// 缓存策略：
/// - 有效期：6小时（与文件数量缓存一致）
/// - 存储方式：SharedPreferences 持久化
/// - 自动失效：超过有效期后重新扫描
/// 
/// 使用示例：
/// ```dart
/// final cache = AppStatisticsCache();
/// await cache.initialize();
/// 
/// // 获取缓存
/// final stats = await cache.get('wechat');
/// if (stats != null && stats.isValid(cache.cacheDuration)) {
///   print('文件数: ${stats.fileCount}');
///   print('总大小: ${stats.totalSize}');
/// }
/// 
/// // 设置缓存
/// final newStats = AppStatistics(
///   fileCount: 100,
///   totalSize: 1234567890,
///   weeklyGrowth: 10,
///   cachedAt: DateTime.now(),
/// );
/// await cache.set('wechat', newStats);
/// ```
class AppStatisticsCache {
  /// SharedPreferences 实例
  SharedPreferences? _prefs;

  /// 缓存键前缀
  static const _cacheKeyPrefix = 'app_statistics_';

  /// 缓存有效期（6小时）
  static const cacheDuration = Duration(hours: 6);

  /// 是否已初始化
  bool _initialized = false;

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    logger.i('初始化应用统计数据缓存服务...');
    try {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      logger.i('✓ 应用统计数据缓存服务初始化完成');
    } catch (e) {
      logger.e('✗ 初始化失败: $e');
      _initialized = true;
    }
  }

  /// 获取缓存的统计数据
  /// 
  /// [appKey] 应用Key，如 'wechat'
  /// 返回统计数据，如果缓存不存在或已过期则返回 null
  Future<AppStatistics?> get(String appKey) async {
    if (!_initialized) await initialize();
    if (_prefs == null) return null;

    final cacheKey = '$_cacheKeyPrefix$appKey';

    if (!_prefs!.containsKey(cacheKey)) {
      logger.d('统计缓存不存在: $appKey');
      return null;
    }

    try {
      final jsonStr = _prefs!.getString(cacheKey);
      if (jsonStr == null) return null;

      final json = Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
      final stats = AppStatistics.fromJson(json);

      // 检查是否过期或版本不匹配
      if (!stats.isValid(cacheDuration)) {
        if (stats.version != AppStatistics.currentVersion) {
          logger.d('统计缓存版本不匹配: $appKey (缓存版本: v${stats.version}, 当前版本: v${AppStatistics.currentVersion})');
        } else {
          logger.d('统计缓存已过期: $appKey (${DateTime.now().difference(stats.cachedAt).inHours}小时)');
        }
        return null;
      }

      logger.d('统计缓存命中: $appKey (v${stats.version}, 文件数: ${stats.fileCount}, 大小: ${_formatSize(stats.totalSize)}, ${DateTime.now().difference(stats.cachedAt).inMinutes}分钟前)');
      return stats;
    } catch (e) {
      logger.e('读取统计缓存失败: $appKey, 错误: $e');
      return null;
    }
  }

  /// 设置统计数据缓存
  /// 
  /// [appKey] 应用Key
  /// [stats] 统计数据
  Future<void> set(String appKey, AppStatistics stats) async {
    if (!_initialized) await initialize();
    if (_prefs == null) return;

    final cacheKey = '$_cacheKeyPrefix$appKey';

    try {
      final jsonStr = jsonEncode(stats.toJson());
      await _prefs!.setString(cacheKey, jsonStr);

      logger.d('统计缓存已更新: $appKey (文件数: ${stats.fileCount}, 大小: ${_formatSize(stats.totalSize)}, 本周新增: ${stats.weeklyGrowth})');
    } catch (e) {
      logger.e('保存统计缓存失败: $appKey, 错误: $e');
    }
  }

  /// 清除特定应用的缓存
  Future<void> clear(String appKey) async {
    if (!_initialized) await initialize();
    if (_prefs == null) return;

    final cacheKey = '$_cacheKeyPrefix$appKey';
    await _prefs!.remove(cacheKey);

    logger.d('统计缓存已清除: $appKey');
  }

  /// 清除所有缓存
  Future<void> clearAll() async {
    if (!_initialized) await initialize();
    if (_prefs == null) return;

    final keys = _prefs!.getKeys();
    int removedCount = 0;

    for (final key in keys) {
      if (key.startsWith(_cacheKeyPrefix)) {
        await _prefs!.remove(key);
        removedCount++;
      }
    }

    logger.i('已清除所有统计缓存: $removedCount 个键');
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    if (_prefs == null) {
      return {'initialized': false};
    }

    final keys = _prefs!.getKeys();
    final cacheKeys = keys.where((k) => k.startsWith(_cacheKeyPrefix)).toList();

    int validCount = 0;
    int expiredCount = 0;

    for (final key in cacheKeys) {
      try {
        final jsonStr = _prefs!.getString(key);
        if (jsonStr != null) {
          final json = jsonDecode(jsonStr) as Map;
          final stats = AppStatistics.fromJson(Map<String, dynamic>.from(json));
          
          if (stats.isValid(cacheDuration)) {
            validCount++;
          } else {
            expiredCount++;
          }
        }
      } catch (e) {
        expiredCount++;
      }
    }

    return {
      'initialized': _initialized,
      'totalCacheKeys': cacheKeys.length,
      'validCacheCount': validCount,
      'expiredCacheCount': expiredCount,
      'cacheDurationHours': cacheDuration.inHours,
    };
  }

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}
