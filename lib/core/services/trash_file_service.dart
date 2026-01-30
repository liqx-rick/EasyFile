import 'dart:io';

import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/platform/mediastore_trash_channel.dart';
import 'package:easyfile/core/services/trash_file_cache_manager.dart';
import 'package:easyfile/data/models/trash_bin.dart';
import 'package:easyfile/data/models/trash_file_item.dart';
import 'package:easyfile/utils/file_size_formatter.dart';

/// 回收站扫描结果
class TrashScanResult {
  /// 发现的回收站列表
  final List<TrashBin> trashBins;

  /// 所有文件列表
  final List<TrashFileItem> allFiles;

  TrashScanResult({
    required this.trashBins,
    required this.allFiles,
  });
}

/// 回收站文件扫描服务
class TrashFileService {
  final TrashFileCacheManager _cacheManager = TrashFileCacheManager();
  bool _useMediaStore = false;

  TrashFileService();

  /// 初始化服务，检查MediaStore支持
  Future<void> initialize() async {
    _useMediaStore = await MediaStoreTrashChannel.isSupported();
    logger.i('回收站服务初始化: useMediaStore=$_useMediaStore');
  }

  /// 清除缓存（文件删除后调用）
  ///
  /// [keepSuppressionPeriods] 是否保留抑制期设置（清理后不想立即重新扫描时使用）
  Future<void> clearCache({bool keepSuppressionPeriods = false}) async {
    await _cacheManager.clearCache(keepSuppressionPeriods: keepSuppressionPeriods);
  }

  /// 获取缓存信息（调试用）
  Map<String, dynamic> getCacheInfo() {
    return _cacheManager.getCacheInfo();
  }

