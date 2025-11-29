import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/data/models/duplicate_file_group.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';

/// 重复文件检测服务
/// 
/// 使用三阶段检测算法（大小分组 → 头部哈希 → 完整哈希），
/// 提供高效的重复文件检测功能
/// 
/// 特性：
/// - ✅ 三阶段检测（大小分组 → 头部哈希 → 完整哈希）
/// - ✅ 智能跳过（系统目录、小文件、隐藏文件）
/// - ✅ 异步扫描（使用compute避免阻塞UI）
/// - ✅ 进度回调（实时反馈扫描进度）
class DuplicateFileService {
  final FilePresenter presenter;

  DuplicateFileService(this.presenter);

  /// 扫描重复文件
  /// 
  /// [config] 扫描配置
  /// [onProgress] 进度回调 (阶段, 当前进度, 总数, 当前处理的文件)
  /// [onFilesCollected] 文件收集完成回调（用于缓存管理）
  /// 
  /// 返回重复文件组列表
  Future<List<DuplicateFileGroup>> scanDuplicateFiles({
    required DuplicateFileScanConfig config,
    Function(int stage, int current, int total, String currentFile)? onProgress,
    Function(List<FileItem>)? onFilesCollected,
  }) async {
    logger.i(
      'Starting duplicate file scan: ${config.description}',
    );

    try {
      // 阶段1: 收集所有文件
      final allFiles = await _collectFiles(
        config: config,
        onProgress: (current, total, file) {
          onProgress?.call(1, current, total, file);
        },
        onFilesCollected: onFilesCollected,
      );

      if (allFiles.isEmpty) {
        logger.i('No files found for scanning');
        return [];
      }

      logger.i('Stage 1 completed: ${allFiles.length} files collected');

      // 阶段2: 按大小分组（快速预筛）
      final sizeGroups = _groupBySize(allFiles);
      logger.i('Stage 2: ${sizeGroups.length} size groups');

      // 只处理有多个文件的组（可能重复）
      final suspiciousGroups = sizeGroups.values
          .where((files) => files.length >= 2)
          .toList();

      if (suspiciousGroups.isEmpty) {
        logger.i('No suspicious size groups found');
        return [];
      }

      final totalSuspiciousFiles = suspiciousGroups
          .fold<int>(0, (sum, group) => sum + group.length);
      logger.i(
        'Stage 2 completed: ${suspiciousGroups.length} groups with $totalSuspiciousFiles files',
      );

      // 阶段3: 计算头部哈希（只处理大小相同的文件）
      final headerHashGroups = await _groupByHeaderHash(
        suspiciousGroups,
        (current, total, file) {
          onProgress?.call(2, current, total, file);
        },
      );

      logger.i('Stage 3 completed: ${headerHashGroups.length} header hash groups');

      // 阶段4: 计算完整哈希（只处理头部哈希相同的文件）
      final duplicateGroups = await _groupByFullHash(
        headerHashGroups,
        (current, total, file) {
          onProgress?.call(3, current, total, file);
        },
      );

      logger.i(
        'Duplicate file scan completed: found ${duplicateGroups.length} duplicate groups',
      );

      return duplicateGroups;
    } catch (e, stackTrace) {
      logger.e('Error scanning duplicate files: $e\n$stackTrace');
      rethrow;
    }
  }

  /// 阶段1: 收集所有文件（✅ 优化：并行扫描多个根目录）
  Future<List<FileItem>> _collectFiles({
    required DuplicateFileScanConfig config,
    Function(int current, int total, String currentFile)? onProgress,
    Function(List<FileItem>)? onFilesCollected, // 📊 新增：文件收集完成回调
  }) async {
    final minSizeInBytes = config.minSizeInKB * 1024;

    // 获取扫描路径（动态发现）
    final scanPaths = await presenter.getCommonScanPaths();
    
    logger.d('Scan paths: ${scanPaths.length} paths');
    debugPrint('\n[文件收集] 📁 使用的扫描路径 (${scanPaths.length} 个):');
    for (var i = 0; i < scanPaths.length; i++) {
      debugPrint('  [扫描路径 ${i + 1}] ${scanPaths[i]}');
    }

    // ✅ 优化1: 并行扫描多个根目录，提升速度
    final scanFutures = scanPaths.map((scanPath) {
      return _scanPathForFiles(
        scanPath,
        minSizeInBytes,
        config.fileTypes,
      );
    }).toList();
    
    // 批量等待所有扫描完成，并定期更新进度
    final allResults = <List<FileItem>>[];
    for (int i = 0; i < scanFutures.length; i++) {
      final result = await scanFutures[i];
      allResults.add(result);
      
      // 更新进度（每完成一个路径）
      onProgress?.call(i + 1, scanPaths.length, scanPaths[i]);
    }
    
    // 合并所有结果
    final allFiles = allResults.expand((files) => files).toList();
    logger.d('Collected ${allFiles.length} files from ${scanPaths.length} paths');

    // 📊 调用回调，通知文件收集完成
    onFilesCollected?.call(allFiles);

    return allFiles;
  }

