import 'dart:io';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/new_file_item.dart';
import 'package:easyfile/data/models/new_files_settings.dart';
import 'package:easyfile/data/sources/file_source_detector.dart';
import 'package:easyfile/platform/file_stats_channel.dart';

/// 扫描优先级
enum ScanPriority {
  high,   // 高优先级：立即扫描（最常用目录）
  medium, // 中优先级：延迟扫描（常用目录）
  low,    // 低优先级：后台扫描（不常用目录）
}

/// 新文件扫描器
/// 负责扫描指定目录下的新文件
class NewFilesScanner {
  final NewFilesSettings settings;
  DateTime? _lastScanTime;

  NewFilesScanner({required this.settings});

  /// 获取扫描路径（按优先级分组）
  Map<ScanPriority, List<String>> _getScanPathsByPriority() {
    final Map<ScanPriority, List<String>> pathsByPriority = {
      ScanPriority.high: [],
      ScanPriority.medium: [],
      ScanPriority.low: [],
    };

    // 高优先级：最常用的目录（立即扫描，1-3秒内快速显示）
    pathsByPriority[ScanPriority.high]!.addAll([
      '/storage/emulated/0/Download',        // 下载
      '/storage/emulated/0/DCIM/Camera',     // 相机
      '/storage/emulated/0/Pictures/WeiXin', // 微信图片
    ]);

    // 中优先级：常用目录（延迟扫描，2-4秒显示）
    pathsByPriority[ScanPriority.medium]!.addAll([
      '/storage/emulated/0/Pictures/Screenshots',      // 截屏
      '/storage/emulated/0/tencent/MicroMsg/Download', // 微信下载
      '/storage/emulated/0/Documents',                 // 文档
      '/storage/emulated/0/bluetooth',                 // 蓝牙
    ]);

    // 低优先级：不常用目录（后台扫描，不阻塞UI）
    pathsByPriority[ScanPriority.low]!.addAll([
      '/storage/emulated/0/DingTalk',
      '/storage/emulated/0/tencent/QQfile_recv',
      '/storage/emulated/0/tencent/WXWork',
      '/storage/emulated/0/BaiduNetdisk',
      '/storage/emulated/0/quark/Download',
      '/storage/emulated/0/UCDownloads',
      '/storage/emulated/0/Recordings',
    ]);

    // 自定义路径归为低优先级
    pathsByPriority[ScanPriority.low]!.addAll(settings.customScanPaths);

    return pathsByPriority;
  }

  /// 获取需要扫描的路径列表（兼容旧方法）
  List<String> _getScanPaths() {
    final pathsByPriority = _getScanPathsByPriority();
    return [
      ...pathsByPriority[ScanPriority.high]!,
      ...pathsByPriority[ScanPriority.medium]!,
      ...pathsByPriority[ScanPriority.low]!,
    ];
  }

  /// 扫描新文件
  Future<List<NewFileItem>> scanNewFiles() async {
    logger.i('NewFilesScanner: Starting scan');
    final cutoffDate =
        DateTime.now().subtract(Duration(days: settings.retentionDays));
    final results = <NewFileItem>[];
    final scanPaths = _getScanPaths();

    logger.i('Cutoff date: $cutoffDate (${settings.retentionDays} days ago)');
    logger.d('Scanning ${scanPaths.length} paths: $scanPaths');

    for (final dirPath in scanPaths) {
      try {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) {
          logger.d('Path does not exist: $dirPath');
          continue;
        }

        logger.d('Scanning: $dirPath');
        final items = await _scanDirectory(dir, cutoffDate);
        results.addAll(items);
        logger.i(
            'Found ${items.length} files in $dirPath (Total: ${results.length})');
      } catch (e) {
        logger.e('Error scanning $dirPath: $e');
      }
    }

    // 按创建时间倒序排序
    results.sort((a, b) => b.created.compareTo(a.created));

    // 限制数量
    final limitedResults =
        results.take(settings.displayCount * 10).toList(); // 存储10倍数量用于缓存

    _lastScanTime = DateTime.now();
    logger.i(
        'NewFilesScanner: Scan complete, found ${limitedResults.length} files');

