import 'package:easyfile/core/logger.dart';

import 'app_initialization_service.dart';
import 'data_load_service.dart';
import 'first_install_service.dart';
import 'initialization_config.dart';

/// 启动编排器
///
/// 检测启动场景，并路由到相应的初始化流程
/// 场景分为：freshInstall（首次安装）、normalOpen（正常打开）
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
        logger.i('[Orchestrator] Executing freshInstall scenario with quick start mode...');
        // ⚡ 快速启动模式（默认策略）
        // 策略：跳过P1.1分类扫描（保留P1.2应用扫描）
        // 原因：避免用户长时间等待，采用按需加载优化体验
        // 节省时间：35秒（分类扫描）
        // 初始化时间：从60-70秒 → 25-35秒
        // 用户首次进入分类页时才扫描（200-500ms MediaStore快速显示）
        await _appInitService.initializeFromScratch(
          config: InitializationConfig.quickStart(),
        );
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
  /// - normalOpen：有初始化标记，正常打开
  Future<StartupScene> _detectStartupScene() async {
    final isInitialized = await _firstInstallService.isInitialized();

    if (!isInitialized) {
      return StartupScene.freshInstall;
    }

    return StartupScene.normalOpen;
  }
}

/// 启动场景枚举
enum StartupScene {
  /// 首次安装：使用快速启动模式（P0→P1.2→P2，跳过P1.1分类扫描）
  /// 策略：按需加载，用户进入分类页时才扫描该分类
  /// 耗时约25-35秒，显示进度UI
  freshInstall,

  /// 正常打开：直接从DB加载
  /// 耗时约2秒，无进度UI
  normalOpen,
}
