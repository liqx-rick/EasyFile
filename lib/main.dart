import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:easyfile/app.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/category_group_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/app_trash_manager.dart';
import 'package:easyfile/utils/thumbnail_cache_manager.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // 保持native splash显示，直到Flutter应用完全准备好
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 配置图片缓存，限制内存使用
  PaintingBinding.instance.imageCache.maximumSize = 100; // 最多缓存100张图片
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50MB

  // Initialize logger before other startup so DI logs go to file
  await logger.init();

  // 记录进程启动
  final processId = DateTime.now().millisecondsSinceEpoch;
  logger.i('==========================================');
  logger.i('NEW PROCESS STARTED - ID: $processId');
  logger.i('EasyFile application starting...');
  logger.i('==========================================');

  setupLocator();

  // 初始化全局服务
  await ViewModeService().initialize();
  logger.i('ViewModeService initialized');

  await CategorySortService().initialize();
  logger.i('CategorySortService initialized');

  await CategoryGroupService().initialize();
  logger.i('CategoryGroupService initialized');

  await PageSettingsService().initialize();
  logger.i('PageSettingsService initialized');

  // 启动回收站自动清理
  final trashManager = await locator.getAsync<AppTrashManager>();
  await trashManager.startAutoCleanup();
  logger.i('AppTrashManager auto cleanup started');

  // 初始化并诊断缩略图缓存
  try {
    final cacheManager = ThumbnailCacheManager();
    await cacheManager.init();
    
    // 诊断缓存状态
    final diagnosis = await cacheManager.diagnoseCache();
    logger.i('Thumbnail cache diagnosis: $diagnosis');
    
    // 如果初始化失败，尝试强制重新初始化
    if (diagnosis['initialized'] == false || diagnosis['cacheDirNull'] == true) {
      logger.w('Thumbnail cache not properly initialized, attempting force reinitialization...');
      final success = await cacheManager.forceReinitialize();
      if (success) {
        logger.i('Thumbnail cache force reinitialization successful');
      } else {
        logger.e('Thumbnail cache force reinitialization failed - thumbnails will not be cached');
      }
    } else if (diagnosis['writable'] == false) {
      logger.e('Thumbnail cache directory is not writable - thumbnails will not be cached');
      logger.e('Write error: ${diagnosis['writeError']}');
    } else {
      logger.i('Thumbnail cache initialized successfully');
      logger.i('Cache size: ${diagnosis['cacheSize']} bytes, count: ${diagnosis['cacheCount']} files');
    }
  } catch (e, stackTrace) {
    logger.e('Failed to initialize thumbnail cache: $e');
    logger.e('Stack trace: $stackTrace');
    logger.e('Application will continue but thumbnails will not be cached');
  }

  logger.i('Running EasyFile app');

  // 启动Flutter应用
  runApp(const EasyFileApp());
}
