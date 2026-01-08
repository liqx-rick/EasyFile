import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/config/app_config.dart';

/// EasyFile回收站配置管理
///
/// 管理回收站相关的用户设置（通过AppConfig统一读取）
class AppTrashSettings {
  // 删除_config字段，直接使用AppConfig.instance

  // ==================== 读取设置（从AppConfig） ====================

  /// 回收站功能是否启用
  bool get isEnabled => AppConfig.instance.fileScan.trashEnabled;

  /// 文件保留天数（自动清理周期）
  int get retentionDays => AppConfig.instance.fileScan.trashRetentionDays;

  /// 可选的保留天数
  List<int> get retentionOptions =>
      AppConfig.instance.fileScan.trashRetentionOptions;

  // ==================== 保存设置（委托给AppConfig） ====================

  /// 启用/禁用回收站功能
  Future<void> setEnabled(bool value) async {
    await AppConfig.instance.fileScan.setTrashEnabled(value);
  }

  /// 设置文件保留天数
  Future<void> setRetentionDays(int days) async {
    await AppConfig.instance.fileScan.setTrashRetentionDays(days);
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
    };
  }

  /// 重置所有设置为默认值（使用 AppConfig.fileScan.reset 统一重置）
  Future<void> resetToDefaults() async {
    // 使用 AppConfig 的 reset 方法，自动应用所有默认值
    await AppConfig.instance.fileScan.reset();
    logger.i('App trash settings reset to defaults');
  }

  /// 导出设置（用于备份）
  Map<String, dynamic> exportSettings() {
    return {
      'enabled': isEnabled,
      'retentionDays': retentionDays,
    };
  }

  /// 导入设置（用于恢复）
  Future<void> importSettings(Map<String, dynamic> settings) async {
    if (settings.containsKey('enabled')) {
      await setEnabled(settings['enabled'] as bool);
    }
    if (settings.containsKey('retentionDays')) {
      final days = settings['retentionDays'] as int;
      if (retentionOptions.contains(days)) {
        await setRetentionDays(days);
      }
    }
    logger.i('App trash settings imported successfully');
  }

  @override
  String toString() {
    return 'AppTrashSettings(enabled: $isEnabled, retentionDays: $retentionDays)';
  }
}
