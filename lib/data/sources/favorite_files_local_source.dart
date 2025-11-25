import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/favorite_file_item.dart';

/// 收藏文件本地数据源
///
/// 负责收藏文件数据的持久化存储和读取
class FavoriteFilesLocalSource {
  static const String _fileName = 'favorite_files.json';

  /// 获取收藏文件数据文件路径
  Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}${Platform.pathSeparator}$_fileName';
  }

  /// 获取所有收藏文件
  Future<List<FavoriteFileItem>> getFavoriteFiles() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (!await file.exists()) {
        logger.d('Favorite files file does not exist, returning empty list');
        return [];
      }

      final jsonString = await file.readAsString();
      final jsonList = json.decode(jsonString) as List<dynamic>;

      final favoriteFiles = jsonList
          .map(
            (json) => FavoriteFileItem.fromJson(json as Map<String, dynamic>),
          )
          .toList();

      logger.d('Loaded ${favoriteFiles.length} favorite files from storage');
      return favoriteFiles;
    } catch (e, stackTrace) {
      logger.e('Error loading favorite files: $e\nStackTrace: $stackTrace');
      return [];
    }
  }

  /// 保存所有收藏文件
  Future<bool> saveFavoriteFiles(List<FavoriteFileItem> favoriteFiles) async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      // 确保目录存在
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      final jsonList = favoriteFiles.map((item) => item.toJson()).toList();
      final jsonString = json.encode(jsonList);

      await file.writeAsString(jsonString);

      logger.d('Saved ${favoriteFiles.length} favorite files to storage');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error saving favorite files: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 添加收藏文件
  Future<bool> addFavoriteFile(FavoriteFileItem favoriteFile) async {
    try {
      final favoriteFiles = await getFavoriteFiles();

      // 检查是否已存在
      if (favoriteFiles.any((item) => item.filePath == favoriteFile.filePath)) {
        logger.w('Favorite file already exists: ${favoriteFile.filePath}');
        return false;
      }

      favoriteFiles.add(favoriteFile);
      return await saveFavoriteFiles(favoriteFiles);
    } catch (e) {
      logger.e('Error adding favorite file: $e');
      return false;
    }
  }

  /// 移除收藏文件
  Future<bool> removeFavoriteFile(String filePath) async {
    try {
      final favoriteFiles = await getFavoriteFiles();
      final originalLength = favoriteFiles.length;

      favoriteFiles.removeWhere((item) => item.filePath == filePath);

      if (favoriteFiles.length == originalLength) {
        logger.w('Favorite file not found: $filePath');
        return false;
      }

      return await saveFavoriteFiles(favoriteFiles);
    } catch (e) {
      logger.e('Error removing favorite file: $e');
      return false;
    }
  }

  /// 更新收藏文件信息
  Future<bool> updateFavoriteFile(FavoriteFileItem favoriteFile) async {
    try {
      final favoriteFiles = await getFavoriteFiles();
      final index = favoriteFiles.indexWhere(
        (item) => item.filePath == favoriteFile.filePath,
      );

      if (index == -1) {
        logger.w('Favorite file not found: ${favoriteFile.filePath}');
        return false;
      }

      favoriteFiles[index] = favoriteFile;
      return await saveFavoriteFiles(favoriteFiles);
    } catch (e) {
      logger.e('Error updating favorite file: $e');
      return false;
    }
  }

  /// 检查文件是否已收藏
  Future<bool> isFavorite(String filePath) async {
    try {
      final favoriteFiles = await getFavoriteFiles();
      return favoriteFiles.any((item) => item.filePath == filePath);
    } catch (e) {
      logger.e('Error checking if file is favorite: $e');
      return false;
    }
  }

  /// 获取单个收藏文件
  Future<FavoriteFileItem?> getFavoriteFile(String filePath) async {
    try {
      final favoriteFiles = await getFavoriteFiles();
      return favoriteFiles.firstWhere(
        (item) => item.filePath == filePath,
        orElse: () => throw Exception('Not found'),
      );
    } catch (e) {
      return null;
    }
  }

  /// 更新文件访问信息
  Future<bool> updateFileAccess(String filePath) async {
    try {
      final favoriteFile = await getFavoriteFile(filePath);
      if (favoriteFile == null) return false;

      final updatedFile = favoriteFile.updateAccess();
      return await updateFavoriteFile(updatedFile);
    } catch (e) {
      logger.e('Error updating file access: $e');
      return false;
    }
  }

  /// 更新收藏文件的路径（用于重命名、移动等操作）
  Future<bool> updateFavoriteFilePath(String oldPath, String newPath) async {
    try {
      final favoriteFiles = await getFavoriteFiles();
      final index = favoriteFiles.indexWhere(
        (item) => item.filePath == oldPath,
      );

      if (index == -1) {
        // 文件不在收藏列表中，无需更新
        logger.d('File not in favorites, no need to update: $oldPath');
        return true;
      }

      // 更新路径
      final oldFavorite = favoriteFiles[index];
      final updatedFavorite = FavoriteFileItem(
        filePath: newPath,
        addedTime: oldFavorite.addedTime,
        accessCount: oldFavorite.accessCount,
        lastAccessTime: oldFavorite.lastAccessTime,
      );
      
      favoriteFiles[index] = updatedFavorite;
      final success = await saveFavoriteFiles(favoriteFiles);
      
      if (success) {
        logger.i('Updated favorite file path: $oldPath -> $newPath');
      }
      
      return success;
    } catch (e) {
      logger.e('Error updating favorite file path: $e');
      return false;
    }
  }

  /// 批量添加收藏文件
  ///
  /// 一次性添加多个文件到收藏，比逐个添加更高效
  /// 返回成功添加的文件数量
  Future<int> batchAddFavoriteFiles(
      List<FavoriteFileItem> newFavoriteFiles) async {
    try {
      final existingFavoriteFiles = await getFavoriteFiles();
      final existingPaths =
          existingFavoriteFiles.map((f) => f.filePath).toSet();

      int addedCount = 0;
      for (final favoriteFile in newFavoriteFiles) {
        // 跳过已存在的
        if (!existingPaths.contains(favoriteFile.filePath)) {
          existingFavoriteFiles.add(favoriteFile);
          addedCount++;
        }
      }

      if (addedCount > 0) {
        await saveFavoriteFiles(existingFavoriteFiles);
        logger.i('Batch added $addedCount favorite files');
      }

      return addedCount;
    } catch (e, stackTrace) {
      logger
          .e('Error batch adding favorite files: $e\nStackTrace: $stackTrace');
      return 0;
    }
  }

  /// 批量移除收藏文件
  ///
  /// 一次性移除多个文件的收藏，比逐个移除更高效
  /// 返回成功移除的文件数量
  Future<int> batchRemoveFavoriteFiles(List<String> filePaths) async {
    try {
      final favoriteFiles = await getFavoriteFiles();
      final originalLength = favoriteFiles.length;
      final pathsToRemove = filePaths.toSet();

      favoriteFiles
          .removeWhere((item) => pathsToRemove.contains(item.filePath));

      final removedCount = originalLength - favoriteFiles.length;
      if (removedCount > 0) {
        await saveFavoriteFiles(favoriteFiles);
        logger.i('Batch removed $removedCount favorite files');
      }

      return removedCount;
    } catch (e, stackTrace) {
      logger.e(
          'Error batch removing favorite files: $e\nStackTrace: $stackTrace');
      return 0;
    }
  }

  /// 清空所有收藏文件
  Future<bool> clearAllFavoriteFiles() async {
    try {
      return await saveFavoriteFiles([]);
    } catch (e) {
      logger.e('Error clearing favorite files: $e');
      return false;
    }
  }
}
