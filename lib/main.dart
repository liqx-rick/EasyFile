import 'package:audio_session/audio_session.dart';
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
  CachePrewarmCoordinator.instance.startPrewarming();

  // 可选：监听预热进度
  CachePrewarmCoordinator.instance.progressStream.listen((progress) {
    logger.d('预热进度: ${progress.taskName} - ${progress.progressPercent}%');
    if (progress.isFailed) {
      logger.e('预热失败: ${progress.error}');
    }
  });

  runApp(const EasyFileApp());
}
