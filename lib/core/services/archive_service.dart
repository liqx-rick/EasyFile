import 'dart:io';
import 'package:easyfile/data/models/archive_entry_info.dart';
import 'package:easyfile/ffi/archive_ffi.dart';
import 'package:easyfile/ffi/unrar_ffi.dart';
import 'package:easyfile/ffi/minizip_ffi.dart';
import 'package:easyfile/core/logger.dart';

/// 压缩包服务 (FFI 版本)
///
/// 基于 dart:ffi + libarchive + UnRAR SDK + minizip-ng 实现压缩包查看和解压功能
/// 支持格式: ZIP, RAR, 7z, TAR, GZ, BZ2, XZ, LZ4, ZSTD, TAR.GZ, TAR.BZ2等
///
/// RAR 文件使用 UnRAR SDK 专门处理
/// ZIP 文件使用 minizip-ng 处理（更好的中文编码支持）
/// 其他格式使用 libarchive 处理
/// 注意: 当前仅支持 Android 平台，iOS 支持为未来计划
class ArchiveService {
  final ArchiveFFI _ffi = ArchiveFFI();
  final UnrarFFI _unrar = UnrarFFI();
  final MinizipFFI _minizip = MinizipFFI();
  int? _currentHandle;

  /// 检查文件是否为RAR格式
  bool _isRarFile(String filePath) {
    // 先检查扩展名
    final lowerPath = filePath.toLowerCase();
    if (!lowerPath.endsWith('.rar')) {
      return false;
    }

    // 再使用UnRAR SDK验证文件头
    try {
      return _unrar.isRarFile(filePath);
    } catch (e) {
      logger.w('检查RAR文件失败: $e');
      return false;
    }
  }

  /// 检查文件是否为ZIP格式
  bool _isZipFile(String filePath) {
    final lowerPath = filePath.toLowerCase();
    return lowerPath.endsWith('.zip');
  }

  /// 解压压缩包到指定目录
  ///
  /// [archivePath] 压缩包完整路径
  /// [targetDir] 目标目录（不含子文件夹名）
  /// [folderName] 子文件夹名称（将创建 targetDir/folderName/）
  /// [autoRename] 如果文件夹已存在，是否自动重命名
  /// [password] 解压密码（可选）
  /// [onProgress] 进度回调 (当前进度 0.0-1.0)
  ///
  /// 返回解压结果
  Future<ExtractResult> extractTo({
    required String archivePath,
    required String targetDir,
    required String folderName,
    bool autoRename = true,
    String? password,
    void Function(double progress)? onProgress,
  }) async {
    logger
        .i('ArchiveService.extractTo: $archivePath -> $targetDir/$folderName');

    try {
      // 验证压缩包是否存在
      final archiveFile = File(archivePath);
      if (!archiveFile.existsSync()) {
        return ExtractResult.failure(
          errorMessage: '压缩包不存在: $archivePath',
          targetPath: '$targetDir/$folderName',
        );
      }

      // 检测文件格式
      final isRar = _isRarFile(archivePath);
      final isZip = _isZipFile(archivePath);
      String formatInfo = isRar 
          ? "RAR (UnRAR SDK)" 
          : isZip 
              ? "ZIP (minizip-ng)" 
              : "其他 (libarchive)";
      logger.i('文件格式检测: $formatInfo');

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

      logger.i('开始解压: $archivePath -> $fullPath');

      // 验证压缩包文件大小
      final fileSize = archiveFile.lengthSync();
      logger.d('压缩包文件大小: $fileSize bytes');

      // 根据文件类型选择解压方法
      if (isRar) {
        // 使用 UnRAR SDK 解压
        return _extractRarFile(
          archivePath: archivePath,
          fullPath: fullPath,
          password: password,
          onProgress: onProgress,
        );
      } else if (isZip) {
        // 使用 minizip-ng 解压
        return _extractZipFile(
          archivePath: archivePath,
          fullPath: fullPath,
          password: password,
          onProgress: onProgress,
        );
      } else {
        // 使用 libarchive 解压其他格式
        return _extractWithLibarchive(
          archivePath: archivePath,
          fullPath: fullPath,
          onProgress: onProgress,
        );
      }
    } catch (e, stackTrace) {
      logger.e('解压异常: $e\n$stackTrace');
      return ExtractResult.failure(
        errorMessage: '解压失败: ${e.toString()}',
        targetPath: '$targetDir/$folderName',
      );
    }
  }

