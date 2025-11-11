import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:easyfile/core/logger.dart';

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
  
  /// 初始化缓存目录
  Future<void> init() async {
    if (_initialized) return;
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/media_thumbnails');
      
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
        logger.d('Thumbnail cache directory created: ${_cacheDir!.path}');
      }
      
      _initialized = true;
    } catch (e) {
      logger.e('Failed to initialize thumbnail cache: $e');
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
    
    try {
      final cacheFile = File(_getCacheFilePath(filePath));
      if (await cacheFile.exists()) {
        logger.d('Loading thumbnail from cache: $filePath');
        return await cacheFile.readAsBytes();
      }
    } catch (e) {
      logger.e('Failed to read cached thumbnail: $e');
    }
    return null;
  }
  
  /// 保存缩略图到缓存
  Future<void> saveCache(String filePath, Uint8List thumbnailData) async {
    if (!_initialized) await init();
    
    try {
      final cacheFile = File(_getCacheFilePath(filePath));
      await cacheFile.writeAsBytes(thumbnailData);
      logger.d('Thumbnail saved to cache: $filePath');
    } catch (e) {
      logger.e('Failed to save thumbnail to cache: $e');
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
