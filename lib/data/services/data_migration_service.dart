import 'dart:io';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/favorite_item.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/data/models/folder_stats.dart';
import 'package:easyfile/data/sources/favorites_local_source.dart';
import 'package:easyfile/data/sources/quick_access_local_source.dart';
import 'package:easyfile/data/services/folder_analyzer.dart';
import 'package:easyfile/data/services/alias_recommendation_service.dart';

/// 数据迁移服务
///
/// 负责将旧版 Favorites 数据迁移到新版 QuickAccess 系统
class DataMigrationService {
  final FavoritesLocalSource _favoritesSource;
  final QuickAccessLocalSource _quickAccessSource;
  final FolderAnalyzer _folderAnalyzer;

  DataMigrationService({
    required FavoritesLocalSource favoritesSource,
    required QuickAccessLocalSource quickAccessSource,
    required FolderAnalyzer folderAnalyzer,
  }) : _favoritesSource = favoritesSource,
       _quickAccessSource = quickAccessSource,
       _folderAnalyzer = folderAnalyzer;

  /// 检查是否需要迁移
  Future<bool> needsMigration() async {
    try {
      // 检查是否已经迁移过
      final quickAccessFolders = await _quickAccessSource.getAllFolders();
      if (quickAccessFolders.isNotEmpty) {
        logger.i('QuickAccess already has data, migration not needed');
        return false;
      }

      // 检查是否有旧数据
      final favorites = await _favoritesSource.getFavorites();
      if (favorites.isEmpty) {
        logger.i('No favorite data to migrate');
        return false;
      }

      logger.i('Found ${favorites.length} favorites to migrate');
      return true;
    } catch (e) {
      logger.e('Error checking migration status: $e');
      return false;
    }
  }

  /// 执行数据迁移
  Future<MigrationResult> migrate() async {
    logger.i('Starting data migration from Favorites to QuickAccess');
    final result = MigrationResult();

    try {
      // 获取所有收藏夹
      final favorites = await _favoritesSource.getFavorites();
      if (favorites.isEmpty) {
        logger.i('No favorites to migrate');
        return result;
      }

      result.totalCount = favorites.length;
      logger.i('Found ${favorites.length} favorites to migrate');

      // 转换每个收藏项
      for (final favorite in favorites) {
        try {
          final quickAccessFolder = await _convertToQuickAccessFolder(favorite);

          if (quickAccessFolder != null) {
            final success = await _quickAccessSource.addFolder(
              quickAccessFolder,
            );
            if (success) {
              result.successCount++;
              logger.d('Migrated: ${favorite.path}');
            } else {
              result.failedCount++;
              result.errors.add('Failed to add: ${favorite.path}');
              logger.w('Failed to add folder: ${favorite.path}');
            }
          } else {
            result.skippedCount++;
            logger.d('Skipped (folder not exists): ${favorite.path}');
          }
        } catch (e) {
          result.failedCount++;
          result.errors.add('Error migrating ${favorite.path}: $e');
          logger.e('Error migrating ${favorite.path}: $e');
        }
      }

      logger.i(
        'Migration completed: ${result.successCount} success, '
        '${result.failedCount} failed, ${result.skippedCount} skipped',
      );

      return result;
    } catch (e) {
      logger.e('Error during migration: $e');
      result.errors.add('Migration error: $e');
      return result;
    }
  }

  /// 将 FavoriteItem 转换为 QuickAccessFolder
  Future<QuickAccessFolder?> _convertToQuickAccessFolder(
    FavoriteItem favorite,
  ) async {
    try {
      // 检查文件夹是否存在
      final dir = Directory(favorite.path);
      if (!await dir.exists()) {
        logger.w('Folder does not exist: ${favorite.path}');
        return null;
      }

      // 分析文件夹统计信息
      FolderStats? stats;
      try {
        stats = await _folderAnalyzer.analyzeFolderStats(favorite.path);
      } catch (e) {
        logger.w('Failed to analyze folder ${favorite.path}: $e');
        // 使用空统计信息
        stats = FolderStats.empty();
      }

      // 确定文件夹类型
      final folderType = _determineFolderType(favorite.path);

      // 生成推荐别名
      final aliasService = AliasRecommendationService();
      final recommendedAlias = aliasService.recommendAlias(
        path: favorite.path,
        originalName: favorite.name,
        stats: stats,
        type: folderType,
      );

      // 创建 QuickAccessFolder
      return QuickAccessFolder(
        id: '${DateTime.now().millisecondsSinceEpoch}_${favorite.name}',
        path: favorite.path,
        originalName: favorite.name,
        recommendedAlias: recommendedAlias.isNotEmpty ? recommendedAlias : null,
        userAlias: null, // FavoriteItem没有alias字段
        type: folderType,
        createdAt: DateTime.now(),
        stats: stats,
        pinned: false, // 默认不置顶，用户可以手动设置
      );
    } catch (e) {
      logger.e('Error converting favorite ${favorite.path}: $e');
      return null;
    }
  }

  /// 根据路径判断文件夹类型
  QuickAccessFolderType _determineFolderType(String path) {
    final lowerPath = path.toLowerCase();

    // 系统文件夹判断
    if (_isSystemFolder(lowerPath)) {
      return QuickAccessFolderType.system;
    }

    // 应用文件夹判断（常见应用目录特征）
    if (_isAppFolder(lowerPath)) {
      return QuickAccessFolderType.appRoot;
    }

    // 默认为用户自定义
    return QuickAccessFolderType.userCustom;
  }

  bool _isSystemFolder(String lowerPath) {
    final systemPaths = [
      '/dcim',
      '/pictures',
      '/camera',
      '/download',
      '/documents',
      '/music',
      '/movies',
      '/alarms',
      '/notifications',
      '/ringtones',
      '/podcasts',
      '/audiobooks',
      '/screenshots',
    ];

    return systemPaths.any((pattern) => lowerPath.contains(pattern));
  }

  bool _isAppFolder(String lowerPath) {
    // 常见应用目录特征
    final appPatterns = [
      '/android/data/',
      '/android/obb/',
      '/tencent/',
      '/baidu/',
      '/alibaba/',
      '.com.',
      'wechat',
      'qq',
      'douyin',
      'taobao',
    ];

    return appPatterns.any((pattern) => lowerPath.contains(pattern));
  }

  /// 清理旧数据（可选，谨慎使用）
  Future<bool> cleanupOldData() async {
    try {
      logger.w('Cleaning up old favorites data');
      await _favoritesSource.clearFavorites();
      logger.i('Old favorites data cleared');
      return true;
    } catch (e) {
      logger.e('Error cleaning up old data: $e');
      return false;
    }
  }
}

/// 迁移结果
class MigrationResult {
  int totalCount = 0;
  int successCount = 0;
  int failedCount = 0;
  int skippedCount = 0;
  List<String> errors = [];

  bool get isSuccess => failedCount == 0 && totalCount > 0;
  bool get hasData => totalCount > 0;

  String get summary {
    return 'Total: $totalCount, Success: $successCount, '
        'Failed: $failedCount, Skipped: $skippedCount';
  }

  @override
  String toString() => summary;
}
