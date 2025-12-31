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
  int get largeFileThreshold => 
      _getInt('large_file_threshold', defaultValue: 1);

  /// 大文件最大结果数（防止过多结果导致卡顿）
  int get largeFileMaxResults => 
      _getInt('large_file_max_results', defaultValue: 300);

  /// 大文件缓存有效期（天）
  /// 
  /// 性能优化参数：缓存时间越长，重复扫描越少，但数据时效性越差
  int get largeFileCacheExpiry => 
      _getInt('large_file_cache_days', defaultValue: 7);

  /// 大文件扫描超时时间（秒）
  /// 
  /// 性能参数：超时时间太长可能导致 ANR，太短可能扫描不完
  int get largeFileScanTimeout => 
      _getInt('large_file_scan_timeout', defaultValue: 90);

  // ==================== 新文件扫描（策略阈值） ====================

  /// 新文件保留天数（产品策略）
  /// 
  /// 可能根据用户习惯调整：3天?7天?15天?
  int get newFilesRetentionDays => 
      _getInt('new_files_retention', defaultValue: 7);

  /// 新文件显示数量（性能与体验的平衡）
  int get newFilesDisplayCount => 
      _getInt('new_files_count', defaultValue: 100);

  /// 新文件缓存过期时长（小时）
  /// 
  /// 性能优化参数，可能需要根据用户反馈调整
  int get newFilesCacheExpiry => 
      _getInt('new_files_cache_hours', defaultValue: 1);

  // ==================== 重复文件扫描（策略阈值） ====================

  /// 最小文件大小（字节）
  /// 
  /// 太小的文件不参与重复检测（性能考虑），默认100KB
  int get duplicateFileMinSize => 
      _getInt('duplicate_min_size', defaultValue: 102400);

  /// 最小文件大小（KB）- 用于DuplicateFileScanConfig
  int get duplicateFileMinSizeInKB => 
      (duplicateFileMinSize / 1024).round();

  // ==================== 回收站配置（策略阈值） ====================

  /// 回收站默认配置常量
  static const int _defaultTrashRetentionDays = 7;
  static const bool _defaultTrashEnabled = true;

  /// 回收站功能是否启用
  bool get trashEnabled => 
      _getBool('trash_enabled', defaultValue: _defaultTrashEnabled);

  /// 回收站保留天数
  int get trashRetentionDays => 
      _getInt('trash_retention', defaultValue: _defaultTrashRetentionDays);

  /// 可选的回收站保留天数列表（产品策略）
  List<int> get trashRetentionOptions => const [3, 7, 15, 30];

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

  /// 重置为默认值
  Future<void> reset() async {
    final keys = _storage.getKeys()
        .where((key) => key.startsWith(_keyPrefix))
        .toList();
    
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
