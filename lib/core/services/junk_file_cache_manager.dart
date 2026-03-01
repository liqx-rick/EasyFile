import 'dart:convert';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/junk_file_scan_config.dart';
import 'package:easyfile/data/models/junk_file_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 垃圾文件扫描缓存管理器
class JunkFileCacheManager {
  static const String _cacheKey = 'junk_files_cache';
  static const String _configKey = 'junk_files_config';
  static const String _timestampKey = 'junk_files_timestamp';
  static const int _cacheValidDays = 7; // 缓存有效期7天

  /// 保存缓存
  Future<void> saveCache(List<JunkFileItem> files, JunkFileScanConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 保存文件列表
      final filesJson = jsonEncode(files.map((f) => f.toJson()).toList());
      await prefs.setString(_cacheKey, filesJson);

      // 保存配置
      await prefs.setString(_configKey, jsonEncode(config.toJson()));

      // 保存时间戳
      await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);

      logger.i('垃圾文件缓存已保存: ${files.length} 个');
    } catch (e) {
      logger.e('保存垃圾文件缓存失败: $e');
    }
  }

  /// 加载缓存
  Future<List<JunkFileItem>?> loadCache(JunkFileScanConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查缓存是否过期
      final timestamp = prefs.getInt(_timestampKey);
      if (timestamp == null) {
        logger.d('没有垃圾文件缓存');
        return null;
      }

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final isExpired = DateTime.now().difference(cacheTime).inDays > _cacheValidDays;
      if (isExpired) {
        logger.d('垃圾文件缓存已过期');
        return null;
      }

      // 检查配置是否匹配
      final cachedConfigJson = prefs.getString(_configKey);
      if (cachedConfigJson == null) {
        logger.d('没有垃圾文件配置缓存');
        return null;
      }

      final cachedConfig = JunkFileScanConfig.fromJson(jsonDecode(cachedConfigJson));
      if (cachedConfig.description != config.description) {
        logger.d('垃圾文件配置不匹配，忽略缓存');
        logger.d('缓存配置: ${cachedConfig.description}');
        logger.d('当前配置: ${config.description}');
        return null;
      }

      // 加载文件列表
      final filesJson = prefs.getString(_cacheKey);
      if (filesJson == null) {
        logger.d('没有垃圾文件列表缓存');
        return null;
      }

      final filesList = (jsonDecode(filesJson) as List).map((json) => JunkFileItem.fromJson(json)).toList();

      logger.i('加载垃圾文件缓存成功: ${filesList.length} 个');
      return filesList;
    } catch (e) {
      logger.e('加载垃圾文件缓存失败: $e');
      await clearCache();
      return null;
    }
  }

  /// 清空缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_configKey);
      await prefs.remove(_timestampKey);
      logger.i('垃圾文件缓存已清空');
    } catch (e) {
      logger.e('清空垃圾文件缓存失败: $e');
    }
  }

  /// 获取缓存信息
  Future<Map<String, dynamic>> getCacheInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final timestamp = prefs.getInt(_timestampKey);
      final filesJson = prefs.getString(_cacheKey);
      final configJson = prefs.getString(_configKey);

      if (timestamp == null || filesJson == null || configJson == null) {
        return {
          'exists': false,
          'timestamp': null,
          'fileCount': 0,
          'isExpired': false,
        };
      }

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final isExpired = DateTime.now().difference(cacheTime).inDays > _cacheValidDays;

      final filesList = jsonDecode(filesJson) as List;

      return {
        'exists': true,
        'timestamp': cacheTime,
        'fileCount': filesList.length,
        'isExpired': isExpired,
        'config': JunkFileScanConfig.fromJson(jsonDecode(configJson)),
      };
    } catch (e) {
      logger.e('获取垃圾文件缓存信息失败: $e');
      return {
        'exists': false,
        'timestamp': null,
        'fileCount': 0,
        'isExpired': false,
      };
    }
  }
}