  /// 扫描指定路径的文件
  Future<List<FileItem>> _scanPathForFiles(
    String pathStr,
    int minSizeInBytes,
    Set<FileTypeFilter> fileTypes,
  ) async {
    final files = <FileItem>[];

    try {
      final directory = Directory(pathStr);
      if (!directory.existsSync()) {
        return files;
      }

      await _scanDirectoryRecursive(
        directory,
        files,
        minSizeInBytes,
        fileTypes,
        0,
        15, // ✅ 优化: 最大深度从10增加到15
      );
    } catch (e) {
      logger.w('Error scanning path $pathStr: $e');
    }

    return files;
  }

  /// 递归扫描目录
  Future<void> _scanDirectoryRecursive(
    Directory directory,
    List<FileItem> files,
    int minSizeInBytes,
    Set<FileTypeFilter> fileTypes,
    int currentDepth,
    int maxDepth,
  ) async {
    if (currentDepth >= maxDepth) {
      return;
    }

    try {
      await for (final entity in directory.list(followLinks: false)) {
        try {
          final name = path.basename(entity.path);

          // 跳过隐藏文件
          if (name.startsWith('.')) continue;

          if (entity is File) {
            final stat = entity.statSync();
            
            // 🔧 跳过临时下载文件
            final fileName = path.basename(entity.path).toLowerCase();
            if (fileName.endsWith('.downloading') || 
                fileName.endsWith('.download') ||
                fileName.endsWith('.tmp') ||
                fileName.endsWith('.temp') ||
                fileName.contains('.p.downloading')) {
              continue;
            }

            // 检查文件大小
            if (stat.size < minSizeInBytes) continue;

            // 检查文件类型
            if (!_matchesFileType(entity.path, fileTypes)) continue;

            final fileItem = FileItem.fromEntity(entity);
            files.add(fileItem);
          } else if (entity is Directory) {
            // 跳过排除的文件夹
            if (FilePresenter.excludedFolders.contains(name)) {
              // Android目录特殊处理
              if (name == 'Android') {
                final dataDir = Directory(path.join(entity.path, 'data'));
                if (dataDir.existsSync()) {
                  await _scanDirectoryRecursive(
                    dataDir,
                    files,
                    minSizeInBytes,
                    fileTypes,
                    currentDepth + 1,
                    maxDepth + 5, // ✅ 优化: Android/data额外增加5层深度 (总共20层)
                  );
                }
              }
              continue;
            }

            await _scanDirectoryRecursive(
              entity,
              files,
              minSizeInBytes,
              fileTypes,
              currentDepth + 1,
              maxDepth,
            );
          }
        } catch (e) {
          // 忽略单个文件的错误
        }
      }
    } catch (e) {
      logger.w('Error listing directory ${directory.path}: $e');
    }
  }

