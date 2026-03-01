import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/core/services/apk_cache_service.dart';
import 'package:easyfile/core/services/app_list_cache_manager.dart';
import 'package:easyfile/core/services/duplicate_file_service.dart';
import 'package:easyfile/core/services/duplicate_file_smart_cache.dart';
import 'package:easyfile/core/services/enhanced_duplicate_file_scan_service.dart';
import 'package:easyfile/core/services/large_file_cache_manager.dart';
import 'package:easyfile/core/services/large_file_service.dart';
import 'package:easyfile/core/services/trash_file_cache_manager.dart';
import 'package:easyfile/core/services/trash_file_service.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/task_card.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/utils/file_size_formatter.dart';

/// 智能任务生成器
///
/// 根据扫描结果生成优先级排序的任务卡片列表
class SmartTaskGenerator {
  /// 最多生成的任务卡片数量
  static const int maxTaskCount = 5;

  /// 重复文件最小可节省空间（字节）
  static const int duplicateMinSavableSize = 50 * 1024 * 1024; // 50MB

  /// 系统回收站最小文件数
  static const int trashMinFileCount = 10;

  /// 系统回收站最小总大小（字节）
  static const int trashMinTotalSize = 100 * 1024 * 1024; // 100MB

  /// APK最小文件数
  static const int apkMinFileCount = 3;

  /// APK最小总大小（字节）
  static const int apkMinTotalSize = 50 * 1024 * 1024; // 50MB

  /// 应用缓存最小总大小（字节）
  static const int appCacheMinTotalSize = 200 * 1024 * 1024; // 100MB（测试用）

  /// 大文件最小单个文件大小（字节）
  static const int largeFileMinSize = 100 * 1024 * 1024; // 100MB

  /// 生成智能任务卡片列表
  ///
  /// [onTaskAction] - 任务操作回调，参数为任务类型
  /// [onTaskDismiss] - 任务忽略回调，参数为任务类型
  Future<List<TaskCard>> generateTasks({
    required Function(TaskType) onTaskAction,
    required Function(TaskType) onTaskDismiss,
  }) async {
    final stopwatch = Stopwatch()..start();
    logger.i('========== 开始生成智能任务卡片 ==========');

    final tasks = <TaskCard>[];

    try {
      // 1. 检查重复文件
      await _checkDuplicateFiles(tasks, onTaskAction, onTaskDismiss);

      // 2. 检查大文件
      await _checkLargeFiles(tasks, onTaskAction, onTaskDismiss);

      // 3. 检查系统回收站
      await _checkSystemTrash(tasks, onTaskAction, onTaskDismiss);

      // 4. 检查APK文件（通过垃圾文件服务）
      await _checkApkFiles(tasks, onTaskAction, onTaskDismiss);

      // 5. 检查应用缓存
      await _checkAppCache(tasks, onTaskAction, onTaskDismiss);

      // 按优先级排序
      tasks.sort((a, b) => b.priority.compareTo(a.priority));

      // 最多返回5个任务
      final result = tasks.take(maxTaskCount).toList();

      stopwatch.stop();
      logger.i('生成 ${result.length} 个任务卡片，耗时 ${stopwatch.elapsedMilliseconds}ms');

      return result;
    } catch (e, stackTrace) {
      logger.e('生成任务卡片失败: $e\n$stackTrace');
      return [];
    }
  }

