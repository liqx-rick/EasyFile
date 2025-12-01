import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';

/// 重复文件扫描配置缓存管理器
///
/// 只缓存用户的扫描配置（记住上次选择），不缓存扫描结果
/// 原因：文件系统随时变化，缓存的扫描结果可能过期导致误删
class DuplicateFileCacheManager {
  static const String _configKey = 'duplicate_file_last_scan_config';

  /// 保存最后一次扫描配置
  Future<void> saveConfig(DuplicateFileScanConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, jsonEncode(config.toJson()));
      logger.d('Duplicate scan config saved: ${config.description}');
    } catch (e) {
      logger.e('Failed to save duplicate scan config: $e');
    }
  }

  /// 加载最后一次扫描配置
  Future<DuplicateFileScanConfig?> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_configKey);

      if (configJson == null) {
        logger.d('No duplicate scan config found');
        return null;
      }

      final config = DuplicateFileScanConfig.fromJson(jsonDecode(configJson));
      logger.d('Duplicate scan config loaded: ${config.description}');
      return config;
    } catch (e) {
      logger.e('Failed to load duplicate scan config: $e');
      await clearConfig();
      return null;
    }
  }

  /// 清空配置缓存
  Future<void> clearConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_configKey);
      logger.i('Duplicate scan config cleared');
    } catch (e) {
      logger.e('Failed to clear config: $e');
    }
  }
}
