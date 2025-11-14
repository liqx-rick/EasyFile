import 'dart:io';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/folder_stats.dart';

/// 文件夹分析服务
///
/// 提供文件夹统计分析功能
class FolderAnalyzer {
  /// 分析文件夹统计信息
  ///
  /// [path] 文件夹路径
  /// [maxDepth] 最大扫描深度（默认1，只扫描一级）
  /// [includeHidden] 是否包含隐藏文件（默认false）
  Future<FolderStats> analyzeFolderStats(
    String path, {
    int maxDepth = 1,
    bool includeHidden = false,
  }) async {
    try {
      final dir = Directory(path);

      if (!dir.existsSync()) {
        logger.w('Folder does not exist: $path');
        return FolderStats.empty();
      }

      int totalFiles = 0;
      int totalFolders = 0;
      double totalSizeBytes = 0;
      final fileTypeCounts = <FileType, int>{};
      DateTime? latestModified;

      await _scanDirectory(
        dir,
        currentDepth: 0,
        maxDepth: maxDepth,
        includeHidden: includeHidden,
        onFile: (file) {
          totalFiles++;

          // 统计文件大小
          try {
            totalSizeBytes += file.lengthSync();
          } catch (e) {
            logger.w('Failed to get file size: ${file.path}');
          }

          // 统计文件类型
          final fileType = _detectFileType(file.path);
          fileTypeCounts[fileType] = (fileTypeCounts[fileType] ?? 0) + 1;

          // 记录最新修改时间
          try {
            final modified = file.lastModifiedSync();
            if (latestModified == null || modified.isAfter(latestModified!)) {
              latestModified = modified;
            }
          } catch (e) {
            logger.w('Failed to get modification time: ${file.path}');
          }
        },
        onDirectory: (directory) {
          totalFolders++;

          // 记录目录的最新修改时间
          try {
            final modified = directory.statSync().modified;
            if (latestModified == null || modified.isAfter(latestModified!)) {
              latestModified = modified;
            }
          } catch (e) {
            logger.w(
              'Failed to get directory modification time: ${directory.path}',
            );
          }
        },
      );

      return FolderStats(
        totalFiles: totalFiles,
        totalFolders: totalFolders,
        fileTypeCounts: fileTypeCounts,
        totalSizeMB: totalSizeBytes / (1024 * 1024), // 转换为MB
        lastModified: latestModified ?? DateTime.now(),
      );
    } catch (e, stackTrace) {
      logger.e('Error analyzing folder stats: $e\nStackTrace: $stackTrace');
      return FolderStats.empty();
    }
  }

  /// 递归扫描目录
  Future<void> _scanDirectory(
    Directory dir, {
    required int currentDepth,
    required int maxDepth,
    required bool includeHidden,
    required void Function(File) onFile,
    required void Function(Directory) onDirectory,
  }) async {
    if (currentDepth > maxDepth) return;

    try {
      final entities = dir.listSync(followLinks: false);

      for (final entity in entities) {
        // 跳过隐藏文件/文件夹
        if (!includeHidden && _isHidden(entity.path)) {
          continue;
        }

        if (entity is File) {
          onFile(entity);
        } else if (entity is Directory) {
          onDirectory(entity);

          // 递归扫描子目录
          if (currentDepth < maxDepth) {
            await _scanDirectory(
              entity,
              currentDepth: currentDepth + 1,
              maxDepth: maxDepth,
              includeHidden: includeHidden,
              onFile: onFile,
              onDirectory: onDirectory,
            );
          }
        }
      }
    } catch (e) {
      logger.w('Failed to scan directory: ${dir.path}, error: $e');
    }
  }

  /// 检测文件类型
  FileType _detectFileType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();

    // 图片
    if (_isImageExtension(extension)) {
      return FileType.image;
    }

    // 视频
    if (_isVideoExtension(extension)) {
      return FileType.video;
    }

    // 音频
    if (_isAudioExtension(extension)) {
      return FileType.audio;
    }

    // 文档
    if (_isDocumentExtension(extension)) {
      return FileType.document;
    }

    // 压缩包
    if (_isArchiveExtension(extension)) {
      return FileType.archive;
    }

    return FileType.other;
  }

  /// 判断是否是图片扩展名
  bool _isImageExtension(String ext) {
    const imageExts = [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'bmp',
      'webp',
      'svg',
      'ico',
      'tiff',
      'tif',
      'heic',
      'heif',
      'raw',
      'cr2',
    ];
    return imageExts.contains(ext);
  }

  /// 判断是否是视频扩展名
  bool _isVideoExtension(String ext) {
    const videoExts = [
      'mp4',
      'avi',
      'mov',
      'wmv',
      'flv',
      'mkv',
      'webm',
      'm4v',
      'mpg',
      'mpeg',
      '3gp',
      'ts',
      'vob',
      'ogv',
    ];
    return videoExts.contains(ext);
  }

  /// 判断是否是音频扩展名
  bool _isAudioExtension(String ext) {
    const audioExts = [
      'mp3',
      'wav',
      'flac',
      'aac',
      'ogg',
      'wma',
      'm4a',
      'opus',
      'ape',
      'alac',
      'aiff',
      'mid',
      'midi',
    ];
    return audioExts.contains(ext);
  }

  /// 判断是否是文档扩展名
  bool _isDocumentExtension(String ext) {
    const docExts = [
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'rtf',
      'odt',
      'ods',
      'odp',
      'pages',
      'numbers',
      'keynote',
      'csv',
      'md',
      'epub',
      'mobi',
    ];
    return docExts.contains(ext);
  }

  /// 判断是否是压缩包扩展名
  bool _isArchiveExtension(String ext) {
    const archiveExts = [
      'zip',
      'rar',
      '7z',
      'tar',
      'gz',
      'bz2',
      'xz',
      'iso',
      'dmg',
      'apk',
      'jar',
      'war',
    ];
    return archiveExts.contains(ext);
  }

  /// 判断是否是隐藏文件/文件夹
  bool _isHidden(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.startsWith('.');
  }

  /// 快速检查文件夹是否有足够内容（用于过滤）
  ///
  /// [minFiles] 最小文件数量
  /// [minSizeMB] 最小大小（MB）
  Future<bool> hasEnoughContent(
    String path, {
    int minFiles = 5,
    double minSizeMB = 1.0,
  }) async {
    try {
      final stats = await analyzeFolderStats(path, maxDepth: 1);
      return stats.totalFiles >= minFiles || stats.totalSizeMB >= minSizeMB;
    } catch (e) {
      logger.w('Failed to check folder content: $path, error: $e');
      return false;
    }
  }

  /// 检查是否是临时/缓存目录
  bool isTempOrCacheFolder(String path) {
    final name = path.split(Platform.pathSeparator).last.toLowerCase();
    const tempKeywords = [
      'cache',
      'temp',
      'tmp',
      'temporary',
      '.cache',
      '.temp',
      '.tmp',
      'thumbnails',
      '.thumbnails',
    ];

    return tempKeywords.any((keyword) => name.contains(keyword));
  }

  /// 批量分析多个文件夹
  Future<Map<String, FolderStats>> batchAnalyzeFolders(
    List<String> paths, {
    int maxDepth = 1,
    bool includeHidden = false,
  }) async {
    final results = <String, FolderStats>{};

    for (final path in paths) {
      final stats = await analyzeFolderStats(
        path,
        maxDepth: maxDepth,
        includeHidden: includeHidden,
      );
      results[path] = stats;
    }

    return results;
  }
}
