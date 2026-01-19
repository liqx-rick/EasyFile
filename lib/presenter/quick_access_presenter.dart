import 'dart:io';

import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/data/models/comprehensive_scan_result.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/sources/quick_access_local_source.dart';
import 'package:easyfile/utils/file_utils.dart';

import 'package:easyfile/data/services/quick_access_folder_detector.dart';
import 'package:easyfile/core/services/category_file_cache_service.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';

/// 扫描配置常量
class _ScanConfig {
  /// 快速扫描的最大目录数量（避免首次启动太慢）
  static const int maxQuickScanDirectories = 10;

  /// 优先扫描的系统目录关键词
  static const List<String> priorityDirectoryKeywords = [
    'dcim',
    'picture',
    'photo',
    'video',
    'movie',
    'music',
    'document',
    'download',
  ];
}

/// 快速访问业务逻辑处理层
class QuickAccessPresenter {
  final QuickAccessLocalSource _localSource;
  final QuickAccessViewModel _viewModel;
  final QuickAccessFolderDetector _quickAccessDetector;

  QuickAccessPresenter({
    required QuickAccessLocalSource localSource,
    required QuickAccessViewModel viewModel,
    QuickAccessFolderDetector? quickAccessDetector,
  })  : _localSource = localSource,
        _viewModel = viewModel,
        _quickAccessDetector =
            quickAccessDetector ?? QuickAccessFolderDetector();

  // ==================== Getters ====================

  /// 暴露 _localSource 供外部使用（用于调试日志等）
  QuickAccessLocalSource get localSource => _localSource;

  // ==================== 私有辅助方法 ====================

  /// 通用单个操作包装器（返回 bool）
  Future<bool> _executeBoolOperation(
    String operationName,
    String id,
    Future<bool> Function() operation,
  ) async {
    logger.i('QuickAccessPresenter.$operationName called: $id');
    try {
      final success = await operation();
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error $operationName: $e');
      return false;
    }
  }

  /// 通用批量操作包装器（返回 int）
  Future<int> _executeBatchOperation(
    String operationName,
    List<String> ids,
    Future<int> Function() operation,
  ) async {
    logger.i(
      'QuickAccessPresenter.$operationName called: ${ids.length} items',
    );
    try {
      final count = await operation();
      await loadQuickAccessFolders();
      return count;
    } catch (e) {
      logger.e('Error $operationName: $e');
      return 0;
    }
  }

