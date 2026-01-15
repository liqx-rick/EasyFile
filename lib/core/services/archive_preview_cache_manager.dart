import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../logger.dart';
import 'archive_service.dart';

/// 压缩包预览缓存管理器
class ArchivePreviewCacheManager {
  static const String _cacheDir = 'archive_preview';
  static const String _metaFileName = '.cache_meta.json';

  /// 获取缓存根目录
  static Future<Directory> _getCacheRoot() async {
    final cacheDir = await getTemporaryDirectory();
    final archiveCacheDir = Directory(path.join(cacheDir.path, _cacheDir));
    if (!await archiveCacheDir.exists()) {
      await archiveCacheDir.create(recursive: true);
    }
    return archiveCacheDir;
  }

  /// 计算压缩包的MD5哈希
  static String _getArchiveHash(String archivePath) {
    final bytes = utf8.encode(archivePath);
    return md5.convert(bytes).toString();
  }

  /// 获取压缩包的缓存目录
  static Future<Directory> _getArchiveCacheDir(String archivePath) async {
    final root = await _getCacheRoot();
    final hash = _getArchiveHash(archivePath);
    final dir = Directory(path.join(root.path, hash));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取元数据文件路径
  static Future<File> _getMetaFile(String archivePath) async {
    final cacheDir = await _getArchiveCacheDir(archivePath);
    return File(path.join(cacheDir.path, _metaFileName));
  }

  /// 读取元数据
  static Future<Map<String, dynamic>?> _readMeta(String archivePath) async {
    try {
      final metaFile = await _getMetaFile(archivePath);
      if (!await metaFile.exists()) {
        return null;
      }
      final content = await metaFile.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 写入元数据
  static Future<void> _writeMeta(String archivePath, Map<String, dynamic> meta) async {
    final metaFile = await _getMetaFile(archivePath);
    await metaFile.writeAsString(jsonEncode(meta));
  }

  /// 提取文件用于预览
  /// 返回缓存文件的路径，失败返回null并设置错误消息
  static Future<String?> extractForPreview({
    required String archivePath,
    required String entryPath,
    required void Function(String message) onError,
  }) async {
    try {
      // 1. 构建缓存文件路径
      final cacheDir = await _getArchiveCacheDir(archivePath);
      final cachedFilePath = path.join(cacheDir.path, entryPath);
      final cachedFile = File(cachedFilePath);

      // 2. 检查缓存是否存在
      if (await cachedFile.exists()) {
        // 缓存命中，直接返回
        return cachedFilePath;
      }

      // 3. 检查文件大小限制（从压缩包读取）
      final archiveService = ArchiveService();
      final listResult = await archiveService.listArchiveContents(archivePath);
      
      if (!listResult.success) {
        onError(listResult.errorMessage ?? '读取压缩包失败');
        return null;
      }

      final entry = listResult.entries.firstWhere(
        (e) => e.path == entryPath,
        orElse: () => throw Exception('Entry not found in archive'),
      );

      // 检查200MB限制
      final maxSizeBytes = AppConfig.instance.cacheConfig.archivePreviewMaxFileSizeMB * 1024 * 1024;
      if (entry.size > maxSizeBytes) {
        onError('文件过大（>${AppConfig.instance.cacheConfig.archivePreviewMaxFileSizeMB}MB）\n\n请解压整个压缩包后操作');
        return null;
      }

      // 4. 提取文件
      final result = await archiveService.extractSingleFileForPreview(
        archivePath,
        entryPath,
        cachedFilePath,
      );

      if (!result.success) {
        onError(result.errorMessage);
        return null;
      }

      // 5. 写入元数据
      final meta = await _readMeta(archivePath) ?? {};
      meta['createdAt'] = DateTime.now().toIso8601String();
      await _writeMeta(archivePath, meta);

      // 6. 触发缓存限制检查
      await _ensureCacheLimit();

      return cachedFilePath;
    } catch (e) {
      onError('提取文件失败: $e');
      return null;
    }
  }

  /// 确保缓存总大小不超过限制
  static Future<void> _ensureCacheLimit() async {
    try {
      final root = await _getCacheRoot();
      final maxSizeBytes = AppConfig.instance.cacheConfig.archivePreviewCacheSizeMB * 1024 * 1024;
      
      // 获取所有缓存目录及其大小和创建时间
      final cacheInfos = <Map<String, dynamic>>[];
      
      await for (final entity in root.list()) {
        if (entity is Directory) {
          final metaFile = File(path.join(entity.path, _metaFileName));
          DateTime createdAt = DateTime.now();
          
          if (await metaFile.exists()) {
            try {
              final meta = jsonDecode(await metaFile.readAsString());
              createdAt = DateTime.parse(meta['createdAt'] ?? DateTime.now().toIso8601String());
            } catch (_) {}
          }
          
          final size = await _getDirectorySize(entity);
          cacheInfos.add({
            'path': entity.path,
            'size': size,
            'createdAt': createdAt,
          });
        }
      }

      // 计算总大小
      final totalSize = cacheInfos.fold<int>(0, (sum, info) => sum + (info['size'] as int));
      
      if (totalSize <= maxSizeBytes) {
        return; // 未超过限制
      }

      // LRU清理：按创建时间排序（最旧的优先）
      cacheInfos.sort((a, b) => 
        (a['createdAt'] as DateTime).compareTo(b['createdAt'] as DateTime)
      );

      int currentSize = totalSize;
      for (final info in cacheInfos) {
        if (currentSize <= maxSizeBytes) {
          break;
        }
        
        final dir = Directory(info['path'] as String);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          currentSize -= info['size'] as int;
        }
      }
    } catch (e) {
      logger.e('Failed to ensure cache limit: $e');
    }
  }

  /// 计算目录大小
  static Future<int> _getDirectorySize(Directory dir) async {
    int totalSize = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return totalSize;
  }

  /// 清理过期缓存（7天）
  static Future<void> clearExpiredCache() async {
    try {
      final root = await _getCacheRoot();
      final expireDays = AppConfig.instance.cacheConfig.archivePreviewCacheExpireDays;
      final now = DateTime.now();

      await for (final entity in root.list()) {
        if (entity is Directory) {
          final metaFile = File(path.join(entity.path, _metaFileName));
          
          if (await metaFile.exists()) {
            try {
              final meta = jsonDecode(await metaFile.readAsString());
              final createdAt = DateTime.parse(meta['createdAt']);
              
              if (now.difference(createdAt).inDays >= expireDays) {
                await entity.delete(recursive: true);
              }
            } catch (_) {
              // 元数据损坏，删除整个目录
              await entity.delete(recursive: true);
            }
          } else {
            // 没有元数据，删除
            await entity.delete(recursive: true);
          }
        }
      }
    } catch (e) {
      logger.e('Failed to clear expired cache: $e');
    }
  }

  /// 清理所有缓存
  static Future<void> clearAllCache() async {
    try {
      final root = await _getCacheRoot();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (e) {
      logger.e('Failed to clear all cache: $e');
    }
  }

  /// 获取缓存总大小（字节）
  static Future<int> getCacheSize() async {
    try {
      final root = await _getCacheRoot();
      if (!await root.exists()) {
        return 0;
      }
      return await _getDirectorySize(root);
    } catch (e) {
      logger.e('Failed to get cache size: $e');
      return 0;
    }
  }
}
