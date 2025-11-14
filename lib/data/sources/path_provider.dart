import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:easyfile/core/logger.dart';

class PathProviderService {
  static Future<List<String>> getAvailablePaths() async {
    logger.d('PathProviderService.getAvailablePaths() called');
    List<String> paths = [];

    if (Platform.isAndroid) {
      logger.d('Platform is Android');
      // Android 路径选项
      try {
        final externalDir = await getExternalStorageDirectory();
        logger.d('getExternalStorageDirectory(): $externalDir');
        if (externalDir != null) {
          paths.add(externalDir.path);
          logger.d('Added external dir: ${externalDir.path}');

          // 尝试获取外部存储根目录
          String rootPath = externalDir.path;
          while (rootPath.contains('/Android/')) {
            rootPath = rootPath.substring(0, rootPath.lastIndexOf('/'));
          }
          if (rootPath != externalDir.path) {
            paths.add(rootPath);
            logger.d('Added root path: $rootPath');
          }
        }
      } catch (e) {
        logger.w('Failed to get external storage: $e');
      }

      try {
        final documentsDir = await getApplicationDocumentsDirectory();
        if (!paths.contains(documentsDir.path)) {
          paths.add(documentsDir.path);
        }
      } catch (e) {
        logger.w('Failed to get documents directory: $e');
      }

      // 常见的 Android 路径
      final commonPaths = [
        '/storage/emulated/0',
        '/sdcard',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/Pictures',
      ];

      for (final path in commonPaths) {
        if (Directory(path).existsSync() && !paths.contains(path)) {
          paths.add(path);
        }
      }
    } else if (Platform.isIOS) {
      // iOS 路径选项
      try {
        final documentsDir = await getApplicationDocumentsDirectory();
        paths.add(documentsDir.path);
      } catch (e) {
        logger.w('Failed to get documents directory: $e');
      }

      try {
        final supportDir = await getApplicationSupportDirectory();
        if (!paths.contains(supportDir.path)) {
          paths.add(supportDir.path);
        }
      } catch (e) {
        logger.w('Failed to get support directory: $e');
      }
    } else {
      // 桌面平台路径选项
      try {
        final documentsDir = await getApplicationDocumentsDirectory();
        paths.add(documentsDir.path);
      } catch (e) {
        logger.w('Failed to get documents directory: $e');
      }

      // 添加用户主目录
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null && Directory(home).existsSync()) {
        paths.add(home);

        // 常见桌面文件夹
        final desktopFolders = [
          'Desktop',
          'Documents',
          'Downloads',
          'Pictures',
        ];
        for (final folder in desktopFolders) {
          final folderPath = '$home${Platform.pathSeparator}$folder';
          if (Directory(folderPath).existsSync() &&
              !paths.contains(folderPath)) {
            paths.add(folderPath);
          }
        }
      }

      // 添加当前工作目录
      if (!paths.contains(Directory.current.path)) {
        paths.add(Directory.current.path);
      }
    }

    // 移除重复路径并验证存在性
    final validPaths = <String>[];
    for (final path in paths) {
      if (!validPaths.contains(path) && Directory(path).existsSync()) {
        validPaths.add(path);
      }
    }

    return validPaths;
  }

  static Future<String> getBestDefaultPath() async {
    logger.d('PathProviderService.getBestDefaultPath() called');
    final paths = await getAvailablePaths();
    logger.d('Available paths: $paths');

    if (paths.isEmpty) {
      final fallback = Directory.current.path;
      logger.w('No paths available, using fallback: $fallback');
      return fallback;
    }

    // 优先选择用户可以看到的目录
    if (Platform.isAndroid) {
      for (final path in paths) {
        if (path.contains('/storage/emulated/0') &&
            !path.contains('/Android/')) {
          logger.d('Selected Android user path: $path');
          return path;
        }
      }
    }

    logger.d('Selected first available path: ${paths.first}');
    return paths.first;
  }
}
