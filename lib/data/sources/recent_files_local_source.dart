import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/recent_file_item.dart';

/// 最近访问文件的本地数据源
class RecentFilesLocalSource {
  static const String _fileName = 'recent_files.json';
  static const int _maxRecentFiles = 20; // 最多保存20个最近文件

  /// 获取数据文件路径
  Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}${Platform.pathSeparator}$_fileName';
  }

  /// 获取所有最近访问的文件
  Future<List<RecentFileItem>> getRecentFiles() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (!await file.exists()) {
        logger.d('Recent files data does not exist, returning empty list');
        return [];
      }

      final jsonString = await file.readAsString();
      final jsonList = json.decode(jsonString) as List<dynamic>;

      final recentFiles = jsonList
          .map((json) => RecentFileItem.fromJson(json as Map<String, dynamic>))
          .toList();

      logger.d('Loaded ${recentFiles.length} recent files from storage');
      return recentFiles;
    } catch (e, stackTrace) {
      logger.e('Error loading recent files: $e\nStackTrace: $stackTrace');
      return [];
    }
  }

  /// 保存所有最近访问的文件
  Future<bool> saveRecentFiles(List<RecentFileItem> recentFiles) async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      // 确保目录存在
      await file.parent.create(recursive: true);

      // 限制数量并按时间排序
      final sortedFiles = recentFiles.toList()
        ..sort((a, b) => b.accessedAt.compareTo(a.accessedAt));

      final limitedFiles = sortedFiles.take(_maxRecentFiles).toList();

      final jsonList = limitedFiles.map((file) => file.toJson()).toList();
      final jsonString = json.encode(jsonList);

      await file.writeAsString(jsonString);

      logger.d('Saved ${limitedFiles.length} recent files to storage');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error saving recent files: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 添加或更新最近访问的文件
  Future<bool> addRecentFile(RecentFileItem recentFile) async {
    try {
      final recentFiles = await getRecentFiles();

      // 查找是否已存在
      final existingIndex = recentFiles.indexWhere(
        (f) => f.path == recentFile.path,
      );

      if (existingIndex != -1) {
        // 更新已存在的文件（增加访问次数和更新时间）
        recentFiles[existingIndex] = recentFiles[existingIndex]
            .copyWithAccess();
        logger.d('Updated existing recent file: ${recentFile.name}');
      } else {
        // 添加新文件
        recentFiles.add(recentFile);
        logger.d('Added new recent file: ${recentFile.name}');
      }

      return await saveRecentFiles(recentFiles);
    } catch (e, stackTrace) {
      logger.e('Error adding recent file: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 删除指定的最近访问文件
  Future<bool> removeRecentFile(String path) async {
    try {
      final recentFiles = await getRecentFiles();
      final initialLength = recentFiles.length;

      recentFiles.removeWhere((f) => f.path == path);

      if (recentFiles.length == initialLength) {
        logger.w('Recent file with path $path not found');
        return false;
      }

      logger.d('Removed recent file: $path');
      return await saveRecentFiles(recentFiles);
    } catch (e, stackTrace) {
      logger.e('Error removing recent file: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 清空所有最近访问文件
  Future<bool> clearRecentFiles() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      logger.d('Cleared all recent files');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error clearing recent files: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 清理无效的最近访问文件（文件不存在的项目）
  Future<bool> cleanupRecentFiles() async {
    try {
      final recentFiles = await getRecentFiles();
      final validFiles = <RecentFileItem>[];

      for (final recentFile in recentFiles) {
        final entity = recentFile.isDirectory
            ? Directory(recentFile.path)
            : File(recentFile.path);

        if (entity.existsSync()) {
          validFiles.add(recentFile);
        } else {
          logger.d('Removing invalid recent file: ${recentFile.path}');
        }
      }

      if (validFiles.length != recentFiles.length) {
        logger.i(
          'Cleaned up ${recentFiles.length - validFiles.length} invalid recent files',
        );
        return await saveRecentFiles(validFiles);
      }

      return true;
    } catch (e, stackTrace) {
      logger.e('Error cleaning up recent files: $e\nStackTrace: $stackTrace');
      return false;
    }
  }
}
