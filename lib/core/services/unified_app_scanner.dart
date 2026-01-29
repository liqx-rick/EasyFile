import 'dart:io';
import 'dart:typed_data';
import 'package:easyfile/core/platform/app_file_scanner_channel.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/app_scanner_config.dart';
import 'package:easyfile/core/constants/system_folders_config.dart';
import 'package:easyfile/core/services/app_scan_result.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/file_count_cache.dart';
import 'package:easyfile/core/utils/cancellation_token.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';

/// 统一应用文件扫描器
///
/// 提供完整的应用文件扫描解决方案：
/// 1. 检测应用是否安装（持久化缓存）
/// 2. 获取应用图标（可选）
/// 3. MediaStore扫描（Android 11+，快速）
/// 4. 路径扫描（全版本兼容，全面）
/// 5. 结果对比与去重
/// 6. 文件数量缓存（6小时有效期）
///
/// 使用示例：
/// ```dart
/// final scanner = UnifiedAppScanner(
///   appDetectionService,
///   fileCountCache: fileCountCache,  // 可选
/// );
///
/// // 快速获取文件数量（优先使用缓存）
/// final count = await scanner.getFileCountFast(appKey: 'wechat');
/// if (count != null) {
///   print('微信文件数量: $count (来自缓存)');
/// }
///
/// // 完整扫描（会更新缓存）
/// final result = await scanner.scanApp(
///   appKey: 'wechat',
///   withIcon: true,
///   updateCache: true,  // 自动更新文件数量缓存
/// );
/// ```
class UnifiedAppScanner {
  final AppDetectionService _detectionService;
  final FileCountCache? _fileCountCache;

  /// 最大递归深度（避免深层目录遍历）
  static const int maxRecursionDepth = 5;

  /// 扫描结果缓存（appKey -> ScanResultCache）
  /// ⚠️ 使用静态变量确保跨实例共享缓存
  static final Map<String, _ScanResultCache> _scanCache = {};

  /// 缓存有效期（24小时）
  static const Duration _cacheExpiration = Duration(hours: 24);

  UnifiedAppScanner(
    this._detectionService, {
    FileCountCache? fileCountCache,
  }) : _fileCountCache = fileCountCache;