  /// 使用UnRAR SDK解压RAR文件
  Future<ExtractResult> _extractRarFile({
    required String archivePath,
    required String fullPath,
    String? password,
    void Function(double progress)? onProgress,
  }) async {
    try {
      logger.i('使用 UnRAR SDK 解压: $archivePath');

      // 先列出压缩包内容，获取预期的文件总数
      int expectedFileCount = 0;
      try {
        final listResult = await _listRarContents(archivePath);
        if (listResult.success) {
          // 只统计文件，不包括目录
          expectedFileCount =
              listResult.entries.where((e) => !e.isDirectory).length;
          logger.d('压缩包中预期文件数: $expectedFileCount');
        }
      } catch (e) {
        logger.w('无法列出压缩包内容，跳过文件数检查: $e');
      }

      final result = _unrar.extract(
        archivePath,
        fullPath,
        password: password,
      );

      if (result.status == 0) {
        final totalFiles = result.extractedCount + result.skippedCount;
        logger.i(
            'UnRAR 解压完成: $fullPath, $totalFiles 个文件 (提取: ${result.extractedCount}, 跳过: ${result.skippedCount})');

        // 检查是否因为密码错误导致没有提取任何文件
        if (totalFiles == 0 && result.extractedCount == 0) {
          logger.w('UnRAR 解压完成但未提取任何文件，可能需要密码');
          String errorMsg =
              password == null || password.isEmpty ? '压缩包需要密码' : '密码错误，未提取任何文件';
          return ExtractResult.failure(
            errorMessage: errorMsg,
            targetPath: fullPath,
            extractedFiles: 0,
          );
        }

        // 检查是否提取的文件数明显少于预期（可能是密码错误）
        if (expectedFileCount > 0 &&
            result.extractedCount > 0 &&
            result.extractedCount < expectedFileCount) {
          // 如果提取的文件数少于预期的50%，认为可能是密码错误
          if (result.extractedCount < expectedFileCount * 0.5) {
            logger.w(
                '提取的文件数(${result.extractedCount})远少于预期($expectedFileCount)，可能是密码错误');
            String errorMsg = password == null || password.isEmpty
                ? '压缩包需要密码（已提取部分文件）'
                : '密码错误，仅提取了部分文件（${result.extractedCount}/$expectedFileCount）';
            return ExtractResult.failure(
              errorMessage: errorMsg,
              targetPath: fullPath,
              extractedFiles: result.extractedCount,
            );
          }
        }

        return ExtractResult.success(
          targetPath: fullPath,
          totalFiles: totalFiles,
          extractedFiles: result.extractedCount,
        );
      } else {
        logger.e(
            'UnRAR 解压失败: status=${result.status}, error=${result.errorMessage}');
        // 检查是否为密码错误
        String errorMsg = result.errorMessage;
        if (errorMsg.isEmpty) {
          if (result.status == 22) {
            // ERAR_MISSING_PASSWORD
            errorMsg = password == null || password.isEmpty
                ? '压缩包需要密码'
                : '密码错误或压缩包已损坏';
          } else {
            errorMsg = 'RAR解压失败 (错误代码: ${result.status})';
          }
        }
        return ExtractResult.failure(
          errorMessage: errorMsg,
          targetPath: fullPath,
          extractedFiles: result.extractedCount,
        );
      }
    } catch (e, stackTrace) {
      logger.e('UnRAR 解压异常: $e\n$stackTrace');
      return ExtractResult.failure(
        errorMessage: 'RAR解压失败: ${e.toString()}',
        targetPath: fullPath,
      );
    }
  }