  /// 检查重复文件
  Future<void> _checkDuplicateFiles(
    List<TaskCard> tasks,
    Function(TaskType) onTaskAction,
    Function(TaskType) onTaskDismiss,
  ) async {
    try {
      final config = DuplicateFileScanConfig(
        scanMode: DuplicateScanMode.full,
      );

      // 只从缓存读取，不触发扫描（避免阻塞UI）
      final cacheManager = DuplicateFileSmartCache();
      final cache = await cacheManager.loadCache(config);

      if (cache == null || cache.groups.isEmpty) {
        logger.d('重复文件缓存不存在，跳过任务生成（等待后台扫描）');
        return;
      }

      final result = cache.groups;

      if (result.isEmpty) {
        logger.d('未发现重复文件');
        return;
      }

      // 计算可节省空间
      final savableSize = _calculateDuplicateSavableSize(result);

      if (savableSize < duplicateMinSavableSize) {
        logger.d('重复文件可节省空间不足 (${FileSizeFormatter.formatBytes(savableSize)})');
        return;
      }

      final priority = _calculatePriority(savableSize);

      tasks.add(TaskCard(
        type: TaskType.duplicateFiles,
        priority: priority,
        title: '发现 ${result.length} 组重复文件',
        subtitle: '可节省 ${FileSizeFormatter.formatBytes(savableSize)}',
        savableSize: savableSize,
        fileCount: result.length,
        onAction: () => onTaskAction(TaskType.duplicateFiles),
        onDismiss: () => onTaskDismiss(TaskType.duplicateFiles),
      ));

      logger.i('✓ 重复文件任务: ${result.length}组, 可节省 ${FileSizeFormatter.formatBytes(savableSize)}');
    } catch (e) {
      logger.w('检查重复文件失败: $e');
    }
  }

  /// 检查大文件
  Future<void> _checkLargeFiles(
    List<TaskCard> tasks,
    Function(TaskType) onTaskAction,
    Function(TaskType) onTaskDismiss,
  ) async {
    try {
      logger.d('========== 开始检查大文件任务 ==========');
      // 优先从缓存加载（避免触发耗时的实时扫描）
      final cacheManager = LargeFileCacheManager();
      logger.d('创建 LargeFileCacheManager 实例');

      final cache = await cacheManager.loadCache();
      logger.d('loadCache() 返回结果: ${cache != null ? "有缓存(${cache.files.length}个文件)" : "null"}');

      List<FileItem> files;

      if (cache != null && cache.files.isNotEmpty) {
        // 使用缓存数据
        logger.i('✅ 使用大文件缓存数据: ${cache.files.length}个文件');
        files = cache.files;
      } else {
        // 缓存不存在或过期，返回空（由AssistantPage统一触发后台扫描）
        logger.w('⚠️ 大文件缓存不存在或已过期，跳过任务生成（等待后台扫描）');
        return;
      }

      if (files.isEmpty) {
        logger.d('未发现大文件');
        return;
      }

      final totalSize = files.fold<int>(0, (sum, file) => sum + file.size);
      final priority = _calculatePriority(totalSize);

      logger.d('大文件统计: 数量=${files.length}, 总大小=${FileSizeFormatter.formatBytes(totalSize)}, 优先级=$priority');

      tasks.add(TaskCard(
        type: TaskType.largeFiles,
        priority: priority,
        title: '发现 ${files.length} 个大文件',
        subtitle: '共占用 ${FileSizeFormatter.formatBytes(totalSize)}',
        savableSize: totalSize,
        fileCount: files.length,
        onAction: () => onTaskAction(TaskType.largeFiles),
        onDismiss: () => onTaskDismiss(TaskType.largeFiles),
      ));

      logger.i('✓ 大文件任务: ${files.length}个, 共 ${FileSizeFormatter.formatBytes(totalSize)}');
    } catch (e, stackTrace) {
      logger.e('检查大文件失败: $e\n$stackTrace');
    }
  }