  /// 扫描回收站并返回分组结果（新版API，带缓存）
  ///
  /// 返回TrashScanResult，包含回收站列表和文件列表
  /// [onProgress] 进度回调 (当前进度, 总数, 当前路径)
  /// [forceRefresh] 强制刷新，忽略缓存
  Future<TrashScanResult> scanTrashBinsWithFiles({
    void Function(int current, int total, String path)? onProgress,
    bool forceRefresh = false,
  }) async {
    // 如果缓存有效且不强制刷新，直接返回缓存
    if (!forceRefresh && _cacheManager.isCacheValid()) {
      final cached = _cacheManager.getCachedResult()!;
      logger.i('使用系统回收站缓存数据（${cached.allFiles.length}个文件）');
      return cached;
    }

    logger.i('========== 开始扫描回收站（多回收站模式） ==========');

    final Map<String, List<TrashFileItem>> trashBinFiles = {};
    final Map<String, String> trashBinPaths = {};

    // 定义回收站搜索关键字
    final keywords = [
      'recycle',
      'Recycle',
      'RECYCLE',
      'trash',
      'Trash',
      'TRASH',
      'delete',
      'deleted',
      'Deleted',
      '.Trash',
      '.trash',
      'bin',
      'bins',
    ];

    final storageRoot = '/storage/emulated/0';

    // 1. 扫描预定义的回收站位置（各厂商实现）
    final knownTrashPaths = [
      // 华为/荣耀系统回收站
      '$storageRoot/.RecycleBinHW',
      '$storageRoot/.\$Trash\$',
      '$storageRoot/.File_Recycle',

      // 小米/MIUI
      '$storageRoot/.trashcan',
      '$storageRoot/MIUI/.recycle',

      // OPPO/ColorOS
      '$storageRoot/.com.coloros.filemanager/.Trash',
      '$storageRoot/.FileRecycleBin',

      // vivo/OriginOS
      '$storageRoot/.vivo_filemanager_recycle',

      // 三星/OneUI
      '$storageRoot/.Trash',
      '$storageRoot/.recycle',

      // 通用
      '$storageRoot/.RecyclerBin',
      '$storageRoot/.recycleBin',

      // 荣耀/华为相册回收站
      '$storageRoot/Pictures/.Gallery2/recycle/bins',
    ];

    logger.i('扫描 ${knownTrashPaths.length} 个已知回收站位置');

    for (final trashPath in knownTrashPaths) {
      final dir = Directory(trashPath);
      if (dir.existsSync()) {
        final binId = TrashBin.generateId(trashPath);
        logger.i('✓ 发现回收站: $trashPath (ID: $binId)');

        trashBinPaths[binId] = trashPath;
        trashBinFiles[binId] = [];

        onProgress?.call(0, 1, trashPath);

        // 特殊处理相册回收站的子目录结构
        if (trashPath.contains('.Gallery2') && trashPath.endsWith('/bins')) {
          try {
            final subDirs = dir.listSync(recursive: false);
            for (final subDir in subDirs) {
              if (subDir is Directory) {
                await _scanTrashDirectory(
                  subDir,
                  results: trashBinFiles[binId]!,
                  trashBinId: binId,
                );
              }
            }
          } catch (e) {
            logger.e('扫描相册回收站子目录失败: $e');
          }
        } else {
          // 普通回收站直接扫描
          await _scanTrashDirectory(
            dir,
            results: trashBinFiles[binId]!,
            trashBinId: binId,
          );
        }
      }
    }

    // 2. 动态搜索：在DCIM、Pictures、Android/data下搜索包含关键字的目录
    final searchPaths = [
      '$storageRoot/DCIM',
      '$storageRoot/Pictures',
      '$storageRoot/Android/data',
      '$storageRoot/Android/media',
    ];

    logger.i('动态搜索回收站目录: ${searchPaths.length} 个路径');

    for (int i = 0; i < searchPaths.length; i++) {
      final searchPath = searchPaths[i];
      final searchDir = Directory(searchPath);
      if (!searchDir.existsSync()) continue;

      // 通知UI正在搜索
      onProgress?.call(i + 1, searchPaths.length, searchPath);

      try {
        // 使用异步流式API代替同步listSync，避免阻塞UI
        int processedCount = 0;
        await for (final entity in searchDir.list(recursive: true, followLinks: false)) {
          if (entity is! Directory) continue;

          // 每处理100个条目让出控制权，让UI有机会更新
          processedCount++;
          if (processedCount % 100 == 0) {
            await Future.delayed(Duration.zero);
          }

          final dirPath = entity.path;
          final dirName = dirPath.split('/').last;

          // 检查是否匹配关键字
          bool matches = false;
          for (final keyword in keywords) {
            if (dirName.toLowerCase().contains(keyword.toLowerCase())) {
              matches = true;
              break;
            }
          }

          if (!matches) continue;

          // 避免重复添加
          final binId = TrashBin.generateId(dirPath);
          if (trashBinPaths.containsKey(binId)) continue;

          logger.i('✓ 动态发现回收站: $dirPath (ID: $binId)');
          trashBinPaths[binId] = dirPath;
          trashBinFiles[binId] = [];

          onProgress?.call(0, 1, dirPath);

          await _scanTrashDirectory(
            entity,
            results: trashBinFiles[binId]!,
            trashBinId: binId,
          );
        }
      } catch (e) {
        logger.e('搜索 $searchPath 失败: $e');
      }
    }

    // 3. 构建TrashBin对象列表
    final trashBins = <TrashBin>[];
    final allFiles = <TrashFileItem>[];
    final seenFilePaths = <String>{}; // 用于去重

    for (final entry in trashBinPaths.entries) {
      final binId = entry.key;
      final binPath = entry.value;
      final files = trashBinFiles[binId] ?? [];

      if (files.isEmpty) {
        logger.d('跳过空回收站: $binPath');
        continue;
      }

      final totalSize = files.fold<int>(0, (sum, f) => sum + f.size);

      final trashBin = TrashBin(
        id: binId,
        path: binPath,
        name: TrashBin.generateFriendlyName(binPath),
        type: TrashBin.determineType(binPath),
        fileCount: files.length,
        totalSize: totalSize,
      );

      trashBins.add(trashBin);

      // 去重添加文件：只添加未见过的文件路径
      int duplicateCount = 0;
      for (final file in files) {
        if (seenFilePaths.add(file.path)) {
          allFiles.add(file);
        } else {
          duplicateCount++;
        }
      }

      if (duplicateCount > 0) {
        logger.w('回收站 [${trashBin.name}] 检测到 $duplicateCount 个重复文件（已去重）');
      }

      logger.i('回收站 [${trashBin.name}]: ${files.length} 个文件, ${FileSizeFormatter.formatBytes(totalSize)}');
    }

    logger.i('========================================');
    logger.i('扫描完成: 发现 ${trashBins.length} 个回收站, 共 ${allFiles.length} 个文件');
    logger.i('总大小: ${FileSizeFormatter.formatBytes(allFiles.fold<int>(0, (sum, f) => sum + f.size))}');
    logger.i('========================================');

    final result = TrashScanResult(
      trashBins: trashBins,
      allFiles: allFiles,
    );

    // 缓存结果
    _cacheManager.saveCache(result);

    return result;
  }

