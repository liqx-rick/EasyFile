import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/new_file_item.dart';

/// 新文件本地数据源（缓存管理）
class NewFilesLocalSource {
  static const String _fileName = 'new_files_index.json';
  static const int _maxCachedItems = 200; // 最多缓存200条索引

  /// 获取数据文件路径
  Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}${Platform.pathSeparator}$_fileName';
  }

  /// 加载缓存的文件索引
  Future<List<NewFileItem>> loadCachedIndex() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (!await file.exists()) {
        logger.d('New files index does not exist');
        return [];
      }

      final jsonString = await file.readAsString();
      final jsonList = json.decode(jsonString) as List<dynamic>;

      final items = jsonList
          .map((json) => NewFileItem.fromJson(json as Map<String, dynamic>))
          .toList();

      logger.d('Loaded ${items.length} cached new file items');
      return items;
    } catch (e, stackTrace) {
      logger.e('Error loading cached index: $e\nStackTrace: $stackTrace');
      return [];
    }
  }

  /// 保存文件索引到缓存
  Future<bool> saveCachedIndex(List<NewFileItem> items) async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      // 确保目录存在
      await file.parent.create(recursive: true);

      // 限制数量
      final limitedItems = items.take(_maxCachedItems).toList();

      // 只存储轻量级索引
      final jsonList = limitedItems.map((item) => item.toJson()).toList();
      final jsonString = json.encode(jsonList);

      await file.writeAsString(jsonString);

      logger.d('Saved ${limitedItems.length} items to cache');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error saving cached index: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 清除缓存
  Future<bool> clearCache() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      logger.d('Cleared new files cache');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error clearing cache: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 获取缓存大小（MB）
  Future<double> getCacheSize() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (await file.exists()) {
        final size = await file.length();
        return size / (1024 * 1024); // 转换为MB
      }

      return 0.0;
    } catch (e) {
      logger.e('Error getting cache size: $e');
      return 0.0;
    }
  }
}
