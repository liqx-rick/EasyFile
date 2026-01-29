import 'dart:async';

/// 抽象埋点服务接口 — 业务代码只依赖此抽象层
/// 主要职责：统一上报事件、控制开关与清理/重置数据
abstract class AnalyticsService {
  /// 初始化 SDK（如果需要异步初始化）
  Future<void> initialize();

  /// 记录任意事件，事件名请使用 snake_case
  Future<void> logEvent(String event, {Map<String, Object?>? params});
}