  // _scanTrashFiles() 方法已删除（旧方案残留）
  // 请使用 scanTrashBinsWithFiles() 代替

  /// 判断文件是否需要进行文件头检测
  bool _shouldDetectMimeType(String fileName) {
    final lowerName = fileName.toLowerCase();

    // 1. 特殊扩展名（厂商加密文件）
    final specialExtensions = [
      '.hndgp', // 荣耀相册
      '.tmp', // 临时文件可能被重命名
      '.bak', // 备份文件可能被重命名
    ];

    for (final ext in specialExtensions) {
      if (lowerName.endsWith(ext)) {
        return true;
      }
    }

    // 2. 无扩展名的文件
    if (!fileName.contains('.') || fileName.startsWith('.')) {
      return true;
    }

    // 3. 长字符串文件名（可能是加密/哈希命名）
    // 例如：f20040d3a88f40d16eb35276395c19c2
    final namePart = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;

    // 如果文件名是32位或40位十六进制字符串（可能是MD5/SHA1哈希）
    if (namePart.length >= 32 && RegExp(r'^[a-f0-9]+$').hasMatch(namePart)) {
      return true;
    }

    // 4. 华为回收站目录下的所有文件（通常都被重命名）
    // 这个由路径判断，暂时不在这里处理

    return false;
  }

  /// 根据文件内容检测MIME类型（增强版）
  Future<String?> _detectMimeTypeFromContent(File file) async {
    try {
      // 读取文件头32字节（足够识别大多数格式）
      final bytes = await file.openRead(0, 32).first;

      // JPEG: FF D8 FF
      if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return 'image/jpeg';
      }

      // PNG: 89 50 4E 47
      if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        return 'image/png';
      }

      // GIF: GIF8
      if (bytes.length >= 4 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
        return 'image/gif';
      }

