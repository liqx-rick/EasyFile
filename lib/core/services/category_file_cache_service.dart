import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_category.dart';

/// 分类文件缓存服务
/// 负责缓存首次扫描时收集的各分类文件数量和最近扫描时间
class CategoryFileCacheService {
  static const String _keyCategoryCounts = 'category_file_counts';
  static const String _keyLastScanTime = 'category_last_scan_time';
  static const String _keyTotalFilesScanned = 'category_total_files';

  /// 缓存有效期（7天）
  static const Duration cacheValidDuration = Duration(days: 7);

  /// 保存分类文件统计
  Future<bool> saveCategoryCounts(Map<FileCategory, int> counts) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 转换枚举为字符串存储
      final Map<String, int> stringMap = {};
      counts.forEach((category, count) {
        stringMap[category.name] = count;
      });

      await prefs.setString(_keyCategoryCounts, jsonEncode(stringMap));
      await prefs.setInt(
        _keyLastScanTime,
        DateTime.now().millisecondsSinceEpoch,
      );

      // 计算总数
      final totalFiles =
          counts.values.fold<int>(0, (sum, count) => sum + count);
      await prefs.setInt(_keyTotalFilesScanned, totalFiles);

      logger.i(
          'Saved category counts: ${counts.length} categories, $totalFiles files');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error saving category counts: $e\n$stackTrace');
      return false;
    }
  }

  /// 获取分类文件统计
  Future<Map<FileCategory, int>?> getCategoryCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查是否有缓存
      if (!prefs.containsKey(_keyCategoryCounts)) {
        logger.d('No category counts cache found');
        return null;
      }

      // 检查缓存是否过期
      final lastScanTime = prefs.getInt(_keyLastScanTime);
      if (lastScanTime != null) {
        final lastScan = DateTime.fromMillisecondsSinceEpoch(lastScanTime);
        final age = DateTime.now().difference(lastScan);

        if (age > cacheValidDuration) {
          logger.i('Category cache expired (age: ${age.inDays} days)');
          return null;
        }
      }

      // 读取缓存
      final jsonString = prefs.getString(_keyCategoryCounts);
      if (jsonString == null) {
        return null;
      }

      final Map<String, dynamic> stringMap = jsonDecode(jsonString);
      final Map<FileCategory, int> counts = {};

      stringMap.forEach((key, value) {
        try {
          final category = FileCategory.values.firstWhere(
            (e) => e.name == key,
            orElse: () => FileCategory.other,
          );
          counts[category] = value as int;
        } catch (e) {
          logger.w('Unknown category: $key');
        }
      });

      logger.d('Loaded category counts: ${counts.length} categories');
      return counts;
    } catch (e, stackTrace) {
      logger.e('Error loading category counts: $e\n$stackTrace');
      return null;
    }
  }

  /// 获取总文件数
  Future<int?> getTotalFilesScanned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyTotalFilesScanned);
    } catch (e) {
      logger.e('Error getting total files: $e');
      return null;
    }
  }

  /// 获取最后扫描时间
  Future<DateTime?> getLastScanTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_keyLastScanTime);
      if (timestamp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      logger.e('Error getting last scan time: $e');
      return null;
    }
  }

  /// 检查缓存是否有效
  Future<bool> isCacheValid() async {
    try {
      final lastScanTime = await getLastScanTime();
      if (lastScanTime == null) return false;

      final age = DateTime.now().difference(lastScanTime);
      return age <= cacheValidDuration;
    } catch (e) {
      logger.e('Error checking cache validity: $e');
      return false;
    }
  }

  /// 清除缓存（包括统计数据和文件列表）
  Future<bool> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 清除统计数据
      await prefs.remove(_keyCategoryCounts);
      await prefs.remove(_keyLastScanTime);
      await prefs.remove(_keyTotalFilesScanned);

      // 清除文件列表缓存
      await clearFileListsCache();

      logger.i('Category cache cleared (including file lists)');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error clearing category cache: $e\n$stackTrace');
      return false;
    }
  }

  /// 清除分类文件列表缓存
  Future<bool> clearFileListsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 分类文件列表的缓存键
      final fileListKeys = [
        'category_cache_images',
        'category_cache_video',
        'category_cache_music',
        'category_cache_documents',
        'category_cache_downloads',
      ];

      int clearedCount = 0;
      for (final key in fileListKeys) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
          clearedCount++;
        }
      }

      logger.i('Cleared $clearedCount file list caches');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error clearing file lists cache: $e\n$stackTrace');
      return false;
    }
  }

  /// 获取文件列表缓存大小（估算）
  Future<int> getFileListsCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final fileListKeys = [
        'category_cache_images',
        'category_cache_video',
        'category_cache_music',
        'category_cache_documents',
        'category_cache_downloads',
      ];

      int totalSize = 0;
      for (final key in fileListKeys) {
        final value = prefs.getString(key);
        if (value != null) {
          // 估算：字符串长度 × 2（UTF-16编码）
          totalSize += value.length * 2;
        }
      }

      return totalSize;
    } catch (e) {
      logger.e('Error getting file lists cache size: $e');
      return 0;
    }
  }

  /// 获取特定分类的文件数
  Future<int?> getCategoryCount(FileCategory category) async {
    final counts = await getCategoryCounts();
    return counts?[category];
  }

  /// 检查是否有缓存数据
  Future<bool> hasCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_keyCategoryCounts);
    } catch (e) {
      return false;
    }
  }
}