  /// 检查系统回收站
  Future<void> _checkSystemTrash(
    List<TaskCard> tasks,
    Function(TaskType) onTaskAction,
    Function(TaskType) onTaskDismiss,
  ) async {
    try {
      logger.d('========== 开始检查系统回收站任务 ==========');
      // 使用缓存数据（避免耗时扫描）
      final cacheManager = TrashFileCacheManager();

      if (!await cacheManager.isCacheValid()) {
        logger.d('系统回收站缓存不存在，跳过任务生成（等待后台扫描）');
        return;
      }

      final cachedResult = await cacheManager.getCachedResult();
      if (cachedResult == null) {
        logger.d('系统回收站缓存为空');
        return;
      }

      // 只统计2个月以上的旧文件（与页面显示保持一致）
      final config = AppConfig.instance.fileScan;
      final months = config.systemTrashOldFileMonths;
      final cutoffDate = DateTime.now().subtract(Duration(days: months * 30));

      final oldFiles = cachedResult.allFiles.where((file) {
        final fileDate = file.trashedTime ?? file.modified;
        return fileDate.isBefore(cutoffDate);
      }).toList();

      final fileCount = oldFiles.length;
      final totalSize = oldFiles.fold<int>(
        0,
        (sum, file) => sum + file.size,
      );

      logger.d(
          '系统回收站缓存数据: 总共${cachedResult.allFiles.length}个文件, $months个月前的旧文件$fileCount个, ${FileSizeFormatter.formatBytes(totalSize)}');

      // 生成条件：文件数 >= 10 或 总大小 >= 100MB
      if (fileCount < trashMinFileCount && totalSize < trashMinTotalSize) {
        logger.d(
            '系统回收站不满足生成条件: 文件数=$fileCount(需要>=$trashMinFileCount), 大小=${FileSizeFormatter.formatBytes(totalSize)}(需要>=${FileSizeFormatter.formatBytes(trashMinTotalSize)})');
        return;
      }

      logger.i(
          '✅ 系统回收站满足生成条件: $months个月前的旧文件=$fileCount(>=$trashMinFileCount), 大小=${FileSizeFormatter.formatBytes(totalSize)}(>=${FileSizeFormatter.formatBytes(trashMinTotalSize)})');

      final priority = _calculatePriority(totalSize);

      tasks.add(TaskCard(
        type: TaskType.systemTrash,
        priority: priority,
        title: '系统回收站中发现 $fileCount 个未清理文件',
        subtitle: '超过 $months 个月，共占用 ${FileSizeFormatter.formatBytes(totalSize)}',
        savableSize: totalSize,
        fileCount: fileCount,
        onAction: () => onTaskAction(TaskType.systemTrash),
        onDismiss: () => onTaskDismiss(TaskType.systemTrash),
      ));

      logger.i('✓ 系统回收站任务卡已生成: $fileCount个旧文件($months个月前), ${FileSizeFormatter.formatBytes(totalSize)}, 优先级=$priority');
    } catch (e, stackTrace) {
      logger.e('检查系统回收站失败: $e\n$stackTrace');
    }
  }

  /// 检查APK文件（通过APK缓存服务）
  Future<void> _checkApkFiles(
    List<TaskCard> tasks,
    Function(TaskType) onTaskAction,
    Function(TaskType) onTaskDismiss,
  ) async {
    try {
      final apkCacheService = ApkCacheService();

      // 从APK缓存服务获取统计信息
      final cacheInfo = await apkCacheService.getCacheInfo();
      final exists = cacheInfo['exists'] as bool? ?? false;
      final isExpired = cacheInfo['isExpired'] as bool? ?? false;

      if (!exists || isExpired) {
        logger.d('APK缓存不存在或已过期，跳过任务生成（等待后台扫描）');
        return;
      }

      final apkCount = cacheInfo['apkCount'] as int? ?? 0;
      final apkSize = cacheInfo['apkSize'] as int? ?? 0;

      logger.d('APK文件统计: apkCount=$apkCount, apkSize=${FileSizeFormatter.formatBytes(apkSize)}');

      if (apkCount < apkMinFileCount && apkSize < apkMinTotalSize) {
        logger.d(
            'APK文件数不足或大小不足: 文件数=$apkCount(需要>=$apkMinFileCount), 大小=${FileSizeFormatter.formatBytes(apkSize)}(需要>=${FileSizeFormatter.formatBytes(apkMinTotalSize)})');
        return;
      }

      final priority = _calculatePriority(apkSize);

      tasks.add(TaskCard(
        type: TaskType.apkFiles,
        priority: priority,
        title: '发现 $apkCount 个安装包',
        subtitle: '共占用 ${FileSizeFormatter.formatBytes(apkSize)}',
        savableSize: apkSize,
        fileCount: apkCount,
        onAction: () => onTaskAction(TaskType.apkFiles),
        onDismiss: () => onTaskDismiss(TaskType.apkFiles),
      ));

      logger.i('✓ APK任务: $apkCount个, ${FileSizeFormatter.formatBytes(apkSize)}');
    } catch (e) {
      logger.w('检查APK文件失败: $e');
    }
  }

