import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/app_dir_config.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/data/models/folder_stats.dart';
import 'package:easyfile/data/services/folder_analyzer.dart';
import 'package:easyfile/data/services/alias_recommendation_service.dart';

/// 用户文件夹信息
class UserFolder {
  final String name;
  final String path;
  final FolderStats stats;
  final DateTime createdAt;
  final QuickAccessFolderType type;
  final String? parentApp;

  const UserFolder({
    required this.name,
    required this.path,
    required this.stats,
    required this.createdAt,
    required this.type,
    this.parentApp,
  });

  /// 转换为 QuickAccessFolder
  QuickAccessFolder toQuickAccessFolder() {
    final aliasService = AliasRecommendationService();
    final recommendedAlias = aliasService.recommendAlias(
      path: path,
      originalName: name,
      stats: stats,
      type: type,
    );

    return QuickAccessFolder(
      id: '${DateTime.now().millisecondsSinceEpoch}_$name',
      path: path,
      originalName: name,
      recommendedAlias: recommendedAlias.isNotEmpty ? recommendedAlias : null,
      type: type,
      parentApp: parentApp,
      createdAt: createdAt,
      stats: stats,
      pinned: false,
      isAddedToQuickAccess: false, // 检测出的项默认不加入快速访问
      isHidden: false,
      homeDisplayOrder: null,
    );
  }
}

/// 用户自建目录检测服务
class UserFolderDetector {
  final FolderAnalyzer _analyzer = FolderAnalyzer();

  static const String _lastDetectionTimeKey = 'last_user_folder_detection_time';
  static const String _detectedFoldersKey = 'detected_user_folder_paths';

  /// 扫描范围：只扫描特定区域，避免全盘扫描
  static const List<String> scanRoots = [
    '/storage/emulated/0', // 主存储根目录
    '/storage/emulated/0/Download', // 下载目录（注意Android上是Download不是Downloads）
    '/storage/emulated/0/Documents', // 文档目录
  ];

  /// 排除目录：系统和应用目录不扫描
  static List<String> get _excludedPaths => [
        '/storage/emulated/0/Android',
        '/storage/emulated/0/.thumbnails',
        '/storage/emulated/0/DCIM/.thumbnails',
        '/storage/emulated/0/Alarms',
        '/storage/emulated/0/Notifications',
        '/storage/emulated/0/Ringtones',
        '/storage/emulated/0/Podcasts',
        // 添加所有应用目录路径
        ...AppDirConfigs.allApps.map((app) => app.path),
        ...AppDirConfigs.allApps.expand((app) => app.alternativePaths),
      ];

  /// 检测用户自建目录
  Future<List<UserFolder>> detectUserFolders() async {
    logger.i('Starting user folder detection');
    final results = <UserFolder>[];

    for (final root in scanRoots) {
      final dir = Directory(root);
      if (!dir.existsSync()) {
        logger.d('Scan root does not exist: $root');
        continue;
      }

      try {
        // 只扫描一级子目录（避免递归过深）
        final entities = dir.listSync(followLinks: false);

        for (final entity in entities) {
          if (entity is! Directory) continue;

          final path = entity.path;

          // 跳过系统和应用目录
          if (_shouldExclude(path)) {
            continue;
          }

          // 分析文件夹
          final stats = await _analyzer.analyzeFolderStats(
            path,
            maxDepth: 1,
            includeHidden: false,
          );

          // 验证是否是有效的用户文件夹
          if (!_isValidUserFolder(path, stats)) {
            continue;
          }

          // 检测文件夹类型和归属
          final detectionResult = _detectFolderType(path);

          final userFolder = UserFolder(
            name: path.split(Platform.pathSeparator).last,
            path: path,
            stats: stats,
            createdAt: await _getCreatedTime(path),
            type: detectionResult['type'] as QuickAccessFolderType,
            parentApp: detectionResult['parentApp'] as String?,
          );

          results.add(userFolder);
          logger.d(
            'Detected user folder: ${userFolder.name} at ${userFolder.path}',
          );
        }
      } catch (e) {
        logger.w('Error scanning root directory $root: $e');
      }
    }

    logger.i(
      'User folder detection completed: ${results.length} folders found',
    );
    return results;
  }

