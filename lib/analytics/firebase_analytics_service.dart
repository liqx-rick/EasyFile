import 'dart:async';

import 'package:easyfile/analytics/analytics_service.dart';

/// Firebase 埋点占位实现（no-op fallback）
/// 未来可在此处引入 `firebase_analytics` 并封装到本类中。
///
/// 注意：此类作为内部 no-op fallback 使用，避免空指针异常
/// 当 Analytics 配置加载失败或全局禁用时，AnalyticsManager 会使用此占位实现
class FirebaseAnalyticsService implements AnalyticsService {
  @override
  Future<void> initialize() async {
    // TODO: 初始化 firebase_analytics
    // Silently no-op - 避免日志污染
  }

  @override
  Future<void> logEvent(String event, {Map<String, Object?>? params}) async {
    // TODO: 调用 FirebaseAnalytics.instance.logEvent(...)
    // Silently no-op - 避免日志污染
  }
}
