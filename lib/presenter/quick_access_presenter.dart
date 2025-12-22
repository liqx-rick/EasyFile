import 'dart:io';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/data/models/comprehensive_scan_result.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/sources/quick_access_local_source.dart';
import 'package:easyfile/core/constants/system_folders_config.dart';

import 'package:easyfile/data/services/alias_recommendation_service.dart';
import 'package:easyfile/data/services/quick_access_folder_detector.dart';
import 'package:easyfile/core/services/category_file_cache_service.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';

/// 快速访问业务逻辑处理层
class QuickAccessPresenter {
  final QuickAccessLocalSource _localSource;
  final QuickAccessViewModel _viewModel;
  final AliasRecommendationService _aliasService;
  final QuickAccessFolderDetector _quickAccessDetector;

  QuickAccessPresenter({
    required QuickAccessLocalSource localSource,
    required QuickAccessViewModel viewModel,
    required AliasRecommendationService aliasService,
    QuickAccessFolderDetector? quickAccessDetector,
  })  : _localSource = localSource,
        _viewModel = viewModel,
        _aliasService = aliasService,
        _quickAccessDetector = quickAccessDetector ?? QuickAccessFolderDetector();

  // ==================== Getters ====================

  /// 暴露 _localSource 供外部使用（用于调试日志等）
  QuickAccessLocalSource get localSource => _localSource;

  // ==================== 核心CRUD操作 ====================

  /// 加载所有快速访问文件夹
  Future<void> loadQuickAccessFolders() async {
    logger.i('QuickAccessPresenter.loadQuickAccessFolders called');
    _viewModel.setLoading(true);

    try {
      final folders = await _localSource.getAllFolders();
      _viewModel.setFolders(folders);
      logger.i('Loaded ${folders.length} quick access folders');
    } catch (e, stackTrace) {
      logger.e('Error loading quick access folders: $e\n$stackTrace');
      _viewModel.setError('加载快速访问失败');
    } finally {
      _viewModel.setLoading(false);
    }
  }

  /// 添加文件夹
  Future<bool> addFolder(QuickAccessFolder folder) async {
    logger.i('QuickAccessPresenter.addFolder called: ${folder.path}');
    try {
      final result = await _localSource.addFolderWithResult(folder);
      if (result == AddFolderResult.added ||
          result == AddFolderResult.unhidden) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error adding folder: $e');
      return false;
    }
  }

  /// 删除文件夹
  Future<bool> removeFolder(String id) async {
    logger.i('QuickAccessPresenter.removeFolder called: $id');
    try {
      final success = await _localSource.removeFolder(id);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error removing folder: $e');
      return false;
    }
  }

  /// 更新文件夹
  Future<bool> updateFolder(QuickAccessFolder folder) async {
    logger.i('QuickAccessPresenter.updateFolder called: ${folder.path}');
    try {
      final success = await _localSource.updateFolder(folder);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error updating folder: $e');
      return false;
    }
  }

  /// 切换置顶状态
  Future<bool> togglePin(String path) async {
    logger.i('QuickAccessPresenter.togglePin called: $path');
    try {
      final success = await _localSource.togglePin(path);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error toggling pin: $e');
      return false;
    }
  }

  /// 设置用户别名
  Future<bool> setUserAlias(String id, String? alias) async {
    logger.i('QuickAccessPresenter.setUserAlias called: $id -> $alias');
    try {
      final success = await _localSource.setAlias(id, alias);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error setting user alias: $e');
      return false;
    }
  }

  /// 更新访问信息
  Future<void> updateAccessInfo(String path) async {
    logger.d('QuickAccessPresenter.updateAccessInfo called: $path');
    try {
      await _localSource.updateAccessInfo(path);
      // 不需要刷新整个列表，只更新访问时间
    } catch (e) {
      logger.w('Error updating access info: $e');
    }
  }

  // ==================== 扫描功能 ====================

