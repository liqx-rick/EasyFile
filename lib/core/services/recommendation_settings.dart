import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';

/// 首页推荐设置
class RecommendationSettings {
  /// SharedPreferences键名
  static const String _keyFileCountThreshold = 'recommendation_file_count_threshold';

  /// 默认文件数量阈值
  static const int defaultFileCountThreshold = 5;

  /// 可选的文件数量阈值列表
  static const List<int> availableThresholds = [3, 5, 10, 20, 30, 50, 100, 1000, 3000];

  /// 当前文件数量阈值
  final int fileCountThreshold;

  const RecommendationSettings({
    required this.fileCountThreshold,
  });

  /// 从SharedPreferences加载设置
  static Future<RecommendationSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final threshold = prefs.getInt(_keyFileCountThreshold) ?? defaultFileCountThreshold;

      return RecommendationSettings(
        fileCountThreshold: threshold,
      );
    } catch (e) {
      logger.e('加载推荐设置失败: $e');
      return const RecommendationSettings(
        fileCountThreshold: defaultFileCountThreshold,
      );
    }
  }

  /// 保存设置到SharedPreferences
  Future<bool> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyFileCountThreshold, fileCountThreshold);
      logger.d('推荐设置已保存: 文件数阈值=$fileCountThreshold');
      return true;
    } catch (e) {
      logger.e('保存推荐设置失败: $e');
      return false;
    }
  }

  /// 创建副本并更新文件数量阈值
  RecommendationSettings copyWith({
    int? fileCountThreshold,
  }) {
    return RecommendationSettings(
      fileCountThreshold: fileCountThreshold ?? this.fileCountThreshold,
    );
  }

  @override
  String toString() {
    return 'RecommendationSettings(fileCountThreshold: $fileCountThreshold)';
  }
}
