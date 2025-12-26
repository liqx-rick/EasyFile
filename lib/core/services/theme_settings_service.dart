import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';

/// 主题设置管理服务 - 管理应用主题的持久化存储和读取
class ThemeSettingsService extends ChangeNotifier {
  static final ThemeSettingsService _instance = ThemeSettingsService._internal();
  factory ThemeSettingsService() => _instance;

  ThemeSettingsService._internal();

  static const String _themeKey = 'app_theme_mode';
  bool _initialized = false;

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  /// 从 SharedPreferences 初始化主题
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString(_themeKey);
      _themeMode = savedTheme != null ? _stringToThemeMode(savedTheme) : ThemeMode.system;
      _initialized = true;
      logger.i('🎨 Theme initialized: $_themeMode');
    } catch (e) {
      logger.e('Error initializing theme: $e');
      _themeMode = ThemeMode.system;
      _initialized = true;
    }
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    try {
      _themeMode = mode;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, mode.toString());
      logger.i('🎨 Theme set to: $mode');
      notifyListeners();
    } catch (e) {
      logger.e('Error setting theme: $e');
    }
  }

  /// 切换主题模式（Light → Dark → System → Light）
  Future<void> toggleThemeMode() async {
    final newMode = switch (_themeMode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    await setThemeMode(newMode);
  }

  /// 将字符串转换为 ThemeMode
  ThemeMode _stringToThemeMode(String themeString) {
    switch (themeString) {
      case 'ThemeMode.light':
        return ThemeMode.light;
      case 'ThemeMode.dark':
        return ThemeMode.dark;
      case 'ThemeMode.system':
      default:
        return ThemeMode.system;
    }
  }
}