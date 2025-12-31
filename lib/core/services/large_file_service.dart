import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';

/// 大文件扫描服务
///
/// 使用智能深度策略和大小剪枝优化，提供高效的大文件查找功能。
///
/// 特性：
/// - ✅ 智能深度：根据路径类型动态调整扫描深度
/// - ✅ 大小剪枝：跳过小目录，延长大目录深度
/// - ✅ 性能优化：异步扫描，避免阻塞UI
/// - ✅ 结果排序：按文件大小降序排列
class LargeFileService {
  final FilePresenter presenter;

  LargeFileService(this.presenter);

  /// 扫描大文件
  ///
  /// [minSizeInMB] 最小文件大小（MB），默认100MB（与 FileScanConfig.largeFileThreshold 一致）
  /// [maxResults] 最大结果数量，默认300个（与 FileScanConfig.largeFileMaxResults 一致），0表示不限制
  /// [useSizePruning] 是否启用大小剪枝优化，默认true
  /// [fileTypes] 文件类型过滤器，为null时不过滤
  ///
  /// 返回按大小降序排列的文件列表
  Future<List<FileItem>> scanLargeFiles({
    int minSizeInMB = 100,
    int maxResults = 300,
    bool useSizePruning = true,
    Set<FileTypeFilter>? fileTypes,
  }) async {
    logger.i(
      'Starting large file scan: minSize=${minSizeInMB}MB, maxResults=$maxResults, pruning=$useSizePruning, fileTypes=$fileTypes',
    );

    try {
      // 1. 获取扫描路径（复用Presenter）
      final scanPaths = await presenter.getCommonScanPaths();
      logger.d('Scan paths: $scanPaths');

      // 2. 扫描所有路径，收集大文件
      final largeFiles = <FileItem>[];
      final minSizeInBytes = minSizeInMB * 1024 * 1024;

      for (final scanPath in scanPaths) {
        // 智能深度：根据路径选择深度
        final depth = _getDepthForPath(scanPath);
        logger
            .d('Scanning $scanPath with depth $depth, pruning=$useSizePruning');

        final files = await _scanLargeFilesInPath(
          scanPath,
          minSizeInBytes,
          depth,
          useSizePruning: useSizePruning,
          fileTypes: fileTypes,
        );
        largeFiles.addAll(files);
        logger.d(
            'Found ${files.length} large files in $scanPath, total so far: ${largeFiles.length}');
      }

      // 3. 去重（同一文件可能在多个路径）
      final uniqueFiles = <String, FileItem>{};
      for (final file in largeFiles) {
        uniqueFiles[file.path] = file;
      }

      // 4. 按大小排序（降序）
      final result = uniqueFiles.values.toList();
      result.sort((a, b) => b.size.compareTo(a.size));

      // 5. 限制结果数量（防止过多结果导致UI卡顿）
      final limitedResult = maxResults > 0 && result.length > maxResults
          ? result.sublist(0, maxResults)
          : result;

      logger.i(
        'Large file scan completed: found ${result.length} files, returning ${limitedResult.length} files (limit: $maxResults)',
      );
      return limitedResult;
    } catch (e, stackTrace) {
      logger.e('Error scanning large files: $e\n$stackTrace');
      rethrow;
    }
  }

  /// 智能深度策略：根据路径类型返回合适的扫描深度
  ///
  /// 不同目录可能有不同的文件组织深度：
  /// - 用户主目录：8层（常见文件区域）
  /// - 应用数据/下载：15层（可能更深）
  /// - WhatsApp/Telegram：15层（媒体文件较深）
  int _getDepthForPath(String pathStr) {
    const defaultDepth = 8;
    const extendedDepth = 15;

    // Android 应用数据目录
    if (pathStr.contains('/Android/data/') ||
        pathStr.contains('/Android/obb/')) {
      return extendedDepth;
    }

    // 社交应用媒体目录
    if (pathStr.contains('/WhatsApp/') || pathStr.contains('/Telegram/')) {
      return extendedDepth;
    }

    // 下载目录（用户可能创建子文件夹分类）
    if (pathStr.contains('/Download') || pathStr.contains('/Downloads')) {
      return extendedDepth;
    }

    // DCIM相机目录
    if (pathStr.contains('/DCIM/')) {
      return extendedDepth;
    }

    return defaultDepth;
  }

