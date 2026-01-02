import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'first_install_service.dart';
import 'cache_service.dart';

/// 应用初始化服务
/// 
/// 执行三阶段初始化过程：
/// - P0：基础初始化（快速访问菜单、收藏夹）- 2秒
/// - P1：分类初始化（分类文件统计缓存）- 2秒
/// - P2：深度扫描（完整文件系统扫描）- 30秒
typedef InitializationProgressCallback = void Function(double progress);

class AppInitializationService {
  final FilePresenter filePresenter;
  final QuickAccessPresenter quickAccessPresenter;
  final FirstInstallService firstInstallService;
  final CacheService cacheService;

  InitializationProgressCallback? onProgress;

  AppInitializationService({
    required this.filePresenter,
    required this.quickAccessPresenter,
    required this.firstInstallService,
    required this.cacheService,
    this.onProgress,
  });

  /// 从头开始完整初始化
  /// 
  /// 按三个阶段顺序执行：
  /// 1. 加载基础资源（快速访问、收藏等） - 2秒
  /// 2. 加载分类统计缓存 - 2秒
  /// 3. 执行完整文件系统扫描 - 30秒
  /// 总耗时约37秒，过程中调用 onProgress 更新UI进度
  /// 
  /// 注意：方法名按功能而非优先级命名，允许未来灵活调整顺序和优先级
  Future<void> initializeFromScratch() async {
    logger.i('[AppInitService] Starting full initialization...');

    try {
      // 阶段1: 加载基础资源（2秒）
      logger.i('[AppInitService] Loading basic resources...');
      _reportProgress(0.05);
      await _loadBasicResources();
      _reportProgress(0.15);

      // 阶段2: 加载分类统计缓存（2秒）
      logger.i('[AppInitService] Loading category statistics cache...');
      _reportProgress(0.20);
      await _loadCategoryStatisticsCache();
      _reportProgress(0.30);

      // 阶段3: 执行完整文件系统扫描（30秒）
      logger.i('[AppInitService] Executing full file system scan...');
      _reportProgress(0.35);
      await _executeFullFileSystemScan();
      _reportProgress(0.95);

      // 更新缓存时间戳
      await cacheService.updateLastScanTime();

      // 标记为已初始化（重要：必须在P2完成后）
      await firstInstallService.markInitialized();

      _reportProgress(1.0);
      logger.i('[AppInitService] Full initialization completed');
    } catch (e) {
      logger.e('[AppInitService] Error during initialization: $e');
      // 即使失败，仍然标记为已初始化（P2已完成大部分工作）
      try {
        await firstInstallService.markInitialized();
      } catch (e2) {
        logger.e('[AppInitService] Failed to mark initialized: $e2');
      }
      rethrow;
    }
  }

  /// 加载基础资源
  /// 
  /// 第一阶段初始化，加载快速访问菜单、收藏夹、主题等基本数据
  /// 耗时约2秒
  /// 
  /// 这些资源加载速度快，用户期望首先看到这些基础功能可用
  /// 注意：主题初始化在 FileBrowserPage._initializeAppWithPermission() 中已完成
  Future<void> _loadBasicResources() async {
    try {
      // 加载快速访问文件夹
      await quickAccessPresenter.loadQuickAccessFolders();
      logger.i('[AppInitService] P0: Quick access folders loaded');

      // 加载收藏文件
      await filePresenter.initializeFavoriteFiles();
      logger.i('[AppInitService] P0: Favorite files loaded');

      logger.i('[AppInitService] P0: Basic resources loading completed');
    } catch (e) {
      logger.e('[AppInitService] Basic resources loading failed: $e');
      // 基础资源加载失败时使用默认值继续
      logger.w('[AppInitService] Using default values for basic resources');
    }
  }

  /// 加载分类统计缓存
  /// 
  /// 第二阶段初始化，扫描并统计各分类文件数，缓存到 SharedPreferences
  /// 耗时约2秒
  /// 
  /// 这一阶段为分类页面提供文件统计数据，加快分类页面打开速度
  /// 注意：这是一个快速扫描，仅统计数据不发现新文件夹
  /// 第三阶段会做完整的文件系统扫描
  Future<void> _loadCategoryStatisticsCache() async {
    try {
      final Map<FileCategory, int> counts = {};

      // 初始化所有分类计数
      for (final category in FileCategory.values) {
        counts[category] = 0;
      }

      // 要扫描的分类类型
      final categoriesToScan = [
        CategoryType.images,
        CategoryType.video,
        CategoryType.music,
        CategoryType.documents,
        CategoryType.downloads,
      ];

      int totalFiles = 0;

      for (int i = 0; i < categoriesToScan.length; i++) {
        final categoryType = categoriesToScan[i];

        try {
          // 更新进度（P1 阶段的进度范围是 0.20-0.30）
          final categoryProgress = 0.20 + (i / categoriesToScan.length) * 0.1;
          _reportProgress(categoryProgress);

          final files = await filePresenter.scanFilesByCategory(categoryType);
          final count = files.length;

          // 映射到 FileCategory
          final fileCategory = _mapCategoryType(categoryType);
          counts[fileCategory] = count;
          totalFiles += count;

          logger.i(
              '[AppInitService] Category statistics: ${categoryType.name} = $count files');
        } catch (e) {
          logger.e('[AppInitService] Error scanning $categoryType: $e');
          // 某个分类扫描失败，使用该分类的零值继续
        }
      }

      // 缓存分类统计数据
      counts[FileCategory.all] = totalFiles;
      await _cacheCategoryCounts(counts);

      logger.i(
          '[AppInitService] Category statistics cache: Total files = $totalFiles, cached successfully');
    } catch (e) {
      logger.e('[AppInitService] Category statistics loading failed: $e');
      // 分类统计加载失败时使用零值继续
      logger.w('[AppInitService] Using zero values for category statistics');
    }
  }