  /// 扫描应用文件
  ///
  /// [appKey] 应用标识，如 'wechat', 'qq'
  /// [additionalPaths] 附加扫描路径
  /// [withIcon] 是否获取应用图标
  /// [useMediaStore] 是否使用 MediaStore 扫描（Android 11+）
  /// [updateCache] 是否更新文件数量缓存（默认 true）
  /// [forceRefresh] 是否强制刷新，忽略缓存（默认 false）
  /// [cancellationToken] 取消令牌，用于中断扫描
  Future<AppScanResult> scanApp({
    required String appKey,
    List<String> additionalPaths = const [],
    bool withIcon = false,
    bool useMediaStore = true,
    bool updateCache = true,
    bool forceRefresh = false,
    CancellationToken? cancellationToken,
  }) async {
    final config = await AppConfig.instance.appScanner.getAppConfig(appKey);
    if (config == null) {
      final enabledApps = await AppConfig.instance.appScanner.getEnabledApps();
      throw ArgumentError(
        '未知应用: $appKey，支持的应用: ${enabledApps.map((a) => a.appKey).toList()}',
      );
    }

    logger.i('========== 开始扫描应用: ${config.appName} ($appKey) ==========');

    // 🚀 缓存检查：如果未强制刷新，先检查缓存
    if (!forceRefresh && _scanCache.containsKey(appKey)) {
      final cached = _scanCache[appKey]!;
      final cacheAge = DateTime.now().difference(cached.timestamp);

      if (cacheAge < _cacheExpiration) {
        logger.i('✅ 使用缓存结果 (缓存年龄: ${cacheAge.inMinutes}分钟, 有效期: ${_cacheExpiration.inHours}小时)');
        logger.i('   文件数量: ${cached.result.allFiles.length}');
        logger.i('========== 扫描完成: ${config.appName} ==========');
        return cached.result;
      } else {
        logger.i('⏰ 缓存已过期 (${cacheAge.inMinutes}分钟 > ${_cacheExpiration.inHours}小时), 执行新扫描');
        _scanCache.remove(appKey); // 清除过期缓存
      }
    }

    // 步骤1: 检测应用是否安装
    final detectionResult = await _detectionService.detectApp(config);

    if (!detectionResult.isInstalled) {
      logger.i('应用未安装: ${config.appName}');
      return AppScanResult.notInstalled(config.appName);
    }

    final packageName = detectionResult.packageName!;
    logger.i('应用已安装: $packageName');

    // 步骤2: 可选获取应用图标
    Uint8List? appIcon;
    if (withIcon) {
      appIcon = await _detectionService.getAppIcon(packageName);
      logger.d('图标获取: ${appIcon != null ? "成功 (${appIcon.length} bytes)" : "失败"}');
    }

    // 步骤3: 构建完整扫描路径
    final scanPaths = await _buildScanPaths(config, additionalPaths);
    logger.i('扫描路径: ${scanPaths.length} 个');

    // 步骤4: MediaStore 扫描（Android 11+）
    ScanResult mediaStoreResult = ScanResult(
      files: const [],
      duration: Duration.zero,
    );

    if (useMediaStore) {
      try {
        final supported = await AppFileScannerChannel.isOwnerPackageSupported();
        if (supported) {
          // 获取缓存中的旧数量
          final oldCount = _fileCountCache != null ? await _fileCountCache!.getFileCount(appKey) : null;

          mediaStoreResult = await _scanByMediaStore(packageName);

          // 计算增量
          final newCount = mediaStoreResult.files.length;
          if (oldCount != null && oldCount > 0) {
            final delta = newCount - oldCount;
            logger.i('MediaStore扫描: $newCount 文件 '
                '(${mediaStoreResult.duration.inMilliseconds}ms) '
                '[上次: $oldCount, 增量: ${delta > 0 ? '+' : ''}$delta]');
          } else {
            logger.i('MediaStore扫描: $newCount 文件 '
                '(${mediaStoreResult.duration.inMilliseconds}ms)');
          }
        } else {
          logger.w('MediaStore OWNER_PACKAGE_NAME 不支持（需要 Android 11+）');
        }
      } catch (e) {
        logger.e('MediaStore扫描失败: $e');
      }
    }

    // 步骤5: 路径扫描（带取消检查）
    if (cancellationToken?.isCancelled ?? false) {
      logger.w('扫描已取消: ${config.appName}');
      return AppScanResult.cancelled(config.appName);
    }
    
    final pathScanResult = await _scanByPaths(scanPaths, config.filePatterns, cancellationToken);
    logger.i('路径扫描: ${pathScanResult.files.length} 文件 '
        '(${pathScanResult.duration.inMilliseconds}ms)');

    // 步骤6: 计算差异文件
    final differenceFiles = _calculateDifference(
      pathScanResult.files,
      mediaStoreResult.files,
    );
    logger.i('差异文件: ${differenceFiles.length} 个');

    // 步骤7: 合并去重
    final totalBeforeMerge = mediaStoreResult.files.length + pathScanResult.files.length;
    final allFiles = _mergeAndDeduplicate(
      mediaStoreResult.files,
      pathScanResult.files,
    );
    final duplicates = totalBeforeMerge - allFiles.length;
    logger.i('总文件数: ${allFiles.length} (去重后), 去重前: $totalBeforeMerge, 重复: $duplicates 个');

    // 步骤8: 构建扫描结果
    final scanResult = AppScanResult(
      appName: config.appName,
      packageName: packageName,
      isInstalled: true,
      allFiles: allFiles,
      mediaStoreFiles: mediaStoreResult.files,
      pathScanFiles: pathScanResult.files,
      differenceFiles: differenceFiles,
      appIcon: appIcon,
      mediaStoreDuration: mediaStoreResult.duration,
      pathScanDuration: pathScanResult.duration,
    );

    // 步骤9: 更新缓存
    _scanCache[appKey] = _ScanResultCache(
      result: scanResult,
      timestamp: DateTime.now(),
    );
    logger.i('💾 扫描结果已缓存 (有效期: ${_cacheExpiration.inHours}小时)');

    // 调试：检查PDF文件的路径格式
    if (appKey == 'wechat') {
      final config = AppConfig.instance.fileTypes;
      // 查找PDF文件
      final mediaStorePdfs = mediaStoreResult.files.where((f) => config.isPdfFile(f.path)).toList();
      final pathScanPdfs = pathScanResult.files.where((f) => config.isPdfFile(f.path)).toList();

      if (mediaStorePdfs.isNotEmpty || pathScanPdfs.isNotEmpty) {
        logger.w('⚠️ PDF文件统计:');
        logger.w('  MediaStore: ${mediaStorePdfs.length} 个');
        logger.w('  路径扫描: ${pathScanPdfs.length} 个');

        // 显示最近的几个PDF路径
        if (mediaStorePdfs.length <= 3) {
          for (final pdf in mediaStorePdfs) {
            logger.w('  [MediaStore] ${pdf.path}');
          }
        }
        if (pathScanPdfs.length <= 3) {
          for (final pdf in pathScanPdfs) {
            logger.w('  [PathScan]  ${pdf.path}');
          }
        }

        // 检查是否有重复的PDF
        final mediaStorePdfPaths = mediaStorePdfs.map((f) => f.path).toSet();
        final pathScanPdfPaths = pathScanPdfs.map((f) => f.path).toSet();
        final commonPdfs = mediaStorePdfPaths.intersection(pathScanPdfPaths);

        logger.w('  共同PDF: ${commonPdfs.length} 个 (已去重)');
        logger.w('  MediaStore独有: ${mediaStorePdfPaths.length - commonPdfs.length} 个');
        logger.w('  PathScan独有: ${pathScanPdfPaths.length - commonPdfs.length} 个');

        // 输出独有PDF示例
        final mediaStoreOnlyPdfs = mediaStorePdfPaths.difference(commonPdfs);
        final pathScanOnlyPdfs = pathScanPdfPaths.difference(commonPdfs);

        if (mediaStoreOnlyPdfs.isNotEmpty) {
          logger.w('  MediaStore独有PDF示例 (前3个):');
          for (final path in mediaStoreOnlyPdfs.take(3)) {
            logger.w('    - $path');
          }
        }

        if (pathScanOnlyPdfs.isNotEmpty) {
          logger.w('  PathScan独有PDF示例 (前3个):');
          for (final path in pathScanOnlyPdfs.take(3)) {
            logger.w('    - $path');
          }
        }
      }
    }

    // 步骤8: 更新文件数量缓存
    if (updateCache && _fileCountCache != null) {
      await _fileCountCache!.setFileCount(appKey, allFiles.length);
      logger.d('文件数量缓存已更新: $appKey = ${allFiles.length}');
    }

    logger.i('========== 扫描完成: ${config.appName} ==========');

    return AppScanResult(
      appName: config.appName,
      packageName: packageName,
      isInstalled: true,
      appIcon: appIcon,
      mediaStoreFiles: mediaStoreResult.files,
      pathScanFiles: pathScanResult.files,
      differenceFiles: differenceFiles,
      allFiles: allFiles,
      mediaStoreDuration: mediaStoreResult.duration,
      pathScanDuration: pathScanResult.duration,
    );
  }