  /// 在指定路径中扫描大文件
  Future<List<FileItem>> _scanLargeFilesInPath(
    String pathStr,
    int minSizeInBytes,
    int maxDepth, {
    bool useSizePruning = true,
    Set<FileTypeFilter>? fileTypes,
  }) async {
    final files = <FileItem>[];

    try {
      final directory = Directory(pathStr);
      if (!directory.existsSync()) {
        logger.d('Directory does not exist: $pathStr');
        return files;
      }

      // 特殊处理：如果是根目录，先扫描第一层的文件（不递归）
      final isRootPath = pathStr == '/storage/emulated/0' ||
          pathStr == Platform.environment['USERPROFILE'] ||
          pathStr == Platform.environment['HOME'];

      if (isRootPath) {
        logger.d('扫描根目录第一层文件: $pathStr');
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is File) {
            try {
              final stat = await entity.stat();
              if (stat.size >= minSizeInBytes) {
                // 文件类型过滤
                if (fileTypes != null && fileTypes.isNotEmpty) {
                  if (!_matchesFileType(entity.path, fileTypes)) continue;
                }

                final fileItem = FileItem(
                  path: entity.path,
                  name: path.basename(entity.path),
                  isDirectory: false,
                  size: stat.size,
                  modified: stat.modified,
                );
                files.add(fileItem);
                logger.d('发现根目录大文件: ${fileItem.name} (${fileItem.size} bytes)');
              }
            } catch (e) {
              logger.w('错误检查根目录文件: ${entity.path}, 错误: $e');
            }
          }
        }
        // 根目录只扫描第一层，不递归到子文件夹
        return files;
      }