      // WebP: RIFF....WEBP
      if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
        final format = String.fromCharCodes(bytes.sublist(8, 12));
        if (format == 'WEBP') {
          return 'image/webp';
        }
      }

      // MP4/MOV: ....ftyp
      if (bytes.length >= 8 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
        return 'video/mp4';
      }

      // AVI: RIFF....AVI
      if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
        final format = String.fromCharCodes(bytes.sublist(8, 11));
        if (format == 'AVI') {
          return 'video/x-msvideo';
        }
      }

      // PDF: %PDF
      if (bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
        return 'application/pdf';
      }

      // ZIP/APK: PK
      if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
        if (bytes[2] == 0x03 && bytes[3] == 0x04) {
          return 'application/zip'; // 可能是ZIP或APK
        }
      }

      // RAR: Rar!
      if (bytes.length >= 4 && bytes[0] == 0x52 && bytes[1] == 0x61 && bytes[2] == 0x72 && bytes[3] == 0x21) {
        return 'application/x-rar';
      }

      // 7Z: 7z
      if (bytes.length >= 6 &&
          bytes[0] == 0x37 &&
          bytes[1] == 0x7A &&
          bytes[2] == 0xBC &&
          bytes[3] == 0xAF &&
          bytes[4] == 0x27 &&
          bytes[5] == 0x1C) {
        return 'application/x-7z-compressed';
      }

      // MP3: ID3 or FF FB/FF F3
      if (bytes.length >= 3) {
        if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
          return 'audio/mpeg'; // ID3 tag
        }
        if (bytes[0] == 0xFF && (bytes[1] == 0xFB || bytes[1] == 0xF3 || bytes[1] == 0xF2)) {
          return 'audio/mpeg'; // MPEG frame
        }
      }

      // WAV: RIFF....WAVE
      if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
        final format = String.fromCharCodes(bytes.sublist(8, 12));
        if (format == 'WAVE') {
          return 'audio/wav';
        }
      }

      // OGG: OggS
      if (bytes.length >= 4 && bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53) {
        return 'audio/ogg';
      }

      // FLAC: fLaC
      if (bytes.length >= 4 && bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) {
        return 'audio/flac';
      }

      return null; // 无法识别
    } catch (e) {
      logger.d('检测文件类型失败: ${file.path}, $e');
      return null;
    }
  }

  /// 扫描回收站目录
  Future<void> _scanTrashDirectory(
    Directory dir, {
    required List<TrashFileItem> results,
    int depth = 0,
    String? trashBinId,
  }) async {
    // 深度限制（回收站通常不会太深）
    if (depth > 5) return;

    // 检查目录是否存在
    if (!dir.existsSync()) return;

    try {
      final entities = await dir.list().toList();

      for (final entity in entities) {
        try {
          final stat = await entity.stat();

          if (entity is File) {
            final fileName = entity.path.split('/').last;
            String? mimeType;

            // 智能检测文件类型：
            // 1. 无扩展名的文件
            // 2. .hndgp等特殊扩展名
            // 3. 华为回收站文件（通常是加密/重命名的）
            final needsDetection = _shouldDetectMimeType(fileName);

            if (needsDetection) {
              mimeType = await _detectMimeTypeFromContent(entity);
              if (mimeType != null) {
                logger.d('文件头检测: $fileName → $mimeType');
              }
            }

            // 添加文件
            results.add(TrashFileItem(
              name: fileName,
              path: entity.path,
              size: stat.size,
              modified: stat.modified,
              trashedTime: stat.modified, // 使用修改时间作为删除时间的近似值
              isDirectory: false,
              mimeType: mimeType, // 如果检测到真实类型，使用检测结果
              mimeTypeVerified: mimeType != null, // 标记是否通过文件头验证
              trashBinId: trashBinId, // 标记所属回收站
            ));
          } else if (entity is Directory) {
            // 递归扫描子目录
            await _scanTrashDirectory(
              entity,
              results: results,
              depth: depth + 1,
              trashBinId: trashBinId,
            );
          }
        } catch (e) {
          logger.d('扫描回收站文件失败: ${entity.path}, 错误: $e');
        }
      }
    } catch (e) {
      logger.d('扫描回收站目录失败: ${dir.path}, 错误: $e');
    }
  }

  /// 删除回收站文件
  Future<bool> deleteTrashFile(TrashFileItem item) async {
    try {
      // 优先使用MediaStore删除（如果有mediaStoreId）
      if (item.mediaStoreId != null) {
        logger.i('使用MediaStore删除文件, ID: ${item.mediaStoreId}');
        final success = await MediaStoreTrashChannel.deleteTrashedFile(item.mediaStoreId!);
        if (success) {
          logger.i('MediaStore删除成功');
          return true;
        } else {
          logger.w('MediaStore删除失败，尝试文件系统删除');
          // 继续尝试文件系统删除
        }
      }

      // 文件系统删除
      logger.i('使用文件系统删除: ${item.path}');
      if (item.isDirectory) {
        final dir = Directory(item.path);

        // 递归删除目录
        await dir.delete(recursive: true);
        logger.i('删除回收站文件夹: ${item.path}');
      } else {
        await File(item.path).delete();
        logger.i('删除回收站文件: ${item.path}');
      }
      return true;
    } catch (e) {
      logger.e('删除失败: ${item.path}, 错误: $e');
      return false;
    }
  }

  /// 批量删除
  Future<Map<String, dynamic>> deleteMultiple(List<TrashFileItem> items) async {
    // 分离MediaStore文件和普通文件
    final mediaStoreItems = items.where((item) => item.mediaStoreId != null).toList();
    final fileSystemItems = items.where((item) => item.mediaStoreId == null).toList();

    int success = 0;
    int failed = 0;
    int totalSize = 0;

    // 批量删除MediaStore文件
    if (mediaStoreItems.isNotEmpty) {
      try {
        final ids = mediaStoreItems.map((item) => item.mediaStoreId!).toList();
        final result = await MediaStoreTrashChannel.deleteMultipleTrashedFiles(ids);
        success += result['success'] as int;
        failed += result['failed'] as int;
        totalSize += mediaStoreItems.take(result['success'] as int).fold<int>(0, (sum, item) => sum + item.size);
        logger.i('MediaStore批量删除: 成功${result['success']}, 失败${result['failed']}');
      } catch (e) {
        logger.e('MediaStore批量删除失败: $e');
        failed += mediaStoreItems.length;
      }
    }

    // 文件系统逐个删除
    for (final item in fileSystemItems) {
      final result = await deleteTrashFile(item);
      if (result) {
        success++;
        totalSize += item.size;
      } else {
        failed++;
      }
    }

    return {
      'success': success,
      'failed': failed,
      'totalSize': totalSize,
      'formattedSize': FileSizeFormatter.formatBytes(totalSize),
    };
  }

  /// 删除指定回收站的所有文件
  ///
  /// [trashBinIds] 要清空的回收站ID列表
  /// [allFiles] 所有文件列表（用于过滤）
  Future<Map<String, dynamic>> deleteTrashBinFiles({
    required List<String> trashBinIds,
    required List<TrashFileItem> allFiles,
  }) async {
    logger.i('开始清空 ${trashBinIds.length} 个回收站');

    // 过滤出属于指定回收站的文件
    final filesToDelete =
        allFiles.where((file) => file.trashBinId != null && trashBinIds.contains(file.trashBinId)).toList();

    if (filesToDelete.isEmpty) {
      logger.i('选中的回收站为空，无需清空');
      return {
        'success': 0,
        'failed': 0,
        'totalSize': 0,
        'formattedSize': '0 B',
      };
    }

    logger.i('准备删除 ${filesToDelete.length} 个文件');
    return await deleteMultiple(filesToDelete);
  }

  /// 清空所有回收站
  Future<Map<String, dynamic>> emptyAllTrash() async {
    logger.i('开始清空所有回收站');

    // 优先使用MediaStore清空
    if (_useMediaStore) {
      try {
        logger.i('使用MediaStore清空回收站');
        final result = await MediaStoreTrashChannel.emptyTrash();
        logger.i('MediaStore清空回收站完成: 成功${result['success']}, 失败${result['failed']}');
        return result;
      } catch (e) {
        logger.e('MediaStore清空失败，降级到文件系统清空: $e');
        // 继续使用文件系统清空
      }
    }

    // 文件系统清空
    logger.i('使用文件系统清空回收站');
    final scanResult = await scanTrashBinsWithFiles();
    final allTrashFiles = scanResult.allFiles;

    if (allTrashFiles.isEmpty) {
      logger.i('回收站为空，无需清空');
      return {
        'success': 0,
        'failed': 0,
        'totalSize': 0,
        'formattedSize': '0 B',
      };
    }

    return await deleteMultiple(allTrashFiles);
  }

  /// 恢复单个文件
  ///
  /// [item] 要恢复的文件项
  /// 返回恢复结果：success, targetPath, message
  Future<Map<String, dynamic>> restoreFile(TrashFileItem item) async {
    try {
      logger.i('开始恢复文件: ${item.name}');
      logger.d('回收站路径: ${item.path}');
      logger.d('原始路径: ${item.originalPath ?? "(无)"}');

      final trashFile = File(item.path);

      if (!await trashFile.exists()) {
        logger.w('文件不存在: ${item.path}');
        return {
          'success': false,
          'message': '文件不存在',
        };
      }

      // 1. 确定目标路径
      String targetPath;
      if (item.originalPath != null && item.originalPath!.isNotEmpty) {
        targetPath = item.originalPath!;
        logger.d('尝试恢复到原始路径: $targetPath');

        // 检查原始目录是否存在，如果不存在则回退到上层目录
        final targetFile = File(targetPath);
        final targetDir = targetFile.parent;

        if (!await targetDir.exists()) {
          logger.w('原始目录不存在: ${targetDir.path}，尝试回退到上层目录');
          // 回退到上层目录
          final parentDir = targetDir.parent;
          if (await parentDir.exists()) {
            targetPath = '${parentDir.path}/${item.name}';
            logger.i('回退到上层目录: $targetPath');
          } else {
            // 上层目录也不存在，使用默认恢复路径
            logger.w('上层目录也不存在，使用默认恢复路径');
            targetPath = _getDefaultRestorePath(item);
          }
        } else {
          logger.d('原始目录存在，将恢复到: ${targetDir.path}');
        }
      } else {
        targetPath = _getDefaultRestorePath(item);
        logger.d('无原始路径信息，使用默认恢复路径: $targetPath');
      }

      // 2. 处理文件名冲突（自动重命名）
      targetPath = await _resolveFileConflict(targetPath);

      // 3. 确保目标目录存在
      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);

      // 4. 复制文件到目标位置
      await trashFile.copy(targetPath);
      logger.d('文件已复制到: $targetPath');

      // 5. 删除回收站中的文件
      await trashFile.delete();
      logger.i('✓ 文件恢复成功: ${item.name} → $targetPath');

      return {
        'success': true,
        'targetPath': targetPath,
        'message': '恢复成功',
      };
    } catch (e) {
      logger.e('恢复文件失败: ${item.path}, 错误: $e');
      return {
        'success': false,
        'message': '恢复失败: $e',
      };
    }
  }

  /// 批量恢复文件
  ///
  /// [items] 要恢复的文件列表
  Future<Map<String, dynamic>> restoreMultiple(List<TrashFileItem> items) async {
    logger.i('开始批量恢复 ${items.length} 个文件');

    int success = 0;
    int failed = 0;
    final errors = <String>[];
    final restoredPaths = <Map<String, String>>[]; // 记录恢复的文件和路径

    for (final item in items) {
      final result = await restoreFile(item);
      if (result['success'] == true) {
        success++;
        final targetPath = result['targetPath'] as String;
        // 从目标路径提取实际的文件名（恢复后的文件名）
        final restoredFileName = targetPath.split('/').last;
        restoredPaths.add({
          'fileName': restoredFileName, // 使用恢复后的文件名
          'targetPath': targetPath,
        });
      } else {
        failed++;
        errors.add('${item.name}: ${result['message']}');
      }
    }

    logger.i('批量恢复完成: 成功$success, 失败$failed');
    return {
      'success': success,
      'failed': failed,
      'errors': errors,
      'restoredPaths': restoredPaths, // 返回恢复路径信息
    };
  }

  /// 获取默认恢复路径
  ///
  /// 所有文件统一恢复到 EasyFile/Restored/ 目录
  String _getDefaultRestorePath(TrashFileItem item) {
    final basePath = '/storage/emulated/0/EasyFile/Restored';

    // 生成有意义的文件名（基于删除时间和文件类型）
    final fileName = _generateRestoreFileName(item);

    return '$basePath/$fileName';
  }

  /// 生成恢复文件名
  ///
  /// 根据MIME类型和删除时间生成有意义的文件名
  /// 例如：IMG_20251203_143012.jpg, VID_20251203_143012.mp4
  String _generateRestoreFileName(TrashFileItem item) {
    // 如果原始文件名看起来正常（不是编码的），直接使用
    final originalName = item.name;
    if (!_isEncodedFileName(originalName)) {
      return originalName;
    }

    // 根据MIME类型确定文件扩展名
    final extension = _getExtensionFromMimeType(item.mimeType);

    // 使用删除时间或修改时间生成时间戳
    final time = item.trashedTime ?? item.modified;
    final timestamp = '${time.year}${time.month.toString().padLeft(2, '0')}${time.day.toString().padLeft(2, '0')}_'
        '${time.hour.toString().padLeft(2, '0')}${time.minute.toString().padLeft(2, '0')}${time.second.toString().padLeft(2, '0')}';

    // 根据文件类型生成前缀
    String prefix;
    if (item.mimeType.startsWith('image/')) {
      prefix = 'IMG';
    } else if (item.mimeType.startsWith('video/')) {
      prefix = 'VID';
    } else if (item.mimeType.startsWith('audio/')) {
      prefix = 'AUD';
    } else if (item.mimeType.contains('pdf')) {
      prefix = 'DOC';
    } else {
      prefix = 'FILE';
    }

    return '${prefix}_$timestamp$extension';
  }

  /// 判断文件名是否是编码的（如华为相册的base32编码）
  bool _isEncodedFileName(String fileName) {
    // 华为相册回收站特征：
    // 1. 以.hndgp结尾
    // 2. 文件名很长且全是大写字母和数字
    if (fileName.toLowerCase().endsWith('.hndgp')) {
      return true;
    }

    // 文件名（去除扩展名）
    final nameWithoutExt = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;

    // 2. 十六进制哈希命名（MD5=32位, SHA1=40位, 华为回收站常见）
    // 例如: 3e7264548eaf463bbe6e01d6bb1b161e, f20040d3a88f40d16eb35276395c19c2
    if ((nameWithoutExt.length == 32 || nameWithoutExt.length == 40) &&
        RegExp(r'^[a-f0-9]+$').hasMatch(nameWithoutExt)) {
      return true; // 判定为哈希命名
    }

    // 3. 文件名超过40个字符且主要是大写字母，可能是编码的
    if (nameWithoutExt.length > 40) {
      final upperCount = nameWithoutExt.split('').where((c) => c == c.toUpperCase() && c != c.toLowerCase()).length;
      if (upperCount > nameWithoutExt.length * 0.8) {
        return true; // 80%以上是大写字母，判定为编码
      }
    }

    return false;
  }

  /// 根据MIME类型获取合适的文件扩展名
  String _getExtensionFromMimeType(String mimeType) {
    // ✅ 委托给 FileTypesConfig 统一管理
    return AppConfig.instance.fileTypes.getExtensionFromMimeType(mimeType);
  }

  /// 解决文件名冲突（自动重命名）
  ///
  /// 如果目标文件已存在，自动添加序号：file.jpg → file(1).jpg
  Future<String> _resolveFileConflict(String targetPath) async {
    final file = File(targetPath);
    if (!await file.exists()) {
      return targetPath; // 无冲突，直接返回
    }

    // 分离文件名和扩展名
    final dir = file.parent.path;
    final fileName = file.uri.pathSegments.last;
    final lastDotIndex = fileName.lastIndexOf('.');

    String baseName;
    String extension;
    if (lastDotIndex > 0) {
      baseName = fileName.substring(0, lastDotIndex);
      extension = fileName.substring(lastDotIndex); // 包含点号
    } else {
      baseName = fileName;
      extension = '';
    }

    // 尝试添加序号 (1), (2), (3)...
    int counter = 1;
    while (true) {
      final newFileName = '$baseName($counter)$extension';
      final newPath = '$dir/$newFileName';
      final newFile = File(newPath);

      if (!await newFile.exists()) {
        logger.d('文件名冲突，重命名为: $newFileName');
        return newPath;
      }

      counter++;
      if (counter > 100) {
        // 防止无限循环
        throw Exception('无法找到可用的文件名（尝试了100次）');
      }
    }
  }

  /// 获取旧文件统计（复用缓存）
  ///
  /// 统计指定月份前的文件
  /// [months] 月份数，如果不传则从配置文件读取 FileScanConfig.systemTrashOldFileMonths
  /// [forceRefresh] 强制刷新，忽略缓存
  Future<Map<String, dynamic>> getOldFilesStatistics({
    int? months,
    bool forceRefresh = false,
  }) async {
    // 从配置读取默认值，确保与配置保持一致
    final effectiveMonths = months ?? AppConfig.instance.fileScan.systemTrashOldFileMonths;
    logger.i('开始统计$effectiveMonths个月前的系统回收站文件');

    // 先尝试从缓存获取扫描结果
    TrashScanResult result;

    if (!forceRefresh && _cacheManager.isCacheValid()) {
      result = _cacheManager.getCachedResult()!;
      logger.i('使用缓存数据统计旧文件（避免重复扫描）');
    } else {
      logger.i('缓存无效，执行完整扫描');
      result = await scanTrashBinsWithFiles(forceRefresh: forceRefresh);
    }

    final cutoffDate = DateTime.now().subtract(Duration(days: effectiveMonths * 30));

    final oldFiles = result.allFiles.where((file) {
      final fileDate = file.trashedTime ?? file.modified;
      return fileDate.isBefore(cutoffDate);
    }).toList();

    final totalSize = oldFiles.fold<int>(0, (sum, f) => sum + f.size);

    // 查找最旧的文件日期
    DateTime? oldestFileDate;
    if (oldFiles.isNotEmpty) {
      oldestFileDate = oldFiles.first.trashedTime ?? oldFiles.first.modified;
      for (final file in oldFiles) {
        final fileDate = file.trashedTime ?? file.modified;
        if (fileDate.isBefore(oldestFileDate!)) {
          oldestFileDate = fileDate;
        }
      }
    }

    logger.i('统计完成: ${oldFiles.length}个文件, ${FileSizeFormatter.formatBytes(totalSize)}');

    return {
      'count': oldFiles.length,
      'size': totalSize,
      'sizeMB': (totalSize / (1024 * 1024)).round(),
      'cutoffDate': cutoffDate,
      'oldestFileDate': oldestFileDate, // 最旧文件的实际日期
      'files': oldFiles,
      'scanResult': result, // 返回完整扫描结果，供页面使用
    };
  }
}
