import 'dart:async';

import 'package:easyfile/analytics/analytics_service.dart';
import 'package:easyfile/core/logger.dart';
import 'package:flutter/services.dart';

/// Umeng (友盟) 埋点实现
/// 说明：为了避免在业务代码中直接依赖第三方包，这里通过 MethodChannel
/// 与原生侧的友盟 SDK 交互。原生需实现对应的 channel 方法：
/// - preInit (合规步骤1: 预初始化)
/// - grantPrivacy (合规步骤2: 隐私授权)
/// - init (合规步骤3: 正式初始化)
/// - logEvent (args: {event: string, params: Map})
class UmengAnalyticsService implements AnalyticsService {
  final MethodChannel _channel = const MethodChannel('easyfile/analytics/umeng');
  bool _preInitialized = false;
  bool _fullyInitialized = false;

  /// 合规步骤1: 预初始化（应用启动时立即调用，无需用户同意）
  Future<void> preInitialize() async {
    if (_preInitialized) {
      logger.i('UmengAnalyticsService already pre-initialized');
      return;
    }

    try {
      await _channel.invokeMethod('preInit');
      _preInitialized = true;
      logger.i('UmengAnalyticsService pre-initialized (Step 1/3)');
    } catch (e) {
      logger.w('Umeng preInit failed or not available: $e');
    }
  }

  /// 合规步骤2: 授权隐私政策（用户同意后调用）
  /// 注意：必须在用户明确同意隐私政策后调用
  Future<void> grantPrivacy() async {
    try {
      await _channel.invokeMethod('grantPrivacy');
      logger.i('UmengAnalyticsService privacy granted (Step 2/3)');
    } catch (e) {
      logger.w('Umeng grantPrivacy failed: $e');
    }
  }

  /// 合规步骤3: 正式初始化（必须在 grantPrivacy 之后调用）
  @override
  Future<void> initialize() async {
    if (_fullyInitialized) {
      logger.i('UmengAnalyticsService already fully initialized');
      return;
    }

    try {
      await _channel.invokeMethod('init');
      _fullyInitialized = true;
      logger.i('UmengAnalyticsService fully initialized (Step 3/3)');
    } catch (e) {
      logger.w('Umeng init failed or not available: $e');
    }
  }

  @override
  Future<void> logEvent(String event, {Map<String, Object?>? params}) async {
    try {
      await _channel.invokeMethod('logEvent', {
        'event': event,
        'params': params ?? <String, Object?>{},
      });
    } catch (e) {
      // 降级处理：打印日志但不阻塞业务
      logger.d('Umeng logEvent fallback: $event, $params, err=$e');
    }
  }
}
