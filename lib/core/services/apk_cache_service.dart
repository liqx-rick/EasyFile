import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/apk_info.dart';
import '../logger.dart';

/// APK缓存服务
///
/// 提供APK扫描结果的缓存功能，减少重复扫描
class ApkCacheService {
  static const String _cacheKey = 'apk_scan_cache';
  static const String _timestampKey = 'apk_scan_timestamp';
  static const Duration _cacheExpiration = Duration(hours: 24); // 24小时过期

  /// 获取缓存的APK列表
  ///
  /// 返回null表示无缓存或缓存已过期
  Future<List<ApkInfo>?> getCachedApkList() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查缓存时间戳
      final timestampMs = prefs.getInt(_timestampKey);
      if (timestampMs == null) {
        logger.d('[ApkCacheService] 无缓存数据');
        return null;
      }

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);
      final now = DateTime.now();
      final age = now.difference(cacheTime);

      if (age > _cacheExpiration) {
        logger.d('[ApkCacheService] 缓存已过期 (${age.inMinutes}分钟前)');
        return null;
      }

      // 读取缓存数据
      final cacheJson = prefs.getString(_cacheKey);
      if (cacheJson == null) {
        return null;
      }

      final List<dynamic> jsonList = json.decode(cacheJson);
      final apkList = jsonList.map((item) => ApkInfo.fromJson(Map<String, dynamic>.from(item))).toList();

      logger.i('[ApkCacheService] 使用缓存数据: ${apkList.length}个APK (${age.inMinutes}分钟前)');
      return apkList;
    } catch (e) {
      logger.e('[ApkCacheService] 读取缓存失败: $e');
      return null;
    }
  }

  /// 保存APK列表到缓存
  Future<void> saveApkListCache(List<ApkInfo> apkList) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 序列化数据
      final jsonList = apkList.map((apk) => apk.toJson()).toList();
      final cacheJson = json.encode(jsonList);

      // 保存缓存
      await prefs.setString(_cacheKey, cacheJson);
      await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);

      logger.i('[ApkCacheService] 缓存已保存: ${apkList.length}个APK');
    } catch (e) {
      logger.e('[ApkCacheService] 保存缓存失败: $e');
    }
  }

  /// 清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_timestampKey);
      logger.i('[ApkCacheService] 缓存已清除');
    } catch (e) {
      logger.e('[ApkCacheService] 清除缓存失败: $e');
    }
  }

  /// 获取缓存信息（用于智能任务卡）
  ///
  /// 返回APK统计信息：
  /// - apkCount: APK文件数量
  /// - apkSize: APK总大小（字节）
  /// - exists: 缓存是否存在
  /// - isExpired: 缓存是否过期
  Future<Map<String, dynamic>> getCacheInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final timestampMs = prefs.getInt(_timestampKey);
      final cacheJson = prefs.getString(_cacheKey);

      if (timestampMs == null || cacheJson == null) {
        return {
          'exists': false,
          'isExpired': false,
          'apkCount': 0,
          'apkSize': 0,
        };
      }

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);
      final age = DateTime.now().difference(cacheTime);
      final isExpired = age > _cacheExpiration;

      // 解析APK列表
      final List<dynamic> jsonList = json.decode(cacheJson);
      final apkList = jsonList.map((item) => ApkInfo.fromJson(Map<String, dynamic>.from(item))).toList();

      // 计算总大小
      int totalSize = 0;
      for (final apk in apkList) {
        totalSize += apk.fileSize;
      }

      return {
        'exists': true,
        'isExpired': isExpired,
        'apkCount': apkList.length,
        'apkSize': totalSize,
        'timestamp': cacheTime,
      };
    } catch (e) {
      logger.e('[ApkCacheService] 获取缓存信息失败: $e');
      return {
        'exists': false,
        'isExpired': false,
        'apkCount': 0,
        'apkSize': 0,
      };
    }
  }
}
