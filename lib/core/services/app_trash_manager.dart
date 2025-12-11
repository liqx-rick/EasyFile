import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/database/app_trash_database.dart';
import 'package:easyfile/core/settings/app_trash_settings.dart';
import 'package:easyfile/data/models/app_trash_item.dart';
import 'package:easyfile/data/models/file_item.dart';

/// EasyFile回收站管理服务
/// 
/// 负责文件的删除、恢复、清理等核心功能
/// 
/// 软删除机制：
/// 1. 用户删除 → 立即标记为deleted (DB) → UI立即刷新
/// 2. 后台队列异步移动文件到回收站
/// 3. 定期清理过期文件
class AppTrashManager {
  // 回收站目录（隐藏目录，不会被扫描）
  static const String trashDir = '/data/data/com.guangqi.easyfile/.trash';

  final AppTrashDatabase _database;
  final AppTrashSettings _settings;
  final Uuid _uuid = const Uuid();

  // 后台移动队列
  final Queue<AppTrashItem> _moveQueue = Queue<AppTrashItem>();
  bool _isProcessingQueue = false;

  AppTrashManager({
    required AppTrashDatabase database,
    required AppTrashSettings settings,
  })  : _database = database,
        _settings = settings;

  // ==================== 初始化 ====================

  /// 初始化回收站服务
  Future<void> initialize() async {
    try {
      // 确保回收站目录存在
      final dir = Directory(trashDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        logger.i('Created trash directory: $trashDir');
      }

      // 恢复未完成的移动任务
      await _recoverPendingMoves();

      // 执行一次启动时清理
      await cleanExpiredFiles();

      logger.i('AppTrashManager initialized');
    } catch (e) {
      logger.e('Failed to initialize AppTrashManager: $e');
      rethrow;
    }
  }

  /// 恢复应用重启前未完成的移动任务
  Future<void> _recoverPendingMoves() async {
    try {
      final pendingFiles = await _database.getPendingFiles();
      if (pendingFiles.isNotEmpty) {
        logger.i('Found ${pendingFiles.length} pending moves, resuming...');
        _moveQueue.addAll(pendingFiles);
        _processQueue();
      }
    } catch (e) {
      logger.e('Failed to recover pending moves: $e');
    }
  }

  // ==================== 核心功能：软删除（标记+后台移动） ====================

  /// 标记文件为已删除（立即返回，后台移动）
  /// 
  /// 这是用户删除操作的入口点：
  /// 1. 立即在数据库标记文件为deleted
  /// 2. 加入后台移动队列
  /// 3. 立即返回（UI可以刷新）
  Future<List<String>> markFilesAsDeleted(List<FileItem> files) async {
    try {
      final trashItems = <AppTrashItem>[];
      
      for (final file in files) {
        final id = _uuid.v4();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = path.basename(file.path);
        final trashPath = '$trashDir/${timestamp}_$fileName';
        
        // 文件夹使用 inode/directory MIME类型
        final mimeType = file.isDirectory ? 'inode/directory' : _inferMimeType(fileName);
        
        final trashItem = AppTrashItem(
          id: id,
          trashPath: trashPath,
          originalPath: file.path,
          fileName: fileName,
          size: file.size,
          mimeType: mimeType,
          deletedAt: DateTime.now(),
        );
        
        trashItems.add(trashItem);
      }
      
      // 批量标记为待删除
      final ids = await _database.markBatchAsDeleted(trashItems);
      
      // 加入后台移动队列
      _moveQueue.addAll(trashItems);
      
      // 触发队列处理（异步，不阻塞）
      _processQueue();
      
      logger.i('Marked ${files.length} files as deleted, added to move queue');
      return ids;
    } catch (e) {
      logger.e('Failed to mark files as deleted: $e');
      rethrow;
    }
  }

