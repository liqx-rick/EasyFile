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
  /// 
  /// 返回重复文件组列表
  Future<List<DuplicateFileGroup>> scanDuplicateFiles({
    required DuplicateFileScanConfig config,
    Function(int stage, int current, int total, String currentFile)? onProgress,
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

  /// 阶段1: 收集所有文件
  Future<List<FileItem>> _collectFiles({
    required DuplicateFileScanConfig config,
    Function(int current, int total, String currentFile)? onProgress,
  }) async {
    final allFiles = <FileItem>[];
    final minSizeInBytes = config.minSizeInKB * 1024;

    // 获取扫描路径（内部存储）
    final scanPaths = await presenter.getCommonScanPaths();
    logger.d('Scan paths: $scanPaths');

    int processedPaths = 0;
    for (final scanPath in scanPaths) {
      processedPaths++;
      onProgress?.call(processedPaths, scanPaths.length, scanPath);

      final files = await _scanPathForFiles(
        scanPath,
        minSizeInBytes,
        config.fileTypes,
      );
      allFiles.addAll(files);
    }

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
      '.txt'
    ];
    const archiveExtensions = ['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2'];

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

  /// 阶段3: 计算头部哈希并分组
  Future<Map<String, List<FileItem>>> _groupByHeaderHash(
    List<List<FileItem>> sizeGroups,
    Function(int current, int total, String currentFile)? onProgress,
  ) async {
    final headerHashGroups = <String, List<FileItem>>{};

    int processedFiles = 0;
    final totalFiles = sizeGroups.fold<int>(0, (sum, group) => sum + group.length);

    for (final group in sizeGroups) {
      for (final file in group) {
        processedFiles++;
        onProgress?.call(processedFiles, totalFiles, file.name);

        try {
          final headerHash = await _calculateHeaderHash(file.path);
          headerHashGroups.putIfAbsent(headerHash, () => []).add(file);
        } catch (e) {
          logger.w('Failed to calculate header hash for ${file.path}: $e');
        }
      }
    }

    // 只保留有多个文件的组
    headerHashGroups.removeWhere((_, files) => files.length < 2);

    return headerHashGroups;
  }

  /// 阶段4: 计算完整哈希并分组
  Future<List<DuplicateFileGroup>> _groupByFullHash(
    Map<String, List<FileItem>> headerHashGroups,
    Function(int current, int total, String currentFile)? onProgress,
  ) async {
    final duplicateGroups = <DuplicateFileGroup>[];

    int processedFiles = 0;
    final totalFiles =
        headerHashGroups.values.fold<int>(0, (sum, group) => sum + group.length);

    for (final headerGroup in headerHashGroups.values) {
      final fullHashGroups = <String, List<FileItem>>{};

      for (final file in headerGroup) {
        processedFiles++;
        onProgress?.call(processedFiles, totalFiles, file.name);

        try {
          final fullHash = await _calculateFullHash(file.path);
          fullHashGroups.putIfAbsent(fullHash, () => []).add(file);
        } catch (e) {
          logger.w('Failed to calculate full hash for ${file.path}: $e');
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
  Future<String> _calculateHeaderHash(String filePath) async {
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

  /// 计算文件完整哈希
  Future<String> _calculateFullHash(String filePath) async {
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
