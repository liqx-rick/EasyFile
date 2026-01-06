import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/app_info.dart';

/// 应用存储信息缓存管理器
class AppStorageCacheManager {
  static const String _keyPrefix = 'app_storage_';
  static const Duration _cacheDuration = Duration(hours: 6);

  /// 获取缓存的存储信息
  Future<AppStorageInfo?> getCached(String packageName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _keyPrefix + packageName;
      final cached = prefs.getString(key);

      if (cached != null) {
        final json = jsonDecode(cached) as Map<String, dynamic>;
        final info = AppStorageInfo.fromJson(json);

        // 检查缓存是否过期
        if (DateTime.now().difference(info.cachedTime) < _cacheDuration) {
          logger.d('Using cached storage info for $packageName');
          return info;
        } else {
          logger.d('Cache expired for $packageName');
          // 清除过期缓存
          await prefs.remove(key);
        }
      }

      return null;
    } catch (e) {
      logger.e('Error loading cached storage info for $packageName: $e');
      return null;
    }
  }

  /// 保存存储信息到缓存
  Future<void> cache(String packageName, AppStorageInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _keyPrefix + packageName;
      await prefs.setString(key, jsonEncode(info.toJson()));
      logger.d('Cached storage info for $packageName');
    } catch (e) {
      logger.e('Error caching storage info for $packageName: $e');
    }
  }



  /// 清除指定应用的缓存
  Future<void> clearCache(String packageName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _keyPrefix + packageName;
      await prefs.remove(key);
      logger.d('Cleared cache for $packageName');
    } catch (e) {
      logger.e('Error clearing cache for $packageName: $e');
    }
  }

  /// 清除所有应用存储缓存
  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith(_keyPrefix));

      for (final key in keys) {
        await prefs.remove(key);
      }

      logger.i('Cleared all app storage cache');
    } catch (e) {
      logger.e('Error clearing all cache: $e');
    }
  }


}
