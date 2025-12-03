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

  /// 获取应用的首次安装时间
  ///
  /// 返回毫秒时间戳
  Future<int?> getFirstInstallTime(String packageName) async {
    try {
      final result = await _channel.invokeMethod<int>(
        'getFirstInstallTime',
        {'packageName': packageName},
      );
      return result;
    } catch (e) {
      logger.e('Error getting first install time for $packageName: $e');
      return null;
    }
  }

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

      // 调用原生API获取真实存储信息
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getAppStorageStats',
        {'packageName': packageName},
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

  /// 批量查询应用存储信息
  ///
  /// 分批查询以避免阻塞UI
  Future<Map<String, AppStorageInfo>> batchGetStorageInfo(
    List<String> packageNames, {
    Function(int current, int total)? onProgress,
  }) async {
    final results = <String, AppStorageInfo>{};
    final batchSize = 10;

    for (var i = 0; i < packageNames.length; i += batchSize) {
      final batch = packageNames.skip(i).take(batchSize);

      for (final packageName in batch) {
        final info = await getAppStorageInfo(packageName);
        if (info != null) {
          results[packageName] = info;
        }

        // 更新进度
        onProgress?.call(
            i + batch.toList().indexOf(packageName) + 1, packageNames.length);
      }

      // 让出CPU时间
      await Future.delayed(const Duration(milliseconds: 50));
    }

    return results;
  }
}