  /// 快速获取文件数量（优先使用缓存）
  ///
  /// 性能优化：
  /// - 优先读取缓存（<5ms）
  /// - 缓存失效则返回 null，由调用方决定是否完整扫描
  ///
  /// [appKey] 应用标识
  /// 返回缓存的文件数量，如果缓存不存在或已过期则返回 null
  ///
  /// 使用示例：
  /// ```dart
  /// final count = await scanner.getFileCountFast(appKey: 'wechat');
  /// if (count != null) {
  ///   // 使用缓存值快速显示
  ///   print('微信文件: $count 个 (来自缓存)');
  /// } else {
  ///   // 缓存失效，执行完整扫描
  ///   final result = await scanner.scanApp(appKey: 'wechat');
  ///   print('微信文件: ${result.totalCount} 个 (实时扫描)');
  /// }
  /// ```
  Future<int?> getFileCountFast({required String appKey}) async {
    if (_fileCountCache == null) return null;

    final count = await _fileCountCache!.getFileCount(appKey);
    if (count != null) {
      logger.d('文件数量缓存命中: $appKey = $count');
    } else {
      logger.d('文件数量缓存未命中: $appKey');
    }

    return count;
  }

  /// 批量快速获取文件数量（优先使用缓存）
  ///
  /// [appKeys] 应用Key列表
  /// 返回映射表（appKey -> 文件数量），未缓存的不包含在结果中
  Future<Map<String, int>> getFileCountBatchFast({
    required List<String> appKeys,
  }) async {
    if (_fileCountCache == null) return {};

    return await _fileCountCache!.getFileCountBatch(appKeys);
  }

