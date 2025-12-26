import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/new_file_item.dart';
import 'package:easyfile/data/models/new_files_settings.dart';
import 'package:easyfile/data/sources/file_source_detector.dart';
import 'package:easyfile/platform/file_stats_channel.dart';
import 'package:easyfile/platform/new_files_native_channel.dart';

/// 取消令牌：用于取消正在进行的扫描
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() {
    _cancelled = true;
    logger.i('CancelToken: Scan cancellation requested');
  }
}

/// 新文件扫描器
/// 负责扫描指定目录下的新文件
class NewFilesScanner {
  final NewFilesSettings settings;
  CancelToken? _currentScanToken;

  NewFilesScanner({required this.settings});

  /// 取消当前正在进行的扫描
  void cancelCurrentScan() {
    if (_currentScanToken != null && !_currentScanToken!.isCancelled) {
      _currentScanToken!.cancel();
      logger.i('NewFilesScanner: Current scan cancelled by user action');
    }
  }

  /// 获取需要扫描的路径列表（用于Dart降级扫描）
  List<String> _getScanPaths() {
    return [
      // 常用目录
      '/storage/emulated/0/Download',
      '/storage/emulated/0/DCIM/Camera',
      '/storage/emulated/0/Pictures/WeiXin',
      '/storage/emulated/0/Pictures/Screenshots',
      '/storage/emulated/0/tencent/MicroMsg/Download',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/bluetooth',
      // 其他应用目录
      '/storage/emulated/0/DingTalk',
      '/storage/emulated/0/tencent/QQfile_recv',
      '/storage/emulated/0/tencent/WXWork',
      '/storage/emulated/0/BaiduNetdisk',
      '/storage/emulated/0/quark/Download',
      '/storage/emulated/0/UCDownloads',
      '/storage/emulated/0/Recordings',
    ];
  }

  /// 扫描新文件（性能优化版）
  /// 
  /// **策略**:
  /// 1. 优先使用Android MediaStore原生扫描（快速，2-3秒）
  /// 2. 失败时降级到Dart文件系统扫描（慢，10-15秒）
  /// 
  /// **取消机制**: 支持Tab切换时中断扫描
  /// 
  /// **返回**: 按创建时间倒序排列的文件列表（最多displayCount*2项）
  Future<List<NewFileItem>> scanNewFiles() async {
    logger.i('NewFilesScanner: Starting scan (optimized)');
    
    // 取消之前的扫描
    if (_currentScanToken != null) {
      _currentScanToken!.cancel();
    }
    _currentScanToken = CancelToken();
    
    try {
      // 检查取消状态
      if (_currentScanToken!.isCancelled) {
        logger.i('NewFilesScanner: Scan cancelled before native scan');
        return [];
      }
      
      // 尝试使用原生优化扫描
      final nativeResults = await NewFilesNativeChannel.scanRecentFiles(
        settings.retentionDays,
      );
      
      // 检查取消状态
      if (_currentScanToken!.isCancelled) {
        logger.i('NewFilesScanner: Scan cancelled after native scan');
        return [];
      }
      
      // 限制数量（预留2倍用于缓存）
      final limitedResults = nativeResults.take(settings.displayCount * 2).toList();
      
      logger.i('NewFilesScanner: Native scan complete, found ${limitedResults.length} files');
      return limitedResults;
      
    } catch (e) {
      logger.w('NewFilesScanner: Native scan failed, fallback to Dart scan: $e');
      
      // 降级到Dart扫描
      return await _dartScanFallback();
    } finally {
      _currentScanToken = null;
    }
  }
  
  /// Dart扫描降级方案 (Legacy Fallback)
  /// 
  /// ⚠️ **仅在MediaStore失败时使用** - 正常情况下不会被调用
  /// 
  /// **原理**: 递归扫描预定义目录，过滤隐藏文件、0B文件，判断创建时间
  /// **性能**: 较慢（10-15秒），但能保证基本功能
  Future<List<NewFileItem>> _dartScanFallback() async {
    logger.i('NewFilesScanner: Using Dart fallback scan');
    
    // 检查取消状态
    if (_currentScanToken?.isCancelled ?? false) {
      logger.i('NewFilesScanner: Dart fallback cancelled before start');
      return [];
    }
    
    final cutoffDate =
        DateTime.now().subtract(Duration(days: settings.retentionDays));
    final results = <NewFileItem>[];
    final scanPaths = _getScanPaths();

    logger.i('Cutoff date: $cutoffDate (${settings.retentionDays} days ago)');
    logger.d('Scanning ${scanPaths.length} paths: $scanPaths');

    for (final dirPath in scanPaths) {
      // 检查取消状态
      if (_currentScanToken?.isCancelled ?? false) {
        logger.i('NewFilesScanner: Dart scan cancelled at $dirPath');
        break;
      }
      
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

    // 限制数量（预留2倍用于缓存）
    final limitedResults =
        results.take(settings.displayCount * 2).toList();

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

  /// 智能缓存策略 - 根据场景决定是否重新扫描
  ///
  /// **用户主动刷新**: 总是执行扫描（保证数据最新）
  /// **应用启动**: 检查缓存文件修改时间
  ///   - < 1小时: 使用缓存（返回null），后台静默刷新
  ///   - >= 1小时: 执行完整扫描
  ///
  /// **返回值**:
  /// - `null`: 使用缓存，Presenter层启动后台刷新
  /// - `List<NewFileItem>`: 新扫描结果，更新UI
  Future<List<NewFileItem>?> quickScanIfNeeded(
    List<NewFileItem> cachedItems, {
    bool isUserRefresh = false, // 是否为用户主动刷新
  }) async {
    // 用户主动刷新：始终扫描（快速响应）
    if (isUserRefresh) {
      logger.i('User refresh triggered, starting quick scan...');
      return await scanNewFiles();
    }

    // 应用启动加载：检查缓存文件年龄
    if (cachedItems.isNotEmpty) {
      try {
        // 获取缓存文件的修改时间
        final directory = await getApplicationDocumentsDirectory();
        final cacheFile = File('${directory.path}${Platform.pathSeparator}new_files_index.json');
        
        if (await cacheFile.exists()) {
          final stat = await cacheFile.stat();
          final age = DateTime.now().difference(stat.modified);

          // 1小时内使用缓存（立即显示）
          if (age < Duration(hours: 1)) {
            logger.d(
                'Using cached scan results (cache file age: ${age.inMinutes} minutes)');

            // 返回null表示使用缓存，后台刷新由Presenter层控制
            return null; // 使用缓存
          }

          // 超过1小时：执行完整扫描
          logger.i('Cache expired (${age.inHours} hours old), performing full scan');
        }
      } catch (e) {
        logger.e('Error checking cache file age: $e');
      }
    }

    // 首次扫描或缓存过期
    return await scanNewFiles();
  }


}
