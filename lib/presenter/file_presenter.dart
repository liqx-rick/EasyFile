import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/data/models/favorite_item.dart';
import 'package:easyfile/data/models/favorite_file_item.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/recent_file_item.dart';
import 'package:easyfile/data/repositories/file_repository.dart';
import 'package:easyfile/data/sources/favorites_local_source.dart';
import 'package:easyfile/data/sources/favorite_files_local_source.dart';
import 'package:easyfile/data/sources/recent_files_local_source.dart';
import 'package:easyfile/data/sources/theme_local_source.dart';
import 'package:easyfile/core/services/search_history_service.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

class FilePresenter {
  final FileRepository repository;
  final FileViewModel viewModel;
  final FavoritesLocalSource favoritesSource;
  final FavoriteFilesLocalSource favoriteFilesSource;
  final RecentFilesLocalSource recentFilesSource;
  final ThemeLocalSource themeSource;

  FilePresenter({
    required this.repository,
    required this.viewModel,
    required this.favoritesSource,
    required this.favoriteFilesSource,
    required this.recentFilesSource,
    required this.themeSource,
  }) {
    logger.d('FilePresenter constructor called');
    logger.d('favoriteFilesSource type: ${favoriteFilesSource.runtimeType}');
  }
  Future<void> loadFiles(String path, {bool isRootNavigation = false}) async {
    logger.i(
      'FilePresenter.loadFiles called with path: $path, isRootNavigation: $isRootNavigation',
    );
    viewModel.setLoading(true);
    logger.d('Setting current path: $path');
    viewModel.setCurrentPath(path);

    // 如果是根导航（从收藏夹或其他入口进入），设置根路径
    if (isRootNavigation) {
      logger.d('Setting root path: $path');
      viewModel.setRootPath(path);
    }

    // 当加载具体路径时，退出最近文件模式
    if (viewModel.isRecentFilesMode) {
      logger.d('Exiting recent files mode, switching to directory browsing');
      viewModel.setIsRecentFilesMode(false);
    }

    // 重置文件类型筛选
    viewModel.resetCategoryFilter();

    // 清除之前的错误消息
    viewModel.clearError();

    logger.d('Current path set, loading files...');
    final files = await repository.getFiles(path);
    logger.i('Files loaded: ${files.length} items');

    // 检测是否是受系统保护的目录（Android/data等）
    final isProtectedDir = path.contains('/Android/data') ||
        path.contains('/Android/obb') ||
        path.contains('/Android/media');

    logger
        .d('isProtectedDir: $isProtectedDir, files.isEmpty: ${files.isEmpty}');

    // 先设置错误消息（如果有）
    if (files.isEmpty && isProtectedDir) {
      logger.w('Setting error for protected system directory: $path');
      viewModel.setError('此目录受 Android 系统保护，无法访问');
      logger.w('Error set, errorMessage: ${viewModel.errorMessage}');
    }

    // 然后设置文件列表
    viewModel.setFiles(files);

    // 最后设置加载状态
    viewModel.setLoading(false);

    logger.d(
      'ViewModel updated - currentPath: ${viewModel.currentPath}, filesCount: ${viewModel.files.length}, hasError: ${viewModel.errorMessage != null}',
    );
  }

  Future<void> navigateToFolder(String folderPath) async {
    await loadFiles(folderPath);
  }

  Future<void> navigateUp() async {
    final currentPath = viewModel.currentPath;
    logger.d('NavigateUp called with current path: $currentPath');

    if (currentPath.isNotEmpty) {
      // 使用 path.dirname 来获取父目录，这样可以正确处理 Windows 和 Unix 路径
      final parentPath = path.dirname(currentPath);
      logger.d('Parent path calculated: $parentPath');
      logger.d('Platform.isWindows: ${Platform.isWindows}');
      logger.d('parentPath != currentPath: ${parentPath != currentPath}');
      logger.d('parentPath.isNotEmpty: ${parentPath.isNotEmpty}');
      logger.d('parentPath != ".": ${parentPath != '.'}');
      if (Platform.isWindows) {
        logger.d('parentPath.endsWith(":"): ${parentPath.endsWith(':')}');
      }

      // 检查是否已经到达根目录
      // Windows: C:\ -> C:, Unix: / -> /
      if (parentPath != currentPath &&
          parentPath.isNotEmpty &&
          parentPath != '.' &&
          !(Platform.isWindows && parentPath.endsWith(':'))) {
        logger.i('Navigating up from $currentPath to $parentPath');
        await loadFiles(parentPath);
      } else {
        logger.w(
          'Already at root directory or invalid parent path. Current: $currentPath, Parent: $parentPath',
        );
      }
    } else {
      logger.w('Current path is empty, cannot navigate up');
    }
  }

  Future<void> searchFiles(String query) async {
    logger.i('FilePresenter.searchFiles called with query: $query');
    logger.i('Current path for search: ${viewModel.currentPath}');

    if (viewModel.currentPath.isEmpty) {
      logger.w('Cannot search: currentPath is empty');
      return;
    }

    viewModel.setLoading(true);
    viewModel.setSearchMode(true);
    viewModel.setSearchQuery(query);

    final files = await repository.searchFiles(viewModel.currentPath, query);
    logger.i('Search completed: ${files.length} results found');

    // 保存搜索历史
    await SearchHistoryService().addSearch(query);

    viewModel.setFiles(files);
    viewModel.setLoading(false);
  }

  Future<void> clearSearch() async {
    logger.i('FilePresenter.clearSearch called');
    viewModel.setSearchMode(false);
    viewModel.setSearchQuery('');
    await loadFiles(viewModel.currentPath);
  }

