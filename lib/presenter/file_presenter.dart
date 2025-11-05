import 'package:easyfile/data/repositories/file_repository.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/logger.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class FilePresenter {
  final FileRepository repository;
  final FileViewModel viewModel;

  FilePresenter(this.repository, this.viewModel);

  Future<void> loadFiles(String path) async {
    logger.i('FilePresenter.loadFiles called with path: $path');
    viewModel.setLoading(true);
    logger.d('Setting current path: $path');
    viewModel.setCurrentPath(path);
    logger.d('Current path set, loading files...');
    final files = await repository.getFiles(path);
    logger.i('Files loaded: ${files.length} items');
    viewModel.setFiles(files);
    viewModel.setLoading(false);
    logger.d('ViewModel updated - currentPath: ${viewModel.currentPath}, filesCount: ${viewModel.files.length}');
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
        logger.w('Already at root directory or invalid parent path. Current: $currentPath, Parent: $parentPath');
      }
    } else {
      logger.w('Current path is empty, cannot navigate up');
    }
  }

  Future<void> searchFiles(String query) async {
    logger.i('FilePresenter.searchFiles called with query: $query');
    viewModel.setLoading(true);
    viewModel.setSearchMode(true);
    viewModel.setSearchQuery(query);
    
    final files = await repository.searchFiles(viewModel.currentPath, query);
    logger.i('Search completed: ${files.length} results found');
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

  Future<bool> copyFile(FileItem file, String destinationPath) async {
    logger.i('FilePresenter.copyFile called from ${file.path} to $destinationPath');
    final success = await repository.copyFile(file, destinationPath);
    if (success) {
      logger.i('File copied successfully, refreshing list');
      await loadFiles(viewModel.currentPath);
    } else {
      logger.w('Failed to copy file: ${file.path}');
    }
    return success;
  }

  Future<bool> moveFile(FileItem file, String destinationPath) async {
    logger.i('FilePresenter.moveFile called from ${file.path} to $destinationPath');
    final success = await repository.moveFile(file, destinationPath);
    if (success) {
      logger.i('File moved successfully, refreshing list');
      await loadFiles(viewModel.currentPath);
    } else {
      logger.w('Failed to move file: ${file.path}');
    }
    return success;
  }

  Future<bool> renameFile(FileItem file, String newName) async {
    logger.i('FilePresenter.renameFile called for ${file.path} to $newName');
    final success = await repository.renameFile(file, newName);
    if (success) {
      logger.i('File renamed successfully, refreshing list');
      await loadFiles(viewModel.currentPath);
    } else {
      logger.w('Failed to rename file: ${file.path}');
    }
    return success;
  }
}
