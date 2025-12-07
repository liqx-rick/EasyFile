import 'dart:io';
// import 'package:device_apps/device_apps.dart';  // 已替换为installed_apps
// import 'package:installed_apps/installed_apps.dart';  // 暂时不使用（无法从文件解析APK）
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/junk_file_scan_config.dart';
import 'package:easyfile/core/services/junk_file_cache_manager.dart';
import 'package:easyfile/data/models/junk_file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/utils/file_size_formatter.dart';

/// 垃圾文件扫描服务
class JunkFileService {
  final FilePresenter _filePresenter;
  final JunkFileCacheManager _cacheManager;

  JunkFileService({
    required FilePresenter filePresenter,
    required JunkFileCacheManager cacheManager,
  })  : _filePresenter = filePresenter,
        _cacheManager = cacheManager;

  /// 扫描垃圾文件
  ///
  /// [config] 扫描配置
  /// [onProgress] 进度回调 (当前进度, 总数, 当前路径)
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  Future<List<JunkFileItem>> scanJunkFiles({
    JunkFileScanConfig? config,
    void Function(int current, int total, String path)? onProgress,
    bool forceRefresh = false,
  }) async {
    config ??= const JunkFileScanConfig();

    // 1. 检查缓存
    if (!forceRefresh) {
      final cached = await _cacheManager.loadCache(config);
      if (cached != null && cached.isNotEmpty) {
        logger.i('使用缓存的垃圾文件数据: ${cached.length} 个');
        return cached;
      }
    }

    logger.i('开始扫描垃圾文件: ${config.description}');

    // 2. 获取扫描路径
    final scanPaths = await _filePresenter.getCommonScanPaths();
    final junkFiles = <JunkFileItem>[];
    final seenPaths = <String>{}; // 用于跟踪已扫描的文件路径，避免重复

    // 3. 扫描每个路径
    int processedPaths = 0;
    for (final path in scanPaths) {
      onProgress?.call(processedPaths++, scanPaths.length, path);

      await _scanDirectory(
        Directory(path),
        config: config,
        results: junkFiles,
        seenPaths: seenPaths,
      );
    }

    // 4. 按大小排序
    junkFiles.sort((a, b) => b.size.compareTo(a.size));

    // 5. 保存缓存
    await _cacheManager.saveCache(junkFiles, config);

    final totalSize = junkFiles.fold<int>(0, (sum, f) => sum + f.size);
    logger.i(
        '垃圾文件扫描完成: ${junkFiles.length} 个, 总大小: ${FileSizeFormatter.formatBytes(totalSize)}');

    return junkFiles;
  }

  /// 扫描目录（递归）
  Future<void> _scanDirectory(
    Directory dir, {
    required JunkFileScanConfig config,
    required List<JunkFileItem> results,
    required Set<String> seenPaths,
    int depth = 0,
  }) async {
    // 深度限制（避免过深扫描）
    final maxDepth = _getMaxDepth(dir.path);
    if (depth > maxDepth) return;

    // 排除路径检查
    if (_isExcluded(dir.path, config.excludePaths)) return;

    try {
      final entities = await dir.list().toList();

      // 检查是否为空文件夹
      if (config.scanEmptyFolders && entities.isEmpty) {
        // 检查是否已扫描过此目录
        if (!seenPaths.contains(dir.path)) {
          seenPaths.add(dir.path); // 标记为已扫描
          final stat = await dir.stat();
          results.add(JunkFileItem(
            name: dir.path.split('/').last,
            path: dir.path,
            size: 0,
            type: JunkFileType.emptyFolder,
            modified: stat.modified,
          ));
        }
        return; // 空文件夹不再递归
      }

      // 扫描文件和子目录
      for (final entity in entities) {
        if (entity is File) {
          await _scanFile(entity, config: config, results: results, seenPaths: seenPaths);
        } else if (entity is Directory) {
          await _scanDirectory(
            entity,
            config: config,
            results: results,
            seenPaths: seenPaths,
            depth: depth + 1,
          );
        }
      }
    } catch (e) {
      // 权限错误等忽略
      logger.d('扫描目录失败: ${dir.path}, 错误: $e');
    }
  }

