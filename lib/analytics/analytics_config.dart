import 'package:easyfile/core/logger.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 埋点提供商枚举
enum AnalyticsProvider { umeng, firebase, none }

/// Analytics 配置读取器
/// 从 config/analytics_config.yaml 读取配置
class AnalyticsConfig {
  static Map<String, dynamic>? _config;

  /// 加载配置文件
  static Future<void> load() async {
    if (_config != null) return;

    try {
      // 从 assets 读取配置文件
      final content = await rootBundle.loadString('config/analytics_config.yaml');
      _config = _parseSimpleYaml(content);
    } catch (e) {
      logger.w('Failed to load analytics config: $e');
      _config = {};
    }
  }

  /// 简单 YAML 解析（仅解析我们需要的字段）
  static Map<String, dynamic> _parseSimpleYaml(String content) {
    final config = <String, dynamic>{};

    for (var line in content.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains(':')) continue;

      final parts = line.split(':');
      final key = parts[0].trim();
      final value = parts.sublist(1).join(':').trim();

      // 解析布尔值，其他保持字符串
      config[key] = (value == 'true')
          ? true
          : (value == 'false')
              ? false
              : value;
    }

    return config;
  }

  /// 获取配置值（内部方法，仅供 isEnabled 和 market getter 使用）
  /// @internal 业务代码不应直接调用此方法
  static T get<T>(String key, T defaultValue) {
    if (_config == null) return defaultValue;
    return _config![key] as T? ?? defaultValue;
  }

  /// 是否启用 Analytics
  static bool get isEnabled => get('enabled', true);

  /// 目标市场
  static String get market => get('market', 'china');
}

/// 根据配置文件选择 provider
///
/// 简化说明：当前项目固定使用 Umeng（国内市场），已移除编译时常量和 locale 判断
/// 如需支持多市场，在 config/analytics_config.yaml 中修改 market 字段即可
Future<AnalyticsProvider> detectProviderFromEnvironment() async {
  // 从配置文件读取市场设置
  await AnalyticsConfig.load();

  final market = AnalyticsConfig.market;

  // 根据市场选择 provider
  if (market == 'china') {
    return AnalyticsProvider.umeng;
  } else if (market == 'international') {
    return AnalyticsProvider.firebase;
  }

  // 默认使用 firebase（面向海外）
  return AnalyticsProvider.firebase;
}
