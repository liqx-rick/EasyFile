import 'dart:io';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/repositories/file_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:easyfile/core/logger.dart';
import 'package:path/path.dart' as path;
import 'package:easyfile/utils/path_security.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';
import 'package:easyfile/core/services/app_trash_manager.dart';
import 'package:easyfile/core/di/locator.dart';

class LocalFileRepository implements FileRepository {
  final _displaySettings = FileDisplaySettingsService();

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

      // 获取显示设置
      final showHidden = await _displaySettings.getShowHiddenFiles();
      final showSystem = await _displaySettings.getShowSystemFiles();
      logger.d(
          'Display settings - showHidden: $showHidden, showSystem: $showSystem');

      // 尝试读取目录内容，捕获权限拒绝错误
      List<FileSystemEntity> entities;
      try {
        entities = dir.listSync().where((entity) {
          final fileName = entity.path.split(Platform.pathSeparator).last;

          // 过滤隐藏文件（以.开头）
          if (!showHidden &&
              FileDisplaySettingsService.isHiddenFile(fileName)) {
            return false;
          }

          // 过滤系统文件夹和文件
          if (!showSystem) {
            if (FileSystemEntity.isDirectorySync(entity.path)) {
              if (FileDisplaySettingsService.isSystemFolder(fileName)) {
                return false;
              }
            } else {
              if (FileDisplaySettingsService.isSystemFile(fileName)) {
                return false;
              }
            }
          }

          return true;
        }).toList();
      } catch (e) {
        // 捕获权限拒绝错误（如 Android/data 目录）
        if (e.toString().contains('Permission denied') ||
            e.toString().contains('errno = 13')) {
          logger.w('Permission denied for directory: $path');
          logger.w('This directory is protected by Android system security');
          // 返回空列表，让UI显示"此目录受系统保护"的提示
          return [];
        }
        // 其他错误继续抛出
        rethrow;
      }

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
    // 安全检查：验证路径是否允许删除
    final riskLevel = PathSecurity.getPathRiskLevel(file.path);

    // 禁止删除的路径直接拒绝
    if (riskLevel == PathRiskLevel.forbidden) {
      PathSecurity.logOperation(
        operation: 'DELETE',
        path: file.path,
        riskLevel: riskLevel,
        allowed: false,
        reason: 'Forbidden system path',
      );
      logger.e(
        'Delete operation blocked: ${file.path} is a forbidden system path',
      );
      return false;
    }

    // 危险路径也拒绝（需要在UI层有特殊确认）
    if (riskLevel == PathRiskLevel.danger) {
      PathSecurity.logOperation(
        operation: 'DELETE',
        path: file.path,
        riskLevel: riskLevel,
        allowed: false,
        reason: 'Dangerous path - requires explicit user confirmation',
      );
      logger.w('Delete operation blocked: ${file.path} is a dangerous path');
      return false;
    }

    // 记录操作日志
    PathSecurity.logOperation(
      operation: 'DELETE',
      path: file.path,
      riskLevel: riskLevel,
      allowed: true,
    );

