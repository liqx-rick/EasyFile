import 'package:easyfile/core/logger.dart';

import 'storage/config_storage.dart';

/// 文件扫描配置
///
/// 符合"强烈值得进Config"原则 2：策略阈值
/// 这些参数影响扫描策略，产品可能会根据用户反馈调整。
class FileScanConfig {
  final ConfigStorage _storage;
  static const String _keyPrefix = 'scan_';

  FileScanConfig(this._storage);

  // ==================== 大文件扫描（策略阈值） ====================

  /// 大文件阈值（MB）
  ///
  /// 产品可能会根据用户反馈调整（30MB? 50MB? 100MB?）
  int get largeFileThreshold => _getInt('large_file_threshold', defaultValue: 50);

  /// 大文件最大结果数（防止过多结果导致卡顿）
  int get largeFileMaxResults => _getInt('large_file_max_results', defaultValue: 300);

  /// 大文件缓存有效期（天）
  ///
  /// 性能优化参数：缓存时间越长，重复扫描越少，但数据时效性越差
  int get largeFileCacheExpiry => _getInt('large_file_cache_days', defaultValue: 7);

  /// 大文件扫描超时时间（秒）
  ///
  /// 性能参数：超时时间太长可能导致 ANR，太短可能扫描不完
  int get largeFileScanTimeout => _getInt('large_file_scan_timeout', defaultValue: 90);

  // ==================== 新文件扫描（策略阈值） ====================

  /// 新文件保留天数（产品策略）
  ///
  /// 可能根据用户习惯调整：3天?7天?15天?
  int get newFilesRetentionDays => _getInt('new_files_retention', defaultValue: 7);

  /// 新文件显示数量（性能与体验的平衡）
  int get newFilesDisplayCount => _getInt('new_files_count', defaultValue: 100);

  /// 新文件缓存过期时长（小时）
  ///
  /// 性能优化参数，可能需要根据用户反馈调整
  int get newFilesCacheExpiry => _getInt('new_files_cache_hours', defaultValue: 1);

  // ==================== 重复文件扫描（策略阈值） ====================

  /// 最小文件大小（字节）
  ///
  /// 太小的文件不参与重复检测（性能考虑），默认100KB
  int get duplicateFileMinSize => _getInt('duplicate_min_size', defaultValue: 102400);

  /// 最小文件大小（KB）- 用于DuplicateFileScanConfig
  int get duplicateFileMinSizeInKB => (duplicateFileMinSize / 1024).round();

  // ==================== 回收站配置（策略阈值） ====================

  /// 回收站默认配置常量
  static const int _defaultTrashRetentionDays = 7;
  static const bool _defaultTrashEnabled = true;

  /// 回收站功能是否启用
  bool get trashEnabled => _getBool('trash_enabled', defaultValue: _defaultTrashEnabled);

  /// 回收站保留天数
  int get trashRetentionDays => _getInt('trash_retention', defaultValue: _defaultTrashRetentionDays);

  /// 可选的回收站保留天数列表（产品策略）
  List<int> get trashRetentionOptions => const [3, 7, 15, 30];

  // ==================== 系统回收站扫描配置 ====================

  /// 系统回收站扫描显示阈值（MB）
  ///
  /// 默认值单位：MB
  /// 只有当系统回收站中的旧文件总大小超过此阈值时，才会显示清理提示
  int get systemTrashScanThresholdMB => _getInt('system_trash_threshold_mb', defaultValue: 10);

  /// 系统回收站扫描缓存有效期（小时）
  ///
  /// 默认值：36小时
  /// 在此时间内不会重复扫描系统回收站，避免频繁IO操作
  int get systemTrashScanCacheHours => _getInt('system_trash_cache_hours', defaultValue: 36);

  /// 系统回收站旧文件判断周期（月）
  ///
  /// 默认值：2个月
  /// 扫描指定月份前的文件作为"旧文件"
  int get systemTrashOldFileMonths => _getInt('system_trash_old_months', defaultValue: 2);

  /// 用户忽略期（天）
  ///
  /// 默认值：7天
  /// 用户点击"不再提示"后的静默期
  int get systemTrashUserDismissDays => _getInt('system_trash_dismiss_days', defaultValue: 7);

  /// 清理抑制期（天）
  ///
  /// 默认值：7天
  /// 清理回收站后的静默期，避免频繁提示
  int get systemTrashCleanSuppressionDays => _getInt('system_trash_suppression_days', defaultValue: 7);

  // ==================== 垃圾文件扫描优化 ====================

  /// 垃圾文件扫描默认深度（层数）
  ///
  /// 默认值：10层
  /// - 适用于大部分普通目录
  /// - 太深可能导致性能问题和扫描时间过长
  int get junkScanDepthDefault => _getInt('junk_scan_depth_default', defaultValue: 10);