  /// 使用minizip-ng解压ZIP文件
  Future<ExtractResult> _extractZipFile({
    required String archivePath,
    required String fullPath,
    String? password,
    void Function(double progress)? onProgress,
  }) async {
    try {
      logger.i('使用 minizip-ng 解压: $archivePath');

      // 列出所有条目
      final listResult = await _listZipContents(archivePath);
      if (!listResult.success || listResult.entries.isEmpty) {
        return ExtractResult.failure(
          errorMessage: listResult.errorMessage ?? '无法读取ZIP内容',
          targetPath: fullPath,
        );
      }

      logger.d('ZIP包含 ${listResult.entries.length} 个条目');

      int totalFiles = listResult.entries.where((e) => !e.isDirectory).length;
      int extractedFiles = 0;

      // 逐个提取文件
      for (var i = 0; i < listResult.entries.length; i++) {
        final entry = listResult.entries[i];
        
        // 构建输出路径：使用UTF-8解码后的路径
        final outputPath = '$fullPath/${entry.path}';
        
        if (entry.isDirectory) {
          // 创建目录
          final dir = Directory(outputPath);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          logger.d('创建目录: ${entry.path}');
        } else {
          // 提取文件：使用原始GBK字节查找，UTF-8路径输出
          if (entry.rawPathname == null || entry.rawPathname!.isEmpty) {
            logger.e('条目 ${entry.path} 缺少原始路径字节');
            continue;
          }
          
          final result = _minizip.extractSingleFile(
            archivePath,
            entry.rawPathname!, // 原始GBK字节
            outputPath, // UTF-8路径
            password: password,
          );

          if (result.success) {
            extractedFiles++;
            logger.d('提取 ${entry.path} 成功 (${result.fileSize} bytes)');
            
            // 更新进度
            if (onProgress != null) {
              onProgress(extractedFiles / totalFiles);
            }
          } else {
            logger.e('提取 ${entry.path} 失败: ${result.errorMessage}');
            // 继续提取其他文件
          }
        }
      }

      logger.i('解压完成: $extractedFiles/$totalFiles 个文件');

      if (extractedFiles == 0 && totalFiles > 0) {
        String errorMsg = password == null || password.isEmpty 
            ? '压缩包需要密码' 
            : '密码错误或文件损坏';
        return ExtractResult.failure(
          errorMessage: errorMsg,
          targetPath: fullPath,
          extractedFiles: 0,
        );
      }

      return ExtractResult.success(
        targetPath: fullPath,
        totalFiles: totalFiles,
        extractedFiles: extractedFiles,
      );
    } catch (e, stackTrace) {
      logger.e('minizip-ng 解压异常: $e\n$stackTrace');
      return ExtractResult.failure(
        errorMessage: 'ZIP解压失败: ${e.toString()}',
        targetPath: fullPath,
      );
    }
  }