  /// 检查应用缓存（提醒类任务）
  Future<void> _checkAppCache(
    List<TaskCard> tasks,
    Function(TaskType) onTaskAction,
    Function(TaskType) onTaskDismiss,
  ) async {
    try {
      logger.d('========== 开始检查应用缓存任务 ==========');

      // 从应用列表缓存读取数据
      final appListCacheManager = AppListCacheManager();
      final cachedApps = await appListCacheManager.getCachedAppList(
        includeSystemApps: false, // 只统计用户应用
      );

      if (cachedApps == null || cachedApps.isEmpty) {
        logger.d('应用列表缓存不存在或为空，跳过任务生成（等待应用扫描）');
        return;
      }

      // 计算总缓存大小
      final totalCacheSize = cachedApps.fold<int>(
        0,
        (sum, app) => sum + (app.storageInfo?.cacheSize ?? 0),
      );

      // 统计有缓存的应用数量
      final appsWithCache = cachedApps
          .where(
            (app) => (app.storageInfo?.cacheSize ?? 0) > 0,
          )
          .length;

      logger.d(
          '应用缓存统计: 总应用数=${cachedApps.length}, 有缓存应用数=$appsWithCache, 总缓存大小=${FileSizeFormatter.formatBytes(totalCacheSize)}');

      // 检查是否满足生成条件
      if (totalCacheSize < appCacheMinTotalSize) {
        logger.d(
            '应用缓存不满足生成条件: 大小=${FileSizeFormatter.formatBytes(totalCacheSize)}(需要>=${FileSizeFormatter.formatBytes(appCacheMinTotalSize)})');
        return;
      }

      logger.i(
          '✅ 应用缓存满足生成条件: $appsWithCache个应用, ${FileSizeFormatter.formatBytes(totalCacheSize)}(>=${FileSizeFormatter.formatBytes(appCacheMinTotalSize)})');

      // 优先级相对较低（提醒类任务，需要跳转系统设置）
      final priority = _calculatePriority(totalCacheSize) - 1; // 降低一级优先级
      final adjustedPriority = priority > 0 ? priority : 1; // 确保优先级至少为1

      tasks.add(TaskCard(
        type: TaskType.appCache,
        priority: adjustedPriority,
        title: '发现 $appsWithCache 个应用有缓存',
        subtitle: '可清理 ${FileSizeFormatter.formatBytes(totalCacheSize)}',
        savableSize: totalCacheSize,
        fileCount: appsWithCache,
        onAction: () => onTaskAction(TaskType.appCache),
        onDismiss: () => onTaskDismiss(TaskType.appCache),
      ));

      logger.i(
          '✓ 应用缓存任务卡已生成: $appsWithCache个应用, ${FileSizeFormatter.formatBytes(totalCacheSize)}, 优先级=$adjustedPriority');
    } catch (e, stackTrace) {
      logger.e('检查应用缓存失败: $e\n$stackTrace');
    }
  }

  /// 计算可节省空间（重复文件）
  int _calculateDuplicateSavableSize(List<dynamic> groups) {
    int totalSavable = 0;
    for (final group in groups) {
      // 假设每组至少有1个文件可以删除
      // group应该有files属性和fileSize属性
      try {
        final files = group.files as List;
        if (files.length > 1) {
          final size = group.fileSize as int;
          // 可节省空间 = 文件大小 * (文件数 - 1)
          totalSavable += size * (files.length - 1);
        }
      } catch (e) {
        logger.w('计算重复文件可节省空间失败: $e');
      }
    }
    return totalSavable;
  }

  /// 计算任务优先级（基于可节省空间大小）
  ///
  /// 优先级范围: 1-5
  /// - 5: > 1GB
  /// - 4: > 500MB
  /// - 3: > 100MB
  /// - 2: > 50MB
  /// - 1: < 50MB
  int _calculatePriority(int size) {
    const gb = 1024 * 1024 * 1024;
    const mb500 = 500 * 1024 * 1024;
    const mb100 = 100 * 1024 * 1024;
    const mb50 = 50 * 1024 * 1024;

    if (size > gb) return 5;
    if (size > mb500) return 4;
    if (size > mb100) return 3;
    if (size > mb50) return 2;
    return 1;
  }