    // 使用回收站进行软删除
    try {
      logger.i('Moving file to trash: ${file.path}');
      final trashManager = locator<AppTrashManager>();
      final success = await trashManager.moveToTrash(file);
      
      if (success) {
        logger.i('File moved to trash successfully: ${file.path}');
      } else {
        logger.w('Failed to move file to trash: ${file.path}');
      }
      return success;
    } catch (e) {
      logger.e('Error moving file to trash ${file.path}: $e');
      return false;
    }
  }

  @override
  Future<FileItem?> copyFile(FileItem file, String destinationPath) async {
    try {
      logger.i('Copying file from ${file.path} to $destinationPath');

      // 构建完整的目标路径（目录 + 文件/文件夹名）
      final fileName = path.basename(file.path);
      final sourceDir = path.dirname(file.path);

      // 检查是否复制到同一目录
      if (path.normalize(sourceDir) == path.normalize(destinationPath)) {
        logger.w('Cannot copy to same directory: $destinationPath');

        // 生成新文件名（添加副本后缀）
        final extension = path.extension(fileName);
        final nameWithoutExt = path.basenameWithoutExtension(fileName);
        String newFileName;
        String fullDestinationPath;
        int copyNumber = 1;

        // 查找可用的文件名
        do {
          if (file.isDirectory) {
            newFileName =
                '$nameWithoutExt - 副本${copyNumber > 1 ? copyNumber : ''}';
          } else {
            newFileName =
                '$nameWithoutExt - 副本${copyNumber > 1 ? copyNumber : ''}$extension';
          }
          fullDestinationPath = path.join(destinationPath, newFileName);
          copyNumber++;
        } while ((file.isDirectory
                ? Directory(fullDestinationPath)
                : File(fullDestinationPath))
            .existsSync());

        logger.i('Using new name: $newFileName');

        // 使用新文件名进行复制
        bool success;
        if (file.isDirectory) {
          success = await _copyDirectory(file.path, fullDestinationPath);
        } else {
          success = await _copyFileInternal(file.path, fullDestinationPath);
        }

        if (success) {
          final copiedEntity = file.isDirectory
              ? Directory(fullDestinationPath)
              : File(fullDestinationPath);
          final stat = await copiedEntity.stat();

          return FileItem(
            path: fullDestinationPath,
            name: newFileName,
            isDirectory: file.isDirectory,
            size: file.isDirectory ? 0 : stat.size,
            modified: stat.modified,
          );
        }
        return null;
      }

      // 正常复制到不同目录
      final fullDestinationPath = path.join(destinationPath, fileName);

      bool success;
      if (file.isDirectory) {
        success = await _copyDirectory(file.path, fullDestinationPath);
      } else {
        success = await _copyFileInternal(file.path, fullDestinationPath);
      }

      if (success) {
        // 获取复制后的文件信息
        final copiedEntity = file.isDirectory
            ? Directory(fullDestinationPath)
            : File(fullDestinationPath);
        final stat = await copiedEntity.stat();

        return FileItem(
          path: fullDestinationPath,
          name: fileName,
          isDirectory: file.isDirectory,
          size: file.isDirectory ? 0 : stat.size,
          modified: stat.modified,
        );
      }
      return null;
    } catch (e) {
      logger.e('Error copying file ${file.path}: $e');
      return null;
    }
  }

  @override
  Future<FileItem?> moveFile(FileItem file, String destinationPath) async {
    // 安全检查：验证源路径是否允许移动
    final sourceRiskLevel = PathSecurity.getPathRiskLevel(file.path);

    // 禁止移动的路径直接拒绝
    if (sourceRiskLevel == PathRiskLevel.forbidden) {
      PathSecurity.logOperation(
        operation: 'MOVE',
        path: file.path,
        riskLevel: sourceRiskLevel,
        allowed: false,
        reason: 'Forbidden system path',
      );
      logger.e(
        'Move operation blocked: ${file.path} is a forbidden system path',
      );
      return null;
    }

    // 危险路径也拒绝
    if (sourceRiskLevel == PathRiskLevel.danger) {
      PathSecurity.logOperation(
        operation: 'MOVE',
        path: file.path,
        riskLevel: sourceRiskLevel,
        allowed: false,
        reason: 'Dangerous path',
      );
      logger.w('Move operation blocked: ${file.path} is a dangerous path');
      return null;
    }

    // 验证目标路径的安全性
    final targetRiskLevel = PathSecurity.getPathRiskLevel(destinationPath);
    if (targetRiskLevel == PathRiskLevel.forbidden ||
        targetRiskLevel == PathRiskLevel.danger) {
      PathSecurity.logOperation(
        operation: 'MOVE',
        path: '${file.path} -> $destinationPath',
        riskLevel: targetRiskLevel,
        allowed: false,
        reason: 'Target path is protected',
      );
      logger.w(
        'Move operation blocked: target path $destinationPath is protected',
      );
      return null;
    }

    // 检查是否为系统关键文件夹
    final currentName = file.path.split(Platform.pathSeparator).last;
    if (PathSecurity.isSystemFolderName(currentName)) {
      PathSecurity.logOperation(
        operation: 'MOVE',
        path: file.path,
        riskLevel: sourceRiskLevel,
        allowed: false,
        reason: 'System critical folder',
      );
      logger.w('Move operation blocked: "$currentName" is a system folder');
      return null;
    }

    try {
      logger.i('Moving file from ${file.path} to $destinationPath');

      // 构建完整的目标路径（目录 + 文件名）
      final fileName = path.basename(file.path);
      final fullDestinationPath = path.join(destinationPath, fileName);

      // 记录操作日志
      PathSecurity.logOperation(
        operation: 'MOVE',
        path: '${file.path} -> $fullDestinationPath',
        riskLevel: sourceRiskLevel,
        allowed: true,
      );

      final source = file.isDirectory ? Directory(file.path) : File(file.path);
      await source.rename(fullDestinationPath);

      logger.i('File moved successfully: ${file.path} -> $fullDestinationPath');

      // 返回更新后的 FileItem
      return FileItem(
        path: fullDestinationPath,
        name: fileName,
        isDirectory: file.isDirectory,
        size: file.size,
        modified: file.modified,
      );
    } catch (e) {
      logger.e('Error moving file ${file.path}: $e');
      // 如果重命名失败，尝试复制然后删除
      try {
        final copiedFile = await copyFile(file, destinationPath);
        if (copiedFile != null) {
          await deleteFile(file);

          logger.i(
            'File moved using copy+delete: ${file.path} -> ${copiedFile.path}',
          );

          // 返回复制的文件信息
          return copiedFile;
        }
      } catch (e2) {
        logger.e('Error in fallback move operation: $e2');
      }
      return null;
    }
  }

  @override
  Future<FileItem?> renameFile(FileItem file, String newName) async {
    // 安全检查：验证源路径是否允许重命名
    final sourceRiskLevel = PathSecurity.getPathRiskLevel(file.path);

    // 禁止重命名的路径直接拒绝
    if (sourceRiskLevel == PathRiskLevel.forbidden) {
      PathSecurity.logOperation(
        operation: 'RENAME',
        path: file.path,
        riskLevel: sourceRiskLevel,
        allowed: false,
        reason: 'Forbidden system path',
      );
      logger.e(
        'Rename operation blocked: ${file.path} is a forbidden system path',
      );
      return null;
    }

    // 危险路径也拒绝
    if (sourceRiskLevel == PathRiskLevel.danger) {
      PathSecurity.logOperation(
        operation: 'RENAME',
        path: file.path,
        riskLevel: sourceRiskLevel,
        allowed: false,
        reason: 'Dangerous path',
      );
      logger.w('Rename operation blocked: ${file.path} is a dangerous path');
      return null;
    }

    // 检查是否为系统关键文件夹名称
    final currentName = file.path.split(Platform.pathSeparator).last;
    if (PathSecurity.isSystemFolderName(currentName)) {
      PathSecurity.logOperation(
        operation: 'RENAME',
        path: file.path,
        riskLevel: sourceRiskLevel,
        allowed: false,
        reason: 'System critical folder name',
      );
      logger.w('Rename operation blocked: "$currentName" is a system folder');
      return null;
    }

    try {
      logger.i('Renaming file ${file.path} to $newName');

      final parentDir = Directory(file.path).parent.path;
      // 使用 path.join 保证跨平台路径正确
      final newPath = path.join(parentDir, newName);

      // 验证目标路径的安全性
      final targetRiskLevel = PathSecurity.getPathRiskLevel(newPath);
      if (targetRiskLevel == PathRiskLevel.forbidden ||
          targetRiskLevel == PathRiskLevel.danger) {
        PathSecurity.logOperation(
          operation: 'RENAME',
          path: '${file.path} -> $newPath',
          riskLevel: targetRiskLevel,
          allowed: false,
          reason: 'Target path is protected',
        );
        logger.w('Rename operation blocked: target path $newPath is protected');
        return null;
      }

      // 记录操作日志
      PathSecurity.logOperation(
        operation: 'RENAME',
        path: '${file.path} -> $newPath',
        riskLevel: sourceRiskLevel,
        allowed: true,
      );

      final source = file.isDirectory ? Directory(file.path) : File(file.path);
      await source.rename(newPath);

      logger.i('File renamed successfully: ${file.path} -> $newPath');

      // Return updated FileItem with new path and name
      return FileItem(
        path: newPath,
        name: newName,
        isDirectory: file.isDirectory,
        size: file.size,
        modified: file.modified,
      );
    } catch (e) {
      logger.e('Error renaming file ${file.path}: $e');
      return null;
    }
  }

  /// 复制文件的内部实现
  Future<bool> _copyFileInternal(
    String sourcePath,
    String destinationPath,
  ) async {
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
        'LocalFileRepository.searchFiles called with path: $path, query: $query',
      );

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
      final allEntities = await _getAllEntitiesRecursive(
        dir,
        maxDepth: 3,
      ); // 限制搜索深度

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
  Future<List<FileSystemEntity>> _getAllEntitiesRecursive(
    Directory dir, {
    int maxDepth = 3,
    int currentDepth = 0,
  }) async {
    final List<FileSystemEntity> allEntities = [];

    if (currentDepth >= maxDepth) {
      return allEntities;
    }

    try {
      final entities = dir
          .listSync()
          .where(
            (entity) =>
                !entity.path.split(Platform.pathSeparator).last.startsWith('.'),
          )
          .toList();

      for (final entity in entities) {
        allEntities.add(entity);

        // 如果是目录，递归搜索
        if (entity is Directory) {
          try {
            final subEntities = await _getAllEntitiesRecursive(
              entity,
              maxDepth: maxDepth,
              currentDepth: currentDepth + 1,
            );
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
