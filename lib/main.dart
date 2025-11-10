import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:easyfile/app.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  
  // 保持native splash显示，直到Flutter应用完全准备好
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  // Initialize logger before other startup so DI logs go to file
  await logger.init();
  logger.i('EasyFile application starting...');
  
  setupLocator();
  logger.i('Running EasyFile app');
  
  // 启动Flutter应用
  runApp(const EasyFileApp());
}
  