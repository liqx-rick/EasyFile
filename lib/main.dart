import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:easyfile/app.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/category_group_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/theme_settings_service.dart';
import 'package:easyfile/core/services/app_trash_manager.dart';
import 'package:easyfile/utils/thumbnail_cache_manager.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // 保持 native splash 显示，直到 Flutter 应用完全准备好
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 配置图片缓存，限制内存使用
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20;

  // Initialize logger before other startup
  await logger.init();

  final processId = DateTime.now().millisecondsSinceEpoch;
  logger.i('NEW PROCESS: $processId');

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
  final trashManager = await locator.getAsync<AppTrashManager>();
  await trashManager.startAutoCleanup();

  // 初始化缩略图缓存
  try {
    final cacheManager = ThumbnailCacheManager();
    await cacheManager.init();
    final diagnosis = await cacheManager.diagnoseCache();

    if (diagnosis['initialized'] == false || diagnosis['cacheDirNull'] == true) {
      final success = await cacheManager.forceReinitialize();
      if (!success) {
        logger.w('Thumbnail cache initialization failed');
      }
    }
  } catch (e) {
    logger.e('Failed to initialize thumbnail cache: $e');
  }

  runApp(const EasyFileApp());
}