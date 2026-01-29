import 'package:audio_session/audio_session.dart';
import 'package:easyfile/analytics/analytics_manager.dart';
import 'package:easyfile/app.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/app_trash_manager.dart';
import 'package:easyfile/core/services/cache_prewarm_coordinator.dart';
import 'package:easyfile/core/services/category_group_service.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/theme_settings_service.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // 保持 native splash 显示，直到 Flutter 应用完全准备好
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 全局允许所有屏幕方向（支持平板横屏）
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  logger.i('✓ Screen orientations: all enabled');

  // 配置图片缓存，限制内存使用
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20;

  // Initialize logger before other startup
  await logger.init();

  final processId = DateTime.now().millisecondsSinceEpoch;
  logger.i('NEW PROCESS: $processId');

  // 初始化 AppConfig（必须在其他服务之前）
  await AppConfig.instance.initialize();
  logger.i('✓ AppConfig initialized');

  // 配置全局 AudioSession（在任何播放器创建之前）
  try {
    final audioSession = await AudioSession.instance;
    await audioSession.configure(AudioSessionConfiguration.music());
    logger.i('✓ AudioSession initialized globally');
  } catch (e) {
    logger.e('Failed to initialize AudioSession: $e');
  }

  setupLocator();

  // 初始化全局服务
  await ViewModeService().initialize();
  await CategorySortService().initialize();
  await CategoryGroupService().initialize();
  await PageSettingsService().initialize();

  // 初始化主题服务（在应用启动时最早加载）
  await ThemeSettingsService().initialize();
  final themeService = ThemeSettingsService();
  logger.i('🎨 Theme initialized: ${themeService.themeMode}');

  // 启动回收站自动清理
  final trashManager = locator<AppTrashManager>();
  await trashManager.initialize();
  await trashManager.startAutoCleanup();

  // 🚀 统一缓存预热协调器
  // 阶段1（同步）：缩略图缓存初始化
  // 阶段2（延迟3秒）：MediaStore 缓存预热
  // 阶段3（延迟5秒）：应用文件缓存预热
  await CachePrewarmCoordinator.instance.initialize();

  // ✨ 优化：首次启动跳过预热（避免与首页推荐服务重复扫描）
  // 原因：首页在T=3s执行推荐扫描并写入缓存，预热T=5s执行时会100%跳过
  // 节省：约200-300ms的初始化成本（AppDetectionService、FileCountCache等）
  final isFirstLaunch = await _isFirstLaunch();
  logger.i('📱 启动类型检查: ${isFirstLaunch ? "首次启动" : "后续启动"}');

  if (!isFirstLaunch) {
    CachePrewarmCoordinator.instance.startPrewarming();
    logger.i('🚀 启动缓存预热（非首次启动）');

    // 可选：监听预热进度
    CachePrewarmCoordinator.instance.progressStream.listen((progress) {
      logger.d('预热进度: ${progress.taskName} - ${progress.progressPercent}%');
      if (progress.isFailed) {
        logger.e('预热失败: ${progress.error}');
      }
    });
  } else {
    logger.i('✨ 首次启动，跳过预热（首页推荐服务将执行扫描）');
  }

  // ===== 合规步骤1: Analytics 预初始化（无需用户同意）=====
  try {
    await AnalyticsManager.preInit();
    logger.i('✓ Analytics pre-initialized (Step 1/3)');
  } catch (e) {
    logger.e('Analytics preInit failed: $e');
  }

  runApp(const EasyFileApp());
}

/// 判断是否首次启动
///
/// 使用SharedPreferences持久化标记。
/// 首次启动时返回true并写入标记，后续启动返回false。
Future<bool> _isFirstLaunch() async {
  const String keyFirstLaunch = 'app_first_launch_completed';

  try {
    final prefs = await SharedPreferences.getInstance();
    final hasLaunched = prefs.getBool(keyFirstLaunch) ?? false;

    logger.d('🔍 首次启动检查: key=$keyFirstLaunch, hasLaunched=$hasLaunched');

    if (!hasLaunched) {
      // 首次启动，写入标记
      await prefs.setBool(keyFirstLaunch, true);
      logger.i('✍️ 写入首次启动标记');
      return true;
    }

    return false;
  } catch (e) {
    logger.e('检查首次启动状态失败: $e');
    // 出错时保守处理：视为非首次启动，执行预热
    return false;
  }
}
