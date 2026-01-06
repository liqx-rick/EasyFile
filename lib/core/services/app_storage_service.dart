import 'package:flutter/services.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/app_info.dart';

/// 应用存储服务
///
/// 用于查询应用的存储占用信息，包括：
/// 1. 应用本身大小
/// 2. 应用数据大小
/// 3. 应用缓存大小
///
/// 使用Android原生StorageStatsManager API (Android 8.0+)
class AppStorageService {
  static const MethodChannel _channel =
      MethodChannel('com.easyfile/storage_stats');

  /// 查询应用存储信息
  ///
  /// 使用Android的StorageStatsManager API获取真实数据
  Future<AppStorageInfo?> getAppStorageInfo(String packageName) async {
    try {
      // 检查平台支持
      final isSupported =
          await _channel.invokeMethod<bool>('isSupported') ?? false;
      if (!isSupported) {
        logger.w(
            'StorageStatsManager not supported on this device (requires Android 8.0+)');
        return null;
      }

      // 调用原生API获取真实存储信息（添加10秒超时）
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getAppStorageStats',
        {'packageName': packageName},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          logger.w('Timeout getting storage stats for $packageName after 10s');
          return null;
        },
      );

      if (result != null) {
        // 将Map<Object?, Object?>转换为Map<String, int>
        final appSize = (result['appSize'] as num?)?.toInt() ?? 0;
        final dataSize = (result['dataSize'] as num?)?.toInt() ?? 0;
        final cacheSize = (result['cacheSize'] as num?)?.toInt() ?? 0;

        logger.d(
            'Got storage stats for $packageName: app=${appSize}B, data=${dataSize}B, cache=${cacheSize}B');

        return AppStorageInfo(
          appSize: appSize,
          dataSize: dataSize,
          cacheSize: cacheSize,
        );
      }

      return null;
    } catch (e) {
      logger.e('Error getting storage info for $packageName: $e');
      return null;
    }
  }


}
