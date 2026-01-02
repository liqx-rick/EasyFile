import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';

/// 添加快速访问文件夹的结果
enum AddFolderResult {
  added, // 成功添加新文件夹
  unhidden, // 恢复了隐藏的文件夹
  exists, // 已存在且未隐藏
  skippedHidden, // 跳过隐藏的文件夹（不恢复）
  error, // 发生错误
}

/// 快速访问本地数据源
///
/// 负责快速访问文件夹数据的持久化存储和读取
class QuickAccessLocalSource {
  static const String _fileName = 'quick_access_folders.json';

  /// 获取数据文件路径
  Future<String> get _filePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}${Platform.pathSeparator}$_fileName';
  }

  /// 获取所有快速访问文件夹
  Future<List<QuickAccessFolder>> getAllFolders() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (!await file.exists()) {
        logger.d('Quick access file does not exist, returning empty list');
        return [];
      }

      final jsonString = await file.readAsString();
      final jsonList = json.decode(jsonString) as List<dynamic>;

      final folders = jsonList
          .map(
            (json) => QuickAccessFolder.fromJson(json as Map<String, dynamic>),
          )
          .toList();

      logger.d('Loaded ${folders.length} quick access folders from storage');
      return folders;
    } catch (e, stackTrace) {
      logger.e(
        'Error loading quick access folders: $e\nStackTrace: $stackTrace',
      );
      return [];
    }
  }

  /// 保存所有快速访问文件夹
  Future<bool> saveFolders(List<QuickAccessFolder> folders) async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      // 确保目录存在
      await file.parent.create(recursive: true);

      final jsonList = folders.map((folder) => folder.toJson()).toList();
      final jsonString = json.encode(jsonList);

      await file.writeAsString(jsonString);

      logger.d('Saved ${folders.length} quick access folders to storage');
      return true;
    } catch (e, stackTrace) {
      logger.e(
        'Error saving quick access folders: $e\nStackTrace: $stackTrace',
      );
      return false;
    }
  }

  /// 添加快速访问文件夹
  /// [unhideIfHidden] 如果为true，当文件夹已存在且被隐藏时，会取消隐藏；否则跳过
  Future<AddFolderResult> addFolderWithResult(
    QuickAccessFolder folder, {
    bool unhideIfHidden = true,
  }) async {
    try {
      final folders = await getAllFolders();

      // 检查是否已存在相同路径的文件夹
      final existingIndex = folders.indexWhere((f) => f.path == folder.path);

      if (existingIndex != -1) {
        final existing = folders[existingIndex];

        // 如果已存在且被隐藏
        if (existing.isHidden) {
          if (unhideIfHidden) {
            // 恢复它（取消隐藏）
            logger.i('Unhiding existing folder: ${folder.path}');
            folders[existingIndex] = existing.copyWith(
              isHidden: false,
              // 保留其他属性，如用户设置的别名等
            );
            final success = await saveFolders(folders);
            return success ? AddFolderResult.unhidden : AddFolderResult.error;
          } else {
            // 不恢复，跳过
            logger.i('Skipping hidden folder: ${folder.path}');
            return AddFolderResult.skippedHidden;
          }
        }

        // 如果已存在且未隐藏，则跳过
        logger.w('Quick access folder with path ${folder.path} already exists');
        return AddFolderResult.exists;
      }

      // 不存在，添加新文件夹
      folders.add(folder);
      final success = await saveFolders(folders);
      return success ? AddFolderResult.added : AddFolderResult.error;
    } catch (e, stackTrace) {
      logger.e('Error adding quick access folder: $e\nStackTrace: $stackTrace');
      return AddFolderResult.error;
    }
  }

  /// 删除快速访问文件夹
  Future<bool> removeFolder(String id) async {
    try {
      final folders = await getAllFolders();
      final initialLength = folders.length;

      folders.removeWhere((f) => f.id == id);

      if (folders.length == initialLength) {
        logger.w('Quick access folder with id $id not found');
        return false;
      }

      return await saveFolders(folders);
    } catch (e, stackTrace) {
      logger.e(
        'Error removing quick access folder: $e\nStackTrace: $stackTrace',
      );
      return false;
    }
  }

  /// 批量删除快速访问文件夹
  Future<bool> removeFolders(List<String> ids) async {
    try {
      final folders = await getAllFolders();
      final initialLength = folders.length;

      folders.removeWhere((f) => ids.contains(f.id));

      if (folders.length == initialLength) {
        logger.w('No quick access folders found with given ids');
        return false;
      }

      return await saveFolders(folders);
    } catch (e, stackTrace) {
      logger.e(
        'Error removing multiple quick access folders: $e\nStackTrace: $stackTrace',
      );
      return false;
    }
  }

  /// 更新快速访问文件夹
  Future<bool> updateFolder(QuickAccessFolder updatedFolder) async {
    try {
      final folders = await getAllFolders();
      final index = folders.indexWhere((f) => f.id == updatedFolder.id);

      if (index == -1) {
        logger.w('Quick access folder with id ${updatedFolder.id} not found');
        return false;
      }

      folders[index] = updatedFolder;
      return await saveFolders(folders);
    } catch (e, stackTrace) {
      logger.e(
        'Error updating quick access folder: $e\nStackTrace: $stackTrace',
      );
      return false;
    }
  }

  /// 批量更新快速访问文件夹
  Future<bool> updateFolders(List<QuickAccessFolder> updatedFolders) async {
    try {
      final folders = await getAllFolders();

      for (final updated in updatedFolders) {
        final index = folders.indexWhere((f) => f.id == updated.id);
        if (index != -1) {
          folders[index] = updated;
        }
      }

      return await saveFolders(folders);
    } catch (e, stackTrace) {
      logger.e(
        'Error updating multiple quick access folders: $e\nStackTrace: $stackTrace',
      );
      return false;
    }
  }

  /// 更新文件夹的最后访问时间和访问次数
  Future<bool> updateAccessInfo(String id) async {
    try {
      final folders = await getAllFolders();
      final index = folders.indexWhere((f) => f.id == id);

      if (index == -1) {
        logger.w('Quick access folder with id $id not found');
        return false;
      }

      final updatedFolder = folders[index].copyWith(
        lastAccessedAt: DateTime.now(),
        accessCount: folders[index].accessCount + 1,
      );

      folders[index] = updatedFolder;
      return await saveFolders(folders);
    } catch (e, stackTrace) {
      logger.e('Error updating access info: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 设置别名
  Future<bool> setAlias(String id, String? alias) async {
    try {
      final folders = await getAllFolders();
      final index = folders.indexWhere((f) => f.id == id);

      if (index == -1) {
        logger.w('Quick access folder with id $id not found');
        return false;
      }

      // 如果alias为null或空字符串，清空别名；否则使用传入的alias
      final updatedFolder = folders[index].copyWith(
        userAlias: (alias == null || alias.isEmpty) ? null : alias,
      );

      folders[index] = updatedFolder;
      return await saveFolders(folders);
    } catch (e, stackTrace) {
      logger.e('Error setting alias: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 切换固定状态
  @Deprecated('homeDisplayOrder field has been removed from QuickAccessFolder')
  Future<bool> togglePin(String id) async {
    logger.w('togglePin is deprecated and has no effect');
    return true;
  }

  /// 批量添加文件夹
  Future<bool> addFolders(List<QuickAccessFolder> newFolders) async {
    try {
      final folders = await getAllFolders();
      final existingPaths = folders.map((f) => f.path).toSet();

      // 只添加不存在的文件夹
      final foldersToAdd =
          newFolders.where((f) => !existingPaths.contains(f.path)).toList();

      if (foldersToAdd.isEmpty) {
        logger.w('All folders already exist');
        return false;
      }

      folders.addAll(foldersToAdd);
      return await saveFolders(folders);
    } catch (e, stackTrace) {
      logger.e(
        'Error adding multiple quick access folders: $e\nStackTrace: $stackTrace',
      );
      return false;
    }
  }

  /// 根据类型获取文件夹
  Future<List<QuickAccessFolder>> getFoldersByType(
    QuickAccessFolderType type,
  ) async {
    try {
      final folders = await getAllFolders();
      return folders.where((f) => f.type == type).toList();
    } catch (e, stackTrace) {
      logger.e('Error getting folders by type: $e\nStackTrace: $stackTrace');
      return [];
    }
  }

  /// 获取固定的文件夹（显示在首页的）
  @Deprecated('homeDisplayOrder field has been removed from QuickAccessFolder')
  Future<List<QuickAccessFolder>> getPinnedFolders() async {
    logger.w('getPinnedFolders is deprecated, returning empty list');
    return [];
  }

  /// 根据父应用获取子文件夹
  @Deprecated('parentApp field has been removed from QuickAccessFolder')
  Future<List<QuickAccessFolder>> getFoldersByParentApp(
    String parentApp,
  ) async {
    logger.w('getFoldersByParentApp is deprecated, returning empty list');
    return [];
  }

  /// 检查路径是否已存在
  Future<bool> pathExists(String path) async {
    try {
      final folders = await getAllFolders();
      return folders.any((f) => f.path == path);
    } catch (e, stackTrace) {
      logger.e('Error checking path existence: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 清空所有快速访问文件夹
  Future<bool> clearAllFolders() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      logger.d('Cleared all quick access folders');
      return true;
    } catch (e, stackTrace) {
      logger.e(
        'Error clearing quick access folders: $e\nStackTrace: $stackTrace',
      );
      return false;
    }
  }

  /// 加入快速访问（将扫描出的项标记为已加入）
  Future<bool> addToQuickAccess(String id) async {
    try {
      final folders = await getAllFolders();
      final index = folders.indexWhere((f) => f.id == id);

      if (index == -1) {
        logger.w('Quick access folder with id $id not found');
        return false;
      }

      final updatedFolder = folders[index].copyWith(
        isAddedToQuickAccess: true,
        isHidden: false, // 加入时取消隐藏
      );

      folders[index] = updatedFolder;
      return await saveFolders(folders);
    } catch (e, stackTrace) {
      logger.e('Error adding to quick access: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 批量加入快速访问
  Future<int> batchAddToQuickAccess(List<String> ids) async {
    int count = 0;
    try {
      final folders = await getAllFolders();

      for (final id in ids) {
        final index = folders.indexWhere((f) => f.id == id);
        if (index != -1) {
          folders[index] = folders[index].copyWith(
            isAddedToQuickAccess: true,
            isHidden: false,
          );
          count++;
        }
      }

      if (count > 0) {
        await saveFolders(folders);
      }

      logger.d('Added $count folders to quick access');
      return count;
    } catch (e, stackTrace) {
      logger.e(
        'Error batch adding to quick access: $e\nStackTrace: $stackTrace',
      );
      return count;
    }
  }

  /// 移出快速访问（但保留在扫描列表中）
  Future<bool> removeFromQuickAccess(String id) async {
    try {
      final folders = await getAllFolders();
      final index = folders.indexWhere((f) => f.id == id);

      if (index == -1) {
        logger.w('Quick access folder with id $id not found');
        return false;
      }

      final updatedFolder = folders[index].copyWith(
        isAddedToQuickAccess: false,
      );

      folders[index] = updatedFolder;
      return await saveFolders(folders);
    } catch (e, stackTrace) {
      logger.e('Error removing from quick access: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 批量移出快速访问
  Future<int> batchRemoveFromQuickAccess(List<String> ids) async {
    int count = 0;
    try {
      final folders = await getAllFolders();

      for (final id in ids) {
        final index = folders.indexWhere((f) => f.id == id);
        if (index != -1) {
          folders[index] = folders[index].copyWith(
            isAddedToQuickAccess: false,
          );
          count++;
        }
      }

      if (count > 0) {
        await saveFolders(folders);
      }

      logger.d('Removed $count folders from quick access');
      return count;
    } catch (e, stackTrace) {
      logger.e(
        'Error batch removing from quick access: $e\nStackTrace: $stackTrace',
      );
      return count;
    }
  }

  /// 忽略项目（不再显示）
  Future<bool> hideFolder(String id) async {
    try {
      final folders = await getAllFolders();
      final index = folders.indexWhere((f) => f.id == id);

      if (index == -1) {
        logger.w('Quick access folder with id $id not found');
        return false;
      }

      final updatedFolder = folders[index].copyWith(
        isHidden: true,
        isAddedToQuickAccess: false,
      );

      folders[index] = updatedFolder;
      return await saveFolders(folders);
    } catch (e, stackTrace) {
      logger.e('Error hiding folder: $e\nStackTrace: $stackTrace');
      return false;
    }
  }

  /// 批量忽略
  Future<int> batchHideFolders(List<String> ids) async {
    int count = 0;
    try {
      final folders = await getAllFolders();

      for (final id in ids) {
        final index = folders.indexWhere((f) => f.id == id);
        if (index != -1) {
          folders[index] = folders[index].copyWith(
            isHidden: true,
            isAddedToQuickAccess: false,
          );
          count++;
        }
      }

      if (count > 0) {
        await saveFolders(folders);
      }

      logger.d('Hidden $count folders');
      return count;
    } catch (e, stackTrace) {
      logger.e('Error batch hiding folders: $e\nStackTrace: $stackTrace');
      return count;
    }
  }

  /// 获取已加入快速访问的文件夹
  Future<List<QuickAccessFolder>> getAddedFolders() async {
    try {
      final folders = await getAllFolders();
      return folders
          .where((f) => f.isAddedToQuickAccess && !f.isHidden)
          .toList();
    } catch (e, stackTrace) {
      logger.e('Error getting added folders: $e\nStackTrace: $stackTrace');
      return [];
    }
  }

  /// 获取未加入但扫描出的文件夹
  Future<List<QuickAccessFolder>> getScannedOnlyFolders() async {
    try {
      final folders = await getAllFolders();
      return folders
          .where((f) => !f.isAddedToQuickAccess && !f.isHidden)
          .toList();
    } catch (e, stackTrace) {
      logger.e(
        'Error getting scanned only folders: $e\nStackTrace: $stackTrace',
      );
      return [];
    }
  }
}
