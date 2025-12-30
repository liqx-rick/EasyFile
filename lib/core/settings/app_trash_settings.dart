import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';

/// EasyFile回收站配置管理
///
/// 管理回收站相关的用户设置
class AppTrashSettings {
  // SharedPreferences键名
  static const String _keyEnabled = 'app_trash_enabled';
  static const String _keyRetentionDays = 'app_trash_retention_days';
  static const String _keyShowUndo = 'app_trash_show_undo';
  static const String _keyUndoDuration = 'app_trash_undo_duration';

  // 默认值
  static const bool _defaultEnabled = true;
  static const int _defaultRetentionDays = 7;
  static const bool _defaultShowUndo = true;
  static const int _defaultUndoDuration = 3;

  // 可选的保留天数
  static const List<int> retentionOptions = [3, 7, 15, 30];

  final SharedPreferences _prefs;

  AppTrashSettings(this._prefs);

  /// 初始化工厂方法
  static Future<AppTrashSettings> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AppTrashSettings(prefs);
  }

  // ==================== 读取设置 ====================

  /// 回收站功能是否启用
  bool get isEnabled {
    return _prefs.getBool(_keyEnabled) ?? _defaultEnabled;
  }

  /// 文件保留天数（自动清理周期）
  int get retentionDays {
    final days = _prefs.getInt(_keyRetentionDays) ?? _defaultRetentionDays;
    // 验证值是否合法
    if (!retentionOptions.contains(days)) {
      logger.w(
          'Invalid retention days: $days, using default: $_defaultRetentionDays');
      return _defaultRetentionDays;
    }
    return days;
  }

  /// 是否显示撤销提示（SnackBar）
  bool get showUndo {
    return _prefs.getBool(_keyShowUndo) ?? _defaultShowUndo;
  }

  /// 撤销窗口时长（秒）
  int get undoDuration {
    return _prefs.getInt(_keyUndoDuration) ?? _defaultUndoDuration;
  }

  // ==================== 保存设置 ====================

  /// 启用/禁用回收站功能
  Future<void> setEnabled(bool value) async {
    try {
      await _prefs.setBool(_keyEnabled, value);
      logger.i('App trash enabled set to: $value');
    } catch (e) {
      logger.e('Failed to set enabled: $e');
      rethrow;
    }
  }

  /// 设置文件保留天数
  Future<void> setRetentionDays(int days) async {
    if (!retentionOptions.contains(days)) {
      throw ArgumentError(
          'Invalid retention days: $days. Must be one of $retentionOptions');
    }

    try {
      await _prefs.setInt(_keyRetentionDays, days);
      logger.i('Retention days set to: $days');
    } catch (e) {
      logger.e('Failed to set retention days: $e');
      rethrow;
    }
  }

  /// 设置是否显示撤销提示
  Future<void> setShowUndo(bool value) async {
    try {
      await _prefs.setBool(_keyShowUndo, value);
      logger.i('Show undo set to: $value');
    } catch (e) {
      logger.e('Failed to set show undo: $e');
      rethrow;
    }
  }

  /// 设置撤销窗口时长
  Future<void> setUndoDuration(int seconds) async {
    if (seconds < 1 || seconds > 10) {
      throw ArgumentError('Undo duration must be between 1 and 10 seconds');
    }

    try {
      await _prefs.setInt(_keyUndoDuration, seconds);
      logger.i('Undo duration set to: $seconds seconds');
    } catch (e) {
      logger.e('Failed to set undo duration: $e');
      rethrow;
    }
  }

  // ==================== 默认恢复目录配置 ====================

  /// Android 存储基础路径
  static const String _storageBase = '/storage/emulated/0';
  
  /// 恢复目录后缀
  static const String _restoreSuffix = '/EasyFile_Restored';

  /// 获取默认恢复目录（根据文件类型）
  static String getDefaultRestorePath(String mimeType) {
    final mimeTypeLower = mimeType.toLowerCase();

    if (mimeTypeLower.startsWith('image/')) {
      return '$_storageBase/Pictures$_restoreSuffix';
    } else if (mimeTypeLower.startsWith('video/')) {
      return '$_storageBase/Movies$_restoreSuffix';
    } else if (mimeTypeLower.startsWith('audio/')) {
      return '$_storageBase/Music$_restoreSuffix';
    } else if (mimeTypeLower.contains('pdf') ||
        mimeTypeLower.contains('document') ||
        mimeTypeLower.contains('text/')) {
      return '$_storageBase/Documents$_restoreSuffix';
    } else {
      return '$_storageBase/Download$_restoreSuffix';
    }
  }

  /// 默认恢复目录映射（用于UI显示）
  static Map<String, String> get defaultRestorePaths => {
    'image': '$_storageBase/Pictures$_restoreSuffix',
    'video': '$_storageBase/Movies$_restoreSuffix',
    'audio': '$_storageBase/Music$_restoreSuffix',
    'document': '$_storageBase/Documents$_restoreSuffix',
    'other': '$_storageBase/Download$_restoreSuffix',
  };

  // ==================== 辅助方法 ====================

  /// 获取保留天数的显示文本
  String getRetentionDaysText() {
    final days = retentionDays;
    return '$days天后自动清理';
  }

  /// 获取所有设置的摘要
  Map<String, dynamic> getAllSettings() {
    return {
      'enabled': isEnabled,
      'retentionDays': retentionDays,
      'showUndo': showUndo,
      'undoDuration': undoDuration,
    };
  }

  /// 重置所有设置为默认值
  Future<void> resetToDefaults() async {
    try {
      await _prefs.setBool(_keyEnabled, _defaultEnabled);
      await _prefs.setInt(_keyRetentionDays, _defaultRetentionDays);
      await _prefs.setBool(_keyShowUndo, _defaultShowUndo);
      await _prefs.setInt(_keyUndoDuration, _defaultUndoDuration);
      logger.i('App trash settings reset to defaults');
    } catch (e) {
      logger.e('Failed to reset settings: $e');
      rethrow;
    }
  }

  /// 导出设置（用于备份）
  Map<String, dynamic> exportSettings() {
    return {
      _keyEnabled: isEnabled,
      _keyRetentionDays: retentionDays,
      _keyShowUndo: showUndo,
      _keyUndoDuration: undoDuration,
    };
  }

  /// 导入设置（用于恢复）
  Future<void> importSettings(Map<String, dynamic> settings) async {
    try {
      if (settings.containsKey(_keyEnabled)) {
        await _prefs.setBool(_keyEnabled, settings[_keyEnabled] as bool);
      }
      if (settings.containsKey(_keyRetentionDays)) {
        final days = settings[_keyRetentionDays] as int;
        if (retentionOptions.contains(days)) {
          await _prefs.setInt(_keyRetentionDays, days);
        }
      }
      if (settings.containsKey(_keyShowUndo)) {
        await _prefs.setBool(_keyShowUndo, settings[_keyShowUndo] as bool);
      }
      if (settings.containsKey(_keyUndoDuration)) {
        await _prefs.setInt(
            _keyUndoDuration, settings[_keyUndoDuration] as int);
      }
      logger.i('App trash settings imported successfully');
    } catch (e) {
      logger.e('Failed to import settings: $e');
      rethrow;
    }
  }

  @override
  String toString() {
    return 'AppTrashSettings(enabled: $isEnabled, retentionDays: $retentionDays, '
        'showUndo: $showUndo, undoDuration: ${undoDuration}s)';
  }
}