  Future<bool> deleteFile(FileItem file) async {
    logger.i('FilePresenter.deleteFile called for: ${file.path}');
    final success = await repository.deleteFile(file);
    if (success) {
      logger.i('File deleted successfully, refreshing list');
      await loadFiles(viewModel.currentPath);
    } else {
      logger.w('Failed to delete file: ${file.path}');
    }
    return success;
  }

  /// 批量删除文件
  Future<Map<String, bool>> batchDeleteFiles(List<String> filePaths) async {
    logger.i(
      'FilePresenter.batchDeleteFiles called for ${filePaths.length} files',
    );
    final results = <String, bool>{};

    for (final filePath in filePaths) {
      try {
        final file = File(filePath);
        if (file.existsSync()) {
          final fileItem = FileItem(
            name: path.basename(filePath),
            path: filePath,
            size: file.lengthSync(),
            modified: file.lastModifiedSync(),
            isDirectory: false,
          );
          final success = await repository.deleteFile(fileItem);
          results[filePath] = success;
          if (success) {
            logger.d('Deleted file: $filePath');
          } else {
            logger.w('Failed to delete file: $filePath');
          }
        } else {
          logger.w('File not found: $filePath');
          results[filePath] = false;
        }
      } catch (e) {
        logger.e('Error deleting file $filePath: $e');
        results[filePath] = false;
      }
    }

    final successCount = results.values.where((v) => v).length;
    logger.i(
      'Batch delete completed: $successCount/${filePaths.length} files deleted',
    );

    return results;
  }

  Future<bool> copyFile(FileItem file, String destinationPath) async {
    logger.i(
      'FilePresenter.copyFile called from ${file.path} to $destinationPath',
    );
    final copiedFile = await repository.copyFile(file, destinationPath);
    if (copiedFile != null) {
      logger.i('File copied successfully: ${copiedFile.path}');

      // 智能判断是否应该将复制的文件添加到当前列表
      bool shouldAddToList = false;

      // 场景1：复制到当前浏览目录（文件浏览模式）
      if (destinationPath == viewModel.currentPath) {
        logger.d('File copied to current browsing directory');
        shouldAddToList = true;
      }
      // 场景2：原文件在当前列表中（分类模式、收藏模式等）
      // 复制的文件类型与原文件相同，应该也在当前列表中
      else if (viewModel.files.any((f) => f.path == file.path)) {
        logger.d(
            'Source file is in current list (${viewModel.files.length} items), copied file should be added too');
        shouldAddToList = true;
      } else {
        logger.d(
            'Source file NOT in current list. Current list has ${viewModel.files.length} items');
        logger.d('Current path: ${viewModel.currentPath}');
      }

      if (shouldAddToList) {
        logger.i('Adding copied file to current list: ${copiedFile.path}');
        viewModel.addFileToList(copiedFile);
        logger
            .i('File added to list. New list size: ${viewModel.files.length}');
      } else {
        logger.d('File not added to list (different directory/category)');
      }

      return true;
    } else {
      logger.w('Failed to copy file: ${file.path}');
      return false;
    }
  }

  Future<bool> moveFile(FileItem file, String destinationPath) async {
    logger.i(
      'FilePresenter.moveFile called from ${file.path} to $destinationPath',
    );
    final movedFile = await repository.moveFile(file, destinationPath);
    if (movedFile != null) {
      logger.i('File moved successfully, updating in list');

      // 如果文件被收藏，同步更新收藏记录中的路径
      if (viewModel.isFavoriteFile(file.path)) {
        logger.d('File is favorited, updating favorite path');

        // 获取原收藏信息
        final oldFavorite = viewModel.favoriteFiles.firstWhere(
          (f) => f.filePath == file.path,
        );

        // 更新数据源中的路径
        await favoriteFilesSource.updateFavoriteFilePath(
          file.path,
          movedFile.path,
        );

        // 同步更新 ViewModel 中的收藏状态
        viewModel.removeFavoriteFile(file.path);
        viewModel.addFavoriteFile(FavoriteFileItem(
          filePath: movedFile.path,
          addedTime: oldFavorite.addedTime,
          accessCount: oldFavorite.accessCount,
          lastAccessTime: oldFavorite.lastAccessTime,
        ));
      }

      viewModel.updateFileInList(file.path, movedFile);
      logger.i('File updated in list instantly');
      return true;
    } else {
      logger.w('Failed to move file: ${file.path}');
      return false;
    }
  }

  /// 批量移动文件
  Future<Map<String, bool>> batchMoveFiles(
    List<String> filePaths,
    String destinationPath,
  ) async {
    logger.i(
      'FilePresenter.batchMoveFiles called for ${filePaths.length} files to $destinationPath',
    );
    final results = <String, bool>{};

    // 验证目标路径是否存在
    final destDir = Directory(destinationPath);
    if (!destDir.existsSync()) {
      logger.w('Destination directory does not exist: $destinationPath');
      for (final filePath in filePaths) {
        results[filePath] = false;
      }
      return results;
    }

    for (final filePath in filePaths) {
      try {
        final file = File(filePath);
        if (file.existsSync()) {
          final fileName = path.basename(filePath);

          final fileItem = FileItem(
            name: fileName,
            path: filePath,
            size: file.lengthSync(),
            modified: file.lastModifiedSync(),
            isDirectory: false,
          );
          final movedFile = await repository.moveFile(
            fileItem,
            destinationPath,
          );
          results[filePath] = movedFile != null;
          if (movedFile != null) {
            logger.d('Moved file: $filePath to ${movedFile.path}');
          } else {
            logger.w('Failed to move file: $filePath');
          }
        } else {
          logger.w('File not found: $filePath');
          results[filePath] = false;
        }
      } catch (e) {
        logger.e('Error moving file $filePath: $e');
        results[filePath] = false;
      }
    }

    final successCount = results.values.where((v) => v).length;
    logger.i(
      'Batch move completed: $successCount/${filePaths.length} files moved',
    );

    return results;
  }

