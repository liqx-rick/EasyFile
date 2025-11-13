import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/app_dir_config.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/data/models/folder_stats.dart';
import 'package:easyfile/data/services/folder_analyzer.dart';
import 'package:easyfile/data/services/alias_recommendation_service.dart';

/// 应用文件夹信息
class AppFolder {
  final String name;
  final String path;
  final int priority;
  final FolderStats stats;
  final String? iconName;

  const AppFolder({
    required this.name,
    required this.path,
    required this.priority,
    required this.stats,
    this.iconName,
  });

  /// 转换为 QuickAccessFolder
  QuickAccessFolder toQuickAccessFolder() {
    final aliasService = AliasRecommendationService();
    final recommendedAlias = aliasService.recommendAlias(
      path: path,
      originalName: name,
      type: QuickAccessFolderType.appRoot,
    );
    
    return QuickAccessFolder(
      id: '${DateTime.now().millisecondsSinceEpoch}_$name',
      path: path,
      originalName: name,
      recommendedAlias: recommendedAlias.isNotEmpty ? recommendedAlias : null,
      type: QuickAccessFolderType.appRoot,
      createdAt: DateTime.now(),
      stats: stats,
      iconName: iconName,
      pinned: false,
      isAddedToQuickAccess: false, // 扫描出的项默认不加入快速访问
      isHidden: false,
      homeDisplayOrder: null,
    );
  }
}

/// 智能应用目录扫描服务
class SmartAppScanner {
  final FolderAnalyzer _analyzer = FolderAnalyzer();
  
  static const String _lastScanTimeKey = 'last_app_scan_time';
  static const String _scannedAppsKey = 'scanned_app_paths';

  /// 首次扫描（仅扫描 Tier1 高优先级应用）
  Future<List<AppFolder>> firstTimeScan() async {
    logger.i('Starting first-time app scan (Tier1 only)');
    final results = await scanApps(AppDirConfigs.tier1Apps);
    await _saveLastScanTime();
    await _saveScannedApps(results);
    logger.i('First-time scan completed: ${results.length} apps found');
    return results;
  }

  /// 增量扫描（检测自上次扫描后的变化）
  Future<List<AppFolder>> incrementalScan() async {
    logger.i('Starting incremental app scan');
    
    final lastScanTime = await _getLastScanTime();
    if (lastScanTime == null) {
      logger.w('No previous scan time found, performing first-time scan');
      return await firstTimeScan();
    }

    // 只扫描 Tier1 应用
    final currentApps = await scanApps(AppDirConfigs.tier1Apps);
    final previousPaths = await _getScannedAppPaths();
    
    // 找出新增的应用
    final newApps = currentApps
        .where((app) => !previousPaths.contains(app.path))
        .toList();

    if (newApps.isNotEmpty) {
      await _saveLastScanTime();
      await _saveScannedApps(currentApps);
      logger.i('Incremental scan found ${newApps.length} new apps');
    } else {
      logger.i('Incremental scan: no new apps found');
    }

    return newApps;
  }

  /// 用户主动扫描（Tier1 + Tier2）
  Future<List<AppFolder>> userInitiatedScan() async {
    logger.i('Starting user-initiated app scan (Tier1 + Tier2)');
    final configs = [
      ...AppDirConfigs.tier1Apps,
      ...AppDirConfigs.tier2Apps,
    ];
    
    final results = await scanApps(configs);
    await _saveLastScanTime();
    await _saveScannedApps(results);
    logger.i('User-initiated scan completed: ${results.length} apps found');
    return results;
  }

  /// 深度扫描（全部 Tier1 + Tier2 + Tier3）
  Future<List<AppFolder>> deepScan() async {
    logger.i('Starting deep app scan (All tiers)');
    final results = await scanApps(AppDirConfigs.allApps);
    await _saveLastScanTime();
    await _saveScannedApps(results);
    logger.i('Deep scan completed: ${results.length} apps found');
    return results;
  }

  /// 扫描应用目录
  Future<List<AppFolder>> scanApps(List<AppDirConfig> configs) async {
    final results = <AppFolder>[];
    
    logger.i('Starting app scan with ${configs.length} configs');
    
    for (final config in configs) {
      try {
        logger.d('Scanning ${config.name}...');
        // 尝试主路径
        var appFolder = await _tryPath(config, config.path);
        
        // 如果主路径失败，尝试备选路径
        if (appFolder == null && config.alternativePaths.isNotEmpty) {
          logger.d('Main path failed, trying ${config.alternativePaths.length} alternatives');
          for (final altPath in config.alternativePaths) {
            appFolder = await _tryPath(config, altPath);
            if (appFolder != null) break;
          }
        }
        
        if (appFolder != null) {
          results.add(appFolder);
          logger.i('✓ Found app: ${config.name} at ${appFolder.path}');
        } else {
          logger.d('✗ Not found: ${config.name}');
        }
      } catch (e) {
        logger.w('Error scanning app ${config.name}: $e');
      }
    }
    
    logger.i('Scan completed: ${results.length} apps found');
    return results;
  }

