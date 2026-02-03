import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:easyfile/core/logger.dart';
import 'package:path_provider/path_provider.dart';

/// 缩略图缓存管理器
///
/// 负责视频缩略图和音频封面的缓存管理
/// 使用文件系统缓存，通过MD5生成唯一键
class ThumbnailCacheManager {
  static final ThumbnailCacheManager _instance = ThumbnailCacheManager._internal();
  factory ThumbnailCacheManager() => _instance;
  ThumbnailCacheManager._internal();

  Directory? _cacheDir;
  bool _initialized = false;
  int _initAttempts = 0;
  static const int _maxInitAttempts = 3;

  /// 初始化缓存目录
  Future<void> init() async {
    // 如果已经初始化成功，直接返回
    if (_initialized && _cacheDir != null) return;

    // 如果已经尝试多次失败，不再重试
    if (_initAttempts >= _maxInitAttempts) {
      logger.w('Thumbnail cache initialization failed after $_initAttempts attempts, giving up');
      return;
    }

    _initAttempts++;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/media_thumbnails');

      logger
          .d('Attempting to initialize thumbnail cache (attempt $_initAttempts/$_maxInitAttempts): ${_cacheDir!.path}');

      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
        logger.d('Thumbnail cache directory created: ${_cacheDir!.path}');
      } else {
        logger.d('Thumbnail cache directory already exists: ${_cacheDir!.path}');
      }

      // 验证目录是否可写
      final testFile = File('${_cacheDir!.path}/.test_${DateTime.now().millisecondsSinceEpoch}');
      try {
        await testFile.writeAsString('test', flush: true);
        final content = await testFile.readAsString();
        await testFile.delete();

        if (content != 'test') {
          throw Exception('Write verification failed: content mismatch');
        }

        logger.d('Thumbnail cache directory is writable and verified');
      } catch (e) {
        logger.e('Thumbnail cache directory is not writable: $e');
        logger.e('Test file path: ${testFile.path}');
        _cacheDir = null;
        _initialized = false;
        return;
      }

