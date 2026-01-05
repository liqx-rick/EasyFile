import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/app_info.dart';

/// 应用列表缓存管理器
/// 
/// 缓存完整的应用列表（包括图标），加快首次加载速度
class AppListCacheManager {
  static const String _cacheKeyUserApps = 'app_list_cache_user';
  static const String _cacheKeyAllApps = 'app_list_cache_all';
  static const String _cacheTimeKeyUser = 'app_list_cache_time_user';
  static const String _cacheTimeKeyAll = 'app_list_cache_time_all';
  static const Duration _cacheDuration = Duration(hours: 24);

  /// 获取缓存的应用列表
  /// 
  /// [includeSystemApps] 是否包含系统应用
  Future<List<EasyFileAppInfo>?> getCachedAppList({
    bool includeSystemApps = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = includeSystemApps ? _cacheKeyAllApps : _cacheKeyUserApps;
      final timeKey = includeSystemApps ? _cacheTimeKeyAll : _cacheTimeKeyUser;
      
      final cachedJson = prefs.getString(cacheKey);
      final cachedTimeStr = prefs.getString(timeKey);
      
      if (cachedJson == null || cachedTimeStr == null) {
        logger.d('No cached app list found (includeSystem: $includeSystemApps)');
        return null;
      }
      
      final cachedTime = DateTime.parse(cachedTimeStr);
      if (DateTime.now().difference(cachedTime) > _cacheDuration) {
        logger.d('App list cache expired (includeSystem: $includeSystemApps)');
        return null;
      }
      
      final jsonList = jsonDecode(cachedJson) as List;
      final apps = jsonList
          .map((json) => EasyFileAppInfo.fromJson(json as Map<String, dynamic>))
          .toList();
      
      logger.i('Loaded ${apps.length} apps from cache (includeSystem: $includeSystemApps)');
      return apps;
    } catch (e) {
      logger.e('Error loading cached app list: $e');
      return null;
    }
  }

  /// 保存应用列表到缓存
  /// 
  /// 包含所有应用信息（包括图标）
  Future<void> saveAppList(
    List<EasyFileAppInfo> apps, {
    bool includeSystemApps = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = includeSystemApps ? _cacheKeyAllApps : _cacheKeyUserApps;
      final timeKey = includeSystemApps ? _cacheTimeKeyAll : _cacheTimeKeyUser;
      
      // 直接缓存应用列表（包括图标）
      final jsonList = apps.map((app) => app.toJson()).toList();
      await prefs.setString(cacheKey, jsonEncode(jsonList));
      await prefs.setString(timeKey, DateTime.now().toIso8601String());
      
      logger.i('Cached ${apps.length} apps with icons (includeSystem: $includeSystemApps)');
    } catch (e) {
      logger.e('Error saving app list to cache: $e');
    }
  }

  /// 清除应用列表缓存
  Future<void> clearCache({bool includeSystemApps = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = includeSystemApps ? _cacheKeyAllApps : _cacheKeyUserApps;
      final timeKey = includeSystemApps ? _cacheTimeKeyAll : _cacheTimeKeyUser;
      
      await prefs.remove(cacheKey);
      await prefs.remove(timeKey);
      
      logger.i('Cleared app list cache (includeSystem: $includeSystemApps)');
    } catch (e) {
      logger.e('Error clearing app list cache: $e');
    }
  }

  /// 清除所有应用列表缓存
  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKeyUserApps);
      await prefs.remove(_cacheKeyAllApps);
      await prefs.remove(_cacheTimeKeyUser);
      await prefs.remove(_cacheTimeKeyAll);
      
      logger.i('Cleared all app list cache');
    } catch (e) {
      logger.e('Error clearing all app list cache: $e');
    }
  }
}
