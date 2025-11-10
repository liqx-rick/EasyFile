import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/favorite_item.dart';

/// 收藏夹本地数据源
///
/// 负责收藏夹数据的持久化存储和读取
class FavoritesLocalSource {
  static const String _fileName = 'favorites.json';

  /// 获取收藏夹数据文件路径
  Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}${Platform.pathSeparator}$_fileName';
  }

  /// 获取所有收藏夹
  Future<List<FavoriteItem>> getFavorites() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (!await file.exists()) {
        logger.d('Favorites file does not exist, returning empty list');
        return [];
      }

      final jsonString = await file.readAsString();
      final jsonList = json.decode(jsonString) as List<dynamic>;

      final favorites = jsonList
          .map((json) => FavoriteItem.fromJson(json as Map<String, dynamic>))
          .toList();

      logger.d('Loaded ${favorites.length} favorites from storage');
      return favorites;
    } catch (e, stackTrace) {
      logger.e('Error loading favorites: $e\nStackTrace: $stackTrace');
      return [];
    }
  }

  /// 保存所有收藏夹
  Future<bool> saveFavorites(List<FavoriteItem> favorites) async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      // 确保目录存在
      await file.parent.create(recursive: true);

      final jsonList = favorites.map((favorite) => favorite.toJson()).toList();
      final jsonString = json.encode(jsonList);

      await file.writeAsString(jsonString);

      logger.d('Saved ${favorites.length} favorites to storage');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error saving favorites: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 添加收藏夹
  Future<bool> addFavorite(FavoriteItem favorite) async {
    try {
      final favorites = await getFavorites();

      // 检查是否已存在相同路径的收藏夹
      if (favorites.any((f) => f.path == favorite.path)) {
        logger.w('Favorite with path ${favorite.path} already exists');
        return false;
      }

      favorites.add(favorite);
      return await saveFavorites(favorites);
    } catch (e, stackTrace) {
      logger.e('Error adding favorite: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 删除收藏夹
  Future<bool> removeFavorite(String id) async {
    try {
      final favorites = await getFavorites();
      final initialLength = favorites.length;

      favorites.removeWhere((f) => f.id == id);

      if (favorites.length == initialLength) {
        logger.w('Favorite with id $id not found');
        return false;
      }

      return await saveFavorites(favorites);
    } catch (e, stackTrace) {
      logger.e('Error removing favorite: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 更新收藏夹
  Future<bool> updateFavorite(FavoriteItem updatedFavorite) async {
    try {
      final favorites = await getFavorites();
      final index = favorites.indexWhere((f) => f.id == updatedFavorite.id);

      if (index == -1) {
        logger.w('Favorite with id ${updatedFavorite.id} not found');
        return false;
      }

      favorites[index] = updatedFavorite;
      return await saveFavorites(favorites);
    } catch (e, stackTrace) {
      logger.e('Error updating favorite: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 更新收藏夹的最后访问时间
  Future<bool> updateLastAccessed(String id) async {
    try {
      final favorites = await getFavorites();
      final index = favorites.indexWhere((f) => f.id == id);

      if (index == -1) {
        logger.w('Favorite with id $id not found');
        return false;
      }

      final updatedFavorite = favorites[index].copyWith(
        lastAccessedAt: DateTime.now(),
      );

      favorites[index] = updatedFavorite;
      return await saveFavorites(favorites);
    } catch (e, stackTrace) {
      logger
          .e('Error updating last accessed time: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 清空所有收藏夹
  Future<bool> clearFavorites() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      logger.d('Cleared all favorites');
      return true;
    } catch (e, stackTrace) {
      logger.e('Error clearing favorites: $e\nStackTrace: $stackTrace');
      return false;
    }
  }
}
