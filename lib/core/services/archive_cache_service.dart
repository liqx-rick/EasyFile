import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/file_item.dart';
import '../logger.dart';

/// 压缩包缓存服务
///
/// 提供压缩包扫描结果的缓存功能，减少重复扫描
class ArchiveCacheService {
  static const String _cacheKey = 'archive_scan_cache';
  static const String _timestampKey = 'archive_scan_timestamp';
  static const Duration _cacheExpiration = Duration(hours: 24); // 24小时过期

  /// 获取缓存的压缩包列表
  ///
  /// 返回null表示无缓存或缓存已过期
  Future<List<FileItem>?> getCachedArchiveList() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查缓存时间戳
      final timestampMs = prefs.getInt(_timestampKey);
      if (timestampMs == null) {
        logger.d('[ArchiveCacheService] 无缓存数据');
        return null;
      }

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);
      final now = DateTime.now();
      final age = now.difference(cacheTime);

      if (age > _cacheExpiration) {
        logger.d('[ArchiveCacheService] 缓存已过期 (${age.inMinutes}分钟前)');
        return null;
      }

      // 读取缓存数据
      final cacheJson = prefs.getString(_cacheKey);
      if (cacheJson == null) {
        return null;
      }

      final List<dynamic> jsonList = json.decode(cacheJson);
      final archiveList = jsonList
          .map((item) => FileItem(
                name: item['name'] as String,
                path: item['path'] as String,
                size: item['size'] as int,
                modified: DateTime.fromMillisecondsSinceEpoch(item['modified'] as int),
                isDirectory: item['isDirectory'] as bool? ?? false,
              ))
          .toList();

      logger.i('[ArchiveCacheService] 使用缓存数据: ${archiveList.length}个压缩包 (${age.inMinutes}分钟前)');
      return archiveList;
    } catch (e) {
      logger.e('[ArchiveCacheService] 读取缓存失败: $e');
      return null;
    }
  }

  /// 保存压缩包列表到缓存
  Future<void> saveArchiveListCache(List<FileItem> archiveList) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 序列化数据
      final jsonList = archiveList
          .map((file) => {
                'name': file.name,
                'path': file.path,
                'size': file.size,
                'modified': file.modified.millisecondsSinceEpoch,
                'isDirectory': file.isDirectory,
              })
          .toList();
      final cacheJson = json.encode(jsonList);

      // 保存缓存
      await prefs.setString(_cacheKey, cacheJson);
      await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);

      logger.i('[ArchiveCacheService] 缓存已保存: ${archiveList.length}个压缩包');
    } catch (e) {
      logger.e('[ArchiveCacheService] 保存缓存失败: $e');
    }
  }

  /// 清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_timestampKey);
      logger.i('[ArchiveCacheService] 缓存已清除');
    } catch (e) {
      logger.e('[ArchiveCacheService] 清除缓存失败: $e');
    }
  }
}