  /// 通用扫描操作包装器
  Future<T> _executeScanOperation<T>({
    required Future<T> Function(
      List<QuickAccessFolder> folders,
      _FolderStatistics stats,
    ) operation,
  }) async {
    _viewModel.setScanning(true);
    try {
      final detectedFolders = await _detectQuickAccessFolders();

      // 🔧 BUG FIX: 批量添加而非逐个添加，避免74次文件读写导致并发破坏
      logger.i('Batch adding ${detectedFolders.length} folders to avoid file corruption');
      final results = await _batchAddFoldersWithResult(detectedFolders);

      final stats = _countFolders(detectedFolders, results);
      return await operation(detectedFolders, stats);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 批量添加文件夹并返回每个文件夹的添加结果
  /// 避免逐个添加导致的大量文件I/O和潜在的并发问题
  Future<List<AddFolderResult>> _batchAddFoldersWithResult(
    List<QuickAccessFolder> newFolders,
  ) async {
    try {
      // 一次性读取现有文件夹
      final existingFolders = await _localSource.getAllFolders();
      final existingPaths = <String, QuickAccessFolder>{};
      for (final f in existingFolders) {
        existingPaths[f.path] = f;
      }

      // 准备结果和待保存的文件夹列表
      final results = <AddFolderResult>[];
      final foldersToSave = List<QuickAccessFolder>.from(existingFolders);

      // 处理每个新文件夹
      for (final newFolder in newFolders) {
        final existing = existingPaths[newFolder.path];

        if (existing != null) {
          // 已存在
          if (existing.isHidden) {
            // 恢复隐藏的文件夹
            logger.d('Unhiding folder: ${newFolder.path}');
            final index = foldersToSave.indexWhere((f) => f.path == newFolder.path);
            if (index != -1) {
              foldersToSave[index] = existing.copyWith(isHidden: false);
              results.add(AddFolderResult.unhidden);
            }
          } else {
            // 已存在且未隐藏
            results.add(AddFolderResult.exists);
          }
        } else {
          // 新文件夹
          foldersToSave.add(newFolder);
          results.add(AddFolderResult.added);
        }
      }

      // 一次性保存所有文件夹
      final success = await _localSource.saveFolders(foldersToSave);
      if (!success) {
        logger.e('Failed to save folders in batch operation');
        // 如果保存失败，将所有未存在的结果改为error
        return results.map((r) => 
          r == AddFolderResult.added ? AddFolderResult.error : r
        ).toList();
      }

      logger.i('Successfully saved ${foldersToSave.length} folders in one operation');
      return results;
    } catch (e, stackTrace) {
      logger.e('Error in batch add operation: $e\n$stackTrace');
      // 返回错误结果
      return List.filled(newFolders.length, AddFolderResult.error);
    }
  }

  /// 文件夹统计辅助类
  _FolderStatistics _countFolders(
    List<QuickAccessFolder> folders,
    List<AddFolderResult> results,
  ) {
    int newlyAdded = 0;
    int unhidden = 0;
    int alreadyExists = 0;
    int systemCount = 0;
    int otherCount = 0;

    // 统计类型
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

    // 统计添加结果
    for (final result in results) {
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

    return _FolderStatistics(
      newlyAdded: newlyAdded,
      unhidden: unhidden,
      alreadyExists: alreadyExists,
      systemCount: systemCount,
      otherCount: otherCount,
    );
  }

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

  /// 设置用户别名
  Future<bool> setUserAlias(String id, String? alias) async {
    return _executeBoolOperation(
      'setUserAlias($id -> $alias)',
      id,
      () => _localSource.setAlias(id, alias),
    );
  }

  /// 更新访问信息
  Future<void> updateAccessInfo(String path) async {
    logger.d('QuickAccessPresenter.updateAccessInfo called: $path');
    try {
      await _localSource.updateAccessInfo(path);
      // 不需要刷新整个列表，只更新访问时间
    } catch (e) {
      logger.e('Error updating access info: $e');
    }
  }

  // ==================== 扫描功能 ====================

  /// 执行首次综合扫描（扫描快速访问目录 + 分类文件）
  ///
  /// 该方法会执行以下操作：
  /// 1. 扫描系统目录 (0-20%)
  /// 2. 扫描分类文件 (30-95%)
  /// 3. 保存缓存 (95-100%)
  ///
  /// [scanCategoryFiles] 是一个可选的回调函数，用于扫描分类文件并返回统计结果
  /// [onProgress] 进度回调，参数为进度值 (0.0 - 1.0)，用于实时更新 UI
  Future<ComprehensiveScanResult> performFirstTimeComprehensiveScan({
    Future<Map<FileCategory, int>> Function()? scanCategoryFiles,
    void Function(double progress)? onProgress,
  }) async {
    logger.i('QuickAccessPresenter.performFirstTimeComprehensiveScan called');

    // 初始进度
    onProgress?.call(0.0);

    try {
      onProgress?.call(0.05);

      // 使用通用扫描包装器
      return await _executeScanOperation(
        operation: (detectedFolders, stats) async {
          logger.i(
              'Detector found ${detectedFolders.length} quick access folders');
          onProgress?.call(0.20);

          // 🆕 首次扫描特殊处理：自动将系统一级目录加入快速访问
          await _autoAddSystemFoldersToQuickAccess(detectedFolders);

          // 扫描分类文件（如果提供了扫描函数）(30-95%)
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

          // 保存分类文件缓存 (95-100%)
          final cacheService = CategoryFileCacheService();
          await cacheService.saveCategoryCounts(categoryFileCounts);

          await loadQuickAccessFolders();
          onProgress?.call(1.0);

          return ComprehensiveScanResult(
            quickAccessFoldersFound: detectedFolders.length,
            systemFoldersCount: stats.systemCount,
            otherFoldersCount: stats.otherCount,
            newlyAdded: stats.newlyAdded,
            alreadyExists: stats.alreadyExists,
            unhidden: stats.unhidden,
            categoryFileCounts: categoryFileCounts,
            totalFilesScanned: totalFilesScanned,
            success: true,
          );
        },
      );
    } catch (e, stackTrace) {
      logger.e('Error performing comprehensive scan: $e\n$stackTrace');
      return ComprehensiveScanResult.error(e.toString());
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
      if (_ScanConfig.priorityDirectoryKeywords
          .any((keyword) => path.contains(keyword))) {
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
            final fileName = entity.path.split(Platform.pathSeparator).last;
            final extension = FileUtils.getExtension(fileName);
            final category =
                AppConfig.instance.fileTypes.getCategoryByExtension(extension);
            counts[category] = (counts[category] ?? 0) + 1;
            counts[FileCategory.all] = (counts[FileCategory.all] ?? 0) + 1;
          }
        }

        totalFilesFound += filesInDir;
        logger.i('Scanned $dirPath: found $filesInDir files');

        scannedDirs++;

        // 限制扫描时间，避免首次启动太慢
        if (scannedDirs >= _ScanConfig.maxQuickScanDirectories) {
          logger.i(
            'Reached scan limit (${_ScanConfig.maxQuickScanDirectories} directories), stopping early',
          );
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

  /// 执行深度扫描（系统目录 + 用户目录）
  ///
  /// 扫描流程：
  /// 1. 使用 QuickAccessFolderDetector 扫描符合条件的文件夹
  /// 2. 将扫描结果添加到数据库（新增/恢复隐藏）
  /// 3. 清理过期数据（两类）：
  ///    - 文件夹不存在：删除记录（所有类型，无论是否加入快速访问）
  ///    - "其他"类型未被扫描到 + 未加入快速访问：删除记录（不符合条件）
  /// 4. 标记新增文件夹（显示 NEW 徽章）
  Future<ScanResult> performDeepScan() async {
    logger.i('QuickAccessPresenter.performDeepScan called');

    try {
      final beforeScanIds =
          (await _localSource.getAllFolders()).map((f) => f.id).toSet();

      // 使用通用扫描包装器
      return await _executeScanOperation(
        operation: (detectedFolders, stats) async {
          logger.i(
              'Deep scan found ${detectedFolders.length} quick access folders');

          final scannedPaths = detectedFolders.map((f) => f.path).toSet();

          // 清理过期数据
          final allFolders = await _localSource.getAllFolders();
          final toRemove =
              await _identifyStaleFolders(allFolders, scannedPaths);

          if (toRemove.isNotEmpty) {
            await _localSource.removeFolders(toRemove);
            logger
                .i('Removed ${toRemove.length} stale folders after deep scan');
          }

          await loadQuickAccessFolders();

          // 标记新增的文件夹
          final afterScanIds = _viewModel.folders.map((f) => f.id).toSet();
          final validNewIds = afterScanIds.difference(beforeScanIds).toList();

          if (validNewIds.isNotEmpty) {
            _viewModel.markAsNew(validNewIds);
          }

          return ScanResult(
            totalFound: detectedFolders.length,
            newlyAdded: stats.newlyAdded,
            alreadyExists: stats.alreadyExists,
            unhidden: stats.unhidden,
            systemCount: stats.systemCount,
            otherCount: stats.otherCount,
          );
        },
      );
    } catch (e, stackTrace) {
      logger.e('Error performing deep scan: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    }
  }

  /// 识别需要清理的过期文件夹
  ///
  /// 清理规则：
  /// 1. 文件夹不存在：删除（用户已删除，保留无意义）
  /// 2. "其他"类型 + 本次未扫描到 + 未加入快速访问：删除（不符合条件）
  /// 3. "其他"类型 + 本次未扫描到 + 已加入快速访问：保留（用户主动添加）
  Future<List<String>> _identifyStaleFolders(
    List<QuickAccessFolder> allFolders,
    Set<String> scannedPaths,
  ) async {
    final toRemove = <String>[];

    for (final existingFolder in allFolders) {
      // 规则1：文件夹不存在，直接删除（无论是否加入快速访问）
      final folderExists = await Directory(existingFolder.path).exists();
      if (!folderExists) {
        toRemove.add(existingFolder.id);
        logger.d('Removing non-existent folder: ${existingFolder.path}');
        continue;
      }

      // 规则2："其他"类型未被扫描到
      if (existingFolder.type == QuickAccessFolderType.other &&
          !scannedPaths.contains(existingFolder.path)) {
        // 已加入快速访问：保留（用户主动添加的）
        if (existingFolder.isAddedToQuickAccess) {
          logger.d(
            'Keeping manually added folder (not scanned): ${existingFolder.path}',
          );
          continue;
        }

        // 未加入快速访问：删除（不符合当前条件）
        toRemove.add(existingFolder.id);
        logger.d('Removing stale folder (not scanned): ${existingFolder.path}');
      }
    }

    return toRemove;
  }

  /// 使用 QuickAccessFolderDetector 检测快速访问文件夹
  ///
  /// 该方法整合了：
  /// 1. 系统常见目录（Pictures, Downloads 等）及其一级子目录
  /// 2. 其他满足条件的用户文件夹（通过 5 层深度分析）
  Future<List<QuickAccessFolder>> _detectQuickAccessFolders() async {
    logger.i('QuickAccessPresenter._detectQuickAccessFolders called');
    try {
      final detectedFolders =
          await _quickAccessDetector.detectQuickAccessFolders();
      logger.i(
          'Successfully detected ${detectedFolders.length} quick access folders');
      return detectedFolders;
    } catch (e, stackTrace) {
      logger.e('Error detecting quick access folders: $e\n$stackTrace');
      return []; // 返回空列表，避免中断扫描流程
    }
  }

  // ==================== 新增方法 ====================

  /// 加入快速访问
  Future<bool> addToQuickAccess(String id) async {
    logger.i('QuickAccessPresenter.addToQuickAccess called: $id');
    try {
      // 验证文件夹是否存在
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

      return await _executeBoolOperation(
        'addToQuickAccess',
        id,
        () => _localSource.addToQuickAccess(id),
      );
    } catch (e) {
      logger.e('Error adding to quick access: $e');
      return false;
    }
  }

  /// 批量加入快速访问
  Future<int> batchAddToQuickAccess(List<String> ids) async {
    try {
      final validIds = await _filterValidFolders(ids);
      if (validIds.isEmpty) {
        return 0;
      }
      return _executeBatchOperation(
        'batchAddToQuickAccess',
        validIds,
        () => _localSource.batchAddToQuickAccess(validIds),
      );
    } catch (e) {
      logger.e('Error in batchAddToQuickAccess: $e');
      return 0;
    }
  }

  /// 移出快速访问
  Future<bool> removeFromQuickAccess(String id) async {
    return _executeBoolOperation(
      'removeFromQuickAccess',
      id,
      () => _localSource.removeFromQuickAccess(id),
    );
  }

  /// 批量移出快速访问
  Future<int> batchRemoveFromQuickAccess(List<String> ids) async {
    return _executeBatchOperation(
      'batchRemoveFromQuickAccess',
      ids,
      () => _localSource.batchRemoveFromQuickAccess(ids),
    );
  }

  /// 忽略文件夹
  Future<bool> hideFolder(String id) async {
    return _executeBoolOperation(
      'hideFolder',
      id,
      () => _localSource.hideFolder(id),
    );
  }

  /// 批量忽略
  Future<int> batchHideFolders(List<String> ids) async {
    return _executeBatchOperation(
      'batchHideFolders',
      ids,
      () => _localSource.batchHideFolders(ids),
    );
  }

  /// 获取已加入快速访问的文件夹
  Future<List<QuickAccessFolder>> getAddedFolders() async {
    return _executeFolderQuery(() => _localSource.getAddedFolders());
  }

  /// 获取仅扫描但未加入的文件夹
  Future<List<QuickAccessFolder>> getScannedOnlyFolders() async {
    return _executeFolderQuery(() => _localSource.getScannedOnlyFolders());
  }

  /// 通用文件夹查询包装器
  Future<List<QuickAccessFolder>> _executeFolderQuery(
    Future<List<QuickAccessFolder>> Function() query,
  ) async {
    try {
      return await query();
    } catch (e) {
      logger.e('Error executing folder query: $e');
      return [];
    }
  }

  /// 验证并过滤有效的文件夹ID
  Future<List<String>> _filterValidFolders(List<String> ids) async {
    final allFolders = await _localSource.getAllFolders();
    final validIds = <String>[];

    for (final id in ids) {
      final folder = allFolders.firstWhere(
        (f) => f.id == id,
        orElse: () => throw Exception('Folder not found: $id'),
      );

      // 检查文件夹是否仍然存在于文件系统
      final dir = Directory(folder.path);
      if (await dir.exists()) {
        validIds.add(id);
      } else {
        logger.w('Skipping non-existent folder: ${folder.path}');
        // 自动清理不存在的文件夹
        await _localSource.removeFolder(id);
      }
    }

    return validIds;
  }

  // ==================== 数据清理 ====================

  /// 首次扫描后自动将系统一级目录加入快速访问
  ///
  /// 在首次安装时，自动将常用的系统文件夹（Download、Pictures等）
  /// 加入快速访问列表，提升首次使用体验
  ///
  /// **执行操作**：
  /// 1. 筛选系统一级目录（排除子目录）
  /// 2. 使用批量操作加入快速访问列表（性能优化）
  ///
  /// **返回**：成功加入的文件夹数量
  Future<int> _autoAddSystemFoldersToQuickAccess(
    List<QuickAccessFolder> scannedFolders,
  ) async {
    logger.i('[FirstScan] Auto-adding system root folders to quick access...');

    // 筛选系统一级目录（排除子目录）
    final systemRootFolders = scannedFolders
        .where((f) =>
            f.type == QuickAccessFolderType.system && !f.isSystemSubfolder)
        .toList();

    logger
        .i('[FirstScan] Found ${systemRootFolders.length} system root folders');

    if (systemRootFolders.isEmpty) {
      return 0;
    }

    // 使用批量操作（一次刷新数据库，性能优化）
    final ids = systemRootFolders.map((f) => f.id).toList();
    final successCount = await batchAddToQuickAccess(ids);

    logger.i(
        '[FirstScan] Auto-added $successCount/${systemRootFolders.length} system folders to quick access');
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

  ScanResult({
    required this.totalFound,
    required this.newlyAdded,
    required this.alreadyExists,
    this.unhidden = 0,
    this.systemCount = 0,
    this.otherCount = 0,
  });

  bool get hasNewFolders => newlyAdded > 0;
  bool get hasUnhidden => unhidden > 0;

  @override
  String toString() {
    return 'ScanResult(total: $totalFound, new: $newlyAdded, exists: $alreadyExists, unhidden: $unhidden, system: $systemCount, other: $otherCount)';
  }
}

/// 文件夹统计数据（内部使用）
class _FolderStatistics {
  final int newlyAdded;
  final int unhidden;
  final int alreadyExists;
  final int systemCount;
  final int otherCount;

  _FolderStatistics({
    required this.newlyAdded,
    required this.unhidden,
    required this.alreadyExists,
    required this.systemCount,
    required this.otherCount,
  });
}
