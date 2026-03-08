import 'dart:io';
import 'dart:typed_data';

import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/app_scanner_config.dart';
import 'package:easyfile/core/constants/system_folders_config.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/platform/app_file_scanner_channel.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/app_file_list_cache.dart';
import 'package:easyfile/core/services/app_scan_result.dart';
import 'package:easyfile/core/services/file_count_cache.dart';
import 'package:easyfile/core/utils/cancellation_token.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 统一应用文件扫描器
///
/// 提供完整的应用文件扫描解决方案：
/// 1. 检测应用是否安装（持久化缓存）
/// 2. 获取应用图标（可选）
/// 3. MediaStore扫描（Android 11+，快速）
/// 4. 路径扫描（全版本兼容，全面）
/// 5. 结果对比与去重
/// 6. 文件数量缓存（24小时有效期）
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
  final AppFileListCache? _fileListCache;

  /// 最大递归深度（避免深层目录遍历）
  /// 优化：从5降到3，减少扫描时间（微信等应用文件通常在3层内）
  static const int maxRecursionDepth = 3;

  /// 扫描结果缓存（appKey -> ScanResultCache）
  /// ⚠️ 使用静态变量确保跨实例共享缓存
  static final Map<String, _ScanResultCache> _scanCache = {};

  /// 缓存有效期（24小时）
  static const Duration _cacheExpiration = Duration(hours: 24);

  UnifiedAppScanner(this._detectionService, {FileCountCache? fileCountCache, AppFileListCache? fileListCache})
      : _fileCountCache = fileCountCache,
        _fileListCache = fileListCache;

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
      throw ArgumentError('未知应用: $appKey，支持的应用: ${enabledApps.map((a) => a.appKey).toList()}');
    }

    logger.i('========== 开始扫描应用: ${config.appName} ($appKey) ==========');
    logger.i('  forceRefresh: $forceRefresh, useMediaStore: $useMediaStore, updateCache: $updateCache');

    // 🚀 快速缓存检查1：内存缓存（最快，有完整文件列表）
    if (!forceRefresh && _scanCache.containsKey(appKey)) {
      final cached = _scanCache[appKey]!;
      final cacheAge = DateTime.now().difference(cached.timestamp);

      if (cacheAge < _cacheExpiration) {
        logger.i('✅ 使用内存缓存结果 (缓存年龄: ${cacheAge.inMinutes}分钟, 有效期: ${_cacheExpiration.inHours}小时)');
        logger.i('   文件数量: ${cached.result.allFiles.length}');
        logger.i('========== 扫描完成: ${config.appName} ==========');
        return cached.result;
      } else {
        logger.i('⏰ 内存缓存已过期 (${cacheAge.inMinutes}分钟 > ${_cacheExpiration.inHours}小时), 执行新扫描');
        _scanCache.remove(appKey); // 清除过期缓存
      }
    } else if (forceRefresh) {
      logger.i('💪 forceRefresh=true，跳过内存缓存检查，执行完整扫描');
    } else {
      logger.i('内存缓存不存在，执行完整扫描');
    }

    // 🚀 快速缓存检查2：持久化缓存年龄判断（用于跳过不必要的扫描）
    if (!forceRefresh && _fileCountCache != null) {
      final cacheAge = await _fileCountCache!.getCacheAgeMinutes(appKey);
      if (cacheAge != null && cacheAge < 30) {
        // 缓存很新（< 30分钟），无需重新扫描，直接返回内存缓存结果
        // 注意：这里返回的是内存缓存，如果内存缓存不存在，会执行完整扫描
        logger.i('⚡ 持久化缓存很新 ($cacheAge 分钟前)，跳过扫描');
        // 但是我们没有完整的文件列表，所以还是需要扫描...
        // 实际上这个优化在应用重启后不起作用，因为内存缓存已清空
        logger.d('   (内存缓存不存在，仍需执行扫描以获取完整文件列表)');
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
    ScanResult mediaStoreResult = ScanResult(files: const [], duration: Duration.zero);

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
            logger.i(
              'MediaStore扫描: $newCount 文件 '
              '(${mediaStoreResult.duration.inMilliseconds}ms) '
              '[上次: $oldCount, 增量: ${delta > 0 ? '+' : ''}$delta]',
            );
          } else {
            logger.i(
              'MediaStore扫描: $newCount 文件 '
              '(${mediaStoreResult.duration.inMilliseconds}ms)',
            );
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
    logger.i(
      '路径扫描: ${pathScanResult.files.length} 文件 '
      '(${pathScanResult.duration.inMilliseconds}ms)',
    );

    // 步骤6: 计算差异文件
    final differenceFiles = _calculateDifference(pathScanResult.files, mediaStoreResult.files);
    logger.i('差异文件: ${differenceFiles.length} 个');

    // 步骤7: 合并去重
    final totalBeforeMerge = mediaStoreResult.files.length + pathScanResult.files.length;
    final allFiles = _mergeAndDeduplicate(mediaStoreResult.files, pathScanResult.files);
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
    _scanCache[appKey] = _ScanResultCache(result: scanResult, timestamp: DateTime.now());
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

    // 步骤8: 更新文件数量缓存（只缓存有效文件数量）
    if (updateCache && _fileCountCache != null) {
      // 过滤掉不支持的文件类型，只缓存有效文件数量
      final fileTypes = AppConfig.instance.fileTypes;
      final validFiles = <FileItem>[];
      final filteredFiles = <FileItem>[];

      for (final file in allFiles) {
        final fileName = file.name;
        final isValid = fileTypes.isImageFile(fileName) ||
            fileTypes.isVideoFile(fileName) ||
            fileTypes.isAudioFile(fileName) ||
            fileTypes.isDocumentFile(fileName) ||
            fileTypes.isArchiveFile(fileName) ||
            fileTypes.isApkFile(fileName);

        if (isValid) {
          validFiles.add(file);
        } else {
          filteredFiles.add(file);
        }
      }

      final validCount = validFiles.length;
      final filteredCount = filteredFiles.length;

      await _fileCountCache!.setFileCount(appKey, validCount);
      logger.d('文件数量缓存已更新: $appKey = $validCount 个有效文件 (过滤 $filteredCount 个不支持的文件)');

      // 💾 保存完整文件列表到持久化缓存（用于应用重启后快速加载）
      if (_fileListCache != null) {
        try {
          await _fileListCache!.setFileList(appKey, validFiles);
          logger.d('文件列表缓存已保存: $appKey = $validCount 个文件 (约 ${(validCount * 0.15).toStringAsFixed(0)} KB)');
        } catch (e) {
          logger.e('保存文件列表缓存失败: $e');
        }
      }

      // 🚫 生产环境不导出过滤文件列表（节省时间和存储空间）
      // 导出被过滤的文件路径到文件（仅用于开发调试）
      // if (filteredFiles.isNotEmpty && appKey == 'wechat') {
      //   await _exportFilteredFiles(appKey, filteredFiles);
      // }
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
  Future<Map<String, int>> getFileCountBatchFast({required List<String> appKeys}) async {
    if (_fileCountCache == null) return {};

    return await _fileCountCache!.getFileCountBatch(appKeys);
  }

  /// 快速获取缓存的扫描结果（如果存在）
  ///
  /// 从内存缓存或持久化缓存中读取之前的扫描结果，用于快速显示内容
  ///
  /// [appKey] 应用标识
  ///
  /// 返回缓存的AppScanResult，如果无有效缓存则返回null
  ///
  /// 使用场景：
  /// - 用户点击应用卡片时，先显示缓存内容（秒开）
  /// - 后台异步执行完整扫描更新数据
  /// - 缓存通过增量更新保持最新，无需强制过期
  Future<AppScanResult?> getCachedScanResult({required String appKey}) async {
    // 1. 检查内存缓存
    final memoryCache = _scanCache[appKey];
    if (memoryCache != null) {
      final age = DateTime.now().difference(memoryCache.timestamp);
      logger.d('使用内存缓存的扫描结果: $appKey (${age.inMinutes}分钟前, ${memoryCache.result.totalCount} 文件)');
      return memoryCache.result;
    }

    // 2. 检查持久化缓存（完整文件列表）- 即使过期也返回，支持后台刷新
    if (_fileListCache != null) {
      try {
        final cachedFiles = await _fileListCache!.getFileList(appKey);
        if (cachedFiles != null && cachedFiles.isNotEmpty) {
          final cacheAge = await _fileListCache!.getCacheAgeMinutes(appKey);
          logger.d('✅ 找到持久化文件列表缓存: $appKey = ${cachedFiles.length} 文件 (${cacheAge ?? 0}分钟前)');

          // 获取应用配置
          final config = await AppConfig.instance.appScanner.getAppConfig(appKey);
          if (config != null) {
            // 构建完整的扫描结果（复用缓存的文件列表）
            final result = AppScanResult(
              appName: config.appName,
              packageName: '',
              isInstalled: true,
              appIcon: null,
              mediaStoreFiles: cachedFiles,
              pathScanFiles: const [],
              differenceFiles: const [],
              allFiles: cachedFiles,
              mediaStoreDuration: Duration.zero,
              pathScanDuration: Duration.zero,
            );

            // 放入内存缓存，避免下次再读取持久化缓存
            _scanCache[appKey] = _ScanResultCache(result: result, timestamp: DateTime.now());

            return result;
          }
        }
      } catch (e) {
        logger.e('读取文件列表缓存失败: $e');
      }
    }

    // 3. 兜底：检查旧的文件数量缓存（只有数量，没有完整列表）
    final count = await getFileCountFast(appKey: appKey);
    if (count != null) {
      logger.d('找到持久化缓存的文件数量: $appKey = $count，但无完整文件列表');
      // 返回null表示需要完整扫描，调用方可以先用count显示占位内容
    }

    return null;
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

  /// 清除内存缓存
  ///
  /// 用于在清理缓存时同时清除内存中的扫描结果
  void clearMemoryCache({String? appKey}) {
    if (appKey != null) {
      _scanCache.remove(appKey);
      logger.i('已清除内存缓存: $appKey');
    } else {
      _scanCache.clear();
      logger.i('已清除所有内存缓存');
    }
  }

  /// 增量更新：从缓存中删除文件
  Future<void> updateCacheForDeletedFile(String appKey, String filePath) async {
    try {
      // 1. 更新内存缓存
      final memoryCache = _scanCache[appKey];
      if (memoryCache != null) {
        final files = memoryCache.result.allFiles.toList();
        final initialLength = files.length;
        files.removeWhere((f) => f.path == filePath);
        final removed = initialLength - files.length;

        if (removed > 0) {
          logger.d('从内存缓存删除文件: $appKey, $filePath (剩余 ${files.length} 个)');
          final updatedResult = memoryCache.result.copyWith(allFiles: files);
          _scanCache[appKey] = _ScanResultCache(result: updatedResult, timestamp: memoryCache.timestamp);
        }
      }

      // 2. 更新持久化缓存
      if (_fileListCache != null) {
        final cachedFiles = await _fileListCache!.getFileList(appKey);
        if (cachedFiles != null) {
          final updatedFiles = cachedFiles.where((f) => f.path != filePath).toList();
          if (updatedFiles.length < cachedFiles.length) {
            await _fileListCache!.setFileList(appKey, updatedFiles);
            logger.d('从持久化缓存删除文件: $appKey, $filePath (剩余 ${updatedFiles.length} 个)');
          }
        }
      }

      // 3. 更新文件数量缓存
      if (_fileCountCache != null) {
        final currentCount = await _fileCountCache!.getFileCount(appKey);
        if (currentCount != null && currentCount > 0) {
          await _fileCountCache!.setFileCount(appKey, currentCount - 1);
        }
      }
    } catch (e) {
      logger.e('更新删除文件缓存失败: $e');
    }
  }

  /// 增量更新：更新文件（重命名/移动）
  Future<void> updateCacheForUpdatedFile(String appKey, String oldPath, FileItem newFile) async {
    try {
      // 1. 更新内存缓存
      final memoryCache = _scanCache[appKey];
      if (memoryCache != null) {
        final files = memoryCache.result.allFiles.toList();
        final index = files.indexWhere((f) => f.path == oldPath);
        if (index != -1) {
          files[index] = newFile;
          logger.d('更新内存缓存文件: $appKey, $oldPath -> ${newFile.path}');
          final updatedResult = memoryCache.result.copyWith(allFiles: files);
          _scanCache[appKey] = _ScanResultCache(result: updatedResult, timestamp: memoryCache.timestamp);
        }
      }

      // 2. 更新持久化缓存
      if (_fileListCache != null) {
        final cachedFiles = await _fileListCache!.getFileList(appKey);
        if (cachedFiles != null) {
          final updatedFiles = cachedFiles.toList();
          final index = updatedFiles.indexWhere((f) => f.path == oldPath);
          if (index != -1) {
            updatedFiles[index] = newFile;
            await _fileListCache!.setFileList(appKey, updatedFiles);
            logger.d('更新持久化缓存文件: $appKey, $oldPath -> ${newFile.path}');
          }
        }
      }
    } catch (e) {
      logger.e('更新文件缓存失败: $e');
    }
  }

  /// 增量更新：添加文件
  Future<void> updateCacheForAddedFile(String appKey, FileItem newFile) async {
    try {
      // 1. 更新内存缓存
      final memoryCache = _scanCache[appKey];
      if (memoryCache != null) {
        final files = memoryCache.result.allFiles.toList();
        if (!files.any((f) => f.path == newFile.path)) {
          files.add(newFile);
          logger.d('添加文件到内存缓存: $appKey, ${newFile.path} (共 ${files.length} 个)');
          final updatedResult = memoryCache.result.copyWith(allFiles: files);
          _scanCache[appKey] = _ScanResultCache(result: updatedResult, timestamp: memoryCache.timestamp);
        }
      }

      // 2. 更新持久化缓存
      if (_fileListCache != null) {
        final cachedFiles = await _fileListCache!.getFileList(appKey);
        if (cachedFiles != null) {
          if (!cachedFiles.any((f) => f.path == newFile.path)) {
            final updatedFiles = [...cachedFiles, newFile];
            await _fileListCache!.setFileList(appKey, updatedFiles);
            logger.d('添加文件到持久化缓存: $appKey, ${newFile.path} (共 ${updatedFiles.length} 个)');
          }
        }
      }

      // 3. 更新文件数量缓存
      if (_fileCountCache != null) {
        final currentCount = await _fileCountCache!.getFileCount(appKey);
        if (currentCount != null) {
          await _fileCountCache!.setFileCount(appKey, currentCount + 1);
        }
      }
    } catch (e) {
      logger.e('添加文件缓存失败: $e');
    }
  }

  /// 检查缓存年龄并决定是否需要后台刷新
  Future<bool> shouldRefreshCache(String appKey) async {
    if (_fileListCache == null) return true;

    final cacheAge = await _fileListCache!.getCacheAgeMinutes(appKey);
    if (cacheAge == null) return true;

    // 缓存超过30分钟，建议后台刷新
    return cacheAge > 30;
  }

  /// 构建扫描路径
  ///
  /// 结合基础路径、文件夹关键字和附加路径
  Future<List<String>> _buildScanPaths(AppConfigData config, List<String> additionalPaths) async {
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

        await for (final entity in dir.list(recursive: true, followLinks: false)) {
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
  List<FileItem> _calculateDifference(List<FileItem> pathScanFiles, List<FileItem> mediaStoreFiles) {
    // 使用小写路径进行比较
    final mediaStorePathSet = mediaStoreFiles.map((f) => f.path.toLowerCase()).toSet();

    return pathScanFiles.where((file) {
      return !mediaStorePathSet.contains(file.path.toLowerCase());
    }).toList();
  }

  /// 合并去重（优先 MediaStore，补充路径扫描）
  List<FileItem> _mergeAndDeduplicate(List<FileItem> mediaStoreFiles, List<FileItem> pathScanFiles) {
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

  /// 导出被过滤的文件路径到文件（用于分析）
  // ignore: unused_element
  Future<void> _exportFilteredFiles(String appKey, List<FileItem> filteredFiles) async {
    try {
      final timestamp = DateTime.now().toString().replaceAll(':', '-').replaceAll(' ', '_');
      final filePath = '/storage/emulated/0/Documents/filtered_files_${appKey}_$timestamp.txt';
      final file = File(filePath);

      // 创建目录（如果不存在）
      await file.parent.create(recursive: true);

      // 统计文件扩展名分布
      final Map<String, int> extensionStats = {};
      final List<String> lines = [];

      lines.add('========== 被过滤的文件列表 ($appKey) ==========');
      lines.add('总数: ${filteredFiles.length}');
      lines.add('导出时间: ${DateTime.now()}');
      lines.add('');

      for (final file in filteredFiles) {
        lines.add(file.path);

        // 统计扩展名
        final ext = file.path.toLowerCase().split('.').last;
        extensionStats[ext] = (extensionStats[ext] ?? 0) + 1;
      }

      // 添加统计信息
      lines.add('');
      lines.add('========== 扩展名统计 ==========');
      final sortedExtensions = extensionStats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sortedExtensions) {
        lines.add('${entry.key}: ${entry.value} 个文件');
      }

      await file.writeAsString(lines.join('\n'));
      logger.i('📄 已导出被过滤的文件列表: $filePath (${filteredFiles.length} 个文件)');
    } catch (e) {
      logger.e('导出被过滤的文件列表失败: $e');
    }
  }

  /// 批量扫描多个应用
  ///
  /// [appKeys] 应用Key列表
  /// 返回扫描结果映射表（appKey -> AppScanResult）
  Future<Map<String, AppScanResult>> scanMultipleApps(List<String> appKeys, {bool withIcon = false}) async {
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

  _ScanResultCache({required this.result, required this.timestamp});
}
