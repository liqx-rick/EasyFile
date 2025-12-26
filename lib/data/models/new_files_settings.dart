import 'package:shared_preferences/shared_preferences.dart';

/// 新文件功能设置
class NewFilesSettings {
  int retentionDays;
  int displayCount;

  NewFilesSettings({
    this.retentionDays = 7,
    this.displayCount = 50,
  });

  /// 保存到 SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('new_files_retention_days', retentionDays);
    await prefs.setInt('new_files_display_count', displayCount);
  }

  /// 从 SharedPreferences 加载
  static Future<NewFilesSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NewFilesSettings(
      retentionDays: prefs.getInt('new_files_retention_days') ?? 7,
      displayCount: prefs.getInt('new_files_display_count') ?? 50,
    );
  }

  /// 创建副本
  NewFilesSettings copyWith({
    int? retentionDays,
    int? displayCount,
  }) {
    return NewFilesSettings(
      retentionDays: retentionDays ?? this.retentionDays,
      displayCount: displayCount ?? this.displayCount,
    );
  }
}
