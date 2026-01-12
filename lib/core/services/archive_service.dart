import 'dart:io';
import 'package:easyfile/data/models/archive_entry_info.dart';
import 'package:easyfile/ffi/archive_ffi.dart';
import 'package:easyfile/core/logger.dart';

/// 压缩包服务 (FFI 版本)
/// 
/// 基于 dart:ffi + libarchive 实现压缩包查看和解压功能
/// 支持格式: ZIP, RAR, 7z, TAR, GZ, BZ2, XZ, LZ4, ZSTD, TAR.GZ, TAR.BZ2等
/// 
/// 注意: 当前仅支持 Android 平台，iOS 支持为未来计划
class ArchiveService {
  final ArchiveFFI _ffi = ArchiveFFI();
  int? _currentHandle;

  /// 解压压缩包到指定目录
  /// 
  /// [archivePath] 压缩包完整路径
  /// [targetDir] 目标目录（不含子文件夹名）
  /// [folderName] 子文件夹名称（将创建 targetDir/folderName/）
  /// [autoRename] 如果文件夹已存在，是否自动重命名
  /// [onProgress] 进度回调 (当前进度 0.0-1.0)
  /// 
  /// 返回解压结果
  Future<ExtractResult> extractTo({
    required String archivePath,
    required String targetDir,
    required String folderName,
    bool autoRename = true,
    void Function(double progress)? onProgress,
  }) async {
    logger.i('ArchiveService.extractTo (FFI): $archivePath -> $targetDir/$folderName');

    try {
      // 验证压缩包是否存在
      final archiveFile = File(archivePath);
      if (!archiveFile.existsSync()) {
        return ExtractResult.failure(
          errorMessage: '压缩包不存在: $archivePath',
          targetPath: '$targetDir/$folderName',
        );
      }

      // 处理文件夹名冲突
      String finalFolderName = folderName;
      if (autoRename) {
        finalFolderName = _getAvailableFolderName(targetDir, folderName);
        if (finalFolderName != folderName) {
          logger.i('文件夹名称冲突，自动重命名: $folderName -> $finalFolderName');
        }
      }

      final fullPath = '$targetDir/$finalFolderName';

      // 创建目标目录
      final targetDirectory = Directory(fullPath);
      if (!targetDirectory.existsSync()) {
        targetDirectory.createSync(recursive: true);
      }

      logger.i('开始解压 (FFI): $archivePath -> $fullPath');

      // 在单独的 Isolate 中执行解压（避免阻塞 UI）
      // 注意：由于 FFI 操作较快，这里先用同步调用，后续可优化为 Isolate
      final result = _ffi.extractArchive(
        archivePath: archivePath,
        destPath: fullPath,
        overwrite: false,
        preservePermissions: false,
        onProgress: (progress, filename) {
          logger.d('Progress: ${(progress * 100).toStringAsFixed(1)}% - $filename');
          onProgress?.call(progress);
        },
      );

      _currentHandle = result.handleId;

      if (result.success) {
        logger.i('解压完成 (FFI): $fullPath, ${result.totalFiles} 个文件');
        return ExtractResult.success(
          targetPath: fullPath,
          totalFiles: result.totalFiles,
          extractedFiles: result.extractedFiles,
        );
      } else {
        logger.e('解压失败 (FFI): ${result.errorMessage}');
        return ExtractResult.failure(
          errorMessage: result.errorMessage.isEmpty 
              ? '解压失败' 
              : result.errorMessage,
          targetPath: fullPath,
          extractedFiles: result.extractedFiles,
        );
      }
    } catch (e, stackTrace) {
      logger.e('解压异常 (FFI): $e\n$stackTrace');
      return ExtractResult.failure(
        errorMessage: '解压失败: ${e.toString()}',
        targetPath: '$targetDir/$folderName',
      );
    }
  }

  /// 取消当前解压操作
  /// 
  /// 返回是否成功取消
  bool cancelExtraction() {
    if (_currentHandle != null) {
      final cancelled = _ffi.cancelExtraction(_currentHandle!);
      logger.i('取消解压 (FFI): handle=$_currentHandle, result=$cancelled');
      return cancelled;
    }
    return false;
  }