      // 普通目录：递归扫描
      await _scanDirectoryWithPruning(
        directory,
        minSizeInBytes,
        files,
        0,
        maxDepth,
        useSizePruning: useSizePruning,
        fileTypes: fileTypes,
      );
    } catch (e) {
      logger.w('Error scanning large files in $pathStr: $e');
    }

    return files;
  }

  /// 递归扫描目录查找大文件（支持智能剪枝）
  ///
  /// 剪枝策略：
  /// - 跳过隐藏文件/文件夹
  /// - 跳过系统排除的文件夹
  /// - 快速估算目录大小，跳过小目录
  /// - 对大目录自动延长深度限制
  Future<void> _scanDirectoryWithPruning(
    Directory directory,
    int minSizeInBytes,
    List<FileItem> files,
    int currentDepth,
    int maxDepth, {
    bool useSizePruning = true,
    Set<FileTypeFilter>? fileTypes,
  }) async {
    if (currentDepth >= maxDepth) {
      logger.d('Reached max depth $maxDepth at: ${directory.path}');
      return;
    }

    try {
      // 使用异步list()，避免阻塞UI
      await for (final entity in directory.list(followLinks: false)) {
        try {
          final name = path.basename(entity.path);

          // 跳过隐藏文件/文件夹
          if (name.startsWith('.')) continue;

          if (entity is File) {
            // 检查文件大小
            final stat = entity.statSync();
            if (stat.size >= minSizeInBytes) {
              // 根据文件类型过滤
              if (fileTypes == null ||
                  _matchesFileType(entity.path, fileTypes)) {
                final fileItem = FileItem.fromEntity(entity);
                files.add(fileItem);
                logger.d(
                    '✅ Found large file at depth $currentDepth: ${fileItem.name} (${stat.size ~/ (1024 * 1024)}MB) in ${path.dirname(entity.path)}');
              } else {
                logger.d(
                    '⏭️ Skipping file (type not matched) at depth $currentDepth: $name (${stat.size ~/ (1024 * 1024)}MB)');
              }
            }
          } else if (entity is Directory) {
            // 跳过排除的文件夹（但Android目录需要特殊处理）
            if (FilePresenter.excludedFolders.contains(name)) {
              // Android目录特殊处理：只扫描data和obb子目录（游戏和应用数据）
              if (name == 'Android') {
                final dataDir = Directory(path.join(entity.path, 'data'));
                final obbDir = Directory(path.join(entity.path, 'obb'));

                if (dataDir.existsSync()) {
                  await _scanDirectoryWithPruning(
                    dataDir,
                    minSizeInBytes,
                    files,
                    currentDepth + 1,
                    maxDepth + 5, // Android/data 可能很深，额外增加深度
                    useSizePruning: useSizePruning,
                    fileTypes: fileTypes,
                  );
                }

                if (obbDir.existsSync()) {
                  await _scanDirectoryWithPruning(
                    obbDir,
                    minSizeInBytes,
                    files,
                    currentDepth + 1,
                    maxDepth + 5, // Android/obb 游戏数据可能很深
                    useSizePruning: useSizePruning,
                    fileTypes: fileTypes,
                  );
                }
              }
              continue;
            }

            if (useSizePruning) {
              // ⭐ 大小剪枝优化
              final estimatedSize = await _quickEstimateDirSize(entity);

              // 目录太小，直接跳过（不可能有大文件）
              if (estimatedSize < minSizeInBytes) {
                logger.d(
                    '🚫 Pruning small directory at depth $currentDepth: $name (${estimatedSize ~/ 1024}KB < ${minSizeInBytes ~/ 1024}KB threshold)');
                continue;
              }

              // 目录很大（10倍阈值），值得深入扫描，延长深度
              final extendedDepth =
                  estimatedSize > minSizeInBytes * 10 ? maxDepth + 3 : maxDepth;

              if (estimatedSize > minSizeInBytes * 10) {
                logger.d(
                    '📂 Large directory at depth $currentDepth: $name (${estimatedSize ~/ (1024 * 1024)}MB), extending depth to $extendedDepth');
              }

              await _scanDirectoryWithPruning(
                entity,
                minSizeInBytes,
                files,
                currentDepth + 1,
                extendedDepth,
                useSizePruning: true,
                fileTypes: fileTypes,
              );
            } else {
              // 不使用剪枝，正常递归
              await _scanDirectoryWithPruning(
                entity,
                minSizeInBytes,
                files,
                currentDepth + 1,
                maxDepth,
                useSizePruning: false,
                fileTypes: fileTypes,
              );
            }
          }
        } catch (e) {
          // 忽略单个文件的错误，继续扫描
          logger.d('Error processing entity ${entity.path}: $e');
        }
      }
    } catch (e) {
      logger.w('Error listing directory ${directory.path}: $e');
    }
  }

  /// 判断文件是否匹配指定的文件类型
  bool _matchesFileType(String filePath, Set<FileTypeFilter> fileTypes) {
    final ext = path.extension(filePath).toLowerCase();

    // 定义每种类型的扩展名
    const videoExtensions = [
      '.mp4',
      '.avi',
      '.mkv',
      '.mov',
      '.wmv',
      '.flv',
      '.webm',
      '.m4v',
      '.3gp'
    ];
    const audioExtensions = [
      '.mp3',
      '.m4a',
      '.wav',
      '.flac',
      '.aac',
      '.ogg',
      '.wma',
      '.opus'
    ];
    const imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.heic',
      '.svg'
    ];
    const documentExtensions = [
      '.pdf',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.ppt',
      '.pptx',
      '.txt'
    ];
    const archiveExtensions = [
      '.zip',
      '.rar',
      '.7z',
      '.tar',
      '.gz',
      '.bz2',
      '.xz'
    ];

    for (final type in fileTypes) {
      switch (type) {
        case FileTypeFilter.video:
          if (videoExtensions.contains(ext)) return true;
          break;
        case FileTypeFilter.audio:
          if (audioExtensions.contains(ext)) return true;
          break;
        case FileTypeFilter.image:
          if (imageExtensions.contains(ext)) return true;
          break;
        case FileTypeFilter.document:
          if (documentExtensions.contains(ext)) return true;
          break;
        case FileTypeFilter.archive:
          if (archiveExtensions.contains(ext)) return true;
          break;
        case FileTypeFilter.other:
          // 其他类型：不在上述任何类型中的文件
          if (!videoExtensions.contains(ext) &&
              !audioExtensions.contains(ext) &&
              !imageExtensions.contains(ext) &&
              !documentExtensions.contains(ext) &&
              !archiveExtensions.contains(ext)) {
            return true;
          }
          break;
      }
    }

    return false;
  }

  /// 快速估算目录大小（采样策略）
  ///
  /// 检查前20个文件并计算子目录数量，更准确地估算。
  /// 使用动态估算系数来推测总大小。
  ///
  /// 返回估算的目录大小（字节）
  Future<int> _quickEstimateDirSize(Directory dir) async {
    int totalSize = 0;
    int fileCount = 0;
    int dirCount = 0;
    const maxSamples = 20;

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          try {
            totalSize += entity.statSync().size;
            fileCount++;
            if (fileCount >= maxSamples) break; // 采样前20个文件
          } catch (e) {
            // 忽略单个文件错误
          }
        } else if (entity is Directory) {
          dirCount++;
          if (fileCount >= maxSamples) break;
        }
      }
    } catch (e) {
      // 忽略目录访问错误
    }

    // 动态估算系数：如果有很多子目录，使用更大的系数
    final estimateFactor = dirCount > 5 ? 10 : (dirCount > 2 ? 5 : 3);
    return fileCount > 0 ? totalSize * estimateFactor : 0;
  }
}
