import 'dart:io';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/repositories/file_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:easyfile/core/logger.dart';

class LocalFileRepository implements FileRepository {
  @override
  Future<List<FileItem>> getFiles(String path) async {
    try {
      logger.i('LocalFileRepository.getFiles called with path: $path');

      // 请求存储权限
      if (!await _requestStoragePermission()) {
        logger.w('Storage permission denied');
        return [];
      }

      final dir = Directory(path);
      if (!dir.existsSync()) {
        logger.w('Directory does not exist: $path');
        // 如果路径不存在，使用应用文档目录
        final documentsDir = await getApplicationDocumentsDirectory();
        logger.d('Fallback to documents directory: ${documentsDir.path}');
        return await getFiles(documentsDir.path);
      }

      logger.d('Reading directory contents...');
      final entities = dir
          .listSync()
          .where((entity) =>
              !entity.path.split(Platform.pathSeparator).last.startsWith('.'))
          .toList();

      logger.d('Found ${entities.length} entities');
      final files = entities.map((e) => FileItem.fromEntity(e)).toList();

      // 按类型排序：文件夹在前，文件在后，然后按名称排序
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      logger.d('Returning ${files.length} files/folders');
      for (final file in files.take(5)) {
        logger.d('  - ${file.isDirectory ? "DIR" : "FILE"}: ${file.name}');
      }

      return files;
    } catch (e) {
      logger.e('Error loading files: $e');
      return [];
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (status.isDenied) {
        final manageStatus = await Permission.manageExternalStorage.request();
        return manageStatus.isGranted;
      }
      return status.isGranted;
    }
    return true; // iOS 和其他平台不需要特殊权限
  }

  @override
  Future<bool> deleteFile(FileItem file) async {
    final entity = FileSystemEntity.typeSync(file.path);
    try {
      logger.i('Deleting file: ${file.path}');
      if (entity == FileSystemEntityType.directory) {
        await Directory(file.path).delete(recursive: true);
      } else {
        await File(file.path).delete();
      }
      logger.i('File deleted successfully: ${file.path}');
      return true;
    } catch (e) {
      logger.e('Error deleting file ${file.path}: $e');
      return false;
    }
  }

  @override
  Future<bool> copyFile(FileItem file, String destinationPath) async {
    try {
      logger.i('Copying file from ${file.path} to $destinationPath');

      if (file.isDirectory) {
        return await _copyDirectory(file.path, destinationPath);
      } else {
        return await _copyFileInternal(file.path, destinationPath);
      }
    } catch (e) {
      logger.e('Error copying file ${file.path}: $e');
      return false;
    }
  }

  @override
  Future<bool> moveFile(FileItem file, String destinationPath) async {
    try {
      logger.i('Moving file from ${file.path} to $destinationPath');

      final source = file.isDirectory ? Directory(file.path) : File(file.path);
      await source.rename(destinationPath);

      logger.i('File moved successfully: ${file.path} -> $destinationPath');
      return true;
    } catch (e) {
      logger.e('Error moving file ${file.path}: $e');
      // 如果重命名失败，尝试复制然后删除
      try {
        if (await copyFile(file, destinationPath)) {
          await deleteFile(file);
          logger.i(
              'File moved using copy+delete: ${file.path} -> $destinationPath');
          return true;
        }
      } catch (e2) {
        logger.e('Error in fallback move operation: $e2');
      }
      return false;
    }
  }

  @override
  Future<bool> renameFile(FileItem file, String newName) async {
    try {
      logger.i('Renaming file ${file.path} to $newName');

      final parentDir = Directory(file.path).parent.path;
      final newPath = '$parentDir${Platform.pathSeparator}$newName';

      final source = file.isDirectory ? Directory(file.path) : File(file.path);
      await source.rename(newPath);

      logger.i('File renamed successfully: ${file.path} -> $newPath');
      return true;
    } catch (e) {
      logger.e('Error renaming file ${file.path}: $e');
      return false;
    }
  }