  /// 检查是否有缓存数据
  ///
  /// 返回一个Map，包含各类型缓存的存在情况
  /// 返回格式：{
  ///   'hasDuplicateCache': bool,
  ///   'hasLargeFileCache': bool,
  ///   'hasAnyCache': bool,
  /// }
  Future<Map<String, bool>> checkCacheStatus() async {
    try {
      bool hasDuplicateCache = false;
      bool hasLargeFileCache = false;

      // 检查重复文件缓存（只读取，不扫描）
      try {
        final config = DuplicateFileScanConfig(
          scanMode: DuplicateScanMode.full,
        );

        final cacheManager = DuplicateFileSmartCache();
        final cache = await cacheManager.loadCache(config);

        hasDuplicateCache = cache != null && cache.groups.isNotEmpty;
        if (hasDuplicateCache) {
          logger.d('✓ 发现重复文件缓存: ${cache.groups.length}组');
        } else {
          logger.d('✗ 重复文件缓存不存在');
        }
      } catch (e) {
        logger.w('检查重复文件缓存失败: $e');
      }

      // 检查大文件缓存
      try {
        final largeCacheManager = LargeFileCacheManager();
        final largeCache = await largeCacheManager.loadCache();

        hasLargeFileCache = largeCache != null && largeCache.files.isNotEmpty;
        if (hasLargeFileCache) {
          logger.d('✓ 发现大文件缓存: ${largeCache.files.length}个');
        } else {
          logger.d('✗ 大文件缓存不存在');
        }
      } catch (e) {
        logger.w('检查大文件缓存失败: $e');
      }

      // 检查系统回收站缓存
      bool hasTrashCache = false;
      try {
        final trashCacheManager = TrashFileCacheManager();
        hasTrashCache = await trashCacheManager.isCacheValid();
        if (hasTrashCache) {
          final trashCache = await trashCacheManager.getCachedResult();
          logger.d('✓ 发现系统回收站缓存: ${trashCache?.allFiles.length ?? 0}个文件');
        } else {
          logger.d('✗ 系统回收站缓存不存在');
        }
      } catch (e) {
        logger.w('检查系统回收站缓存失败: $e');
      }

      final hasAnyCache = hasDuplicateCache || hasLargeFileCache || hasTrashCache;

      logger.i('缓存状态: 重复文件=$hasDuplicateCache, 大文件=$hasLargeFileCache, 回收站=$hasTrashCache');

      return {
        'hasDuplicateCache': hasDuplicateCache,
        'hasLargeFileCache': hasLargeFileCache,
        'hasTrashCache': hasTrashCache,
        'hasAnyCache': hasAnyCache,
      };
    } catch (e) {
      logger.e('检查缓存失败: $e');
      return {
        'hasDuplicateCache': false,
        'hasLargeFileCache': false,
        'hasAnyCache': false,
      };
    }
  }

  /// 检查是否有缓存数据（向后兼容）
  ///
  /// 返回 true 表示至少有一种类型的缓存存在
  Future<bool> hasCachedData() async {
    final status = await checkCacheStatus();
    return status['hasAnyCache'] as bool;
  }

  /// 启动后台扫描
  ///
  /// [onProgress] - 进度回调
  /// [onComplete] - 完成回调（支持异步）
  /// [forceAll] - 是否强制扫描所有类型（默认false，只扫描缺失的类型）
  Future<void> startBackgroundScan({
    Function(String)? onProgress,
    Function()? onComplete,
    bool forceAll = false,
  }) async {
    logger.i('========== 启动后台扫描 ==========');

    try {
      // 检查缓存状态，决定需要扫描哪些类型
      final cacheStatus = await checkCacheStatus();
      final hasDuplicateCache = cacheStatus['hasDuplicateCache'] as bool;
      final hasLargeFileCache = cacheStatus['hasLargeFileCache'] as bool;
      final hasTrashCache = cacheStatus['hasTrashCache'] as bool;

      final tasks = <Future>[];

      // 只扫描缺失的类型（除非forceAll=true）
      if (!hasDuplicateCache || forceAll) {
        logger.i('📋 需要扫描重复文件');
        tasks.add(_scanDuplicateFilesInBackground());
        onProgress?.call('分析重复文件...');
      } else {
        logger.d('跳过重复文件扫描（已有缓存）');
      }

      if (!hasLargeFileCache || forceAll) {
        logger.i('📋 需要扫描大文件');
        tasks.add(_scanLargeFilesInBackground());
        onProgress?.call('检测大文件...');
      } else {
        logger.d('跳过大文件扫描（已有缓存）');
      }

      if (!hasTrashCache || forceAll) {
        logger.i('📋 需要扫描系统回收站');
        tasks.add(_scanTrashFilesInBackground());
        onProgress?.call('检测回收站...');
      } else {
        logger.d('跳过系统回收站扫描（已有缓存）');
      }

      if (tasks.isEmpty) {
        logger.i('所有类型都有缓存，无需扫描');
        // 即使不需要扫描也调用完成回调
        final completeResult = onComplete?.call();
        if (completeResult is Future) {
          await completeResult;
        }
        return;
      }

      // 并行扫描需要的类型
      await Future.wait(tasks);

      logger.i('✅ 后台扫描全部完成');

      // 等待完成回调执行完成（支持异步回调）
      final completeResult = onComplete?.call();
      if (completeResult is Future) {
        await completeResult;
      }
    } catch (e, stackTrace) {
      logger.e('后台扫描失败: $e\n$stackTrace');

      // 即使失败也调用完成回调（支持异步）
      final completeResult = onComplete?.call();
      if (completeResult is Future) {
        await completeResult;
      }
    }
  }

