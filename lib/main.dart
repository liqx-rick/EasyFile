import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:easyfile/app.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/category_group_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/theme_settings_service.dart';
import 'package:easyfile/core/services/app_trash_manager.dart';
import 'package:easyfile/core/services/mediastore_cache_service.dart';
import 'package:easyfile/core/platform/native_log_config_channel.dart';
import 'package:easyfile/utils/thumbnail_cache_manager.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // 保持 native splash 显示，直到 Flutter 应用完全准备好
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 配置图片缓存，限制内存使用
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20;

  // Initialize logger before other startup
  // 根据构建模式设置日志级别
  late final LogLevel logLevel;
  if (kReleaseMode) {
    logLevel = LogLevel.warn;   // Release: 生产环境，只显示警告和错误
  } else if (kProfileMode) {
    logLevel = LogLevel.info;   // Profile: Staging环境，显示信息、警告和错误
  } else {
    logLevel = LogLevel.debug;  // Debug: 开发环境，显示所有日志
  }
  await logger.init(minLevel: logLevel);
  
  // 🔄 同步日志级别到原生端（确保 Flutter 和原生日志使用统一策略）
  await NativeLogConfigChannel.syncLogConfig(level: logLevel);

  final processId = DateTime.now().millisecondsSinceEpoch;
  logger.i('NEW PROCESS: $processId');

  // 初始化配置系统（在所有服务之前）
  await AppConfig.instance.initialize();

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

  // 初始化 MediaStore 缓存服务
  try {
    final mediastoreCacheService = MediaStoreCacheService();
    await mediastoreCacheService.initialize();
    logger.i('✓ MediaStore 缓存服务已初始化');
    
    // 后台预热缓存（不阻塞UI启动）
    mediastoreCacheService.warmUp().then((_) {
      logger.i('✓ MediaStore 缓存预热完成');
    }).catchError((e) {
      logger.e('MediaStore 缓存预热失败: $e');
    });
  } catch (e) {
    logger.e('Failed to initialize MediaStore cache service: $e');
  }

  runApp(const EasyFileApp());
}