  /// 执行首次综合扫描（扫描快速访问目录 + 分类文件）
  ///
  /// 该方法会执行以下操作：
  /// 1. 扫描系统目录 (0-20%)
  /// 2. 扫描分类文件 (20-95%)
  /// 3. 保存缓存 (95-100%)
  ///
  /// [scanCategoryFiles] 是一个可选的回调函数，用于扫描分类文件并返回统计结果
  /// [onProgress] 进度回调，参数为进度值 (0.0 - 1.0)，用于实时更新 UI
  Future<ComprehensiveScanResult> performFirstTimeComprehensiveScan({
    Future<Map<FileCategory, int>> Function()? scanCategoryFiles,
    void Function(double progress)? onProgress,
  }) async {
    logger.i('QuickAccessPresenter.performFirstTimeComprehensiveScan called');
    _viewModel.setScanning(true);

    // 初始进度
    onProgress?.call(0.0);

    try {
      // 1. 使用 QuickAccessFolderDetector 扫描快速访问文件夹 (0-20%)
      onProgress?.call(0.05);
      final detectedFolders = await _detectQuickAccessFolders();
      logger.i('Detector found ${detectedFolders.length} quick access folders');
      onProgress?.call(0.20);

      // 合并所有扫描结果
      final allScannedFolders = [
        ...detectedFolders,
      ];

      logger.i('Deep scan total: ${allScannedFolders.length} folders');

      int newlyAdded = 0;
      int unhidden = 0;
      int alreadyExists = 0;
      int systemCount = 0;
      int otherCount = 0;

      // 添加到数据库并统计
      for (final folder in allScannedFolders) {
        // 统计类型
        switch (folder.type) {
          case QuickAccessFolderType.system:
            systemCount++;
            break;
          case QuickAccessFolderType.other:
            otherCount++;
            break;
        }

        // 添加到数据库
        final result = await _localSource.addFolderWithResult(folder);
        switch (result) {
          case AddFolderResult.added:
            newlyAdded++;
            break;
          case AddFolderResult.unhidden:
            unhidden++;
            break;
          case AddFolderResult.exists:
            alreadyExists++;
            break;
          case AddFolderResult.skippedHidden:
          case AddFolderResult.error:
            break;
        }
      }

      // 🆕 首次扫描特殊处理：自动将系统一级目录加入快速访问并设置别名
      await _autoAddSystemFoldersToQuickAccess(allScannedFolders);

      // 4. 扫描分类文件（如果提供了扫描函数）(30-95%)
      logger.i('Starting category file scan...');
      onProgress?.call(0.30);
      Map<FileCategory, int> categoryFileCounts;

      if (scanCategoryFiles != null) {
        // 使用外部提供的扫描函数（完整扫描）
        logger.i('Using provided category scan function');
        categoryFileCounts = await scanCategoryFiles();
      } else {
        // 回退到快速扫描（只扫描系统目录第一层）
        logger.i('Using fallback quick scan');
        final systemFolders = detectedFolders
            .where((f) => f.type == QuickAccessFolderType.system)
            .toList();
        categoryFileCounts = await _scanCategoryFiles(systemFolders);
      }
      onProgress?.call(0.95);

      // 使用 'all' 分类的计数作为总文件数（避免重复计数）
      final totalFilesScanned = categoryFileCounts[FileCategory.all] ?? 0;

      logger.i(
          'Category scan completed: $totalFilesScanned files in ${categoryFileCounts.length} categories');

      // 5. 保存分类文件缓存 (95-100%)
      final cacheService = CategoryFileCacheService();
      await cacheService.saveCategoryCounts(categoryFileCounts);

      await loadQuickAccessFolders();
      onProgress?.call(1.0);

      return ComprehensiveScanResult(
        quickAccessFoldersFound: allScannedFolders.length,
        systemFoldersCount: systemCount,
        otherFoldersCount: otherCount,
        newlyAdded: newlyAdded,
        alreadyExists: alreadyExists,
        unhidden: unhidden,
        categoryFileCounts: categoryFileCounts,
        totalFilesScanned: totalFilesScanned,
        success: true,
      );
    } catch (e, stackTrace) {
      logger.e('Error performing comprehensive scan: $e\n$stackTrace');
      return ComprehensiveScanResult.error(e.toString());
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 扫描分类文件（统计各分类文件数量）
  Future<Map<FileCategory, int>> _scanCategoryFiles(
    List<QuickAccessFolder> systemFolders,
  ) async {
    logger.i(
        '_scanCategoryFiles called with ${systemFolders.length} system folders');
    final Map<FileCategory, int> counts = {};

    // 初始化所有分类计数
    for (final category in FileCategory.values) {
      counts[category] = 0;
    }

    // 优先扫描的系统目录
    final priorityPaths = <String>[];
    for (final folder in systemFolders) {
      final path = folder.path.toLowerCase();
      logger.d('Checking system folder: $path');
      // 只扫描常用的系统目录
      if (path.contains('dcim') ||
          path.contains('picture') ||
          path.contains('photo') ||
          path.contains('video') ||
          path.contains('movie') ||
          path.contains('music') ||
          path.contains('document') ||
          path.contains('download')) {
        priorityPaths.add(folder.path);
        logger.d('Added to priority: ${folder.path}');
      }
    }

    logger.i(
        'Scanning ${priorityPaths.length} priority directories for category files');

    if (priorityPaths.isEmpty) {
      logger.w('No priority directories found, returning empty counts');
      return counts;
    }

    // 扫描每个优先目录
    int scannedDirs = 0;
    int totalFilesFound = 0;
    for (final dirPath in priorityPaths) {
      try {
        logger.d('Scanning directory: $dirPath');
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          logger.w('Directory does not exist: $dirPath');
          continue;
        }

        // 只扫描一级文件，不递归（提高速度）
        final entities = await dir.list(followLinks: false).toList();
        logger.d('Found ${entities.length} entities in $dirPath');

        int filesInDir = 0;
        for (final entity in entities) {
          if (entity is File) {
            filesInDir++;
            final extension = entity.path.split('.').last.toLowerCase();
            final category = FileCategoryExtension.fromExtension(extension);
            counts[category] = (counts[category] ?? 0) + 1;
            counts[FileCategory.all] = (counts[FileCategory.all] ?? 0) + 1;
          }
        }

        totalFilesFound += filesInDir;
        logger.i('Scanned $dirPath: found $filesInDir files');

        scannedDirs++;

        // 限制扫描时间，避免首次启动太慢
        if (scannedDirs >= 10) {
          logger.i('Reached scan limit (10 directories), stopping early');
          break;
        }
      } catch (e) {
        logger.e('Error scanning directory $dirPath: $e');
        continue;
      }
    }

    logger.i(
        'Category scan completed: scanned $scannedDirs directories, found $totalFilesFound files');
    logger.i(
        'Category counts: ${counts.entries.where((e) => e.value > 0).map((e) => '${e.key.name}:${e.value}').join(', ')}');

    return counts;
  }

  /// 执行首次扫描（直接使用深度扫描获取所有目录）
  /// 此方法保留用于向后兼容
  Future<ScanResult> performFirstTimeScan() async {
    logger.i(
        'QuickAccessPresenter.performFirstTimeScan called - using deep scan');
    // 首次扫描直接使用深度扫描，一次性获取所有目录
    return await performDeepScan();
  }

  /// 执行增量扫描（带通知）
  /// 在新架构中已移除应用扫描功能
  Future<ScanResult> performIncrementalScanWithNotification() async {
    logger.i(
      'QuickAccessPresenter.performIncrementalScanWithNotification called',
    );
    _viewModel.setScanning(true);

    try {
      // 新架构不再提供增量扫描
      logger.w('Incremental scan not supported in new architecture');

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: 0,
        newlyAdded: 0, // 不自动添加，等待用户确认
        alreadyExists: 0,
      );
    } catch (e, stackTrace) {
      logger.e('Error performing incremental scan: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 执行增量扫描（原方法，直接添加）
  Future<ScanResult> performIncrementalScan() async {
    logger.i('QuickAccessPresenter.performIncrementalScan called');
    _viewModel.setScanning(true);

    try {
      // No incremental scan from app scanner in new architecture
      final scannedFolders = <QuickAccessFolder>[];
      final counts = _countFolderTypes(scannedFolders);

      int newlyAdded = 0;
      int alreadyExists = 0;
      int skippedHidden = 0;

      for (final folder in scannedFolders) {
        final result = await _localSource.addFolderWithResult(
          folder,
          unhideIfHidden: false,
        );
        switch (result) {
          case AddFolderResult.added:
            newlyAdded++;
            break;
          case AddFolderResult.exists:
            alreadyExists++;
            break;
          case AddFolderResult.skippedHidden:
            // 跳过隐藏的，不计入有效发现
            skippedHidden++;
            break;
          case AddFolderResult.unhidden:
          case AddFolderResult.error:
            // 这些情况理论上不会发生（unhideIfHidden: false）
            break;
        }
      }

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: scannedFolders.length - skippedHidden,
        newlyAdded: newlyAdded,
        alreadyExists: alreadyExists,
        unhidden: 0, // 增量扫描不恢复隐藏项
        systemCount: counts['system']!,
        otherCount: counts['other']!,
      );
    } catch (e, stackTrace) {
      logger.e('Error performing incremental scan: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 执行用户主动扫描（Tier1+2 + 系统目录，不恢复隐藏项）
  Future<ScanResult> performUserInitiatedScan() async {
    logger.i('QuickAccessPresenter.performUserInitiatedScan called');
    _viewModel.setScanning(true);

    try {
      // 1. 使用 QuickAccessFolderDetector 扫描快速访问文件夹
      final detectedFolders = await _detectQuickAccessFolders();
      logger.i(
        'User-initiated scan found ${detectedFolders.length} quick access folders',
      );

      // 合并扫描结果
      final scannedFolders = [
        ...detectedFolders,
      ];

      final counts = _countFolderTypes(scannedFolders);

      int newlyAdded = 0;
      int alreadyExists = 0;
      int skippedHidden = 0;

      for (final folder in scannedFolders) {
        final result = await _localSource.addFolderWithResult(
          folder,
          unhideIfHidden: false,
        );
        switch (result) {
          case AddFolderResult.added:
            newlyAdded++;
            break;
          case AddFolderResult.exists:
            alreadyExists++;
            break;
          case AddFolderResult.skippedHidden:
            // 跳过隐藏的，不计入有效发现
            skippedHidden++;
            break;
          case AddFolderResult.unhidden:
          case AddFolderResult.error:
            // 这些情况理论上不会发生（unhideIfHidden: false）
            break;
        }
      }

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: scannedFolders.length - skippedHidden,
        newlyAdded: newlyAdded,
        alreadyExists: alreadyExists,
        unhidden: 0, // 常规扫描不恢复隐藏项
        systemCount: counts['system']!,
        otherCount: counts['other']!,
      );
    } catch (e, stackTrace) {
      logger.e('Error performing user-initiated scan: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 执行深度扫描（系统目录 + 用户目录）
  Future<ScanResult> performDeepScan() async {
    logger.i('QuickAccessPresenter.performDeepScan called');
    _viewModel.setScanning(true);

    try {
      // 1. 使用 QuickAccessFolderDetector 扫描快速访问文件夹
      final detectedFolders = await _detectQuickAccessFolders();
      logger.i('Deep scan found ${detectedFolders.length} quick access folders');

      // 合并所有扫描结果
      final allScannedFolders = [
        ...detectedFolders,
      ];

      logger.i('Deep scan total: ${allScannedFolders.length} folders');

      int newlyAdded = 0;
      int unhidden = 0;
      int alreadyExists = 0;

      // 按类型统计
      int systemCount = 0;
      int otherCount = 0;

      for (final folder in allScannedFolders) {
        // 统计类型
        switch (folder.type) {
          case QuickAccessFolderType.system:
            systemCount++;
            break;
          case QuickAccessFolderType.other:
            otherCount++;
            break;
        }

        // 深度扫描会恢复隐藏项（unhideIfHidden默认为true）
        final result = await _localSource.addFolderWithResult(folder);
        switch (result) {
          case AddFolderResult.added:
            newlyAdded++;
            break;
          case AddFolderResult.unhidden:
            unhidden++;
            break;
          case AddFolderResult.exists:
            alreadyExists++;
            break;
          case AddFolderResult.skippedHidden:
          case AddFolderResult.error:
            // 这些情况理论上不会发生（深度扫描使用默认的unhideIfHidden: true）
            break;
        }
      }

      // 2. 执行数据清理
      logger.i('Performing data cleanup after deep scan');
      final cleanupResult = await _performDataCleanup();
      logger.i('Data cleanup completed: $cleanupResult');

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: allScannedFolders.length,
        newlyAdded: newlyAdded,
        alreadyExists: alreadyExists,
        unhidden: unhidden,
        systemCount: systemCount,
        otherCount: otherCount,
        removedNonExistent: cleanupResult.removedNonExistent,
        removedMisclassified: cleanupResult.removedMisclassified,
        removedUnqualified: cleanupResult.removedUnqualified,
      );
    } catch (e, stackTrace) {
      logger.e('Error performing deep scan: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 检测用户自定义文件夹（不恢复隐藏项）
  /// 在新架构中已由 QuickAccessFolderDetector 的第二部分取代
  Future<ScanResult> detectUserFolders() async {
    logger.i('QuickAccessPresenter.detectUserFolders called');
    _viewModel.setScanning(true);

    try {
      // 使用 QuickAccessFolderDetector 的第二部分功能
      final userFolders = await _detectQuickAccessFolders();
      logger.i('Detected ${userFolders.length} user folders');

      final scannedFolders = userFolders;
      final counts = _countFolderTypes(scannedFolders);

      int newlyAdded = 0;
      int alreadyExists = 0;
      int skippedHidden = 0;

      for (final folder in scannedFolders) {
        final result = await _localSource.addFolderWithResult(
          folder,
          unhideIfHidden: false,
        );
        switch (result) {
          case AddFolderResult.added:
            newlyAdded++;
            break;
          case AddFolderResult.exists:
            alreadyExists++;
            break;
          case AddFolderResult.skippedHidden:
            // 跳过隐藏的，不计入有效发现
            skippedHidden++;
            break;
          case AddFolderResult.unhidden:
          case AddFolderResult.error:
            // 这些情况理论上不会发生（unhideIfHidden: false）
            break;
        }
      }

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: scannedFolders.length - skippedHidden,
        newlyAdded: newlyAdded,
        alreadyExists: alreadyExists,
        unhidden: 0, // 用户目录检测不恢复隐藏项
        systemCount: counts['system']!,
        otherCount: counts['other']!,
      );
    } catch (e, stackTrace) {
      logger.e('Error detecting user folders: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 统计文件夹类型
  Map<String, int> _countFolderTypes(List<QuickAccessFolder> folders) {
    int systemCount = 0;
    int otherCount = 0;

    for (final folder in folders) {
      switch (folder.type) {
        case QuickAccessFolderType.system:
          systemCount++;
          break;
        case QuickAccessFolderType.other:
          otherCount++;
          break;
      }
    }

    return {
      'system': systemCount,
      'other': otherCount,
    };
  }

  /// 使用 QuickAccessFolderDetector 检测快速访问文件夹
  /// 
  /// 该方法整合了：
  /// 1. 系统常见目录（Pictures, Downloads 等）及其一级子目录
  /// 2. 其他满足条件的用户文件夹（通过 5 层深度分析）
  Future<List<QuickAccessFolder>> _detectQuickAccessFolders() async {
    logger.i('QuickAccessPresenter._detectQuickAccessFolders called');
    try {
      final detectedFolders = await _quickAccessDetector.detectQuickAccessFolders();
      logger.i('Successfully detected ${detectedFolders.length} quick access folders');
      return detectedFolders;
    } catch (e, stackTrace) {
      logger.e('Error detecting quick access folders: $e\n$stackTrace');
      return []; // 返回空列表，避免中断扫描流程
    }
  }

  /// 为文件夹推荐别名
  String recommendAlias({
    required String path,
    required String originalName,
    QuickAccessFolderType? type,
  }) {
    return _aliasService.recommendAlias(
      path: path,
      originalName: originalName,
      type: type,
    );
  }

  /// 批量添加文件夹（用于通知确认后的批量添加）
  Future<int> batchAddFolders(List<QuickAccessFolder> folders) async {
    logger.i(
      'QuickAccessPresenter.batchAddFolders called: ${folders.length} folders',
    );
    int addedCount = 0;

    for (final folder in folders) {
      try {
        final result = await _localSource.addFolderWithResult(folder);
        if (result == AddFolderResult.added ||
            result == AddFolderResult.unhidden) {
          addedCount++;
        }
      } catch (e) {
        logger.w('Error adding folder ${folder.path}: $e');
      }
    }

    await loadQuickAccessFolders();
    return addedCount;
  }

  /// 批量删除文件夹
  Future<int> batchRemoveFolders(List<String> ids) async {
    logger.i(
      'QuickAccessPresenter.batchRemoveFolders called: ${ids.length} folders',
    );
    int removedCount = 0;

    for (final id in ids) {
      try {
        final success = await _localSource.removeFolder(id);
        if (success) removedCount++;
      } catch (e) {
        logger.w('Error removing folder $id: $e');
      }
    }

    await loadQuickAccessFolders();
    return removedCount;
  }

  /// 获取按类型分组的文件夹
  Map<QuickAccessFolderType, List<QuickAccessFolder>> getFoldersByType() {
    final folders = _viewModel.folders;
    final grouped = <QuickAccessFolderType, List<QuickAccessFolder>>{};

    for (final type in QuickAccessFolderType.values) {
      grouped[type] = folders.where((f) => f.type == type).toList();
    }

    return grouped;
  }

  /// 获取应用根目录及其子目录的映射
  @Deprecated('AppRoot and AppSubfolder types have been consolidated into Other')
  Map<String, List<QuickAccessFolder>> getAppFolderHierarchy() {
    logger.w('getAppFolderHierarchy is deprecated');
    return {};
  }

  // ==================== 新增方法 ====================

  /// 加入快速访问
  Future<bool> addToQuickAccess(String id) async {
    logger.i('QuickAccessPresenter.addToQuickAccess called: $id');
    try {
      // 步骤3：验证文件夹是否存在
      final allFolders = await _localSource.getAllFolders();
      final folder = allFolders.firstWhere(
        (f) => f.id == id,
        orElse: () => throw Exception('Folder not found'),
      );

      // 检查文件夹是否仍然存在于文件系统
      final dir = Directory(folder.path);
      if (!await dir.exists()) {
        logger.w('Folder does not exist on file system: ${folder.path}');
        // 自动清理不存在的文件夹
        await _localSource.removeFolder(id);
        await loadQuickAccessFolders();
        return false;
      }

      final success = await _localSource.addToQuickAccess(id);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error adding to quick access: $e');
      return false;
    }
  }

  /// 批量加入快速访问
  Future<int> batchAddToQuickAccess(List<String> ids) async {
    logger.i(
      'QuickAccessPresenter.batchAddToQuickAccess called: ${ids.length} items',
    );
    try {
      final count = await _localSource.batchAddToQuickAccess(ids);
      await loadQuickAccessFolders();
      return count;
    } catch (e) {
      logger.e('Error batch adding to quick access: $e');
      return 0;
    }
  }

  /// 移出快速访问
  Future<bool> removeFromQuickAccess(String id) async {
    logger.i('QuickAccessPresenter.removeFromQuickAccess called: $id');
    try {
      final success = await _localSource.removeFromQuickAccess(id);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error removing from quick access: $e');
      return false;
    }
  }

  /// 批量移出快速访问
  Future<int> batchRemoveFromQuickAccess(List<String> ids) async {
    logger.i(
      'QuickAccessPresenter.batchRemoveFromQuickAccess called: ${ids.length} items',
    );
    try {
      final count = await _localSource.batchRemoveFromQuickAccess(ids);
      await loadQuickAccessFolders();
      return count;
    } catch (e) {
      logger.e('Error batch removing from quick access: $e');
      return 0;
    }
  }

  /// 忽略文件夹
  Future<bool> hideFolder(String id) async {
    logger.i('QuickAccessPresenter.hideFolder called: $id');
    try {
      final success = await _localSource.hideFolder(id);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error hiding folder: $e');
      return false;
    }
  }

  /// 批量忽略
  Future<int> batchHideFolders(List<String> ids) async {
    logger.i(
      'QuickAccessPresenter.batchHideFolders called: ${ids.length} items',
    );
    try {
      final count = await _localSource.batchHideFolders(ids);
      await loadQuickAccessFolders();
      return count;
    } catch (e) {
      logger.e('Error batch hiding folders: $e');
      return 0;
    }
  }

  /// 设置首页展示顺序
  Future<bool> setHomeDisplayOrder(String id, int? order) async {
    logger.i('QuickAccessPresenter.setHomeDisplayOrder called: $id -> $order');
    try {
      final success = await _localSource.setHomeDisplayOrder(id, order);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error setting home display order: $e');
      return false;
    }
  }

  /// 批量更新首页展示顺序（拖拽排序）
  Future<bool> updateHomeDisplayOrders(Map<String, int?> orderMap) async {
    logger.i(
      'QuickAccessPresenter.updateHomeDisplayOrders called: ${orderMap.length} items',
    );
    try {
      final success = await _localSource.updateHomeDisplayOrders(orderMap);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error updating home display orders: $e');
      return false;
    }
  }

  /// 获取首页文件夹
  Future<List<QuickAccessFolder>> getHomeFolders() async {
    try {
      return await _localSource.getHomeFolders();
    } catch (e) {
      logger.e('Error getting home folders: $e');
      return [];
    }
  }

  /// 获取已加入快速访问的文件夹
  Future<List<QuickAccessFolder>> getAddedFolders() async {
    try {
      return await _localSource.getAddedFolders();
    } catch (e) {
      logger.e('Error getting added folders: $e');
      return [];
    }
  }

  /// 获取仅扫描但未加入的文件夹
  Future<List<QuickAccessFolder>> getScannedOnlyFolders() async {
    try {
      return await _localSource.getScannedOnlyFolders();
    } catch (e) {
      logger.e('Error getting scanned only folders: $e');
      return [];
    }
  }

  // ==================== 数据清理 ====================

  /// 执行数据清理，移除不符合条件的记录
  /// 
  /// 三条清理规则：
  /// 1. 文件夹不存在的记录（不论isAddedToQuickAccess状态）
  /// 2. type==other 但实际是系统文件夹的记录
  /// 3. type==other 且 !isAddedToQuickAccess 但不再满足扫描条件的记录
  Future<CleanupResult> _performDataCleanup() async {
    logger.i('QuickAccessPresenter._performDataCleanup called');
    
    int removedNonExistent = 0;
    int removedMisclassified = 0;
    int removedUnqualified = 0;

    try {
      // 获取所有文件夹
      final allFolders = await _localSource.getAllFolders();
      logger.i('Checking ${allFolders.length} folders for cleanup');

      final foldersToRemove = <String>[];

      for (final folder in allFolders) {
        // 规则1：文件夹不存在的记录
        final dir = Directory(folder.path);
        if (!await dir.exists()) {
          logger.i('Cleanup: Removing non-existent folder: ${folder.path}');
          foldersToRemove.add(folder.id);
          removedNonExistent++;
          continue;
        }

        // 规则2：type==other 但实际是系统文件夹的记录
        if (folder.type == QuickAccessFolderType.other && 
            SystemFoldersConfig.isSystemFolder(folder.path)) {
          logger.i('Cleanup: Removing misclassified system folder: ${folder.path}');
          foldersToRemove.add(folder.id);
          removedMisclassified++;
          continue;
        }

        // 规则3：type==other 且 !isAddedToQuickAccess 但不再满足扫描条件的记录
        // 这需要重新扫描该文件夹，看它是否仍然符合"other"类型的条件
        if (folder.type == QuickAccessFolderType.other && 
            !folder.isAddedToQuickAccess) {
          // 使用 QuickAccessFolderDetector 判断该文件夹是否仍满足条件
          final shouldKeep = await _shouldKeepOtherFolder(folder.path);
          if (!shouldKeep) {
            logger.i('Cleanup: Removing unqualified other folder: ${folder.path}');
            foldersToRemove.add(folder.id);
            removedUnqualified++;
            continue;
          }
        }
      }

      // 批量删除
      if (foldersToRemove.isNotEmpty) {
        logger.i('Cleanup: Removing ${foldersToRemove.length} folders');
        for (final id in foldersToRemove) {
          await _localSource.removeFolder(id);
        }
      }

      final result = CleanupResult(
        removedNonExistent: removedNonExistent,
        removedMisclassified: removedMisclassified,
        removedUnqualified: removedUnqualified,
      );

      logger.i('Cleanup completed: $result');
      return result;

    } catch (e, stackTrace) {
      logger.e('Error during data cleanup: $e\n$stackTrace');
      return CleanupResult(
        removedNonExistent: removedNonExistent,
        removedMisclassified: removedMisclassified,
        removedUnqualified: removedUnqualified,
      );
    }
  }

  /// 判断一个other类型的文件夹是否应该保留
  /// 
  /// 检查该文件夹是否仍然满足"其他文件夹"的扫描条件：
  /// - 不是隐藏文件夹
  /// - 有足够的文件或子文件夹
  /// - 符合QuickAccessFolderDetector的筛选逻辑
  Future<bool> _shouldKeepOtherFolder(String path) async {
    try {
      final dir = Directory(path);
      
      // 1. 检查是否是隐藏文件夹
      final name = path.split('/').last;
      if (name.startsWith('.')) {
        return false;
      }

      // 2. 检查文件夹是否有内容
      final entities = await dir.list().toList();
      if (entities.isEmpty) {
        return false;
      }

      // 3. 文件夹需要有一定数量的文件或子文件夹才能被认为是"有价值的"
      // 这个逻辑与 QuickAccessFolderDetector 的筛选条件保持一致
      final files = entities.whereType<File>().length;
      final subDirs = entities.whereType<Directory>().length;
      
      // 需要至少有5个文件或2个子文件夹
      return files >= 5 || subDirs >= 2;

    } catch (e) {
      logger.e('Error checking if should keep other folder: $e');
      return false;
    }
  }

  // ==================== 首次扫描自动配置 ====================

  /// 首次扫描后自动将系统一级目录加入快速访问并设置别名
  /// 
  /// 在首次安装时，自动将常用的系统文件夹（Download、Pictures等）
  /// 加入快速访问列表，并设置中文别名，提升首次使用体验
  /// 
  /// **执行操作**：
  /// 1. 筛选系统一级目录（排除子目录）
  /// 2. 将这些目录加入快速访问列表
  /// 3. 设置对应的中文别名（从 SystemFoldersConfig 获取）
  /// 
  /// **返回**：成功加入的文件夹数量
  Future<int> _autoAddSystemFoldersToQuickAccess(
    List<QuickAccessFolder> scannedFolders,
  ) async {
    logger.i('[FirstScan] Auto-adding system root folders to quick access...');
    
    // 筛选系统一级目录（排除子目录）
    final systemRootFolders = scannedFolders
        .where((f) => 
          f.type == QuickAccessFolderType.system && 
          !f.isSystemSubfolder
        )
        .toList();
    
    logger.i('[FirstScan] Found ${systemRootFolders.length} system root folders');
    
    // 批量加入快速访问并设置别名
    int successCount = 0;
    for (final folder in systemRootFolders) {
      try {
        // 加入快速访问（不自动设置别名，由用户自行决定）
        final addSuccess = await addToQuickAccess(folder.id);
        if (addSuccess) {
          logger.i('[FirstScan] Added system folder: ${folder.path}');
          successCount++;
        } else {
          logger.w('[FirstScan] Failed to add ${folder.path} to quick access');
        }
      } catch (e) {
        logger.w('[FirstScan] Failed to process ${folder.path}: $e');
      }
    }
    
    logger.i('[FirstScan] Auto-added $successCount/${systemRootFolders.length} system folders to quick access');
    return successCount;
  }
}

/// 扫描结果
class ScanResult {
  final int totalFound;
  final int newlyAdded;
  final int alreadyExists;
  final int unhidden;

  // 按类型统计
  final int systemCount;
  final int otherCount;

  // 清理统计
  final int removedNonExistent;
  final int removedMisclassified;
  final int removedUnqualified;

  ScanResult({
    required this.totalFound,
    required this.newlyAdded,
    required this.alreadyExists,
    this.unhidden = 0,
    this.systemCount = 0,
    this.otherCount = 0,
    this.removedNonExistent = 0,
    this.removedMisclassified = 0,
    this.removedUnqualified = 0,
  });

  bool get hasNewFolders => newlyAdded > 0;
  bool get hasUnhidden => unhidden > 0;
  bool get hasCleaned => removedNonExistent > 0 || removedMisclassified > 0 || removedUnqualified > 0;

  @override
  String toString() {
    return 'ScanResult(total: $totalFound, new: $newlyAdded, exists: $alreadyExists, unhidden: $unhidden, system: $systemCount, other: $otherCount, cleaned: non-exist=$removedNonExistent, misclassified=$removedMisclassified, unqualified=$removedUnqualified)';
  }
}

/// 清理结果
class CleanupResult {
  final int removedNonExistent;
  final int removedMisclassified;
  final int removedUnqualified;

  CleanupResult({
    required this.removedNonExistent,
    required this.removedMisclassified,
    required this.removedUnqualified,
  });

  int get totalRemoved => removedNonExistent + removedMisclassified + removedUnqualified;

  @override
  String toString() {
    return 'CleanupResult(non-exist: $removedNonExistent, misclassified: $removedMisclassified, unqualified: $removedUnqualified, total: $totalRemoved)';
  }
}
