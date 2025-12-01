import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 大文件扫描缓存管理器
class LargeFileCacheManager {
  static const String _cacheKey = 'large_file_scan_cache';
  static const String _configKey = 'large_file_scan_config';
  static const String _timestampKey = 'large_file_scan_timestamp';
  static const Duration _cacheExpiration = Duration(days: 7);

  /// 保存扫描结果到缓存
  Future<void> saveCache({
    required List<FileItem> files,
    required LargeFileScanConfig config,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 保存文件列表（转为简化的JSON格式）
      final filesJson = files
          .map((file) => {
                'name': file.name,
                'path': file.path,
                'size': file.size,
                'modified': file.modified.millisecondsSinceEpoch,
              })
          .toList();

      await prefs.setString(_cacheKey, jsonEncode(filesJson));
      await prefs.setString(_configKey, jsonEncode(config.toJson()));
      await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);

      logger.i('Large file cache saved: ${files.length} files');
    } catch (e) {
      logger.e('Failed to save large file cache: $e');
    }
  }

  /// 从缓存加载扫描结果
  Future<LargeFileScanCache?> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final filesJson = prefs.getString(_cacheKey);
      final configJson = prefs.getString(_configKey);
      final timestamp = prefs.getInt(_timestampKey);

      if (filesJson == null || configJson == null || timestamp == null) {
        logger.d('No cache found');
        return null;
      }

      final scanTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final age = DateTime.now().difference(scanTime);

      // 检查缓存是否过期
      if (age > _cacheExpiration) {
        logger.i('Cache expired (age: ${age.inDays} days), clearing...');
        await clearCache();
        return null;
      }

      // 解析文件列表
      final filesList = (jsonDecode(filesJson) as List)
          .map((json) => FileItem(
                name: json['name'] as String,
                path: json['path'] as String,
                size: json['size'] as int,
                modified: DateTime.fromMillisecondsSinceEpoch(
                    json['modified'] as int),
                isDirectory: false,
              ))
          .toList();

      // 解析配置
      final config = LargeFileScanConfig.fromJson(
          jsonDecode(configJson) as Map<String, dynamic>);

      logger.i(
          'Cache loaded: ${filesList.length} files, age: ${age.inMinutes} minutes');

      return LargeFileScanCache(
        files: filesList,
        config: config,
        scanTime: scanTime,
      );
    } catch (e) {
      logger.e('Failed to load large file cache: $e');
      await clearCache();
      return null;
    }
  }

  /// 清空缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_configKey);
      await prefs.remove(_timestampKey);
      logger.i('Large file cache cleared');
    } catch (e) {
      logger.e('Failed to clear cache: $e');
    }
  }

  /// 获取缓存大小（估算）
  Future<int> getCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      int totalSize = 0;

      // 估算 SharedPreferences 中的存储大小
      final filesJson = prefs.getString(_cacheKey);
      final configJson = prefs.getString(_configKey);

      if (filesJson != null) {
        totalSize += filesJson.length * 2; // UTF-16编码
      }
      if (configJson != null) {
        totalSize += configJson.length * 2;
      }

      // 加上时间戳（约8字节）
      if (prefs.getInt(_timestampKey) != null) {
        totalSize += 8;
      }

      return totalSize;
    } catch (e) {
      logger.e('Failed to get cache size: $e');
      return 0;
    }
  }

  /// 检查缓存配置是否匹配
  Future<bool> isCacheValid(LargeFileScanConfig config) async {
    final cache = await loadCache();
    if (cache == null) return false;
    return cache.config.isEquivalent(config);
  }
}

/// 扫描缓存数据
class LargeFileScanCache {
  final List<FileItem> files;
  final LargeFileScanConfig config;
  final DateTime scanTime;

  const LargeFileScanCache({
    required this.files,
    required this.config,
    required this.scanTime,
  });

  /// 缓存年龄
  Duration get age => DateTime.now().difference(scanTime);

  /// 缓存是否新鲜（小于1小时）
  bool get isFresh => age.inHours < 1;

  /// 格式化扫描时间
  String get formattedAge {
    if (age.inMinutes < 1) {
      return '刚刚';
    } else if (age.inMinutes < 60) {
      return '${age.inMinutes}分钟前';
    } else if (age.inHours < 24) {
      return '${age.inHours}小时前';
    } else {
      return '${age.inDays}天前';
    }
  }
}
