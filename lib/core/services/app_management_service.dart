import 'package:installed_apps/installed_apps.dart' as installed;
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/app_info.dart';
import 'package:easyfile/core/services/app_storage_service.dart';
import 'package:easyfile/core/services/app_storage_cache_manager.dart';
import 'package:easyfile/core/services/app_list_cache_manager.dart';
import 'package:easyfile/core/services/usage_stats_service.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用管理服务
///
/// 提供应用管理相关的核心功能
class AppManagementService {
  final AppStorageService _storageService;
  final AppStorageCacheManager _cacheManager;
  final AppListCacheManager _appListCacheManager = AppListCacheManager();
  final UsageStatsService _usageStatsService;

  /// 设备基准时间（用户最早安装应用的时间）
  DateTime? _deviceBaselineTime;

  AppManagementService(
    this._storageService,
    this._cacheManager,
    this._usageStatsService,
  ) {
    _loadBaselineTimeFromCache();
  }

  /// 从缓存加载基准时间
  Future<void> _loadBaselineTimeFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('device_baseline_time');
      if (timestamp != null) {
        _deviceBaselineTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        logger.i('Loaded baseline time from cache: $_deviceBaselineTime');
      }
    } catch (e) {
      logger.e('Failed to load baseline time from cache: $e');
    }
  }

  /// 保存基准时间到缓存
  Future<void> _saveBaselineTimeToCache() async {
    if (_deviceBaselineTime == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('device_baseline_time', _deviceBaselineTime!.millisecondsSinceEpoch);
      logger.i('Saved baseline time to cache: $_deviceBaselineTime');
    } catch (e) {
      logger.e('Failed to save baseline time to cache: $e');
    }
  }

  /// 获取设备基准时间
  DateTime? get deviceBaselineTime => _deviceBaselineTime;

  /// 确保设备基准时间已加载
  /// 
  /// 用于从缓存加载应用时，确保 baseline 已从 SharedPreferences 加载
  Future<void> loadDeviceBaselineTime() async {
    if (_deviceBaselineTime == null) {
      await _loadBaselineTimeFromCache();
    }
  }

  /// 验证并更新设备基准时间
  /// 
  /// 从缓存加载用户应用时调用，确保baseline准确
  /// 只针对用户安装的应用列表（不包括系统应用）
  Future<void> validateAndUpdateBaseline(List<EasyFileAppInfo> apps) async {
    // 确保已加载缓存的baseline
    await loadDeviceBaselineTime();
    
    // 计算当前应用列表的最早时间
    DateTime? calculatedEarliest;
    final now = DateTime.now();
    
    for (final app in apps) {
      final appTime = app.usageStats?.effectiveLastTime;
      if (appTime != null) {
        // 使用相同的过滤逻辑：距今0-15年内
        final yearsDiff = now.difference(appTime).inDays / 365;
        if (yearsDiff >= 0 && yearsDiff <= 15 && appTime.isBefore(now)) {
          if (calculatedEarliest == null || appTime.isBefore(calculatedEarliest)) {
            calculatedEarliest = appTime;
          }
        }
      }
    }
    
    // 如果计算出的最早时间存在
    if (calculatedEarliest != null) {
      // 比较：如果与缓存的baseline不同（差异超过1天），则更新
      if (_deviceBaselineTime == null || 
          (_deviceBaselineTime!.difference(calculatedEarliest).inDays.abs() > 1)) {
        
        final oldBaseline = _deviceBaselineTime;
        _deviceBaselineTime = calculatedEarliest;
        await _saveBaselineTimeToCache();
        
        logger.i('📌 Baseline更新: $oldBaseline -> $calculatedEarliest');
        logger.i('   差异: ${oldBaseline != null ? oldBaseline.difference(calculatedEarliest).inDays.abs() : "N/A"}天');
      } else {
        logger.i('✓ Baseline验证通过: $_deviceBaselineTime (无需更新)');
      }
    }
  }

  /// 获取已安装的应用列表
  ///
  /// [includeSystemApps] 是否包含系统应用
  /// [withIcons] 是否包含应用图标
  Future<List<EasyFileAppInfo>> getInstalledApps({
    bool includeSystemApps = false,
    bool withIcons = true,
  }) async {
    try {
      logger.i('Loading installed apps (includeSystem: $includeSystemApps)');

      final apps = await installed.InstalledApps.getInstalledApps(
        !includeSystemApps, // excludeSystemApps 参数相反
        withIcons,
      );

      logger.i('Loaded ${apps.length} apps');

      return apps.map((app) => EasyFileAppInfo.fromInstalledApp(app)).toList();
    } catch (e) {
      logger.e('Error loading installed apps: $e');
      return [];
    }
  }

  /// 快速加载应用列表（优先使用缓存）
  ///
  /// [includeSystemApps] 是否包含系统应用
  /// [withIcons] 是否加载图标（缓存已包含图标）
  /// 
  /// 返回: (apps, isFromCache)
  Future<(List<EasyFileAppInfo>, bool)> quickLoadApps({
    bool includeSystemApps = false,
    bool withIcons = true,
  }) async {
    try {
      // 1. 先尝试从缓存加载
      final cachedApps = await _appListCacheManager.getCachedAppList(
        includeSystemApps: includeSystemApps,
      );

      if (cachedApps != null && cachedApps.isNotEmpty) {
        logger.i('Quick loaded ${cachedApps.length} apps from cache (with icons)');
        return (cachedApps, true);
      }

      // 2. 缓存不存在，从 native 加载
      logger.i('No cache found, loading from native');
      final apps = await getInstalledApps(
        includeSystemApps: includeSystemApps,
        withIcons: withIcons,
      );

      return (apps, false);
    } catch (e) {
      logger.e('Error in quick load: $e');
      return (<EasyFileAppInfo>[], false);
    }
  }

  /// 保存应用列表到缓存
  Future<void> saveAppListToCache(
    List<EasyFileAppInfo> apps, {
    bool includeSystemApps = false,
  }) async {
    await _appListCacheManager.saveAppList(
      apps,
      includeSystemApps: includeSystemApps,
    );
  }

  /// 清除应用列表缓存
  Future<void> clearAppListCache({bool includeSystemApps = false}) async {
    await _appListCacheManager.clearCache(includeSystemApps: includeSystemApps);
    logger.i('Cleared app list cache (includeSystem: $includeSystemApps)');
  }

  /// 加载应用存储信息
  ///
  /// 优先使用缓存，缓存过期则重新查询
  /// [includeSystemApps] 是否包含系统应用（用于判断是否计算 baseline）
  Future<List<EasyFileAppInfo>> loadAppsWithStorage(
    List<EasyFileAppInfo> apps, {
    Function(int current, int total)? onProgress,
    bool includeSystemApps = false,
  }) async {
    try {
      // 过滤掉 EasyFile 自身
      apps = apps
          .where((app) => app.packageName != 'com.guangqi.easyfile')
          .toList();

      logger.i('Loading storage info for ${apps.length} apps');

      // 批量获取使用统计（只查询一次）
      final packageNames = apps.map((app) => app.packageName).toList();
      logger.i('======= 开始查询使用统计 =======');
      logger.i('查询参数: packageNames.length=${packageNames.length}, daysBack=90');

      final usageStatsMap = await _usageStatsService.batchGetUsageStats(
        packageNames,
        daysBack: 90, // 使用90天而不是365天 - 华为设备在90天时最稳定
      );

      logger.i(
          'Got usage stats for ${usageStatsMap.length} apps out of ${packageNames.length}');
      logger.i('======= 查询统计完成 =======');

      // 调试：统计有多少应用有lastTimeUsed
      final appsWithTime = usageStatsMap.values
          .where((stats) => stats.lastTimeUsed != null)
          .length;
      logger.i(
          'Apps with lastTimeUsed: $appsWithTime out of ${usageStatsMap.length}');

      for (var i = 0; i < apps.length; i++) {
        final app = apps[i];

        // 1. 尝试从缓存加载存储信息
        var storageInfo = await _cacheManager.getCached(app.packageName);

        // 2. 缓存不存在或已过期，重新查询
        if (storageInfo == null) {
          storageInfo =
              await _storageService.getAppStorageInfo(app.packageName);

          // 保存到缓存
          if (storageInfo != null) {
            await _cacheManager.cache(app.packageName, storageInfo);
          }
        }

        // 3. 获取使用统计
        final usageStats = usageStatsMap[app.packageName];

        // 调试日志：记录没有lastTimeUsed的应用
        if (usageStats != null && usageStats.lastTimeUsed == null) {
          logger.d('App ${app.name} has usageStats but lastTimeUsed is null');
        }

        // 4. 更新应用信息
        if (storageInfo != null || usageStats != null) {
          apps[i] = app.copyWith(
            storageInfo: storageInfo ?? app.storageInfo,
            usageStats: usageStats,
          );
        }

        // 5. 更新进度
        onProgress?.call(i + 1, apps.length);

        // 6. 每10个应用让出一次CPU时间
        if (i % 10 == 0) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      logger.i(
          'Loaded storage info for ${apps.where((a) => a.storageInfo != null).length} apps');
      logger.i(
          'Loaded usage stats for ${apps.where((a) => a.usageStats != null).length} apps');
      logger.i(
          'Apps with lastTimeUsed: ${apps.where((a) => a.usageStats?.lastTimeUsed != null).length}');
      logger.i(
          'Apps with lastUpdateTime: ${apps.where((a) => a.usageStats?.lastUpdateTime != null).length}');
      logger.i(
          'Apps with effectiveLastTime: ${apps.where((a) => a.usageStats?.effectiveLastTime != null).length}');

      // 详细统计各时间段的应用数量（基于effectiveLastTime）
      final now = DateTime.now();
      var within7Days = 0,
          within30Days = 0,
          within180Days = 0,
          beyond180Days = 0,
          noTime = 0;
      var usedTimeUsed = 0, usedUpdateTime = 0;

      for (final app in apps) {
        final effectiveTime = app.usageStats?.effectiveLastTime;
        if (effectiveTime == null) {
          noTime++;
        } else {
          final days = now.difference(effectiveTime).inDays;
          if (days <= 7) {
            within7Days++;
          } else if (days <= 30) {
            within30Days++;
          } else if (days <= 180) {
            within180Days++;
          } else {
            beyond180Days++;
          }

          // 统计数据来源
          if (app.usageStats?.lastTimeUsed != null) {
            usedTimeUsed++;
          } else if (app.usageStats?.lastUpdateTime != null) {
            usedUpdateTime++;
          }
        }
      }
      logger.i(
          'Time distribution (effectiveLastTime): ≤7天=$within7Days, 8-30天=$within30Days, 31-180天=$within180Days, >180天=$beyond180Days, 无时间=$noTime');
      logger.i(
          'Data source: lastTimeUsed=$usedTimeUsed, lastUpdateTime=$usedUpdateTime');

      // 只在加载用户应用时计算设备基准时间
      if (!includeSystemApps) {
        await _calculateDeviceBaselineTime(apps);
      } else {
        logger.i('Skipping baseline calculation (including system apps)');
      }

      return apps;
    } catch (e) {
      logger.e('Error loading apps with storage: $e');
      return apps;
    }
  }

  /// 搜索应用
  Future<List<EasyFileAppInfo>> searchApps(
    List<EasyFileAppInfo> apps,
    String query,
  ) async {
    if (query.isEmpty) return apps;

    final lowerQuery = query.toLowerCase();
    return apps.where((app) {
      return app.name.toLowerCase().contains(lowerQuery) ||
          app.packageName.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// 按占用空间排�?
  List<EasyFileAppInfo> sortBySize(List<EasyFileAppInfo> apps,
      {bool descending = true}) {
    final sorted = List<EasyFileAppInfo>.from(apps);
    sorted.sort((a, b) {
      final sizeA = a.totalSize;
      final sizeB = b.totalSize;
      return descending ? sizeB.compareTo(sizeA) : sizeA.compareTo(sizeB);
    });
    return sorted;
  }

  /// 按应用名称排�?
  /// 按应用名称排序（支持中文拼音排序）
  ///
  /// 中文按拼音排序，英文按首字母排序
  List<EasyFileAppInfo> sortByName(List<EasyFileAppInfo> apps,
      {bool descending = false}) {
    final sorted = List<EasyFileAppInfo>.from(apps);
    sorted.sort((a, b) {
      // 将中文转换为拼音，英文保持不变
      final pinyinA =
          PinyinHelper.getPinyinE(a.name, defPinyin: a.name).toLowerCase();
      final pinyinB =
          PinyinHelper.getPinyinE(b.name, defPinyin: b.name).toLowerCase();

      final comparison = pinyinA.compareTo(pinyinB);
      return descending ? -comparison : comparison;
    });
    return sorted;
  }


  /// 筛选大于指定大小的应用
  List<EasyFileAppInfo> filterByMinSize(
      List<EasyFileAppInfo> apps, int minSizeInBytes) {
    return apps.where((app) => app.totalSize >= minSizeInBytes).toList();
  }

  /// 快速刷新（检测已卸载的应用并更新使用统计）
  ///
  /// 返回仍然已安装的应用列表，并更新使用统计信息
  Future<List<EasyFileAppInfo>> quickRefresh(
    List<EasyFileAppInfo> currentApps, {
    bool includeSystemApps = false,
  }) async {
    try {
      logger.i(
          'Quick refresh: checking for uninstalled apps and updating usage stats');

      // 1. 获取当前实际安装的应用列表（不带图标，快速）
      final installedApps = await getInstalledApps(
        includeSystemApps: includeSystemApps,
        withIcons: false,
      );

      // 2. 创建已安装应用的包名集合
      final installedPackages =
          installedApps.map((app) => app.packageName).toSet();

      // 3. 找出已卸载的应用
      final uninstalledApps = currentApps
          .where((app) => !installedPackages.contains(app.packageName))
          .toList();

      if (uninstalledApps.isNotEmpty) {
        logger.i('Found ${uninstalledApps.length} uninstalled apps');

        // 4. 从缓存中移除已卸载应用的数据
        for (var app in uninstalledApps) {
          await _cacheManager.clearCache(app.packageName);
          logger.i('Removed cache for uninstalled app: ${app.name}');
        }
      }

      // 5. 找出新安装的应用（在 installedApps 但不在 currentApps）
      final currentPackages = currentApps.map((app) => app.packageName).toSet();
      var newApps = installedApps
          .where((app) => !currentPackages.contains(app.packageName))
          .toList();

      if (newApps.isNotEmpty) {
        logger.i('Found ${newApps.length} newly installed apps');
        
        // 重新获取新应用的完整信息（包含图标）
        final newAppsWithIcons = await getInstalledApps(
          includeSystemApps: includeSystemApps,
          withIcons: true,
        );
        
        // 只保留新安装的应用
        final newPackages = newApps.map((app) => app.packageName).toSet();
        newApps = newAppsWithIcons
            .where((app) => newPackages.contains(app.packageName))
            .toList();
        
        // 为新安装的应用加载存储信息
        newApps = await loadAppsWithStorage(
          newApps,
          includeSystemApps: includeSystemApps,
        );
        
        logger.i('Loaded data and icons for ${newApps.length} new apps');
      }

      // 6. 获取仍然安装的应用列表
      var stillInstalled = currentApps
          .where((app) => installedPackages.contains(app.packageName))
          .toList();

      // 7. 更新使用统计（不更新存储信息，保持缓存）
      final packageNames =
          stillInstalled.map((app) => app.packageName).toList();
      final usageStatsMap = await _usageStatsService.batchGetUsageStats(
        packageNames,
        daysBack: 90, // 使用90天而不是365天 - 华为设备在90天时最稳定
      );
      logger.i('Updated usage stats for ${usageStatsMap.length} apps');

      // 8. 更新应用的使用统计
      stillInstalled = stillInstalled.map((app) {
        final usageStats = usageStatsMap[app.packageName];
        if (usageStats != null) {
          return app.copyWith(usageStats: usageStats);
        }
        return app;
      }).toList();

      // 9. 合并新安装的应用和现有应用
      final allApps = [...stillInstalled, ...newApps];

      // 10. quickRefresh 不重新计算 baseline（baseline 只在首次加载用户应用时计算）
      // _calculateDeviceBaselineTime(allApps);

      logger.i('Quick refresh complete: ${allApps.length} apps (${stillInstalled.length} existing + ${newApps.length} new)');
      return allApps;
    } catch (e) {
      logger.e('Error in quick refresh: $e');
      return currentApps; // 出错时返回原列表
    }
  }

  /// 获取应用统计信息
  AppStatistics getStatistics(List<EasyFileAppInfo> apps) {
    final totalCount = apps.length;
    final systemCount = apps.where((app) => app.isSystemApp).length;
    final userCount = totalCount - systemCount;

    final totalSize = apps.fold<int>(0, (sum, app) => sum + app.totalSize);
    final totalCache = apps.fold<int>(
      0,
      (sum, app) => sum + (app.storageInfo?.cacheSize ?? 0),
    );

    final appsWithStorage = apps.where((app) => app.storageInfo != null).length;

    return AppStatistics(
      totalCount: totalCount,
      systemCount: systemCount,
      userCount: userCount,
      totalSize: totalSize,
      totalCache: totalCache,
      appsWithStorageInfo: appsWithStorage,
    );
  }

  /// 计算设备基准时间：用户安装应用的最早时间
  /// 
  /// 使用 effectiveLastTime（lastTimeUsed ?? lastUpdateTime），与UI显示保持一致
  /// 用于推断用户开始使用设备的时间，作为应用显示的基准
  /// 只在加载用户应用（不包括系统应用）时计算
  Future<void> _calculateDeviceBaselineTime(List<EasyFileAppInfo> apps) async {
    DateTime? earliestTime;
    final now = DateTime.now();
    int totalApps = 0;
    int appsWithTime = 0;
    int filteredAbnormalTimes = 0;

    // 遍历所有应用
    for (final app in apps) {
      totalApps++;
      
      // 使用 effectiveLastTime（优先 lastTimeUsed，否则 lastUpdateTime）
      final appTime = app.usageStats?.effectiveLastTime;
      
      if (appTime != null) {
        appsWithTime++;
        
        // 过滤明显异常的时间（距今超过15年或晚于当前时间）
        final yearsDiff = now.difference(appTime).inDays / 365;
        if (yearsDiff >= 0 && yearsDiff <= 15 && appTime.isBefore(now)) {
          if (earliestTime == null || appTime.isBefore(earliestTime)) {
            earliestTime = appTime;
          }
        } else {
          filteredAbnormalTimes++;
        }
      }
    }

    _deviceBaselineTime = earliestTime;

    if (_deviceBaselineTime != null) {
      final years = (now.difference(_deviceBaselineTime!).inDays / 365).floor();
      final months = (now.difference(_deviceBaselineTime!).inDays / 30).floor();
      
      logger.i('Device baseline time: $_deviceBaselineTime (约${years > 0 ? "$years年" : "$months个月"}前)');
      logger.i('统计：共$totalApps个应用，其中$appsWithTime个有时间记录，过滤$filteredAbnormalTimes个异常时间');
      logger.i('早于此时间的应用将显示为"${years > 0 ? "$years+" : ""}年前"');
      
      // 保存到缓存
      await _saveBaselineTimeToCache();
    } else {
      logger.w('Device baseline time: null (应用无时间记录)');
    }
  }
}

/// 应用统计信息
class AppStatistics {
  final int totalCount;
  final int systemCount;
  final int userCount;
  final int totalSize;
  final int totalCache;
  final int appsWithStorageInfo;

  AppStatistics({
    required this.totalCount,
    required this.systemCount,
    required this.userCount,
    required this.totalSize,
    required this.totalCache,
    required this.appsWithStorageInfo,
  });
}