    return limitedResults;
  }

  /// 扫描单个目录
  Future<List<NewFileItem>> _scanDirectory(
    Directory dir,
    DateTime cutoffDate,
  ) async {
    final results = <NewFileItem>[];
    int totalFiles = 0;
    int matchedFiles = 0;

    try {
      // 递归扫描所有子目录
      final entities = dir.listSync(recursive: true);
      final filePaths = <String>[];

      // 先收集所有文件路径
      for (final entity in entities) {
        if (entity is File) {
          totalFiles++;
          filePaths.add(entity.path);
        }
      }

      if (filePaths.isEmpty) {
        return results;
      }

      // 批量获取文件创建时间（使用原生方法）
      final creationTimes =
          await FileStatsChannel.getFilesCreationTimes(filePaths);

      // 处理每个文件
      for (final filePath in filePaths) {
        try {
          final file = File(filePath);
          final stat = file.statSync();

          // 过滤条件1：排除隐藏文件（以.开头的文件）
          final fileName = filePath.split('/').last;
          if (fileName.startsWith('.')) {
            if (totalFiles <= 3) {
              logger.d('  ✗ $fileName (hidden file)');
            }
            continue;
          }

          // 过滤条件2：排除0B文件
          if (stat.size == 0) {
            if (totalFiles <= 3) {
              logger.d('  ✗ $fileName (0B file)');
            }
            continue;
          }

          // 使用真正的创建时间（如果获取失败，fallback到modified）
          final creationTime = creationTimes[filePath] ?? stat.modified;

          // 检查创建时间是否在保留期内
          if (creationTime.isAfter(cutoffDate)) {
            matchedFiles++;
            final source = FileSourceDetector.detectSource(filePath);

            final item = NewFileItem(
              path: filePath,
              created: creationTime,
              discovered: DateTime.now(),
              source: source,
            );

            results.add(item);

            if (matchedFiles <= 3) {
              logger.d('  ✓ $fileName (created: $creationTime)');
            }
          } else {
            if (totalFiles <= 3) {
              logger.d('  ✗ $fileName (created: $creationTime, too old)');
            }
          }
        } catch (e) {
          // 跳过无法访问的文件
          logger.d('Cannot access file: $filePath, error: $e');
        }
      }

      logger.d('  Summary: $matchedFiles matched out of $totalFiles files');
    } catch (e) {
      logger.e('Error listing directory ${dir.path}: $e');
    }

    return results;
  }

  /// 快速扫描（智能缓存策略）
  /// 
  /// 根据使用场景决定是否需要重新扫描：
  /// - 应用启动：1小时内使用缓存，后台增量扫描
  /// - 用户手动刷新：始终执行快速扫描
  Future<List<NewFileItem>?> quickScanIfNeeded(
    List<NewFileItem> cachedItems, {
    bool isUserRefresh = false, // 是否为用户主动刷新
  }) async {
    // 用户主动刷新：始终扫描（快速响应）
    if (isUserRefresh) {
      logger.i('User refresh triggered, starting quick scan...');
      return await scanNewFiles();
    }

    // 应用启动加载：智能缓存策略
    if (_lastScanTime != null) {
      final age = DateTime.now().difference(_lastScanTime!);
      
      // 1小时内使用缓存（立即显示）
      if (age < Duration(hours: 1)) {
        logger.d(
            'Using cached scan results (scanned ${age.inMinutes} minutes ago)');
        
        // 后台静默扫描（不阻塞UI）
        _backgroundIncrementalScan(cachedItems);
        
        return null; // 使用缓存
      }
      
      // 超过1小时：执行完整扫描
      logger.i('Cache expired (${age.inHours} hours old), performing full scan');
    }

    // 首次扫描或缓存过期
    return await scanNewFiles();
  }

  /// 后台增量扫描（不阻塞UI）
  void _backgroundIncrementalScan(List<NewFileItem> cachedItems) {
    // 异步执行，不等待结果
    Future.microtask(() async {
      try {
        logger.d('Starting background incremental scan...');
        final newItems = await incrementalScan(cachedItems);
        logger.i('Background scan complete: ${newItems.length} items');
        
        // 注意：这里只是扫描，不自动更新UI
        // UI更新由Presenter层控制
      } catch (e) {
        logger.e('Background scan error: $e');
      }
    });
  }

  /// 增量扫描（只扫描自上次扫描后的新文件）
  Future<List<NewFileItem>> incrementalScan(
    List<NewFileItem> existingItems,
  ) async {
    final scanStartTime =
        _lastScanTime ?? DateTime.now().subtract(Duration(days: 1));
    logger.i('NewFilesScanner: Incremental scan since $scanStartTime');

    final cutoffDate = scanStartTime;
    final results = <NewFileItem>[];
    final scanPaths = _getScanPaths();

    for (final dirPath in scanPaths) {
      try {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) continue;

        final items = await _scanDirectory(dir, cutoffDate);
        results.addAll(items);
      } catch (e) {
        logger.e('Error in incremental scan of $dirPath: $e');
      }
    }

    // 合并现有项和新项，去重
    final allItems = <String, NewFileItem>{};
    for (final item in existingItems) {
      allItems[item.path] = item;
    }
    for (final item in results) {
      allItems[item.path] = item; // 新项覆盖旧项
    }

    final mergedList = allItems.values.toList()
      ..sort((a, b) => b.created.compareTo(a.created));

    _lastScanTime = DateTime.now();
    logger.i('Incremental scan complete, found ${results.length} new files');

    return mergedList.take(settings.displayCount * 10).toList();
  }

  /// 分批扫描（支持优先级和渐进式结果）
  /// 
  /// 按优先级批次扫描，并通过回调逐步返回结果：
  /// - 第1批（高优先级）：1-3秒内完成，立即显示
  /// - 第2批（中优先级）：3-5秒内完成，更新显示
  /// - 第3批（低优先级）：后台扫描，不阻塞UI
  Future<List<NewFileItem>> scanNewFilesByPriority({
    Function(List<NewFileItem> partialResults)? onPartialResults,
  }) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: settings.retentionDays));
    final allResults = <NewFileItem>[];
    final pathsByPriority = _getScanPathsByPriority();

    logger.i('NewFilesScanner: Starting priority-based scan');

    // 批次1：高优先级（立即扫描）
    logger.i('Batch 1: Scanning high priority paths...');
    final highPriorityResults = await _scanPathsBatch(
      pathsByPriority[ScanPriority.high]!,
      cutoffDate,
    );
    allResults.addAll(highPriorityResults);
    
    // 第一批结果返回（快速显示）
    if (onPartialResults != null && highPriorityResults.isNotEmpty) {
      final sortedResults = List<NewFileItem>.from(allResults)
        ..sort((a, b) => b.created.compareTo(a.created));
      onPartialResults(sortedResults.take(settings.displayCount * 10).toList());
      logger.i('Batch 1 complete: ${highPriorityResults.length} files');
    }

    // 批次2：中优先级（延迟扫描）
    logger.i('Batch 2: Scanning medium priority paths...');
    final mediumPriorityResults = await _scanPathsBatch(
      pathsByPriority[ScanPriority.medium]!,
      cutoffDate,
    );
    allResults.addAll(mediumPriorityResults);
    
    // 第二批结果返回（更新显示）
    if (onPartialResults != null && mediumPriorityResults.isNotEmpty) {
      final sortedResults = List<NewFileItem>.from(allResults)
        ..sort((a, b) => b.created.compareTo(a.created));
      onPartialResults(sortedResults.take(settings.displayCount * 10).toList());
      logger.i('Batch 2 complete: ${mediumPriorityResults.length} files');
    }

    // 批次3：低优先级（后台扫描，不阻塞）
    _scanLowPriorityInBackground(
      pathsByPriority[ScanPriority.low]!,
      cutoffDate,
      allResults,
      onPartialResults,
    );

    // 返回高+中优先级的结果（低优先级结果通过回调异步返回）
    final sortedResults = allResults
      ..sort((a, b) => b.created.compareTo(a.created));

    _lastScanTime = DateTime.now();
    logger.i('Priority scan complete: ${sortedResults.length} files (excluding low priority)');

    return sortedResults.take(settings.displayCount * 10).toList();
  }

  /// 扫描一批路径
  Future<List<NewFileItem>> _scanPathsBatch(
    List<String> paths,
    DateTime cutoffDate,
  ) async {
    final results = <NewFileItem>[];

    for (final dirPath in paths) {
      try {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) {
          logger.d('Directory does not exist: $dirPath');
          continue;
        }

        logger.d('Scanning: $dirPath');
        final items = await _scanDirectory(dir, cutoffDate);
        results.addAll(items);
        logger.d('Found ${items.length} files in $dirPath');
      } catch (e) {
        logger.e('Error scanning $dirPath: $e');
      }
    }

    return results;
  }

  /// 后台扫描低优先级路径（不阻塞UI）
  void _scanLowPriorityInBackground(
    List<String> paths,
    DateTime cutoffDate,
    List<NewFileItem> existingResults,
    Function(List<NewFileItem>)? onPartialResults,
  ) {
    // 异步后台执行
    Future(() async {
      logger.i('Batch 3: Scanning low priority paths in background...');
      final lowPriorityResults = await _scanPathsBatch(paths, cutoffDate);
      
      if (lowPriorityResults.isNotEmpty) {
        existingResults.addAll(lowPriorityResults);
        
        // 第三批结果返回（后台更新）
        if (onPartialResults != null) {
          final sortedResults = List<NewFileItem>.from(existingResults)
            ..sort((a, b) => b.created.compareTo(a.created));
          onPartialResults(sortedResults.take(settings.displayCount * 10).toList());
          logger.i('Batch 3 complete: ${lowPriorityResults.length} files');
        }
      }
    });
  }
}