      _initialized = true;
      logger.i('Thumbnail cache initialized successfully: ${_cacheDir!.path} (attempt $_initAttempts)');
    } catch (e, stackTrace) {
      logger.e('Failed to initialize thumbnail cache (attempt $_initAttempts/$_maxInitAttempts): $e');
      logger.e('Stack trace: $stackTrace');
      _cacheDir = null;
      _initialized = false;
    }
  }

  /// 生成缓存键（使用文件路径的 MD5）
  String _getCacheKey(String filePath) {
    final bytes = utf8.encode(filePath);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// 获取缓存文件路径
  String _getCacheFilePath(String filePath, {String extension = 'jpg'}) {
    final key = _getCacheKey(filePath);
    return '${_cacheDir!.path}/$key.$extension';
  }

  /// 检查缓存是否存在
  Future<bool> hasCached(String filePath) async {
    if (!_initialized) await init();

    final cacheFile = File(_getCacheFilePath(filePath));
    return await cacheFile.exists();
  }

  /// 获取缓存的缩略图
  Future<Uint8List?> getCached(String filePath) async {
    if (!_initialized) await init();

    // 如果缓存目录未初始化，直接返回
    if (_cacheDir == null) {
      return null;
    }

    try {
      final cacheFile = File(_getCacheFilePath(filePath));
      if (await cacheFile.exists()) {
        final fileSize = await cacheFile.length();

        // 检查文件是否为空或过小
        if (fileSize == 0) {
          logger.w('Cached thumbnail is empty (0 bytes), deleting: $filePath');
          await cacheFile.delete();
          return null;
        }

        if (fileSize < 100) {
          logger.w('Cached thumbnail too small ($fileSize bytes), possibly corrupted, deleting: $filePath');
          await cacheFile.delete();
          return null;
        }

        // 性能优化：移除滚动时频繁触发的日志输出
        // logger.d('Loading thumbnail from cache: $filePath ($fileSize bytes)');
        return await cacheFile.readAsBytes();
      }
    } catch (e) {
      logger.e('Failed to read cached thumbnail: $e');
    }
    return null;
  }

  /// 保存缩略图到缓存
  Future<bool> saveCache(String filePath, Uint8List thumbnailData) async {
    // 尝试初始化（如果未初始化或初始化失败）
    if (!_initialized || _cacheDir == null) {
      await init();
    }

    // 验证缓存目录是否正常初始化
    if (_cacheDir == null || !_initialized) {
      // 如果普通初始化失败，尝试强制重新初始化一次
      logger.w('Cache directory not initialized, attempting force reinitialization...');
      final success = await forceReinitialize();

      if (!success) {
        logger.e('Cache directory not initialized after force reinitialization, cannot save thumbnail');
        logger.e('File path: $filePath');
        logger.e('_initialized: $_initialized, _cacheDir: $_cacheDir, _initAttempts: $_initAttempts');
        return false;
      }

      logger.i('Force reinitialization successful, proceeding with cache save');
    }

    // 验证数据有效性：防止保存空数据
    if (thumbnailData.isEmpty) {
      logger.w('Cannot save empty thumbnail data for: $filePath');
      return false;
    }

    // 验证数据大小：至少应该有一些字节（JPEG头部至少需要几百字节）
    if (thumbnailData.length < 100) {
      logger.w('Thumbnail data too small (${thumbnailData.length} bytes), possibly corrupted: $filePath');
      return false;
    }

    try {
      final cacheFile = File(_getCacheFilePath(filePath));

      // 确保父目录存在
      final parentDir = cacheFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      await cacheFile.writeAsBytes(thumbnailData, flush: true);

      // 验证写入是否成功
      final writtenSize = await cacheFile.length();
      if (writtenSize != thumbnailData.length) {
        logger.e('Thumbnail write incomplete: expected ${thumbnailData.length} bytes, got $writtenSize bytes');
        await cacheFile.delete(); // 删除不完整的文件
        return false;
      }

      logger.d('Thumbnail saved to cache: $filePath (${thumbnailData.length} bytes)');
      return true;
    } catch (e, stackTrace) {
      logger.e('Failed to save thumbnail to cache: $e');
      logger.e('File path: $filePath');
      logger.e('Cache file path: ${_getCacheFilePath(filePath)}');
      logger.e('Stack trace: $stackTrace');
      return false;
    }
  }

  /// 清理缓存
  Future<void> clearCache() async {
    if (!_initialized) await init();

    try {
      if (_cacheDir != null && await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
        logger.d('Thumbnail cache cleared');
      }
    } catch (e) {
      logger.e('Failed to clear thumbnail cache: $e');
    }
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    if (!_initialized) await init();

    try {
      int totalSize = 0;
      await for (final entity in _cacheDir!.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      logger.e('Failed to calculate cache size: $e');
      return 0;
    }
  }

  /// 获取缓存文件数量
  Future<int> getCacheCount() async {
    if (!_initialized) await init();

    try {
      int count = 0;
      await for (final entity in _cacheDir!.list()) {
        if (entity is File) {
          count++;
        }
      }
      return count;
    } catch (e) {
      logger.e('Failed to count cache files: $e');
      return 0;
    }
  }

  /// 诊断缓存状态
  ///
  /// 返回缓存系统的详细状态信息
  Future<Map<String, dynamic>> diagnoseCache() async {
    final result = <String, dynamic>{};

    try {
      result['initialized'] = _initialized;
      result['initAttempts'] = _initAttempts;
      result['maxInitAttempts'] = _maxInitAttempts;
      result['cacheDirNull'] = _cacheDir == null;

      if (_cacheDir != null) {
        result['cacheDirPath'] = _cacheDir!.path;
        result['cacheDirExists'] = await _cacheDir!.exists();

        if (await _cacheDir!.exists()) {
          // 测试写入权限
          final testFile = File('${_cacheDir!.path}/.diagnostic_test_${DateTime.now().millisecondsSinceEpoch}');
          try {
            await testFile.writeAsString('diagnostic test', flush: true);
            result['writable'] = true;
            await testFile.delete();
          } catch (e) {
            result['writable'] = false;
            result['writeError'] = e.toString();
          }

          // 获取缓存统计
          result['cacheSize'] = await getCacheSize();
          result['cacheCount'] = await getCacheCount();
        }
      }

      // 获取应用文档目录信息
      try {
        final appDir = await getApplicationDocumentsDirectory();
        result['appDocDir'] = appDir.path;
        result['appDocDirExists'] = await appDir.exists();
      } catch (e) {
        result['appDocDirError'] = e.toString();
      }

      logger.i('Cache diagnosis: $result');
    } catch (e) {
      logger.e('Failed to diagnose cache: $e');
      result['diagnosisError'] = e.toString();
    }

    return result;
  }

  /// 强制重新初始化缓存
  ///
  /// 用于修复缓存系统问题
  Future<bool> forceReinitialize() async {
    logger.w('Force reinitializing thumbnail cache...');

    _initialized = false;
    _cacheDir = null;
    _initAttempts = 0;

    await init();

    if (_initialized && _cacheDir != null) {
      logger.i('Force reinitialization successful');
      return true;
    } else {
      logger.e('Force reinitialization failed');
      return false;
    }
  }

  /// 删除单个缓存
  Future<void> deleteCached(String filePath) async {
    if (!_initialized) await init();

    try {
      final cacheFile = File(_getCacheFilePath(filePath));
      if (await cacheFile.exists()) {
        await cacheFile.delete();
        logger.d('Deleted cached thumbnail: $filePath');
      }
    } catch (e) {
      logger.e('Failed to delete cached thumbnail: $e');
    }
  }

  /// 清理损坏的缓存文件（0B或过小的文件）
  ///
  /// 返回清理的文件数量
  Future<int> cleanupCorruptedCache() async {
    if (!_initialized) await init();

    if (_cacheDir == null || !await _cacheDir!.exists()) {
      return 0;
    }

    int cleanedCount = 0;
    try {
      await for (final entity in _cacheDir!.list()) {
        if (entity is File) {
          try {
            final fileSize = await entity.length();

            // 删除空文件或过小的文件（可能损坏）
            if (fileSize == 0) {
              logger.d('Deleting empty cache file: ${entity.path}');
              await entity.delete();
              cleanedCount++;
            } else if (fileSize < 100) {
              logger.d('Deleting corrupted cache file (${fileSize}B): ${entity.path}');
              await entity.delete();
              cleanedCount++;
            }
          } catch (e) {
            logger.w('Failed to check/delete cache file ${entity.path}: $e');
          }
        }
      }

      if (cleanedCount > 0) {
        logger.i('Cleaned up $cleanedCount corrupted cache files');
      }
    } catch (e) {
      logger.e('Failed to cleanup corrupted cache: $e');
    }

    return cleanedCount;
  }

  /// 格式化缓存大小
  String formatCacheSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