  /// 增量检测新文件夹（只检测自上次扫描后新创建的）
  Future<List<UserFolder>> detectNewFolders() async {
    logger.i('Starting incremental new folder detection');

    final lastDetectionTime = await _getLastDetectionTime();
    final allFolders = await detectUserFolders();

    if (lastDetectionTime == null) {
      logger.d('No previous detection time, returning all folders');
      await _saveLastDetectionTime();
      await _saveDetectedFolders(allFolders);
      return allFolders;
    }

    // 过滤出创建时间晚于上次检测时间的文件夹
    final newFolders = allFolders
        .where((folder) => folder.createdAt.isAfter(lastDetectionTime))
        .toList();

    if (newFolders.isNotEmpty) {
      await _saveLastDetectionTime();
      await _saveDetectedFolders(allFolders);
      logger.i('Found ${newFolders.length} new folders');
    } else {
      logger.i('No new folders found');
    }

    return newFolders;
  }

  /// 检测指定路径的文件夹类型
  Map<String, dynamic> _detectFolderType(String path) {
    // 检查是否是应用子目录
    for (final appConfig in AppDirConfigs.allApps) {
      if (path.startsWith(appConfig.path) && path != appConfig.path) {
        return {
          'type': QuickAccessFolderType.appSubfolder,
          'parentApp': appConfig.name,
        };
      }

      // 检查备选路径
      for (final altPath in appConfig.alternativePaths) {
        if (path.startsWith(altPath) && path != altPath) {
          return {
            'type': QuickAccessFolderType.appSubfolder,
            'parentApp': appConfig.name,
          };
        }
      }
    }

    // 否则就是用户自建目录
    return {'type': QuickAccessFolderType.userCustom, 'parentApp': null};
  }

  /// 判断是否应该排除该路径
  bool _shouldExclude(String path) {
    // 1. 检查是否在排除列表
    for (final excluded in _excludedPaths) {
      if (path.startsWith(excluded)) {
        return true;
      }
    }

    // 2. 检查是否是已知的系统目录
    final systemDirs = [
      'DCIM',
      'Pictures',
      'Documents',
      'Download',
      'Downloads',
      'Music',
      'Movies',
      'Podcasts',
      'Ringtones',
      'Alarms',
      'Notifications',
      'Android',
      'data',
    ];

    final name = path.split(Platform.pathSeparator).last;
    if (systemDirs.contains(name)) {
      return true;
    }

    return false;
  }

  /// 验证是否是有效的用户文件夹
  bool _isValidUserFolder(String path, FolderStats stats) {
    final name = path.split(Platform.pathSeparator).last;

    // 1. 不是隐藏文件夹
    if (name.startsWith('.')) {
      return false;
    }

    // 2. 有足够内容（至少5个文件 或 至少1MB）
    if (stats.totalFiles < 5 && stats.totalSizeMB < 1.0) {
      return false;
    }

    // 3. 不是临时/缓存目录
    if (_analyzer.isTempOrCacheFolder(path)) {
      return false;
    }

    // 4. 不是特殊系统目录
    final lowerName = name.toLowerCase();
    final excludeKeywords = [
      'lost.dir',
      'lost+found',
      'system',
      'data',
      'obb',
      'media',
    ];

    if (excludeKeywords.any((keyword) => lowerName.contains(keyword))) {
      return false;
    }

    return true;
  }

  /// 获取目录创建时间
  Future<DateTime> _getCreatedTime(String path) async {
    try {
      final dir = Directory(path);
      final stat = await dir.stat();
      return stat.modified; // Android上通常只有修改时间
    } catch (e) {
      logger.w('Failed to get created time for $path: $e');
      return DateTime.now();
    }
  }

  /// 扫描特定目录下的用户文件夹
  Future<List<UserFolder>> scanSpecificRoot(String rootPath) async {
    logger.i('Scanning specific root: $rootPath');
    final results = <UserFolder>[];

    final dir = Directory(rootPath);
    if (!dir.existsSync()) {
      logger.w('Root path does not exist: $rootPath');
      return results;
    }

    try {
      final entities = dir.listSync(followLinks: false);

      for (final entity in entities) {
        if (entity is! Directory) continue;

        final path = entity.path;
        if (_shouldExclude(path)) continue;

        final stats = await _analyzer.analyzeFolderStats(
          path,
          maxDepth: 1,
          includeHidden: false,
        );

        if (!_isValidUserFolder(path, stats)) continue;

        final detectionResult = _detectFolderType(path);

        results.add(
          UserFolder(
            name: path.split(Platform.pathSeparator).last,
            path: path,
            stats: stats,
            createdAt: await _getCreatedTime(path),
            type: detectionResult['type'] as QuickAccessFolderType,
            parentApp: detectionResult['parentApp'] as String?,
          ),
        );
      }
    } catch (e) {
      logger.e('Error scanning specific root $rootPath: $e');
    }

    return results;
  }

  /// 验证文件夹路径是否仍然有效
  Future<bool> validateUserFolder(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return false;
    }

