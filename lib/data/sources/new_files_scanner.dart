import 'dart:io';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/new_file_item.dart';
import 'package:easyfile/data/models/new_files_settings.dart';
import 'package:easyfile/data/sources/file_source_detector.dart';
import 'package:easyfile/platform/file_stats_channel.dart';

/// 新文件扫描器
/// 负责扫描指定目录下的新文件
class NewFilesScanner {
  final NewFilesSettings settings;
  DateTime? _lastScanTime;

  NewFilesScanner({required this.settings});

  /// 获取需要扫描的路径列表
  List<String> _getScanPaths() {
    final paths = <String>[];

    // 系统下载（始终扫描）
    paths.add('/storage/emulated/0/Download');

    // 相机和截屏路径（始终扫描，隐私控制在Presenter层过滤）
    paths.add('/storage/emulated/0/DCIM/Camera');
    paths.add('/storage/emulated/0/Pictures/Screenshots');
    paths.add('/storage/emulated/0/Pictures/WeiXin');

    // 添加其他常见路径
    paths.addAll([
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/bluetooth',
      '/storage/emulated/0/DingTalk',
      '/storage/emulated/0/tencent/MicroMsg/Download',
      '/storage/emulated/0/tencent/QQfile_recv',
      '/storage/emulated/0/tencent/WXWork',
      '/storage/emulated/0/BaiduNetdisk',
      '/storage/emulated/0/quark/Download',
      '/storage/emulated/0/UCDownloads',
      '/storage/emulated/0/Recordings',
    ]);

    // 添加用户自定义路径
    paths.addAll(settings.customScanPaths);

    return paths;
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

  /// 快速扫描（使用缓存时间判断）
  Future<List<NewFileItem>?> quickScanIfNeeded(
    List<NewFileItem> cachedItems,
  ) async {
    // 如果5分钟内扫描过，返回null表示使用缓存
    if (_lastScanTime != null &&
        DateTime.now().difference(_lastScanTime!) < Duration(minutes: 5)) {
      logger.d(
          'Using cached scan results (scanned ${DateTime.now().difference(_lastScanTime!).inMinutes} minutes ago)');
      return null;
    }

    // 否则执行扫描
    return await scanNewFiles();
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
}
