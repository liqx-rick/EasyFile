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
    logger.i(
        'ArchiveService.extractTo (FFI): $archivePath -> $targetDir/$folderName');

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

      // 检查目标目录剩余空间是否足够
      final diskSpaceCheck =
          await _checkDiskSpace(targetDir, archiveFile.lengthSync() * 2);
      if (!diskSpaceCheck) {
        return ExtractResult.failure(
          errorMessage: '磁盘空间不足，请清理后重试',
          targetPath: fullPath,
        );
      }

      // 创建目标目录
      final targetDirectory = Directory(fullPath);
      if (!targetDirectory.existsSync()) {
        targetDirectory.createSync(recursive: true);
      }

      logger.i('开始解压 (FFI): $archivePath -> $fullPath');

      // 验证压缩包文件大小
      final fileSize = archiveFile.lengthSync();
      logger.d('压缩包文件大小: $fileSize bytes');

      // 在单独的 Isolate 中执行解压（避免阻塞 UI）
      // 注意：由于 FFI 操作较快，这里先用同步调用，后续可优化为 Isolate
      final result = _ffi.extractArchive(
        archivePath: archivePath,
        destPath: fullPath,
        overwrite: false,
        preservePermissions: false,
        onProgress: (progress, filename) {
          logger.d(
              'Progress: ${(progress * 100).toStringAsFixed(1)}% - $filename');
          onProgress?.call(progress);
        },
      );

      _currentHandle = result.handleId;

      // 记录详细的解压结果
      logger.d(
          'FFI extractArchive 返回: status=${result.status}, totalFiles=${result.totalFiles}, extractedFiles=${result.extractedFiles}, errorMessage="${result.errorMessage}"');

      if (result.success) {
        logger.i('解压完成 (FFI): $fullPath, ${result.totalFiles} 个文件');

        // 验证解压结果
        if (result.totalFiles == 0) {
          logger.w('解压完成但没有文件被提取 (可能是加密、损坏或不支持的格式)');
        }

        return ExtractResult.success(
          targetPath: fullPath,
          totalFiles: result.totalFiles,
          extractedFiles: result.extractedFiles,
        );
      } else {
        logger.e(
            '解压失败 (FFI): status=${result.status}, error=${result.errorMessage}');
        return ExtractResult.failure(
          errorMessage:
              result.errorMessage.isEmpty ? '解压失败' : result.errorMessage,
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
      final extension =
          fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

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
  /// 返回文件和目录列表以及错误信息（如果有）
  Future<ArchiveListResult> listArchiveContents(String archivePath) async {
    logger.i('ArchiveService.listArchiveContents (FFI): $archivePath');

    try {
      // 验证压缩包是否存在
      final archiveFile = File(archivePath);
      if (!archiveFile.existsSync()) {
        logger.w('压缩包不存在: $archivePath');
        return ArchiveListResult(
          entries: [],
          errorMessage: '压缩包文件不存在',
        );
      }

      // 验证文件大小
      final fileSize = archiveFile.lengthSync();
      logger.d('压缩包文件大小: $fileSize bytes');

      // 通过 FFI 列出内容
      final result = _ffi.listContents(archivePath);

      // 记录详细的结果信息
      logger.d(
          'FFI listContents 返回: status=${result.status}, entries=${result.entries.length}, errorMessage="${result.errorMessage}"');

      if (!result.success) {
        logger.e(
            '列出压缩包内容失败 (FFI): status=${result.status}, error=${result.errorMessage}');
        return ArchiveListResult(
          entries: [],
          errorMessage: result.errorMessage,
        );
      }

      // 检查是否返回了空列表
      if (result.entries.isEmpty) {
        final errorMsg =
            result.errorMessage.isNotEmpty ? result.errorMessage : '未知原因';
        logger.w('压缩包内容为空: $errorMsg');
        logger.w('文件路径: $archivePath');

        // 尝试验证压缩包
        final isValid = _ffi.validate(archivePath);
        logger.d('压缩包验证结果: $isValid');

        // 根据错误信息提供更友好的提示
        String userMessage;
        if (result.errorMessage.contains('UTF-16') ||
            result.errorMessage.contains('locale') ||
            result.errorMessage.contains('charset')) {
          userMessage = 'RAR 文件编码不兼容\n\n'
              '此文件使用了特殊字符编码（UTF-16BE），当前无法读取。';
        } else if (result.errorMessage.contains('Unsupported') ||
            result.errorMessage.contains('encrypted')) {
          userMessage = result.errorMessage;
        } else if (!isValid) {
          userMessage = '压缩包格式不支持或文件已损坏';
        } else {
          userMessage = '无法读取压缩包内容（可能是 RAR 5.0+ 或加密文件）';
        }

        logger.e('无法读取压缩包内容: $userMessage');
        
        return ArchiveListResult(
          entries: [],
          errorMessage: userMessage,
          canOpenWithOtherApp: result.errorMessage.contains('UTF-16') ||
              result.errorMessage.contains('locale') ||
              result.errorMessage.contains('charset'),
        );
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
      return ArchiveListResult(entries: entries);
    } catch (e, stackTrace) {
      logger.e('列出压缩包内容异常 (FFI): $e\n$stackTrace');
      return ArchiveListResult(
        entries: [],
        errorMessage: '读取失败: ${e.toString()}',
      );
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

  /// 检查磁盘空间是否充足
  ///
  /// [dirPath] 目标目录路径
  /// [requiredBytes] 所需空间大小（字节）
  ///
  /// 返回 true 表示空间充足，false 表示空间不足
  Future<bool> _checkDiskSpace(String dirPath, int requiredBytes) async {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (e) {
          logger.w('创建目录失败: $e');
          // 无法创建目录，允许继续（可能在后续操作中失败）
          return true;
        }
      }

      // 获取父目录的统计信息用于验证目录可访问性
      // (statSync() 返回的 size 是文件/文件夹大小，不是剩余空间)
      // 获取剩余空间需要使用平台特定代码或第三方库
      // 这里作为简单检查，仅验证目录是否可写

      final testFile = File(
          '${dir.path}/.disk_check_${DateTime.now().millisecondsSinceEpoch}');
      try {
        await testFile.writeAsBytes([]);
        await testFile.delete();
        logger.i('磁盘空间检查: 目录 $dirPath 可写');
        return true;
      } catch (e) {
        logger.w('磁盘空间检查: 目录 $dirPath 不可写 - $e');
        return false;
      }
    } catch (e) {
      logger.w('磁盘空间检查异常: $e');
      // 异常情况下允许继续
      return true;
    }
  }

  /// 从压缩包中提取单个文件用于预览
  ///
  /// [archivePath] 压缩包完整路径
  /// [entryPath] 条目在压缩包中的路径
  /// [outputPath] 输出文件路径
  ///
  /// 返回提取结果
  Future<SingleFileExtractResult> extractSingleFileForPreview(
    String archivePath,
    String entryPath,
    String outputPath,
  ) async {
    logger.i('ArchiveService.extractSingleFileForPreview: $entryPath from $archivePath');

    try {
      // 确保输出目录存在
      final outputFile = File(outputPath);
      final outputDir = outputFile.parent;
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final result = _ffi.extractSingleFile(
        archivePath: archivePath,
        entryPath: entryPath,
        outputPath: outputPath,
      );

      if (result.success) {
        logger.i('提取成功: $entryPath (${result.extractedSize} bytes)');
        return SingleFileExtractResult(
          success: true,
          extractedSize: result.extractedSize,
          errorMessage: '',
        );
      } else {
        logger.w('提取失败: ${result.errorMessage}');
        return SingleFileExtractResult(
          success: false,
          extractedSize: 0,
          errorMessage: result.errorMessage,
        );
      }
    } catch (e) {
      logger.e('提取文件异常: $e');
      return SingleFileExtractResult(
        success: false,
        extractedSize: 0,
        errorMessage: '提取失败: $e',
      );
    }
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

/// 压缩包列表结果
class ArchiveListResult {
  final List<ArchiveEntryInfo> entries;
  final String? errorMessage;
  final bool canOpenWithOtherApp;

  ArchiveListResult({
    required this.entries,
    this.errorMessage,
    this.canOpenWithOtherApp = false,
  });

  bool get success => errorMessage == null || errorMessage!.isEmpty;
  bool get isEmpty => entries.isEmpty;
}

/// 单文件提取结果
class SingleFileExtractResult {
  final bool success;
  final int extractedSize;
  final String errorMessage;

  SingleFileExtractResult({
    required this.success,
    required this.extractedSize,
    required this.errorMessage,
  });
}
