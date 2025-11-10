import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:easyfile/core/logger.dart';

/// 主题设置数据源
///
/// 负责应用主题设置的持久化存储
class ThemeLocalSource {
  static const String _fileName = 'theme_settings.json';

  /// 获取主题设置文件路径
  Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}${Platform.pathSeparator}$_fileName';
  }

  /// 获取当前主题模式
  Future<ThemeMode> getThemeMode() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (!await file.exists()) {
        logger
            .d('Theme settings file does not exist, returning system default');
        return ThemeMode.system;
      }

      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      final themeString = json['themeMode'] as String? ?? 'system';
      final themeMode = _stringToThemeMode(themeString);

      logger.d('Loaded theme mode: $themeMode');
      return themeMode;
    } catch (e, stackTrace) {
      logger.e('Error loading theme mode: $e\nStackTrace: $stackTrace');
      return ThemeMode.system;
    }
  }

  /// 保存主题模式
  Future<bool> saveThemeMode(ThemeMode themeMode) async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      // 确保目录存在
      await file.parent.create(recursive: true);

      final json = {
        'themeMode': _themeModeToString(themeMode),
        'savedAt': DateTime.now().toIso8601String(),
      };

      await file.writeAsString(jsonEncode(json));

      logger.d('Saved theme mode: $themeMode');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error saving theme mode: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 获取是否启用深色主题（基于系统和用户设置）
  Future<bool> isDarkTheme(Brightness systemBrightness) async {
    final themeMode = await getThemeMode();

    switch (themeMode) {
      case ThemeMode.light:
        return false;
      case ThemeMode.dark:
        return true;
      case ThemeMode.system:
        return systemBrightness == Brightness.dark;
    }
  }

  /// 清除主题设置
  Future<bool> clearThemeSettings() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      logger.d('Cleared theme settings');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error clearing theme settings: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 将 ThemeMode 转换为字符串
  String _themeModeToString(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// 将字符串转换为 ThemeMode
  ThemeMode _stringToThemeMode(String themeString) {
    switch (themeString.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
