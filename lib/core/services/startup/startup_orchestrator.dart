import 'package:easyfile/core/logger.dart';
import 'first_install_service.dart';
import 'app_initialization_service.dart';
import 'data_load_service.dart';

/// 启动编排器
///
/// 检测启动场景，并路由到相应的初始化流程
/// 场景分为：freshInstall（首次安装）、reinstall（重新安装）、normalOpen（正常打开）
class StartupOrchestrator {
  final AppInitializationService _appInitService;
  final DataLoadService _dataLoadService;
  final FirstInstallService _firstInstallService;

  StartupOrchestrator({
    required AppInitializationService appInitService,
    required DataLoadService dataLoadService,
    required FirstInstallService firstInstallService,
  })  : _appInitService = appInitService,
        _dataLoadService = dataLoadService,
        _firstInstallService = firstInstallService;

  /// 编排启动流程
  ///
  /// 根据当前应用状态，判断需要执行的初始化场景
  Future<void> orchestrate() async {
    logger.i('[Orchestrator] Starting orchestration...');

    final scene = await _detectStartupScene();
    logger.i('[Orchestrator] Detected startup scene: $scene');

    switch (scene) {
      case StartupScene.freshInstall:
        logger.i('[Orchestrator] Executing freshInstall scenario...');
        await _appInitService.initializeFromScratch();
        break;

      case StartupScene.reinstall:
        logger.i('[Orchestrator] Executing reinstall scenario...');
        await _dataLoadService.loadFromCache();
        break;

      case StartupScene.normalOpen:
        logger.i('[Orchestrator] Executing normalOpen scenario...');
        await _dataLoadService.loadFromDatabase();
        break;
    }

    logger.i('[Orchestrator] Orchestration completed');
  }

  /// 检测启动场景
  ///
  /// 返回值说明：
  /// - freshInstall：无初始化标记，第一次安装
  /// - reinstall：有初始化标记，但无缓存或缓存过期，重新开始
  /// - normalOpen：有初始化标记，缓存有效，正常打开
  Future<StartupScene> _detectStartupScene() async {
    final isInitialized = await _firstInstallService.isInitialized();

    if (!isInitialized) {
      return StartupScene.freshInstall;
    }

    final isCacheValid = await _dataLoadService.isCacheValid();

    if (!isCacheValid) {
      return StartupScene.reinstall;
    }

    return StartupScene.normalOpen;
  }
}

/// 启动场景枚举
enum StartupScene {
  /// 首次安装：执行完整初始化（P0→P1→P2）
  /// 耗时约37秒，显示进度UI
  freshInstall,

  /// 重新安装：使用有效缓存快速加载
  /// 耗时约3秒，无进度UI
  reinstall,

  /// 正常打开：直接从DB加载
  /// 耗时约2秒，无进度UI
  normalOpen,
}