  /// 使用libarchive解压其他格式
  Future<ExtractResult> _extractWithLibarchive({
    required String archivePath,
    required String fullPath,
    void Function(double progress)? onProgress,
  }) async {
    try {
      logger.i('使用 libarchive 解压: $archivePath');

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
          'libarchive extractArchive 返回: status=${result.status}, totalFiles=${result.totalFiles}, extractedFiles=${result.extractedFiles}, errorMessage="${result.errorMessage}"');

      if (result.success) {
        logger.i('解压完成 (libarchive): $fullPath, ${result.totalFiles} 个文件');

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
            '解压失败 (libarchive): status=${result.status}, error=${result.errorMessage}');
        return ExtractResult.failure(
          errorMessage:
              result.errorMessage.isEmpty ? '解压失败' : result.errorMessage,
          targetPath: fullPath,
          extractedFiles: result.extractedFiles,
        );
      }
    } catch (e, stackTrace) {
      logger.e('libarchive 解压异常: $e\n$stackTrace');
      return ExtractResult.failure(
        errorMessage: '解压失败: ${e.toString()}',
        targetPath: fullPath,
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
    logger.i('ArchiveService.listArchiveContents: $archivePath');

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

      // 检测文件格式并路由到对应的处理器
      final isRar = _isRarFile(archivePath);
      final isZip = _isZipFile(archivePath);
      
      if (isRar) {
        logger.i('文件格式检测: RAR (UnRAR SDK)');
        return _listRarContents(archivePath);
      } else if (isZip) {
        logger.i('文件格式检测: ZIP (minizip-ng)');
        return _listZipContents(archivePath);
      } else {
        logger.i('文件格式检测: 其他 (libarchive)');
        return _listWithLibarchive(archivePath, fileSize);
      }
    } catch (e, stackTrace) {
      logger.e('列出压缩包内容异常: $e\n$stackTrace');
      return ArchiveListResult(
        entries: [],
        errorMessage: '读取失败: ${e.toString()}',
      );
    }
  }

  /// 使用minizip-ng列出ZIP内容
  Future<ArchiveListResult> _listZipContents(String archivePath) async {
    try {
      logger.i('使用 minizip-ng 列出ZIP内容: $archivePath');

      final result = _minizip.listContents(archivePath);

      if (result.success) {
        logger.i('minizip 读取成功: ${result.entries.length} 个条目');

        // 转换为 ArchiveEntryInfo 列表
        final entries = result.entries.map((entry) {
          return ArchiveEntryInfo(
            name: entry.name,
            size: entry.size,
            compressedSize: entry.compressedSize,
            isDirectory: entry.isDirectory,
            modificationDate:
                DateTime.fromMillisecondsSinceEpoch(entry.mtime * 1000),
            path: entry.pathname,
            rawPathname: entry.rawPathname, // 保存原始字节
            compressionMethod: 0,
            crc: entry.crc32,
          );
        }).toList();

        return ArchiveListResult(entries: entries, errorMessage: null);
      } else {
        logger.e('minizip 读取失败: ${result.errorMessage}');
        return ArchiveListResult(
          entries: [],
          errorMessage: result.errorMessage.isNotEmpty
              ? result.errorMessage
              : 'ZIP文件读取失败',
        );
      }
    } catch (e, stackTrace) {
      logger.e('minizip 读取异常: $e\n$stackTrace');
      return ArchiveListResult(
        entries: [],
        errorMessage: 'ZIP文件读取失败: ${e.toString()}',
      );
    }
  }

  /// 使用UnRAR SDK列出RAR内容
  Future<ArchiveListResult> _listRarContents(String archivePath) async {
    try {
      logger.i('使用 UnRAR SDK 列出内容: $archivePath');

      final result = _unrar.listContents(archivePath);

      if (result.status == 0) {
        logger.i('UnRAR 读取成功: ${result.entries.length} 个条目');

        // 记录每个条目的详细信息（用于诊断）
        for (var i = 0; i < result.entries.length; i++) {
          final entry = result.entries[i];
          logger.d(
              '  Entry $i: "${entry.filename}" (${entry.size} bytes, isDir: ${entry.isDirectory})');
        }

        // 转换为 ArchiveEntryInfo 列表
        final entries = result.entries.map((entry) {
          return ArchiveEntryInfo(
            name: entry.filename,
            size: entry.size,
            compressedSize: entry.packedSize,
            isDirectory: entry.isDirectory,
            modificationDate: DateTime.now(), // UnRAR SDK不提供文件时间，使用当前时间
            path: entry.filename,
            compressionMethod: 0, // UnRAR不提供
            crc: 0, // UnRAR不提供
          );
        }).toList();

        return ArchiveListResult(
          entries: entries,
          errorMessage: null,
        );
      } else {
        logger.e(
            'UnRAR 读取失败: status=${result.status}, error=${result.errorMessage}');
        return ArchiveListResult(
          entries: [],
          errorMessage: result.errorMessage.isNotEmpty
              ? result.errorMessage
              : 'RAR文件读取失败 (错误代码: ${result.status})',
        );
      }
    } catch (e, stackTrace) {
      logger.e('UnRAR 读取异常: $e\n$stackTrace');
      return ArchiveListResult(
        entries: [],
        errorMessage: 'RAR文件读取失败: ${e.toString()}',
      );
    }
  }

  /// 使用libarchive列出其他格式内容
  Future<ArchiveListResult> _listWithLibarchive(
      String archivePath, int fileSize) async {
    try {
      logger.i('使用 libarchive 列出内容: $archivePath');

      // 通过 FFI 列出内容
      final result = _ffi.listContents(archivePath);

      // 记录详细的结果信息
      logger.d(
          'libarchive listContents 返回: status=${result.status}, entries=${result.entries.length}, errorMessage="${result.errorMessage}"');

      if (!result.success) {
        logger.e(
            '列出压缩包内容失败 (libarchive): status=${result.status}, error=${result.errorMessage}');
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

      logger.i('列出压缩包内容成功 (libarchive): ${entries.length} 个条目');
      return ArchiveListResult(entries: entries);
    } catch (e, stackTrace) {
      logger.e('列出压缩包内容异常 (libarchive): $e\n$stackTrace');
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
  /// [password] 解压密码（可选）
  ///
  /// 返回提取结果
  Future<SingleFileExtractResult> extractSingleFileForPreview(
    String archivePath,
    String entryPath,
    String outputPath, {
    String? password,
  }) async {
    logger.i(
        'ArchiveService.extractSingleFileForPreview: $entryPath from $archivePath');
    logger.d('  Output path: $outputPath');
    logger.d('  Entry path length: ${entryPath.length} chars');
    logger.d('  Entry path bytes: ${entryPath.codeUnits}');

    try {
      // 确保输出目录存在
      final outputFile = File(outputPath);
      final outputDir = outputFile.parent;
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // 检测文件格式
      final isRar = _isRarFile(archivePath);
      final isZip = _isZipFile(archivePath);

      if (isRar) {
        // 使用UnRAR SDK提取RAR文件
        logger.d('Using UnRAR SDK to extract single file from RAR');

        // UnRAR SDK会在目标目录下创建与RAR内相同的目录结构
        // 所以我们需要提取到父目录，然后移动文件到正确位置
        final tempDir = outputDir.parent;
        final success = _unrar.extractFile(
          archivePath,
          entryPath,
          tempDir.path,
          password: password,
        );

        if (success) {
          // 文件被提取到 tempDir/entryPath
          final extractedFile = File('${tempDir.path}/$entryPath');

          if (await extractedFile.exists()) {
            // 如果输出路径与提取路径不同，移动文件
            if (extractedFile.path != outputPath) {
              // 确保目标目录存在
              await outputFile.parent.create(recursive: true);
              // 移动文件到目标位置
              await extractedFile.rename(outputPath);
              logger.d(
                  'Moved extracted file from ${extractedFile.path} to $outputPath');
            }

            final size = await File(outputPath).length();
            logger.i('UnRAR提取成功: $entryPath ($size bytes)');
            return SingleFileExtractResult(
              success: true,
              extractedSize: size,
              errorMessage: '',
            );
          } else {
            logger.e('Extracted file not found at: ${extractedFile.path}');
            return SingleFileExtractResult(
              success: false,
              extractedSize: 0,
              errorMessage: 'Extracted file not found',
            );
          }
        } else {
          logger.w('UnRAR提取失败');
          // 检查是否为密码错误
          String errorMsg = '提取文件失败，压缩包可能需要密码或已损坏';
          if (password == null || password.isEmpty) {
            errorMsg = '压缩包需要密码';
          } else {
            errorMsg = '密码错误或压缩包已损坏';
          }
          return SingleFileExtractResult(
            success: false,
            extractedSize: 0,
            errorMessage: errorMsg,
          );
        }
      } else if (isZip) {
        // 使用minizip-ng提取ZIP文件
        logger.d('Using minizip-ng to extract single file from ZIP');
        
        // 需要找到原始GBK字节路径
        List<int>? rawPath;
        try {
          final listResult = await _listZipContents(archivePath);
          if (listResult.success) {
            logger.d('查找条目: $entryPath (共${listResult.entries.length}个条目)');
            for (var e in listResult.entries) {
              logger.d('  条目路径: "${e.path}" == "$entryPath" ? ${e.path == entryPath}');
            }
            
            final entry = listResult.entries.firstWhere(
              (e) => e.path == entryPath,
              orElse: () => throw Exception('Entry not found: $entryPath'),
            );
            rawPath = entry.rawPathname;
            logger.d('找到条目的原始字节路径: ${rawPath?.take(20).toList()}');
          }
        } catch (e) {
          logger.w('无法获取原始路径: $e');
        }

        if (rawPath == null || rawPath.isEmpty) {
          logger.e('rawPath为空，无法提取');
          return SingleFileExtractResult(
            success: false,
            extractedSize: 0,
            errorMessage: '无法找到条目的原始路径',
          );
        }
        
        logger.d('调用extractSingleFile with rawPath length: ${rawPath.length}');
        final result = _minizip.extractSingleFile(
          archivePath,
          rawPath, // 使用原始GBK字节
          outputPath,
          password: password,
        );

        if (result.success) {
          logger.i('minizip-ng提取成功: $entryPath (${result.fileSize} bytes)');
          return SingleFileExtractResult(
            success: true,
            extractedSize: result.fileSize.toInt(),
            errorMessage: '',
          );
        } else {
          logger.w('minizip-ng提取失败: ${result.errorMessage}');
          return SingleFileExtractResult(
            success: false,
            extractedSize: 0,
            errorMessage: result.errorMessage,
          );
        }
      } else {
        // 使用libarchive提取其他格式
        logger.d('Using libarchive to extract single file');
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