  /// 清除文件数量缓存
  ///
  /// 用于用户主动刷新或检测到数据不准确时
  Future<void> clearFileCountCache({String? appKey}) async {
    if (_fileCountCache == null) return;

    if (appKey != null) {
      await _fileCountCache!.clearFileCount(appKey);
      logger.i('已清除文件数量缓存: $appKey');
    } else {
      await _fileCountCache!.clearAllCache();
      logger.i('已清除所有文件数量缓存');
    }
  }

  /// 构建扫描路径
  ///
  /// 结合基础路径、文件夹关键字和附加路径
  Future<List<String>> _buildScanPaths(
    AppConfigData config,
    List<String> additionalPaths,
  ) async {
    final paths = <String>[];

    // 动态查找：在基础路径中查找匹配的文件夹
    if (config.folderKeywords.isNotEmpty) {
      for (final keyword in config.folderKeywords) {
        try {
          final foundPaths = await AppFileScannerChannel.findFoldersContaining(
            SystemFoldersConfig.systemPaths,
            keyword,
          );
          paths.addAll(foundPaths);
        } catch (e) {
          logger.w('查找文件夹失败 ($keyword): $e');
        }
      }
    }

    // 添加配置的附加路径
    if (config.additionalPaths.isNotEmpty) {
      paths.addAll(config.additionalPaths);
    }

    // 添加用户提供的附加路径
    if (additionalPaths.isNotEmpty) {
      paths.addAll(additionalPaths);
    }

    // 去重
    return paths.toSet().toList();
  }

  /// MediaStore 扫描（方案2 - Android 11+）
  Future<ScanResult> _scanByMediaStore(String packageName) async {
    final startTime = DateTime.now();

    final files = await AppFileScannerChannel.scanByOwnerPackage(packageName);

    final duration = DateTime.now().difference(startTime);
    return ScanResult(files: files, duration: duration);
  }