  /// 获取可用的文件夹名称（处理冲突）
  /// 
  /// 如果文件夹已存在，会自动添加后缀 _1, _2, _3 等
  String _getAvailableFolderName(String baseDir, String folderName) {
    String testName = folderName;
    int suffix = 1;

    while (Directory('$baseDir/$testName').existsSync()) {
      testName = '${folderName}_$suffix';
      suffix++;
    }

    return testName;
  }

  /// 统计目录中的文件数量（递归）
  // ignore: unused_element
  int _countFilesInDirectory(Directory dir) {
    int count = 0;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          count++;
        }
      }
    } catch (e) {
      logger.w('统计文件数量时出错: $e');
    }
    return count;
  }

  /// 验证压缩包是否有效
  /// 
  /// 通过 FFI 调用 libarchive 验证
  Future<bool> validateArchive(String archivePath) async {
    try {
      final file = File(archivePath);
      if (!file.existsSync()) return false;

      return _ffi.validate(archivePath);
    } catch (e) {
      logger.w('验证压缩包失败 (FFI): $e');
      return false;
    }
  }

  /// 获取压缩包信息（大小、类型等）
  /// 
  /// 返回压缩包的基本信息，不解压内容
  Future<Map<String, dynamic>?> getArchiveInfo(String archivePath) async {
    try {
      final file = File(archivePath);
      if (!file.existsSync()) return null;

      final stat = await file.stat();
      final fileName = file.path.split(Platform.pathSeparator).last;
      final extension = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';

      return {
        'name': fileName,
        'path': archivePath,
        'size': stat.size,
        'extension': extension,
        'modified': stat.modified,
      };
    } catch (e) {
      logger.w('获取压缩包信息失败: $e');
      return null;
    }
  }

  /// 列出压缩包内的所有文件和目录
  /// 
  /// [archivePath] 压缩包完整路径
  /// 返回文件和目录列表，不实际解压
  Future<List<ArchiveEntryInfo>> listArchiveContents(String archivePath) async {
    logger.i('ArchiveService.listArchiveContents (FFI): $archivePath');

    try {
      // 验证压缩包是否存在
      final archiveFile = File(archivePath);
      if (!archiveFile.existsSync()) {
        logger.w('压缩包不存在: $archivePath');
        return [];
      }

      // 通过 FFI 列出内容
      final result = _ffi.listContents(archivePath);

      if (!result.success) {
        logger.e('列出压缩包内容失败 (FFI): ${result.errorMessage}');
        return [];
      }

      // 转换为 ArchiveEntryInfo
      final entries = result.entries.map((e) {
        return ArchiveEntryInfo(
          name: e.name,
          path: e.pathname,
          isDirectory: e.isDirectory,
          size: e.size,
          compressedSize: e.compressedSize,
          modificationDate: DateTime.fromMillisecondsSinceEpoch(e.mtime * 1000),
          compressionMethod: 0, // FFI 暂不提供
          crc: e.crc32,
        );
      }).toList();

      logger.i('列出压缩包内容成功 (FFI): ${entries.length} 个条目');
      return entries;
    } catch (e, stackTrace) {
      logger.e('列出压缩包内容异常 (FFI): $e\n$stackTrace');
      return [];
    }
  }

  /// 检查平台支持
  /// 
  /// 当前仅支持 Android
  /// iOS 支持将在未来版本添加
  bool isPlatformSupported() {
    return Platform.isAndroid;
    // TODO: iOS 支持 - 未来计划
    // return Platform.isAndroid || Platform.isIOS;
  }
}

/// 解压结果
class ExtractResult {
  final bool success;
  final String targetPath;
  final int totalFiles;
  final int? extractedFiles;
  final String errorMessage;

  ExtractResult({
    required this.success,
    required this.targetPath,
    this.totalFiles = 0,
    this.extractedFiles,
    this.errorMessage = '',
  });

  factory ExtractResult.success({
    required String targetPath,
    int totalFiles = 0,
    int? extractedFiles,
  }) {
    return ExtractResult(
      success: true,
      targetPath: targetPath,
      totalFiles: totalFiles,
      extractedFiles: extractedFiles ?? totalFiles,
    );
  }

  factory ExtractResult.failure({
    required String errorMessage,
    String? targetPath,
    int? extractedFiles,
  }) {
    return ExtractResult(
      success: false,
      targetPath: targetPath ?? '',
      errorMessage: errorMessage,
      extractedFiles: extractedFiles,
    );
  }
}