  /// 尝试扫描指定路径
  Future<AppFolder?> _tryPath(AppDirConfig config, String path) async {
    final dir = Directory(path);
    
    if (!dir.existsSync()) {
      logger.d('Path does not exist: $path (${config.name})');
      return null;
    }
    
    logger.d('Found path: $path (${config.name})');

    // 分析文件夹统计
    final stats = await _analyzer.analyzeFolderStats(
      path,
      maxDepth: 1,
      includeHidden: false,
    );

    // 过滤条件：必须有足够内容才推荐
    if (!_shouldIncludeApp(stats)) {
      logger.d('Skipping ${config.name}: insufficient content');
      return null;
    }

    return AppFolder(
      name: config.name,
      path: path,
      priority: config.priority,
      stats: stats,
      iconName: config.iconName,
    );
  }

  /// 判断是否应该包含该应用
  bool _shouldIncludeApp(FolderStats stats) {
    // 条件1: 至少1个文件即可（用于测试和实际应用）
    final hasEnoughFiles = stats.totalFiles >= 1;
    final hasEnoughSize = stats.totalSizeMB >= 0.001; // 1KB即可
    
    final shouldInclude = hasEnoughFiles || hasEnoughSize;
    logger.d('Should include app: $shouldInclude (files: ${stats.totalFiles}, size: ${stats.totalSizeMB}MB)');
    
    return shouldInclude;
  }

  /// 检测新应用（与已知列表对比）
  Future<List<AppFolder>> detectNewApps(List<String> knownPaths) async {
    final allApps = await userInitiatedScan();
    return allApps.where((app) => !knownPaths.contains(app.path)).toList();
  }

  /// 根据优先级扫描
  Future<List<AppFolder>> scanByPriority(int priority) async {
    final configs = AppDirConfigs.getAppsByPriority(priority);
    return await scanApps(configs);
  }

  /// 扫描特定应用
  Future<AppFolder?> scanSpecificApp(String appName) async {
    final config = AppDirConfigs.allApps.firstWhere(
      (c) => c.name.toLowerCase() == appName.toLowerCase(),
      orElse: () => throw Exception('App config not found: $appName'),
    );
    
    final results = await scanApps([config]);
    return results.isNotEmpty ? results.first : null;
  }

  /// 验证应用目录是否仍然有效
  Future<bool> validateAppFolder(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return false;
    }
    
    return await _analyzer.hasEnoughContent(path, minFiles: 5, minSizeMB: 1.0);
  }

  /// 批量验证应用目录
  Future<Map<String, bool>> validateAppFolders(List<String> paths) async {
    final results = <String, bool>{};
    
    for (final path in paths) {
      results[path] = await validateAppFolder(path);
    }
    
    return results;
  }

  // ==================== 私有辅助方法 ====================

  /// 保存最后扫描时间
  Future<void> _saveLastScanTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastScanTimeKey,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      logger.e('Failed to save last scan time: $e');
    }
  }

  /// 获取最后扫描时间
  Future<DateTime?> _getLastScanTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timeStr = prefs.getString(_lastScanTimeKey);
      return timeStr != null ? DateTime.parse(timeStr) : null;
    } catch (e) {
      logger.e('Failed to get last scan time: $e');
      return null;
    }
  }

  /// 保存已扫描的应用路径
  Future<void> _saveScannedApps(List<AppFolder> apps) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = apps.map((app) => app.path).toList();
      await prefs.setStringList(_scannedAppsKey, paths);
    } catch (e) {
      logger.e('Failed to save scanned apps: $e');
    }
  }

  /// 获取已扫描的应用路径
  Future<List<String>> _getScannedAppPaths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_scannedAppsKey) ?? [];
    } catch (e) {
      logger.e('Failed to get scanned app paths: $e');
      return [];
    }
  }

  /// 清除扫描缓存
  Future<void> clearScanCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastScanTimeKey);
      await prefs.remove(_scannedAppsKey);
      logger.i('Scan cache cleared');
    } catch (e) {
      logger.e('Failed to clear scan cache: $e');
    }
  }

  /// 获取上次扫描的统计信息
  Future<Map<String, dynamic>> getScanStatistics() async {
    final lastScanTime = await _getLastScanTime();
    final scannedPaths = await _getScannedAppPaths();
    
    return {
      'lastScanTime': lastScanTime?.toIso8601String(),
      'scannedAppsCount': scannedPaths.length,
      'scannedPaths': scannedPaths,
    };
  }
}
