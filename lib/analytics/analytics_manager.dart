import 'dart:async';

import 'package:easyfile/analytics/analytics_config.dart';
import 'package:easyfile/analytics/analytics_service.dart';
import 'package:easyfile/analytics/firebase_analytics_service.dart';
import 'package:easyfile/analytics/umeng_analytics_service.dart';
import 'package:easyfile/core/logger.dart';

/// 全局埋点管理器（单例）
/// 
/// 职责：
/// - 根据配置选择具体实现（Umeng/Firebase）
/// - 提供统一的静态 API 入口
/// - 管理合规三步初始化流程
class AnalyticsManager {
  AnalyticsManager._internal();

  static final AnalyticsManager instance = AnalyticsManager._internal();

  late AnalyticsService _service;
  bool _initialized = false;
  bool _preInitialized = false;

  /// 合规步骤1: 预初始化（应用启动时立即调用，无需用户同意）
  Future<void> preInitialize({AnalyticsProvider? provider}) async {
    if (_preInitialized) {
      logger.i('Analytics already pre-initialized');
      return;
    }

    logger.i('Analytics pre-initializing...');

    // 加载配置文件
    try {
      await AnalyticsConfig.load();
      logger.i('Analytics config loaded');
    } catch (e) {
      logger.e('Failed to load analytics config: $e');
      _service = FirebaseAnalyticsService(); // 使用 no-op placeholder
      _preInitialized = true;
      return;
    }

    // 检查全局开关
    if (!AnalyticsConfig.isEnabled) {
      logger.i('Analytics globally disabled in config');
      _service = FirebaseAnalyticsService(); // 使用 no-op placeholder
      _preInitialized = true;
      return;
    }

    final selected = provider ?? await detectProviderFromEnvironment();
    logger.i('Analytics selecting provider: $selected');

    switch (selected) {
      case AnalyticsProvider.umeng:
        _service = UmengAnalyticsService();
        break;
      case AnalyticsProvider.firebase:
        _service = FirebaseAnalyticsService();
        break;
      case AnalyticsProvider.none:
        _service = FirebaseAnalyticsService(); // use placeholder no-op
        break;
    }

    // 仅对 Umeng 执行预初始化
    if (_service is UmengAnalyticsService) {
      try {
        await (_service as UmengAnalyticsService).preInitialize();
        _preInitialized = true;
        logger.i('Analytics pre-initialized successfully with provider: $selected (Step 1/3)');
      } catch (e) {
        logger.e('Analytics pre-initialization failed: $e');
      }
    } else {
      _preInitialized = true;
      logger.i('Analytics pre-initialized (non-Umeng provider)');
    }
  }

  /// 合规步骤2: 授权隐私政策（用户同意后调用）
  Future<void> grantPrivacy() async {
    if (!_preInitialized) {
      logger.w('Analytics not pre-initialized, call preInitialize first');
      return;
    }

    if (_service is UmengAnalyticsService) {
      try {
        await (_service as UmengAnalyticsService).grantPrivacy();
        logger.i('Analytics privacy granted (Step 2/3)');
      } catch (e) {
        logger.e('Analytics privacy grant failed: $e');
      }
    }
  }

  /// 合规步骤3: 正式初始化（必须在用户同意隐私政策后调用）
  /// 初始化全局埋点系统，若 [provider] 为 null，会自动检测环境
  Future<void> initialize({AnalyticsProvider? provider}) async {
    if (_initialized) {
      logger.i('Analytics already initialized');
      return;
    }

    if (!_preInitialized) {
      logger.w('Analytics not pre-initialized, call preInitialize first');
      // 兜底：自动执行预初始化
      await preInitialize(provider: provider);
    }

    logger.i('Analytics initializing...');

    try {
      await _service.initialize();
      _initialized = true;
      logger.i('Analytics initialized successfully (Step 3/3)');
    } catch (e) {
      logger.e('Analytics initialization failed: $e');
      _initialized = false;
    }
  }

  /// 记录事件（内部方法，业务代码请使用静态方法 `AnalyticsManager.log`）
  Future<void> _logEvent(String event, {Map<String, Object?>? params}) async {
    if (!_initialized) {
      logger.w('Analytics not initialized, dropping event: $event');
      return;
    }
    // 参数审查：禁止上传敏感/隐私信息（由调用方保证）
    await _service.logEvent(event, params: params);
  }

  // ---------- 静态便捷调用 ----------
  static Future<void> preInit({AnalyticsProvider? provider}) => instance.preInitialize(provider: provider);

  static Future<void> grant() => instance.grantPrivacy();

  static Future<void> init({AnalyticsProvider? provider}) => instance.initialize(provider: provider);

  static Future<void> log(String event, {Map<String, Object?>? params}) => instance._logEvent(event, params: params);
}