  /// 扫描文件
  Future<void> _scanFile(
    File file, {
    required JunkFileScanConfig config,
    required List<JunkFileItem> results,
    required Set<String> seenPaths,
  }) async {
    final fileName = file.path.split('/').last;
    final lowerName = fileName.toLowerCase();

    // 检查是否已经扫描过此文件
    if (seenPaths.contains(file.path)) {
      return;
    }

    try {
      final stat = await file.stat();

      // 1. 检查APK
      if (config.scanApk && lowerName.endsWith('.apk')) {
        logger.d('发现APK文件: $fileName');

        // 注意：由于installed_apps包不支持从文件解析包名，暂时无法判断是否已安装
        // 因此显示所有APK，让用户手动判断
        seenPaths.add(file.path); // 标记为已扫描
        results.add(JunkFileItem(
          name: fileName,
          path: file.path,
          size: stat.size,
          type: JunkFileType.apk,
          modified: stat.modified,
          packageName: null, // 暂时无法获取
          isInstalled: false, // 暂时无法判断
        ));
        logger.i(
            '已添加APK: $fileName (${FileSizeFormatter.formatBytes(stat.size)})');
      }

      // 2. 检查临时文件
      if (config.scanTempFiles && _isTempFile(lowerName)) {
        final daysSinceModified =
            DateTime.now().difference(stat.modified).inDays;

        // 仅添加超过指定天数的临时文件
        if (daysSinceModified >= config.minTempFileDays) {
          seenPaths.add(file.path); // 标记为已扫描
          results.add(JunkFileItem(
            name: fileName,
            path: file.path,
            size: stat.size,
            type: JunkFileType.tempFile,
            modified: stat.modified,
          ));
        }
      }
    } catch (e) {
      // 权限错误等忽略
      logger.d('扫描文件失败: ${file.path}, 错误: $e');
    }
  }

  /// 根据路径类型动态调整扫描深度
  int _getMaxDepth(String path) {
    final lowerPath = path.toLowerCase();

    // 应用数据目录浅扫（避免扫描大量应用子目录）
    if (lowerPath.contains('android/data') ||
        lowerPath.contains('android/obb')) {
      return 3;
    }

    // 相册目录中等深度
    if (lowerPath.contains('dcim') || lowerPath.contains('pictures')) {
      return 5;
    }

    // 其他目录正常深度
    return 10;
  }

  /// 判断是否为临时文件
  bool _isTempFile(String lowerName) {
    return lowerName.endsWith('.tmp') ||
        lowerName.endsWith('.temp') ||
        lowerName.startsWith('tmp_') ||
        lowerName.startsWith('temp_') ||
        lowerName.contains('.tmp.') ||
        lowerName.contains('.temp.');
  }

  /// 判断路径是否被排除
  bool _isExcluded(String path, List<String> excludePaths) {
    if (excludePaths.isEmpty) return false;

    final lowerPath = path.toLowerCase();
    return excludePaths
        .any((exclude) => lowerPath.contains(exclude.toLowerCase()));
  }

  /// 删除垃圾文件
  Future<bool> deleteJunkFile(JunkFileItem item) async {
    try {
      if (item.type == JunkFileType.emptyFolder) {
        final dir = Directory(item.path);

        // 二次验证：确保文件夹仍然为空
        final entities = await dir.list().toList();
        if (entities.isNotEmpty) {
          logger.w('文件夹不为空，取消删除: ${item.path} (包含 ${entities.length} 个项目)');
          return false; // 不为空则拒绝删除
        }

        // 确认为空后才删除
        await dir.delete();
        logger.i('删除空文件夹: ${item.path}');
      } else {
        await File(item.path).delete();
        logger.i('删除垃圾文件: ${item.path}');
      }
      return true;
    } catch (e) {
      logger.e('删除失败: ${item.path}, 错误: $e');
      return false;
    }
  }

  /// 批量删除
  Future<Map<String, dynamic>> deleteMultiple(List<JunkFileItem> items) async {
    int success = 0;
    int failed = 0;
    int totalSize = 0;

    for (final item in items) {
      final result = await deleteJunkFile(item);
      if (result) {
        success++;
        totalSize += item.size;
      } else {
        failed++;
      }
    }

    return {
      'success': success,
      'failed': failed,
      'totalSize': totalSize,
      'formattedSize': FileSizeFormatter.formatBytes(totalSize),
    };
  }

  /// 获取统计信息
  Map<JunkFileType, Map<String, dynamic>> getStatistics(
      List<JunkFileItem> files) {
    final stats = <JunkFileType, Map<String, dynamic>>{};

    for (final type in JunkFileType.values) {
      final typeFiles = files.where((f) => f.type == type).toList();
      final totalSize = typeFiles.fold<int>(0, (sum, f) => sum + f.size);

      stats[type] = {
        'count': typeFiles.length,
        'size': totalSize,
        'formattedSize': FileSizeFormatter.formatBytes(totalSize),
        'files': typeFiles,
      };
    }

    return stats;
  }
}
