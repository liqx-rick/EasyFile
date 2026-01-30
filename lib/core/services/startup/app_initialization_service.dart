import 'dart:convert';

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/initialization_stage.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/app_file_list_cache.dart';
import 'package:easyfile/core/services/file_count_cache.dart';
import 'package:easyfile/core/services/recommendation_service.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cache_service.dart';
import 'first_install_service.dart';
import 'initialization_config.dart';
import 'robust_progress_calculator.dart';

/// 应用初始化服务
///
/// 执行三阶段初始化过程：
/// - P0：基础初始化（快速访问菜单、收藏夹）
/// - P1：分类初始化（分类文件统计缓存）
/// - P2：深度扫描（完整文件系统扫描）
///
/// 进度回调会传递进度值和阶段信息，UI可以显示详细的进度和实时计数
typedef InitializationProgressCallback = void Function(
  double progress,
  InitializationStage? stage,
);

class AppInitializationService {
  final FilePresenter filePresenter;
  final QuickAccessPresenter quickAccessPresenter;
  final FirstInstallService firstInstallService;
  final CacheService cacheService;

  InitializationProgressCallback? onProgress;

  /// 初始化配置
  InitializationConfig? _config;

  /// 进度计算器（根据配置动态创建）
  RobustProgressCalculator? _progressCalculator;

