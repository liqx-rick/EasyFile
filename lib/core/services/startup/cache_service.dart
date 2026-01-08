import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';

/// 缓存管理服务
///
/// 检查缓存的有效性
/// 使用 SharedPreferences 存储缓存元数据
class CacheService {
  static const int _defaultCacheValidityDays = 7; // 缓存7天有效

  /// 检查缓存是否有效
  ///
  /// 返回 true：缓存有效，可以使用
  /// 返回 false：缓存无效或已过期，需要重新扫描
  Future<bool> isCacheValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 获取最后扫描时间戳
      final lastScanTimeStr = prefs.getString('last_full_scan_time');
      if (lastScanTimeStr == null) {
        logger.i('[CacheService] No cache found (never scanned)');
        return false;
      }

      final lastScanTime = DateTime.tryParse(lastScanTimeStr);
      if (lastScanTime == null) {
        logger.w('[CacheService] Invalid cache timestamp format');
        return false;
      }

      // 检查缓存是否过期
      final daysSinceScan = DateTime.now().difference(lastScanTime).inDays;
      final isValid = daysSinceScan < _defaultCacheValidityDays;

      logger
          .i('[CacheService] Cache age: $daysSinceScan days, valid: $isValid');
      return isValid;
    } catch (e) {
      logger.e('[CacheService] Error checking cache validity: $e');
      // 如果出错，认为缓存无效，重新扫描
      return false;
    }
  }

  /// 获取最后扫描时间
  Future<DateTime?> getLastScanTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timeStr = prefs.getString('last_full_scan_time');
      if (timeStr == null) return null;
      return DateTime.tryParse(timeStr);
    } catch (e) {
      logger.e('[CacheService] Error getting last scan time: $e');
      return null;
    }
  }

  /// 更新最后扫描时间
  ///
  /// 应该在完整扫描完成（P2完成）后调用
  Future<void> updateLastScanTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();
      await prefs.setString('last_full_scan_time', now);
      logger.i('[CacheService] Updated last scan time to: $now');
    } catch (e) {
      logger.e('[CacheService] Error updating last scan time: $e');
      rethrow;
    }
  }

  /// 清除缓存
  /// 用于测试或强制重新扫描
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_full_scan_time');
      logger.i('[CacheService] Cache cleared');
    } catch (e) {
      logger.e('[CacheService] Error clearing cache: $e');
      rethrow;
    }
  }
}
