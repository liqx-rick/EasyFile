import 'package:easyfile/data/models/recommendation_card.dart';

/// RecommendConfig 与数据源的映射关系
///
/// 提供推荐类型到 queryStrategy 和查询参数的映射
/// 用于将 RecommendConfig 转换为数据源查询
class RecommendConfigDataSourceMapper {
  /// 根据推荐类型获取 queryStrategy
  ///
  /// 映射关系：
  /// - wechat/qq/telegram/wps -> 'app_files'
  /// - memories -> 'time_memory'
  /// - videos -> 'life_moments'
  /// - recordings -> 'audio_records'
  /// - largeFiles -> 'large_files'
  static String getQueryStrategy(RecommendationType type) {
    // 应用类推荐 -> app_files
    if (type == RecommendationType.wechat ||
        type == RecommendationType.qq ||
        type == RecommendationType.telegram ||
        type == RecommendationType.wps ||
        type == RecommendationType.dingtalk) {
      return 'app_files';
    }

    // 系统类推荐 -> 各自的数据源
    switch (type) {
      case RecommendationType.memories:
        return 'time_memory';
      case RecommendationType.videos:
        return 'life_moments';
      case RecommendationType.recordings:
        return 'audio_records';
      case RecommendationType.largeFiles:
        return 'large_files';
      default:
        throw ArgumentError('未支持的推荐类型: $type');
    }
  }

  /// 根据推荐类型生成默认查询参数
  ///
  /// 应用类：
  /// ```dart
  /// {'appKey': 'wechat', 'useMediaStore': true}
  /// ```
  ///
  /// 时光记忆（一年前今天，前后7天）：
  /// ```dart
  /// {'daysAgo': 365, 'tolerance': 7}
  /// ```
  ///
  /// 生活剪影（最近7天）：
  /// ```dart
  /// {'recentDays': 7}
  /// ```
  ///
  /// 声音记录（所有）：
  /// ```dart
  /// {}
  /// ```
  ///
  /// 大文件（>100MB）：
  /// ```dart
  /// {'minSize': 100 * 1024 * 1024}
  /// ```
  static Map<String, dynamic> getDefaultQueryParams(RecommendationType type) {
    // 应用类推荐：需要 appKey
    switch (type) {
      case RecommendationType.wechat:
        return {'appKey': 'wechat', 'useMediaStore': true};
      case RecommendationType.qq:
        return {'appKey': 'qq', 'useMediaStore': true};
      case RecommendationType.telegram:
        return {'appKey': 'telegram', 'useMediaStore': true};
      case RecommendationType.wps:
        return {'appKey': 'wps', 'useMediaStore': true};
      case RecommendationType.dingtalk:
        return {'appKey': 'dingtalk', 'useMediaStore': true};

      // 系统类推荐：不同的默认参数
      case RecommendationType.memories:
        return {
          'daysAgo': 365, // 一年前今天
          'tolerance': 7, // 前后7天
          'maxResults': 100,
        };

      case RecommendationType.videos:
        return {
          'recentDays': 7, // 最近7天
          'maxResults': 50,
        };

      case RecommendationType.recordings:
        return {
          'maxResults': 50,
        };

      case RecommendationType.largeFiles:
        return {
          'minSize': 100 * 1024 * 1024, // 100MB
          'maxResults': 100,
        };
    }
  }

  /// 根据推荐类型生成 Tab 配置的查询参数
  ///
  /// 用于应用推荐模式的文件类型 Tab
  ///
  /// 示例：微信图片 Tab
  /// ```dart
  /// getTabQueryParams(
  ///   RecommendationType.wechat,
  ///   fileTypes: ['jpg', 'png', 'gif'],
  /// )
  /// // 返回: {'appKey': 'wechat', 'fileTypes': ['jpg', 'png', 'gif']}
  /// ```
  static Map<String, dynamic> getTabQueryParams(
    RecommendationType type, {
    List<String>? fileTypes,
  }) {
    final baseParams = getDefaultQueryParams(type);

    if (fileTypes != null && fileTypes.isNotEmpty) {
      baseParams['fileTypes'] = fileTypes;
    }

    return baseParams;
  }

  /// 获取推荐类型的默认 maxResults
  static int getDefaultMaxResults(RecommendationType type) {
    switch (type) {
      case RecommendationType.memories:
        return 100; // 照片较多
      case RecommendationType.videos:
      case RecommendationType.recordings:
        return 50; // 视频和录音中等
      case RecommendationType.largeFiles:
        return 100; // 大文件可能较多
      default:
        return 100; // 应用文件默认
    }
  }

  /// 获取推荐类型的建议缓存过期时间（秒）
  static int getSuggestedCacheExpiration(RecommendationType type) {
    switch (type) {
      case RecommendationType.memories:
        return 3600; // 1小时（时间敏感）
      case RecommendationType.videos:
      case RecommendationType.recordings:
        return 1800; // 30分钟（相对实时）
      case RecommendationType.largeFiles:
        return 1800; // 30分钟（文件大小变化快）
      default:
        return 6 * 3600; // 6小时（应用文件，与 UnifiedAppScanner 一致）
    }
  }
}