  /// 执行完整文件系统扫描
  /// 
  /// 第三阶段初始化，执行完整的文件系统扫描，发现新文件夹和文件
  /// 耗时约30秒
  /// 
  /// 这是最耗时的阶段，但前两个阶段已完成，用户已可使用基本功能
  /// 此阶段完成后标记初始化为完成
  Future<void> _executeFullFileSystemScan() async {
    try {
      logger.i('[AppInitService] Starting full file system scan...');

      // 使用 QuickAccessPresenter 的完整扫描方法
      // 这个方法会：
      // 1. 检测快速访问文件夹
      // 2. 扫描分类文件（使用我们提供的 scanCategoryFiles 回调）
      // 3. 缓存分类统计数据
      
      final scanResult = await quickAccessPresenter.performFirstTimeComprehensiveScan(
        onProgress: (progress) {
          // 将 quickAccessPresenter 的进度 (0.35-1.0) 映射到我们的进度范围
          final mappedProgress = 0.35 + (progress * 0.6);
          _reportProgress(mappedProgress);
        },
        scanCategoryFiles: _performCompleteCategoryScan,
      );

      logger.i(
          '[AppInitService] File system scan completed: ${scanResult.quickAccessFoldersFound} folders found, ${scanResult.totalFilesScanned} files scanned');
    } catch (e) {
      logger.e('[AppInitService] File system scan failed: $e');
      // 即使扫描失败也标记为已初始化（前两个阶段已完成）
      logger.w('[AppInitService] Scan failed but marking as initialized (previous stages complete)');
    }
  }

  /// 执行完整的分类扫描
  /// 
  /// 这个方法被 performFirstTimeComprehensiveScan 调用
  /// 用于扫描并统计所有分类文件数，然后缓存结果
  Future<Map<FileCategory, int>> _performCompleteCategoryScan() async {
    try {
      logger.i('[AppInitService] Performing complete category scan...');

      final Map<FileCategory, int> counts = {};

      // 初始化所有分类计数
      for (final category in FileCategory.values) {
        counts[category] = 0;
      }

      // 要扫描的分类类型（与第二阶段相同）
      final categoriesToScan = [
        CategoryType.images,
        CategoryType.video,
        CategoryType.music,
        CategoryType.documents,
        CategoryType.downloads,
      ];

      int totalFiles = 0;

      for (int i = 0; i < categoriesToScan.length; i++) {
        final categoryType = categoriesToScan[i];

        try {
          // 注意：这里不更新进度，因为整体进度由 performFirstTimeComprehensiveScan 管理
          
          final files = await filePresenter.scanFilesByCategory(categoryType);
          final count = files.length;

          // 映射到 FileCategory
          final fileCategory = _mapCategoryType(categoryType);
          counts[fileCategory] = count;
          totalFiles += count;

          logger.i(
              '[AppInitService] Category scan: ${categoryType.name} = $count files');
        } catch (e) {
          logger.e('[AppInitService] Error scanning $categoryType: $e');
          // 某个分类扫描失败，使用该分类的零值继续
        }
      }

      // 设置总文件数
      counts[FileCategory.all] = totalFiles;

      logger.i(
          '[AppInitService] Complete category scan finished: $totalFiles total files');

      return counts;
    } catch (e) {
      logger.e('[AppInitService] Complete category scan failed: $e');
      // 返回空的统计（所有分类都是0）
      final emptyCounts = <FileCategory, int>{};
      for (final category in FileCategory.values) {
        emptyCounts[category] = 0;
      }
      return emptyCounts;
    }
  }

  /// 映射 CategoryType 到 FileCategory
  FileCategory _mapCategoryType(CategoryType categoryType) {
    switch (categoryType) {
      case CategoryType.images:
        return FileCategory.image;
      case CategoryType.video:
        return FileCategory.video;
      case CategoryType.music:
        return FileCategory.audio;
      case CategoryType.documents:
        return FileCategory.document;
      case CategoryType.downloads:
        return FileCategory.other;
      case CategoryType.apk:
        return FileCategory.other;
      case CategoryType.archive:
        return FileCategory.other;
    }
  }

  /// 缓存分类统计数据
  Future<void> _cacheCategoryCounts(Map<FileCategory, int> counts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'counts': counts.map((key, value) => MapEntry(key.name, value)),
      };
      await prefs.setString('category_counts_cache', json.encode(cacheData));
      logger.i('[AppInitService] Cached category counts');
    } catch (e) {
      logger.e('[AppInitService] Error caching category counts: $e');
    }
  }

  /// 报告进度
  void _reportProgress(double progress) {
    onProgress?.call(progress);
  }
}