  /// 已完成的阶段列表
  final List<String> _completedPhases = [];

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
  /// 1. P0: 加载基础资源（快速访问、收藏等）
  /// 2. P1: 加载分类统计缓存（分类扫描 + 推荐应用）
  /// 3. P2: 执行完整文件系统扫描（文件夹检测）
  ///
  /// [config] 初始化配置，控制各阶段是否执行
  Future<void> initializeFromScratch({InitializationConfig? config}) async {
    // 加载配置
    _config = config ?? await InitializationConfig.load();
    logger.i('[AppInitService] Starting full initialization with config: $_config');

    // 根据配置创建进度计算器（动态权重）
    _progressCalculator = RobustProgressCalculator(config: _config);
    logger.d('[AppInitService] Progress calculator initialized with dynamic weights');

    try {
      // 阶段P0: 加载基础资源（始终执行）
      logger.i('[AppInitService] P0: Loading basic resources...');
      await _loadBasicResources();

      // 阶段P1: 加载分类统计缓存（分类扫描 + 应用扫描）
      if (_config!.enableP1CategoryScan || _config!.enableP1AppScan) {
        logger.i('[AppInitService] P1: Loading category statistics cache...');
        await _loadCategoryStatisticsCache();
      } else {
        logger.i('[AppInitService] P1: Skipped (both P1.1 and P1.2 disabled)');
        // 标记所有P1阶段为已完成，避免进度计算错误
        _completedPhases.addAll([
          'p1_images',
          'p1_video',
          'p1_music',
          'p1_documents',
          'p1_downloads',
          'p1_apk',
          'p1_archive',
          'p1_apps',
        ]);
      }

      // 阶段P2: 执行文件夹检测（始终执行）
      logger.i('[AppInitService] P2: Executing folder detection...');
      await _executeFullFileSystemScan();

      // 更新缓存时间戳
      await cacheService.updateLastScanTime();

      // 标记为已初始化（重要：必须在P2完成后）
      await firstInstallService.markInitialized();

      // 显示完成消息并停顿，让用户看到完成状态
      _reportProgress(
        1.0,
        const InitializationStage(
          phase: 'completed',
          message: '✅ 初始化完成，开始探索吧',
          detail: null,
        ),
      );
      logger.i('[AppInitService] Full initialization completed');

      // 停顿1.5秒让用户看到完成消息
      await Future.delayed(const Duration(milliseconds: 1500));
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
  /// P0阶段：加载快速访问菜单、收藏夹等基本数据
  Future<void> _loadBasicResources() async {
    final phase = 'p0_init';

    try {
      // 开始阶段：0%
      _reportProgress(
        _progressCalculator!.calculateProgress(
          currentPhase: phase,
          stageProgress: 0.0,
        ),
        _progressCalculator!.buildStage(phase: phase, scannedCount: 0),
      );

      // 加载快速访问文件夹
      await quickAccessPresenter.loadQuickAccessFolders();
      logger.i('[AppInitService] P0: Quick access folders loaded');

      // 中间进度：50%
      _reportProgress(
        _progressCalculator!.calculateProgress(
          currentPhase: phase,
          stageProgress: 0.5,
        ),
        _progressCalculator!.buildStage(phase: phase, scannedCount: 1),
      );

      // 加载收藏文件
      await filePresenter.initializeFavoriteFiles();
      logger.i('[AppInitService] P0: Favorite files loaded');

      // 完成阶段：95%（不到100%，防止卡死）
      _reportProgress(
        _progressCalculator!.calculateProgress(
          currentPhase: phase,
          stageProgress: 0.95,
        ),
        _progressCalculator!.buildStage(phase: phase, scannedCount: 2),
      );

      // 标记阶段完成
      _completedPhases.add(phase);
      logger.i('[AppInitService] P0: Basic resources loading completed');
    } catch (e) {
      logger.e('[AppInitService] Basic resources loading failed: $e');
      // 标记阶段完成（即使失败也继续）
      _completedPhases.add(phase);
      logger.w('[AppInitService] Using default values for basic resources');
    }
  }

  /// 加载分类统计缓存
  ///
  /// P1阶段：扫描并统计各分类文件数，缓存结果
  /// 包含两个子阶段：
  /// - P1.1: 分类文件扫描（images, video, music, documents, downloads, apk, archive）
  /// - P1.2: 推荐应用扫描
  Future<void> _loadCategoryStatisticsCache() async {
    try {
      final Map<FileCategory, int> counts = {};

      // 初始化所有分类计数
      for (final category in FileCategory.values) {
        counts[category] = 0;
      }

      // 要扫描的分类类型（对应阶段权重）
      final categoriesToScan = [
        (CategoryType.images, 'p1_images'),
        (CategoryType.video, 'p1_video'),
        (CategoryType.music, 'p1_music'),
        (CategoryType.documents, 'p1_documents'),
        (CategoryType.downloads, 'p1_downloads'),
        (CategoryType.apk, 'p1_apk'),
        (CategoryType.archive, 'p1_archive'),
      ];

      int totalFiles = 0;

      // P1.1: 分类统计扫描（可选）
      if (_config!.enableP1CategoryScan) {
        logger.i('[AppInitService] P1.1: Category scan enabled');

        for (var i = 0; i < categoriesToScan.length; i++) {
          final (categoryType, phase) = categoriesToScan[i];

          try {
            // 扫描开始：当前分类0%
            _reportProgress(
              _progressCalculator!.calculateProgress(
                completedPhases: _completedPhases,
                currentPhase: phase,
                stageProgress: 0.0,
              ),
              _progressCalculator!.buildStage(phase: phase, scannedCount: 0),
            );

            // 使用Future来并行执行扫描和进度动画
            List<FileItem>? files;
            var isScanning = true;

            logger.d('[AppInitService] Starting scan for $phase with animation');

            // 启动扫描任务
            final scanFuture = filePresenter
                .scanFilesByCategory(
              categoryType,
              useHybridScan: true,
            )
                .then((result) {
              files = result;
              isScanning = false;
              logger.d('[AppInitService] Scan completed for $phase: ${result.length} files');
              return result;
            });

            // 同时运行进度动画（模拟扫描进度）
            var animationProgress = 0.1; // 从10%开始
            var updateCount = 0;
            while (isScanning && animationProgress < 0.9) {
              await Future.delayed(const Duration(milliseconds: 500));
              if (isScanning) {
                updateCount++;
                logger.d(
                    '[AppInitService] Animation update #$updateCount for $phase: ${(animationProgress * 100).toStringAsFixed(0)}%');
                _reportProgress(
                  _progressCalculator!.calculateProgress(
                    completedPhases: _completedPhases,
                    currentPhase: phase,
                    stageProgress: animationProgress,
                  ),
                  _progressCalculator!.buildStage(phase: phase, scannedCount: 0),
                );
                animationProgress += 0.1;
              }
            }

            logger
                .d('[AppInitService] Animation ended for $phase after $updateCount updates (isScanning: $isScanning)');

            // 等待扫描完成
            await scanFuture;
            final count = files?.length ?? 0;

            // 扫描完成：当前分类95%
            _reportProgress(
              _progressCalculator!.calculateProgress(
                completedPhases: _completedPhases,
                currentPhase: phase,
                stageProgress: 0.95,
              ),
              _progressCalculator!.buildStage(phase: phase, scannedCount: count),
            );

            // 💾 将文件列表保存到分类页面的缓存（避免用户首次进入时重新扫描）
            if (files != null) {
              await _saveToCategoryPageCache(categoryType, files!);

              // 映射到 FileCategory
              final fileCategory = _mapCategoryType(categoryType);
              counts[fileCategory] = count;
              totalFiles += count;
            }

            // 标记当前分类完成
            _completedPhases.add(phase);
            logger.i('[AppInitService] $phase completed: $count files (cached)');
          } catch (e) {
            logger.e('[AppInitService] Error scanning ${categoryType.name}: $e');
            // 标记阶段完成（即使失败也继续）
            _completedPhases.add(phase);
          }
        }

        // 缓存分类统计数据
        counts[FileCategory.all] = totalFiles;

        logger.i('[AppInitService] P1.1 completed: Total files = $totalFiles');
      } else {
        logger.i('[AppInitService] P1.1: Category scan disabled, skipping...');
        // 标记所有分类阶段为已完成
        _completedPhases.addAll([
          'p1_images',
          'p1_video',
          'p1_music',
          'p1_documents',
          'p1_downloads',
          'p1_apk',
          'p1_archive',
        ]);
      }

      // P1.2: 首页推荐应用扫描（可选）
      if (_config!.enableP1AppScan) {
        logger.i('[AppInitService] P1.2: App scan enabled');
        await _scanRecommendedApps();
      } else {
        logger.i('[AppInitService] P1.2: App scan disabled, skipping...');
        // 标记应用扫描阶段为已完成
        _completedPhases.add('p1_apps');
      }
    } catch (e) {
      logger.e('[AppInitService] Category statistics loading failed: $e');
      // 分类统计加载失败时使用零值继续
      logger.w('[AppInitService] Using zero values for category statistics');
    }
  }

  /// 扫描推荐应用（P1.2 阶段）
  ///
  /// 在首次启动时预扫描推荐应用，避免用户进入主页后看到loading状态
  Future<void> _scanRecommendedApps() async {
    final phase = 'p1_apps';

    try {
      logger.i('[AppInitService] P1.2: Starting recommended apps scan...');

      // 扫描开始：0%
      _reportProgress(
        _progressCalculator!.calculateProgress(
          completedPhases: _completedPhases,
          currentPhase: phase,
          stageProgress: 0.0,
        ),
        _progressCalculator!.buildStage(phase: phase, scannedCount: 0),
      );

      // 创建应用检测服务
      final appDetectionService = AppDetectionService();
      await appDetectionService.initialize();

      // 中间进度：30%
      _reportProgress(
        _progressCalculator!.calculateProgress(
          completedPhases: _completedPhases,
          currentPhase: phase,
          stageProgress: 0.3,
        ),
        _progressCalculator!.buildStage(phase: phase, scannedCount: 0),
      );

      // 创建统一扫描器（使用全局FileCountCache）
      final fileCountCache = await locator.getAsync<FileCountCache>();
      final fileListCache = await locator.getAsync<AppFileListCache>();
      final scanner = UnifiedAppScanner(
        appDetectionService,
        fileCountCache: fileCountCache,
        fileListCache: fileListCache,
      );

      // 创建推荐服务并执行扫描
      final recommendationService = RecommendationService(
        detectionService: appDetectionService,
        scanner: scanner,
      );

      // 中间进度：60%
      _reportProgress(
        _progressCalculator!.calculateProgress(
          completedPhases: _completedPhases,
          currentPhase: phase,
          stageProgress: 0.6,
        ),
        _progressCalculator!.buildStage(phase: phase, scannedCount: 0),
      );

      // 调用getRecommendations触发初始化扫描（如果需要）
      final recommendations = await recommendationService.getRecommendations();

      // 扫描完成：95%
      _reportProgress(
        _progressCalculator!.calculateProgress(
          completedPhases: _completedPhases,
          currentPhase: phase,
          stageProgress: 0.95,
        ),
        _progressCalculator!.buildStage(phase: phase, scannedCount: recommendations.length),
      );

      // 标记阶段完成
      _completedPhases.add(phase);
      logger.i('[AppInitService] P1.2 completed: ${recommendations.length} apps detected');
    } catch (e) {
      logger.e('[AppInitService] Error scanning recommended apps: $e');
      // 标记阶段完成（即使失败也继续）
      _completedPhases.add(phase);
      logger.w('[AppInitService] Continuing initialization despite recommendation scan failure');
    }
  }

  /// 执行文件系统扫描
  ///
  /// P2阶段：检测快速访问文件夹
  /// P1.1已完成所有分类文件扫描和缓存，此阶段不再重复扫描
  Future<void> _executeFullFileSystemScan() async {
    final phase = 'p2_folders';

    try {
      logger.i('[AppInitService] P2: Starting quick access folder detection...');

      // 扫描开始：0%
      _reportProgress(
        _progressCalculator!.calculateProgress(
          completedPhases: _completedPhases,
          currentPhase: phase,
          stageProgress: 0.0,
        ),
        _progressCalculator!.buildStage(phase: phase, scannedCount: 0),
      );

      // 用于跟踪文件夹数量
      int foldersFound = 0;

      // 使用 QuickAccessPresenter 检测快速访问文件夹
      final scanResult = await quickAccessPresenter.performFirstTimeComprehensiveScan(
        onProgress: (progress) {
          // 将 quickAccessPresenter 的进度映射到当前阶段
          _reportProgress(
            _progressCalculator!.calculateProgress(
              completedPhases: _completedPhases,
              currentPhase: phase,
              stageProgress: progress,
            ),
            _progressCalculator!.buildStage(
              phase: phase,
              scannedCount: foldersFound,
            ),
          );
        },
        scanCategoryFiles: null, // ⚡ 优化：移除重复扫描，使用P1.1的缓存数据
      );

      // 更新文件夹数量
      foldersFound = scanResult.foldersFound;

      // 扫描完成：95%
      _reportProgress(
        _progressCalculator!.calculateProgress(
          completedPhases: _completedPhases,
          currentPhase: phase,
          stageProgress: 0.95,
        ),
        _progressCalculator!.buildStage(phase: phase, scannedCount: foldersFound),
      );

      // 标记阶段完成
      _completedPhases.add(phase);
      logger.i('[AppInitService] P2 completed: ${scanResult.foldersFound} folders found');
    } catch (e) {
      logger.e('[AppInitService] File system scan failed: $e');
      // 标记阶段完成（即使失败也继续）
      _completedPhases.add(phase);
      logger.w('[AppInitService] Scan failed but marking as initialized (previous stages complete)');
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

  /// 保存文件列表到分类页面的缓存
  ///
  /// 使用与 CategoryFilePage._saveToCache() 相同的格式和缓存键
  /// 这样用户首次进入分类页面时可以直接使用，无需重新扫描
  Future<void> _saveToCategoryPageCache(
    CategoryType categoryType,
    List<FileItem> files,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'category_cache_${categoryType.name}';

      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'categoryType': categoryType.name,
        'files': files
            .map(
              (file) => {
                'name': file.name,
                'path': file.path,
                'size': file.size,
                'modified': file.modified.millisecondsSinceEpoch,
              },
            )
            .toList(),
      };

      await prefs.setString(key, json.encode(cacheData));
      logger.i('[AppInitService] Saved ${files.length} files to category page cache: ${categoryType.name}');
    } catch (e) {
      logger.e('[AppInitService] Error saving category page cache for ${categoryType.name}: $e');
    }
  }

  /// 报告进度
  void _reportProgress(double progress, InitializationStage? stage) {
    logger.d(
        '[AppInitService] _reportProgress: progress=${(progress * 100).toStringAsFixed(1)}%, stage.message=${stage?.message}, stage.detail=${stage?.detail}');
    onProgress?.call(progress, stage);
  }
}
