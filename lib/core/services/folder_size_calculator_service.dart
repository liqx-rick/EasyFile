import 'dart:io';

import 'package:easyfile/core/logger.dart';

/// 文件夹大小计算结果
class FolderSizeResult {
  final String folderPath;
  final String folderName;
  final int totalBytes;
  final int fileCount;
  final int folderCount;
  final Duration calculationTime;

  const FolderSizeResult({
    required this.folderPath,
    required this.folderName,
    required this.totalBytes,
    required this.fileCount,
    required this.folderCount,
    required this.calculationTime,
  });

  /// 格式化文件大小
  String get formattedSize {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(2)} KB';
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 文件夹大小计算服务
///
/// 递归计算指定文件夹的总大小、文件数量和子文件夹数量
/// 支持进度回调，适合大型文件夹计算
class FolderSizeCalculatorService {
  /// 计算文件夹大小
  ///
  /// [folderPath] 文件夹路径
  /// [onProgress] 进度回调 (已处理文件数, 当前正在处理的文件路径)
  /// 返回 FolderSizeResult 或在出错时抛出异常
  Future<FolderSizeResult> calculateFolderSize(
    String folderPath, {
    void Function(int processedFiles, String currentPath)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      logger.d('开始计算文件夹大小: $folderPath');

      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        throw Exception('文件夹不存在: $folderPath');
      }

      int totalBytes = 0;
      int fileCount = 0;
      int folderCount = 0;
      int processedFiles = 0;

      // 递归遍历文件夹
      await _calculateRecursively(
        folder,
        (size, isFile, path) {
          if (isFile) {
            totalBytes += size;
            fileCount++;
            processedFiles++;

            // 每处理 10 个文件触发一次进度回调
            if (onProgress != null && (processedFiles % 10 == 0 || processedFiles == 1)) {
              onProgress(processedFiles, path);
            }
          } else {
            folderCount++;
          }
        },
      );

      stopwatch.stop();
      logger.d('文件夹大小计算完成，耗时: ${stopwatch.elapsed.inMilliseconds}ms');
      logger.d('总大小: $totalBytes 字节, 文件数: $fileCount, 子文件夹数: $folderCount');

      final folderName = _getFolderName(folderPath);

      return FolderSizeResult(
        folderPath: folderPath,
        folderName: folderName,
        totalBytes: totalBytes,
        fileCount: fileCount,
        folderCount: folderCount,
        calculationTime: stopwatch.elapsed,
      );
    } catch (e, stackTrace) {
      logger.e('计算文件夹大小失败: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }

  /// 递归计算文件夹内容
  Future<void> _calculateRecursively(
    Directory directory,
    void Function(int size, bool isFile, String path) onItem,
  ) async {
    try {
      final entities = directory.listSync(recursive: false, followLinks: false);

      for (final entity in entities) {
        try {
          if (entity is File) {
            final stat = await entity.stat();
            onItem(stat.size, true, entity.path);
          } else if (entity is Directory) {
            onItem(0, false, entity.path);
            // 递归处理子文件夹
            await _calculateRecursively(entity, onItem);
          }
        } catch (e) {
          // 跳过无权限访问的文件/文件夹
          logger.w('跳过无法访问的项: ${entity.path}, 错误: $e');
        }
      }
    } catch (e) {
      // 跳过无权限访问的文件夹
      logger.w('跳过无法访问的文件夹: ${directory.path}, 错误: $e');
    }
  }

  /// 获取文件夹名称
  String _getFolderName(String folderPath) {
    final parts = folderPath.split(Platform.pathSeparator);
    return parts.isNotEmpty ? parts.last : folderPath;
  }

  /// 格式化字节数为可读字符串
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