  /// 应用数据目录扫描深度（层数）
  ///
  /// 默认值：3层（浅扫描）
  /// - Android/data 等目录包含大量应用子目录
  /// - 浅扫描避免性能问题，且这些目录通常不需要深度清理
  int get junkScanDepthAppData => _getInt('junk_scan_depth_app_data', defaultValue: 3);

  /// 媒体目录扫描深度（层数）
  ///
  /// 默认值：5层（中等深度）
  /// - DCIM、Pictures 等目录用户会创建子文件夹分类
  /// - 中等深度平衡性能和覆盖范围
  int get junkScanDepthMedia => _getInt('junk_scan_depth_media', defaultValue: 5);

  // ==================== 缓存管理 ====================

  /// 智能缓存最大大小（MB）
  ///
  /// 默认值：50MB
  /// - 重复文件扫描的缓存数据可能很大
  /// - 超过此大小的缓存将不会保存，避免占用过多存储空间
  /// - 产品可根据用户设备情况调整
  int get smartCacheMaxSizeMB => _getInt('smart_cache_max_size_mb', defaultValue: 50);

  /// 智能缓存最大大小（字节）
  int get smartCacheMaxSizeBytes => smartCacheMaxSizeMB * 1024 * 1024;

  // ==================== 首页推荐配置（策略阈值） ====================

  /// 推荐应用文件数量阈值
  ///
  /// 应用文件数量大于此阈值时才会显示在首页推荐。
  /// 默认值：5 个文件
  /// 产品可能会根据用户反馈调整此阈值
  int get recommendationFileCountThreshold => _getInt('recommendation_file_count_threshold', defaultValue: 5);

  /// 可选的推荐阈值列表（供UI使用）
  List<int> get recommendationThresholdOptions => const [3, 5, 10, 20, 30, 50, 100, 1000, 3000];

  // ==================== 内部实现 ====================

  int _getInt(String key, {required int defaultValue}) {
    return _storage.getInt('$_keyPrefix$key') ?? defaultValue;
  }

  bool _getBool(String key, {required bool defaultValue}) {
    return _storage.getBool('$_keyPrefix$key') ?? defaultValue;
  }

  Future<void> _setInt(String key, int value) async {
    await _storage.setInt('$_keyPrefix$key', value);
  }

  Future<void> _setBool(String key, bool value) async {
    await _storage.setBool('$_keyPrefix$key', value);
  }

  // ==================== 公开接口 ====================

  /// 修改大文件阈值
  Future<void> setLargeFileThreshold(int thresholdMB) async {
    await _setInt('large_file_threshold', thresholdMB);
    logger.i('Large file threshold set to $thresholdMB MB');
  }

  /// 修改新文件保留天数
  Future<void> setNewFilesRetentionDays(int days) async {
    await _setInt('new_files_retention', days);
    logger.i('New files retention set to $days days');
  }

  /// 修改新文件显示数量
  Future<void> setNewFilesDisplayCount(int count) async {
    await _setInt('new_files_count', count);
    logger.i('New files display count set to $count');
  }

  /// 启用/禁用回收站功能
  Future<void> setTrashEnabled(bool enabled) async {
    await _setBool('trash_enabled', enabled);
    logger.i('Trash enabled set to $enabled');
  }

  /// 修改回收站保留天数
  Future<void> setTrashRetentionDays(int days) async {
    if (!trashRetentionOptions.contains(days)) {
      throw ArgumentError(
        'Invalid trash retention days: $days. '
        'Must be one of: ${trashRetentionOptions.join(", ")}',
      );
    }
    await _setInt('trash_retention', days);
    logger.i('Trash retention set to $days days');
  }

  /// 修改推荐文件数量阈值
  Future<void> setRecommendationFileCountThreshold(int threshold) async {
    if (!recommendationThresholdOptions.contains(threshold)) {
      throw ArgumentError(
        'Invalid recommendation threshold: $threshold. '
        'Must be one of: ${recommendationThresholdOptions.join(", ")}',
      );
    }
    await _setInt('recommendation_file_count_threshold', threshold);
    logger.i('Recommendation file count threshold set to $threshold');
  }

  /// 重置为默认值
  Future<void> reset() async {
    final keys = _storage.getKeys().where((key) => key.startsWith(_keyPrefix)).toList();

    for (final key in keys) {
      await _storage.remove(key);
    }
    logger.i('Reset all file scan configs to defaults');
  }

  /// 批量更新扫描配置（用于远程配置）
  Future<void> mergeWith(Map<String, dynamic> remoteConfig) async {
    try {
      final prefixedData = remoteConfig.map(
        (key, value) => MapEntry('$_keyPrefix$key', value),
      );
      await _storage.setAll(prefixedData);
      logger.i('Merged ${remoteConfig.length} scan configs from remote');
    } catch (e) {
      logger.e('Failed to merge scan configs: $e');
      rethrow;
    }
  }
}