  /// 批量分享文件
  Future<bool> batchShareFiles(List<String> filePaths) async {
    logger.i(
      'FilePresenter.batchShareFiles called for ${filePaths.length} files',
    );

    const platform = MethodChannel('com.example.easyfile/share');

    try {
      // 过滤出存在的文件
      final existingFilePaths = <String>[];
      for (final filePath in filePaths) {
        final file = File(filePath);
        if (file.existsSync()) {
          existingFilePaths.add(filePath);
          logger.d('Added file to share: $filePath');
        } else {
          logger.w('File not found, skipping: $filePath');
        }
      }

      if (existingFilePaths.isEmpty) {
        logger.w('No valid files to share');
        return false;
      }

      // 如果只有一个文件，使用单文件分享方法以获得更好的兼容性
      if (existingFilePaths.length == 1) {
        await platform.invokeMethod('shareFile', {
          'filePath': existingFilePaths[0],
          'mimeType': '*/*', // 让原生代码自动检测
        });
        logger.i('Share completed for single file');
      } else {
        // 多个文件使用批量分享
        await platform.invokeMethod('shareMultipleFiles', {
          'filePaths': existingFilePaths,
        });
        logger.i('Share completed for ${existingFilePaths.length} files');
      }

      return true;
    } catch (e) {
      logger.e('Error sharing files: $e');
      return false;
    }
  }

  Future<bool> renameFile(FileItem file, String newName) async {
    logger.i('FilePresenter.renameFile called for ${file.path} to $newName');
    final renamedFile = await repository.renameFile(file, newName);
    if (renamedFile != null) {
      logger.i('File renamed successfully, updating in list');

      // 如果文件被收藏，同步更新收藏记录中的路径
      if (viewModel.isFavoriteFile(file.path)) {
        logger.d('File is favorited, updating favorite path');

        // 获取原收藏信息
        final oldFavorite = viewModel.favoriteFiles.firstWhere(
          (f) => f.filePath == file.path,
        );

        // 更新数据源中的路径
        await favoriteFilesSource.updateFavoriteFilePath(
          file.path,
          renamedFile.path,
        );

        // 同步更新 ViewModel 中的收藏状态
        viewModel.removeFavoriteFile(file.path);
        viewModel.addFavoriteFile(FavoriteFileItem(
          filePath: renamedFile.path,
          addedTime: oldFavorite.addedTime,
          accessCount: oldFavorite.accessCount,
          lastAccessTime: oldFavorite.lastAccessTime,
        ));
      }

      viewModel.updateFileInList(file.path, renamedFile);
      logger.i('File updated in list instantly');
      return true;
    } else {
      logger.w('Failed to rename file: ${file.path}');
      return false;
    }
  }

  // 收藏夹相关方法

  /// 初始化收藏夹数据
  Future<void> initializeFavorites() async {
    logger.i('FilePresenter.initializeFavorites called');
    try {
      final favorites = await favoritesSource.getFavorites();

      // 如果是首次运行且没有收藏夹，则添加默认收藏夹
      if (favorites.isEmpty) {
        logger.i('No favorites found, initializing default favorites');
        await _initializeDefaultFavorites();
        // 重新加载收藏夹
        final updatedFavorites = await favoritesSource.getFavorites();
        viewModel.setFavorites(updatedFavorites);
        logger.d('Loaded ${updatedFavorites.length} default favorites');
      } else {
        viewModel.setFavorites(favorites);
        logger.d('Loaded ${favorites.length} existing favorites');
      }
    } catch (e) {
      logger.e('Error loading favorites: $e');
    }
  }

