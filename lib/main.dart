import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:easyfile/app.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/category_group_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // 保持native splash显示，直到Flutter应用完全准备好
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 优化图片缓存配置
  // 增加缓存容量，解决从预览返回时缩略图被清除的问题
  PaintingBinding.instance.imageCache.maximumSize = 300; // 增加到300张（原100张）
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      150 << 20; // 150MB（原50MB）
  logger.i('ImageCache configured: maximumSize=300, maximumSizeBytes=150MB');

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

  logger.i('Running EasyFile app');

  // 启动Flutter应用
  runApp(const EasyFileApp());
}