    return await _analyzer.hasEnoughContent(path, minFiles: 5, minSizeMB: 1.0);
  }

  /// 批量验证文件夹
  Future<Map<String, bool>> validateUserFolders(List<String> paths) async {
    final results = <String, bool>{};

    for (final path in paths) {
      results[path] = await validateUserFolder(path);
    }

    return results;
  }

  /// 查找特定应用下的用户子目录
  Future<List<UserFolder>> findAppSubfolders(String appPath) async {
    logger.i('Finding subfolders for app: $appPath');
    final results = <UserFolder>[];

    final appDir = Directory(appPath);
    if (!appDir.existsSync()) {
      logger.w('App directory does not exist: $appPath');
      return results;
    }

    // 查找应用配置
    final appConfig = AppDirConfigs.allApps.firstWhere(
      (config) =>
          config.path == appPath || config.alternativePaths.contains(appPath),
      orElse: () => AppDirConfig(name: 'Unknown', path: appPath, priority: 3),
    );

    try {
      // 递归扫描应用目录（最多2级）
      await _scanAppDirectory(
        appDir,
        appConfig.name,
        currentDepth: 0,
        maxDepth: 2,
        results: results,
      );
    } catch (e) {
      logger.e('Error finding app subfolders for $appPath: $e');
    }

    logger.i('Found ${results.length} subfolders for ${appConfig.name}');
    return results;
  }

  /// 递归扫描应用目录
  Future<void> _scanAppDirectory(
    Directory dir,
    String appName, {
    required int currentDepth,
    required int maxDepth,
    required List<UserFolder> results,
  }) async {
    if (currentDepth >= maxDepth) return;

    try {
      final entities = dir.listSync(followLinks: false);

      for (final entity in entities) {
        if (entity is! Directory) continue;

        final path = entity.path;
        final name = path.split(Platform.pathSeparator).last;

        // 跳过隐藏和临时目录
        if (name.startsWith('.') || _analyzer.isTempOrCacheFolder(path)) {
          continue;
        }

        final stats = await _analyzer.analyzeFolderStats(
          path,
          maxDepth: 1,
          includeHidden: false,
        );

        // 只添加有足够内容的目录
        if (stats.totalFiles >= 10 || stats.totalSizeMB >= 5.0) {
          results.add(
            UserFolder(
              name: name,
              path: path,
              stats: stats,
              createdAt: await _getCreatedTime(path),
              type: QuickAccessFolderType.appSubfolder,
              parentApp: appName,
            ),
          );
        }

        // 继续递归
        await _scanAppDirectory(
          entity,
          appName,
          currentDepth: currentDepth + 1,
          maxDepth: maxDepth,
          results: results,
        );
      }
    } catch (e) {
      logger.w('Error scanning app directory ${dir.path}: $e');
    }
  }

  // ==================== 私有辅助方法 ====================

  /// 保存最后检测时间
  Future<void> _saveLastDetectionTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastDetectionTimeKey,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      logger.e('Failed to save last detection time: $e');
    }
  }

  /// 获取最后检测时间
  Future<DateTime?> _getLastDetectionTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timeStr = prefs.getString(_lastDetectionTimeKey);
      return timeStr != null ? DateTime.parse(timeStr) : null;
    } catch (e) {
      logger.e('Failed to get last detection time: $e');
      return null;
    }
  }

  /// 保存已检测的文件夹
  Future<void> _saveDetectedFolders(List<UserFolder> folders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = folders.map((folder) => folder.path).toList();
      await prefs.setStringList(_detectedFoldersKey, paths);
    } catch (e) {
      logger.e('Failed to save detected folders: $e');
    }
  }

  /// 获取已检测的文件夹路径
  Future<List<String>> _getDetectedFolderPaths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_detectedFoldersKey) ?? [];
    } catch (e) {
      logger.e('Failed to get detected folder paths: $e');
      return [];
    }
  }

  /// 清除检测缓存
  Future<void> clearDetectionCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastDetectionTimeKey);
      await prefs.remove(_detectedFoldersKey);
      logger.i('Detection cache cleared');
    } catch (e) {
      logger.e('Failed to clear detection cache: $e');
    }
  }

  /// 获取检测统计信息
  Future<Map<String, dynamic>> getDetectionStatistics() async {
    final lastDetectionTime = await _getLastDetectionTime();
    final detectedPaths = await _getDetectedFolderPaths();

    return {
      'lastDetectionTime': lastDetectionTime?.toIso8601String(),
      'detectedFoldersCount': detectedPaths.length,
      'detectedPaths': detectedPaths,
    };
  }
}
