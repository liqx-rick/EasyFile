import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/di/locator.dart';
import '../core/logger.dart';
import '../data/services/data_migration_service.dart';
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
    // 任务1：检查存储权限
    await _checkPermissions();

    // 任务2：预加载主题配置
    await _preloadTheme();

    // 任务3：初始化日志记录
    await _initializeLogging();

    // 任务4：其他初始化任务
    await _performAdditionalInit();
  }

  /// 检查应用权限（只在首次启动且权限未授予时请求）
  ///
  /// 该方法会：
  /// 1. 检查所有必需权限的状态
  /// 2. 如果所有权限已授予，直接返回
  /// 3. 只在权限处于未决定状态时请求，避免重复请求
  Future<void> _checkPermissions() async {
    try {
      logger.d('SplashPresenter: Requesting permissions...');
      viewModel.setInitMessage('请求应用权限...');

      // 检查所有权限状态
      final manageStorageStatus = await Permission.manageExternalStorage.status;
      final storageStatus = await Permission.storage.status;
      final photosStatus = await Permission.photos.status;
      final videosStatus = await Permission.videos.status;

      // 如果所有权限已授予，直接返回（避免重复弹窗）
      if (manageStorageStatus.isGranted ||
          (storageStatus.isGranted &&
              photosStatus.isGranted &&
              videosStatus.isGranted)) {
        logger.i(
            'SplashPresenter: All permissions already granted, skipping requests');
        return;
      }

      // 只在首次启动（未决定状态）时请求权限
      // 已授予或永久拒绝的权限不再请求
      if (manageStorageStatus.isDenied &&
          !manageStorageStatus.isPermanentlyDenied) {
        logger.i('SplashPresenter: Requesting MANAGE_EXTERNAL_STORAGE...');
        Permission.manageExternalStorage.request();
      }

      if (storageStatus.isDenied && !storageStatus.isPermanentlyDenied) {
        logger.i('SplashPresenter: Requesting storage permission...');
        Permission.storage.request();
      }

      // 请求媒体访问权限（Android 13+）
      if (photosStatus.isDenied && !photosStatus.isPermanentlyDenied) {
        Permission.photos.request();
      }
      if (videosStatus.isDenied && !videosStatus.isPermanentlyDenied) {
        Permission.videos.request();
      }

      logger.d('SplashPresenter: Permission requests sent');
    } catch (e) {
      logger.w('SplashPresenter: Error requesting permissions: $e');
      // 权限请求失败不阻塞启动
    }
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

      // 执行数据迁移（从旧Favorites到新QuickAccess）
      await _performDataMigration();

      viewModel.setInitMessage('准备就绪...');

      logger.i('SplashPresenter: All initialization tasks completed');
    } catch (e) {
      logger.w('SplashPresenter: Error in additional initialization: $e');
    }
  }

  /// 执行数据迁移
  Future<void> _performDataMigration() async {
    try {
      logger.d('SplashPresenter: Checking data migration requirements...');
      viewModel.setInitMessage('检查数据迁移...');

      final migrationService = locator<DataMigrationService>();

      // 检查是否需要迁移
      final needsMigration = await migrationService.needsMigration();

      if (needsMigration) {
        logger.i(
          'SplashPresenter: Migration needed, starting migration process...',
        );
        viewModel.setInitMessage('正在迁移收藏数据...');

        // 执行迁移
        final result = await migrationService.migrate();

        // 记录迁移结果
        logger.i(
          'SplashPresenter: Migration completed - '
          'Total: ${result.totalCount}, '
          'Success: ${result.successCount}, '
          'Failed: ${result.failedCount}, '
          'Skipped: ${result.skippedCount}',
        );

        if (result.failedCount > 0) {
          logger.w('SplashPresenter: Migration had failures: ${result.errors}');
        }

        viewModel.setInitMessage('数据迁移完成');
      } else {
        logger.d('SplashPresenter: No migration needed');
      }
    } catch (e) {
      logger.e('SplashPresenter: Error during data migration: $e');
      // 迁移失败不阻塞应用启动
      viewModel.setInitMessage('数据迁移失败，将使用默认设置');
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