  /// 判断文件是否匹配指定的文件类型
  bool _matchesFileType(String filePath, Set<FileTypeFilter> fileTypes) {
    // 🔧 如果没有指定文件类型（所有类型），接受所有文件
    if (fileTypes.isEmpty) return true;
    
    final ext = path.extension(filePath).toLowerCase();

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
      '.opus',
      '.amr'
    ];
    const imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.heic',
      '.heif',
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
      '.txt',
      '.html',   // 网页文件
      '.htm',
      '.md',     // Markdown
      '.rtf',    // 富文本
      '.csv',    // 数据表格
      '.json',   // 配置文件
      '.xml',    // 配置文件
    ];
    const archiveExtensions = [
      '.zip',
      '.rar',
      '.7z',
      '.tar',
      '.gz',
      '.bz2',
      '.apk',    // Android 安装包（实际是 zip 格式）
      '.xz',     // 现代压缩格式
      '.zst',    // Zstandard 压缩
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

  /// 阶段2: 按大小分组
  Map<int, List<FileItem>> _groupBySize(List<FileItem> files) {
    final sizeGroups = <int, List<FileItem>>{};

    for (final file in files) {
      sizeGroups.putIfAbsent(file.size, () => []).add(file);
    }

    return sizeGroups;
  }

  /// 阶段3: 计算头部哈希并分组（✅ 优化：批量并行计算）
  Future<Map<String, List<FileItem>>> _groupByHeaderHash(
    List<List<FileItem>> sizeGroups,
    Function(int current, int total, String currentFile)? onProgress,
  ) async {
    final headerHashGroups = <String, List<FileItem>>{};

    int processedFiles = 0;
    final totalFiles = sizeGroups.fold<int>(0, (sum, group) => sum + group.length);

    // ✅ 优化2: 批量并行计算哈希，每批最多50个文件并发
    const batchSize = 50;
    
    for (final group in sizeGroups) {
      // 将每组文件分成小批次
      for (int i = 0; i < group.length; i += batchSize) {
        final batch = group.skip(i).take(batchSize).toList();
        
        // 并行计算这一批文件的哈希
        final hashFutures = batch.map((file) async {
          try {
            final hash = await calculateHeaderHash(file.path);
            return (file: file, hash: hash, error: null);
          } catch (e) {
            logger.w('Failed to calculate header hash for ${file.path}: $e');
            return (file: file, hash: null, error: e.toString());
          }
        }).toList();
        
        // 等待这一批完成
        final results = await Future.wait(hashFutures);
        
        // 更新结果和进度
        for (final result in results) {
          processedFiles++;
          
          // 降低进度更新频率，避免UI卡顿
          if (processedFiles % 10 == 0 || processedFiles == totalFiles) {
            onProgress?.call(processedFiles, totalFiles, result.file.name);
          }
          
          if (result.hash != null) {
            headerHashGroups.putIfAbsent(result.hash!, () => []).add(result.file);
          }
        }
      }
    }

    // 只保留有多个文件的组
    headerHashGroups.removeWhere((_, files) => files.length < 2);

    return headerHashGroups;
  }

  /// 阶段4: 计算完整哈希并分组（✅ 优化：批量并行计算）
  Future<List<DuplicateFileGroup>> _groupByFullHash(
    Map<String, List<FileItem>> headerHashGroups,
    Function(int current, int total, String currentFile)? onProgress,
  ) async {
    final duplicateGroups = <DuplicateFileGroup>[];

    int processedFiles = 0;
    final totalFiles =
        headerHashGroups.values.fold<int>(0, (sum, group) => sum + group.length);

    // ✅ 优化3: 批量并行计算完整哈希，每批最多30个文件并发（完整哈希更耗时）
    const batchSize = 30;
    
    for (final headerGroup in headerHashGroups.values) {
      final fullHashGroups = <String, List<FileItem>>{};

      // 将文件分成小批次
      for (int i = 0; i < headerGroup.length; i += batchSize) {
        final batch = headerGroup.skip(i).take(batchSize).toList();
        
        // 并行计算这一批文件的完整哈希
        final hashFutures = batch.map((file) async {
          try {
            final hash = await calculateFullHash(file.path);
            return (file: file, hash: hash, error: null);
          } catch (e) {
            logger.w('Failed to calculate full hash for ${file.path}: $e');
            return (file: file, hash: null, error: e.toString());
          }
        }).toList();
        
        // 等待这一批完成
        final results = await Future.wait(hashFutures);
        
        // 更新结果和进度
        for (final result in results) {
          processedFiles++;
          
          // 降低进度更新频率，避免UI卡顿
          if (processedFiles % 10 == 0 || processedFiles == totalFiles) {
            onProgress?.call(processedFiles, totalFiles, result.file.name);
          }
          
          if (result.hash != null) {
            fullHashGroups.putIfAbsent(result.hash!, () => []).add(result.file);
          }
        }
      }

      // 将有多个文件的组转换为DuplicateFileGroup
      for (final entry in fullHashGroups.entries) {
        if (entry.value.length >= 2) {
          final group = DuplicateFileGroup(
            groupId: entry.key,
            files: entry.value,
            fileSize: entry.value.first.size,
          );
          duplicateGroups.add(group);
        }
      }
    }

    return duplicateGroups;
  }

  /// 计算文件头部哈希（前8KB）
  /// 计算文件头部哈希（8KB）
  Future<String> calculateHeaderHash(String filePath) async {
    const headerSize = 8 * 1024; // 8KB

    return await compute(_calculateHeaderHashInIsolate, {
      'filePath': filePath,
      'headerSize': headerSize,
    });
  }

  /// 在Isolate中计算头部哈希
  static Future<String> _calculateHeaderHashInIsolate(
      Map<String, dynamic> params) async {
    final filePath = params['filePath'] as String;
    final headerSize = params['headerSize'] as int;

    final file = File(filePath);
    final bytes = await file.openRead(0, headerSize).toList();
    final allBytes = bytes.expand((chunk) => chunk).toList();

    final digest = md5.convert(allBytes);
    return digest.toString();
  }

  /// 计算文件完整哈希（MD5）
  Future<String> calculateFullHash(String filePath) async {
    return await compute(_calculateFullHashInIsolate, filePath);
  }

  /// 在Isolate中计算完整哈希
  static Future<String> _calculateFullHashInIsolate(String filePath) async {
    final file = File(filePath);
    final stream = file.openRead();
    final digest = await md5.bind(stream).first;
    return digest.toString();
  }
}