  /// 后台扫描重复文件
  Future<void> _scanDuplicateFilesInBackground() async {
    final stopwatch = Stopwatch()..start();
    try {
      logger.i('🔄 开始后台扫描重复文件...');

      final presenter = locator<FilePresenter>();
      final duplicateService = DuplicateFileService(presenter);
      final enhancedService = EnhancedDuplicateFileScanService(duplicateService);

      final config = DuplicateFileScanConfig(
        scanMode: DuplicateScanMode.full,
      );

      // 触发全量扫描（会自动缓存结果）
      final result = await enhancedService.smartScan(
        config,
        forceFullScan: true,
      );

      stopwatch.stop();
      logger.i('✅ 重复文件后台扫描完成: ${result.length}组, 耗时${stopwatch.elapsedMilliseconds}ms');
    } catch (e, stackTrace) {
      stopwatch.stop();
      logger.e('❌ 重复文件后台扫描失败: $e\n$stackTrace');
    }
  }

  /// 后台扫描大文件
  Future<void> _scanLargeFilesInBackground() async {
    final stopwatch = Stopwatch()..start();
    try {
      logger.i('🔄 开始后台扫描大文件...');

      // 直接创建LargeFileService实例（不使用依赖注入，因为它没有注册）
      final presenter = locator<FilePresenter>();
      final largeFileService = LargeFileService(presenter);
      final cacheManager = LargeFileCacheManager();

      final config = LargeFileScanConfig(
        minSizeInMB: (largeFileMinSize / (1024 * 1024)).round(),
      );

      // 执行扫描
      final files = await largeFileService.scanLargeFiles(
        minSizeInMB: config.minSizeInMB,
      );

      // 保存到缓存
      await cacheManager.saveCache(files: files, config: config);

      stopwatch.stop();
      logger.i('✅ 大文件后台扫描完成: ${files.length}个文件, 耗时${stopwatch.elapsedMilliseconds}ms');
    } catch (e, stackTrace) {
      stopwatch.stop();
      logger.e('❌ 大文件后台扫描失败: $e\n$stackTrace');
    }
  }

  /// 后台扫描系统回收站
  Future<void> _scanTrashFilesInBackground() async {
    final stopwatch = Stopwatch()..start();
    try {
      logger.i('🔄 开始后台扫描系统回收站...');

      // 直接创建TrashFileService实例（避免异步依赖注入的问题）
      final trashService = TrashFileService();

      // 初始化服务（检测设备支持）
      await trashService.initialize();

      // 执行扫描（会自动缓存结果）
      final result = await trashService.scanTrashBinsWithFiles(
        forceRefresh: true,
      );

      stopwatch.stop();
      logger.i('✅ 系统回收站后台扫描完成: ${result.allFiles.length}个文件, 耗时${stopwatch.elapsedMilliseconds}ms');
    } catch (e, stackTrace) {
      stopwatch.stop();
      logger.e('❌ 系统回收站后台扫描失败: $e\n$stackTrace');
    }
  }
}