  /// 路径扫描（方案1 - 全版本兼容）
  Future<ScanResult> _scanByPaths(
    List<String> paths,
    List<String> filePatterns,
    CancellationToken? cancellationToken,
  ) async {
    final startTime = DateTime.now();
    final files = <FileItem>[];
    final pathSet = <String>{};

    // 4.1 递归扫描路径
    for (final path in paths) {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        logger.d('路径不存在: $path');
        continue;
      }

      try {
        final baseDepth = path.split('/').where((s) => s.isNotEmpty).length;

        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          // 定期检查取消状态
          if (cancellationToken?.isCancelled ?? false) {
            logger.w('路径扫描已取消');
            break;
          }
          
          if (entity is File) {
            // 计算当前文件深度
            final currentDepth = entity.path.split('/').where((s) => s.isNotEmpty).length;
            final relativeDepth = currentDepth - baseDepth;

            // 限制递归深度为5层
            if (relativeDepth > maxRecursionDepth) continue;

            final fileItem = FileItem.fromEntity(entity);

            // 过滤隐藏文件
            if (fileItem.name.startsWith('.') || fileItem.path.contains('/.')) {
              continue;
            }

            final normalizedPath = fileItem.path.toLowerCase();
            if (!pathSet.contains(normalizedPath)) {
              files.add(fileItem);
              pathSet.add(normalizedPath);
            }
          }
        }
      } catch (e) {
        logger.e('扫描路径失败 ($path): $e');
      }
    }

    // 4.2 文件名模式补充扫描
    if (filePatterns.isNotEmpty) {
      try {
        final patternFiles = await AppFileScannerChannel.scanByFileNamePattern(filePatterns);

        for (final file in patternFiles) {
          final normalizedPath = file.path.toLowerCase();
          if (!pathSet.contains(normalizedPath)) {
            files.add(file);
            pathSet.add(normalizedPath);
          }
        }
      } catch (e) {
        logger.e('文件名模式扫描失败: $e');
      }
    }

    final duration = DateTime.now().difference(startTime);
    return ScanResult(files: files, duration: duration);
  }

  /// 计算差异文件（路径扫描 - MediaStore）
  ///
  /// 这些文件只能通过路径扫描找到，MediaStore 未索引
  List<FileItem> _calculateDifference(
    List<FileItem> pathScanFiles,
    List<FileItem> mediaStoreFiles,
  ) {
    // 使用小写路径进行比较
    final mediaStorePathSet = mediaStoreFiles.map((f) => f.path.toLowerCase()).toSet();

    return pathScanFiles.where((file) {
      return !mediaStorePathSet.contains(file.path.toLowerCase());
    }).toList();
  }

  /// 合并去重（优先 MediaStore，补充路径扫描）
  List<FileItem> _mergeAndDeduplicate(
    List<FileItem> mediaStoreFiles,
    List<FileItem> pathScanFiles,
  ) {
    final pathSet = <String>{}; // 使用小写路径进行去重
    final allFiles = <FileItem>[];

    // 优先添加 MediaStore 结果（更准确，有 MIME 类型等信息）
    for (final file in mediaStoreFiles) {
      final normalizedPath = file.path.toLowerCase();
      if (!pathSet.contains(normalizedPath)) {
        allFiles.add(file);
        pathSet.add(normalizedPath);
      }
    }

    // 补充路径扫描结果
    for (final file in pathScanFiles) {
      final normalizedPath = file.path.toLowerCase();
      if (!pathSet.contains(normalizedPath)) {
        allFiles.add(file);
        pathSet.add(normalizedPath);
      }
    }

    return allFiles;
  }

  /// 批量扫描多个应用
  ///
  /// [appKeys] 应用Key列表
  /// 返回扫描结果映射表（appKey -> AppScanResult）
  Future<Map<String, AppScanResult>> scanMultipleApps(
    List<String> appKeys, {
    bool withIcon = false,
  }) async {
    final results = <String, AppScanResult>{};

    for (final appKey in appKeys) {
      try {
        results[appKey] = await scanApp(appKey: appKey, withIcon: withIcon);
      } catch (e) {
        logger.e('扫描应用失败 ($appKey): $e');
      }
    }

    return results;
  }
}

/// 扫描结果缓存（内部类）
class _ScanResultCache {
  final AppScanResult result;
  final DateTime timestamp;

  _ScanResultCache({
    required this.result,
    required this.timestamp,
  });
}
