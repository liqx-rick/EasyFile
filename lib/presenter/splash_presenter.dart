import 'dart:async';

import 'package:flutter/material.dart';

import '../core/logger.dart';
import '../viewmodel/splash_viewmodel.dart';

/// 启动页业务逻辑处理器
class SplashPresenter {
  final SplashViewModel viewModel;
  final AppLogger logger;
  final VoidCallback? onComplete;
  Timer? _delayTimer;

  SplashPresenter({
    required this.viewModel,
    required this.logger,
    this.onComplete,
  });

  /// 初始化应用
  Future<void> initApp(BuildContext context) async {
    try {
      logger.i('SplashPresenter: Starting app initialization...');

      // 设置初始化开始状态
      viewModel.setInitializing(true);
      viewModel.setInitMessage('正在启动应用...');

      // 执行初始化任务
      await _performInitializationTasks();

      // 设置初始化完成状态
      viewModel.setInitializing(false);
      viewModel.setInitMessage('启动完成');

      // 延迟2秒后跳转（通过 onComplete 回调处理导航）
      await _scheduleNavigation();
    } catch (e) {
      logger.e('SplashPresenter: Error during app initialization: $e');
      viewModel.setInitMessage('启动失败：$e');
      // 即使出错也要跳转，避免用户卡在启动页
      await _scheduleNavigation();
    }
  }

  /// 执行初始化任务
  Future<void> _performInitializationTasks() async {
    // 任务1：检查存储权限（已移至 app.dart 的 _initializeApp 中提前处理）
    // 避免在隐私政策弹窗显示时重复请求权限

    // 任务2：预加载主题配置
    await _preloadTheme();

    // 任务3：初始化日志记录
    await _initializeLogging();

    // 任务4：其他初始化任务
    await _performAdditionalInit();
  }

  /// 预加载主题配置
  Future<void> _preloadTheme() async {
    try {
      logger.d('SplashPresenter: Preloading theme configuration...');
      viewModel.setInitMessage('加载主题配置...');

      logger.d('SplashPresenter: Theme preload completed');
    } catch (e) {
      logger.w('SplashPresenter: Error preloading theme: $e');
    }
  }

  /// 初始化日志记录
  Future<void> _initializeLogging() async {
    try {
      logger.d('SplashPresenter: Initializing logging system...');
      viewModel.setInitMessage('初始化日志系统...');

      // 记录应用启动事件
      logger.i('EasyFile application started at ${DateTime.now()}');
    } catch (e) {
      logger.w('SplashPresenter: Error initializing logging: $e');
    }
  }

  /// 执行其他初始化任务
  Future<void> _performAdditionalInit() async {
    try {
      logger.d('SplashPresenter: Performing additional initialization...');

      viewModel.setInitMessage('准备就绪...');

      logger.i('SplashPresenter: All initialization tasks completed');
    } catch (e) {
      logger.w('SplashPresenter: Error in additional initialization: $e');
    }
  }

  /// 安排导航到主页面（通过 onComplete 回调触发，由调用方处理具体导航）
  Future<void> _scheduleNavigation() async {
    logger.d('SplashPresenter: Scheduling navigation to main page...');

    // 快速跳转到主页面，给用户简短的品牌展示时间
    _delayTimer = Timer(const Duration(milliseconds: 800), () {
      // 通过回调通知上层进行导航
      onComplete?.call();
    });
  }

  /// 清理资源
  void dispose() {
    logger.d('SplashPresenter: Disposing resources...');
    _delayTimer?.cancel();
    _delayTimer = null;
  }
}
