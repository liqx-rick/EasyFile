import 'package:flutter/services.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/app_usage_stats.dart';

/// 应用使用统计服务
class UsageStatsService {
  static const MethodChannel _channel =
      MethodChannel('com.easyfile/usage_stats');

  /// 获取单个应用的使用统计
  ///
  /// [packageName] 应用包名
  /// [daysBack] 统计最近多少天的数据，默认7天
  Future<AppUsageStats?> getAppUsageStats(
    String packageName, {
    int daysBack = 7,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAppUsageStats',
        {
          'packageName': packageName,
          'daysBack': daysBack,
        },
      );

      if (result == null) {
        logger.d('No usage stats for $packageName');
        return null;
      }

      // 将 Map<dynamic, dynamic> 转换为 Map<String, dynamic>
      final statsMap = Map<String, dynamic>.from(result);
      return AppUsageStats.fromJson(statsMap);
    } catch (e) {
      logger.e('Error getting usage stats for $packageName: $e');
      return null;
    }
  }

  /// 批量获取应用使用统计
  ///
  /// [packageNames] 应用包名列表
  /// [daysBack] 统计最近多少天的数据，默认7天
  /// 返回: Map<包名, 使用统计>
  Future<Map<String, AppUsageStats>> batchGetUsageStats(
    List<String> packageNames, {
    int daysBack = 7,
  }) async {
    try {
      logger.i(
          'Batch getting usage stats for ${packageNames.length} apps (daysBack: $daysBack)');
      logger.i('>>> 调用Android端 batchGetUsageStats <<<');

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'batchGetUsageStats',
        {
          'packageNames': packageNames,
          'daysBack': daysBack,
        },
      );

      logger.i('>>> Android端返回结果 <<<');
      if (result == null) {
        logger.w('Batch usage stats returned null');
        return {};
      }

      logger.i('原始返回数据: ${result.length} 个应用');

      // 转换结果
      final statsMap = <String, AppUsageStats>{};
      result.forEach((key, value) {
        if (value is Map) {
          final packageName = key.toString();
          final rawMap = Map<String, dynamic>.from(value);

          // 打印原始数据
          final lastTimeUsedRaw = rawMap['lastTimeUsed'];
          logger.d(
              '[$packageName] 原始 lastTimeUsed=$lastTimeUsedRaw (type=${lastTimeUsedRaw.runtimeType})');

          final stats = AppUsageStats.fromJson(rawMap);
          statsMap[packageName] = stats;

          // 打印解析后的数据
          if (stats.lastTimeUsed != null) {
            final daysAgo =
                DateTime.now().difference(stats.lastTimeUsed!).inDays;
            logger.d(
                '[$packageName] 解析后 lastTimeUsed=${stats.lastTimeUsed}, $daysAgo天前');
          } else {
            logger.d('[$packageName] 解析后 lastTimeUsed=null');
          }
        }
      });

      logger.i('Got usage stats for ${statsMap.length} apps');
      return statsMap;
    } catch (e) {
      logger.e('Error batch getting usage stats: $e');
      return {};
    }
  }

  /// 获取僵尸应用列表（超过指定天数未使用）
  ///
  /// [packageNames] 要检查的应用包名列表
  /// [daysThreshold] 天数阈值，默认90天
  Future<List<String>> getZombieApps(
    List<String> packageNames, {
    int daysThreshold = 90,
  }) async {
    try {
      final statsMap = await batchGetUsageStats(
        packageNames,
        daysBack: daysThreshold,
      );

      final zombieApps = <String>[];
      for (final packageName in packageNames) {
        final stats = statsMap[packageName];
        // 没有使用记录，或者超过阈值未使用
        if (stats == null) {
          zombieApps.add(packageName);
        } else {
          final days = stats.daysSinceLastTime;
          if (days == null || days > daysThreshold) {
            zombieApps.add(packageName);
          }
        }
      }

      logger.i('Found ${zombieApps.length} zombie apps ($daysThreshold+ days)');
      return zombieApps;
    } catch (e) {
      logger.e('Error getting zombie apps: $e');
      return [];
    }
  }
}
