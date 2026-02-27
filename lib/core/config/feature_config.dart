import 'package:easyfile/core/logger.dart';

import 'storage/config_storage.dart';

/// 功能开关配置
///
/// 符合"强烈值得进Config"原则 1：功能是否存在（Feature Toggle）
/// 用于灰度发布、AB Test、风险控制。
class FeatureConfig {
  final ConfigStorage _storage;
  static const String _keyPrefix = 'feature_';

  FeatureConfig(this._storage);

  // ==================== 核心功能开关 ====================

  /// 新文件扫描功能
  bool get isNewFilesEnabled => _getBool('new_files', defaultValue: true);

  /// 大文件扫描功能
  bool get isLargeFilesEnabled => _getBool('large_files', defaultValue: true);

  /// 重复文件扫描功能
  bool get isDuplicateFilesEnabled => _getBool('duplicate_files', defaultValue: true);

  /// 垃圾文件清理功能
  bool get isJunkCleanupEnabled => _getBool('junk_cleanup', defaultValue: true);

  /// 应用管理功能
  bool get isAppManagementEnabled => _getBool('app_management', defaultValue: true);

  /// 回收站功能
  bool get isTrashEnabled => _getBool('trash', defaultValue: true);

  /// 收藏功能
  bool get isFavoritesEnabled => _getBool('favorites', defaultValue: true);

  /// 压缩包管理功能
  bool get isArchiveManagementEnabled => _getBool('archive_management', defaultValue: true);

  /// 安装包管理功能
  bool get isApkManagementEnabled => _getBool('apk_management', defaultValue: true);

  /// 隐私空间功能
  bool get isPrivacySpaceEnabled => _getBool('privacy_space', defaultValue: true);

  // ==================== 实验性功能（预留，默认禁用） ====================

  /// 云同步功能（未来）
  bool get isCloudSyncEnabled => _getBool('cloud_sync', defaultValue: false);

  /// 会员功能（未来）
  bool get isPremiumEnabled => _getBool('premium', defaultValue: false);

  /// 开发者选项显示开关（默认隐藏）
  bool get isDeveloperOptionsEnabled => _getBool('developer_options', defaultValue: true);

  // ==================== 内部实现 ====================

  bool _getBool(String key, {required bool defaultValue}) {
    final fullKey = '$_keyPrefix$key';
    return _storage.getBool(fullKey) ?? defaultValue;
  }

  Future<void> _setBool(String key, bool value) async {
    final fullKey = '$_keyPrefix$key';
    await _storage.setBool(fullKey, value);
  }

  // ==================== 公开接口 ====================

  /// 动态设置功能开关（用于灰度发布）
  Future<void> setFeature(String key, {required bool enabled}) async {
    try {
      await _setBool(key, enabled);
      logger.i('Feature "$key" set to $enabled');
    } catch (e) {
      logger.e('Failed to set feature "$key": $e');
      rethrow;
    }
  }

  /// 批量更新功能开关（用于远程配置）
  Future<void> mergeWith(Map<String, bool> remoteFlags) async {
    try {
      final prefixedData = remoteFlags.map(
        (key, value) => MapEntry('$_keyPrefix$key', value),
      );
      await _storage.setAll(prefixedData);
      logger.i('Merged ${remoteFlags.length} feature flags from remote');
    } catch (e) {
      logger.e('Failed to merge feature flags: $e');
      rethrow;
    }
  }

  /// 重置所有功能开关为默认值
  Future<void> reset() async {
    try {
      final keys = _storage.getKeys().where((key) => key.startsWith(_keyPrefix)).toList();

      for (final key in keys) {
        await _storage.remove(key);
      }
      logger.i('Reset all feature flags to defaults');
    } catch (e) {
      logger.e('Failed to reset feature flags: $e');
      rethrow;
    }
  }
}