  /// 处理后台移动队列
  /// 
  /// 异步处理文件移动操作，不阻塞UI线程
  /// - 使用串行处理避免并发冲突
  /// - 单个文件失败不影响队列继续
  /// - 失败的文件标记为failed状态，可后续重试
  Future<void> _processQueue() async {
    // 防止并发处理和空队列处理
    if (_isProcessingQueue || _moveQueue.isEmpty) return;
    
    _isProcessingQueue = true;
    
    try {
      while (_moveQueue.isNotEmpty) {
        final item = _moveQueue.removeFirst();
        
        try {
          // 执行实际的文件移动
          await _moveFileToTrash(item);
          
          // 更新状态为已移动
          await _database.updateStatusMoved(item.id);
          
          logger.d('Successfully moved to trash: ${item.originalPath}');
        } catch (e) {
          logger.e('Failed to move ${item.originalPath}: $e');
          
          // 标记为失败，将来可以重试
          await _database.updateStatusFailed(item.id);
          
          // 继续处理下一个文件，不中断队列
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  /// 实际执行文件移动到回收站
  /// 
  /// 智能处理跨分区移动：
  /// 1. 优先使用rename（同分区，速度快）
  /// 2. 跨分区时自动fallback到copy+delete
  /// 3. 其他错误直接抛出
  Future<void> _moveFileToTrash(AppTrashItem item) async {
    // 判断是文件还是文件夹
    final isDirectory = await FileSystemEntity.isDirectory(item.originalPath);
    
    // 确保源文件/文件夹存在
    if (isDirectory) {
      final sourceDir = Directory(item.originalPath);
      if (!await sourceDir.exists()) {
        logger.w('Source directory not found, skipping: ${item.originalPath}');
        return;
      }
    } else {
      final sourceFile = File(item.originalPath);
      if (!await sourceFile.exists()) {
        logger.w('Source file not found, skipping: ${item.originalPath}');
        return;
      }
    }
    
    try {
      // 尝试快速重命名（同分区，原子操作）
      if (isDirectory) {
        await Directory(item.originalPath).rename(item.trashPath);
      } else {
        await File(item.originalPath).rename(item.trashPath);
      }
    } on FileSystemException catch (e) {
      // EXDEV错误码18表示跨分区，需要复制后删除
      if (e.osError?.errorCode == 18) {
        if (isDirectory) {
          await _copyDirectoryRecursive(item.originalPath, item.trashPath);
          await Directory(item.originalPath).delete(recursive: true);
        } else {
          await File(item.originalPath).copy(item.trashPath);
          await File(item.originalPath).delete();
        }
      } else {
        rethrow;
      }
    }
  }

  // ==================== 核心功能：删除（保留旧接口兼容性） ====================

  /// 移动文件到回收站
  /// 
  /// [file] 要删除的文件
  /// [onProgress] 进度回调（0.0-1.0），用于大文件
  /// 
  /// 返回是否成功
  Future<bool> moveToTrash(
    FileItem file, {
    Function(double progress)? onProgress,
  }) async {
    try {
      // 生成唯一ID和回收站路径
      final id = _uuid.v4();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = path.basename(file.path);
      final trashPath = '$trashDir/${timestamp}_$fileName';

      logger.i('Moving to trash: ${file.path} → $trashPath');

      // 检查文件大小，决定是否显示进度
      final showProgress = file.size > 10 * 1024 * 1024; // >10MB

      // 策略1: 尝试快速rename（同一分区）
      try {
        if (file.isDirectory) {
          // 文件夹使用 Directory.rename
          await Directory(file.path).rename(trashPath);
        } else {
          // 文件使用 File.rename
          await File(file.path).rename(trashPath);
        }
        logger.d('✅ Quick rename succeeded');
      } on FileSystemException catch (e) {
        // 跨分区错误，降级到复制+删除
        if (e.message.contains('Cross-device') || e.osError?.errorCode == 18) {
          logger.d('⚠️ Cross-partition detected, using copy+delete');

          if (file.isDirectory) {
            // 文件夹：递归复制整个目录树
            await _copyDirectoryRecursive(file.path, trashPath);
            // 删除原文件夹
            await Directory(file.path).delete(recursive: true);
          } else {
            if (showProgress && onProgress != null) {
              // 大文件：带进度的复制
              await _copyFileWithProgress(
                file.path,
                trashPath,
                file.size,
                onProgress,
              );
            } else {
              // 小文件：直接复制
              await File(file.path).copy(trashPath);
            }
            // 删除原文件
            await File(file.path).delete();
          }
          logger.d('✅ Copy+delete completed');
        } else {
          // 其他错误，抛出
          rethrow;
        }
      }

      // 保存元数据到数据库
      // 文件夹使用 inode/directory MIME类型
      final mimeType = file.isDirectory ? 'inode/directory' : _inferMimeType(fileName);
      
      final trashItem = AppTrashItem(
        id: id,
        trashPath: trashPath,
        originalPath: file.path,
        fileName: fileName,
        size: file.size,
        mimeType: mimeType,
        deletedAt: DateTime.now(),
      );

      await _database.insert(trashItem);

      logger.i('✅ File moved to trash successfully: $fileName');
      return true;
    } catch (e) {
      logger.e('❌ Failed to move file to trash: $e');
      return false;
    }
  }

  /// 带进度的文件复制（分块读写）
  Future<void> _copyFileWithProgress(
    String sourcePath,
    String targetPath,
    int totalSize,
    Function(double progress) onProgress,
  ) async {
    final source = File(sourcePath);
    final target = File(targetPath);

    // 确保目标目录存在
    await target.parent.create(recursive: true);

    // 打开流
    final sourceStream = source.openRead();
    final targetSink = target.openWrite();

    int bytesWritten = 0;

    try {
      await for (final chunk in sourceStream) {
        targetSink.add(chunk);
        bytesWritten += chunk.length;

        // 回调进度
        final progress = totalSize > 0 ? bytesWritten / totalSize : 0.0;
        onProgress(progress);
      }

      await targetSink.flush();
      await targetSink.close();

      logger.d('Copy completed: $bytesWritten bytes');
    } catch (e) {
      await targetSink.close();
      // 清理失败的文件
      if (await target.exists()) {
        await target.delete();
      }
      rethrow;
    }
  }

  /// 递归复制文件夹到回收站
  Future<void> _copyDirectoryRecursive(String sourcePath, String targetPath) async {
    final sourceDir = Directory(sourcePath);
    final targetDir = Directory(targetPath);

    // 创建目标文件夹
    await targetDir.create(recursive: true);

    // 遍历源文件夹中的所有项
    await for (final entity in sourceDir.list(recursive: false)) {
      final name = path.basename(entity.path);
      final newPath = path.join(targetPath, name);

      if (entity is File) {
        // 复制文件
        await entity.copy(newPath);
      } else if (entity is Directory) {
        // 递归复制子文件夹
        await _copyDirectoryRecursive(entity.path, newPath);
      }
    }
  }

  // ==================== 核心功能：恢复 ====================

  /// 从回收站恢复文件
  /// 
  /// [item] 要恢复的文件项
  /// 
  /// 返回恢复结果：
  /// - success: 是否成功
  /// - targetPath: 实际恢复到的路径
  /// - isOriginalPath: 是否恢复到原位置
  /// - wasRenamed: 是否重命名了
  Future<Map<String, dynamic>> restoreFile(AppTrashItem item) async {
    try {
      logger.i('Restoring file: ${item.fileName} from ${item.trashPath}');

      // 判断是文件还是文件夹
      final isDirectory = await FileSystemEntity.isDirectory(item.trashPath);

      // 确定恢复目标路径
      final targetPath = await _determineRestorePath(item);
      final isOriginalPath = targetPath == item.originalPath;
      final wasRenamed = !isOriginalPath && 
                         path.dirname(targetPath) == path.dirname(item.originalPath);

      // 确保目标目录存在
      final targetDir = Directory(path.dirname(targetPath));
      await targetDir.create(recursive: true);

      // 移动文件/文件夹（同样的策略：rename或copy+delete）
      try {
        if (isDirectory) {
          await Directory(item.trashPath).rename(targetPath);
        } else {
          await File(item.trashPath).rename(targetPath);
        }
        logger.d('✅ Quick rename succeeded for restore');
      } on FileSystemException catch (e) {
        if (e.message.contains('Cross-device') || e.osError?.errorCode == 18) {
          logger.d('⚠️ Cross-partition, using copy+delete for restore');
          if (isDirectory) {
            await _copyDirectoryRecursive(item.trashPath, targetPath);
            await Directory(item.trashPath).delete(recursive: true);
          } else {
            await File(item.trashPath).copy(targetPath);
            await File(item.trashPath).delete();
          }
        } else {
          rethrow;
        }
      }

      // 从数据库删除记录
      await _database.delete(item.id);

      logger.i('✅ File restored successfully: ${item.fileName} → $targetPath');

      return {
        'success': true,
        'targetPath': targetPath,
        'isOriginalPath': isOriginalPath,
        'wasRenamed': wasRenamed,
      };
    } catch (e) {
      logger.e('❌ Failed to restore file: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 智能确定恢复路径
  Future<String> _determineRestorePath(AppTrashItem item) async {
    final originalPath = item.originalPath;
    final originalDir = path.dirname(originalPath);

    // 策略1: 优先原位置
    if (await Directory(originalDir).exists()) {
      // 原目录存在，检查文件名冲突
      if (await File(originalPath).exists()) {
        // 文件名冲突，自动重命名
        final uniquePath = _generateUniquePath(originalPath);
        logger.d('Original path occupied, using: $uniquePath');
        return uniquePath;
      }
      // 原位置可用
      return originalPath;
    }

    // 策略2: 降级到最近的存在的父目录
    String currentDir = originalDir;
    const storageRoot = '/storage/emulated/0';

    while (currentDir != storageRoot && currentDir != '/') {
      final parentDir = path.dirname(currentDir);
      if (await Directory(parentDir).exists()) {
        // 找到存在的父目录
        final fileName = path.basename(originalPath);
        final newPath = path.join(parentDir, fileName);
        logger.d('Original dir not found, using parent: $newPath');
        return _generateUniquePath(newPath);
      }
      currentDir = parentDir;
    }

    // 策略3: 兜底到默认恢复目录
    final defaultPath = _getDefaultRestorePath(item);
    logger.d('Using default restore path: $defaultPath');
    return _generateUniquePath(defaultPath);
  }

  /// 生成唯一路径（处理文件名冲突）
  String _generateUniquePath(String originalPath) {
    final dir = path.dirname(originalPath);
    final baseName = path.basenameWithoutExtension(originalPath);
    final extension = path.extension(originalPath);

    var counter = 1;
    var newPath = originalPath;

    while (File(newPath).existsSync()) {
      newPath = path.join(dir, '$baseName($counter)$extension');
      counter++;
    }

    return newPath;
  }

  /// 获取默认恢复目录
  String _getDefaultRestorePath(AppTrashItem item) {
    final defaultDir = AppTrashSettings.getDefaultRestorePath(item.mimeType);
    return path.join(defaultDir, item.fileName);
  }

  // ==================== 核心功能：永久删除 ====================

  /// 永久删除文件（不可恢复）
  Future<bool> deleteFilePermanently(AppTrashItem item) async {
    try {
      logger.i('Permanently deleting: ${item.fileName}');

      // 删除物理文件
      final file = File(item.trashPath);
      if (await file.exists()) {
        await file.delete();
      }

      // 删除数据库记录
      await _database.delete(item.id);

      logger.i('✅ File permanently deleted: ${item.fileName}');
      return true;
    } catch (e) {
      logger.e('❌ Failed to permanently delete file: $e');
      return false;
    }
  }

  /// 批量永久删除
  Future<Map<String, dynamic>> deleteBatchPermanently(
    List<AppTrashItem> items,
  ) async {
    int successCount = 0;
    int failedCount = 0;
    int totalSize = 0;

    for (final item in items) {
      final success = await deleteFilePermanently(item);
      if (success) {
        successCount++;
        totalSize += item.size;
      } else {
        failedCount++;
      }
    }

    logger.i('Batch delete completed: $successCount success, $failedCount failed');

    return {
      'success': successCount,
      'failed': failedCount,
      'totalSize': totalSize,
    };
  }

  // ==================== 核心功能：清空回收站 ====================

  /// 清空所有回收站文件
  Future<Map<String, dynamic>> emptyTrash() async {
    try {
      logger.i('Emptying trash...');

      // 获取所有文件
      final allItems = await _database.getAll();

      if (allItems.isEmpty) {
        return {
          'success': 0,
          'failed': 0,
          'totalSize': 0,
        };
      }

      // 批量删除
      return await deleteBatchPermanently(allItems);
    } catch (e) {
      logger.e('Failed to empty trash: $e');
      return {
        'success': 0,
        'failed': 0,
        'error': e.toString(),
      };
    }
  }

  // ==================== 自动清理 ====================

  /// 清理过期文件
  Future<Map<String, dynamic>> cleanExpiredFiles() async {
    try {
      final retentionDays = _settings.retentionDays;
      logger.i('Cleaning expired files (retention: $retentionDays days)...');

      // 获取过期文件
      final expiredItems = await _database.getExpired(retentionDays);

      if (expiredItems.isEmpty) {
        logger.d('No expired files found');
        return {
          'deleted': 0,
          'size': 0,
        };
      }

      // 删除过期文件
      final result = await deleteBatchPermanently(expiredItems);

      logger.i('Expired files cleaned: ${result['success']} files, ${result['totalSize']} bytes');

      return {
        'deleted': result['success'],
        'size': result['totalSize'],
      };
    } catch (e) {
      logger.e('Failed to clean expired files: $e');
      return {
        'deleted': 0,
        'size': 0,
        'error': e.toString(),
      };
    }
  }

  /// 启动自动清理任务（应用启动时调用）
  Future<void> startAutoCleanup() async {
    // 立即执行一次清理
    await cleanExpiredFiles();

    // TODO: 实现定期清理（每天检查一次）
    // 可以使用 flutter_background_service 或 workmanager 插件
  }

  // ==================== 查询功能 ====================

  /// 获取所有回收站文件
  Future<List<AppTrashItem>> getAllItems() async {
    return await _database.getAll();
  }

  /// 获取即将过期的文件
  Future<List<AppTrashItem>> getExpiringSoonItems() async {
    return await _database.getExpiringSoon(_settings.retentionDays);
  }

  /// 获取回收站统计信息
  Future<Map<String, dynamic>> getStatistics() async {
    final totalCount = await _database.getTotalCount();
    final totalSize = await _database.getTotalSize();
    final countByType = await _database.getCountByType();
    final retentionDays = _settings.retentionDays;

    return {
      'totalCount': totalCount,
      'totalSize': totalSize,
      'countByType': countByType,
      'retentionDays': retentionDays,
    };
  }

  // ==================== 辅助方法 ====================

  /// 根据文件名推断MIME类型
  String _inferMimeType(String fileName) {
    final ext = path.extension(fileName).toLowerCase().replaceFirst('.', '');

    // 图片
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic'].contains(ext)) {
      return 'image/$ext';
    }
    // 视频
    if (['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', '3gp'].contains(ext)) {
      return 'video/$ext';
    }
    // 音频
    if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'].contains(ext)) {
      return 'audio/$ext';
    }
    // 文档
    if (['pdf', 'doc', 'docx', 'txt'].contains(ext)) {
      return 'application/$ext';
    }
    // 压缩包
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return 'application/$ext';
    }

    return 'application/octet-stream';
  }
}