  /// 初始化默认收藏夹
  Future<void> _initializeDefaultFavorites() async {
    logger.i(
      'Initializing default favorites for platform: ${Platform.operatingSystem}',
    );

    try {
      List<Map<String, String>> defaultPaths = [];

      if (Platform.isAndroid) {
        defaultPaths = [
          {
            'name': 'DCIM',
            'path': '/storage/emulated/0/DCIM',
            'icon': 'pictures',
          },
          {
            'name': 'Pictures',
            'path': '/storage/emulated/0/Pictures',
            'icon': 'pictures',
          },
          {
            'name': 'Documents',
            'path': '/storage/emulated/0/Documents',
            'icon': 'documents',
          },
          {
            'name': 'Music',
            'path': '/storage/emulated/0/Music',
            'icon': 'music',
          },
          {
            'name': 'Movies',
            'path': '/storage/emulated/0/Movies',
            'icon': 'videos',
          },
        ];
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          defaultPaths = [
            {
              'name': 'Downloads',
              'path': '$userProfile\\Downloads',
              'icon': 'download',
            },
            {
              'name': 'Documents',
              'path': '$userProfile\\Documents',
              'icon': 'documents',
            },
            {
              'name': 'Pictures',
              'path': '$userProfile\\Pictures',
              'icon': 'pictures',
            },
            {'name': 'Music', 'path': '$userProfile\\Music', 'icon': 'music'},
            {
              'name': 'Videos',
              'path': '$userProfile\\Videos',
              'icon': 'videos',
            },
          ];
        }
      } else {
        // 对于其他平台（Linux、macOS等），添加通用默认路径
        final home = Platform.environment['HOME'];
        if (home != null) {
          defaultPaths = [
            {
              'name': 'Documents',
              'path': '$home/Documents',
              'icon': 'documents',
            },
            {
              'name': 'Downloads',
              'path': '$home/Downloads',
              'icon': 'download',
            },
            {'name': 'Pictures', 'path': '$home/Pictures', 'icon': 'pictures'},
            {'name': 'Music', 'path': '$home/Music', 'icon': 'music'},
            {'name': 'Videos', 'path': '$home/Videos', 'icon': 'videos'},
          ];
        }
      }

      int addedCount = 0;
      for (final pathInfo in defaultPaths) {
        final dir = Directory(pathInfo['path']!);
        if (dir.existsSync()) {
          final favorite = FavoriteItem(
            id: '${DateTime.now().millisecondsSinceEpoch}_${pathInfo['name']}',
            name: pathInfo['name']!,
            path: pathInfo['path']!,
            iconName: pathInfo['icon'],
            createdAt: DateTime.now(),
          );

          final success = await favoritesSource.addFavorite(favorite);
          if (success) {
            addedCount++;
            logger.d('Added default favorite: ${favorite.name}');
          } else {
            logger.w('Failed to add default favorite: ${favorite.name}');
          }
        } else {
          logger.d('Skipping non-existent default path: ${pathInfo['path']}');
        }
      }

      logger.i('Added $addedCount default favorites');
    } catch (e) {
      logger.e('Error initializing default favorites: $e');
    }
  }

  /// 添加收藏夹
  Future<bool> addFavorite(FavoriteItem favorite) async {
    logger.i('FilePresenter.addFavorite called for: ${favorite.name}');
    try {
      final success = await favoritesSource.addFavorite(favorite);
      if (success) {
        viewModel.addFavorite(favorite);
        logger.i('Favorite added successfully');
      } else {
        logger.w('Failed to add favorite');
      }
      return success;
    } catch (e) {
      logger.e('Error adding favorite: $e');
      return false;
    }
  }

  /// 删除收藏夹
  Future<bool> removeFavorite(String id) async {
    logger.i('FilePresenter.removeFavorite called for id: $id');
    try {
      final success = await favoritesSource.removeFavorite(id);
      if (success) {
        viewModel.removeFavorite(id);
        logger.i('Favorite removed successfully');
      } else {
        logger.w('Failed to remove favorite');
      }
      return success;
    } catch (e) {
      logger.e('Error removing favorite: $e');
      return false;
    }
  }

  /// 更新收藏夹
  Future<bool> updateFavorite(FavoriteItem updatedFavorite) async {
    logger.i(
      'FilePresenter.updateFavorite called for: ${updatedFavorite.name}',
    );
    try {
      final success = await favoritesSource.updateFavorite(updatedFavorite);
      if (success) {
        viewModel.updateFavorite(updatedFavorite);
        logger.i('Favorite updated successfully');
      } else {
        logger.w('Failed to update favorite');
      }
      return success;
    } catch (e) {
      logger.e('Error updating favorite: $e');
      return false;
    }
  }

  /// 更新收藏夹的最后访问时间
  Future<void> updateFavoriteLastAccessed(String id) async {
    logger.d('FilePresenter.updateFavoriteLastAccessed called for id: $id');
    try {
      await favoritesSource.updateLastAccessed(id);
    } catch (e) {
      logger.w('Error updating favorite last accessed time: $e');
    }
  }

  // 最近文件相关方法

  /// 加载最近访问的文件
  Future<void> loadRecentFiles() async {
    logger.i('FilePresenter.loadRecentFiles called');
    try {
      // 先清理无效的文件
      await recentFilesSource.cleanupRecentFiles();

      // 获取最近文件，并过滤掉文件夹
      final recentFiles = await recentFilesSource.getRecentFiles();
      final fileItems = recentFiles
          .where((rf) => !rf.isDirectory) // 只保留文件，不显示文件夹
          .map((rf) => rf.toFileItem())
          .toList();

      viewModel.setFiles(fileItems);
      viewModel.setCurrentPath(''); // 清空路径表示这是最近文件视图
      viewModel.setRootPath(''); // 设置根路径为空
      viewModel.setIsRecentFilesMode(true); // 设置为最近文件模式

      logger.d(
        'Loaded ${fileItems.length} recent files (folders filtered out)',
      );
    } catch (e) {
      logger.e('Error loading recent files: $e');
      viewModel.setFiles([]);
    }
  }

  /// 添加文件到最近访问记录
  Future<void> addToRecentFiles(FileItem file) async {
    // 只记录文件，不记录文件夹
    if (file.isDirectory) {
      logger.d('Skipping folder from recent: ${file.name}');
      return;
    }

    logger.d('Adding file to recent: ${file.name}');
    try {
      final recentFile = RecentFileItem.fromFileItem(file);
      await recentFilesSource.addRecentFile(recentFile);
    } catch (e) {
      logger.w('Error adding file to recent: $e');
    }
  }

  // 主题相关方法

  /// 初始化主题设置
  Future<void> initializeTheme() async {
    logger.i('FilePresenter.initializeTheme called');
    try {
      final themeMode = await themeSource.getThemeMode();
      viewModel.setThemeMode(themeMode);

      logger.d('Theme initialized - mode: $themeMode');
    } catch (e) {
      logger.e('Error initializing theme: $e');
    }
  }

  /// 切换主题
  Future<void> toggleTheme() async {
    logger.i('FilePresenter.toggleTheme called');
    try {
      final oldMode = viewModel.themeMode;
      viewModel.toggleTheme();
      final newMode = viewModel.themeMode;
      logger.d('Theme mode changed from $oldMode to $newMode');

      final success = await themeSource.saveThemeMode(newMode);

      if (success) {
        // 验证保存是否成功
        final savedMode = await themeSource.getThemeMode();
        logger.d('Verified saved theme mode: $savedMode');

        if (savedMode != newMode) {
          logger.w('Theme mode mismatch! Expected: $newMode, Got: $savedMode');
          // 重新设置为正确的值
          viewModel.setThemeMode(newMode);
        }

        logger.i('Theme toggled successfully to: $newMode');
      } else {
        logger.w('Failed to save theme mode, reverting to: $oldMode');
        // 如果保存失败，恢复原来的模式
        viewModel.setThemeMode(oldMode);
      }
    } catch (e) {
      logger.e('Error toggling theme: $e');
    }
  }

  /// 设置特定主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    logger.i('FilePresenter.setThemeMode called with: $mode');
    try {
      viewModel.setThemeMode(mode);
      final success = await themeSource.saveThemeMode(mode);

      if (success) {
        logger.i('Theme mode set successfully to: $mode');
      } else {
        logger.w('Failed to save theme mode');
      }
    } catch (e) {
      logger.e('Error setting theme mode: $e');
    }
  }

  /// 搜索相关方法

  /// 切换搜索模式
  void toggleSearch() {
    logger.d('FilePresenter.toggleSearch called');
    viewModel.toggleSearchMode();
  }

  // 收藏文件相关方法

  /// 初始化收藏文件列表
  Future<void> initializeFavoriteFiles() async {
    logger.i('FilePresenter.initializeFavoriteFiles called');
    try {
      final favoriteFiles = await favoriteFilesSource.getFavoriteFiles();
      viewModel.setFavoriteFiles(favoriteFiles);
      logger.d('Favorite files initialized - count: ${favoriteFiles.length}');
    } catch (e) {
      logger.e('Error initializing favorite files: $e');
    }
  }

  /// 加载收藏文件列表（供Tab切换时调用）
  Future<void> loadFavoriteFiles() async {
    logger.i('FilePresenter.loadFavoriteFiles called');
    try {
      viewModel.setLoading(true);

      // 从本地数据源加载收藏文件列表
      final favoriteFiles = await favoriteFilesSource.getFavoriteFiles();
      logger.d('Loaded ${favoriteFiles.length} favorite files from storage');
      viewModel.setFavoriteFiles(favoriteFiles);

      // 将收藏文件转换为FileItem列表以便在UI中显示
      final fileItems = <FileItem>[];
      int existingCount = 0;
      int missingCount = 0;

      for (final favoriteFile in favoriteFiles) {
        try {
          final file = File(favoriteFile.filePath);
          if (file.existsSync()) {
            final fileItem = FileItem(
              name: path.basename(favoriteFile.filePath),
              path: favoriteFile.filePath,
              size: file.lengthSync(),
              modified: file.lastModifiedSync(),
              isDirectory: false,
              addedTime: favoriteFile.addedTime, // 传递收藏时间
            );
            fileItems.add(fileItem);
            existingCount++;
          } else {
            missingCount++;
            logger.w(
              'Favorite file no longer exists: ${favoriteFile.filePath}',
            );
          }
        } catch (e) {
          logger.w(
            'Error processing favorite file ${favoriteFile.filePath}: $e',
          );
        }
      }

      viewModel.setFiles(fileItems);
      viewModel.setLoading(false);

      logger.i(
          'Loaded ${fileItems.length} favorite files for display (existing: $existingCount, missing: $missingCount)');
    } catch (e) {
      logger.e('Error loading favorite files: $e');
      viewModel.setLoading(false);
    }
  }

  /// 切换文件收藏状态
  Future<bool> toggleFavoriteFile(FileItem file) async {
    logger.i('FilePresenter.toggleFavoriteFile called for: ${file.path}');
    try {
      final isFavorite = viewModel.isFavoriteFile(file.path);
      final isInFavoriteTab = viewModel.currentTab == TabView.favorite;

      if (isFavorite) {
        // 取消收藏
        final success = await favoriteFilesSource.removeFavoriteFile(file.path);
        if (success) {
          viewModel.removeFavoriteFile(file.path);
          logger.i('File removed from favorites: ${file.path}');

          // 如果当前在收藏Tab，立即重新加载收藏列表以更新UI
          if (isInFavoriteTab) {
            logger.d('Currently in favorite tab, reloading favorite files');
            await loadFavoriteFiles();
          }

          return false;
        }
      } else {
        // 添加收藏
        final favoriteFile = FavoriteFileItem(
          filePath: file.path,
          addedTime: DateTime.now(),
        );
        final success = await favoriteFilesSource.addFavoriteFile(favoriteFile);
        if (success) {
          viewModel.addFavoriteFile(favoriteFile);
          logger.i('File added to favorites: ${file.path}');

          // 如果当前在收藏Tab，立即重新加载收藏列表以更新UI
          if (isInFavoriteTab) {
            logger.d('Currently in favorite tab, reloading favorite files');
            await loadFavoriteFiles();
          }

          return true;
        }
      }

      return isFavorite;
    } catch (e) {
      logger.e('Error toggling favorite file: $e');
      return viewModel.isFavoriteFile(file.path);
    }
  }

  /// 批量添加收藏文件
  ///
  /// 一次性添加多个文件到收藏，适用于批量操作场景
  /// 返回 (成功数量, 失败数量)
  Future<(int, int)> batchAddFavoriteFiles(List<FileItem> files) async {
    logger.i(
        'FilePresenter.batchAddFavoriteFiles called for ${files.length} files');

    try {
      // 只处理文件，过滤掉文件夹
      final fileItems = files.where((f) => !f.isDirectory).toList();

      if (fileItems.isEmpty) {
        logger.w('No files to add to favorites (all are directories)');
        return (0, 0);
      }

      // 构建收藏文件列表
      final now = DateTime.now();
      final favoriteFiles = fileItems
          .map((file) => FavoriteFileItem(
                filePath: file.path,
                addedTime: now,
              ))
          .toList();

      // 批量添加
      final addedCount =
          await favoriteFilesSource.batchAddFavoriteFiles(favoriteFiles);
      final failedCount = favoriteFiles.length - addedCount;

      // 更新ViewModel（批量添加，延迟通知避免UI冲突）
      if (addedCount > 0) {
        // 收集需要添加的文件
        final filesToAdd = <FavoriteFileItem>[];
        for (final favoriteFile in favoriteFiles) {
          if (!viewModel.isFavoriteFile(favoriteFile.filePath)) {
            filesToAdd.add(favoriteFile);
          }
        }
        
        // 批量添加到viewModel（内部延迟通知）
        if (filesToAdd.isNotEmpty) {
          viewModel.batchAddFavoriteFiles(filesToAdd);
        }

        // 如果当前在收藏Tab，重新加载
        if (viewModel.currentTab == TabView.favorite) {
          await loadFavoriteFiles();
        }
      }

      logger.i(
          'Batch add favorites completed: $addedCount succeeded, $failedCount failed');
      return (addedCount, failedCount);
    } catch (e, stackTrace) {
      logger.e('Error batch adding favorite files: $e\n$stackTrace');
      return (0, files.length);
    }
  }

  /// 批量移除收藏文件
  ///
  /// 一次性移除多个文件的收藏，适用于批量操作场景
  /// 返回 (成功数量, 失败数量)
  Future<(int, int)> batchRemoveFavoriteFiles(List<String> filePaths) async {
    logger.i(
        'FilePresenter.batchRemoveFavoriteFiles called for ${filePaths.length} files');

    try {
      // 只处理文件，过滤掉文件夹
      final filesToRemove = <String>[];
      for (final path in filePaths) {
        final entity = FileSystemEntity.typeSync(path);
        if (entity == FileSystemEntityType.file) {
          filesToRemove.add(path);
        }
      }

      if (filesToRemove.isEmpty) {
        logger.w('No files to remove from favorites (all are directories)');
        return (0, 0);
      }

      // 批量移除
      final removedCount =
          await favoriteFilesSource.batchRemoveFavoriteFiles(filesToRemove);
      final failedCount = filesToRemove.length - removedCount;

      // 更新ViewModel
      if (removedCount > 0) {
        // 使用批量移除方法，避免多次notifyListeners触发"deactivated widget's ancestor"错误
        viewModel.batchRemoveFavoriteFiles(filesToRemove);

        // 如果当前在收藏Tab，延迟重新加载以避免在PopupMenu关闭前触发notifyListeners
        if (viewModel.currentTab == TabView.favorite) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await loadFavoriteFiles();
          });
        }
      }

      logger.i(
          'Batch remove favorites completed: $removedCount succeeded, $failedCount failed');
      return (removedCount, failedCount);
    } catch (e, stackTrace) {
      logger.e('Error batch removing favorite files: $e\n$stackTrace');
      return (0, filePaths.length);
    }
  }

  /// 更新收藏文件访问信息
  Future<void> updateFavoriteFileAccess(String filePath) async {
    logger.d('Updating favorite file access: $filePath');
    try {
      await favoriteFilesSource.updateFileAccess(filePath);

      // 重新加载收藏列表以更新UI
      final favoriteFiles = await favoriteFilesSource.getFavoriteFiles();
      viewModel.setFavoriteFiles(favoriteFiles);
    } catch (e) {
      logger.w('Error updating favorite file access: $e');
    }
  }

  /// 刷新当前目录
  Future<void> refreshCurrent() async {
    logger.i('FilePresenter.refreshCurrent called');
    // 根据当前Tab类型刷新相应内容
    if (viewModel.currentTab == TabView.favorite) {
      logger.d('Refreshing favorite files');
      await loadFavoriteFiles();
    } else if (viewModel.isRecentFilesMode) {
      logger.d('Refreshing recent files');
      await loadRecentFiles();
    } else {
      // 否则刷新当前目录
      await loadFiles(viewModel.currentPath);
    }
  }

  // 分类相关方法

  /// 按文件类型扫描文件
  Future<List<FileItem>> scanFilesByCategory(CategoryType categoryType) async {
    logger.i('FilePresenter.scanFilesByCategory called for: $categoryType');

    try {
      // 获取分类信息
      final categoryInfo = CategoryInfo.getInfoByType(categoryType);
      if (categoryInfo == null) {
        logger.w('Unknown category type: $categoryType');
        return [];
      }

      List<FileItem> categoryFiles = [];

      // 确定扫描路径
      List<String> scanPaths = [];

      if (categoryType == CategoryType.downloads) {
        // 下载文件夹特殊处理
        scanPaths = await _getDownloadPaths();
      } else {
        // 其他类型扫描常见目录
        scanPaths = await getCommonScanPaths();
      }

      logger.d('Scanning paths for ${categoryInfo.name}: $scanPaths');

      // 扫描每个路径
      for (final scanPath in scanPaths) {
        final files = await _scanCategoryInPath(scanPath, categoryInfo);
        categoryFiles.addAll(files);
      }

      // 去重（同一文件可能在多个路径中）
      final uniqueFiles = <String, FileItem>{};
      for (final file in categoryFiles) {
        uniqueFiles[file.path] = file;
      }

      final result = uniqueFiles.values.toList();

      // 按修改时间排序（最新的在前）
      result.sort((a, b) => b.modified.compareTo(a.modified));

      logger.i(
        'Found ${result.length} files for category ${categoryInfo.name}',
      );
      return result;
    } catch (e) {
      logger.e('Error scanning files by category $categoryType: $e');
      rethrow;
    }
  }

  /// 打开分类视图
  Future<bool> openCategory(CategoryType categoryType) async {
    logger.i('FilePresenter.openCategory called for: $categoryType');

    try {
      // 获取分类信息
      final categoryInfo = CategoryInfo.getInfoByType(categoryType);
      if (categoryInfo == null) {
        logger.w('Unknown category type: $categoryType');
        return false;
      }

      // 导航到分类页面
      // 这里我们先返回true，实际的页面导航会在UI层处理
      return true;
    } catch (e) {
      logger.e('Error opening category $categoryType: $e');
      return false;
    }
  }

  /// 获取下载路径
  Future<List<String>> _getDownloadPaths() async {
    final paths = <String>[];

    try {
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          paths.addAll(['$userProfile\\Downloads', '$userProfile\\Desktop']);
        }
      } else if (Platform.isAndroid) {
        paths.addAll([
          '/storage/emulated/0/Download',
          '/sdcard/Download',
          '/storage/emulated/0/Downloads',
          '/sdcard/Downloads',
        ]);
      } else {
        final home = Platform.environment['HOME'];
        if (home != null) {
          paths.addAll(['$home/Downloads', '$home/Desktop']);
        }
      }
    } catch (e) {
      logger.w('Error getting download paths: $e');
    }

    // 过滤存在的路径
    final existingPaths = <String>[];
    for (final path in paths) {
      if (Directory(path).existsSync()) {
        existingPaths.add(path);
      }
    }

    return existingPaths;
  }

  /// Android 系统预定义目录名称（单一数据源）
  ///
  /// 这些目录会在 _getSystemPaths() 中构建完整路径
  /// 也会在 _discoverUserFolders() 中用于跳过重复扫描
  static const List<String> _androidSystemFolderNames = [
    'DCIM',
    'Pictures',
    'Music',
    'Movies',
    'Videos',
    'Video', // 有些设备用 Video 而不是 Videos
    'Documents',
    'Download',
    'Downloads',
    'Podcasts',
    'Audiobooks',
    'Recordings',
    'Sounds',
    'Voice Recorder',
    'Screenshots',
    'Screen recordings',
    'Screenrecords',
    'Books',
  ];

  /// Windows/Linux 系统预定义目录名称
  static const List<String> _desktopSystemFolderNames = [
    'Documents',
    'Pictures',
    'Music',
    'Videos',
    'Desktop',
    'Downloads',
  ];

  /// 应该排除的文件夹（系统/应用数据）
  ///
  /// ⚠️ 注意：此字段暴露为public以供文件清理功能使用
  /// ⚠️ 不要在此列表中添加已在系统目录列表中的文件夹（会被提前过滤）
  static const List<String> excludedFolders = [
    'Android', // Android应用数据
    '.thumbnails', // 缩略图缓存
    '.cache', // 缓存（隐藏）
    'cache', // 缓存（普通）
    '.trash', // 回收站
    'Alarms', // 系统铃声
    'Notifications', // 通知音
    'Ringtones', // 铃声
    'lost+found', // Android系统目录
  ];

  /// 获取常见扫描路径（混合策略：系统目录 + 用户自定义文件夹）
  ///
  /// ⚠️ 注意：此方法暴露为public以供文件清理功能使用
  /// 外部调用时请注意遵循相同的扫描策略
  Future<List<String>> getCommonScanPaths() async {
    final paths = <String>[];

    try {
      debugPrint('\n========== getCommonScanPaths() 开始 ==========');

      // 阶段1: 添加系统预定义目录（已知的高价值路径）
      final systemPaths = await _getSystemPaths();
      paths.addAll(systemPaths);
      logger.d('System paths: ${systemPaths.length}');
      debugPrint('[路径发现] 阶段1-系统路径: ${systemPaths.length} 个');
      for (var i = 0; i < systemPaths.length && i < 5; i++) {
        debugPrint('  系统路径示例 ${i + 1}: ${systemPaths[i]}');
      }

      // 阶段2: 发现用户自定义文件夹（根目录第一层扫描）
      final discoveredPaths = await _discoverUserFolders();
      paths.addAll(discoveredPaths);
      logger.d('Discovered user folders: ${discoveredPaths.length}');
      debugPrint('[路径发现] 阶段2-用户文件夹: ${discoveredPaths.length} 个');
      for (var i = 0; i < discoveredPaths.length; i++) {
        debugPrint('  用户文件夹 ${i + 1}: ${discoveredPaths[i]}');
      }
    } catch (e) {
      logger.w('Error getting common scan paths: $e');
    }

    debugPrint('[路径发现] 合并前总数: ${paths.length} 个');

    // 去重并过滤存在的路径
    final existingPaths = <String>[];
    final seen = <String>{};
    for (final path in paths) {
      if (!seen.contains(path) && Directory(path).existsSync()) {
        existingPaths.add(path);
        seen.add(path);
      }
    }

    logger.i('Total scan paths: ${existingPaths.length}');
    debugPrint('[路径发现] 最终结果: ${existingPaths.length} 个有效路径');
    debugPrint('==========================================\n');
    return existingPaths;
  }

  /// 获取系统预定义目录
  Future<List<String>> _getSystemPaths() async {
    final paths = <String>[];

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        // 使用统一定义的系统目录列表
        for (final folderName in _desktopSystemFolderNames) {
          paths.add('$userProfile\\$folderName');
        }
      }
    } else if (Platform.isAndroid) {
      // 使用统一定义的系统目录列表
      const baseAndroidPath = '/storage/emulated/0';
      for (final folderName in _androidSystemFolderNames) {
        paths.add('$baseAndroidPath/$folderName');
      }

      // ✅ 优化2: 扫描所有外部存储设备（SD卡等）
      try {
        final storageRoot = Directory('/storage');
        if (storageRoot.existsSync()) {
          await for (final entity in storageRoot.list()) {
            if (entity is Directory) {
              final name = path.basename(entity.path);
              // 跳过特殊目录
              if (name == 'self' || name == 'emulated') continue;

              // 这是外部存储设备（SD卡等）
              final externalPath = entity.path;
              if (Directory(externalPath).existsSync()) {
                logger.d('Found external storage: $externalPath');
                // 添加外部存储根目录
                paths.add(externalPath);

                // 添加外部存储的标准子目录
                // 未完成，待优化（外部存储里的所有的目录 应被认为是扫描路径）
                paths.addAll([
                  '$externalPath/DCIM',
                  '$externalPath/Pictures',
                  '$externalPath/Music',
                  '$externalPath/Movies',
                  '$externalPath/Documents',
                  '$externalPath/Download',
                  '$externalPath/Downloads',
                ]);
              }
            }
          }
        }
      } catch (e) {
        logger.w('Error scanning external storage: $e');
      }
    } else {
      final home = Platform.environment['HOME'];
      if (home != null) {
        // 使用统一定义的系统目录列表
        for (final folderName in _desktopSystemFolderNames) {
          paths.add('$home/$folderName');
        }
      }
    }

    return paths;
  }

  /// 发现存储根目录下的用户自定义文件夹
  Future<List<String>> _discoverUserFolders() async {
    final discovered = <String>[];

    try {
      debugPrint('\n[用户文件夹发现] 开始扫描根目录...');

      // 确定扫描根目录
      String? rootPath;
      if (Platform.isAndroid) {
        rootPath = '/storage/emulated/0';
      } else if (Platform.isWindows) {
        rootPath = Platform.environment['USERPROFILE'];
      } else {
        rootPath = Platform.environment['HOME'];
      }

      if (rootPath == null || !Directory(rootPath).existsSync()) {
        logger.w('Root path not found or not exists');
        debugPrint('[用户文件夹发现] ⚠️ 根目录不存在: $rootPath');
        return discovered;
      }

      logger.d('Discovering user folders in: $rootPath');
      debugPrint('[用户文件夹发现] 扫描根目录: $rootPath');

      // 扫描根目录第一层（只扫描一层，不递归）
      final entities = Directory(rootPath).listSync(followLinks: false);
      debugPrint('[用户文件夹发现] listSync() 返回了 ${entities.length} 个项目');

      var skippedHidden = 0;
      var skippedSystem = 0;
      var skippedExcluded = 0;
      var foundCount = 0;

      for (final entity in entities) {
        if (entity is! Directory) continue;

        final folderName = path.basename(entity.path);

        // 跳过隐藏文件夹
        if (folderName.startsWith('.')) {
          skippedHidden++;
          continue;
        }

        // 跳过已知系统目录（避免重复）
        // 根据平台选择对应的系统目录列表
        final systemFolders = Platform.isAndroid
            ? _androidSystemFolderNames
            : _desktopSystemFolderNames;
        if (systemFolders.contains(folderName)) {
          skippedSystem++;
          debugPrint('[用户文件夹发现] 跳过系统目录: $folderName');
          continue;
        }

        // 跳过应用/系统数据目录
        if (excludedFolders.contains(folderName)) {
          skippedExcluded++;
          debugPrint('[用户文件夹发现] 跳过排除目录: $folderName');
          continue;
        }

        // 这是用户自定义文件夹，添加到列表
        discovered.add(entity.path);
        foundCount++;
        logger.d('Found user folder: ${entity.path}');
        debugPrint('[用户文件夹发现] ✅ 发现用户文件夹 $foundCount: ${entity.path}');
      }

      debugPrint(
          '[用户文件夹发现] 统计: 总计=${entities.length}, 隐藏=$skippedHidden, 系统=$skippedSystem, 排除=$skippedExcluded, 发现=$foundCount');
      logger.i('Discovered ${discovered.length} user-defined folders');
    } catch (e) {
      logger.w('Error discovering user folders: $e');
      debugPrint('[用户文件夹发现] ❌ 错误: $e');
    }

    return discovered;
  }

  /// 在指定路径中扫描分类文件
  Future<List<FileItem>> _scanCategoryInPath(
    String path,
    CategoryInfo categoryInfo,
  ) async {
    final files = <FileItem>[];

    try {
      final directory = Directory(path);
      if (!directory.existsSync()) {
        return files;
      }

      // 下载分类：接受所有文件类型
      // 其他分类：按扩展名过滤
      final acceptAllTypes = categoryInfo.type == CategoryType.downloads;

      // 递归扫描，限制深度为5层
      await _scanDirectory(
        directory,
        categoryInfo,
        files,
        0,
        5,
        acceptAllTypes: acceptAllTypes,
      );
    } catch (e) {
      logger.w('Error scanning category in path $path: $e');
    }

    return files;
  }

  /// 递归扫描目录
  Future<void> _scanDirectory(
    Directory directory,
    CategoryInfo categoryInfo,
    List<FileItem> files,
    int currentDepth,
    int maxDepth, {
    bool acceptAllTypes = false,
  }) async {
    if (currentDepth >= maxDepth) {
      return;
    }

    try {
      // 使用异步list()替代同步listSync()，避免阻塞UI
      await for (final entity in directory.list(followLinks: false)) {
        try {
          final name = path.basename(entity.path);

          // 跳过隐藏文件/文件夹
          if (name.startsWith('.')) continue;

          if (entity is File) {
            // 下载分类：接受所有文件
            if (acceptAllTypes) {
              final fileItem = FileItem.fromEntity(entity);
              files.add(fileItem);
            } else {
              // 其他分类：检查文件扩展名
              final extension = path.extension(entity.path).toLowerCase();
              if (extension.isNotEmpty) {
                final cleanExtension = extension.substring(1); // 移除点号
                if (categoryInfo.extensions.contains(cleanExtension)) {
                  final fileItem = FileItem.fromEntity(entity);
                  files.add(fileItem);
                }
              }
            }
          } else if (entity is Directory) {
            // 跳过应用/系统数据目录
            if (excludedFolders.contains(name)) continue;

            // 递归扫描子目录
            await _scanDirectory(
              entity,
              categoryInfo,
              files,
              currentDepth + 1,
              maxDepth,
              acceptAllTypes: acceptAllTypes,
            );
          }
        } catch (e) {
          // 忽略单个文件的错误，继续扫描
          logger.d('Error processing entity ${entity.path}: $e');
        }
      }
    } catch (e) {
      logger.w('Error listing directory ${directory.path}: $e');
    }
  }
}