  /// 复制文件的内部实现
  Future<bool> _copyFileInternal(
      String sourcePath, String destinationPath) async {
    try {
      final sourceFile = File(sourcePath);
      final destinationFile = File(destinationPath);

      // 确保目标目录存在
      await destinationFile.parent.create(recursive: true);

      await sourceFile.copy(destinationPath);
      logger.d('File copied: $sourcePath -> $destinationPath');
      return true;
    } catch (e) {
      logger.e('Error copying file $sourcePath: $e');
      return false;
    }
  }

  /// 复制目录的递归实现
  Future<bool> _copyDirectory(String sourcePath, String destinationPath) async {
    try {
      final sourceDir = Directory(sourcePath);
      final destinationDir = Directory(destinationPath);

      // 创建目标目录
      await destinationDir.create(recursive: true);

      // 递归复制所有内容
      await for (final entity in sourceDir.list(recursive: false)) {
        final fileName = entity.path.split(Platform.pathSeparator).last;
        final newPath = '$destinationPath${Platform.pathSeparator}$fileName';

        if (entity is Directory) {
          await _copyDirectory(entity.path, newPath);
        } else if (entity is File) {
          await _copyFileInternal(entity.path, newPath);
        }
      }

      logger.d('Directory copied: $sourcePath -> $destinationPath');
      return true;
    } catch (e) {
      logger.e('Error copying directory $sourcePath: $e');
      return false;
    }
  }

  @override
  Future<List<FileItem>> searchFiles(String path, String query) async {
    try {
      logger.i(
          'LocalFileRepository.searchFiles called with path: $path, query: $query');

      if (query.isEmpty) {
        logger.d('Empty query, returning all files');
        return await getFiles(path);
      }

      // 请求存储权限
      if (!await _requestStoragePermission()) {
        logger.w('Storage permission denied');
        return [];
      }

      final dir = Directory(path);
      if (!dir.existsSync()) {
        logger.w('Directory does not exist: $path');
        return [];
      }

      logger.d('Searching for files matching: $query');
      final allEntities =
          await _getAllEntitiesRecursive(dir, maxDepth: 3); // 限制搜索深度

      final queryLower = query.toLowerCase();
      final matchingEntities = allEntities.where((entity) {
        final fileName =
            entity.path.split(Platform.pathSeparator).last.toLowerCase();
        final fileExtension =
            fileName.contains('.') ? fileName.split('.').last : '';

        // 搜索文件名或扩展名
        return fileName.contains(queryLower) ||
            fileExtension.contains(queryLower);
      }).toList();

      logger.d('Found ${matchingEntities.length} matching entities');
      final files =
          matchingEntities.map((e) => FileItem.fromEntity(e)).toList();

      // 按类型排序：文件夹在前，文件在后，然后按名称排序
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      logger.d('Returning ${files.length} search results');
      return files;
    } catch (e) {
      logger.e('Error searching files: $e');
      return [];
    }
  }

  /// 递归获取目录下所有文件和文件夹
  Future<List<FileSystemEntity>> _getAllEntitiesRecursive(Directory dir,
      {int maxDepth = 3, int currentDepth = 0}) async {
    final List<FileSystemEntity> allEntities = [];

    if (currentDepth >= maxDepth) {
      return allEntities;
    }

    try {
      final entities = dir
          .listSync()
          .where((entity) =>
              !entity.path.split(Platform.pathSeparator).last.startsWith('.'))
          .toList();

      for (final entity in entities) {
        allEntities.add(entity);

        // 如果是目录，递归搜索
        if (entity is Directory) {
          try {
            final subEntities = await _getAllEntitiesRecursive(entity,
                maxDepth: maxDepth, currentDepth: currentDepth + 1);
            allEntities.addAll(subEntities);
          } catch (e) {
            logger.w('Error accessing subdirectory ${entity.path}: $e');
          }
        }
      }
    } catch (e) {
      logger.w('Error listing directory ${dir.path}: $e');
    }

    return allEntities;
  }
}
