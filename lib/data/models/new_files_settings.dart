import 'package:shared_preferences/shared_preferences.dart';

/// 新文件功能设置
class NewFilesSettings {
  int retentionDays;
  int displayCount;

  // 隐私设置 - "隐藏"语义，默认false（即默认显示）
  bool hideCameraPhotos;
  bool hideScreenshots;

  List<String> customScanPaths;

  NewFilesSettings({
    this.retentionDays = 7,
    this.displayCount = 50,
    this.hideCameraPhotos = false,
    this.hideScreenshots = false,
    this.customScanPaths = const [],
  });

  /// 判断是否扫描某个路径类型
  bool shouldScanCamera() => !hideCameraPhotos;
  bool shouldScanScreenshots() => !hideScreenshots;

  /// 保存到 SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('new_files_retention_days', retentionDays);
    await prefs.setInt('new_files_display_count', displayCount);
    await prefs.setBool('new_files_hide_camera', hideCameraPhotos);
    await prefs.setBool('new_files_hide_screenshots', hideScreenshots);
    await prefs.setStringList('new_files_custom_paths', customScanPaths);
  }

  /// 从 SharedPreferences 加载
  static Future<NewFilesSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NewFilesSettings(
      retentionDays: prefs.getInt('new_files_retention_days') ?? 7,
      displayCount: prefs.getInt('new_files_display_count') ?? 50,
      hideCameraPhotos: prefs.getBool('new_files_hide_camera') ?? false,
      hideScreenshots: prefs.getBool('new_files_hide_screenshots') ?? false,
      customScanPaths: prefs.getStringList('new_files_custom_paths') ?? [],
    );
  }

  /// 创建副本
  NewFilesSettings copyWith({
    int? retentionDays,
    int? displayCount,
    bool? hideCameraPhotos,
    bool? hideScreenshots,
    List<String>? customScanPaths,
  }) {
    return NewFilesSettings(
      retentionDays: retentionDays ?? this.retentionDays,
      displayCount: displayCount ?? this.displayCount,
      hideCameraPhotos: hideCameraPhotos ?? this.hideCameraPhotos,
      hideScreenshots: hideScreenshots ?? this.hideScreenshots,
      customScanPaths: customScanPaths ?? this.customScanPaths,
    );
  }
}
