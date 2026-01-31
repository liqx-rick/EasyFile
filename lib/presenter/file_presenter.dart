import 'dart:io';

import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/database/app_trash_database.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/platform/mediastore_scanner_channel.dart';
import 'package:easyfile/core/services/search_history_service.dart';
import 'package:easyfile/core/services/theme_settings_service.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/data/models/favorite_file_item.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/new_file_item.dart';
import 'package:easyfile/data/models/recent_file_item.dart';
import 'package:easyfile/data/repositories/file_repository.dart';
import 'package:easyfile/data/sources/favorite_files_local_source.dart';
import 'package:easyfile/data/sources/new_files_local_source.dart';
import 'package:easyfile/data/sources/new_files_scanner.dart';
import 'package:easyfile/data/sources/recent_files_local_source.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/utils/thumbnail_cache_manager.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class FilePresenter {
  /// Android 存储基础路径常量
  static const String _androidStorageBase = '/storage/emulated/0';

  final FileRepository repository;
  final FileViewModel viewModel;
  final FavoriteFilesLocalSource favoriteFilesSource;
  final RecentFilesLocalSource recentFilesSource;
  final NewFilesScanner newFilesScanner;
  final NewFilesLocalSource newFilesLocalSource;
  final ThemeSettingsService themeSettingsService;
  final AppTrashDatabase trashDatabase;

  FilePresenter({
    required this.repository,
    required this.viewModel,
    required this.favoriteFilesSource,
    required this.recentFilesSource,
    required this.newFilesScanner,
    required this.newFilesLocalSource,
    required this.themeSettingsService,
    required this.trashDatabase,
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

    // 过滤已标记删除的文件
    final deletedPaths = await trashDatabase.getDeletedFilePaths();
    final visibleFiles = files.where((file) => !deletedPaths.contains(file.path)).toList();

    // 设置文件列表（使用过滤后的列表）
    viewModel.setFiles(visibleFiles);

    // 设置加载状态
    viewModel.setLoading(false);

    logger.d(
      'ViewModel updated - currentPath: ${viewModel.currentPath}, filesCount: ${viewModel.files.length}, hasError: ${viewModel.errorMessage != null}',
    );
    logger.d('⏱️ [PERF] loadFiles完成，等待UI rebuild...');
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
      logger.i('File deleted successfully');

      // 删除文件时，立即清理收藏记录
      // 即使用户以后恢复文件，也不应该显示收藏状态
      if (viewModel.isFavoriteFile(file.path)) {
        logger.i('Removing favorite record for deleted file: ${file.path}');
        await favoriteFilesSource.removeFavoriteFile(file.path);
        viewModel.removeFavoriteFile(file.path);
      }

      // 注意：不再删除缩略图缓存，保留缓存以优化性能
      // 依赖 RealVideoThumbnail 的 didUpdateWidget 检测路径变化来更新显示

      // 从列表中移除删除的文件（立即更新UI）
      // 各个页面会在 onRefresh 回调中重新加载数据
      logger.i('Removing deleted file from list');
      viewModel.removeFileFromList(file.path);
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
    final cacheManager = ThumbnailCacheManager();

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

            // 删除成功后，立即清理收藏记录
            if (viewModel.isFavoriteFile(filePath)) {
              logger.d('Removing favorite record for deleted file: $filePath');
              await favoriteFilesSource.removeFavoriteFile(filePath);
              viewModel.removeFavoriteFile(filePath);
            }

            // 从ViewModel列表中移除（同步 _files, _allFiles, _newFiles）
            viewModel.removeFileFromList(filePath);

            // 清理视频缩略图缓存
            if (AppConfig.instance.fileTypes.isVideoFile(fileItem.name)) {
              try {
                await cacheManager.deleteCached(filePath);
                logger.d('Deleted video thumbnail cache for: $filePath');
              } catch (e) {
                logger.w('Failed to delete thumbnail cache: $e');
              }
            }
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

      // 如果复制后的文件路径在垃圾桶中，从垃圾桶移除
      // （可能之前删除过同名文件，现在又复制了新文件过来）
      final deletedPaths = await trashDatabase.getDeletedFilePaths();
      if (deletedPaths.contains(copiedFile.path)) {
        logger.w('Copied file path exists in trash database, removing: ${copiedFile.path}');
        await trashDatabase.removeFromTrash(copiedFile.path);
      }

      // 判断是否应该将复制的文件添加到当前列表
      // 对于分类页面，总是通知添加（让分类页面自己判断是否属于当前分类）
      // 对于浏览器页面，只有复制到当前目录时才添加
      bool shouldAddToList = false;

      if (destinationPath == viewModel.currentPath) {
        logger.d('File copied to current browsing directory');
        shouldAddToList = true;
      } else if (viewModel.currentPath.isEmpty) {
        // currentPath为空，可能是分类页面，总是通知
        logger.d('Current path is empty (category page?), notifying file addition');
        shouldAddToList = true;
      } else {
        logger.d('File copied to different directory, not adding to current list');
        logger.d('Destination: $destinationPath, Current path: ${viewModel.currentPath}');
      }

      if (shouldAddToList) {
        // 检查文件是否已在列表中（避免重复添加）
        final alreadyExists = viewModel.files.any((f) => f.path == copiedFile.path);
        if (alreadyExists) {
          logger.w('File already exists in list, skipping add: ${copiedFile.path}');
        } else {
          logger.i('Adding copied file to list: ${copiedFile.path}');
          viewModel.addFileToList(copiedFile);
          logger.i('File added to list. New list size: ${viewModel.files.length}');
        }
      } else {
        // 即使不添加到 files 列表，也要通知全局监听器
        // 让其他页面（如大文件页面、分类页面）自行判断是否需要处理
        logger.d('Notifying global listeners about copied file');
        viewModel.notifyFileAdded(copiedFile);
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
      logger.i('File moved successfully');

      // 如果移动后的文件路径在垃圾桶中，从垃圾桶移除
      // （可能之前删除过同名文件，现在又移动了新文件过来）
      final deletedPaths = await trashDatabase.getDeletedFilePaths();
      if (deletedPaths.contains(movedFile.path)) {
        logger.w('Moved file path exists in trash database, removing: ${movedFile.path}');
        await trashDatabase.removeFromTrash(movedFile.path);
      }

      // 如果源文件被收藏，同步更新收藏记录中的路径
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

      // 移动文件后，根据原文件位置和目标位置决定如何更新列表
      // 判断逻辑：通过检查原文件是否在 currentPath 中来判断页面类型
      // 关键：只有当 currentPath 非空且原文件确实在这个目录中时，才是目录浏览模式
      // 1. currentPath 为空 → 分类/全局页面，更新路径继续显示
      // 2. 原文件不在 currentPath 中 → 分类/全局页面，更新路径继续显示
      // 3. 原文件在 currentPath 且移动到 currentPath → 更新路径（重命名）
      // 4. 原文件在 currentPath 且移动到其他目录 → 从列表移除

      final originalFileDir = path.dirname(file.path);
      final movedFileDir = path.dirname(movedFile.path);
      final currentPath = viewModel.currentPath;

      logger.d('Original file directory: $originalFileDir');
      logger.d('Moved file directory: $movedFileDir');
      logger.d('Current browsing path: "$currentPath"');

      // 判断是否是目录浏览模式：
      // 1. currentPath 不为空
      // 2. 且原文件确实在这个目录中
      final isDirectoryBrowsing = currentPath.isNotEmpty && originalFileDir == currentPath;

      logger.d('Is directory browsing mode: $isDirectoryBrowsing');

      if (!isDirectoryBrowsing) {
        // 非目录浏览模式（分类页面、全局搜索等）：更新路径继续显示
        logger.i('Not directory browsing mode, updating file path to continue display');
        viewModel.updateFileInList(file.path, movedFile);
      } else if (movedFileDir == currentPath) {
        // 目录浏览模式：移动到当前目录（实际上是重命名）
        logger.i('File moved within current directory, updating file path');
        viewModel.updateFileInList(file.path, movedFile);
      } else {
        // 目录浏览模式：移动到其他目录，从当前列表移除
        logger.i('File moved to different directory, removing from current list');
        viewModel.removeFileFromList(file.path);
      }

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
            // 在ViewModel列表中更新文件路径（同步 _files, _allFiles, _newFiles）
            viewModel.updateFileInList(filePath, movedFile);
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

    const platform = MethodChannel('com.guangqi.easyfile/share');

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
        // 获取精确的MIME类型以便正确显示缩略图
        final mimeType = FileUtils.getMimeType(existingFilePaths[0]);
        logger.d('Sharing file with MIME type: $mimeType');

        await platform.invokeMethod('shareFile', {
          'filePath': existingFilePaths[0],
          'mimeType': mimeType,
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

  // 最近文件相关方法

  /// 加载最近访问的文件
  Future<void> loadRecentFiles() async {
    logger.i('FilePresenter.loadRecentFiles called');
    try {
      // 先清理无效的文件
      await recentFilesSource.cleanupRecentFiles();

      // 获取文件类型配置
      final fileTypes = AppConfig.instance.fileTypes;

      // 获取最近文件，并过滤掉文件夹和不支持的文件类型
      final recentFiles = await recentFilesSource.getRecentFiles();
      final fileItems = recentFiles
          .where((rf) {
            // 过滤文件夹
            if (rf.isDirectory) return false;

            // **类型过滤**：只显示支持的文件类型（过滤缓存中的旧数据）
            // 排除APK文件（有单独的安装包管理模块）
            return fileTypes.isImageFile(rf.name) ||
                fileTypes.isVideoFile(rf.name) ||
                fileTypes.isAudioFile(rf.name) ||
                fileTypes.isDocumentFile(rf.name) ||
                fileTypes.isArchiveFile(rf.name);
          })
          .map((rf) => rf.toFileItem())
          .toList();

      viewModel.setFiles(fileItems);
      viewModel.setCurrentPath(''); // 清空路径表示这是最近文件视图
      viewModel.setRootPath(''); // 设置根路径为空
      viewModel.setIsRecentFilesMode(true); // 设置为最近文件模式

      logger.d(
        'Loaded ${fileItems.length} recent files (folders and unsupported types filtered out)',
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

    // **类型过滤**：只记录 FileTypesConfig 支持的文件类型
    // 注意：直接传入文件名，让 FileTypesConfig 内部提取扩展名
    final fileTypes = AppConfig.instance.fileTypes;
    final isSupported = fileTypes.isImageFile(file.name) ||
        fileTypes.isVideoFile(file.name) ||
        fileTypes.isAudioFile(file.name) ||
        fileTypes.isDocumentFile(file.name) ||
        fileTypes.isArchiveFile(file.name) ||
        fileTypes.isApkFile(file.name);

    if (!isSupported) {
      logger.d('Skipping unsupported file type from recent: ${file.name}');
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

  /// 同步 ViewModel 主题（主题在 main() 和 EasyFileApp 中已初始化）
  void initializeTheme() {
    try {
      viewModel.setThemeMode(themeSettingsService.themeMode);
    } catch (e) {
      logger.e('Error syncing theme: $e');
    }
  }

  /// 切换主题
  Future<void> toggleTheme() async {
    try {
      await themeSettingsService.toggleThemeMode();
      viewModel.setThemeMode(themeSettingsService.themeMode);
    } catch (e) {
      logger.e('Error toggling theme: $e');
    }
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    try {
      await themeSettingsService.setThemeMode(mode);
      viewModel.setThemeMode(mode);
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

    // ✅ 取消后台扫描以释放I/O资源
    newFilesScanner.cancelCurrentScan();

    try {
      viewModel.setLoading(true);

      // 从本地数据源加载收藏文件列表
      final favoriteFiles = await favoriteFilesSource.getFavoriteFiles();
      logger.d('Loaded ${favoriteFiles.length} favorite files from storage');
      viewModel.setFavoriteFiles(favoriteFiles);

      // ✅ 并行异步检查文件存在性和属性
      final fileItemFutures = favoriteFiles.map((favoriteFile) async {
        try {
          final file = File(favoriteFile.filePath);

          // ✅ 使用异步API
          final exists = await file.exists();
          if (!exists) {
            logger.w('Favorite file no longer exists: ${favoriteFile.filePath}');
            return null;
          }

          final stat = await file.stat();
          return FileItem(
            name: path.basename(favoriteFile.filePath),
            path: favoriteFile.filePath,
            size: stat.size,
            modified: stat.modified,
            isDirectory: false,
            addedTime: favoriteFile.addedTime,
          );
        } catch (e) {
          logger.w('Error processing favorite file ${favoriteFile.filePath}: $e');
          return null;
        }
      }).toList();

      // 等待所有异步操作完成
      final fileItems = await Future.wait(fileItemFutures);

      // 过滤掉null值（不存在的文件）
      final validFileItems = fileItems.whereType<FileItem>().toList();

      viewModel.setFiles(validFileItems);
      viewModel.setLoading(false);

      logger.i('Loaded ${validFileItems.length} favorite files for display');
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
    logger.i('FilePresenter.batchAddFavoriteFiles called for ${files.length} files');

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
      final addedCount = await favoriteFilesSource.batchAddFavoriteFiles(favoriteFiles);
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

      logger.i('Batch add favorites completed: $addedCount succeeded, $failedCount failed');
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
    logger.i('FilePresenter.batchRemoveFavoriteFiles called for ${filePaths.length} files');

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
      final removedCount = await favoriteFilesSource.batchRemoveFavoriteFiles(filesToRemove);
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

      logger.i('Batch remove favorites completed: $removedCount succeeded, $failedCount failed');
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

    // 新文件Tab：MediaStore自动监听，下拉刷新无需执行任何操作
    // （收藏和最近Tab由于内容通常不满屏，实际上也无法触发下拉刷新）
    if (viewModel.currentTab == TabView.newFiles) {
      logger.d('New files tab: MediaStore auto-refresh handles file changes');
      return;
    }

    // 根据当前Tab类型刷新相应内容
    if (viewModel.currentTab == TabView.favorite) {
      logger.d('Refreshing favorite files');
      await loadFavoriteFiles();
    } else if (viewModel.isRecentFilesMode) {
      logger.d('Refreshing recent files');
      await loadRecentFiles();
    } else {
      // 刷新当前目录
      await loadFiles(viewModel.currentPath);
    }
  }

  // 分类相关方法

  /// 按文件类型扫描文件
  ///
  /// 优先使用 MediaStore 扫描（快速），下载文件夹使用文件系统扫描（全面）
  ///
  /// [categoryType] 文件分类类型
  /// [useMediaStore] 是否使用 MediaStore，默认 true（智能选择）
  ///   - true: 图片/音乐/视频/文档使用 MediaStore，下载使用文件系统
  ///   - false: 强制使用文件系统扫描（测试对比用）
  Future<List<FileItem>> scanFilesByCategory(
    CategoryType categoryType, {
    bool useMediaStore = true,
    bool useHybridScan = true, // 新增：是否使用混合扫描（MediaStore + 路径扫描）
  }) async {
    logger.i(
        'FilePresenter.scanFilesByCategory called for: $categoryType (useMediaStore: $useMediaStore, useHybridScan: $useHybridScan)');

    try {
      // 🔥 混合扫描模式：MediaStore + 路径扫描，合并去重（类似微信推荐页面）
      if (useMediaStore && useHybridScan && categoryType != CategoryType.downloads) {
        return await _scanByCategoryHybrid(categoryType);
      }

      // 图片、音频、视频、文档使用 MediaStore 扫描（快速）
      if (useMediaStore && categoryType != CategoryType.downloads) {
        return await _scanByCategoryWithMediaStore(categoryType);
      }

      // 下载文件夹或强制文件系统扫描
      return await _scanByCategoryWithFileSystem(categoryType);
    } catch (e) {
      logger.e('Error scanning files by category $categoryType: $e');
      rethrow;
    }
  }

  /// 🔥 混合扫描：MediaStore + 路径扫描，合并去重
  ///
  /// 适用于所有支持 MediaStore 的分类：
  /// - 图片 (images)
  /// - 视频 (video)
  /// - 音乐 (music)
  /// - 文档 (documents)
  /// - APK (apk)
  /// - 压缩包 (archive)
  ///
  /// 解决 MediaStore 索引延迟问题：
  /// - 文件刚下载/保存时未被 MediaStore 索引
  /// - 文件从回收站恢复后未更新索引
  /// - 用户手动复制/移动文件后索引未更新
  Future<List<FileItem>> _scanByCategoryHybrid(CategoryType categoryType) async {
    final startTime = DateTime.now();
    logger.i('🔄 开始混合扫描 (MediaStore + FileSystem): $categoryType');

    // 1. MediaStore 扫描（快速，但可能遗漏新文件）
    final mediaStoreFiles = await _scanByCategoryWithMediaStore(categoryType);
    final mediaStoreTime = DateTime.now().difference(startTime);
    logger.i('  📱 MediaStore: ${mediaStoreFiles.length} 个文件 (${mediaStoreTime.inMilliseconds}ms)');

    // 2. 路径扫描（全面，但较慢）
    final pathScanFiles = await _scanByCategoryWithFileSystem(categoryType);
    final pathScanTime = DateTime.now().difference(startTime) - mediaStoreTime;
    logger.i('  📁 路径扫描: ${pathScanFiles.length} 个文件 (${pathScanTime.inMilliseconds}ms)');

    // 3. 合并去重（以路径为键）
    final fileMap = <String, FileItem>{};

    // 先加入 MediaStore 结果
    for (final file in mediaStoreFiles) {
      fileMap[file.path] = file;
    }

    // 再加入路径扫描结果（如果路径已存在，保留 MediaStore 的版本）
    int addedCount = 0;
    for (final file in pathScanFiles) {
      if (!fileMap.containsKey(file.path)) {
        fileMap[file.path] = file;
        addedCount++;
      }
    }

    final allFiles = fileMap.values.toList();
    final totalTime = DateTime.now().difference(startTime);

    logger.i('✅ 混合扫描完成: $categoryType');
    logger.i('  总文件数: ${allFiles.length}');
    logger.i('  MediaStore独有: ${mediaStoreFiles.length - (allFiles.length - addedCount)}');
    logger.i('  路径扫描补充: $addedCount 个 (MediaStore未索引的文件)');
    logger.i('  总耗时: ${totalTime.inMilliseconds}ms');

    if (addedCount > 0) {
      logger.w('⚠️ 发现 $addedCount 个文件未被 MediaStore 索引，已通过路径扫描补充');
    }

    return allFiles;
  }

  /// 使用 MediaStore 扫描分类文件（快速）
  Future<List<FileItem>> _scanByCategoryWithMediaStore(CategoryType categoryType) async {
    logger.i('Using MediaStore for category: $categoryType');

    final scanType = _categoryTypeToMediaScanType(categoryType);
    final files = await MediaStoreScannerChannel.scan(scanType);

    logger.i('MediaStore found ${files.length} files for category: $categoryType');
    return files;
  }

  /// 将 CategoryType 转换为 MediaScanType
  MediaScanType _categoryTypeToMediaScanType(CategoryType type) {
    switch (type) {
      case CategoryType.images:
        return MediaScanType.image;
      case CategoryType.music:
        return MediaScanType.audio;
      case CategoryType.video:
        return MediaScanType.video;
      case CategoryType.documents:
        return MediaScanType.document;
      case CategoryType.apk:
        return MediaScanType.apk;
      case CategoryType.archive:
        return MediaScanType.archive;
      default:
        throw ArgumentError('Unsupported category type for MediaStore: $type');
    }
  }

  /// 使用文件系统扫描分类文件（全面）
  Future<List<FileItem>> _scanByCategoryWithFileSystem(CategoryType categoryType) async {
    logger.i('Using file system scan for category: $categoryType');

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
        // 只使用 /storage/emulated/0/ 路径，避免 /sdcard 符号链接导致的重复
        // /sdcard 是 /storage/emulated/0 的符号链接，会导致同一文件被扫描两次
        paths.addAll([
          '$_androidStorageBase/Download',
          '$_androidStorageBase/Downloads',
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

  /// 检查是否为16进制临时文件夹
  ///
  /// 这类文件夹通常由浏览器下载缓存、下载管理器、应用市场等创建
  /// 例如: 4753E391CCF6FA2, 1060A0DAF0CAB42
  static bool _isHexTempFolder(String folderName) {
    // 检查是否为纯16进制字符（10-20位）且大写
    // 长度范围基于常见的UUID/GUID格式（去掉连字符）
    if (folderName.length < 10 || folderName.length > 32) {
      return false;
    }

    // 必须全部是16进制字符（0-9, A-F）
    final hexPattern = RegExp(r'^[0-9A-F]+$');
    return hexPattern.hasMatch(folderName);
  }

  /// 获取常见扫描路径（混合策略：系统目录 + 用户自定义文件夹）
  ///
  /// ⚠️ 注意：此方法暴露为public以供文件清理功能使用
  /// 外部调用时请注意遵循相同的扫描策略
  Future<List<String>> getCommonScanPaths() async {
    final paths = <String>[];

    try {
      // 阶段1: 添加系统预定义目录（已知的高价值路径）
      final systemPaths = await _getSystemPaths();
      paths.addAll(systemPaths);
      logger.d('System paths: ${systemPaths.length}');

      // 阶段2: 添加根目录本身（❌ 已废弃 - 会导致路径重叠）
      // 原因分析：
      // 1. 阶段1的系统目录 + 阶段3的用户文件夹已经覆盖了根目录的所有子目录
      // 2. 如果再添加根目录并递归扫描，会导致所有文件被扫描2次
      // 3. 根目录直接放置的文件场景极少，可以接受不扫描
      // 结论：删除此阶段，避免2倍重复扫描

      // 阶段3: 发现用户自定义文件夹（根目录第一层扫描）
      final discoveredPaths = await _discoverUserFolders();
      paths.addAll(discoveredPaths);
      logger.d('Discovered user folders: ${discoveredPaths.length}');
    } catch (e) {
      logger.w('Error getting common scan paths: $e');
    }

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
      for (final folderName in _androidSystemFolderNames) {
        paths.add('$_androidStorageBase/$folderName');
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
      // 确定扫描根目录
      String? rootPath;
      if (Platform.isAndroid) {
        rootPath = _androidStorageBase;
      } else if (Platform.isWindows) {
        rootPath = Platform.environment['USERPROFILE'];
      } else {
        rootPath = Platform.environment['HOME'];
      }

      if (rootPath == null || !Directory(rootPath).existsSync()) {
        logger.w('Root path not found or not exists');
        return discovered;
      }

      logger.d('Discovering user folders in: $rootPath');

      // 扫描根目录第一层（只扫描一层，不递归）
      final entities = Directory(rootPath).listSync(followLinks: false);

      for (final entity in entities) {
        if (entity is! Directory) continue;

        final folderName = path.basename(entity.path);

        // 跳过隐藏文件夹
        if (folderName.startsWith('.')) {
          continue;
        }

        // 跳过已知系统目录（避免重复）
        // 根据平台选择对应的系统目录列表
        final systemFolders = Platform.isAndroid ? _androidSystemFolderNames : _desktopSystemFolderNames;
        if (systemFolders.contains(folderName)) {
          continue;
        }

        // 跳过应用/系统数据目录
        if (excludedFolders.contains(folderName)) {
          continue;
        }

        // 跳过16进制临时文件夹（下载缓存等）
        if (_isHexTempFolder(folderName)) {
          logger.d('Skipping hex temp folder in root: $folderName');
          continue;
        }

        // 这是用户自定义文件夹，添加到列表
        discovered.add(entity.path);
        logger.d('Found user folder: ${entity.path}');
      }

      logger.i('Discovered ${discovered.length} user-defined folders');
    } catch (e) {
      logger.w('Error discovering user folders: $e');
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
                if (categoryInfo.getExtensions().contains(cleanExtension)) {
                  final fileItem = FileItem.fromEntity(entity);
                  files.add(fileItem);
                }
              }
            }
          } else if (entity is Directory) {
            // 跳过应用/系统数据目录
            if (excludedFolders.contains(name)) continue;

            // 跳过16进制命名的临时文件夹（下载缓存/应用临时文件夹）
            // 例如: 4753E391CCF6FA2, 1060A0DAF0CAB42
            if (_isHexTempFolder(name)) {
              logger.d('Skipping hex temp folder: $name');
              continue;
            }

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

  /// 加载新文件列表
  ///
  /// [isUserRefresh] - 是否为用户主动刷新（下拉刷新）
  Future<void> loadNewFiles({bool isUserRefresh = false}) async {
    logger.i('FilePresenter.loadNewFiles called (userRefresh: $isUserRefresh)');
    viewModel.setLoading(true);

    try {
      // 从FileScanConfig读取最新配置
      final fileScanConfig = AppConfig.instance.fileScan;
      final retentionDays = fileScanConfig.newFilesRetentionDays;
      final displayCount = fileScanConfig.newFilesDisplayCount;
      logger.d('FileScanConfig: retentionDays=$retentionDays, displayCount=$displayCount');

      // 先从本地缓存加载
      final cachedItems = await newFilesLocalSource.loadCachedIndex();

      // 智能扫描策略（传入最新配置）
      final scannedItems = await newFilesScanner.quickScanIfNeeded(
        cachedItems,
        retentionDays: retentionDays,
        maxResults: displayCount * 2, // 预留2倍空间用于缓存
        isUserRefresh: isUserRefresh,
      );

      // 使用扫描结果或缓存
      final newFileItems = scannedItems ?? cachedItems;
      logger.d('Got ${newFileItems.length} new file items');

      // 应用来源过滤（当前未启用）
      final filteredItems = newFileItems.toList();

      logger.d('After filtering: ${filteredItems.length} items');

      // 处理文件项（应用限制并转换为FileItem）
      final fileItems = await _processNewFileItems(filteredItems, displayCount);

      logger.i('Loaded ${fileItems.length} new files');

      // 构建source映射：path -> displayName
      final sourceMap = <String, String>{};
      for (final item in filteredItems) {
        sourceMap[item.path] = item.displayName;
      }

      // 更新视图模型（传递retentionDays设置和source映射）
      viewModel.setNewFiles(fileItems, retentionDays: retentionDays, sourceMap: sourceMap);

      // 后台异步保存到本地缓存（不阻塞UI显示）
      if (newFileItems.isNotEmpty) {
        newFilesLocalSource.saveCachedIndex(newFileItems).catchError((e) {
          logger.e('Error saving cache: $e');
          return false;
        });
      }

      // 如果使用了缓存数据，启动后台静默刷新以获取最新结果
      if (scannedItems == null && !isUserRefresh) {
        logger.d('Starting background refresh to update with latest files...');
        refreshNewFilesInBackground();
      }
    } catch (e) {
      logger.e('Error loading new files: $e');
      viewModel.setError('加载新文件失败：$e');
    } finally {
      viewModel.setLoading(false);
    }
  }

  /// 处理新文件项：应用限制并转换为FileItem
  ///
  /// **公共逻辑提取** - 被loadNewFiles和refreshNewFilesInBackground共用
  ///
  /// **处理流程**:
  /// 1. **过滤不支持的文件类型**（使用FileTypesConfig作为唯一权威）
  /// 2. 检查文件是否仍然存在（防止已删除文件）
  /// 3. 转换NewFileItem → FileItem（添加完整文件信息）
  /// 4. 应用displayCount限制（确保显示足够数量的支持文件）
  ///
  /// **重要**：先过滤类型，再应用数量限制，确保不支持的文件不占用显示配额
  ///
  /// **参数**:
  /// - [newFileItems]: 扫描得到的新文件列表（已按时间倒序）
  /// - [displayCount]: 显示数量限制
  Future<List<FileItem>> _processNewFileItems(
    List<NewFileItem> newFileItems,
    int displayCount,
  ) async {
    logger.d('Processing ${newFileItems.length} items, target display count: $displayCount');

    // 获取文件类型配置（唯一权威）
    final fileTypes = AppConfig.instance.fileTypes;

    // 先过滤类型并转换为FileItem，再应用数量限制
    final fileItems = <FileItem>[];
    int filteredCount = 0; // 统计被过滤的文件数量

    for (final newFileItem in newFileItems) {
      // 如果已经收集到足够的文件，停止处理
      if (fileItems.length >= displayCount) {
        break;
      }

      try {
        final file = File(newFileItem.path);
        if (!file.existsSync()) continue;

        // **关键过滤**: 只显示 FileTypesConfig 支持的文件类型
        // 注意：直接传入文件名，让 FileTypesConfig 内部提取扩展名
        // 排除APK文件（有单独的安装包管理模块）
        final fileName = newFileItem.path.split('/').last;
        final isSupported = fileTypes.isImageFile(fileName) ||
            fileTypes.isVideoFile(fileName) ||
            fileTypes.isAudioFile(fileName) ||
            fileTypes.isDocumentFile(fileName) ||
            fileTypes.isArchiveFile(fileName);

        if (isSupported) {
          fileItems.add(FileItem.fromEntity(file));
        } else {
          filteredCount++;
          logger.d('Filtered unsupported file type: ${newFileItem.path}');
        }
      } catch (e) {
        logger.e('Error loading file ${newFileItem.path}: $e');
      }
    }

    logger.d(
        'Processing complete: ${fileItems.length} supported files displayed, $filteredCount unsupported files filtered');
    return fileItems;
  }

  /// 后台刷新新文件列表（不阻塞UI）
  ///
  /// 静默执行扫描和更新，用户无感知
  void refreshNewFilesInBackground() {
    logger.i('FilePresenter.refreshNewFilesInBackground called');

    // 异步后台扫描，不阻塞UI（复用loadNewFiles逻辑，但不显示loading）
    Future(() async {
      try {
        // 从FileScanConfig读取最新配置
        final fileScanConfig = AppConfig.instance.fileScan;
        final retentionDays = fileScanConfig.newFilesRetentionDays;
        final displayCount = fileScanConfig.newFilesDisplayCount;

        // 使用优化的扫描方法（MediaStore + 原生）
        final newFileItems = await newFilesScanner.scanNewFiles(
          retentionDays: retentionDays,
          maxResults: displayCount * 2,
        );
        logger.d('Background scan complete: ${newFileItems.length} items');

        // 处理文件项（应用限制并转换为FileItem）
        final fileItems = await _processNewFileItems(newFileItems, displayCount);

        // 构建source映射：path -> displayName
        final sourceMap = <String, String>{};
        for (final item in newFileItems) {
          sourceMap[item.path] = item.displayName;
        }

        // 静默更新UI（不显示loading状态）
        viewModel.setNewFiles(fileItems, retentionDays: retentionDays, sourceMap: sourceMap);

        // 保存缓存
        if (newFileItems.isNotEmpty) {
          await newFilesLocalSource.saveCachedIndex(newFileItems);
        }

        logger.i('Background refresh complete: ${fileItems.length} files');
      } catch (e) {
        logger.e('Background refresh error: $e');
      }
    });
  }
}
