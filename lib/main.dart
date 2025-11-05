import 'package:flutter/material.dart';
import 'package:easyfile/app.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize logger before other startup so DI logs go to file
  await logger.init();
  setupLocator();
  runApp(const EasyFileApp());
}
  